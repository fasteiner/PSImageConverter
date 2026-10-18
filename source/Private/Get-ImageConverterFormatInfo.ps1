function Get-ImageConverterFormatInfo
{
    <#
        .SYNOPSIS
        Returns the file extension and capabilities of an output format.

        .DESCRIPTION
        Returns an object with the output format name (spelled as in the -Format ValidateSet of
        the cmdlets, whatever the casing of -Format), the file extension written for it,
        whether -Quality applies (lossy formats), whether the output keeps the EXIF profile,
        whether it stores CMYK pixels, whether it stores grey pixels as grey (one channel) and
        whether it keeps an alpha channel. Tiff, Bmp and Gif output loses the EXIF data, so the
        cmdlets warn about it. CMYK sources are converted to sRGB for the formats that cannot
        store CMYK, because their encoders would otherwise change or invert the colours. WebP,
        Avif, Heic, Bmp and Gif store grey pixels as RGB, for which a grey ICC profile is not
        valid, so grey pixels with a grey profile are converted to sRGB for them. Transparent
        pixels are flattened onto white for the formats without alpha. Heic is written by the
        encoder of the operating system, so two values depend on the platform: the WIC encoder of
        Windows stores no alpha channel, and ImageIO of macOS writes no EXIF. Without -Format the
        objects of all output formats are returned, so the tests can compare the -Format
        ValidateSets of the cmdlets with this table.

        .PARAMETER Format
        The output format name as accepted by Convert-Image -Format, e.g. Jpeg or WebP; all
        formats when it is left out.

        .EXAMPLE
        Get-ImageConverterFormatInfo -Format 'WebP'

        Returns Format WebP, Extension .webp, IsLossy $true, KeepsExif $true, SupportsCmyk $false,
        StoresGray $false and KeepsAlpha $true.

        .EXAMPLE
        (Get-ImageConverterFormatInfo).Format

        Returns the names of all output formats.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [ValidateSet('Jpeg', 'Png', 'WebP', 'Avif', 'Heic', 'Jxl', 'Tiff', 'Bmp', 'Gif')]
        [System.String]
        $Format
    )

    $formats = [ordered] @{
        Jpeg = @{ Extension = '.jpg'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $true; StoresGray = $true; KeepsAlpha = $false }
        Png  = @{ Extension = '.png'; IsLossy = $false; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $true; KeepsAlpha = $true }
        WebP = @{ Extension = '.webp'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $false; KeepsAlpha = $true }
        Avif = @{ Extension = '.avif'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $false; KeepsAlpha = $true }
        Heic = @{ Extension = '.heic'; IsLossy = $true; KeepsExif = [PSImageConverter.HeicEncoder]::StoresMetadata; SupportsCmyk = $false; StoresGray = $false; KeepsAlpha = [PSImageConverter.HeicEncoder]::StoresAlpha }
        Jxl  = @{ Extension = '.jxl'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $true; KeepsAlpha = $true }
        Tiff = @{ Extension = '.tif'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $true; StoresGray = $true; KeepsAlpha = $true }
        Bmp  = @{ Extension = '.bmp'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $false; StoresGray = $false; KeepsAlpha = $true }
        Gif  = @{ Extension = '.gif'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $false; StoresGray = $false; KeepsAlpha = $true }
    }

    # The table's spelling, also when -Format is given in another casing ('webp' -> 'WebP').
    $names = $formats.Keys
    if ($PSBoundParameters.ContainsKey('Format'))
    {
        $names = @($formats.Keys | Where-Object -FilterScript { $_ -eq $Format })
    }

    foreach ($name in $names)
    {
        $info = $formats[$name]

        [PSCustomObject] @{
            Format       = $name
            Extension    = $info.Extension
            IsLossy      = $info.IsLossy
            KeepsExif    = $info.KeepsExif
            SupportsCmyk = $info.SupportsCmyk
            StoresGray   = $info.StoresGray
            KeepsAlpha   = $info.KeepsAlpha
        }
    }
}
