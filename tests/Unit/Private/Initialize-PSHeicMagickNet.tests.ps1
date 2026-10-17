BeforeAll {
    $script:moduleName = 'PSHeic'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Initialize-PSHeicMagickNet' {
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

    It 'Should not throw when Magick.NET is already loaded' {
        {
            InModuleScope -ModuleName $script:moduleName {
                Initialize-PSHeicMagickNet -LibraryPath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
            }
        } | Should -Not -Throw
    }
}
