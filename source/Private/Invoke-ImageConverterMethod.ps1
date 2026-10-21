function Invoke-ImageConverterMethod
{
    <#
        .SYNOPSIS
        Calls a .NET constructor or method and returns its exception instead of throwing it.

        .DESCRIPTION
        Runs a constructor (-Type without -Name), a static method (-Type with -Name) or an
        instance method (-InputObject with -Name) in compiled code that catches the exception
        (PSImageConverter.SafeInvoker in the helper assembly), and returns an object with the
        properties Result, Exception and Arguments. Exactly one of Result and Exception is set;
        Arguments holds the argument values after the call, so out parameters can be read from
        it. PowerShell records every exception that reaches a script in $Error and in the
        -ErrorVariable of each calling advanced function, also when a catch block handles it,
        so a failure the cmdlets report as one error record would otherwise show up twice.

        .PARAMETER Type
        The .NET type whose constructor (without -Name) or static method (with -Name) is called.

        .PARAMETER InputObject
        The object whose instance method is called. Requires the method name in -Name.

        .PARAMETER Name
        The name of the method to call. Without it, the constructor of -Type is called.

        .PARAMETER ArgumentList
        The arguments for the constructor or method, in the order of its parameters. Pass
        $null for an out parameter and read its value from the Arguments property.

        .EXAMPLE
        Invoke-ImageConverterMethod -Type ([System.IO.File]) -Name 'Move' -ArgumentList $tempPath, $targetPath, $true

        Moves the file and returns the exception in the Exception property if the move fails.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Static')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'Static')]
        [System.Type]
        $Type,

        [Parameter(Mandatory = $true, ParameterSetName = 'Instance')]
        [System.Object]
        $InputObject,

        [Parameter(ParameterSetName = 'Static')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Instance')]
        [System.String]
        $Name,

        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [System.Object[]]
        $ArgumentList = @()
    )

    $target = $null
    if ($PSCmdlet.ParameterSetName -eq 'Instance')
    {
        $target = $InputObject
        $Type = $InputObject.GetType()
    }

    # An unbound -Name arrives as an empty string, which the helper class treats as the constructor.
    $result = $null
    $argumentValues = $null
    $exception = [PSImageConverter.SafeInvoker]::Invoke($Type, $target, $Name, $ArgumentList, [ref] $result, [ref] $argumentValues)

    [PSCustomObject] @{
        Result    = $result
        Exception = $exception
        Arguments = $argumentValues
    }
}
