function Import-ImageConverterCallerPreference
{
    <#
        .SYNOPSIS
        Copies the caller's preference variables into the scope of the calling public cmdlet.

        .DESCRIPTION
        A function of a script module resolves preference variables through its own module scope
        and the global scope, so it does not see the values its caller set in a local scope:
        a user's function called with -WhatIf, or a script that sets $ErrorActionPreference =
        'Stop', would not reach the cmdlet (PowerShell issue #4568). Compiled cmdlets do see
        them. This function reads WhatIfPreference, ConfirmPreference, ErrorActionPreference,
        WarningPreference, InformationPreference, VerbosePreference and DebugPreference from the
        caller's session state of the cmdlet passed in -Cmdlet and sets them in the scope this
        function was called from, which is the public cmdlet's own scope when it is called
        first thing in its begin block. A preference whose common parameter (-WhatIf, -Confirm,
        -ErrorAction, -WarningAction, -InformationAction, -Verbose, -Debug) was bound is left
        alone, so an explicit parameter wins. $PSCmdlet.ShouldProcess and WriteError read the
        variables on first use, so they follow the imported values.

        .PARAMETER Cmdlet
        The $PSCmdlet of the public cmdlet whose caller's preferences are imported.

        .EXAMPLE
        Import-ImageConverterCallerPreference -Cmdlet $PSCmdlet

        Run first in the begin block of a public cmdlet: makes it honour the -WhatIf of a user
        function that calls it.
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]
        $Cmdlet
    )

    $preferences = [ordered] @{
        WhatIf            = 'WhatIfPreference'
        Confirm           = 'ConfirmPreference'
        ErrorAction       = 'ErrorActionPreference'
        WarningAction     = 'WarningPreference'
        InformationAction = 'InformationPreference'
        Verbose           = 'VerbosePreference'
        Debug             = 'DebugPreference'
    }

    foreach ($preference in $preferences.GetEnumerator())
    {
        if ($Cmdlet.MyInvocation.BoundParameters.ContainsKey($preference.Key))
        {
            continue
        }

        # The session state of a cmdlet is the one of its caller, so the lookup starts in the caller's scope.
        $value = $Cmdlet.SessionState.PSVariable.GetValue($preference.Value)

        if ($null -ne $value)
        {
            <#
                Scope 1 is the scope of the function that called this one; a variable set here would
                end with this function. -WhatIf:$false and -Confirm:$false: Set-Variable itself would
                otherwise follow a WhatIfPreference or ConfirmPreference imported just before.
            #>
            Set-Variable -Name $preference.Value -Value $value -Scope 1 -WhatIf:$false -Confirm:$false
        }
    }
}
