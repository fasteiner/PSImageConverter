function Convert-PSHeicImage
{
    <#
        .SYNOPSIS
        Converts a single image file with Magick.NET.

        .DESCRIPTION
        Reads the source image, applies the EXIF orientation to the pixels
        (auto-orient), optionally strips all metadata, sets the quality for lossy
        output formats and writes the image in the requested format.

        .PARAMETER SourcePath
        The full path of the image file to read.

        .PARAMETER TargetPath
        The full path of the image file to write.

        .PARAMETER Format
        The Magick.NET format name of the output, e.g. Jpeg, Png or WebP.

        .PARAMETER Quality
        The quality (1-100) applied to lossy output formats (Jpeg, WebP, Avif).

        .PARAMETER StripMetadata
        Removes all profiles and comments (EXIF, XMP, ICC, ...) from the output.

        .EXAMPLE
        Convert-PSHeicImage -SourcePath 'C:\Pictures\IMG_1234.HEIC' -TargetPath 'C:\Pictures\IMG_1234.jpg' -Format Jpeg -Quality 90
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $SourcePath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $TargetPath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Format,

        [Parameter()]
        [ValidateRange(1, 100)]
        [System.Int32]
        $Quality = 90,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $StripMetadata
    )

    $image = [ImageMagick.MagickImage]::new($SourcePath)

    try
    {
        $image.AutoOrient()

        if ($StripMetadata)
        {
            $image.Strip()
        }

        if ($Format -in @('Jpeg', 'WebP', 'Avif'))
        {
            $image.Quality = [System.UInt32] $Quality
        }

        $image.Write($TargetPath, [ImageMagick.MagickFormat] $Format)
    }
    finally
    {
        $image.Dispose()
    }
}
