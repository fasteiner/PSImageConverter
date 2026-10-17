BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterPathComparer' {
    It 'Should compare paths case-insensitively on <Platform>' -ForEach @(
        @{ Platform = 'Windows' }
        @{ Platform = 'OSX' }
    ) {
        $comparer = InModuleScope -ModuleName $script:moduleName -Parameters @{ Platform = $Platform } {
            Get-ImageConverterPathComparer -Platform $Platform
        }

        $comparer.Equals('C:\Pictures\a.JPG', 'c:\pictures\a.jpg') | Should -BeTrue
    }

    It 'Should compare paths case-sensitively on Linux' {
        $comparer = InModuleScope -ModuleName $script:moduleName {
            Get-ImageConverterPathComparer -Platform 'Linux'
        }

        $comparer.Equals('/home/a.JPG', '/home/a.jpg') | Should -BeFalse
        $comparer.Equals('/home/a.jpg', '/home/a.jpg') | Should -BeTrue
    }

    It 'Should use the platform of the current session by default' {
        $comparer = InModuleScope -ModuleName $script:moduleName {
            Get-ImageConverterPathComparer
        }

        $comparer.Equals('a.JPG', 'a.jpg') | Should -Be (-not $IsLinux)
    }
}
