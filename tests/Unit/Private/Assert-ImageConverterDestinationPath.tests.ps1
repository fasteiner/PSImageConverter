BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    # Runs the check from a named advanced function, as the public cmdlets do, and catches its terminating error.
    function Invoke-Assert
    {
        param ([System.String] $DestinationPath)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ DestinationPath = $DestinationPath } {
            function Test-ImageConverterCaller
            {
                [CmdletBinding()]
                param ([System.String] $DestinationPath)

                Assert-ImageConverterDestinationPath -Cmdlet $PSCmdlet -DestinationPath $DestinationPath
                'continued'
            }

            $errorCount = $global:Error.Count
            $output = $null
            $caught = $null
            try
            {
                $output = Test-ImageConverterCaller -DestinationPath $DestinationPath
            }
            catch
            {
                $caught = $_
            }

            [PSCustomObject] @{
                Output     = $output
                Error      = $caught
                ErrorCount = $global:Error.Count - $errorCount
            }
        }
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Assert-ImageConverterDestinationPath' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
        $script:file = Join-Path -Path $script:tempDir.FullName -ChildPath 'file.txt'
        Set-Content -Path $script:file -Value 'x'
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should return nothing when no destination is given' {
        $result = Invoke-Assert -DestinationPath ''

        $result.Error | Should -BeNullOrEmpty
        $result.Output | Should -Be 'continued'
    }

    It 'Should return the full path of a folder that does not exist yet without creating it' {
        $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'out/jpg'

        $result = Invoke-Assert -DestinationPath $destination

        $result.Error | Should -BeNullOrEmpty
        $result.Output | Should -Be @([System.IO.Path]::GetFullPath($destination), 'continued')
        $destination | Should -Not -Exist
    }

    It 'Should stop the caller with one terminating <ErrorId> error for <Case>' -ForEach @(
        @{ Case = 'a file'; ErrorId = 'DestinationNotDirectory'; Destination = 'file' }
        @{ Case = 'a folder below a file'; ErrorId = 'DestinationNotDirectory'; Destination = 'below-file' }
        @{ Case = 'a path of another provider'; ErrorId = 'UnsupportedProvider'; Destination = 'Env:\Pictures' }
        @{ Case = 'an unknown provider'; ErrorId = 'InvalidDestinationPath'; Destination = 'NoSuchProvider::C:\out' }
        @{ Case = 'an unknown drive'; ErrorId = 'InvalidDestinationPath'; Destination = 'PsicNoSuchDrive:\out' }
        @{ Case = 'a NUL character'; ErrorId = 'InvalidDestinationPath'; Destination = 'nul-character' }
        @{ Case = 'white space only'; ErrorId = 'InvalidDestinationPath'; Destination = ' ' }
        @{ Case = 'a provider-qualified path without a folder'; ErrorId = 'InvalidDestinationPath'; Destination = 'Microsoft.PowerShell.Core\FileSystem::' }
    ) {
        $destinationPath = switch ($Destination)
        {
            'file' { $script:file }
            'below-file' { Join-Path -Path $script:file -ChildPath 'sub' }
            'nul-character' { Join-Path -Path $script:tempDir.FullName -ChildPath "a`0b" }
            default { $Destination }
        }

        $result = Invoke-Assert -DestinationPath $destinationPath

        $result.Output | Should -BeNullOrEmpty
        $result.ErrorCount | Should -Be 1
        $result.Error.FullyQualifiedErrorId | Should -Be "$ErrorId,Test-ImageConverterCaller"
        $result.Error.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $result.Error.TargetObject | Should -Be $destinationPath
    }
}
