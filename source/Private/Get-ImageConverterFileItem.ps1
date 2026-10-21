function Get-ImageConverterFileItem
{
    <#
        .SYNOPSIS
        Returns a file as the FileSystem provider returns it, the same object Get-Item returns.

        .DESCRIPTION
        Returns the FileInfo of an existing file with the properties the FileSystem provider adds
        (PSPath, PSParentPath, PSChildName, PSDrive, PSProvider and, on Linux and macOS,
        UnixStat), also for hidden files and for names with wildcard characters. Piped into the
        next cmdlet, its PSPath binds -LiteralPath, as with Get-ChildItem output; a plain
        FileInfo would bind -Path, which expands wildcard characters in the file name. When the
        provider cannot return the item, a FileInfo with only the PSPath property is returned,
        which binds the same way. No exception reaches the caller.

        .PARAMETER Path
        The full path of the existing file to return.

        .EXAMPLE
        Get-ImageConverterFileItem -Path 'C:\Pictures\Holiday [2026].jpg'

        Returns the FileInfo of 'Holiday [2026].jpg' with its PSPath.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    # Get(path, force, literalPath): force returns hidden files, literalPath keeps [ and ] in the name.
    $item = Invoke-ImageConverterMethod -InputObject $ExecutionContext.InvokeProvider.Item -Name 'Get' -ArgumentList ([System.String[]] @($Path)), $true, $true

    if ($null -eq $item.Exception -and $item.Result.Count -eq 1)
    {
        return $item.Result[0]
    }

    $file = [System.IO.FileInfo]::new($Path)
    Add-Member -InputObject $file -NotePropertyName 'PSPath' -NotePropertyValue ('Microsoft.PowerShell.Core\FileSystem::' + $Path)
    $file
}
