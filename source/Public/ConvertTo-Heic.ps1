function ConvertTo-Heic
{
    <#
        .SYNOPSIS
        Converts images to HEIC with the HEVC encoder of the operating system.

        .DESCRIPTION
        Converts one or more image files of any format Magick.NET can read (JPEG, PNG, WebP,
        AVIF, TIFF, HEIC/HEIF, ...) to HEIC files with the extension .heic. The module ships no
        HEVC encoder (HEVC is covered by patent pools; shipping an encoder would pass their
        licensing duties on to every user); it uses the one of the operating system: on Windows
        the HEIF encoder of WIC with the 'HEVC Video Extensions' from the Microsoft Store
        (Windows 10 1809 or later), on Linux the libheif of the distribution with its HEVC
        encoder x265, built in or as a plugin (e.g. sudo apt install libheif1
        libheif-plugin-x265 on Ubuntu 24.04; about_PSImageConverter lists other distributions),
        on macOS ImageIO (macOS 10.13 or later on a Mac with an HEVC encoder). When that encoder is missing or does not work, the call stops
        before any file is read with one terminating error HeicEncoderNotAvailable (category
        NotInstalled, target object 'Heic'), also with -WhatIf; the message says what to
        install. ConvertTo-Avif writes the royalty-free AV1 codec into the same HEIF container
        and needs nothing installed.
        This is Convert-Image -Format Heic: all files of one call go through a single
        Convert-Image call, so output names, -Force, -WhatIf, the metadata handling and the
        error ids are the same, and errors are reported as coming from Convert-Image
        (FullyQualifiedErrorId '<Id>,Convert-Image'). Only a -DestinationPath that cannot name
        a folder and a missing encoder are reported by ConvertTo-Heic itself, as one terminating
        error before any file is read. A source that is already a .heic file gets a
        TargetIsSource error unless -DestinationPath points to another folder; the source is
        never overwritten. Returns a FileInfo object for every written file.

        .PARAMETER Path
        One or more image files to convert. Wildcards are supported (e.g. *.jpg). Accepts
        pipeline input from strings.

        .PARAMETER LiteralPath
        One or more image files to convert, used exactly as written (no wildcards). Accepts
        pipeline input from Get-ChildItem / Get-Item, the conversion cmdlets and Get-ImageInfo
        through the PSPath property. Aliases: PSPath, LP.

        .PARAMETER Quality
        The HEIC quality from 1 to 100. Default 90; lower values give smaller files. It is
        passed to the encoder of the operating system on its own scale (WIC and ImageIO 0.01 to
        1.0, libheif 1 to 100); 100 is not lossless. At 90 the files are larger than JPEG files
        at 90 (about 1.1 to 2 times on Windows, 2.4 to 3.4 times with x265 on Linux); 60 to 80
        gives about the size of JPEG at 90.

        .PARAMETER DestinationPath
        The folder the converted files are written to. Defaults to the folder of each source
        file. The folder is created if it does not exist; a folder that cannot be created or
        written to fails each file with ImageWriteFailed. Only file system paths are supported:
        a value that cannot name a folder (unknown drive, another provider, invalid characters,
        an existing file or a link without target or that cannot be resolved on the way) stops
        the call with one terminating error.

        .PARAMETER StripMetadata
        Removes EXIF (including the GPS location) and XMP metadata from the output. The ICC
        colour profile is kept, so photos that carry one keep their colours; grey images with a
        grey profile get sRGB pixels instead (see Get-Help Convert-Image -Full).

        .PARAMETER Force
        Overwrites output files that existed before the call, also read-only or hidden ones.
        Never overwrites the source file or a file written earlier in the same call.

        .EXAMPLE
        ConvertTo-Heic -Path .\IMG_1234.jpg -Quality 80

        Converts IMG_1234.jpg to IMG_1234.heic with quality 80 in the same folder.

        .EXAMPLE
        Get-ChildItem -Path C:\Pictures -Filter *.png | ConvertTo-Heic -DestinationPath C:\Pictures\heic

        Converts all PNG files in C:\Pictures to HEIC files in C:\Pictures\heic.

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
        What HEIC output keeps unless -StripMetadata is used depends on the encoder:

        - Windows: EXIF, XMP and the ICC colour profile. The encoder takes opaque pixels only, so
          transparent pixels are placed on a white background, as for Jpeg. Images with a side
          longer than 22528 pixels fail with ImageWriteFailed.
        - Linux: EXIF, XMP, the ICC colour profile and the alpha channel. Images with a side
          longer than 32768 pixels (libheif would not read the file back), or with a side
          shorter than 32 pixels and the other longer than 4096, fail with ImageWriteFailed.
          Images larger than 8 megapixels are encoded in several slices, so Magick.NET can read
          them back; Windows' own viewer does not open such files, nor files with a side longer
          than 16384 pixels.
        - macOS: no EXIF and no XMP (a warning is written for a source with EXIF data); the alpha
          channel and the ICC colour profile are kept, except sRGB, which ImageIO stores as nclx
          colour information instead of a profile.

        IPTC data and comments are not written. EXIF and XMP are stored as they are, so a block
        another program could not parse is kept, as in the other output formats; the EXIF
        orientation of the output is 1, because the pixels are already upright. Windows' own
        viewer (Photos, Explorer) does not show a HEIC image with a side shorter than 8 pixels,
        whichever program wrote it, and ignores the alpha channel of HEIC files. The check whether the encoder works runs once per
        PowerShell process; after installing an encoder, start a new session. See Get-Help
        Convert-Image -Full for the other formats, sources with several frames or damaged data,
        the preference variables of the caller, parallel conversions and PSDrives that are not
        global.
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
            Convert-Image checks -DestinationPath and the HEIC encoder as well, but its terminating
            error would reach this begin block as an ordinary statement error: this command would go
            on into its process block, and passing the error on would put it into -ErrorVariable
            three times.
        #>
        $null = Assert-ImageConverterDestinationPath -Cmdlet $PSCmdlet -DestinationPath $DestinationPath
        Assert-ImageConverterHeicEncoder -Cmdlet $PSCmdlet -Format 'Heic'

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
        $convertParameters = Get-ImageConverterForwardedParameter -BoundParameter $PSBoundParameters -Format 'Heic'
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
