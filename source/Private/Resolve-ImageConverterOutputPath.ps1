function Resolve-ImageConverterOutputPath
{
    <#
        .SYNOPSIS
        Builds the full output path for a converted image.

        .DESCRIPTION
        Combines the destination folder (or the source file's folder when none is
        given) with the source file's base name and the new extension. Throws when
        the target file already exists unless Force is specified. The folder itself
        is not created here, so -WhatIf callers stay free of side effects.

        .PARAMETER SourcePath
        The full path of the source image file.

        .PARAMETER Extension
        The extension of the output file including the leading dot, e.g. '.jpg'.

        .PARAMETER DestinationPath
        Optional folder for the output file. Defaults to the source file's folder.

        .PARAMETER Force
        Allows overwriting an existing output file instead of throwing an error.

        .EXAMPLE
        Resolve-ImageConverterOutputPath -SourcePath 'C:\Pictures\IMG_1234.HEIC' -Extension '.jpg'
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
        $DestinationPath,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    if ([System.String]::IsNullOrEmpty($DestinationPath))
    {
        $folder = [System.IO.Path]::GetDirectoryName($SourcePath)
    }
    else
    {
        $folder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)
    }

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath) + $Extension
    $targetPath = Join-Path -Path $folder -ChildPath $fileName

    if ((Test-Path -LiteralPath $targetPath) -and -not $Force)
    {
        throw [System.IO.IOException]::new("The file '$targetPath' already exists. Use -Force to overwrite it.")
    }

    return $targetPath
}
