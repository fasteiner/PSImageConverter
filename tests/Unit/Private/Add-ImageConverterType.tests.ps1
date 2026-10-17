BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Add-ImageConverterType' {
    It 'Should compile a type that does not exist yet' {
        $className = 'Answer' + [System.Guid]::NewGuid().ToString('N')
        $source = "namespace PSImageConverterTest { public static class $className { public static int Get() { return 42; } } }"

        InModuleScope -ModuleName $script:moduleName -Parameters @{ TypeName = "PSImageConverterTest.$className"; Source = $source } {
            Add-ImageConverterType -TypeName $TypeName -TypeDefinition $Source
        }

        ("PSImageConverterTest.$className" -as [System.Type])::Get() | Should -Be 42
    }

    It 'Should not compile the source again when the type exists' {
        {
            InModuleScope -ModuleName $script:moduleName {
                Add-ImageConverterType -TypeName 'System.String' -TypeDefinition 'this is not C#'
            }
        } | Should -Not -Throw
    }
}
