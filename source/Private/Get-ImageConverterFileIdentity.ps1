function Get-ImageConverterFileIdentity
{
    <#
        .SYNOPSIS
        Returns a string that identifies a file independently of how its path is spelled.

        .DESCRIPTION
        Returns the volume serial number and file id on Windows, or the device id and inode on
        Linux and macOS, as one string. Two paths that name the same file give the same string,
        also when one of them reaches it through a junction, a symbolic link to a folder, a subst
        or mapped drive, a UNC path, the \\?\ prefix, a short 8.3 name or another letter case on
        a case-insensitive file system. Hard links of one file share the identity. On Linux and
        macOS a symbolic link to a file has an identity of its own, because replacing the link
        does not touch the file it points to. Returns $null when the file does not exist or its
        identity cannot be read; the callers then compare the path strings instead.

        .PARAMETER Path
        The full path of the file whose identity is returned.

        .PARAMETER Platform
        The platform whose API is used, Windows or Unix. Defaults to the current platform.

        .EXAMPLE
        Get-ImageConverterFileIdentity -Path 'C:\Pictures\IMG_1234.jpg'

        Returns e.g. '2c94326c:00000000000000000005000000185ed7'.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [ValidateSet('Windows', 'Unix')]
        [System.String]
        $Platform
    )

    if (-not [System.IO.File]::Exists($Path))
    {
        return $null
    }

    if (-not $PSBoundParameters.ContainsKey('Platform'))
    {
        $Platform = 'Unix'

        if ($IsWindows)
        {
            $Platform = 'Windows'
        }
    }

    if ($Platform -eq 'Unix')
    {
        # pwsh adds UnixStat (the lstat of the path) to the items of the FileSystem provider on Linux and macOS.
        $stat = (Get-ImageConverterFileItem -Path $Path).UnixStat

        if ($null -eq $stat)
        {
            return $null
        }

        return '{0}:{1}' -f $stat.DeviceId, $stat.Inode
    }

    [PSImageConverter.FileIdentity]::Get($Path)
}
