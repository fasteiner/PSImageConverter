function Resolve-ImageConverterDestinationPath
{
    <#
        .SYNOPSIS
        Resolves -DestinationPath to a full file system folder path and checks that it is usable.

        .DESCRIPTION
        Resolves the destination folder against the current location (relative paths, PSDrives,
        provider-qualified paths) without requiring that it exists, and returns an object with
        the properties Path, ErrorId and Exception. Path is the full folder path when the
        destination is usable. Otherwise Path is empty and ErrorId names the problem:
        InvalidDestinationPath (white space only, unknown drive or provider, a drive-qualified
        path that climbs above the root of its drive such as Temp:\..\x, a provider-qualified
        path without a folder, invalid characters, on Windows also a colon after the root),
        UnsupportedProvider (a path of another provider, also its root such as Env:\) or
        DestinationNotDirectory (the path or one of its parent folders is an existing file, a
        junction or symbolic link whose target does not exist, or a link that cannot be resolved,
        such as one that points to itself). A relative path that climbs above the root stays at
        the root, as in other PowerShell cmdlets. A drive-qualified path on a PSDrive that the
        caller created in a scope the module cannot see (which the module would not find, or
        resolve on a global drive of the same name) is InvalidDestinationPath with the
        explanation of Get-ImageConverterDriveScopeHint; a relative path while the current
        location is on such a drive resolves on the right drive. Nothing is written or created,
        so -WhatIf callers stay free of side effects and can report the problem before
        ShouldProcess.

        .PARAMETER Cmdlet
        The $PSCmdlet of the public cmdlet whose -DestinationPath this is, e.g. Convert-Image.

        .PARAMETER DestinationPath
        The destination folder as given by the user, e.g. '.\out' or 'C:\Pictures\jpg'.

        .EXAMPLE
        Resolve-ImageConverterDestinationPath -Cmdlet $PSCmdlet -DestinationPath '.\jpg'

        Returns the full path of the folder jpg below the current location.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]
        $Cmdlet,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DestinationPath
    )

    # Windows trims trailing spaces from a path, so ' ' would silently become the current folder.
    if ([System.String]::IsNullOrWhiteSpace($DestinationPath))
    {
        return [PSCustomObject] @{
            Path      = $null
            ErrorId   = 'InvalidDestinationPath'
            Exception = [System.ArgumentException]::new("The destination path '$DestinationPath' is not valid: it consists of white space only.")
        }
    }

    # The module does not find a drive the caller created in its own scope, or it would write to a global drive of the same name.
    $scopeHint = Get-ImageConverterDriveScopeHint -Cmdlet $Cmdlet -Path $DestinationPath
    if ($null -ne $scopeHint)
    {
        return [PSCustomObject] @{
            Path      = $null
            ErrorId   = 'InvalidDestinationPath'
            Exception = [System.ArgumentException]::new("The destination path '$DestinationPath' is not valid: $scopeHint")
        }
    }

    # The out parameters provider and drive are passed as $null and read back from Arguments.
    $resolve = Invoke-ImageConverterMethod -InputObject $ExecutionContext.SessionState.Path -Name 'GetUnresolvedProviderPathFromPSPath' -ArgumentList $DestinationPath, $null, $null

    if ($null -ne $resolve.Exception)
    {
        return [PSCustomObject] @{
            Path      = $null
            ErrorId   = 'InvalidDestinationPath'
            Exception = [System.ArgumentException]::new("The destination path '$DestinationPath' is not valid: $($resolve.Exception.Message)", $resolve.Exception)
        }
    }

    $provider = $resolve.Arguments[1]

    if ($provider.ImplementingType -ne [Microsoft.PowerShell.Commands.FileSystemProvider])
    {
        return [PSCustomObject] @{
            Path      = $null
            ErrorId   = 'UnsupportedProvider'
            Exception = [System.ArgumentException]::new("The destination path '$DestinationPath' belongs to the $($provider.Name) provider. Only file system paths are supported.")
        }
    }

    # A provider-qualified path without a path after the provider, e.g. 'FileSystem::'.
    if ([System.String]::IsNullOrWhiteSpace($resolve.Result))
    {
        return [PSCustomObject] @{
            Path      = $null
            ErrorId   = 'InvalidDestinationPath'
            Exception = [System.ArgumentException]::new("The destination path '$DestinationPath' is not valid: it names no folder.")
        }
    }

    <#
        Test-Path -IsValid writes an error for some drive-qualified paths; on the resolved file system
        path it only checks the characters. It accepts a colon after the root on Windows (the syntax of
        an alternate data stream), which no folder name can contain there.
    #>
    $root = [System.IO.Path]::GetPathRoot($resolve.Result)
    if (-not (Test-Path -LiteralPath $resolve.Result -IsValid -ErrorAction Ignore) -or ($IsWindows -and $resolve.Result.Substring($root.Length).Contains(':')))
    {
        return [PSCustomObject] @{
            Path      = $null
            ErrorId   = 'InvalidDestinationPath'
            Exception = [System.ArgumentException]::new("The destination path '$DestinationPath' is not valid: it contains invalid characters.")
        }
    }

    $folder = [System.IO.Path]::GetFullPath($resolve.Result)

    <#
        The missing folders are created later, inside ShouldProcess; a file anywhere on the way makes
        that impossible, and so does a link whose target is gone: Windows reports a dangling junction
        or folder link as an existing folder, Linux and macOS a dangling symbolic link as a file. The
        nearest existing entry is the only one that can be such a link.
    #>
    $existing = $folder
    while (-not [System.String]::IsNullOrEmpty($existing))
    {
        $isDirectory = [System.IO.Directory]::Exists($existing)

        if ($isDirectory -or [System.IO.File]::Exists($existing))
        {
            $entry = [System.IO.FileInfo]::new($existing)
            if ($isDirectory)
            {
                $entry = [System.IO.DirectoryInfo]::new($existing)
            }

            # Null for an entry that is not a link; a drive root throws, which leaves it a folder.
            $link = Invoke-ImageConverterMethod -InputObject $entry -Name 'ResolveLinkTarget' -ArgumentList $true
            $linkTarget = $link.Result

            <#
                A link that points to itself or into a loop: Linux and macOS report it as a file, Windows
                a junction loop as a folder, which only the creation of the target folder would reveal.
            #>
            if ($null -ne $link.Exception -and $null -ne $entry.LinkTarget)
            {
                return [PSCustomObject] @{
                    Path      = $null
                    ErrorId   = 'DestinationNotDirectory'
                    Exception = [System.ArgumentException]::new("The destination path '$folder' cannot be a folder: '$existing' is a link that cannot be resolved: $($link.Exception.Message)")
                }
            }

            if ($null -ne $linkTarget -and -not [System.IO.Directory]::Exists($linkTarget.FullName) -and -not [System.IO.File]::Exists($linkTarget.FullName))
            {
                return [PSCustomObject] @{
                    Path      = $null
                    ErrorId   = 'DestinationNotDirectory'
                    Exception = [System.ArgumentException]::new("The destination path '$folder' cannot be a folder: '$existing' is a link whose target '$($linkTarget.FullName)' does not exist.")
                }
            }

            if (-not $isDirectory)
            {
                return [PSCustomObject] @{
                    Path      = $null
                    ErrorId   = 'DestinationNotDirectory'
                    Exception = [System.ArgumentException]::new("The destination path '$folder' cannot be a folder: '$existing' is a file. -DestinationPath must be a folder.")
                }
            }

            break
        }

        $existing = [System.IO.Path]::GetDirectoryName($existing)
    }

    [PSCustomObject] @{
        Path      = $folder
        ErrorId   = $null
        Exception = $null
    }
}
