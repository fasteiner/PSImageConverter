BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    # A user's advanced function, so the resolver sees the drives of the scope that calls it, as a public cmdlet does.
    function Resolve-Destination
    {
        [CmdletBinding()]
        param ([System.String] $DestinationPath)

        & (Get-Module -Name $script:moduleName) {
            param ($Cmdlet, $DestinationPath)

            Resolve-ImageConverterDestinationPath -Cmdlet $Cmdlet -DestinationPath $DestinationPath
        } $PSCmdlet $DestinationPath
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Resolve-ImageConverterDestinationPath' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should return the full path of a folder that does not exist yet without creating it' {
        $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'out/jpg'

        $result = Resolve-Destination -DestinationPath $destination

        $result.ErrorId | Should -BeNullOrEmpty
        $result.Path | Should -Be ([System.IO.Path]::GetFullPath($destination))
        $destination | Should -Not -Exist
    }

    It 'Should resolve a relative path against the current location' {
        Push-Location -LiteralPath $script:tempDir.FullName
        try
        {
            $result = Resolve-Destination -DestinationPath 'relative'
        }
        finally
        {
            Pop-Location
        }

        $result.Path | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'relative')
    }

    It 'Should return DestinationNotDirectory when <Case>' -ForEach @(
        @{ Case = 'the destination is a file'; Child = '' }
        @{ Case = 'a parent folder of the destination is a file'; Child = 'sub/deeper' }
    ) {
        $file = Join-Path -Path $script:tempDir.FullName -ChildPath 'file.txt'
        Set-Content -Path $file -Value 'x'
        $destination = $file
        if ($Child)
        {
            $destination = Join-Path -Path $file -ChildPath $Child
        }

        $result = Resolve-Destination -DestinationPath $destination

        $result.Path | Should -BeNullOrEmpty
        $result.ErrorId | Should -Be 'DestinationNotDirectory'
        $result.Exception.Message | Should -BeLike "*'$file' is a file*"
    }

    It 'Should return UnsupportedProvider for <DestinationPath>' -ForEach @(
        @{ DestinationPath = 'Env:\Pictures' }
        @{ DestinationPath = 'Env:\' }
        @{ DestinationPath = 'Function:\' }
    ) {
        $result = Resolve-Destination -DestinationPath $DestinationPath

        $result.ErrorId | Should -Be 'UnsupportedProvider'
        $result.Exception.Message | Should -BeLike '*provider. Only file system paths are supported.'
    }

    It 'Should return InvalidDestinationPath for an unknown provider' {
        $result = Resolve-Destination -DestinationPath 'NoSuchProvider::C:\out'

        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $result.Exception.InnerException | Should -BeOfType [System.Management.Automation.ProviderNotFoundException]
    }

    It 'Should return InvalidDestinationPath for a path that leaves its drive root without recording an error' {
        $null = New-PSDrive -Name 'PsicRoot' -PSProvider FileSystem -Root $script:tempDir.FullName -Scope Global
        $errorCount = $global:Error.Count
        try
        {
            $result = Resolve-Destination -DestinationPath 'PsicRoot:/../../x'
        }
        finally
        {
            Remove-PSDrive -Name 'PsicRoot' -Scope Global
        }

        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $global:Error.Count | Should -Be $errorCount
    }

    It 'Should return InvalidDestinationPath for invalid characters' -Skip:(-not $IsWindows) {
        $result = Resolve-Destination -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'a|b')

        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $result.Exception.Message | Should -BeLike '*invalid characters*'
    }

    It 'Should return InvalidDestinationPath for a NUL character on every platform' {
        $result = Resolve-Destination -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath "a`0b")

        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $result.Path | Should -BeNullOrEmpty
    }

    It 'Should return InvalidDestinationPath for an unknown drive' {
        $result = Resolve-Destination -DestinationPath 'PsicNoSuchDrive:\out'

        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $result.Exception.InnerException | Should -BeOfType [System.Management.Automation.DriveNotFoundException]
    }

    It 'Should return InvalidDestinationPath that explains a drive created in a scope the module cannot see' {
        # Without -Scope Global the drive exists in this It block's scope only, which the module does not see.
        $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName

        $result = Resolve-Destination -DestinationPath 'PsicScopeDrive:\out'

        $result.Path | Should -BeNullOrEmpty
        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $result.Exception.Message | Should -Be "The destination path 'PsicScopeDrive:\out' is not valid: drive 'PsicScopeDrive' was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module). Create the drive with New-PSDrive -Scope Global, or use the file system path; the root of the drive is '$($script:tempDir.FullName)'."
    }

    It 'Should return InvalidDestinationPath for a drive of the caller that hides a global drive of the same name' {
        $globalRoot = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'global')
        $localRoot = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'local')
        $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $globalRoot.FullName -Scope Global
        try
        {
            # This It block's drive hides the global one for the test, but not for the module.
            $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $localRoot.FullName
            $errorCount = $global:Error.Count

            $result = Resolve-Destination -DestinationPath 'PsicShadowDrive:\out'
        }
        finally
        {
            Remove-PSDrive -Name 'PsicShadowDrive' -Scope Global
        }

        $result.Path | Should -BeNullOrEmpty
        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $result.Exception.Message | Should -Be "The destination path 'PsicShadowDrive:\out' is not valid: drive 'PsicShadowDrive' was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module), so the module would use the global drive of that name, whose root is '$($globalRoot.FullName)'. Give the drive a name that no global drive has, or use the file system path; the root of the drive is '$($localRoot.FullName)'."
        $global:Error.Count | Should -Be $errorCount
    }

    It 'Should return InvalidDestinationPath that names the provider of a drive of another provider the module cannot see' {
        $null = New-PSDrive -Name 'PsicEnvDrive' -PSProvider Environment -Root ''

        $result = Resolve-Destination -DestinationPath 'PsicEnvDrive:\out'

        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $result.Exception.Message | Should -Be "The destination path 'PsicEnvDrive:\out' is not valid: drive 'PsicEnvDrive' belongs to the Environment provider. Only file system paths are supported."
    }

    It 'Should return InvalidDestinationPath for a colon after the root on Windows: <Case>' -Skip:(-not $IsWindows) -ForEach @(
        @{ Case = 'alternate data stream syntax'; Child = 'x:stream' }
        @{ Case = 'a colon in a middle folder'; Child = 'partial/x:y/z' }
    ) {
        $destination = Join-Path -Path $script:tempDir.FullName -ChildPath $Child

        $result = Resolve-Destination -DestinationPath $destination

        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $result.Exception.Message | Should -BeLike '*contains invalid characters.'
        Join-Path -Path $script:tempDir.FullName -ChildPath 'partial' | Should -Not -Exist
    }

    It 'Should accept a colon in a folder name on Linux and macOS' -Skip:$IsWindows {
        $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'x:y'

        $result = Resolve-Destination -DestinationPath $destination

        $result.ErrorId | Should -BeNullOrEmpty
        $result.Path | Should -Be $destination
    }

    It 'Should resolve a relative path while the current location is on a drive the module cannot see' {
        $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
        Push-Location -Path 'PsicScopeDrive:\'
        try
        {
            $result = Resolve-Destination -DestinationPath 'out'
        }
        finally
        {
            Pop-Location
        }

        $result.ErrorId | Should -BeNullOrEmpty
        $result.Path | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'out')
    }

    It 'Should return InvalidDestinationPath for white space only: <Name>' -ForEach @(
        @{ Name = 'one space'; DestinationPath = ' ' }
        @{ Name = 'three spaces'; DestinationPath = '   ' }
        @{ Name = 'a tab'; DestinationPath = "`t" }
    ) {
        # Windows trims trailing spaces, so ' ' would be the current folder instead of the source folder.
        $result = Resolve-Destination -DestinationPath $DestinationPath

        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $result.Exception.Message | Should -BeLike '*consists of white space only.'
    }

    It 'Should return InvalidDestinationPath for a provider-qualified path without a folder' {
        $result = Resolve-Destination -DestinationPath 'Microsoft.PowerShell.Core\FileSystem::'

        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $result.Exception.Message | Should -BeLike '*names no folder.'
    }

    Context 'When the destination is reached through a link' {
        BeforeEach {
            # A junction on Windows needs no privilege; Linux and macOS have symbolic links.
            $script:linkTarget = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'target')
            $script:link = Join-Path -Path $script:tempDir.FullName -ChildPath 'link'
            $linkType = 'SymbolicLink'
            if ($IsWindows)
            {
                $linkType = 'Junction'
            }
            $null = New-Item -ItemType $linkType -Path $script:link -Target $script:linkTarget.FullName
        }

        It 'Should accept a link to an existing folder, child folder <Child>' -ForEach @(
            @{ Child = '' }
            @{ Child = 'sub' }
        ) {
            $destination = $script:link
            if ($Child)
            {
                $destination = Join-Path -Path $script:link -ChildPath $Child
            }

            $result = Resolve-Destination -DestinationPath $destination

            $result.ErrorId | Should -BeNullOrEmpty
            $result.Path | Should -Be $destination
        }

        It 'Should return DestinationNotDirectory for a link whose target is gone, child folder <Child>' -ForEach @(
            @{ Child = '' }
            @{ Child = 'sub' }
        ) {
            Remove-Item -LiteralPath $script:linkTarget.FullName
            $destination = $script:link
            if ($Child)
            {
                $destination = Join-Path -Path $script:link -ChildPath $Child
            }

            $result = Resolve-Destination -DestinationPath $destination

            $result.Path | Should -BeNullOrEmpty
            $result.ErrorId | Should -Be 'DestinationNotDirectory'
            $result.Exception.Message | Should -BeLike "*'$($script:link)' is a link whose target '$($script:linkTarget.FullName)' does not exist."
        }

        It 'Should return DestinationNotDirectory for a link that points to itself, child folder <Child>' -ForEach @(
            @{ Child = '' }
            @{ Child = 'sub' }
        ) {
            # Linux and macOS report a symbolic link loop as a file, Windows a junction loop as a folder.
            $loop = Join-Path -Path $script:tempDir.FullName -ChildPath 'loop'
            if ($IsWindows)
            {
                $null = cmd.exe /c mklink /J $loop $loop
            }
            else
            {
                $null = [System.IO.File]::CreateSymbolicLink($loop, $loop)
            }

            $destination = $loop
            if ($Child)
            {
                $destination = Join-Path -Path $loop -ChildPath $Child
            }

            $result = Resolve-Destination -DestinationPath $destination

            $result.Path | Should -BeNullOrEmpty
            $result.ErrorId | Should -Be 'DestinationNotDirectory'
            $result.Exception.Message | Should -BeLike "*'$loop' is a link that cannot be resolved: *"
        }

        It 'Should return DestinationNotDirectory for a link to a file' -Skip:$IsWindows {
            $file = Join-Path -Path $script:tempDir.FullName -ChildPath 'file.txt'
            Set-Content -Path $file -Value 'x'
            $fileLink = Join-Path -Path $script:tempDir.FullName -ChildPath 'file-link'
            $null = New-Item -ItemType SymbolicLink -Path $fileLink -Target $file

            $result = Resolve-Destination -DestinationPath $fileLink

            $result.ErrorId | Should -Be 'DestinationNotDirectory'
            $result.Exception.Message | Should -BeLike "*'$fileLink' is a file*"
        }
    }
}
