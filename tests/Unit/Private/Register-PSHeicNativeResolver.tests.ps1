BeforeAll {
    $script:moduleName = 'PSHeic'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Register-PSHeicNativeResolver' {
    # NativeLibrary.SetDllImportResolver only exists on .NET Core / PowerShell 7.
    It 'Should register the resolver idempotently' -Skip:($PSVersionTable.PSEdition -eq 'Desktop') {
        {
            InModuleScope -ModuleName $script:moduleName {
                Register-PSHeicNativeResolver -Assembly ([ImageMagick.MagickImage].Assembly) -NativePath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
                Register-PSHeicNativeResolver -Assembly ([ImageMagick.MagickImage].Assembly) -NativePath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
            }
        } | Should -Not -Throw

        'PSHeic.NativeResolver' -as [System.Type] | Should -Not -BeNullOrEmpty
    }
}
