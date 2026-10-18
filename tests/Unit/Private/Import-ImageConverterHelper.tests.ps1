BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:libraryPath = Join-Path -Path (Get-Module -Name $script:moduleName).ModuleBase -ChildPath 'lib'
    $script:helperPath = Join-Path -Path $script:libraryPath -ChildPath 'PSImageConverter.Helper.dll'

    function Invoke-ImportHelper
    {
        param ([System.String] $LibraryPath)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ LibraryPath = $LibraryPath } {
            $helperWarnings = $null
            Import-ImageConverterHelper -LibraryPath $LibraryPath -WarningVariable helperWarnings -WarningAction SilentlyContinue
            @($helperWarnings)
        }
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Import-ImageConverterHelper' {
    Context 'When the module has been imported' {
        It 'Should have loaded the helper assembly from the lib folder of the module' {
            $assembly = [PSImageConverter.SafeInvoker].Assembly

            $assembly.GetName().Name | Should -Be 'PSImageConverter.Helper'
            $assembly.Location | Should -Be $script:helperPath
            [PSImageConverter.NativeResolver].Assembly | Should -Be $assembly
            [PSImageConverter.FileIdentity].Assembly | Should -Be $assembly
        }

        It 'Should target .NET 8, the runtime of PowerShell 7.4' {
            $attribute = [PSImageConverter.SafeInvoker].Assembly.GetCustomAttributes([System.Runtime.Versioning.TargetFrameworkAttribute], $false)

            $attribute.FrameworkName | Should -Be '.NETCoreApp,Version=v8.0'
        }

        It 'Should reference only assemblies of the .NET runtime' {
            # A package reference would need its DLL in the module; System.Management.Automation is a package outside PowerShell.
            $references = [PSImageConverter.SafeInvoker].Assembly.GetReferencedAssemblies().Name

            $references | Should -Not -Contain 'System.Management.Automation'
            $references | Where-Object -FilterScript { $_ -notmatch '^(System|Microsoft\.Win32)(\.|$)' } | Should -BeNullOrEmpty
        }

        It 'Should ship the assembly without pdb, deps.json or XML documentation' {
            (Get-ChildItem -LiteralPath $script:libraryPath -Filter 'PSImageConverter.Helper*').Name | Should -Be 'PSImageConverter.Helper.dll'
        }
    }

    Context 'When the helper assembly is already loaded' {
        It 'Should use the loaded assembly for the same build without a warning' {
            $warnings = Invoke-ImportHelper -LibraryPath $script:libraryPath

            $warnings | Should -BeNullOrEmpty
            [PSImageConverter.SafeInvoker].Assembly.Location | Should -Be $script:helperPath
        }

        It 'Should use the loaded assembly for the same build in another folder' {
            $copyFolder = New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath 'same-build')
            Copy-Item -LiteralPath $script:helperPath -Destination $copyFolder.FullName

            $warnings = Invoke-ImportHelper -LibraryPath $copyFolder.FullName

            $warnings | Should -BeNullOrEmpty
            [PSImageConverter.SafeInvoker].Assembly.Location | Should -Be $script:helperPath
        }

        It 'Should keep the loaded assembly and warn when the file is another build' {
            # Another module version id (MVID) makes the copy another build to .NET, which refuses to load it next to the loaded one.
            $otherFolder = New-Item -ItemType Directory -Path (Join-Path -Path $TestDrive -ChildPath 'other-build')
            $otherPath = Join-Path -Path $otherFolder.FullName -ChildPath 'PSImageConverter.Helper.dll'
            $bytes = [System.IO.File]::ReadAllBytes($script:helperPath)
            $hex = [System.Convert]::ToHexString($bytes)
            $mvidHex = [System.Convert]::ToHexString([PSImageConverter.SafeInvoker].Module.ModuleVersionId.ToByteArray())
            $position = $hex.IndexOf($mvidHex, [System.StringComparison]::Ordinal)
            while ($position -gt 0 -and $position % 2 -ne 0)
            {
                $position = $hex.IndexOf($mvidHex, $position + 1, [System.StringComparison]::Ordinal)
            }
            $position | Should -BeGreaterThan 0 -Because 'the file holds the MVID of the loaded assembly'
            [System.Array]::Copy([System.Guid]::NewGuid().ToByteArray(), 0, $bytes, $position / 2, 16)
            [System.IO.File]::WriteAllBytes($otherPath, $bytes)

            $warnings = Invoke-ImportHelper -LibraryPath $otherFolder.FullName

            $warnings | Should -HaveCount 1
            "$($warnings[0])" | Should -Be ("Another build of PSImageConverter.Helper.dll is already loaded in this process ('{0}'); it is used instead of '{1}'. Commands of this module may fail. Start a new PowerShell session to use this version of the module." -f $script:helperPath, $otherPath)
            [PSImageConverter.SafeInvoker].Assembly.Location | Should -Be $script:helperPath
        }
    }
}
