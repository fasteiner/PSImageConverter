function ConvertTo-PSHeicDateTime
{
    <#
        .SYNOPSIS
        Parses an EXIF date string into a DateTime.

        .DESCRIPTION
        Parses EXIF date values in the 'yyyy:MM:dd HH:mm:ss' format (as used by
        DateTimeOriginal and DateTime) into a DateTime. Returns null for empty or
        unparseable values instead of throwing, as camera metadata is often malformed.

        .PARAMETER Value
        The EXIF date string to parse, e.g. '2026:10:17 18:21:00'.

        .EXAMPLE
        ConvertTo-PSHeicDateTime -Value '2026:10:17 18:21:00'
    #>
    [CmdletBinding()]
    [OutputType([System.DateTime])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Value
    )

    if ([System.String]::IsNullOrWhiteSpace($Value))
    {
        return $null
    }

    $result = [System.DateTime]::MinValue
    $isParsed = [System.DateTime]::TryParseExact(
        $Value.Trim(),
        'yyyy:MM:dd HH:mm:ss',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref] $result
    )

    if ($isParsed)
    {
        return $result
    }

    return $null
}
