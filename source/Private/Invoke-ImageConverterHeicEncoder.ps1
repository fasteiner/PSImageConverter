function Invoke-ImageConverterHeicEncoder
{
    <#
        .SYNOPSIS
        Encodes a prepared MagickImage as HEIC with the encoder of the operating system.

        .DESCRIPTION
        Magick.NET cannot write HEIC, so Convert-ImageConverterImage hands the image to this function
        after all its steps (orientation, colour profiles, -StripMetadata, flattening where the
        encoder stores no alpha). It converts the pixels of an image in another colour space than sRGB
        or grey (e.g. Lab) to sRGB, takes the pixels as 8-bit RGB, or RGBA when the image has
        transparent pixels, the ICC profile when it is an RGB profile, the EXIF block with its
        orientation set to 1 in place (PSImageConverter.ExifOrientation; the pixels are upright, and
        rewriting the block could move data that other tags point to) and the XMP packet, and passes
        them to PSImageConverter.HeicEncoder. Returns an object with Result (the bytes of the HEIC
        file) and Exception (why the encoder or the pixel export failed); exactly one of them is set,
        as Invoke-ImageConverterMethod returns them.

        .PARAMETER Image
        The MagickImage to encode, after the conversion steps; its colour space may be changed to sRGB.

        .PARAMETER Quality
        The quality from 1 (smallest file) to 100 (best quality) that the encoder maps to its scale.

        .EXAMPLE
        $encoded = Invoke-ImageConverterHeicEncoder -Image $image -Quality 90

        Returns the HEIC bytes in $encoded.Result, or the failure in $encoded.Exception.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ImageMagick.MagickImage]
        $Image,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 100)]
        [System.Int32]
        $Quality
    )

    # The pixels are exported as stored; grey ones come out with three equal channels.
    if ($Image.ColorSpace -notin @([ImageMagick.ColorSpace]::sRGB, [ImageMagick.ColorSpace]::Gray))
    {
        $Image.ColorSpace = [ImageMagick.ColorSpace]::sRGB
    }

    $mapping = 'RGB'
    if ($Image.HasAlpha -and -not $Image.IsOpaque)
    {
        $mapping = 'RGBA'
    }

    $pixelCollection = $Image.GetPixelsUnsafe()
    try
    {
        $pixels = Invoke-ImageConverterMethod -InputObject $pixelCollection -Name 'ToByteArray' -ArgumentList $mapping
    }
    finally
    {
        $pixelCollection.Dispose()
    }

    if ($null -ne $pixels.Exception)
    {
        return $pixels
    }

    $iccProfile = $null
    $colorProfile = $Image.GetColorProfile()
    if ($null -ne $colorProfile -and $colorProfile.ColorSpace -eq [ImageMagick.ColorSpace]::sRGB)
    {
        $iccProfile = $colorProfile.ToByteArray()
    }

    $exif = $null
    $exifProfile = $Image.GetExifProfile()
    if ($null -ne $exifProfile)
    {
        $exif = [PSImageConverter.ExifOrientation]::SetTopLeft($exifProfile.ToByteArray())
    }

    $xmp = $null
    $xmpProfile = $Image.GetXmpProfile()
    if ($null -ne $xmpProfile)
    {
        $xmp = $xmpProfile.ToByteArray()
    }

    # Magick.NET reports the size as UInt32; the reflection call converts no argument types.
    $encodeArguments = @([System.Int32] $Image.Width, [System.Int32] $Image.Height, $pixels.Result, $mapping.Length, $Quality, $iccProfile, $exif, $xmp)

    Invoke-ImageConverterMethod -Type ([PSImageConverter.HeicEncoder]) -Name 'Encode' -ArgumentList $encodeArguments
}
