function Get-ImageInfo
{
    <#
        .SYNOPSIS
        Returns format, size, orientation and EXIF details of images.

        .DESCRIPTION
        Reads one or more image files with the bundled Magick.NET library and returns an
        object per file with the format, pixel dimensions, EXIF orientation, camera make and
        model, the date the photo was taken and the file size. Works for HEIC/HEIF and every
        other format Magick.NET can read (JPEG, PNG, WebP, AVIF, ...). Folders in the input
        are skipped. An image without orientation tag is reported as TopLeft (upright), the
        way viewers display it. Errors are non-terminating with the ids PathNotFound,
        InvalidWildcardPattern, UnsupportedProvider and ImageReadFailed.

        .PARAMETER Path
        One or more image files to inspect. Wildcards are supported (e.g. *.heic). Accepts
        pipeline input from strings.

        .PARAMETER LiteralPath
        One or more image files to inspect, used exactly as written (no wildcards). Accepts
        pipeline input from Get-ChildItem / Get-Item and from the conversion cmdlets through the
        PSPath property. Aliases: PSPath, LP.

        .EXAMPLE
        Get-ImageInfo -Path .\IMG_1234.HEIC

        Shows the dimensions, orientation and camera details of IMG_1234.HEIC.

        .EXAMPLE
        Get-ChildItem -Path C:\Pictures -Filter *.heic | Get-ImageInfo | Sort-Object -Property DateTaken

        Lists all HEIC photos in C:\Pictures ordered by the date they were taken.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([System.Management.Automation.PSCustomObject])]
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
            $read = Read-ImageConverterImage -Path $sourcePath
            if ($null -ne $read.Exception)
            {
                Write-ImageConverterError -Cmdlet $PSCmdlet -Exception $read.Exception -ErrorId 'ImageReadFailed' -Category 'InvalidData' -TargetObject $sourcePath -MessagePrefix "Cannot read image '$sourcePath'"
                continue
            }

            $image = $read.Result

            try
            {
                $exif = ConvertFrom-ImageConverterExifProfile -ExifProfile $image.GetExifProfile()

                # Without an orientation tag an image is displayed as stored, which is what TopLeft means.
                $orientation = $image.Orientation.ToString()
                if ($orientation -eq 'Undefined')
                {
                    $orientation = 'TopLeft'
                }

                [PSCustomObject] @{
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
                }
            }
            finally
            {
                $image.Dispose()
            }
        }
    }
}
