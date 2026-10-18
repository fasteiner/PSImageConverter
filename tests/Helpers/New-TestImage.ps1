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

        .DESCRIPTION
        Writes a solid -Width x -Height image in -Color with the metadata the switches ask for
        (EXIF, an EXIF orientation, the Adobe RGB ICC profile, grey pixels with a grey ICC
        profile, XMP, IPTC, a comment, CMYK pixels, a camera-style EXIF thumbnail or an XMP
        orientation) and returns the file as Get-Item returns it.

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

        .PARAMETER GrayColorProfile
        Stores the pixels as grey (one channel in JPEG, PNG and TIFF) and adds the grey ICC
        profile of Get-TestGrayColorProfile (gamma 1.8), as Photoshop greyscale exports and
        scanned greyscale images have. Grey 128 shows as about 146 in a colour-managed viewer.

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

        .EXAMPLE
        New-TestImage -Path (Join-Path -Path $tempDir -ChildPath 'rich.jpg') -Exif -ColorProfile -Comment 'secret'

        Writes a JPEG with EXIF data, the Adobe RGB profile and a comment.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture factory: writes a file into the temporary folder of a test.')]
    [CmdletBinding()]
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
        $GrayColorProfile,

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

        if ($GrayColorProfile)
        {
            $image.ColorSpace = [ImageMagick.ColorSpace]::Gray
            $image.SetProfile((Get-TestGrayColorProfile))
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

function New-TestFrameImage
{
    <#
        .SYNOPSIS
        Writes an image file with several frames, e.g. an animated GIF or a multi-page TIFF.

        .DESCRIPTION
        Writes -FrameCount solid 16x16 frames in the colours red, green and blue (repeated),
        so a test can check that the first frame is the one that is converted.

        .PARAMETER Path
        The file to write. The content format comes from -Format, not from the extension.

        .PARAMETER Format
        The Magick.NET format of the content, e.g. Gif, WebP, Tiff or Psd.

        .PARAMETER FrameCount
        The number of frames to write.

        .PARAMETER Keep
        The fraction of the encoded bytes that is written, e.g. 0.8 to cut the file off like an
        interrupted copy. ImageMagick still reads the first frame of such a GIF, but cannot
        count the frames any more. Default 1 (the whole file).

        .EXAMPLE
        New-TestFrameImage -Path (Join-Path -Path $tempDir -ChildPath 'anim.gif') -Format Gif -FrameCount 3

        Writes an animated GIF with a red, a green and a blue frame.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture factory: writes a file into the temporary folder of a test.')]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [System.String]
        $Format = 'Gif',

        [Parameter()]
        [System.Int32]
        $FrameCount = 3,

        [Parameter()]
        [System.Double]
        $Keep = 1
    )

    $colors = @('#FF0000', '#00FF00', '#0000FF')
    $frames = [ImageMagick.MagickImageCollection]::new()

    try
    {
        foreach ($index in 0..($FrameCount - 1))
        {
            $frame = [ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new($colors[$index % 3]), 16, 16)
            $frame.AnimationDelay = 10
            $frames.Add($frame)
        }

        $frames.Write($Path, [ImageMagick.MagickFormat] $Format)
    }
    finally
    {
        $frames.Dispose()
    }

    if ($Keep -lt 1)
    {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        [System.IO.File]::WriteAllBytes($Path, [System.Byte[]] $bytes[0..([System.Int32] ($bytes.Length * $Keep) - 1)])
    }

    Get-Item -LiteralPath $Path -Force
}

