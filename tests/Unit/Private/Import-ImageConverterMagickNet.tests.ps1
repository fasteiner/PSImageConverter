BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Import-ImageConverterMagickNet' {
    Context 'When the lib folder contains the native library for this platform' {
        It 'Should load Magick.NET and register the native resolver' {
            $libraryPath = Join-Path -Path (Get-Module -Name $script:moduleName).ModuleBase -ChildPath 'lib'

            {
                InModuleScope -ModuleName $script:moduleName -Parameters @{ LibraryPath = $libraryPath } {
                    Import-ImageConverterMagickNet -LibraryPath $LibraryPath
                }
            } | Should -Not -Throw

            [PSImageConverter.NativeResolver]::IsRegistered | Should -BeTrue
            [ImageMagick.MagickNET]::Version | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When the native library for this platform is missing' {
        It 'Should throw an error that names the missing folder' {
            {
                InModuleScope -ModuleName $script:moduleName -Parameters @{ LibraryPath = $TestDrive } {
                    Import-ImageConverterMagickNet -LibraryPath $LibraryPath
                }
            } | Should -Throw -ExpectedMessage '*was not found*'
        }
    }
}
