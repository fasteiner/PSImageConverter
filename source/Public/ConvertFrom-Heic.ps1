function ConvertFrom-Heic
{
    <#
        .SYNOPSIS
        Converts HEIC/HEIF images to JPEG, PNG, WebP, AVIF, HEIC, JPEG XL, TIFF, BMP or GIF.

        .DESCRIPTION
        Converts one or more HEIC/HEIF image files (e.g. iPhone photos) into another image
        format. Checks that every source file has the extension .heic, .heif or .hif (any case)
        and writes a NotHeicFile error for other files; files this call writes itself
        (Get-ChildItem -Recurse into a -DestinationPath inside the tree) are skipped instead.
        The conversion itself is done by Convert-Image, so output names, -Force, -WhatIf, the
        metadata handling and the error ids are the same. All files of one call go through a
        single Convert-Image call, so two sources that map to the same target (IMG_1.heic and
        IMG_1.heif) are detected, and errors are reported as coming from Convert-Image: the
        errors Convert-Image finds (TargetExists, DuplicateTarget, ConfirmationFailed,
        ImageReadFailed, ...) have the FullyQualifiedErrorId '<Id>,Convert-Image'.
        ConvertFrom-Heic reports the checks it makes itself: PathNotFound,
        InvalidWildcardPattern, UnsupportedProvider and NotHeicFile for the input paths, and a
        -DestinationPath that cannot name a folder (InvalidDestinationPath, UnsupportedProvider,
        DestinationNotDirectory), which stops the whole call with one terminating error before
        any file is read, and so does -Format Heic on a computer without a working HEVC encoder
        (HeicEncoderNotAvailable). Returns a FileInfo object for every written file.

        .PARAMETER Path
        One or more HEIC/HEIF files to convert. Wildcards are supported (e.g. *.heic).
        Accepts pipeline input from strings.

        .PARAMETER LiteralPath
        One or more HEIC/HEIF files to convert, used exactly as written (no wildcards).
        Accepts pipeline input from Get-ChildItem / Get-Item and Get-ImageInfo through the
        PSPath property. Aliases: PSPath, LP.

        .PARAMETER Format
        The output format: Jpeg (default), Png, WebP, Avif, Heic, Jxl (JPEG XL), Tiff, Bmp or
        Gif. Heic re-encodes with the HEVC encoder of the operating system (see Get-Help
        ConvertTo-Heic), e.g. at a lower -Quality into another -DestinationPath.

        .PARAMETER Quality
        The quality from 1 to 100 used for the lossy formats Jpeg, WebP, Avif, Heic and Jxl.
        Default 90. Ignored for the other formats.

        .PARAMETER DestinationPath
        The folder the converted files are written to. Defaults to the folder of each source
        file. The folder is created if it does not exist; a folder that cannot be created or
        written to fails each file with ImageWriteFailed. Only file system paths are supported:
        a value that cannot name a folder (unknown drive, another provider, invalid characters,
        an existing file or a link without target or that cannot be resolved on the way) stops
        the call with one terminating error.

        .PARAMETER StripMetadata
        Removes EXIF (including the GPS location), XMP and IPTC metadata and comments from the
        output. The ICC colour profile is kept, so photos that carry one (as iPhone photos do)
        keep their colours; lossy Jxl output, and grey images with a grey profile in WebP,
        Avif, Heic, Bmp and Gif output, get sRGB pixels instead (see Get-Help Convert-Image
        -Full).

        .PARAMETER Force
        Overwrites output files that existed before the call, also read-only or hidden ones.
        Never overwrites a file written earlier in the same call.

        .EXAMPLE
        ConvertFrom-Heic -Path .\IMG_1234.HEIC

        Converts IMG_1234.HEIC to IMG_1234.jpg in the same folder.

        .EXAMPLE
        ConvertFrom-Heic -Path C:\Pictures\*.heic -Format Png -DestinationPath C:\Pictures\png

        Converts all HEIC files in C:\Pictures to PNG files in C:\Pictures\png.

        .EXAMPLE
        Get-ChildItem -Path ~/Photos -Filter *.heic -Recurse | ConvertFrom-Heic -Quality 80 -StripMetadata -Force

        Converts all HEIC files recursively to JPEG with quality 80, removes the location data
        and other metadata, and overwrites existing JPEG files.

        .INPUTS
        System.String
        System.IO.FileInfo
        PSImageConverter.ImageInfo

        Strings bind to -Path, so wildcards in them are expanded. Objects with a PSPath property
        bind to -LiteralPath: files from Get-ChildItem or Get-Item and the objects returned by
        Get-ImageInfo.

        .OUTPUTS
        System.IO.FileInfo

        One object per written file, as Get-Item returns it (with the PSPath property). Nothing
        is returned with -WhatIf or for a file that fails.

        .NOTES
        See Get-Help Convert-Image -Full for the metadata each output format keeps, the handling
        of transparency, several frames and damaged files, how the preference variables of the
        caller apply, parallel conversions and PSDrives that are not global.
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
        [ValidateSet('Jpeg', 'Png', 'WebP', 'Avif', 'Heic', 'Jxl', 'Tiff', 'Bmp', 'Gif')]
        [System.String]
        $Format = 'Jpeg',

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
        $destinationFolder = Assert-ImageConverterDestinationPath -Cmdlet $PSCmdlet -DestinationPath $DestinationPath
        Assert-ImageConverterHeicEncoder -Cmdlet $PSCmdlet -Format (Get-ImageConverterFormatInfo -Format $Format).Format

        <#
            One Convert-Image runs for the whole call, so its duplicate-target check covers every file,
            and the common parameters that do not name a variable (-WhatIf, -ErrorAction, ...) reach it
            unchanged. The files are forwarded one by one as resolved literal paths, so wildcards are
            not expanded a second time. Begin($true, ...) instead of Begin($PSCmdlet): Convert-Image has
            to expect pipeline input even when this call has none (ConvertFrom-Heic -Path x.heic),
            otherwise it fails for the missing mandatory -Path. Its output and errors go to this
            command through $ExecutionContext, which applies -ErrorVariable, -OutVariable and the like.
            Convert-Image is called through its FunctionInfo, because an alias of that name defined
            anywhere in the session would win over the function name.
        #>
        $convertParameters = Get-ImageConverterForwardedParameter -BoundParameter $PSBoundParameters -Format $Format -ExcludeParameter 'Path', 'LiteralPath'
        $convertCommand = $ExecutionContext.InvokeCommand.GetCommand('Convert-Image', [System.Management.Automation.CommandTypes]::Function)

        $convertPipeline = { & $convertCommand @convertParameters }.GetSteppablePipeline($MyInvocation.CommandOrigin)
        $convertPipeline.Begin($true, $ExecutionContext)

        <#
            Target path -> source path of every HEIC file forwarded so far. Get-ChildItem -Recurse into a
            -DestinationPath inside the tree lists the files this call writes; Convert-Image skips them,
            but they would fail the extension check here first.
        #>
        $extension = (Get-ImageConverterFormatInfo -Format $Format).Extension
        $forwardedTargets = [System.Collections.Generic.Dictionary[System.String, System.String]]::new((Get-ImageConverterPathComparer))
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
            if ([System.IO.Path]::GetExtension($sourcePath) -notin @('.heic', '.heif', '.hif'))
            {
                if ($forwardedTargets.ContainsKey($sourcePath))
                {
                    Write-Verbose -Message "Skipping '$sourcePath': it is the target of '$($forwardedTargets[$sourcePath])' in this call."
                    continue
                }

                $exception = [System.ArgumentException]::new("The file '$sourcePath' is not a HEIC/HEIF image (.heic, .heif, .hif).")
                Write-ImageConverterError -Cmdlet $PSCmdlet -Exception $exception -ErrorId 'NotHeicFile' -Category 'InvalidArgument' -TargetObject $sourcePath
                continue
            }

            $forwardedTargets[(Get-ImageConverterTargetPath -SourcePath $sourcePath -Extension $extension -Folder $destinationFolder)] = $sourcePath

            $convertPipeline.Process([PSCustomObject] @{ LiteralPath = $sourcePath })
        }
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