function New-TestTransparentImage
{
    <#
        .SYNOPSIS
        Writes a 48x16 RGBA PNG with a fully transparent, a half transparent and an opaque block.

        .DESCRIPTION
        The three 16x16 blocks are, from left to right: transparent black (#00000000), red with
        alpha 128 (#FF000080) and opaque blue. Black under the transparency is what a JPEG
        encoder shows when it drops the alpha channel. Sample the blocks at x = 8, 24 and 40.
        With -Cmyk the pixels are converted to CMYK through the U.S. Web Coated (SWOP) profile
        and written as TIFF, the way print cut-outs are stored; the alpha channel is kept.

        .PARAMETER Path
        The file to write: a PNG, or a TIFF with -Cmyk.

        .PARAMETER Cmyk
        Writes a CMYK TIFF with alpha instead of the RGBA PNG, with the SWOP profile embedded.

        .PARAMETER WithoutColorProfile
        With -Cmyk: leaves the SWOP profile out of the file, so readers have to assume one.

        .EXAMPLE
        New-TestTransparentImage -Path (Join-Path -Path $tempDir -ChildPath 'logo.png')

        Writes logo.png with the three blocks.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture factory: writes a file into the temporary folder of a test.')]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Cmyk,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $WithoutColorProfile
    )

    $blocks = [ImageMagick.MagickImageCollection]::new()

    try
    {
        foreach ($color in @('#00000000', '#FF000080', '#0000FFFF'))
        {
            $blocks.Add([ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new($color), 16, 16))
        }

        $image = $blocks.AppendHorizontally()
        try
        {
            if ($Cmyk)
            {
                $null = $image.TransformColorSpace([ImageMagick.ColorProfiles]::SRGB, [ImageMagick.ColorProfiles]::USWebCoatedSWOP)
                if ($WithoutColorProfile)
                {
                    $image.RemoveProfile('icc')
                }

                $image.Write($Path, [ImageMagick.MagickFormat]::Tiff)
            }
            else
            {
                # As 8-bit RGBA, so every block keeps its exact alpha; New-TestPaletteImage writes the palette case.
                $image.Write($Path, [ImageMagick.MagickFormat]::Png32)
            }
        }
        finally
        {
            $image.Dispose()
        }
    }
    finally
    {
        $blocks.Dispose()
    }

    Get-Item -LiteralPath $Path -Force
}

function New-TestPaletteImage
{
    <#
        .SYNOPSIS
        Writes a palette PNG with -ColorCount colours and a half-transparent band, like a small logo.

        .DESCRIPTION
        Writes one 16x16 block per colour (#C83C3C, #3C3CC8, #4080C0, #00C800, #FFA500, from left
        to right) whose rows 12 to 15 have alpha 128. ImageMagick's PNG encoder stores it as a
        palette PNG whose bit depth follows the number of palette entries (two per colour): 1 bit
        for one colour, 2 bits for two, 4 bits for three to eight. Sample a block at y = 8
        (opaque) and y = 14 (alpha 128).

        .PARAMETER Path
        The PNG file to write.

        .PARAMETER ColorCount
        The number of colours (1 to 5); the palette has twice as many entries.

        .EXAMPLE
        New-TestPaletteImage -Path (Join-Path -Path $tempDir -ChildPath 'logo.png') -ColorCount 2

        Writes a 2-bit palette PNG with two colours, each opaque and half transparent.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture factory: writes a file into the temporary folder of a test.')]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [ValidateRange(1, 5)]
        [System.Int32]
        $ColorCount = 2
    )

    $colors = @('#C83C3C', '#3C3CC8', '#4080C0', '#00C800', '#FFA500')
    $blocks = [ImageMagick.MagickImageCollection]::new()

    try
    {
        foreach ($color in $colors[0..($ColorCount - 1)])
        {
            $blocks.Add([ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new($color), 16, 16))
        }

        $image = $blocks.AppendHorizontally()
        try
        {
            $image.Alpha([ImageMagick.AlphaOption]::Set)
            $pixels = $image.GetPixels()
            for ($x = 0; $x -lt $image.Width; $x++)
            {
                for ($y = 12; $y -lt 16; $y++)
                {
                    $value = $pixels.GetValue($x, $y)
                    $value[3] = 128
                    $pixels.SetPixel($x, $y, $value)
                }
            }

            $image.Write($Path, [ImageMagick.MagickFormat]::Png)
        }
        finally
        {
            $image.Dispose()
        }
    }
    finally
    {
        $blocks.Dispose()
    }

    Get-Item -LiteralPath $Path -Force
}

