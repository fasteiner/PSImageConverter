BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Register-ImageConverterNativeResolver' {
    It 'Should register the resolver idempotently' {
        {
            InModuleScope -ModuleName $script:moduleName {
                Register-ImageConverterNativeResolver -Assembly ([ImageMagick.MagickImage].Assembly) -NativePath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
                Register-ImageConverterNativeResolver -Assembly ([ImageMagick.MagickImage].Assembly) -NativePath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
            }
        } | Should -Not -Throw

        'PSImageConverter.NativeResolver' -as [System.Type] | Should -Not -BeNullOrEmpty
        [PSImageConverter.NativeResolver]::IsRegistered | Should -BeTrue
    }
}
