function Read-ImageConverterImage
{
    <#
        .SYNOPSIS
        Reads an image file with Magick.NET and returns the image, its warnings or the exception.

        .DESCRIPTION
        Reads the first image of the file into a MagickImage and returns an object with the
        properties Result (the image, which the caller disposes), Exception (why it could not be
        read), Warnings (the warnings ImageMagick raised while reading, e.g. for a truncated
        JPEG, which is still read) and FrameCount; exactly one of Result and Exception is set,
        and no exception reaches the caller. An image that is not handed back is disposed,
        also when the pipeline is stopped. ImageMagick treats a file name that ends with a
        bracket expression such as 'scan[1]' as a frame selector and opens 'scan' instead, so
        such a file is read from a stream; the format is then detected from the content. Every
        other file is read by name, where ImageMagick also uses the extension for formats it
        cannot detect from the content.
        With CountFrames, FrameCount is the number of frames, pages or images in the file
        (animated GIF/WebP, multi-page TIFF, HEIC with several images), counted without
        decoding their pixels; otherwise, or when the file cannot be counted, it is $null. When
        the first frame can be read but the frames cannot be counted because a later frame is
        damaged (e.g. an animated GIF cut off after its first frame), the
        MagickCorruptImageErrorException of the count is added to Warnings.

        .PARAMETER Path
        The full path of the image file to read.

        .PARAMETER CountFrames
        Also counts the frames of the file, so the caller can tell that only the first is read.

        .EXAMPLE
        Read-ImageConverterImage -Path 'C:\Pictures\IMG_1234.HEIC' -CountFrames

        Returns an object whose Result property holds the decoded image and whose FrameCount is 1.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $CountFrames
    )

    $source = $Path
    $stream = $null

    if ([System.IO.Path]::GetFileName($Path).EndsWith(']'))
    {
        $open = Invoke-ImageConverterMethod -Type ([System.IO.FileStream]) -ArgumentList $Path, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::ReadWrite)

        if ($null -ne $open.Exception)
        {
            return [PSCustomObject] @{
                Result     = $null
                Exception  = $open.Exception
                Warnings   = @()
                FrameCount = $null
            }
        }

        $stream = $open.Result
        $source = $stream
    }

    $image = [ImageMagick.MagickImage]::new()
    $warnings = [System.Collections.Generic.List[ImageMagick.MagickException]]::new()
    $result = $null

    <#
        Magick.NET does not throw warnings; it raises this event while Read runs and returns the
        image. The handler gets the image and the WarningEventArgs as its two arguments.
    #>
    $warningHandler = [System.EventHandler[ImageMagick.WarningEventArgs]] {
        $warnings.Add($args[1].Exception)
    }.GetNewClosure()

    try
    {
        $image.add_Warning($warningHandler)
        $read = Invoke-ImageConverterMethod -InputObject $image -Name 'Read' -ArgumentList $source
        $image.remove_Warning($warningHandler)

        $frameCount = $null
        if ($null -eq $read.Exception -and $CountFrames)
        {
            $frames = Get-ImageConverterFrameCount -Source $source
            $frameCount = $frames.Count

            # The first frame was read, so a later frame is cut off or broken; ImageMagick raises no warning for it.
            if ($frames.Exception -is [ImageMagick.MagickCorruptImageErrorException])
            {
                $warnings.Add($frames.Exception)
            }
        }

        if ($null -eq $read.Exception)
        {
            $result = [PSCustomObject] @{
                Result     = $image
                Exception  = $null
                Warnings   = $warnings.ToArray()
                FrameCount = $frameCount
            }
        }
        else
        {
            $result = [PSCustomObject] @{
                Result     = $null
                Exception  = $read.Exception
                Warnings   = $warnings.ToArray()
                FrameCount = $null
            }
        }
    }
    finally
    {
        if ($null -ne $stream)
        {
            $stream.Dispose()
        }

        # Also when the pipeline is stopped while the frames are counted: an image that is not handed back is disposed here.
        if ($null -eq $result -or $null -eq $result.Result)
        {
            $image.Dispose()
        }
    }

    $result
}