function Get-TestGrayColorProfile
{
    <#
        .SYNOPSIS
        Returns a minimal ICC colour profile for grey pixels (gamma 1.8) as a Magick.NET ColorProfile.

        .DESCRIPTION
        Magick.NET ships no grey profile, so an ICC version 2 display profile is built byte by
        byte: the 128-byte header (device class mntr, data colour space GRAY, connection space
        XYZ, D50 illuminant) and the tags desc ('Gray Gamma 1.8 (test)'), wtpt (D50), kTRC (a
        gamma curve of 1.8) and cprt. lcms accepts it, so ImageMagick converts grey pixels
        through it: grey 128 becomes about 146 in sRGB.

        .EXAMPLE
        $grayProfile = Get-TestGrayColorProfile

        Returns the profile; $grayProfile.ToByteArray() gives the ICC data.
    #>
    [CmdletBinding()]
    [OutputType([ImageMagick.ColorProfile])]
    param ()

    $ascii = [System.Text.Encoding]::ASCII

    # ICC numbers are big-endian; s15Fixed16 is a 32-bit number with 16 fraction bits.
    $bigEndian32 = {
        param ([System.Int64] $Value)

        $bytes = [System.BitConverter]::GetBytes([System.UInt32] ($Value -band 0xFFFFFFFFL))
        [System.Array]::Reverse($bytes)
        , $bytes
    }
    $xyz = {
        param ([System.Double[]] $Values)

        $bytes = [System.Collections.Generic.List[System.Byte]]::new()
        $bytes.AddRange($ascii.GetBytes('XYZ '))
        $bytes.AddRange([System.Byte[]]::new(4))
        foreach ($value in $Values)
        {
            $bytes.AddRange((& $bigEndian32 ([System.Int64] [System.Math]::Round($value * 65536))))
        }
        , $bytes.ToArray()
    }

    $description = 'Gray Gamma 1.8 (test)'
    $descriptionTag = [System.Collections.Generic.List[System.Byte]]::new()
    $descriptionTag.AddRange($ascii.GetBytes('desc'))
    $descriptionTag.AddRange([System.Byte[]]::new(4))
    $descriptionTag.AddRange((& $bigEndian32 ($description.Length + 1)))
    $descriptionTag.AddRange($ascii.GetBytes($description))
    # The ASCII terminator, then empty Unicode (language code, count) and ScriptCode (code, count, 67 bytes) parts.
    $descriptionTag.AddRange([System.Byte[]]::new(1 + 8 + 3 + 67))

    $tags = [ordered] @{
        desc = $descriptionTag.ToArray()
        wtpt = & $xyz @(0.9642, 1.0, 0.8249)
        # curveType with one entry: the gamma as u8Fixed8Number, 1.8 * 256 = 461.
        kTRC = $ascii.GetBytes('curv') + [System.Byte[]]::new(4) + (& $bigEndian32 1) + [System.Byte[]] @(0x01, 0xCD)
        cprt = $ascii.GetBytes('text') + [System.Byte[]]::new(4) + $ascii.GetBytes("No copyright, test profile`0")
    }

    $table = [System.Collections.Generic.List[System.Byte]]::new()
    $data = [System.Collections.Generic.List[System.Byte]]::new()
    $dataOffset = 128 + 4 + 12 * $tags.Count
    $table.AddRange((& $bigEndian32 $tags.Count))
    foreach ($signature in $tags.Keys)
    {
        # Every tag starts on a 4-byte boundary.
        while ($data.Count % 4 -ne 0)
        {
            $data.Add(0)
        }

        $table.AddRange($ascii.GetBytes($signature))
        $table.AddRange((& $bigEndian32 ($dataOffset + $data.Count)))
        $table.AddRange((& $bigEndian32 $tags[$signature].Length))
        $data.AddRange([System.Byte[]] $tags[$signature])
    }

    while ($data.Count % 4 -ne 0)
    {
        $data.Add(0)
    }

    $header = [System.Collections.Generic.List[System.Byte]]::new()
    $header.AddRange((& $bigEndian32 (128 + $table.Count + $data.Count)))
    $header.AddRange($ascii.GetBytes('lcms'))
    $header.AddRange([System.Byte[]] @(2, 0x10, 0, 0))
    $header.AddRange($ascii.GetBytes('mntrGRAYXYZ '))
    # Creation date 2026-10-18 12:00:00 as six 16-bit numbers.
    $header.AddRange([System.Byte[]] @(0x07, 0xEA, 0, 10, 0, 18, 0, 12, 0, 0, 0, 0))
    $header.AddRange($ascii.GetBytes('acspMSFT'))
    # Flags, manufacturer, model, attributes and rendering intent are 0.
    $header.AddRange([System.Byte[]]::new(4 + 4 + 4 + 8 + 4))
    $header.AddRange([System.Byte[]] (& $xyz @(0.9642, 1.0, 0.8249))[8..19])
    # Creator, profile id and the reserved bytes are 0.
    $header.AddRange([System.Byte[]]::new(4 + 16 + 28))

    [ImageMagick.ColorProfile]::new([System.Byte[]] ($header.ToArray() + $table.ToArray() + $data.ToArray()))
}

