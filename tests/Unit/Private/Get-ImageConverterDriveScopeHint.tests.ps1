BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    # A user's advanced function: its $PSCmdlet sees the drives of the scope that calls it, as a public cmdlet's does.
    function Invoke-UserCaller
    {
        [CmdletBinding()]
        [OutputType([System.String])]
        param ([System.String] $Path, [System.Management.Automation.SwitchParameter] $RelativeToLocation)

        & (Get-Module -Name $script:moduleName) {
            param ($Cmdlet, $Path, $RelativeToLocation)

            Get-ImageConverterDriveScopeHint -Cmdlet $Cmdlet -Path $Path -RelativeToLocation:$RelativeToLocation
        } $PSCmdlet $Path $RelativeToLocation
    }

    <#
        Script blocks bound to the module: the outer one stands for a ConvertTo-* wrapper (an advanced
        function of the module called by the user), the inner one for Convert-Image, which the wrapper
        calls, so the inner one's caller is module code.
    #>
    $script:moduleWrapper = InModuleScope -ModuleName $script:moduleName {
        {
            [CmdletBinding()]
            param ([System.String] $Path)

            & {
                [CmdletBinding()]
                param ([System.String] $Path)

                Get-ImageConverterDriveScopeHint -Cmdlet $PSCmdlet -Path $Path
            } -Path $Path
        }
    }

    # The same with a caller that is no advanced function and so has no $PSCmdlet.
    $script:moduleSimpleCaller = InModuleScope -ModuleName $script:moduleName {
        {
            param ([System.String] $Path)

            & {
                [CmdletBinding()]
                param ([System.String] $Path)

                Get-ImageConverterDriveScopeHint -Cmdlet $PSCmdlet -Path $Path
            } -Path $Path
        }
    }

    $script:scope = 'was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module)'
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterDriveScopeHint' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should name the drive and its root when the caller created it in its own scope' {
        # Without -Scope Global the drive exists in this It block's scope only.
        $null = New-PSDrive -Name 'PsicHintDrive' -PSProvider FileSystem -Root $script:tempDir.FullName

        $result = Invoke-UserCaller -Path 'PsicHintDrive:\a.heic'

        $result | Should -Be "drive 'PsicHintDrive' $($script:scope). Create the drive with New-PSDrive -Scope Global, or use the file system path; the root of the drive is '$($script:tempDir.FullName)'."
    }

    It 'Should name both roots when the caller''s drive hides a global drive of the same name' {
        $globalRoot = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'global')
        $null = New-PSDrive -Name 'PsicHintDrive' -PSProvider FileSystem -Root $globalRoot.FullName -Scope Global
        try
        {
            $null = New-PSDrive -Name 'PsicHintDrive' -PSProvider FileSystem -Root $script:tempDir.FullName

            $result = Invoke-UserCaller -Path 'PsicHintDrive:\a.heic'
        }
        finally
        {
            Remove-PSDrive -Name 'PsicHintDrive' -Scope Global
        }

        $result | Should -Be "drive 'PsicHintDrive' $($script:scope), so the module would use the global drive of that name, whose root is '$($globalRoot.FullName)'. Give the drive a name that no global drive has, or use the file system path; the root of the drive is '$($script:tempDir.FullName)'."
    }

    It 'Should return nothing for a global drive' {
        $null = New-PSDrive -Name 'PsicHintDrive' -PSProvider FileSystem -Root $script:tempDir.FullName -Scope Global
        try
        {
            $result = Invoke-UserCaller -Path 'PsicHintDrive:\a.heic'
        }
        finally
        {
            Remove-PSDrive -Name 'PsicHintDrive' -Scope Global
        }

        $result | Should -BeNullOrEmpty
    }

    It 'Should say that only file system paths are supported for a drive of another provider' {
        $null = New-PSDrive -Name 'PsicHintEnv' -PSProvider Environment -Root ''

        $result = Invoke-UserCaller -Path 'PsicHintEnv:\PATH'

        $result | Should -Be "drive 'PsicHintEnv' belongs to the Environment provider. Only file system paths are supported."
    }

    It 'Should check the drive of the current location for a relative path only with -RelativeToLocation' {
        $null = New-PSDrive -Name 'PsicHintDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
        Push-Location -Path 'PsicHintDrive:\'
        try
        {
            $relative = Invoke-UserCaller -Path 'a.heic' -RelativeToLocation
            $withoutSwitch = Invoke-UserCaller -Path 'a.heic'
        }
        finally
        {
            Pop-Location
        }

        $relative | Should -BeLike "drive 'PsicHintDrive' $($script:scope)*"
        $withoutSwitch | Should -BeNullOrEmpty
    }

    It 'Should return nothing for <Case> while the current location is on such a drive' -ForEach @(
        @{ Case = 'a provider-qualified path'; Path = 'Microsoft.PowerShell.Core\FileSystem::/a.heic' }
        @{ Case = 'a path below ~'; Path = '~/a.heic' }
        @{ Case = 'a UNC path'; Path = '\\server\share\a.heic' }
    ) {
        $null = New-PSDrive -Name 'PsicHintDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
        Push-Location -Path 'PsicHintDrive:\'
        try
        {
            $result = Invoke-UserCaller -Path $Path -RelativeToLocation
        }
        finally
        {
            Pop-Location
        }

        $result | Should -BeNullOrEmpty
    }

    It 'Should look up the drive in the scopes of the code that called a wrapper of the module' {
        $null = New-PSDrive -Name 'PsicHintDrive' -PSProvider FileSystem -Root $script:tempDir.FullName

        $result = & $script:moduleWrapper -Path 'PsicHintDrive:\a.heic'

        $result | Should -BeLike "drive 'PsicHintDrive' was created in a scope *"
    }

    It 'Should return nothing when the module code that called the cmdlet has no $PSCmdlet' {
        $null = New-PSDrive -Name 'PsicHintDrive' -PSProvider FileSystem -Root $script:tempDir.FullName

        $result = & $script:moduleSimpleCaller -Path 'PsicHintDrive:\a.heic'

        $result | Should -BeNullOrEmpty
    }

    It 'Should return nothing for <Case>' -ForEach @(
        @{ Case = 'a drive that the caller does not know either'; Path = 'PsicNoSuchDrive:\a.heic' }
        @{ Case = 'a file system path'; Path = [System.IO.Path]::GetTempPath() }
        @{ Case = 'a relative path on a global drive'; Path = 'a.heic' }
    ) {
        $result = Invoke-UserCaller -Path $Path -RelativeToLocation

        $result | Should -BeNullOrEmpty
    }

    It 'Should write no error record' {
        $null = New-PSDrive -Name 'PsicHintDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
        $errorCount = $global:Error.Count

        $null = Invoke-UserCaller -Path 'PsicHintDrive:\a.heic'
        $null = Invoke-UserCaller -Path 'PsicNoSuchDrive:\a.heic'
        $null = Invoke-UserCaller -Path ':' -RelativeToLocation

        $global:Error.Count | Should -Be $errorCount
    }
}
