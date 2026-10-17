BeforeAll {
    $script:moduleName = 'PSHeic'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-PSHeicRuntimeIdentifier' {
    Context 'When the platform is given explicitly' {
        It 'Should return <Expected> for <Platform> <Architecture> (musl: <IsMusl>)' -ForEach @(
            @{ Platform = 'Windows'; Architecture = 'X64'; IsMusl = $false; Expected = 'win-x64' }
            @{ Platform = 'Windows'; Architecture = 'Arm64'; IsMusl = $false; Expected = 'win-arm64' }
            @{ Platform = 'Linux'; Architecture = 'X64'; IsMusl = $false; Expected = 'linux-x64' }
            @{ Platform = 'Linux'; Architecture = 'Arm64'; IsMusl = $false; Expected = 'linux-arm64' }
            @{ Platform = 'Linux'; Architecture = 'X64'; IsMusl = $true; Expected = 'linux-musl-x64' }
            @{ Platform = 'OSX'; Architecture = 'X64'; IsMusl = $false; Expected = 'osx-x64' }
            @{ Platform = 'OSX'; Architecture = 'Arm64'; IsMusl = $false; Expected = 'osx-arm64' }
        ) {
            $result = InModuleScope -ModuleName $script:moduleName -Parameters $_ {
                Get-PSHeicRuntimeIdentifier -Platform $Platform -Architecture $Architecture -IsMusl:$IsMusl
            }

            $result | Should -Be $Expected
        }

        It 'Should throw for 32-bit processes' {
            {
                InModuleScope -ModuleName $script:moduleName {
                    Get-PSHeicRuntimeIdentifier -Platform Windows -Architecture X86
                }
            } | Should -Throw -ExpectedMessage '*32-bit*'
        }

        It 'Should throw for musl on arm64' {
            {
                InModuleScope -ModuleName $script:moduleName {
                    Get-PSHeicRuntimeIdentifier -Platform Linux -Architecture Arm64 -IsMusl
                }
            } | Should -Throw -ExpectedMessage '*linux-musl-arm64*'
        }
    }

    Context 'When called without parameters' {
        It 'Should return the identifier of the current session' {
            $result = InModuleScope -ModuleName $script:moduleName {
                Get-PSHeicRuntimeIdentifier
            }

            $result | Should -Match '^(win|linux|linux-musl|osx)-(x64|arm64)$'
        }
    }
}
