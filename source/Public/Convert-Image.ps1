function Convert-Image
{
    <#
        .SYNOPSIS
        Converts images to JPEG, PNG, WebP, AVIF, JPEG XL, TIFF, BMP or GIF.

        .DESCRIPTION
        Converts one or more image files into the format given in -Format using the bundled
        Magick.NET library. Every format Magick.NET can read is accepted as source (HEIC/HEIF,
        JPEG, PNG, WebP, AVIF, TIFF, ...); the source format is detected from the file content.
        Works on Windows, Linux and macOS without installing any codecs. The EXIF orientation
        is applied to the pixels so the result is always upright. Returns a FileInfo object
        for every written file, the same object Get-Item returns, so it can be piped into the
        next cmdlet also when its name contains wildcard characters.

        The output file gets the source file's base name and the extension of the format
        (.jpg, .png, .webp, .avif, .jxl, .tif, .bmp, .gif) and is written next to the source
        or into -DestinationPath. The image is written to a temporary file in the target
        folder first and then moved over the target, so a failed or stopped (Ctrl+C)
        conversion never leaves a truncated file or the temporary file behind.

        Errors are non-terminating and processing continues with the next file; use
        -ErrorAction Stop to stop at the first one. Every error has a stable error id:
        PathNotFound, InvalidWildcardPattern (a -Path that is not a valid wildcard pattern,
        e.g. 'a[.jpg'; use -LiteralPath), UnsupportedProvider, InvalidDestinationPath,
        DestinationNotDirectory, TargetIsSource (the target would overwrite the source file),
        DuplicateTarget (two sources of one call map to the same target), TargetExists,
        ImageReadFailed and ImageWriteFailed. -Force never overwrites the source file or a
        file written earlier in the same call, also not when the folder is reached through
        another path (a junction, a symbolic link, a subst or mapped drive, a UNC path).
        Folders in the input (e.g. from Get-ChildItem -Recurse) are skipped, and a file given
        more than once is converted once.

        .PARAMETER Path
        One or more image files to convert. Wildcards are supported (e.g. *.heic). Accepts
        pipeline input from strings.

        .PARAMETER LiteralPath
        One or more image files to convert, used exactly as written (no wildcards). Accepts
        pipeline input from Get-ChildItem / Get-Item and from the conversion cmdlets through the
        PSPath property. Aliases: PSPath, LP.

        .PARAMETER Format
        The output format: Jpeg, Png, WebP, Avif, Jxl (JPEG XL), Tiff, Bmp or Gif.

        .PARAMETER Quality
        The quality from 1 to 100 used for the lossy formats Jpeg, WebP, Avif and Jxl.
        Default 90. Ignored for the other formats.

        .PARAMETER DestinationPath
        The folder the converted files are written to. Defaults to the folder of each source
        file. The folder is created if it does not exist. Only file system paths are supported.

        .PARAMETER StripMetadata
        Removes EXIF (including the GPS location), XMP and IPTC metadata and comments from the
        output. The ICC colour profile is kept, so photos with a wide-gamut profile (e.g.
        Display P3) keep their colours.

        .PARAMETER Force
        Overwrites output files that existed before the call, also read-only or hidden ones.
        Never overwrites the source file or a file written earlier in the same call.

        .EXAMPLE
        Convert-Image -Path .\IMG_1234.HEIC -Format Jpeg

        Converts IMG_1234.HEIC to IMG_1234.jpg in the same folder.

        .EXAMPLE
        Convert-Image -Path C:\Pictures\*.png -Format WebP -Quality 80 -DestinationPath C:\Pictures\web

        Converts all PNG files in C:\Pictures to WebP files with quality 80 in C:\Pictures\web.

        .EXAMPLE
        Get-ChildItem -Path ~/Photos -Recurse -File | Convert-Image -Format Avif -StripMetadata -WhatIf

        Shows which files would be converted to AVIF without metadata, without writing anything.

        .EXAMPLE
        Convert-Image -LiteralPath '.\Holiday [2026].jpg' -Format Png -Force

        Converts a file whose name contains wildcard characters and overwrites an existing
        'Holiday [2026].png'.

        .NOTES
        Metadata kept in the output without -StripMetadata, with the bundled Magick.NET build:

        - Jpeg, Png: EXIF, XMP, IPTC, ICC colour profile and comments.
        - WebP, Avif, Jxl: EXIF, XMP and ICC colour profile; no IPTC, no comments.
        - Tiff: XMP, IPTC, ICC colour profile and comments; no EXIF.
        - Gif: IPTC, ICC colour profile and comments; no EXIF, no XMP.
        - Bmp: ICC colour profile only.

        Tiff, Gif and Bmp output cannot carry EXIF data (date taken, camera, GPS location), so
        a warning is written for every source file with EXIF data unless -StripMetadata is used.
        After the orientation is applied, an EXIF thumbnail is removed (it would show rotated)
        and the XMP orientation and pixel dimensions are updated.

        CMYK images (e.g. print JPEGs) stay CMYK with their colour profile in Jpeg and Tiff
        output; for the other formats they are converted to sRGB through their CMYK profile.

        Writing HEIC is not supported: the bundled Magick.NET build has no HEVC encoder.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path', SupportsShouldProcess = $true)]
    [OutputType([System.IO.FileInfo])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ParameterSetName = 'Path')]
        [SupportsWildcards()]
        [System.String[]]
        $Path,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'LiteralPath')]
        [Alias('PSPath', 'LP')]
        [System.String[]]
        $LiteralPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Jpeg', 'Png', 'WebP', 'Avif', 'Jxl', 'Tiff', 'Bmp', 'Gif')]
        [System.String]
        $Format,

        [Parameter()]
        [ValidateRange(1, 100)]
        [System.Int32]
        $Quality = 90,

        [Parameter()]
        [System.String]
        $DestinationPath,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $StripMetadata,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    begin
    {
        $formatInfo = Get-ImageConverterFormatInfo -Format $Format

        if ($PSBoundParameters.ContainsKey('Quality') -and -not $formatInfo.IsLossy)
        {
            Write-Verbose -Message "-Quality is ignored for $Format output, which is not a lossy format."
        }

        <#
            Target path -> source path of every target this call writes, or would write with -WhatIf,
            and file identity -> source path of every file it has written. -Force only overwrites files
            that existed before the call, never the output of an earlier source, also when a second
            source reaches that output through another spelling of its folder.
        #>
        $claimedTargets = [System.Collections.Generic.Dictionary[System.String, System.String]]::new((Get-ImageConverterPathComparer))
        $writtenTargets = [System.Collections.Generic.Dictionary[System.String, System.String]]::new([System.StringComparer]::Ordinal)

        # Overlapping patterns (*.heic, IMG_*) can name a source twice; it is converted once.
        $processedSources = [System.Collections.Generic.HashSet[System.String]]::new((Get-ImageConverterPathComparer))
    }

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'Path')
        {
            $sourcePaths = Resolve-ImageConverterInputPath -Path $Path -Cmdlet $PSCmdlet
        }
        else
        {
            $sourcePaths = Resolve-ImageConverterInputPath -LiteralPath $LiteralPath -Cmdlet $PSCmdlet
        }

        foreach ($sourcePath in $sourcePaths)
        {
            if (-not $processedSources.Add($sourcePath))
            {
                Write-Verbose -Message "Skipping '$sourcePath': it was already given earlier in this call."
                continue
            }

            # Get-ChildItem -Recurse into a -DestinationPath inside the tree also lists the files written by this call.
            $writtenBy = $null
            if ($claimedTargets.ContainsKey($sourcePath))
            {
                $writtenBy = $claimedTargets[$sourcePath]
            }
            elseif ($writtenTargets.Count -gt 0)
            {
                $sourceIdentity = Get-ImageConverterFileIdentity -Path $sourcePath

                if ($null -ne $sourceIdentity -and $writtenTargets.ContainsKey($sourceIdentity))
                {
                    $writtenBy = $writtenTargets[$sourceIdentity]
                }
            }

            if ($null -ne $writtenBy)
            {
                Write-Verbose -Message "Skipping '$sourcePath': it is the output of '$writtenBy' in this call."
                continue
            }

            $outputPathParameters = @{
                Cmdlet          = $PSCmdlet
                SourcePath      = $sourcePath
                Extension       = $formatInfo.Extension
                DestinationPath = $DestinationPath
                ClaimedTarget   = $claimedTargets
                WrittenTarget   = $writtenTargets
                Force           = $Force
            }
            $targetPath = Resolve-ImageConverterOutputPath @outputPathParameters

            if ($null -eq $targetPath)
            {
                continue
            }

            $claimedTargets[$targetPath] = $sourcePath

            if ($PSCmdlet.ShouldProcess($sourcePath, "Convert to $Format '$targetPath'"))
            {
                $convertParameters = @{
                    Cmdlet        = $PSCmdlet
                    SourcePath    = $sourcePath
                    TargetPath    = $targetPath
                    Format        = $Format
                    Quality       = $Quality
                    StripMetadata = $StripMetadata
                    Force         = $Force
                }
                $written = Convert-ImageConverterImage @convertParameters

                if ($null -ne $written)
                {
                    $targetIdentity = Get-ImageConverterFileIdentity -Path $targetPath

                    if ($null -ne $targetIdentity)
                    {
                        $writtenTargets[$targetIdentity] = $sourcePath
                    }

                    $written
                }
            }
        }
    }
}
