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
        InvalidDestinationPath (unknown drive or provider, a path that leaves its drive root,
        invalid characters), UnsupportedProvider (a path of another provider, also its root such
        as Env:\) or DestinationNotDirectory (the path or one of its parent folders is an
        existing file). Nothing is written or created, so -WhatIf callers stay free of side
        effects and can report the problem before ShouldProcess.

        .PARAMETER DestinationPath
        The destination folder as given by the user, e.g. '.\out' or 'C:\Pictures\jpg'.

        .EXAMPLE
        Resolve-ImageConverterDestinationPath -DestinationPath '.\jpg'

        Returns the full path of the folder jpg below the current location.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $DestinationPath
    )

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

    # Test-Path -IsValid writes an error for some drive-qualified paths; on the resolved file system path it only checks the characters.
    if (-not (Test-Path -LiteralPath $resolve.Result -IsValid -ErrorAction Ignore))
    {
        return [PSCustomObject] @{
            Path      = $null
            ErrorId   = 'InvalidDestinationPath'
            Exception = [System.ArgumentException]::new("The destination path '$DestinationPath' is not valid: it contains invalid characters.")
        }
    }

    $folder = [System.IO.Path]::GetFullPath($resolve.Result)

    # The missing folders are created later, inside ShouldProcess; a file anywhere on the way makes that impossible.
    $existing = $folder
    while (-not [System.String]::IsNullOrEmpty($existing) -and -not [System.IO.Directory]::Exists($existing))
    {
        if ([System.IO.File]::Exists($existing))
        {
            return [PSCustomObject] @{
                Path      = $null
                ErrorId   = 'DestinationNotDirectory'
                Exception = [System.ArgumentException]::new("The destination path '$folder' cannot be a folder: '$existing' is a file. -DestinationPath must be a folder.")
            }
        }

        $existing = [System.IO.Path]::GetDirectoryName($existing)
    }

    [PSCustomObject] @{
        Path      = $folder
        ErrorId   = $null
        Exception = $null
    }
}
