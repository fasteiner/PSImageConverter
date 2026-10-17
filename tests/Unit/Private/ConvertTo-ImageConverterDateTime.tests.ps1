BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'ConvertTo-ImageConverterDateTime' {
    It 'Should parse an EXIF date string' {
        $result = InModuleScope -ModuleName $script:moduleName {
            ConvertTo-ImageConverterDateTime -Value '2026:10:17 18:21:05'
        }

        $result | Should -Be ([System.DateTime]::new(2026, 10, 17, 18, 21, 5))
    }

    It 'Should return null for <Name>' -ForEach @(
        @{ Name = 'null'; Value = $null }
        @{ Name = 'an empty string'; Value = '' }
        @{ Name = 'whitespace'; Value = '   ' }
        @{ Name = 'a malformed date'; Value = '0000:00:00 00:00:00' }
        @{ Name = 'an ISO date'; Value = '2026-10-17T18:21:05' }
    ) {
        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Value = $Value } {
            ConvertTo-ImageConverterDateTime -Value $Value
        }

        $result | Should -BeNullOrEmpty
    }
}
