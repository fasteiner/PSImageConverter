function ConvertFrom-Heic
{
    <#
        .SYNOPSIS
        Converts HEIC/HEIF images to JPEG, PNG, WebP, AVIF, JPEG XL, TIFF, BMP or GIF.

        .DESCRIPTION
        Converts one or more HEIC/HEIF image files (e.g. iPhone photos) into another image
        format. Checks that every source file has the extension .heic, .heif or .hif (any
        case) and writes a NotHeicFile error for other files; files this call writes itself
        (Get-ChildItem -Recurse into a -DestinationPath inside the tree) are skipped instead.
        The conversion itself is done by Convert-Image, so output names, -Force, -WhatIf, the
        metadata handling and the error ids are the same. All files of one call go through a
        single Convert-Image call, so two sources that map to the same target (IMG_1.heic and
        IMG_1.heif) are detected. The errors Convert-Image finds (TargetExists, DuplicateTarget,
        ImageReadFailed, ...) are reported as coming from Convert-Image; PathNotFound,
        InvalidWildcardPattern, UnsupportedProvider and NotHeicFile for the input paths come
        from ConvertFrom-Heic. Returns a FileInfo object for every written file.

        .PARAMETER Path
        One or more HEIC/HEIF files to convert. Wildcards are supported (e.g. *.heic).
        Accepts pipeline input from strings.

        .PARAMETER LiteralPath
        One or more HEIC/HEIF files to convert, used exactly as written (no wildcards).
        Accepts pipeline input from Get-ChildItem / Get-Item through the PSPath property.
        Aliases: PSPath, LP.

        .PARAMETER Format
        The output format: Jpeg (default), Png, WebP, Avif, Jxl (JPEG XL), Tiff, Bmp or Gif.

        .PARAMETER Quality
        The quality from 1 to 100 used for the lossy formats Jpeg, WebP, Avif and Jxl.
        Default 90. Ignored for the other formats.

        .PARAMETER DestinationPath
        The folder the converted files are written to. Defaults to the folder of each source
        file. The folder is created if it does not exist. Only file system paths are supported.

        .PARAMETER StripMetadata
        Removes EXIF (including the GPS location), XMP and IPTC metadata and comments from the
        output. The ICC colour profile is kept, so photos keep their colours.

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

        .NOTES
        See Get-Help Convert-Image -Full for the metadata each output format keeps.
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
        [ValidateSet('Jpeg', 'Png', 'WebP', 'Avif', 'Jxl', 'Tiff', 'Bmp', 'Gif')]
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
        <#
            One Convert-Image runs for the whole call, so its duplicate-target check covers every file,
            and the common parameters that do not name a variable (-WhatIf, -ErrorAction, ...) reach it
            unchanged. The files are forwarded one by one as resolved literal paths, so wildcards are
            not expanded a second time. Begin($true, ...) instead of Begin($PSCmdlet): Convert-Image has
            to expect pipeline input even when this call has none (ConvertFrom-Heic -Path x.heic),
            otherwise it fails for the missing mandatory -Path. Its output and errors go to this
            command through $ExecutionContext, which applies -ErrorVariable, -OutVariable and the like.
        #>
        $convertParameters = Get-ImageConverterForwardedParameter -BoundParameter $PSBoundParameters -Format $Format -ExcludeParameter 'Path', 'LiteralPath'

        $convertPipeline = { Convert-Image @convertParameters }.GetSteppablePipeline($MyInvocation.CommandOrigin)
        $convertPipeline.Begin($true, $ExecutionContext)

        <#
            Target path -> source path of every HEIC file forwarded so far. Get-ChildItem -Recurse into a
            -DestinationPath inside the tree lists the files this call writes; Convert-Image skips them,
            but they would fail the extension check here first. With an unusable -DestinationPath
            Convert-Image writes nothing, so no target is predicted.
        #>
        $extension = (Get-ImageConverterFormatInfo -Format $Format).Extension
        $forwardedTargets = [System.Collections.Generic.Dictionary[System.String, System.String]]::new((Get-ImageConverterPathComparer))
        $predictTargets = $true
        $destinationFolder = $null

        if (-not [System.String]::IsNullOrEmpty($DestinationPath))
        {
            $destinationFolder = (Resolve-ImageConverterDestinationPath -DestinationPath $DestinationPath).Path
            $predictTargets = $null -ne $destinationFolder
        }
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

            if ($predictTargets)
            {
                $forwardedTargets[(Get-ImageConverterTargetPath -SourcePath $sourcePath -Extension $extension -Folder $destinationFolder)] = $sourcePath
            }

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
