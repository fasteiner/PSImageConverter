BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterRuntimeIdentifier' {
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
                Get-ImageConverterRuntimeIdentifier -Platform $Platform -Architecture $Architecture -IsMusl:$IsMusl
            }

            $result | Should -Be $Expected
        }

        It 'Should throw for 32-bit processes' {
            {
                InModuleScope -ModuleName $script:moduleName {
                    Get-ImageConverterRuntimeIdentifier -Platform Windows -Architecture X86
                }
            } | Should -Throw -ExpectedMessage '*32-bit*'
        }

        It 'Should throw for musl on arm64' {
            {
                InModuleScope -ModuleName $script:moduleName {
                    Get-ImageConverterRuntimeIdentifier -Platform Linux -Architecture Arm64 -IsMusl
                }
            } | Should -Throw -ExpectedMessage '*linux-musl-arm64*'
        }
    }

    Context 'When called without parameters' {
        It 'Should return the identifier of the current session' {
            $result = InModuleScope -ModuleName $script:moduleName {
                Get-ImageConverterRuntimeIdentifier
            }

            $result | Should -Match '^(win|linux|linux-musl|osx)-(x64|arm64)$'
        }

        It 'Should match the operating system of the current session' {
            $expectedPattern = if ($IsWindows)
            {
                '^win-'
            }
            elseif ($IsMacOS)
            {
                '^osx-'
            }
            elseif (Test-Path -Path '/etc/alpine-release')
            {
                '^linux-musl-'
            }
            else
            {
                '^linux-(x64|arm64)$'
            }

            $result = InModuleScope -ModuleName $script:moduleName {
                Get-ImageConverterRuntimeIdentifier
            }

            $result | Should -Match $expectedPattern
        }
    }
}
