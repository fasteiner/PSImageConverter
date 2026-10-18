BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Write-ImageConverterError' {
    BeforeAll {
        # Writes one error through a named advanced function, as the public cmdlets do.
        function Invoke-WriteError
        {
            param
            (
                [System.Collections.Hashtable] $Parameters,
                [System.String] $ErrorAction = 'SilentlyContinue'
            )

            InModuleScope -ModuleName $script:moduleName -Parameters @{ WriteParameters = $Parameters; Action = $ErrorAction } {
                function Test-ImageConverterCaller
                {
                    [CmdletBinding()]
                    [OutputType([System.String])]
                    param ()

                    Write-ImageConverterError -Cmdlet $PSCmdlet @WriteParameters
                    'continued'
                }

                $writeErrors = $null
                $output = Test-ImageConverterCaller -ErrorAction $Action -ErrorVariable writeErrors
                $succeeded = $?

                [PSCustomObject] @{
                    Output    = $output
                    Succeeded = $succeeded
                    Errors    = @($writeErrors)
                }
            }
        }
    }

    It 'Should write a non-terminating error with the id, category and target' {
        $exception = [System.IO.IOException]::new('The file exists.')

        $result = Invoke-WriteError -Parameters @{ Exception = $exception; ErrorId = 'TargetExists'; Category = 'ResourceExists'; TargetObject = 'C:\a.heic' }

        $result.Output | Should -Be 'continued'
        $result.Succeeded | Should -BeFalse
        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -Be 'TargetExists,Test-ImageConverterCaller'
        $result.Errors[0].CategoryInfo.Category | Should -Be 'ResourceExists'
        $result.Errors[0].TargetObject | Should -Be 'C:\a.heic'
        $result.Errors[0].Exception | Should -Be $exception
        "$($result.Errors[0])" | Should -Be 'The file exists.'
    }

    It 'Should unwrap a <Wrapper>' -ForEach @(
        @{ Wrapper = 'MethodInvocationException' }
        @{ Wrapper = 'TargetInvocationException' }
    ) {
        $inner = [System.IO.InvalidDataException]::new('corrupt image')
        if ($Wrapper -eq 'MethodInvocationException')
        {
            $exception = [System.Management.Automation.MethodInvocationException]::new('Exception calling ".ctor"', $inner)
        }
        else
        {
            $exception = [System.Reflection.TargetInvocationException]::new($inner)
        }

        $result = Invoke-WriteError -Parameters @{ Exception = $exception; ErrorId = 'ImageReadFailed'; Category = 'InvalidData' }

        $result.Errors[0].Exception | Should -Be $inner
    }

    It 'Should put the message prefix in front of the exception message' {
        $exception = [System.IO.InvalidDataException]::new('corrupt image')

        $result = Invoke-WriteError -Parameters @{ Exception = $exception; ErrorId = 'ImageReadFailed'; Category = 'InvalidData'; MessagePrefix = "Cannot read image 'C:\a.heic'" }

        "$($result.Errors[0])" | Should -Be "Cannot read image 'C:\a.heic': corrupt image"
        $result.Errors[0].Exception.Message | Should -Be 'corrupt image'
    }

    It 'Should make the error terminating with -ErrorAction Stop' {
        $exception = [System.IO.IOException]::new('The file exists.')

        { Invoke-WriteError -Parameters @{ Exception = $exception; ErrorId = 'TargetExists'; Category = 'ResourceExists' } -ErrorAction Stop } | Should -Throw -ErrorId 'TargetExists,Test-ImageConverterCaller'
    }

    It 'Should stop the calling cmdlet with -Terminating, also with -ErrorAction SilentlyContinue' {
        $exception = [System.ArgumentException]::new('The destination is a file.')
        $errorCount = $global:Error.Count
        $caught = $null

        try
        {
            $null = Invoke-WriteError -Parameters @{ Exception = $exception; ErrorId = 'DestinationNotDirectory'; Category = 'InvalidArgument'; TargetObject = 'C:\file.txt'; Terminating = $true }
        }
        catch
        {
            $caught = $_
        }

        $caught.FullyQualifiedErrorId | Should -Be 'DestinationNotDirectory,Test-ImageConverterCaller'
        $caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $caught.TargetObject | Should -Be 'C:\file.txt'
        $caught.Exception | Should -Be $exception
        $global:Error.Count - $errorCount | Should -Be 1
    }
}
