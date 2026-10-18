function Get-ImageConverterFormatInfo
{
    <#
        .SYNOPSIS
        Returns the file extension and capabilities of an output format.

        .DESCRIPTION
        Returns an object with the output format name (spelled as in the -Format ValidateSet of
        the cmdlets, whatever the casing of -Format), the file extension written for it,
        whether -Quality applies (lossy formats), whether the bundled Magick.NET build writes
        the EXIF profile for it, whether it stores CMYK pixels and whether it stores grey pixels
        as grey (one channel). Tiff, Bmp and Gif output loses the EXIF data, so the cmdlets warn
        about it. CMYK sources are converted to sRGB for the formats that cannot store CMYK,
        because their encoders would otherwise change or invert the colours. WebP, Avif, Bmp and
        Gif store grey pixels as RGB, for which a grey ICC profile is not valid, so grey pixels
        with a grey profile are converted to sRGB for them. Without -Format the objects of all
        output formats are returned, so the tests can compare the -Format ValidateSets of the
        cmdlets with this table.

        .PARAMETER Format
        The output format name as accepted by Convert-Image -Format, e.g. Jpeg or WebP; all
        formats when it is left out.

        .EXAMPLE
        Get-ImageConverterFormatInfo -Format 'WebP'

        Returns Format WebP, Extension .webp, IsLossy $true, KeepsExif $true, SupportsCmyk $false
        and StoresGray $false.

        .EXAMPLE
        (Get-ImageConverterFormatInfo).Format

        Returns the names of all output formats.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [ValidateSet('Jpeg', 'Png', 'WebP', 'Avif', 'Jxl', 'Tiff', 'Bmp', 'Gif')]
        [System.String]
        $Format
    )

    $formats = [ordered] @{
        Jpeg = @{ Extension = '.jpg'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $true; StoresGray = $true }
        Png  = @{ Extension = '.png'; IsLossy = $false; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $true }
        WebP = @{ Extension = '.webp'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $false }
        Avif = @{ Extension = '.avif'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $false }
        Jxl  = @{ Extension = '.jxl'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $true }
        Tiff = @{ Extension = '.tif'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $true; StoresGray = $true }
        Bmp  = @{ Extension = '.bmp'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $false; StoresGray = $false }
        Gif  = @{ Extension = '.gif'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $false; StoresGray = $false }
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
        }
    }
}
