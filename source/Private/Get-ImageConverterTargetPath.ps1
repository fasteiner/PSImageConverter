function Get-ImageConverterTargetPath
{
    <#
        .SYNOPSIS
        Returns the full path of the output file for a source file.

        .DESCRIPTION
        Builds the output path the conversion cmdlets write to: the source file's base name with
        the extension of the output format, in -Folder or, without it, in the source file's
        folder. The result is a full, normalised path. Only the name is computed; nothing is
        checked or created, so ConvertFrom-Heic can predict the targets Convert-Image writes.

        .PARAMETER SourcePath
        The full path of the source image file the output name is derived from.

        .PARAMETER Extension
        The extension of the output file including the leading dot, e.g. '.jpg'.

        .PARAMETER Folder
        The full path of the destination folder. Defaults to the source file's folder.

        .EXAMPLE
        Get-ImageConverterTargetPath -SourcePath 'C:\Pictures\IMG_1234.HEIC' -Extension '.jpg'

        Returns 'C:\Pictures\IMG_1234.jpg'.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SourcePath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Extension,

        [Parameter()]
        [System.String]
        $Folder
    )

    if ([System.String]::IsNullOrEmpty($Folder))
    {
        $Folder = [System.IO.Path]::GetDirectoryName($SourcePath)
    }

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath) + $Extension

    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($Folder, $fileName))
}
