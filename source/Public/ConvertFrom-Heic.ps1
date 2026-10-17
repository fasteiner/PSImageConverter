function ConvertFrom-Heic
{
    <#
        .SYNOPSIS
        Converts HEIC/HEIF images to JPEG, PNG, WebP, TIFF, BMP, GIF or AVIF.

        .DESCRIPTION
        Converts one or more HEIC/HEIF image files (e.g. iPhone photos) into another
        image format using the bundled Magick.NET library. Works on Windows, Linux and
        macOS without installing any codecs. The EXIF orientation is applied to the
        pixels so the result is always upright, and EXIF metadata is kept unless
        -StripMetadata is specified. Returns a FileInfo object for every written file.

        .PARAMETER Path
        One or more HEIC/HEIF files to convert. Accepts pipeline input from strings and
        from Get-ChildItem / Get-Item.

        .PARAMETER Format
        The output format: Jpeg (default), Png, WebP, Tiff, Bmp, Gif or Avif.

        .PARAMETER Quality
        The quality from 1 to 100 used for lossy formats (Jpeg, WebP, Avif). Default 90.

        .PARAMETER DestinationPath
        The folder the converted files are written to. Defaults to the folder of each
        source file. The folder is created if it does not exist.

        .PARAMETER StripMetadata
        Removes all metadata (EXIF incl. GPS location, XMP, ICC profiles) from the output.

        .PARAMETER Force
        Overwrites existing output files instead of writing an error for them.

        .EXAMPLE
        ConvertFrom-Heic -Path .\IMG_1234.HEIC

        Converts IMG_1234.HEIC to IMG_1234.jpg in the same folder.

        .EXAMPLE
        Get-ChildItem -Path C:\Pictures -Filter *.heic | ConvertFrom-Heic -Format Png -DestinationPath C:\Pictures\png

        Converts all HEIC files in C:\Pictures to PNG files in C:\Pictures\png.

        .EXAMPLE
        Get-ChildItem -Path ~/Photos -Filter *.heic -Recurse | ConvertFrom-Heic -Quality 80 -StripMetadata -Force

        Converts all HEIC files recursively to JPEG with quality 80, removes location
        data and other metadata, and overwrites existing JPEG files.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.IO.FileInfo])]
    param
    (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName', 'PSPath')]
        [System.String[]]
        $Path,

        [Parameter()]
        [ValidateSet('Jpeg', 'Png', 'WebP', 'Tiff', 'Bmp', 'Gif', 'Avif')]
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
        $extensions = @{
            Jpeg = '.jpg'
            Png  = '.png'
            WebP = '.webp'
            Tiff = '.tif'
            Bmp  = '.bmp'
            Gif  = '.gif'
            Avif = '.avif'
        }
    }

    process
    {
        foreach ($item in $Path)
        {
            try
            {
                $sourcePath = (Resolve-Path -LiteralPath $item -ErrorAction Stop).ProviderPath

                if ([System.IO.Path]::GetExtension($sourcePath) -notin @('.heic', '.heif', '.hif'))
                {
                    throw [System.ArgumentException]::new("The file '$sourcePath' is not a HEIC/HEIF image (.heic, .heif, .hif).")
                }

                $targetPath = Resolve-PSHeicOutputPath -SourcePath $sourcePath -Extension $extensions[$Format] -DestinationPath $DestinationPath -Force:$Force

                if ($PSCmdlet.ShouldProcess($sourcePath, "Convert to $Format '$targetPath'"))
                {
                    $targetFolder = Split-Path -Path $targetPath -Parent
                    if (-not (Test-Path -LiteralPath $targetFolder -PathType Container))
                    {
                        $null = New-Item -Path $targetFolder -ItemType Directory -Force
                    }

                    Convert-PSHeicImage -SourcePath $sourcePath -TargetPath $targetPath -Format $Format -Quality $Quality -StripMetadata:$StripMetadata

                    Get-Item -LiteralPath $targetPath
                }
            }
            catch
            {
                Write-Error -ErrorRecord $_
            }
        }
    }
}
