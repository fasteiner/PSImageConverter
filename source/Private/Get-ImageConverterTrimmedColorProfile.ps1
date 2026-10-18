function Get-ImageConverterTrimmedColorProfile
{
    <#
        .SYNOPSIS
        Returns ICC profile data without the bytes that follow the size its header declares.

        .DESCRIPTION
        Reads the profile size from the first four bytes of the ICC header (big-endian) and,
        when the data is longer, returns its first that many bytes. The ICC specification
        defines this field as the size of the whole profile, so the bytes after it are not part
        of the profile: lcms and viewers read only the declared size. Such bytes occur in
        camera files (Samsung Galaxy HEIC photos have been seen with two zero bytes after the
        profile); ImageMagick's Jpeg, WebP, Avif, Jxl, Tiff and Gif encoders copy them, and
        libpng refuses to write the profile then ('Incorrect data in iCCP'). Returns nothing
        when the data is not longer than the declared size, when the declared size ends before
        the tag table does (the 128-byte header, the tag count at byte 128 and 12 bytes per
        tag), or when the data has no ICC header (signature 'acsp' at byte 36). lcms reads the
        tag table from the data as given and skips every tag whose data ends after the declared
        size. So lcms reads the returned profile exactly as it reads the data as given, while a
        profile cut inside its tag table would no longer open at all. The caller checks with
        lcms first whether the profile can be applied.

        .PARAMETER Data
        The bytes of the ICC profile as Magick.NET returns them, e.g. from
        $image.GetColorProfile().ToByteArray().

        .EXAMPLE
        Get-ImageConverterTrimmedColorProfile -Data $image.GetColorProfile().ToByteArray()

        Returns the first 632 bytes of a 634-byte profile whose header declares 632 bytes, and
        nothing for a profile that ends where its header says.
    #>
    [CmdletBinding()]
    [OutputType([System.Byte[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Byte[]]
        $Data
    )

    # Only data longer than the 128-byte header can hold a profile with bytes after it.
    if ($Data.Length -le 128 -or [System.Text.Encoding]::ASCII.GetString($Data, 36, 4) -cne 'acsp')
    {
        return
    }

    $declaredSize = ([System.Int64] $Data[0] -shl 24) -bor ([System.Int64] $Data[1] -shl 16) -bor ([System.Int64] $Data[2] -shl 8) -bor [System.Int64] $Data[3]
    if ($declaredSize -lt 132 -or $declaredSize -ge $Data.Length)
    {
        return
    }

    # The data is longer than the declared size, so the tag count (bytes 128 to 131) is there. Int64 keeps 12 times any count exact.
    $tagCount = ([System.Int64] $Data[128] -shl 24) -bor ([System.Int64] $Data[129] -shl 16) -bor ([System.Int64] $Data[130] -shl 8) -bor [System.Int64] $Data[131]
    if ($declaredSize -lt 132 + 12 * $tagCount)
    {
        return
    }

    $trimmed = [System.Byte[]]::new($declaredSize)
    [System.Array]::Copy($Data, $trimmed, $declaredSize)

    Write-Output -InputObject $trimmed -NoEnumerate
}
