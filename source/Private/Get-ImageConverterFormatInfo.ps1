function Get-ImageConverterFormatInfo
{
    <#
        .SYNOPSIS
        Returns the file extension and capabilities of an output format.

        .DESCRIPTION
        Returns an object with the output format name, the file extension written for it,
        whether -Quality applies (lossy formats), whether the bundled Magick.NET build writes
        the EXIF profile for it and whether it stores CMYK pixels. Tiff, Bmp and Gif output
        loses the EXIF data, so the cmdlets warn about it. CMYK sources are converted to sRGB
        for the formats that cannot store CMYK, because their encoders would otherwise change
        or invert the colours.

        .PARAMETER Format
        The output format name as accepted by Convert-Image -Format, e.g. Jpeg or WebP.

        .EXAMPLE
        Get-ImageConverterFormatInfo -Format 'WebP'

        Returns Format WebP, Extension .webp, IsLossy $true, KeepsExif $true and SupportsCmyk $false.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Jpeg', 'Png', 'WebP', 'Avif', 'Jxl', 'Tiff', 'Bmp', 'Gif')]
        [System.String]
        $Format
    )

    $formats = @{
        Jpeg = @{ Extension = '.jpg'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $true }
        Png  = @{ Extension = '.png'; IsLossy = $false; KeepsExif = $true; SupportsCmyk = $false }
        WebP = @{ Extension = '.webp'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false }
        Avif = @{ Extension = '.avif'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false }
        Jxl  = @{ Extension = '.jxl'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false }
        Tiff = @{ Extension = '.tif'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $true }
        Bmp  = @{ Extension = '.bmp'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $false }
        Gif  = @{ Extension = '.gif'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $false }
    }

    $info = $formats[$Format]

    [PSCustomObject] @{
        Format       = $Format
        Extension    = $info.Extension
        IsLossy      = $info.IsLossy
        KeepsExif    = $info.KeepsExif
        SupportsCmyk = $info.SupportsCmyk
    }
}
