function Get-ImageConverterPathComparer
{
    <#
        .SYNOPSIS
        Returns the string comparer that matches how the platform compares file paths.

        .DESCRIPTION
        Returns StringComparer.OrdinalIgnoreCase on Windows and macOS, whose default file
        systems treat 'a.JPG' and 'a.jpg' as the same file, and StringComparer.Ordinal on
        Linux. The cmdlets use it for paths of files that may not exist yet: two sources of one
        call that map to the same target, a source given twice. Existing files are compared by
        file identity, which also covers volumes that do not follow the platform's usual rule
        (an exFAT card on Linux); this comparer is the fallback when no identity can be read.

        .PARAMETER Platform
        The operating system platform. Defaults to the platform of the current session.

        .EXAMPLE
        Get-ImageConverterPathComparer -Platform 'Linux'

        Returns StringComparer.Ordinal.
    #>
    [CmdletBinding()]
    [OutputType([System.StringComparer])]
    param
    (
        [Parameter()]
        [ValidateSet('Windows', 'Linux', 'OSX')]
        [System.String]
        $Platform
    )

    if (-not $PSBoundParameters.ContainsKey('Platform'))
    {
        $Platform = 'Windows'

        if ($IsLinux)
        {
            $Platform = 'Linux'
        }
    }

    if ($Platform -eq 'Linux')
    {
        return [System.StringComparer]::Ordinal
    }

    return [System.StringComparer]::OrdinalIgnoreCase
}
