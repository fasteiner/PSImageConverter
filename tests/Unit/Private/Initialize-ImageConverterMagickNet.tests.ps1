BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Initialize-ImageConverterMagickNet' {
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

    It 'Should load the native library when several runspaces import the module at the same time' {
        $manifestPath = Join-Path -Path (Get-Module -Name $script:moduleName).ModuleBase -ChildPath "$($script:moduleName).psd1"
        $fixture = Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic'

        # A fresh process, because the module is already initialized in this one.
        $output = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command {
            param ($ManifestPath, $Fixture)

            $jobs = 1..6 | ForEach-Object -Process {
                Start-ThreadJob -ArgumentList $ManifestPath, $Fixture -ScriptBlock {
                    param ($ManifestPath, $Fixture)

                    Import-Module -Name $ManifestPath
                    (Get-ImageInfo -Path $Fixture -ErrorAction Stop).Width
                }
            }

            $jobs | Receive-Job -Wait -AutoRemoveJob

            # A failed native load is cached for the lifetime of the process, so a later call shows it.
            Import-Module -Name $ManifestPath
            'after: {0}' -f (Get-ImageInfo -Path $Fixture -ErrorAction Stop).Width
        } -args $manifestPath, $fixture 2>&1

        <#
            Parallel Import-Module calls can also fail inside PowerShell itself ("An item with the same key has
            already been added", a non-thread-safe engine cache filled while the module is parsed). That is not
            what this test is about, so only errors from loading Magick.Native count.
        #>
        $nativeErrors = $output | Where-Object -FilterScript {
            $_ -is [System.Management.Automation.ErrorRecord] -and "$_" -match 'NativeMagickSettings|Magick\.Native|DllNotFound'
        }

        $nativeErrors | Should -BeNullOrEmpty
        $output | Should -Contain 64
        $output | Should -Contain 'after: 64'
    }

    It 'Should not throw when Magick.NET is already loaded' {
        {
            InModuleScope -ModuleName $script:moduleName {
                Initialize-ImageConverterMagickNet -LibraryPath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
            }
        } | Should -Not -Throw
    }
}
