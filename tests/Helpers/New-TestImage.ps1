<#
    Test fixture factory, dot-sourced by the unit tests after the module is imported (it needs the
    Magick.NET types the module loads). tests/assets/sample.heic carries no metadata, so the tests
    that check EXIF, XMP, IPTC, comments and ICC profiles create their sources with this function.
#>
function New-TestImage
{
    <#
        .SYNOPSIS
        Writes a small test image with the requested metadata.

        .PARAMETER Path
        The file to write. The content format comes from -Format, not from the extension.

        .PARAMETER Format
        The Magick.NET format of the content, e.g. Jpeg or Png.

        .PARAMETER Width
        The width of the image in pixels.

        .PARAMETER Height
        The height of the image in pixels.

        .PARAMETER Exif
        Adds an EXIF profile with camera make and model, date taken and a GPS tag.

        .PARAMETER Orientation
        Adds the EXIF orientation tag with this value (1-8); implies -Exif.

        .PARAMETER ColorProfile
        Adds the Adobe RGB (1998) ICC colour profile, a wide-gamut profile like Display P3.

        .PARAMETER Xmp
        Adds an XMP profile with a dc:creator entry.

        .PARAMETER Iptc
        Adds an IPTC profile with a byline entry.

        .PARAMETER Comment
        Adds this text as image comment.

        .PARAMETER Color
        The colour every pixel gets, e.g. '#C03C3B'.

        .PARAMETER Cmyk
        Converts the pixels to CMYK with the U.S. Web Coated (SWOP) profile, which is embedded.

        .PARAMETER ExifThumbnail
        Writes the EXIF data the way cameras do, with a 16x8 thumbnail in IFD1 that is stored in
        the orientation of the pixels. Only for -Format Jpeg; uses -Orientation and adds Make.

        .PARAMETER XmpOrientation
        Adds an XMP packet with tiff:Orientation set to -Orientation and exif:PixelXDimension /
        exif:PixelYDimension set to the stored size, as Lightroom and Photoshop exports have.
    #>
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [System.String]
        $Format = 'Jpeg',

        [Parameter()]
        [System.Int32]
        $Width = 64,

        [Parameter()]
        [System.Int32]
        $Height = 48,

        [Parameter()]
        [System.String]
        $Color = '#4080C0',

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Cmyk,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $ExifThumbnail,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $XmpOrientation,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Exif,

        [Parameter()]
        [System.UInt16]
        $Orientation,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $ColorProfile,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Xmp,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Iptc,

        [Parameter()]
        [System.String]
        $Comment
    )

    $image = [ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new($Color), [System.UInt32] $Width, [System.UInt32] $Height)

    try
    {
        if ($ColorProfile)
        {
            $image.SetProfile([ImageMagick.ColorProfiles]::AdobeRGB1998)
        }

        if ($Cmyk)
        {
            $null = $image.TransformColorSpace([ImageMagick.ColorProfiles]::SRGB, [ImageMagick.ColorProfiles]::USWebCoatedSWOP)
        }

        if ($ExifThumbnail)
        {
            <#
                Magick.NET drops IFD1 when it writes an EXIF profile, so the APP1 segment is built by
                hand and inserted after the JPEG start marker: a little-endian TIFF structure with IFD0
                (Orientation, Make) and IFD1 (offset and length of the thumbnail JPEG behind it).
            #>
            $thumbnailImage = [ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new('#FF0000'), 16, 8)
            try
            {
                $thumbnail = $thumbnailImage.ToByteArray([ImageMagick.MagickFormat]::Jpeg)
            }
            finally
            {
                $thumbnailImage.Dispose()
            }

            $tiffStream = [System.IO.MemoryStream]::new()
            $writer = [System.IO.BinaryWriter]::new($tiffStream)
            $writer.Write([System.Byte[]] @(0x49, 0x49, 0x2A, 0x00))
            $writer.Write([System.UInt32] 8)
            # IFD0 at 8: 2 entries end at 38, the Make string follows at 38, IFD1 at 46 ends at 76.
            $writer.Write([System.UInt16] 2)
            $writer.Write([System.UInt16] 0x0112)
            $writer.Write([System.UInt16] 3)
            $writer.Write([System.UInt32] 1)
            $writer.Write([System.UInt16] ([System.Math]::Max(1, [System.Int32] $Orientation)))
            $writer.Write([System.UInt16] 0)
            $writer.Write([System.UInt16] 0x010F)
            $writer.Write([System.UInt16] 2)
            $writer.Write([System.UInt32] 8)
            $writer.Write([System.UInt32] 38)
            $writer.Write([System.UInt32] 46)
            $writer.Write([System.Text.Encoding]::ASCII.GetBytes("TestCam`0"))
            $writer.Write([System.UInt16] 2)
            $writer.Write([System.UInt16] 0x0201)
            $writer.Write([System.UInt16] 4)
            $writer.Write([System.UInt32] 1)
            $writer.Write([System.UInt32] 76)
            $writer.Write([System.UInt16] 0x0202)
            $writer.Write([System.UInt16] 4)
            $writer.Write([System.UInt32] 1)
            $writer.Write([System.UInt32] $thumbnail.Length)
            $writer.Write([System.UInt32] 0)
            $writer.Write($thumbnail)
            $writer.Flush()

            $exifData = [System.Text.Encoding]::ASCII.GetBytes("Exif`0`0") + $tiffStream.ToArray()
            $segmentLength = $exifData.Length + 2
            $jpeg = $image.ToByteArray([ImageMagick.MagickFormat]::Jpeg)
            $segment = [System.Byte[]] @(0xFF, 0xE1, [System.Byte] ($segmentLength -shr 8), [System.Byte] ($segmentLength -band 0xFF)) + $exifData
            [System.IO.File]::WriteAllBytes($Path, [System.Byte[]] ($jpeg[0..1] + $segment + $jpeg[2..($jpeg.Length - 1)]))

            return Get-Item -LiteralPath $Path -Force
        }

        if ($XmpOrientation)
        {
            $packet = '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?><x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:tiff="http://ns.adobe.com/tiff/1.0/" xmlns:exif="http://ns.adobe.com/exif/1.0/" tiff:Orientation="{0}" exif:PixelXDimension="{1}" exif:PixelYDimension="{2}"/></rdf:RDF></x:xmpmeta><?xpacket end="w"?>' -f $Orientation, $Width, $Height
            $image.SetProfile([ImageMagick.XmpProfile]::new([System.Text.Encoding]::UTF8.GetBytes($packet)))
        }

        if ($Exif -or $Orientation)
        {
            $exifProfile = [ImageMagick.ExifProfile]::new()
            $exifProfile.SetValue([ImageMagick.ExifTag]::Make, 'TestCam Inc.')
            $exifProfile.SetValue([ImageMagick.ExifTag]::Model, 'Model X-100')
            $exifProfile.SetValue([ImageMagick.ExifTag]::DateTimeOriginal, '2024:05:17 13:45:30')
            $exifProfile.SetValue([ImageMagick.ExifTag]::GPSLatitudeRef, 'N')

            if ($Orientation)
            {
                $exifProfile.SetValue([ImageMagick.ExifTag]::Orientation, $Orientation)
                $image.Orientation = [ImageMagick.OrientationType] $Orientation
            }

            $image.SetProfile($exifProfile)
        }

        if ($Xmp)
        {
            $packet = '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?><x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>XmpTester</dc:creator></rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end="w"?>'
            $image.SetProfile([ImageMagick.XmpProfile]::new([System.Text.Encoding]::UTF8.GetBytes($packet)))
        }

        if ($Iptc)
        {
            $iptcProfile = [ImageMagick.IptcProfile]::new()
            $iptcProfile.SetValue([ImageMagick.IptcTag]::Byline, 'IptcTester')
            $image.SetProfile($iptcProfile)
        }

        if ($Comment)
        {
            $image.Comment = $Comment
        }

        $image.Write($Path, [ImageMagick.MagickFormat] $Format)
    }
    finally
    {
        $image.Dispose()
    }

    Get-Item -LiteralPath $Path -Force
}
