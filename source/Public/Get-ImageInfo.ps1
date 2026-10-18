function Get-ImageInfo
{
    <#
        .SYNOPSIS
        Returns format, size, orientation and EXIF details of images.

        .DESCRIPTION
        Reads one or more image files with the bundled Magick.NET library and returns an object
        per file with the format, pixel dimensions, EXIF orientation, camera make and model, the
        date the photo was taken and the file size. Works for HEIC/HEIF and every other format
        Magick.NET can read (JPEG, PNG, WebP, AVIF, ...). Folders in the input are skipped. An
        image without orientation tag is reported as TopLeft (upright), the way viewers display
        it. For a file with several frames (animated GIF/WebP, multi-page TIFF) the first frame
        is described. A file given more than once (e.g. by overlapping patterns such as *.heic
        and IMG_*) is described once. Errors are non-terminating with the ids PathNotFound,
        InvalidWildcardPattern, UnsupportedProvider and ImageReadFailed; their target object is
        the file, for the first three the input as given. A file that ImageMagick can read but
        reports as damaged (e.g. a truncated JPEG, whose missing part is shown grey, or an
        animated GIF cut off after its first frame) gets the warning 'The image may be damaged
        (<reasons>): <path>'. A JPEG that lacks only its end marker gets this warning as well,
        although its pixels are complete: the decoder reports it like a file that is cut off.
        A path on a PSDrive that is not global gets PathNotFound with a message that names the
        drive (see the NOTES of Get-Help Convert-Image -Full).

        The objects can be piped into the conversion cmdlets: their PSPath property, which the
        default view does not show, binds -LiteralPath. Export-Csv, ConvertTo-Json, Format-List *
        and Select-Object * include PSPath; Select-Object -ExcludeProperty PSPath leaves it out.

        .PARAMETER Path
        One or more image files to inspect. Wildcards are supported (e.g. *.heic). Accepts
        pipeline input from strings.

        .PARAMETER LiteralPath
        One or more image files to inspect, used exactly as written (no wildcards). Accepts
        pipeline input from Get-ChildItem / Get-Item, the conversion cmdlets and Get-ImageInfo
        through the PSPath property. Aliases: PSPath, LP.

        .EXAMPLE
        Get-ImageInfo -Path .\IMG_1234.HEIC

        Shows the dimensions, orientation and camera details of IMG_1234.HEIC.

        .EXAMPLE
        Get-ChildItem -Path C:\Pictures -Filter *.heic | Get-ImageInfo | Sort-Object -Property DateTaken

        Lists all HEIC photos in C:\Pictures ordered by the date they were taken.

        .EXAMPLE
        Get-ImageInfo -Path .\*.heic | Where-Object -Property Width -GT 4000 | ConvertTo-Jpeg -Quality 85

        Converts only the HEIC photos wider than 4000 pixels to JPEG.

        .INPUTS
        System.String
        System.IO.FileInfo
        PSImageConverter.ImageInfo

        Strings bind to -Path, so wildcards in them are expanded. Objects with a PSPath property
        bind to -LiteralPath: files from Get-ChildItem or Get-Item, the files returned by the
        conversion cmdlets and the objects returned by Get-ImageInfo.

        .OUTPUTS
        PSImageConverter.ImageInfo

        One object per file with the type name PSImageConverter.ImageInfo and the properties
        Path (full path of the file), Format (e.g. Heic, Jpeg, Png), Width and Height (pixels
        as stored), Orientation (the EXIF orientation, e.g. TopLeft or RightTop; TopLeft when
        the image has none), CameraMake, CameraModel, DateTaken (a DateTime, or empty),
        HasExif and FileSize (bytes). The hidden property PSPath holds the provider-qualified
        path, so the object binds -LiteralPath of the conversion cmdlets and of Get-ImageInfo.
        The default view leaves it out, but Export-Csv, ConvertTo-Json, Format-List * and
        Select-Object * include it; Select-Object -ExcludeProperty PSPath leaves it out.
        Cmdlets that take -Path from the pipeline by property name (Get-Item, Copy-Item,
        Remove-Item, Get-FileHash, ...) bind the Path property instead and expand wildcards in
        it, so for a file name with [ or ] use ForEach-Object { Get-Item -LiteralPath $_.Path }.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('PSImageConverter.ImageInfo')]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ParameterSetName = 'Path')]
        [SupportsWildcards()]
        [System.String[]]
        $Path,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'LiteralPath')]
        [Alias('PSPath', 'LP')]
        [System.String[]]
        $LiteralPath
    )

    begin
    {
        Import-ImageConverterCallerPreference -Cmdlet $PSCmdlet

        # Overlapping patterns (*.heic, IMG_*) can name a file twice; it is described once.
        $processedSources = [System.Collections.Generic.HashSet[System.String]]::new((Get-ImageConverterPathComparer))

        # The default view shows these; PSPath is there for the pipeline only.
        $displayPropertyNames = [System.String[]] @('Path', 'Format', 'Width', 'Height', 'Orientation', 'CameraMake', 'CameraModel', 'DateTaken', 'HasExif', 'FileSize')
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

            # The frames are counted only because damage to a later frame shows up there.
            $read = Read-ImageConverterImage -Path $sourcePath -CountFrames
            if ($null -ne $read.Exception)
            {
                Write-ImageConverterError -Cmdlet $PSCmdlet -Exception $read.Exception -ErrorId 'ImageReadFailed' -Category 'InvalidData' -TargetObject $sourcePath -MessagePrefix "Cannot read image '$sourcePath'"
                continue
            }

            $image = $read.Result

            try
            {
                # Inside the try block: with -WarningAction Stop this ends the call, and the image is still disposed.
                Write-ImageConverterReadWarning -Cmdlet $PSCmdlet -Path $sourcePath -Warning $read.Warnings

                $exif = ConvertFrom-ImageConverterExifProfile -ExifProfile $image.GetExifProfile()

                # Without an orientation tag an image is displayed as stored, which is what TopLeft means.
                $orientation = $image.Orientation.ToString()
                if ($orientation -eq 'Undefined')
                {
                    $orientation = 'TopLeft'
                }

                $info = [PSCustomObject] @{
                    PSTypeName  = 'PSImageConverter.ImageInfo'
                    Path        = $sourcePath
                    Format      = $image.Format.ToString()
                    Width       = [System.Int32] $image.Width
                    Height      = [System.Int32] $image.Height
                    Orientation = $orientation
                    CameraMake  = $exif['Make']
                    CameraModel = $exif['Model']
                    DateTaken   = ConvertTo-ImageConverterDateTime -Value $exif['DateTimeOriginal']
                    HasExif     = $exif.Count -gt 0
                    FileSize    = [System.IO.FileInfo]::new($sourcePath).Length
                    # The provider-qualified path that Get-Item gives a file; the -LiteralPath alias PSPath binds it.
                    PSPath      = 'Microsoft.PowerShell.Core\FileSystem::' + $sourcePath
                }
                $displayProperties = [System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', $displayPropertyNames)
                $info.PSObject.Members.Add([System.Management.Automation.PSMemberSet]::new('PSStandardMembers', [System.Management.Automation.PSMemberInfo[]] @($displayProperties)))
                $info
            }
            finally
            {
                $image.Dispose()
            }
        }
    }
}
