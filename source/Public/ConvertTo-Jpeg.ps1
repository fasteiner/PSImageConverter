function ConvertTo-Jpeg
{
    <#
        .SYNOPSIS
        Converts images to JPEG.

        .DESCRIPTION
        Converts one or more image files of any format Magick.NET can read (HEIC/HEIF, PNG,
        WebP, AVIF, TIFF, ...) to JPEG files with the extension .jpg. This is Convert-Image
        -Format Jpeg: all files of one call go through a single Convert-Image call, so output
        names, -Force, -WhatIf, the metadata handling and the error ids are the same, and errors
        are reported as coming from Convert-Image (FullyQualifiedErrorId '<Id>,Convert-Image').
        Only a -DestinationPath that cannot name a folder is reported by ConvertTo-Jpeg itself, as one
        terminating error before any file is read. A source that is already a .jpg file gets a
        TargetIsSource error unless -DestinationPath points to another folder; the source is
        never overwritten. Returns a FileInfo object for every written file.

        .PARAMETER Path
        One or more image files to convert. Wildcards are supported (e.g. *.heic). Accepts
        pipeline input from strings.

        .PARAMETER LiteralPath
        One or more image files to convert, used exactly as written (no wildcards). Accepts
        pipeline input from Get-ChildItem / Get-Item, the conversion cmdlets and Get-ImageInfo
        through the PSPath property. Aliases: PSPath, LP.

        .PARAMETER Quality
        The JPEG quality from 1 to 100. Default 90; lower values give smaller files.

        .PARAMETER DestinationPath
        The folder the converted files are written to. Defaults to the folder of each source
        file. The folder is created if it does not exist; a folder that cannot be created or
        written to fails each file with ImageWriteFailed. Only file system paths are supported:
        a value that cannot name a folder (unknown drive, another provider, invalid characters,
        an existing file or a link without target on the way) stops the call with one
        terminating error.

        .PARAMETER StripMetadata
        Removes EXIF (including the GPS location), XMP and IPTC metadata and comments from the
        output. The ICC colour profile is kept, so photos keep their colours.

        .PARAMETER Force
        Overwrites output files that existed before the call, also read-only or hidden ones.
        Never overwrites the source file or a file written earlier in the same call.

        .EXAMPLE
        ConvertTo-Jpeg -Path .\IMG_1234.HEIC

        Converts IMG_1234.HEIC to IMG_1234.jpg in the same folder.

        .EXAMPLE
        Get-ChildItem -Path C:\Pictures -Filter *.png | ConvertTo-Jpeg -Quality 80 -DestinationPath C:\Pictures\jpg

        Converts all PNG files in C:\Pictures to JPEG files with quality 80 in C:\Pictures\jpg.

        .EXAMPLE
        ConvertTo-Jpeg -Path .\scans\*.jpg -Quality 60 -StripMetadata -DestinationPath .\small

        Writes smaller copies of existing JPEG files without metadata into the folder small.
        Without -DestinationPath every file would get a TargetIsSource error.

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
        JPEG output keeps EXIF, XMP, IPTC, the ICC colour profile and comments unless
        -StripMetadata is used. JPEG has no transparency: transparent and half-transparent
        pixels (e.g. of a PNG logo) are placed on a white background (paper white for a CMYK
        image, which stays CMYK). See Get-Help Convert-Image -Full for the other formats,
        sources with several frames or damaged data, the preference variables of the caller
        and parallel conversions.
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
        $convertParameters = Get-ImageConverterForwardedParameter -BoundParameter $PSBoundParameters -Format 'Jpeg'
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
