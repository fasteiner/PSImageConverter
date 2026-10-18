BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterForwardedParameter' {
    It 'Should keep the conversion and common parameters, set -Format and drop the variable and buffer parameters' {
        $bound = @{
            LiteralPath         = 'a.heic'
            Quality             = 80
            Force               = [System.Management.Automation.SwitchParameter]::Present
            WhatIf              = [System.Management.Automation.SwitchParameter]::Present
            ErrorAction         = 'Stop'
            Verbose             = [System.Management.Automation.SwitchParameter]::Present
            ErrorVariable       = '+errors'
            WarningVariable     = 'warnings'
            InformationVariable = 'information'
            OutVariable         = 'output'
            PipelineVariable    = 'current'
            OutBuffer           = 10
        }

        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Bound = $bound } {
            Get-ImageConverterForwardedParameter -BoundParameter $Bound -Format 'Jpeg'
        }

        $result.Keys | Sort-Object | Should -Be @('ErrorAction', 'Force', 'Format', 'LiteralPath', 'Quality', 'Verbose', 'WhatIf')
        $result['Format'] | Should -Be 'Jpeg'
        $result['Quality'] | Should -Be 80
        $bound.Keys | Should -Contain 'ErrorVariable'
    }

    It 'Should drop the parameters the caller handles itself' {
        $result = InModuleScope -ModuleName $script:moduleName {
            Get-ImageConverterForwardedParameter -BoundParameter @{ Path = '*.heic'; Format = 'Png' } -Format 'Png' -ExcludeParameter 'Path', 'LiteralPath'
        }

        $result.Keys | Should -Be @('Format')
    }

    It 'Should accept a call without bound parameters' {
        $result = InModuleScope -ModuleName $script:moduleName {
            Get-ImageConverterForwardedParameter -BoundParameter @{} -Format 'WebP'
        }

        $result['Format'] | Should -Be 'WebP'
    }
}
