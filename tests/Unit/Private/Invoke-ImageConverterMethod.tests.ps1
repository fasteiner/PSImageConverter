BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Invoke-ImageConverterMethod' {
    It 'Should call a constructor when no method name is given' {
        $call = InModuleScope -ModuleName $script:moduleName {
            Invoke-ImageConverterMethod -Type ([System.Text.StringBuilder]) -ArgumentList 'abc'
        }

        $call.Exception | Should -BeNullOrEmpty
        $call.Result | Should -BeOfType [System.Text.StringBuilder]
        $call.Result.ToString() | Should -Be 'abc'
    }

    It 'Should call a static method' {
        $call = InModuleScope -ModuleName $script:moduleName {
            Invoke-ImageConverterMethod -Type ([System.String]) -Name 'Concat' -ArgumentList 'a', 'b'
        }

        $call.Result | Should -Be 'ab'
    }

    It 'Should call an instance method' {
        $call = InModuleScope -ModuleName $script:moduleName {
            Invoke-ImageConverterMethod -InputObject 'hello' -Name 'ToUpperInvariant'
        }

        $call.Result | Should -Be 'HELLO'
    }

    It 'Should pass the base object of wrapped arguments' {
        $call = InModuleScope -ModuleName $script:moduleName {
            Invoke-ImageConverterMethod -Type ([System.Text.StringBuilder]) -ArgumentList ([System.Management.Automation.PSObject]::AsPSObject('abc'))
        }

        $call.Exception | Should -BeNullOrEmpty
        $call.Result.ToString() | Should -Be 'abc'
    }

    It 'Should return the exception of the call instead of throwing it' {
        $missing = Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString())

        $call = InModuleScope -ModuleName $script:moduleName -Parameters @{ Missing = $missing } {
            Invoke-ImageConverterMethod -Type ([System.IO.File]) -Name 'ReadAllText' -ArgumentList $Missing
        }

        $call.Result | Should -BeNullOrEmpty
        $call.Exception | Should -BeOfType [System.IO.FileNotFoundException]
    }

    It 'Should return the values of out parameters in Arguments' {
        $call = InModuleScope -ModuleName $script:moduleName {
            Invoke-ImageConverterMethod -Type ([System.Uri]) -Name 'TryCreate' -ArgumentList 'https://example.org/a', ([System.UriKind]::Absolute), $null
        }

        $call.Exception | Should -BeNullOrEmpty
        $call.Result | Should -BeTrue
        $call.Arguments[2] | Should -BeOfType [System.Uri]
        $call.Arguments[2].AbsolutePath | Should -Be '/a'
    }

    It 'Should return the exception for a method that does not exist' {
        $call = InModuleScope -ModuleName $script:moduleName {
            Invoke-ImageConverterMethod -InputObject 'hello' -Name 'NoSuchMethod'
        }

        $call.Exception | Should -BeOfType [System.MissingMethodException]
    }

    It 'Should not add the exception to $Error or to the caller''s -ErrorVariable' {
        $missing = Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString())
        $errorCount = $global:Error.Count

        $callerErrors = InModuleScope -ModuleName $script:moduleName -Parameters @{ Missing = $missing } {
            function Test-ImageConverterCaller
            {
                [CmdletBinding()]
                param ()

                $null = Invoke-ImageConverterMethod -Type ([System.IO.File]) -Name 'ReadAllText' -ArgumentList $Missing
            }

            $callerErrors = $null
            Test-ImageConverterCaller -ErrorVariable callerErrors
            @($callerErrors)
        }

        $callerErrors | Should -BeNullOrEmpty
        $global:Error.Count | Should -Be $errorCount
    }
}
