function Get-ImageConverterDriveScopeHint
{
    <#
        .SYNOPSIS
        Explains a path whose PSDrive the caller created in a scope the module cannot see.

        .DESCRIPTION
        A script module resolves paths in its own session state, which sees the global PSDrives
        but not a drive created without -Scope Global inside a function, in a script run with &
        or by its path, or in another module. A path on such a drive is not found there, or,
        when a global drive has the same name, it silently resolves on that global drive. For a
        drive-qualified -Path, and with -RelativeToLocation also for a relative path while the
        current location is on such a drive, this returns a sentence that names the drive and
        its root and suggests New-PSDrive -Scope Global (or a name no global drive has) or the
        file system path; for a drive of another provider it says that only file system paths
        are supported. It returns nothing when the module sees the same drive as the caller, for
        a provider-qualified path, a path below ~, a UNC path, and for a drive the caller does
        not know either. The caller is the code that called the public cmdlet in -Cmdlet: for
        Convert-Image run by a ConvertTo-* wrapper of this module, the code that called the
        wrapper.

        .PARAMETER Cmdlet
        The $PSCmdlet of the public cmdlet that resolves the path, e.g. Convert-Image.

        .PARAMETER Path
        The path as the user gave it, e.g. 'Photos:\IMG_1.heic' or '.\*.heic'.

        .PARAMETER RelativeToLocation
        Checks the drive of the current location for a relative path, too. Input paths need
        it; a relative -DestinationPath resolves on the right drive.

        .EXAMPLE
        Get-ImageConverterDriveScopeHint -Cmdlet $PSCmdlet -Path 'Photos:\IMG_1.heic'

        Returns "drive 'Photos' was created in a scope ..." when the caller created the drive
        Photos in a function, and nothing for a global drive.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]
        $Cmdlet,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $RelativeToLocation
    )

    # A provider-qualified path names no drive, and ~ and UNC paths do not depend on the drive of the current location.
    if ($Path.Contains('::') -or $Path -match '^(~([\\/]|$)|[\\/]{2})')
    {
        return
    }

    <#
        The out parameter returns the drive of a drive-qualified path, and that of the current location
        for a relative one; the module and its caller share the current location, by drive name.
    #>
    $absolute = Invoke-ImageConverterMethod -InputObject $Cmdlet.SessionState.Path -Name 'IsPSAbsolute' -ArgumentList $Path, $null
    $driveName = $absolute.Arguments[1]

    if ((-not $absolute.Result -and -not $RelativeToLocation) -or [System.String]::IsNullOrEmpty($driveName))
    {
        return
    }

    # The session state of the code that called the cmdlet: its own scopes are the ones that can hold such a drive.
    $sessionState = $Cmdlet.SessionState

    <#
        A ConvertTo-* wrapper runs Convert-Image through a steppable pipeline, so Convert-Image is called
        by this module and its caller's session state is the module's. The drive is then known to the
        code that called the wrapper, whose session state the wrapper's $PSCmdlet holds: the call stack
        frame below Convert-Image's own frame is the wrapper's.
    #>
    if ($sessionState.Module -eq $ExecutionContext.SessionState.Module)
    {
        $frames = @(Get-PSCallStack)

        for ($index = 0; $index -lt $frames.Count - 1; $index++)
        {
            if ([System.Object]::ReferenceEquals($frames[$index].InvocationInfo, $Cmdlet.MyInvocation))
            {
                $callerVariables = $frames[$index + 1].GetFrameVariables()

                if ($callerVariables.ContainsKey('PSCmdlet') -and $callerVariables['PSCmdlet'].Value -is [System.Management.Automation.PSCmdlet])
                {
                    $sessionState = $callerVariables['PSCmdlet'].Value.SessionState
                }

                break
            }
        }
    }

    $callerDrive = (Invoke-ImageConverterMethod -InputObject $sessionState.Drive -Name 'Get' -ArgumentList $driveName).Result
    $moduleDrive = (Invoke-ImageConverterMethod -InputObject $ExecutionContext.SessionState.Drive -Name 'Get' -ArgumentList $driveName).Result

    if ($null -eq $callerDrive -or [System.Object]::ReferenceEquals($callerDrive, $moduleDrive))
    {
        return
    }

    # Making such a drive global would only lead to UnsupportedProvider.
    if ($callerDrive.Provider.ImplementingType -ne [Microsoft.PowerShell.Commands.FileSystemProvider])
    {
        return "drive '$($callerDrive.Name)' belongs to the $($callerDrive.Provider.Name) provider. Only file system paths are supported."
    }

    $scope = "drive '$($callerDrive.Name)' was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module)"

    if ($null -eq $moduleDrive)
    {
        return "$scope. Create the drive with New-PSDrive -Scope Global, or use the file system path; the root of the drive is '$($callerDrive.Root)'."
    }

    "$scope, so the module would use the global drive of that name, whose root is '$($moduleDrive.Root)'. Give the drive a name that no global drive has, or use the file system path; the root of the drive is '$($callerDrive.Root)'."
}