function Add-TestJpegColorProfile
{
    <#
        .SYNOPSIS
        Inserts ICC profile data into a JPEG file as APP2 segment, without changing the pixels.

        .DESCRIPTION
        Writes the bytes as one 'ICC_PROFILE' APP2 segment right after the start marker of the
        JPEG file, the way cameras store a profile. Magick.NET would convert the pixels or
        refuse a profile that does not match them, so a profile made for other pixels (a grey
        profile in a colour JPEG) or a damaged profile is inserted this way. The profile has
        to fit into one segment (less than 64 KB).

        .PARAMETER Path
        The JPEG file to change; it must not have an ICC profile yet.

        .PARAMETER ColorProfile
        The ICC profile data to insert.

        .EXAMPLE
        Add-TestJpegColorProfile -Path $jpeg.FullName -ColorProfile (Get-TestGrayColorProfile).ToByteArray()

        Tags a colour JPEG with a grey profile.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture factory: changes a file in the temporary folder of a test.')]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [System.Byte[]]
        $ColorProfile
    )

    # The payload is the name, the sequence number 1 of 1 segments and the profile data.
    $payload = [System.Text.Encoding]::ASCII.GetBytes("ICC_PROFILE`0") + [System.Byte[]] @(1, 1) + $ColorProfile
    $length = $payload.Length + 2
    $segment = [System.Byte[]] @(0xFF, 0xE2, [System.Byte] ($length -shr 8), [System.Byte] ($length -band 0xFF)) + $payload
    $jpeg = [System.IO.File]::ReadAllBytes($Path)
    [System.IO.File]::WriteAllBytes($Path, [System.Byte[]] ($jpeg[0..1] + $segment + $jpeg[2..($jpeg.Length - 1)]))

    Get-Item -LiteralPath $Path -Force
}

function New-TestDamagedJpeg
{
    <#
        .SYNOPSIS
        Writes a JPEG file that is cut off, as after an interrupted copy or download.

        .DESCRIPTION
        Encodes a 320x240 gradient as JPEG and writes only the first part of it (-Keep, a
        fraction of the bytes), or the whole file without its 2-byte end marker (FF D9) with
        -WithoutEndMarker. ImageMagick reads both with a MagickCorruptImageWarningException
        instead of an error; the missing rows of a cut file are filled in grey. The encoding is
        the same in every call, so -Keep 1 writes the complete file to compare with.

        .PARAMETER Path
        The file to write.

        .PARAMETER Keep
        The fraction of the encoded bytes that is written, e.g. 0.6 for 60 %; 1 writes all.

        .PARAMETER WithoutEndMarker
        Writes the complete image data and leaves out only the end marker.

        .EXAMPLE
        New-TestDamagedJpeg -Path (Join-Path -Path $tempDir -ChildPath 'cut.jpg') -Keep 0.6

        Writes the first 60 % of the JPEG file.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture factory: writes a file into the temporary folder of a test.')]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [System.Double]
        $Keep = 0.6,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $WithoutEndMarker
    )

    $image = [ImageMagick.MagickImage]::new('gradient:red-blue', 320, 240)
    try
    {
        $jpeg = $image.ToByteArray([ImageMagick.MagickFormat]::Jpeg)
    }
    finally
    {
        $image.Dispose()
    }

    $length = [System.Int32] ($jpeg.Length * $Keep)
    if ($WithoutEndMarker)
    {
        $length = $jpeg.Length - 2
    }

    [System.IO.File]::WriteAllBytes($Path, [System.Byte[]] $jpeg[0..($length - 1)])

    Get-Item -LiteralPath $Path -Force
}

