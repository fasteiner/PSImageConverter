function Convert-ImageConverterImage
{
    <#
        .SYNOPSIS
        Converts a single image file with Magick.NET and returns the written file.

        .DESCRIPTION
        Reads the source image, applies the EXIF orientation to the pixels (auto-orient) and
        updates the metadata that still describes the stored orientation, converts CMYK pixels
        to sRGB for formats that cannot store CMYK, optionally strips the metadata but keeps the
        ICC colour profile, sets the quality for lossy output formats and writes the image in
        the requested format. The image is written into a temporary file in the target folder
        first, through a stream so ImageMagick does not interpret the file name, and then moved
        over the target, so a failed or stopped conversion never leaves a truncated target file
        or the temporary file behind; the target folder is created when it does not exist. With
        Force, the ReadOnly and Hidden attributes of an existing target are cleared before it is
        replaced and restored when it cannot be replaced.
        Failures are written as non-terminating errors through the cmdlet passed in -Cmdlet:
        ImageReadFailed when the source cannot be read, ImageWriteFailed when the target
        cannot be written. For output formats that cannot carry EXIF data (Tiff, Bmp, Gif) a
        warning is written when the source has EXIF data and StripMetadata is not set.
        Returns the written file as the FileSystem provider returns it (a FileInfo with PSPath),
        or nothing after a failure.

        .PARAMETER Cmdlet
        The $PSCmdlet of the public cmdlet that reports errors and warnings, e.g. Convert-Image.

        .PARAMETER SourcePath
        The full path of the image file to read.

        .PARAMETER TargetPath
        The full path of the image file to write.

        .PARAMETER Format
        The output format name as accepted by Convert-Image -Format, e.g. Jpeg or WebP.

        .PARAMETER Quality
        The quality (1-100) applied to lossy output formats (Jpeg, WebP, Avif, Jxl).

        .PARAMETER StripMetadata
        Removes EXIF, XMP, IPTC and comments from the output but keeps the ICC colour profile.

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
        [ValidateSet('Jpeg', 'Png', 'WebP', 'Avif', 'Jxl', 'Tiff', 'Bmp', 'Gif')]
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

    $read = Read-ImageConverterImage -Path $SourcePath
    if ($null -ne $read.Exception)
    {
        Write-ImageConverterError -Cmdlet $Cmdlet -Exception $read.Exception -ErrorId 'ImageReadFailed' -Category 'InvalidData' -TargetObject $SourcePath -MessagePrefix "Cannot read image '$SourcePath'"
        return
    }

    $image = $read.Result
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

        if (-not $formatInfo.SupportsCmyk -and $image.ColorSpace -eq [ImageMagick.ColorSpace]::CMYK)
        {
            <#
                The encoders of these formats convert CMYK with a plain formula and drop the CMYK
                profile, and the JPEG XL encoder stores C, M and Y as R, G and B. The conversion uses
                the embedded CMYK profile; the SWOP profile is used only for a source without one.
            #>
            $null = $image.TransformColorSpace([ImageMagick.ColorProfiles]::USWebCoatedSWOP, [ImageMagick.ColorProfiles]::SRGB)
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

        if ($formatInfo.IsLossy)
        {
            $image.Quality = [System.UInt32] $Quality
        }

        if (-not [System.IO.Directory]::Exists($targetFolder))
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

        if ($null -eq $failure)
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

    if ($hasExif -and -not $StripMetadata -and -not $formatInfo.KeepsExif)
    {
        $Cmdlet.WriteWarning("EXIF metadata (date taken, camera, GPS) is not written to $Format output: $SourcePath")
    }

    # With its PSPath, the written file binds -LiteralPath when it is piped into the next cmdlet.
    Get-ImageConverterFileItem -Path $TargetPath
}
