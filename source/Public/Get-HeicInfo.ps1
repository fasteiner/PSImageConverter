function Get-HeicInfo
{
    <#
        .SYNOPSIS
        Returns size, orientation and EXIF details of HEIC/HEIF (and other) images.

        .DESCRIPTION
        Reads one or more image files with the bundled Magick.NET library and returns
        an object per file with the format, pixel dimensions, EXIF orientation, camera
        make and model, the date the photo was taken and the file size. Works for
        HEIC/HEIF as well as every other format Magick.NET can read (JPEG, PNG, ...).

        .PARAMETER Path
        One or more image files to inspect. Accepts pipeline input from strings and
        from Get-ChildItem / Get-Item.

        .EXAMPLE
        Get-HeicInfo -Path .\IMG_1234.HEIC

        Shows the dimensions, orientation and camera details of IMG_1234.HEIC.

        .EXAMPLE
        Get-ChildItem -Path C:\Pictures -Filter *.heic | Get-HeicInfo | Sort-Object -Property DateTaken

        Lists all HEIC photos in C:\Pictures ordered by the date they were taken.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'PSPath')]
        [System.String[]]
        $Path
    )

    process
    {
        foreach ($item in $Path)
        {
            try
            {
                $sourcePath = (Resolve-Path -LiteralPath $item -ErrorAction Stop).ProviderPath
                $image = [ImageMagick.MagickImage]::new($sourcePath)

                try
                {
                    $exif = ConvertFrom-PSHeicExifProfile -ExifProfile $image.GetExifProfile()

                    [PSCustomObject] @{
                        PSTypeName  = 'PSHeic.ImageInfo'
                        Path        = $sourcePath
                        Format      = $image.Format.ToString()
                        Width       = [System.Int32] $image.Width
                        Height      = [System.Int32] $image.Height
                        Orientation = $image.Orientation.ToString()
                        CameraMake  = $exif['Make']
                        CameraModel = $exif['Model']
                        DateTaken   = ConvertTo-PSHeicDateTime -Value $exif['DateTimeOriginal']
                        HasExif     = $exif.Count -gt 0
                        FileSize    = (Get-Item -LiteralPath $sourcePath).Length
                    }
                }
                finally
                {
                    $image.Dispose()
                }
            }
            catch
            {
                Write-Error -ErrorRecord $_
            }
        }
    }
}
