BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:manifestPath = Join-Path -Path (Get-Module -Name $script:moduleName).ModuleBase -ChildPath "$($script:moduleName).psd1"
    $script:fixture = Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic'
    $script:libraryPath = Join-Path -Path (Get-Module -Name $script:moduleName).ModuleBase -ChildPath 'lib'
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Initialize-ImageConverterAssembly' {
    It 'Should have loaded the helper assembly and registered its resolver when the module was imported' {
        [PSImageConverter.NativeResolver]::IsRegistered | Should -BeTrue
    }

    It 'Should have loaded Magick.NET when the module was imported' {
        'ImageMagick.MagickImage' -as [System.Type] | Should -Not -BeNullOrEmpty
    }

    It 'Should be able to call into the native library' {
        [ImageMagick.MagickNET]::Version | Should -Not -BeNullOrEmpty
    }

    It 'Should report HEIC read support' {
        $heic = [ImageMagick.MagickNET]::SupportedFormats | Where-Object -FilterScript { $_.Format -eq 'Heic' }

        $heic.SupportsReading | Should -BeTrue
    }

    It 'Should load the assemblies when several runspaces import the module at the same time' {
        # A fresh process, because the module is already initialized in this one.
        $output = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command {
            param ($ManifestPath, $Fixture, $OutputPath)

            $jobs = 1..6 | ForEach-Object -Process {
                Start-ThreadJob -ArgumentList $ManifestPath, $Fixture, (Join-Path -Path $OutputPath -ChildPath "job$_") -ScriptBlock {
                    param ($ManifestPath, $Fixture, $Destination)

                    Import-Module -Name $ManifestPath
                    (Get-ImageInfo -Path $Fixture -ErrorAction Stop).Width
                    # A conversion uses the SafeInvoker and, on Windows, the FileIdentity class of the helper assembly.
                    'png: {0}' -f (ConvertTo-Png -LiteralPath $Fixture -DestinationPath $Destination -ErrorAction Stop).Name
                }
            }

            $jobs | Receive-Job -Wait -AutoRemoveJob

            # A failed native load is cached for the lifetime of the process, so a later call shows it.
            Import-Module -Name $ManifestPath
            'after: {0}' -f (Get-ImageInfo -Path $Fixture -ErrorAction Stop).Width
        } -args $script:manifestPath, $script:fixture, $TestDrive 2>&1

        <#
            Parallel Import-Module calls can also fail inside PowerShell itself ("An item with the same key has
            already been added", a non-thread-safe engine cache filled while the module is parsed). That is not
            what this test is about, so only errors from loading the helper assembly and Magick.Native count.
        #>
        $loadErrors = $output | Where-Object -FilterScript {
            $_ -is [System.Management.Automation.ErrorRecord] -and "$_" -match 'NativeMagickSettings|Magick\.Native|DllNotFound|PSImageConverter\.|same name is already loaded'
        }

        $loadErrors | Should -BeNullOrEmpty
        $output | Should -Contain 64
        $output | Should -Contain 'png: sample.png'
        $output | Should -Contain 'after: 64'
    }

    It 'Should reuse the loaded assemblies when the module is imported again, after Remove-Module and from another folder' {
        # The copy needs no native library: Magick.NET is initialized by the first import of the process.
        $moduleBase = Split-Path -Path $script:manifestPath -Parent
        $copyBase = Join-Path -Path (Join-Path -Path $TestDrive -ChildPath 'copy') -ChildPath $script:moduleName
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $copyBase -ChildPath 'lib') -Force
        Copy-Item -Path (Join-Path -Path $moduleBase -ChildPath "$($script:moduleName).ps*1") -Destination $copyBase
        Copy-Item -Path (Join-Path -Path $moduleBase -ChildPath 'lib/*.dll') -Destination (Join-Path -Path $copyBase -ChildPath 'lib')

        $output = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command {
            param ($ManifestPath, $CopyPath, $Fixture, $OutputPath)

            # -WarningVariable of Import-Module does not collect warnings the module writes while it loads; stream 3 does.
            $importWarnings = @()

            foreach ($step in @('first', 'force', 'reimport', 'copy'))
            {
                switch ($step)
                {
                    'first'
                    {
                        $importWarnings += @(Import-Module -Name $ManifestPath 3>&1)
                    }

                    'force'
                    {
                        $importWarnings += @(Import-Module -Name $ManifestPath -Force 3>&1)
                    }

                    'reimport'
                    {
                        Remove-Module -Name 'PSImageConverter'
                        $importWarnings += @(Import-Module -Name $ManifestPath 3>&1)
                    }

                    'copy'
                    {
                        Remove-Module -Name 'PSImageConverter'
                        $importWarnings += @(Import-Module -Name $CopyPath 3>&1)
                    }
                }

                $destination = Join-Path -Path $OutputPath -ChildPath $step
                '{0}: {1} {2}' -f $step, (ConvertTo-Png -LiteralPath $Fixture -DestinationPath $destination -ErrorAction Stop).Name, (Get-Module -Name 'PSImageConverter').ModuleBase
            }

            'warnings: {0}' -f $importWarnings.Count
            'helper: {0}' -f [PSImageConverter.SafeInvoker].Assembly.Location
        } -args $script:manifestPath, (Join-Path -Path $copyBase -ChildPath "$($script:moduleName).psd1"), $script:fixture, $TestDrive 2>&1

        $output | Where-Object -FilterScript { $_ -is [System.Management.Automation.ErrorRecord] } | Should -BeNullOrEmpty
        $moduleBase = Split-Path -Path $script:manifestPath -Parent
        $output | Should -Be @(
            "first: sample.png $moduleBase"
            "force: sample.png $moduleBase"
            "reimport: sample.png $moduleBase"
            "copy: sample.png $copyBase"
            'warnings: 0'
            "helper: $(Join-Path -Path (Join-Path -Path $moduleBase -ChildPath 'lib') -ChildPath 'PSImageConverter.Helper.dll')"
        )
    }

    It 'Should not throw or warn when the assemblies are already loaded' {
        $initializeWarnings = InModuleScope -ModuleName $script:moduleName -Parameters @{ LibraryPath = $script:libraryPath } {
            $initializeWarnings = $null
            Initialize-ImageConverterAssembly -LibraryPath $LibraryPath -WarningVariable initializeWarnings -WarningAction SilentlyContinue
            @($initializeWarnings)
        }

        $initializeWarnings | Should -BeNullOrEmpty
    }
}
