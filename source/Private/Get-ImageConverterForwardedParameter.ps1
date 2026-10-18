function Get-ImageConverterForwardedParameter
{
    <#
        .SYNOPSIS
        Returns the parameters a wrapper cmdlet passes on to its Convert-Image call.

        .DESCRIPTION
        Copies the bound parameters of a wrapper (ConvertTo-Jpeg, ConvertFrom-Heic, ...) into a
        new hashtable for the Convert-Image call of its steppable pipeline and sets -Format.
        Common parameters such as -WhatIf, -Confirm, -ErrorAction and -Verbose are kept, so
        Convert-Image behaves as if it had been called directly. The common parameters that
        name a variable or buffer the output (-ErrorVariable, -WarningVariable,
        -InformationVariable, -OutVariable, -PipelineVariable, -OutBuffer) are removed: the
        wrapper already applies them to everything Convert-Image writes through it. Passed on,
        the '+name' form would collect every record twice, -PipelineVariable would stay empty
        and a variable named like one of the wrapper's own variables would replace it.

        .PARAMETER BoundParameter
        The $PSBoundParameters of the wrapper cmdlet; it is copied, not changed.

        .PARAMETER Format
        The output format the wrapper converts to, e.g. Jpeg; set as -Format of Convert-Image.

        .PARAMETER ExcludeParameter
        Further parameter names the wrapper handles itself, e.g. Path and LiteralPath.

        .EXAMPLE
        Get-ImageConverterForwardedParameter -BoundParameter $PSBoundParameters -Format 'Jpeg'

        Returns the wrapper's parameters with Format = 'Jpeg' for Convert-Image.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.IDictionary]
        $BoundParameter,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Format,

        [Parameter()]
        [System.String[]]
        $ExcludeParameter = @()
    )

    $forwarded = @{}

    foreach ($name in $BoundParameter.Keys)
    {
        if ($name -notin @('ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'PipelineVariable', 'OutBuffer') -and $name -notin $ExcludeParameter)
        {
            $forwarded[$name] = $BoundParameter[$name]
        }
    }

    $forwarded['Format'] = $Format

    $forwarded
}
