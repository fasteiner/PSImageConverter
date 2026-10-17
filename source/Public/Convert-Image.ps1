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

        Errors about a file are non-terminating and processing continues with the next file;
        use -ErrorAction Stop to stop at the first one. Every error has a stable error id:
        PathNotFound (for a wildcard pattern that matches nothing the message says that
        wildcards skip hidden files and, for a pattern with [ or ], that these are wildcard
        characters), InvalidWildcardPattern (a -Path that is not a valid wildcard pattern,
        e.g. 'a[.jpg'; use -LiteralPath), UnsupportedProvider (an input that is not a file
        system path; one error per input, also for a pattern that matches several items of
        another provider), TargetIsSource (the target would overwrite the source file),
        DuplicateTarget (two sources of one call map to the same target), TargetExists,
        ConfirmationFailed (-Confirm, or a $ConfirmPreference of the caller, asks for a
        confirmation that the host cannot show, e.g. in pwsh -NonInteractive; use
        -Confirm:$false), ImageReadFailed and ImageWriteFailed. The target object of an error is
        the source file; for PathNotFound, InvalidWildcardPattern and UnsupportedProvider it is
        the input as given. -Force never overwrites the source file or a file written earlier in
        the same call, also not when the folder is reached through another path (a junction, a
        symbolic link, a subst or mapped drive, a UNC path). Folders in the input (e.g. from
        Get-ChildItem -Recurse) are skipped, and a file given more than once is converted once.

        A -DestinationPath that cannot name a folder is a parameter error: it stops the whole
        call with one terminating error before any file is read, also with -WhatIf, and
        try/catch catches it without -ErrorAction Stop. The ids are InvalidDestinationPath
        (white space only, an unknown drive or provider, a drive-qualified path that climbs
        above the root of its drive such as Temp:\..\x, invalid characters),
        UnsupportedProvider (not a file system path) and DestinationNotDirectory (the path or
        one of its parent folders is an existing file, or a junction or symbolic link whose
        target does not exist); the target object is the -DestinationPath value as given. A
        relative path that climbs above the root of its drive stays at the root, as in other
        PowerShell cmdlets. A folder that does not exist yet is created when the first file is
        written; when that fails (no permission, a read-only file system), or the folder cannot
        be written to, each file gets an ImageWriteFailed error.

        .PARAMETER Path
        One or more image files to convert. Wildcards are supported (e.g. *.heic). Accepts
        pipeline input from strings.

        .PARAMETER LiteralPath
        One or more image files to convert, used exactly as written (no wildcards). Accepts
        pipeline input from Get-ChildItem / Get-Item, the conversion cmdlets and Get-ImageInfo
        through the PSPath property. Aliases: PSPath, LP.

        .PARAMETER Format
        The output format: Jpeg, Png, WebP, Avif, Jxl (JPEG XL), Tiff, Bmp or Gif.

        .PARAMETER Quality
        The quality from 1 to 100 used for the lossy formats Jpeg, WebP, Avif and Jxl.
        Default 90. Ignored for the other formats.

        .PARAMETER DestinationPath
        The folder the converted files are written to. Defaults to the folder of each source
        file. The folder is created if it does not exist; a folder that cannot be created or
        written to fails each file with ImageWriteFailed. Only file system paths are supported:
        a value that cannot name a folder (unknown drive, another provider, invalid characters,
        an existing file or a link without target on the way) stops the call with one
        terminating error.

        .PARAMETER StripMetadata
        Removes EXIF (including the GPS location), XMP and IPTC metadata and comments from the
        output. The ICC colour profile is kept, so photos with a wide-gamut profile (e.g.
        Display P3) keep their colours; lossy Jxl output stores no ICC profile and gets sRGB
        pixels instead (see NOTES).

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

        .EXAMPLE
        Get-ImageInfo -Path .\*.heic | Where-Object -Property Width -GT 4000 | Convert-Image -Format Jpeg -Quality 85

        Converts only the HEIC photos wider than 4000 pixels; the objects of Get-ImageInfo bind
        -LiteralPath through their PSPath property.

        .INPUTS
        System.String
        System.IO.FileInfo
        PSImageConverter.ImageInfo

        Strings bind to -Path, so wildcards in them are expanded. Objects with a PSPath property
        bind to -LiteralPath: files from Get-ChildItem or Get-Item, the files returned by the
        conversion cmdlets and the objects returned by Get-ImageInfo.

        .OUTPUTS
        System.IO.FileInfo

        One object per written file, as Get-Item returns it (with the PSPath property). Nothing
        is returned with -WhatIf or for a file that fails.

        .NOTES
        Metadata kept in the output without -StripMetadata, with the bundled Magick.NET build:

        - Jpeg, Png: EXIF, XMP, IPTC, ICC colour profile and comments.
        - WebP, Avif: EXIF, XMP and ICC colour profile; no IPTC, no comments.
        - Jxl: EXIF and XMP; the ICC colour profile only at -Quality 100 (lossless); no IPTC,
          no comments.
        - Tiff: XMP, IPTC, ICC colour profile and comments; no EXIF.
        - Gif: IPTC, ICC colour profile and comments; no EXIF, no XMP.
        - Bmp: ICC colour profile only.

        Lossy Jxl output (-Quality below 100) is always sRGB: the bundled JPEG XL encoder
        stores an ICC colour profile only in lossless files. The pixels of a source with an ICC
        profile (e.g. Display P3 or Adobe RGB) are therefore converted to sRGB first, with and
        without -StripMetadata, so the photo looks the same; colours outside sRGB are clipped.
        Use -Quality 100 or Avif to keep a wide gamut. -Verbose reports the conversion. A
        profile that viewers ignore, because it is damaged or made for other pixels (a grey
        profile in a colour image or the other way round), is ignored here as well: the pixels
        are written unchanged.

        Tiff, Gif and Bmp output cannot carry EXIF data (date taken, camera, GPS location), so
        a warning is written for every source file with EXIF data unless -StripMetadata is used.
        After the orientation is applied, an EXIF thumbnail is removed (it would show rotated)
        and the XMP orientation and pixel dimensions are updated.

        CMYK images (e.g. print JPEGs) stay CMYK with their colour profile in Jpeg and Tiff
        output; for the other formats they are converted to sRGB through their CMYK profile.

        Jpeg has no transparency: transparent and half-transparent pixels are placed on a white
        background (paper white for a CMYK image). The other formats keep the alpha channel
        (Gif has only fully transparent and opaque pixels).

        Only the first frame of an animated GIF or WebP, a multi-page TIFF or a HEIC file with
        several images is converted; a warning 'Only the first of <N> frames is converted:
        <path>' is written for every such source. A source that ImageMagick can read but
        reports as damaged (e.g. a truncated JPEG, whose missing part becomes grey, or an
        animated GIF cut off after its first frame, whose frames cannot be counted then) is
        converted with the warning 'The image may be damaged (<reasons>): <path>'. Other
        ImageMagick warnings about a source go to the verbose stream.

        Like a compiled cmdlet, Convert-Image follows the preference variables of its caller
        ($WhatIfPreference, $ConfirmPreference, $ErrorActionPreference, $WarningPreference,
        $InformationPreference, $VerbosePreference, $DebugPreference) also when they are set in
        a script or function scope: a function with SupportsShouldProcess that is called with
        -WhatIf passes it on, and $ErrorActionPreference = 'Stop' in a script makes the first
        error terminating. A common parameter given to Convert-Image itself wins.

        Separate calls or processes that write the same target file at the same time without
        -Force are not coordinated: on Windows the later one fails with TargetExists or
        ImageWriteFailed; on Linux and macOS both can succeed and the later file replaces the
        earlier one, because the final move checks for an existing file and then renames,
        which is not atomic there. With -Force the later file replaces the earlier one on every
        platform. Give parallel conversions different destination folders.

        Writing HEIC is not supported: the bundled Magick.NET build has no HEVC encoder.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called through Invoke-ImageConverterMethod, which returns the exception of a confirmation the host cannot ask instead of throwing it.')]
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
        Import-ImageConverterCallerPreference -Cmdlet $PSCmdlet

        $formatInfo = Get-ImageConverterFormatInfo -Format $Format

        if ($PSBoundParameters.ContainsKey('Quality') -and -not $formatInfo.IsLossy)
        {
            Write-Verbose -Message "-Quality is ignored for $Format output, which is not a lossy format."
        }

        # A destination that cannot name a folder would fail every file; it stops the call before any file is read.
        $destinationFolder = Assert-ImageConverterDestinationPath -Cmdlet $PSCmdlet -DestinationPath $DestinationPath

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
                Folder          = $destinationFolder
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

            <#
                ShouldProcess throws when it has to ask but the host cannot (pwsh -NonInteractive, a
                runspace without a user interface). Called directly, script code would record that as
                a MethodInvocationException without id and target. It is an error about this file like
                the others: a terminating error would reach the wrappers' process block only as a
                statement error, and their next pipeline object would then hit the stopped pipeline.
                Ctrl+C at the prompt stops the pipeline; the next command call ends the cmdlet then, so
                that exception needs no error record.
            #>
            $decision = Invoke-ImageConverterMethod -InputObject $PSCmdlet -Name 'ShouldProcess' -ArgumentList $sourcePath, "Convert to $Format '$targetPath'"

            if ($null -ne $decision.Exception -and $decision.Exception -isnot [System.Management.Automation.PipelineStoppedException])
            {
                Write-ImageConverterError -Cmdlet $PSCmdlet -Exception $decision.Exception -ErrorId 'ConfirmationFailed' -Category 'InvalidOperation' -TargetObject $sourcePath -MessagePrefix "Cannot ask whether to convert '$sourcePath'"
            }

            if ($decision.Result)
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
