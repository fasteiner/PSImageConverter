function Convert-ImageConverterImage
{
    <#
        .SYNOPSIS
        Converts a single image file with Magick.NET (and HEIC output with the encoder of the
        operating system) and returns the written file.

        .DESCRIPTION
        Reads the first frame of the source image, applies the EXIF orientation to the pixels
        (auto-orient) and updates the metadata that still describes the stored orientation,
        leaves out an ICC profile that lcms cannot apply (damaged or of an unknown colour
        space), converts CMYK pixels to sRGB for formats that cannot store CMYK, converts the
        pixels of a source with an ICC profile that matches them (colour or grey) to sRGB for
        lossy Jxl output (Quality below 100), whose encoder stores no ICC profile, and grey
        pixels with a grey profile to sRGB for WebP, Avif, Heic, Bmp and Gif output, which store
        grey pixels as RGB; a grey JPEG XL source, which ImageMagick reads as sRGB, counts as
        grey. A profile made for other pixels (a grey profile in a colour image or the other way
        round) is left out of lossless Jxl output, which cannot be written with it, and a grey
        profile on colour pixels out of Avif and Bmp output, which browsers then show wrongly,
        out of Heic output, whose encoders get RGB pixels, and out of Jpeg, Png and Tiff output
        when the pixels are all neutral grey, which these formats store as grey. After the
        profile is replaced or left out, the icc:* properties that describe the source profile
        are removed. Optionally strips the metadata but keeps the ICC colour profile (the one
        left after these steps), flattens transparent pixels onto white for the formats without
        alpha (Jpeg, CMYK white for a CMYK image; Heic on Windows), writes Tiff output of an
        image with alpha with at least 8 bits per sample, sets the quality for lossy output
        formats and writes the image in the requested format; Png output gets the ICC profile
        only as iCCP chunk, and Png, Jpeg and Tiff output are stored as RGB when an RGB profile
        is kept for neutral grey pixels. Heic output is encoded by the encoder of the operating
        system (Invoke-ImageConverterHeicEncoder) from the pixels, the ICC profile, the EXIF
        block with orientation 1 and the XMP packet. The image is written into a temporary file
        in the target folder first, through a stream so neither ImageMagick nor the HEIC encoder
        sees the file name, and then moved over the target, so a failed or stopped conversion
        never leaves a truncated target file or the temporary file behind; the target folder is
        created when it does not exist. With Force, the ReadOnly and Hidden attributes of an
        existing target are cleared before it is replaced and restored when it cannot be
        replaced.
        Failures are written as non-terminating errors through the cmdlet passed in -Cmdlet:
        ImageReadFailed when the source cannot be read, ImageWriteFailed when the target cannot
        be written (also when the HEIC encoder rejects the image, e.g. a size it cannot encode).
        Warnings are written through the same cmdlet: when ImageMagick reports the source as
        damaged (it is converted anyway; a warning that the caller turns into a stop still
        disposes the decoded image), when the source has more than one frame and only the first
        is converted, and, for output formats that cannot carry EXIF data (Tiff, Bmp, Gif; Heic
        on macOS), when the source has EXIF data and StripMetadata is not set. Returns the
        written file as the FileSystem provider returns it (a FileInfo with PSPath), or nothing
        after a failure.

        .PARAMETER Cmdlet
        The $PSCmdlet of the public cmdlet that reports errors and warnings, e.g. Convert-Image.

        .PARAMETER SourcePath
        The full path of the image file to read.

        .PARAMETER TargetPath
        The full path of the image file to write.

        .PARAMETER Format
        The output format name as accepted by Convert-Image -Format, e.g. Jpeg or WebP.

        .PARAMETER Quality
        The quality (1-100) applied to lossy output formats (Jpeg, WebP, Avif, Heic, Jxl).

        .PARAMETER StripMetadata
        Removes EXIF, XMP, IPTC and comments from the output but keeps the ICC colour profile,
        except where the pixels are converted to sRGB instead (lossy Jxl; grey pixels with a
        grey profile in WebP, Avif, Heic, Bmp and Gif output) or the profile is left out (see
        the description: a profile that cannot be applied or one made for other pixels).

        .PARAMETER Force
        Replaces an existing target file, also when it is read-only or hidden.

        .EXAMPLE
        Convert-ImageConverterImage -Cmdlet $PSCmdlet -SourcePath 'C:\Pictures\IMG_1234.HEIC' -TargetPath 'C:\Pictures\IMG_1234.jpg' -Format 'Jpeg' -Quality 90

        Writes C:\Pictures\IMG_1234.jpg and returns its FileInfo.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]
        $Cmdlet,

        [Parameter(Mandatory = $true)]
        [System.String]
        $SourcePath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $TargetPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Jpeg', 'Png', 'WebP', 'Avif', 'Heic', 'Jxl', 'Tiff', 'Bmp', 'Gif')]
        [System.String]
        $Format,

        [Parameter()]
        [ValidateRange(1, 100)]
        [System.Int32]
        $Quality = 90,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $StripMetadata,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    $formatInfo = Get-ImageConverterFormatInfo -Format $Format

    $read = Read-ImageConverterImage -Path $SourcePath -CountFrames
    if ($null -ne $read.Exception)
    {
        Write-ImageConverterError -Cmdlet $Cmdlet -Exception $read.Exception -ErrorId 'ImageReadFailed' -Category 'InvalidData' -TargetObject $SourcePath -MessagePrefix "Cannot read image '$SourcePath'"
        return
    }

    $image = $read.Result

    <#
        With -WarningAction Stop the warning about a damaged source ends the call. The image is
        disposed then, too; the try block below cannot take the warning, because its catch would
        turn the stop into an ImageWriteFailed error.
    #>
    $warned = $false
    try
    {
        Write-ImageConverterReadWarning -Cmdlet $Cmdlet -Path $SourcePath -Warning $read.Warnings
        $warned = $true
    }
    finally
    {
        if (-not $warned)
        {
            $image.Dispose()
        }
    }

    $targetFolder = [System.IO.Path]::GetDirectoryName($TargetPath)

    # A short name that does not contain the target name stays within the file name length limit whenever the target does.
    $tempPath = [System.IO.Path]::Combine($targetFolder, ('.{0}.tmp' -f [System.Guid]::NewGuid().ToString('N').Substring(0, 16)))
    $stream = $null
    $clearedAttributes = $null
    $failure = $null
    $ignoredArguments = $null

    try
    {
        $hasExif = $null -ne $image.GetExifProfile()
        $storedOrientation = $image.Orientation
        $image.AutoOrient()

        if ($storedOrientation -notin @([ImageMagick.OrientationType]::TopLeft, [ImageMagick.OrientationType]::Undefined))
        {
            Repair-ImageConverterProfileOrientation -Image $image
        }

        $profileReplaced = $false
        if ($null -ne $image.GetColorProfile())
        {
            <#
                lcms cannot use a damaged profile (e.g. cut short) or one that names an unknown colour
                space: the PNG and lossless JPEG XL encoders fail with it, and Chrome and Edge do not
                display an Avif that carries it. Viewers ignore it in the source, so it is left out of
                every output. A conversion of one pixel shows whether lcms can use it.
            #>
            $probe = $image.CloneArea(0, 0, 1, 1)
            try
            {
                $probeTransform = Invoke-ImageConverterMethod -InputObject $probe -Name 'TransformColorSpace' -ArgumentList ([ImageMagick.ColorProfiles]::SRGB)
            }
            finally
            {
                $probe.Dispose()
            }

            if ($null -ne $probeTransform.Exception)
            {
                $image.RemoveProfile('icc')
                $profileReplaced = $true
                Write-Verbose -Message "The ICC colour profile cannot be applied ($($probeTransform.Exception.Message)), so it is left out of the $Format output: $SourcePath"
            }
        }

        $isSrgb = $false
        if (-not $formatInfo.SupportsCmyk -and $image.ColorSpace -eq [ImageMagick.ColorSpace]::CMYK)
        {
            <#
                The encoders of these formats convert CMYK with a plain formula and drop the CMYK
                profile, and the JPEG XL encoder stores C, M and Y as R, G and B. The conversion uses
                the embedded CMYK profile; the SWOP profile is used only for a source without one.
            #>
            $isSrgb = $image.TransformColorSpace([ImageMagick.ColorProfiles]::USWebCoatedSWOP, [ImageMagick.ColorProfiles]::SRGB)
        }

        $profileReplaced = $profileReplaced -or $isSrgb
        $sourceProfile = $image.GetColorProfile()
        if (-not $isSrgb -and $null -ne $sourceProfile)
        {
            $grayTypes = @([ImageMagick.ColorType]::Bilevel, [ImageMagick.ColorType]::Grayscale, [ImageMagick.ColorType]::GrayscaleAlpha)
            $profileIsGray = $sourceProfile.ColorSpace -eq [ImageMagick.ColorSpace]::Gray
            $imageIsGray = $image.ColorSpace -in @([ImageMagick.ColorSpace]::Gray, [ImageMagick.ColorSpace]::LinearGray)

            <#
                ImageMagick reads a grey JPEG XL with a grey profile (as Jxl -Quality 100 output of a grey
                source is) as sRGB with three equal channels. The format cannot carry a grey profile with
                colour pixels, so the pixels are grey; switching to the grey colour space changes no value.
            #>
            if ($profileIsGray -and -not $imageIsGray -and $image.Format -eq [ImageMagick.MagickFormat]::Jxl -and $image.DetermineColorType() -in $grayTypes)
            {
                $image.ColorSpace = [ImageMagick.ColorSpace]::Gray
                $imageIsGray = $true
            }

            $profileKind = 'colour'
            if ($profileIsGray)
            {
                $profileKind = 'grey'
            }

            $isLossyJxl = $Format -eq 'Jxl' -and $Quality -lt 100

            <#
                ImageMagick's JPEG XL encoder writes the ICC profile only for lossless output
                (quality 100). Lossy output is tagged sRGB without converting the pixels, so a
                wide-gamut photo (Adobe RGB, Display P3) would look washed out. WebP, Avif, Bmp and
                Gif store grey pixels as RGB, for which a grey profile is not valid: browsers show
                the raw grey levels of the WebP and Gif, Chrome and Edge do not display the Avif and
                Firefox renders the Bmp black. The HEIC encoders get RGB pixels as well. In both
                cases the pixels are converted to sRGB instead; colours outside sRGB are clipped.
            #>
            $toSrgbReason = $null
            if ($isLossyJxl)
            {
                $toSrgbReason = 'lossy Jxl output stores no ICC colour profile'
            }
            elseif ($profileIsGray -and -not $formatInfo.StoresGray)
            {
                $toSrgbReason = "$Format output stores grey pixels as RGB, for which a grey ICC colour profile is not valid"
            }

            if ($profileIsGray -ne $imageIsGray)
            {
                <#
                    A profile made for other pixels: viewers ignore a grey profile in a colour image, and
                    browsers apply an RGB profile to grey JPEG pixels, which WIC rejects. ImageMagick
                    would turn a colour image grey through a grey profile, so the pixels are written
                    unchanged. The JPEG XL encoder cannot write such a profile losslessly
                    (UnableToWriteImageData), and browsers do not show an Avif or Bmp whose colour pixels
                    carry a grey profile correctly (Chrome and Edge do not display the Avif and show
                    false colours for the Bmp, Firefox shows both grey), so the profile is left out of
                    these outputs, and out of Heic output, whose encoders get RGB pixels (ImageIO
                    cannot even create the image with it). The Jpeg, Png and Tiff encoders store colour
                    pixels that are all neutral grey as grey, for which the grey profile is valid and
                    would then be applied.
                #>
                if ($isLossyJxl)
                {
                    Write-Verbose -Message "The ICC colour profile is made for $profileKind pixels and does not match the image, so the colours are written unchanged: $SourcePath"
                }
                elseif ($Format -eq 'Jxl' -or ($profileIsGray -and $Format -in @('Avif', 'Heic', 'Bmp')) -or ($profileIsGray -and $Format -in @('Jpeg', 'Png', 'Tiff') -and $image.DetermineColorType() -in $grayTypes))
                {
                    $image.RemoveProfile('icc')
                    $profileReplaced = $true
                    Write-Verbose -Message "The ICC colour profile is made for $profileKind pixels and does not match the image, so it is left out of the $Format output: $SourcePath"
                }
            }
            elseif ($null -ne $toSrgbReason)
            {
                # The probe above has shown that lcms can use the profile.
                $transform = Invoke-ImageConverterMethod -InputObject $image -Name 'TransformColorSpace' -ArgumentList ([ImageMagick.ColorProfiles]::SRGB)
                $failure = $transform.Exception

                if ($transform.Result)
                {
                    $profileReplaced = $true
                    Write-Verbose -Message "Converted the colours to sRGB, because $($toSrgbReason): $SourcePath"
                }
            }
        }

        if ($profileReplaced)
        {
            # The properties read with the source profile (icc:description, icc:copyright, ...) would still name it; PNG output writes them as text chunks.
            foreach ($attributeName in @($image.AttributeNames))
            {
                if ($attributeName -like 'icc:*')
                {
                    $image.RemoveAttribute($attributeName)
                }
            }
        }

        if ($StripMetadata)
        {
            $colorProfile = $image.GetColorProfile()
            $image.Strip()

            if ($null -ne $colorProfile)
            {
                $image.SetProfile($colorProfile)

                <#
                    Strip() keeps the image properties parsed from the removed profiles (exif:Make,
                    exif:GPSLatitude, dc:creator, ...) and excludes the PNG text chunks so they are not
                    written. ImageMagick's PNG encoder writes the iCCP chunk only when tEXt chunks are
                    allowed, so the properties are removed and tEXt and iCCP are allowed again.
                #>
                foreach ($attributeName in @($image.AttributeNames))
                {
                    $image.RemoveAttribute($attributeName)
                }

                $excludedChunks = $image.GetArtifact('png:exclude-chunk') -split ',' | Where-Object -FilterScript { $_ -notin @('tEXt', 'iCCP') }
                $image.SetArtifact('png:exclude-chunk', ($excludedChunks -join ','))
            }
        }

        if (-not $formatInfo.KeepsAlpha -and $image.HasAlpha)
        {
            <#
                JPEG has no alpha channel, and the HEIC encoder of Windows takes opaque pixels only;
                without this the colour stored under transparent pixels (often black) would show.
                ImageMagick uses the numbers of the background colour as they are in the image's
                colour space, so a CMYK image (Jpeg keeps CMYK) needs the CMYK white C=M=Y=K=0; sRGB
                white would be full cyan, magenta and yellow ink there.
            #>
            $background = [ImageMagick.MagickColors]::White
            if ($image.ColorSpace -eq [ImageMagick.ColorSpace]::CMYK)
            {
                $background = [ImageMagick.MagickColor]::new([System.Byte] 0, [System.Byte] 0, [System.Byte] 0, [System.Byte] 0, [System.Byte] 255)
            }

            $image.BackgroundColor = $background
            $image.Alpha([ImageMagick.AlphaOption]::Remove)
        }

        if ($Format -eq 'Tiff' -and $image.HasAlpha -and $image.Depth -lt 8)
        {
            <#
                A palette PNG with up to 16 colours is read with its palette bit depth (1, 2 or 4). A
                TIFF cannot store a palette together with alpha, so ImageMagick writes RGBA samples
                at that depth and rounds colours and alpha to 2, 4 or 16 levels. The pixels are 8 bit
                in memory, so raising the depth changes no pixel.
            #>
            $image.Depth = 8
        }

        $outputProfile = $image.GetColorProfile()
        if ($Format -in @('Jpeg', 'Tiff') -and $null -ne $outputProfile -and $outputProfile.ColorSpace -eq [ImageMagick.ColorSpace]::sRGB -and $image.ColorSpace -eq [ImageMagick.ColorSpace]::sRGB)
        {
            <#
                ImageMagick writes an image whose pixels are all neutral grey (a black-and-white photo
                in Adobe RGB, say) as a greyscale JPEG or TIFF but keeps its RGB profile, a pairing that
                WIC (Windows Photos, Explorer) rejects, so it shows the grey levels unmanaged. Stored as
                RGB, the profile stays valid, as for Png output below. Jpeg output has no alpha here.
                A palette PNG is read with its palette bit depth (1, 2 or 4), which RGB samples would
                keep (a one-colour image would turn black); the pixels are 8 bit in memory.
            #>
            $colorType = [ImageMagick.ColorType]::TrueColor
            if ($image.HasAlpha)
            {
                $colorType = [ImageMagick.ColorType]::TrueColorAlpha
            }

            $image.Settings.ColorType = $colorType
            if ($image.Depth -lt 8)
            {
                $image.Depth = 8
            }
        }

        if ($formatInfo.IsLossy)
        {
            $image.Quality = [System.UInt32] $Quality
        }

        if ($null -eq $failure -and -not [System.IO.Directory]::Exists($targetFolder))
        {
            $failure = (Invoke-ImageConverterMethod -Type ([System.IO.Directory]) -Name 'CreateDirectory' -ArgumentList $targetFolder).Exception
        }

        if ($null -eq $failure)
        {
            <#
                ImageMagick expands %d, %o and %x in a file name it opens itself, and .NET handles long
                paths, so it writes into a stream. The compiled helper is called directly: it assigns
                $stream in the same step that creates the file, so a pipeline stopped right after it
                cannot leave an open file that the finally block does not know about.
            #>
            $streamArguments = @($tempPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $failure = [PSImageConverter.SafeInvoker]::Invoke([System.IO.FileStream], $null, $null, $streamArguments, [ref] $stream, [ref] $ignoredArguments)
        }

        $pngProfile = $image.GetColorProfile()
        if ($null -eq $failure -and $Format -eq 'Png' -and $null -ne $pngProfile)
        {
            # ImageMagick writes the ICC profile as iCCP chunk and once more as zTXt chunk 'Raw profile type icc'.
            $encoded = Invoke-ImageConverterMethod -InputObject $image -Name 'ToByteArray' -ArgumentList ([ImageMagick.MagickFormat]::Png)
            $failure = $encoded.Exception

            # The colour type is byte 25 of a PNG file: its IHDR chunk comes right after the 8-byte signature.
            if ($null -eq $failure -and $encoded.Result[25] -in @(0, 4) -and $pngProfile.ColorSpace -ne [ImageMagick.ColorSpace]::Gray)
            {
                <#
                    ImageMagick writes an image whose pixels are all neutral grey as greyscale PNG (colour
                    type 0, or 4 with alpha) but keeps its RGB profile. The PNG format allows an RGB
                    profile only for colour images, so readers drop it; RGB (2) or RGBA (6) keeps it valid.
                #>
                $colorType = '2'
                if ($encoded.Result[25] -eq 4)
                {
                    $colorType = '6'
                }

                $image.Settings.SetDefine([ImageMagick.MagickFormat]::Png, 'color-type', $colorType)
                $encoded = Invoke-ImageConverterMethod -InputObject $image -Name 'ToByteArray' -ArgumentList ([ImageMagick.MagickFormat]::Png)
                $failure = $encoded.Exception
            }

            if ($null -eq $failure)
            {
                $png = Select-ImageConverterPngChunk -Data $encoded.Result -ExcludeTextKeyword 'Raw profile type icc', 'Raw profile type icm'
                $failure = (Invoke-ImageConverterMethod -InputObject $stream -Name 'Write' -ArgumentList $png, 0, $png.Length).Exception
            }
        }
        elseif ($null -eq $failure -and $Format -eq 'Heic')
        {
            # Magick.NET cannot write HEIC. The encoder of the operating system encodes into memory and never sees the target name.
            $encoded = Invoke-ImageConverterHeicEncoder -Image $image -Quality $Quality
            $failure = $encoded.Exception

            if ($null -eq $failure)
            {
                $failure = (Invoke-ImageConverterMethod -InputObject $stream -Name 'Write' -ArgumentList $encoded.Result, 0, $encoded.Result.Length).Exception
            }
        }
        elseif ($null -eq $failure)
        {
            $failure = (Invoke-ImageConverterMethod -InputObject $image -Name 'Write' -ArgumentList $stream, ([ImageMagick.MagickFormat] $Format)).Exception
        }

        if ($null -ne $stream)
        {
            # Closing writes the last buffered bytes, which can fail as well (disk full).
            $close = Invoke-ImageConverterMethod -InputObject $stream -Name 'Dispose'
            $stream = $null

            if ($null -eq $failure)
            {
                $failure = $close.Exception
            }
        }

        if ($null -eq $failure -and $Force -and [System.IO.File]::Exists($TargetPath))
        {
            # Like Copy-Item -Force, a read-only or hidden target is replaced, too; the move below fails for a read-only target on Windows.
            $attributes = [System.IO.File]::GetAttributes($TargetPath)

            if ($attributes -band ([System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::Hidden))
            {
                # Set first, so the finally block also restores them when the pipeline is stopped in between.
                $clearedAttributes = $attributes
                $failure = (Invoke-ImageConverterMethod -Type ([System.IO.File]) -Name 'SetAttributes' -ArgumentList $TargetPath, ([System.IO.FileAttributes]::Normal)).Exception
            }
        }

        if ($null -eq $failure)
        {
            $failure = (Invoke-ImageConverterMethod -Type ([System.IO.File]) -Name 'Move' -ArgumentList $tempPath, $TargetPath, $Force.IsPresent).Exception
        }
    }
    catch
    {
        # The in-memory steps above are not expected to throw; if one does, it ends only this file.
        $failure = $_.Exception
    }
    finally
    {
        <#
            Also runs when the pipeline is stopped (Ctrl+C) while the encoder writes. Only direct .NET
            calls are made here: PowerShell stops a command call while the pipeline is stopping. After
            a successful move nothing is left under the temporary name; while the temporary file is
            still there, the old target has not been replaced (e.g. it is open in another program),
            so it gets its attributes back.
        #>
        $ignoredResult = $null

        if ($null -ne $stream)
        {
            $null = [PSImageConverter.SafeInvoker]::Invoke([System.IO.FileStream], $stream, 'Dispose', $null, [ref] $ignoredResult, [ref] $ignoredArguments)
        }

        $image.Dispose()

        if ([System.IO.File]::Exists($tempPath))
        {
            if ($null -ne $clearedAttributes)
            {
                $null = [PSImageConverter.SafeInvoker]::Invoke([System.IO.File], $null, 'SetAttributes', @($TargetPath, $clearedAttributes), [ref] $ignoredResult, [ref] $ignoredArguments)
            }

            $null = [PSImageConverter.SafeInvoker]::Invoke([System.IO.File], $null, 'Delete', @($tempPath), [ref] $ignoredResult, [ref] $ignoredArguments)
        }
    }

    if ($null -ne $failure)
    {
        Write-ImageConverterError -Cmdlet $Cmdlet -Exception $failure -ErrorId 'ImageWriteFailed' -Category 'WriteError' -TargetObject $SourcePath -MessagePrefix "Cannot write image '$TargetPath'"
        return
    }

    if ($read.FrameCount -gt 1)
    {
        $Cmdlet.WriteWarning("Only the first of $($read.FrameCount) frames is converted: $SourcePath")
    }

    if ($hasExif -and -not $StripMetadata -and -not $formatInfo.KeepsExif)
    {
        $Cmdlet.WriteWarning("EXIF metadata (date taken, camera, GPS) is not written to $Format output: $SourcePath")
    }

    # With its PSPath, the written file binds -LiteralPath when it is piped into the next cmdlet.
    Get-ImageConverterFileItem -Path $TargetPath
}