function Get-TestStoredColorLayout
{
    <#
        .SYNOPSIS
        Reads from the bytes of an image file how it stores its pixels and which ICC profile it embeds.

        .DESCRIPTION
        Returns Channels ('Grey', 'RGB' or 'CMYK': how the file stores the pixels) and
        ProfileSpace (the data colour space of the embedded ICC profile, 'GRAY', 'RGB' or
        'CMYK', or $null without a profile), read from the file structure, not through
        ImageMagick, whose readback reports grey files of some formats as sRGB. Supported:
        JPEG (SOF components, APP2 ICC_PROFILE), PNG (IHDR colour type, iCCP), WebP (ICCP;
        always RGB), AVIF (av1C mono_chrome, colr 'prof'), TIFF (PhotometricInterpretation,
        tag 34675), BMP (V5 header with an embedded profile; always RGB) and GIF (ICCRGBG1
        application extension; always RGB). JPEG XL is not supported: its colour encoding is
        stored in a bit-packed header.

        .PARAMETER Path
        The image file to inspect; its format is detected from the first bytes.

        .EXAMPLE
        Get-TestStoredColorLayout -Path $result.FullName

        Returns e.g. Channels RGB and ProfileSpace GRAY for a WebP that stores grey pixels as
        RGB with a grey profile.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $data = [System.IO.File]::ReadAllBytes($Path)
    $ascii = [System.Text.Encoding]::ASCII
    $bigEndian32 = {
        param ([System.Int64] $Offset)

        ([System.Int64] $data[$Offset] -shl 24) -bor ([System.Int64] $data[$Offset + 1] -shl 16) -bor ([System.Int64] $data[$Offset + 2] -shl 8) -bor [System.Int64] $data[$Offset + 3]
    }
    $channels = 'RGB'
    $iccData = $null

    if ($data[0] -eq 0xFF -and $data[1] -eq 0xD8)
    {
        $segments = [System.Collections.Generic.List[System.Byte]]::new()
        $position = 2
        while ($position + 4 -le $data.Length -and $data[$position] -eq 0xFF)
        {
            $marker = $data[$position + 1]
            $length = ([System.Int32] $data[$position + 2] -shl 8) -bor $data[$position + 3]
            if ($marker -eq 0xE2 -and $ascii.GetString($data, $position + 4, 11) -eq 'ICC_PROFILE')
            {
                # The name (12 bytes) and the sequence numbers (2 bytes) come before the profile data of each segment.
                $segments.AddRange([System.Byte[]] $data[($position + 18)..($position + 1 + $length)])
            }
            elseif ($marker -in @(0xC0, 0xC1, 0xC2))
            {
                $channels = @{ 1 = 'Grey'; 3 = 'RGB'; 4 = 'CMYK' }[[System.Int32] $data[$position + 9]]
            }
            elseif ($marker -eq 0xDA)
            {
                break
            }

            $position += 2 + $length
        }

        if ($segments.Count -gt 0)
        {
            $iccData = $segments.ToArray()
        }
    }
    elseif ($ascii.GetString($data, 1, 3) -eq 'PNG')
    {
        # The colour type is byte 25: 0 grey, 4 grey with alpha, 2 RGB, 6 RGBA, 3 a palette of RGB entries.
        if ($data[25] -in @(0, 4))
        {
            $channels = 'Grey'
        }

        $position = 8
        while ($position + 12 -le $data.Length)
        {
            $length = & $bigEndian32 $position
            if ($ascii.GetString($data, $position + 4, 4) -ceq 'iCCP')
            {
                # The keyword, a 0 byte and the compression method byte come before the zlib stream.
                $streamStart = [System.Array]::IndexOf($data, [System.Byte] 0, $position + 8) + 2
                $compressed = [System.IO.MemoryStream]::new($data, $streamStart, [System.Int32] ($position + 8 + $length - $streamStart))
                $inflater = [System.IO.Compression.ZLibStream]::new($compressed, [System.IO.Compression.CompressionMode]::Decompress)
                $inflated = [System.IO.MemoryStream]::new()
                $inflater.CopyTo($inflated)
                $inflater.Dispose()
                $iccData = $inflated.ToArray()
            }

            $position += 12 + $length
        }
    }
    elseif ($ascii.GetString($data, 0, 4) -eq 'RIFF' -and $ascii.GetString($data, 8, 4) -eq 'WEBP')
    {
        # VP8 stores YUV colour, VP8L ARGB; WebP has no grey mode.
        $position = 12
        while ($position + 8 -le $data.Length)
        {
            $length = [System.BitConverter]::ToUInt32($data, $position + 4)
            if ($ascii.GetString($data, $position, 4) -eq 'ICCP')
            {
                $iccData = [System.Byte[]] $data[($position + 8)..($position + 7 + $length)]
            }

            $position += 8 + $length + ($length % 2)
        }
    }
    elseif ($ascii.GetString($data, 4, 4) -eq 'ftyp')
    {
        # The item properties of a HEIF file: meta (a full box) > iprp > ipco. An image with alpha has a second, monochrome av1C.
        $findBox = {
            param ([System.Int64] $Start, [System.Int64] $End, [System.String] $Type)

            $boxPosition = $Start
            while ($boxPosition + 8 -le $End)
            {
                $boxSize = & $bigEndian32 $boxPosition
                if ($ascii.GetString($data, $boxPosition + 4, 4) -eq $Type)
                {
                    return [PSCustomObject] @{ Body = $boxPosition + 8; End = $boxPosition + $boxSize }
                }

                $boxPosition += $boxSize
            }
        }
        $meta = & $findBox 0 $data.Length 'meta'
        $iprp = & $findBox ($meta.Body + 4) $meta.End 'iprp'
        $ipco = & $findBox $iprp.Body $iprp.End 'ipco'
        $monochrome = [System.Collections.Generic.List[System.Boolean]]::new()
        $position = $ipco.Body
        while ($position + 8 -le $ipco.End)
        {
            $size = & $bigEndian32 $position
            $type = $ascii.GetString($data, $position + 4, 4)
            if ($type -eq 'av1C')
            {
                # Byte 2 of the configuration: tier, high bit depth, twelve bit, mono_chrome, ...
                $monochrome.Add((($data[$position + 10] -shr 4) -band 1) -eq 1)
            }
            elseif ($type -eq 'colr' -and $ascii.GetString($data, $position + 8, 4) -in @('prof', 'rICC'))
            {
                $iccData = [System.Byte[]] $data[($position + 12)..($position + $size - 1)]
            }

            $position += $size
        }

        if ($monochrome.Count -gt 0 -and $monochrome -notcontains $false)
        {
            $channels = 'Grey'
        }
    }
    elseif ($ascii.GetString($data, 0, 2) -in @('II', 'MM'))
    {
        $littleEndian = $data[0] -eq 0x49
        $read = {
            param ([System.Int64] $Offset, [System.Int32] $Size)

            $value = [System.Int64] 0
            for ($index = 0; $index -lt $Size; $index++)
            {
                $byteIndex = $Offset + $Size - 1 - $index
                if ($littleEndian)
                {
                    $byteIndex = $Offset + $index
                }

                $value = $value -bor ([System.Int64] $data[$byteIndex] -shl (8 * $index))
            }

            $value
        }
        $directory = & $read 4 4
        $entryCount = & $read $directory 2
        for ($entry = 0; $entry -lt $entryCount; $entry++)
        {
            $entryOffset = $directory + 2 + 12 * $entry
            $tag = & $read $entryOffset 2
            if ($tag -eq 262)
            {
                $channels = @{ 0 = 'Grey'; 1 = 'Grey'; 2 = 'RGB'; 3 = 'RGB'; 5 = 'CMYK' }[[System.Int32] (& $read ($entryOffset + 8) 2)]
            }
            elseif ($tag -eq 34675)
            {
                $count = & $read ($entryOffset + 4) 4
                $offset = & $read ($entryOffset + 8) 4
                $iccData = [System.Byte[]] $data[$offset..($offset + $count - 1)]
            }
        }
    }
    elseif ($ascii.GetString($data, 0, 2) -eq 'BM')
    {
        # A BITMAPV5HEADER (124 bytes) names an embedded profile with CSType 'MBED' (stored as 'DEBM'), offset and size relative to the header.
        if ([System.BitConverter]::ToUInt32($data, 14) -ge 124 -and $ascii.GetString($data, 70, 4) -eq 'DEBM')
        {
            $offset = 14 + [System.BitConverter]::ToUInt32($data, 126)
            $size = [System.BitConverter]::ToUInt32($data, 130)
            $iccData = [System.Byte[]] $data[$offset..($offset + $size - 1)]
        }
    }
    elseif ($ascii.GetString($data, 0, 3) -eq 'GIF')
    {
        # An application extension 'ICCRGBG1' '012' whose data sub-blocks hold the profile.
        $start = $ascii.GetString($data).IndexOf('ICCRGBG1012', [System.StringComparison]::Ordinal)
        if ($start -ge 0)
        {
            $blocks = [System.Collections.Generic.List[System.Byte]]::new()
            $position = $start + 11
            while ($data[$position] -ne 0)
            {
                $blocks.AddRange([System.Byte[]] $data[($position + 1)..($position + $data[$position])])
                $position += 1 + $data[$position]
            }

            $iccData = $blocks.ToArray()
        }
    }
    else
    {
        throw [System.NotSupportedException]::new("Not a JPEG, PNG, WebP, AVIF, TIFF, BMP or GIF file: $Path")
    }

    $profileSpace = $null
    if ($null -ne $iccData -and $iccData.Length -ge 20)
    {
        # The data colour space signature is at byte 16 of the ICC header.
        $profileSpace = $ascii.GetString($iccData, 16, 4).TrimEnd()
    }

    [PSCustomObject] @{
        Channels     = $channels
        ProfileSpace = $profileSpace
    }
}
