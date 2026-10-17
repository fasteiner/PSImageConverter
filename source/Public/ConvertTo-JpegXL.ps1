function ConvertTo-JpegXL
{
    <#
        .SYNOPSIS
        Converts images to JPEG XL.

        .DESCRIPTION
        Converts one or more image files of any format Magick.NET can read (HEIC/HEIF, JPEG,
        PNG, WebP, AVIF, TIFF, ...) to JPEG XL files with the extension .jxl. This is
        Convert-Image -Format Jxl: all files of one call go through a single Convert-Image call,
        so output names, -Force, -WhatIf, the metadata handling and the error ids are the same,
        and errors are reported as coming from Convert-Image (FullyQualifiedErrorId
        '<Id>,Convert-Image'). Only a -DestinationPath that cannot name a folder is reported by
        ConvertTo-JpegXL itself, as one terminating error before any file is read. A source that
        is already a .jxl file gets a TargetIsSource error unless -DestinationPath points to
        another folder; the source is never overwritten. Returns a FileInfo object for every
        written file.

        .PARAMETER Path
        One or more image files to convert. Wildcards are supported (e.g. *.heic). Accepts
        pipeline input from strings.

        .PARAMETER LiteralPath
        One or more image files to convert, used exactly as written (no wildcards). Accepts
        pipeline input from Get-ChildItem / Get-Item, the conversion cmdlets and Get-ImageInfo
        through the PSPath property. Aliases: PSPath, LP.

        .PARAMETER Quality
        The JPEG XL quality from 1 to 100. Default 90; lower values give smaller files. 100
        is lossless and the only quality that keeps the ICC colour profile.

        .PARAMETER DestinationPath
        The folder the converted files are written to. Defaults to the folder of each source
        file. The folder is created if it does not exist; a folder that cannot be created or
        written to fails each file with ImageWriteFailed. Only file system paths are supported:
        a value that cannot name a folder (unknown drive, another provider, invalid characters,
        an existing file or a link without target on the way) stops the call with one
        terminating error.

        .PARAMETER StripMetadata
        Removes EXIF (including the GPS location) and XMP metadata from the output. The colours
        are kept: at -Quality 100 with the ICC colour profile, below that as sRGB pixels.

        .PARAMETER Force
        Overwrites output files that existed before the call, also read-only or hidden ones.
        Never overwrites the source file or a file written earlier in the same call.

        .EXAMPLE
        ConvertTo-JpegXL -Path .\IMG_1234.HEIC

        Converts IMG_1234.HEIC to IMG_1234.jxl with quality 90 in the same folder.

        .EXAMPLE
        Get-ChildItem -Path C:\Pictures -Filter *.png | ConvertTo-JpegXL -Quality 75 -DestinationPath C:\Pictures\jxl -Force

        Converts all PNG files in C:\Pictures to JPEG XL files with quality 75 in
        C:\Pictures\jxl and overwrites JPEG XL files that are already there.

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
        JPEG XL output keeps EXIF and XMP unless -StripMetadata is used; IPTC data and comments
        are not written. The ICC colour profile is kept only at -Quality 100 (lossless): the
        bundled encoder stores no profile in lossy files. Below 100 the pixels of a source with
        an ICC profile (e.g. Display P3 or Adobe RGB) are converted to sRGB first, so the photo
        looks the same; colours outside sRGB are clipped. Use -Quality 100 or ConvertTo-Avif to
        keep a wide gamut. See Get-Help Convert-Image -Full for the other formats, sources with
        several frames or damaged data, the preference variables of the caller and parallel
        conversions.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called by Convert-Image, which receives -WhatIf and -Confirm through the bound parameters.')]
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

        <#
            Convert-Image checks -DestinationPath as well, but its terminating error would reach this
            begin block as an ordinary statement error: this command would go on into its process
            block, and passing the error on would put it into -ErrorVariable three times.
        #>
        $null = Assert-ImageConverterDestinationPath -Cmdlet $PSCmdlet -DestinationPath $DestinationPath

        <#
            One Convert-Image runs for the whole call, so its duplicate-target check covers every file,
            and the bound parameters, including -WhatIf, -ErrorAction and the other common parameters
            that do not name a variable, reach it unchanged. Begin($PSCmdlet) makes Convert-Image
            expect pipeline input exactly when this call has some, and sends its output, errors and
            warnings to this command, which applies -ErrorVariable, -OutVariable and the like.
            The pipeline is created here and not in a shared helper function: Convert-Image then runs
            in a child scope of the helper's scope and no longer finds the module's private functions
            once the helper has returned. Convert-Image is called through its FunctionInfo, because
            an alias of that name defined anywhere in the session would win over the function name.
        #>
        $convertParameters = Get-ImageConverterForwardedParameter -BoundParameter $PSBoundParameters -Format 'Jxl'
        $convertCommand = $ExecutionContext.InvokeCommand.GetCommand('Convert-Image', [System.Management.Automation.CommandTypes]::Function)

        $convertPipeline = { & $convertCommand @convertParameters }.GetSteppablePipeline($MyInvocation.CommandOrigin)
        $convertPipeline.Begin($PSCmdlet)
    }

    process
    {
        # The pipeline object itself is passed on, so Convert-Image binds it like a direct call (strings to -Path, files to -LiteralPath).
        $convertPipeline.Process($_)
    }

    end
    {
        $convertPipeline.End()
    }

    clean
    {
        if ($null -ne $convertPipeline)
        {
            $convertPipeline.Clean()
        }
    }
}
