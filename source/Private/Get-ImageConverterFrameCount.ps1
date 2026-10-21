function Get-ImageConverterFrameCount
{
    <#
        .SYNOPSIS
        Counts the frames, pages or images of an image file without decoding their pixels.

        .DESCRIPTION
        Pings the file with Magick.NET, which reads only the headers of every frame, and
        returns an object with the properties Count and Exception. Count is the number of
        frames: the frames of an animated GIF or WebP, the pages of a multi-page TIFF or the
        top-level images of a HEIC file (a thumbnail does not count). A layered Photoshop file
        reads as the merged picture followed by one image per layer; the merged picture is the
        whole image, so it counts as 1. When the file cannot be pinged, Count is $null and
        Exception says why; an animated GIF that is cut off after its first frame, for
        example, gives a MagickCorruptImageErrorException although its first frame can be
        read. Takes the file name or an open stream, which is read from its beginning. No
        exception reaches the caller.

        .PARAMETER Source
        The full path of the image file, or a seekable stream with the file content.

        .EXAMPLE
        (Get-ImageConverterFrameCount -Source 'C:\Pictures\animation.gif').Count

        Returns 3 for an animated GIF with three frames.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Source
    )

    $frameCount = $null
    $exception = $null

    if ($Source -is [System.IO.Stream])
    {
        # The stream has been read to the end by the image read before.
        $exception = (Invoke-ImageConverterMethod -InputObject $Source -Name 'Seek' -ArgumentList ([System.Int64] 0), ([System.IO.SeekOrigin]::Begin)).Exception
    }

    $frames = [ImageMagick.MagickImageCollection]::new()

    try
    {
        if ($null -eq $exception)
        {
            $exception = (Invoke-ImageConverterMethod -InputObject $frames -Name 'Ping' -ArgumentList $Source).Exception
        }

        if ($null -eq $exception -and $frames.Count -gt 0)
        {
            $frameCount = $frames.Count

            if ($frames[0].Format -in @([ImageMagick.MagickFormat]::Psd, [ImageMagick.MagickFormat]::Psb))
            {
                $frameCount = 1
            }
        }
    }
    finally
    {
        $frames.Dispose()
    }

    [PSCustomObject] @{
        Count     = $frameCount
        Exception = $exception
    }
}
