function Get-ImageConverterPathNotFoundMessage
{
    <#
        .SYNOPSIS
        Returns the message of the PathNotFound error for an input that matches no file.

        .DESCRIPTION
        Builds the message that says why an input path of a public cmdlet matched no file. A path
        on a PSDrive that the caller created in a scope the module cannot see (or a relative path
        while the current location is on such a drive) gets the explanation of
        Get-ImageConverterDriveScopeHint. A wildcard pattern gets a message that names the
        likely reason: its drive does not exist; its folder does not exist or is a file; for a
        folder part with wildcards, that no folder matches it, or that wildcards do not match
        the hidden folders that do; or, when the folder exists, that wildcards do not match
        hidden files (on Linux and macOS names starting with a dot), which -LiteralPath reaches.
        Unescaped [ and ] are named as wildcard characters where they can be the reason, with a
        way to match them that works with the rest of the pattern. A pattern in a container of
        another provider (Env:\, HKCU:\) gets no hint. Any other path gets "Cannot find path
        '<path>' because it does not exist."

        .PARAMETER Cmdlet
        The $PSCmdlet of the public cmdlet that reports the error, e.g. Convert-Image.

        .PARAMETER Path
        The input as the user gave it, e.g. 'C:\Pictures\*.heic' or 'IMG_1.heic'.

        .PARAMETER IsPattern
        The input is a -Path that contains wildcard characters, so it was resolved as a pattern.

        .PARAMETER Exception
        The exception of the failed path resolution, or nothing when it simply found no file.

        .EXAMPLE
        Get-ImageConverterPathNotFoundMessage -Cmdlet $PSCmdlet -Path 'C:\Missing\*.heic' -IsPattern

        Returns "No file matches the pattern 'C:\Missing\*.heic': the folder 'C:\Missing' does not exist."
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
        $IsPattern,

        [Parameter()]
        [AllowNull()]
        [System.Exception]
        $Exception
    )

    $driveHint = Get-ImageConverterDriveScopeHint -Cmdlet $Cmdlet -Path $Path -RelativeToLocation

    if ($null -ne $driveHint)
    {
        # Without a drive name the path is relative to the current location, which is on that drive.
        if ((Invoke-ImageConverterMethod -InputObject $Cmdlet.SessionState.Path -Name 'IsPSAbsolute' -ArgumentList $Path, $null).Result)
        {
            return "Cannot resolve the path '$Path': $driveHint"
        }

        return "Cannot resolve the path '$Path', which is relative to the current location '$($Cmdlet.SessionState.Path.CurrentLocation)': $driveHint"
    }

    if (-not $IsPattern)
    {
        return "Cannot find path '$Path' because it does not exist."
    }

    if ($Exception -is [System.Management.Automation.DriveNotFoundException])
    {
        return "No file matches the pattern '$Path': the drive '$($Exception.ItemName)' does not exist."
    }

    # PowerShell's globbing leaves out hidden items, as Get-ChildItem does without -Force.
    $hiddenItems = 'hidden (dot) {0}'
    if ($IsWindows)
    {
        $hiddenItems = 'hidden {0}'
    }

    # Only providers with folders can split a path; hidden files are no matter for Env:\ and the like.
    $parentParse = Invoke-ImageConverterMethod -InputObject $Cmdlet.SessionState.Path -Name 'ParseParent' -ArgumentList $Path, $null
    if ($null -ne $parentParse.Exception)
    {
        return "No file matches the pattern '$Path'."
    }

    # An empty parent is the current location, which exists.
    $parent = $parentParse.Result
    $leaf = (Invoke-ImageConverterMethod -InputObject $Cmdlet.SessionState.Path -Name 'ParseChildName' -ArgumentList $Path).Result
    $unescapedBracket = '(?<!`)[\[\]]'

    if (-not [System.String]::IsNullOrEmpty($parent))
    {
        $parentResolve = Invoke-ImageConverterMethod -InputObject $Cmdlet.SessionState.Path -Name 'GetResolvedPSPathFromPSPath' -ArgumentList $parent

        $folderExists = $false
        $parentIsFile = $false
        foreach ($resolvedParent in $parentResolve.Result)
        {
            # A folder of another provider with folders, such as HKCU:\, gets no hint either.
            if ($resolvedParent.Provider.ImplementingType -ne [Microsoft.PowerShell.Commands.FileSystemProvider])
            {
                return "No file matches the pattern '$Path'."
            }

            if ([System.IO.Directory]::Exists($resolvedParent.ProviderPath))
            {
                $folderExists = $true
            }
            elseif ([System.IO.File]::Exists($resolvedParent.ProviderPath))
            {
                $parentIsFile = $true
            }
        }

        if (-not $folderExists)
        {
            if (-not [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($parent))
            {
                if ($parentIsFile)
                {
                    return "No file matches the pattern '$Path': '$parent' is a file, not a folder."
                }

                return "No file matches the pattern '$Path': the folder '$parent' does not exist."
            }

            $message = "No file matches the pattern '$Path': no folder matches '$parent'."

            # Globbing with force includes hidden folders: when one matches, they are the reason.
            $hiddenMatches = (Invoke-ImageConverterMethod -InputObject $Cmdlet.SessionState.InvokeProvider.Item -Name 'Get' -ArgumentList ([System.String[]] @($parent)), $true, $false).Result
            if (@($hiddenMatches | Where-Object -FilterScript { $_.PSIsContainer }).Count -gt 0)
            {
                $message = "$message Wildcards do not match $($hiddenItems -f 'folders'); a folder name without wildcards reaches them."
            }

            # 'Photos [2024]' as a pattern matches 'Photos 2', 'Photos 0' and 'Photos 4', not the folder of that name.
            if ($parent -match $unescapedBracket)
            {
                $remedy = '-LiteralPath takes the name as written.'
                if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($leaf))
                {
                    # -LiteralPath would take the wildcards of the file name literally, too.
                    $remedy = 'escape them with a backtick (`[ and `]) to match them as written.'
                }

                $message = "$message [ and ] are wildcard characters; $remedy"
            }

            return $message
        }
    }

    $hiddenFiles = $hiddenItems -f 'files'

    # A name such as 'photo[1].heic' is a pattern that matches 'photo1.heic' only.
    if ($Path -match $unescapedBracket)
    {
        $remedy = '-LiteralPath takes the name as written.'
        if (($leaf -replace $unescapedBracket, '') -match '(?<!`)[*?]')
        {
            # PowerShell finds nothing for an escaped [ or ] next to a * in the file name on Windows; ? matches them.
            $remedy = 'put ? in place of [ and ] to match them, as -LiteralPath takes no wildcards.'
        }

        return "No file matches the pattern '$Path'. [ and ] are wildcard characters, and wildcards do not match $hiddenFiles; $remedy"
    }

    "No file matches the pattern '$Path'. Wildcards do not match $hiddenFiles; -LiteralPath does."
}
