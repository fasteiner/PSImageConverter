BeforeAll {
    $script:moduleName = 'PSHeic'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'ConvertFrom-PSHeicExifProfile' {
    It 'Should return an empty hashtable for a missing profile' {
        $result = InModuleScope -ModuleName $script:moduleName {
            ConvertFrom-PSHeicExifProfile -ExifProfile $null
        }

        $result | Should -BeOfType [System.Collections.Hashtable]
        $result.Count | Should -Be 0
    }

    It 'Should map tag names to values and trim strings' {
        $values = @(
            [PSCustomObject] @{ Tag = 'Make' } | Add-Member -MemberType ScriptMethod -Name GetValue -Value { "Apple`0" } -PassThru
            [PSCustomObject] @{ Tag = 'Model' } | Add-Member -MemberType ScriptMethod -Name GetValue -Value { ' iPhone 15 Pro ' } -PassThru
            [PSCustomObject] @{ Tag = 'ImageWidth' } | Add-Member -MemberType ScriptMethod -Name GetValue -Value { [System.UInt32] 4032 } -PassThru
        )
        $exifProfile = [PSCustomObject] @{ Values = $values }

        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ ExifProfile = $exifProfile } {
            ConvertFrom-PSHeicExifProfile -ExifProfile $ExifProfile
        }

        $result['Make'] | Should -Be 'Apple'
        $result['Model'] | Should -Be 'iPhone 15 Pro'
        $result['ImageWidth'] | Should -Be 4032
    }
}
