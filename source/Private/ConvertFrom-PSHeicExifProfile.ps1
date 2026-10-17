function ConvertFrom-PSHeicExifProfile
{
    <#
        .SYNOPSIS
        Converts a Magick.NET EXIF profile into a hashtable keyed by tag name.

        .DESCRIPTION
        Iterates the Values of a Magick.NET IExifProfile and returns a hashtable that
        maps each tag name (e.g. Make, Model, DateTimeOriginal) to its value. String
        values are trimmed of trailing NUL characters and whitespace. Returns an empty
        hashtable when no profile is given.

        .PARAMETER ExifProfile
        The EXIF profile as returned by MagickImage.GetExifProfile(). May be null.

        .EXAMPLE
        ConvertFrom-PSHeicExifProfile -ExifProfile $image.GetExifProfile()
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.Object]
        $ExifProfile
    )

    $data = @{}

    if ($null -eq $ExifProfile)
    {
        return $data
    }

    foreach ($exifValue in $ExifProfile.Values)
    {
        $value = $exifValue.GetValue()

        if ($value -is [System.String])
        {
            $value = $value.TrimEnd([char] 0).Trim()
        }

        $data["$($exifValue.Tag)"] = $value
    }

    return $data
}
