function Resolve-ImageConverterInputPath
{
    <#
        .SYNOPSIS
        Resolves -Path or -LiteralPath input of a cmdlet to the full paths of the files.

        .DESCRIPTION
        Resolves each -Path item with wildcard expansion or each -LiteralPath item as is and
        returns the full, normalised file system path of every file it stands for (short 8.3
        names are expanded, so one file always has one spelling). Folders are skipped
        (Write-Verbose), so the output of Get-ChildItem -Recurse can be piped in. An item that
        matches nothing gets a PathNotFound error, a -Path item that is not a valid wildcard
        pattern (e.g. 'a[.jpg', whether or not a file of that name exists) an
        InvalidWildcardPattern error and a path of another provider (Registry, Env:, ...) an
        UnsupportedProvider error, one for the item also when its pattern matches several
        items there; each is written once through the cmdlet passed in -Cmdlet with the item
        as given as target object, and processing continues with the next item. A path on a
        PSDrive that the caller created in a scope the module cannot see is not resolved (the
        module would not find the drive, or resolve the path on a global drive of the same
        name) and gets PathNotFound, too. The PathNotFound message comes from
        Get-ImageConverterPathNotFoundMessage: it explains such a drive, and for a wildcard
        pattern it names a drive or folder that does not exist or, when the folder exists, that
        wildcards skip hidden files (on Linux and macOS: names starting with a dot) and that
        [ and ] are wildcard characters.

        .PARAMETER Path
        Paths to resolve with wildcard expansion, e.g. 'C:\Pictures\*.heic'.

        .PARAMETER LiteralPath
        Paths to resolve exactly as written; wildcard characters are part of the file name.

        .PARAMETER Cmdlet
        The $PSCmdlet of the public cmdlet that reports the errors, e.g. Convert-Image.

        .EXAMPLE
        Resolve-ImageConverterInputPath -Path 'C:\Pictures\*.heic' -Cmdlet $PSCmdlet

        Returns the full path of every HEIC file in C:\Pictures.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [System.String[]]
        $Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'LiteralPath')]
        [System.String[]]
        $LiteralPath,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]
        $Cmdlet
    )

    $items = $Path
    if ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
    {
        $items = $LiteralPath
    }

    foreach ($item in $items)
    {
        $pattern = $item
        if ($PSCmdlet.ParameterSetName -eq 'LiteralPath')
        {
            $pattern = [System.Management.Automation.WildcardPattern]::Escape($item)
        }

        $isPattern = $PSCmdlet.ParameterSetName -eq 'Path' -and [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($item)
        $resolve = $null
        $found = $false
        $patternException = $null

        <#
            The module does not find a drive that the caller created in its own scope, or it resolves the
            path on a global drive of the same name, which would read other files; such a path is not
            resolved at all.
        #>
        if ($null -eq (Get-ImageConverterDriveScopeHint -Cmdlet $Cmdlet -Path $item -RelativeToLocation))
        {
            <#
                Resolve-Path throws a terminating error for an invalid pattern that names an existing
                file, which -ErrorAction Ignore does not suppress; the compiled call returns it instead.
            #>
            $resolve = Invoke-ImageConverterMethod -InputObject $Cmdlet.SessionState.Path -Name 'GetResolvedPSPathFromPSPath' -ArgumentList $pattern
            $found = $null -eq $resolve.Exception -and $resolve.Result.Count -gt 0

            if ($resolve.Exception -is [System.Management.Automation.WildcardPatternException])
            {
                $patternException = $resolve.Exception
            }
            elseif (-not $found -and $isPattern)
            {
                # The resolver checks the pattern only against an existing file of that literal name; otherwise it finds nothing.
                $patternException = (Invoke-ImageConverterMethod -InputObject ([System.Management.Automation.WildcardPattern]::new($item)) -Name 'IsMatch' -ArgumentList '').Exception
            }
        }

        if ($patternException -is [System.Management.Automation.WildcardPatternException])
        {
            $exception = [System.ArgumentException]::new("The path '$item' is not a valid wildcard pattern. Use -LiteralPath for a file name that contains [ or ].", $patternException)
            Write-ImageConverterError -Cmdlet $Cmdlet -Exception $exception -ErrorId 'InvalidWildcardPattern' -Category 'InvalidArgument' -TargetObject $item
            continue
        }

        if (-not $found)
        {
            $message = Get-ImageConverterPathNotFoundMessage -Cmdlet $Cmdlet -Path $item -IsPattern:$isPattern -Exception $resolve.Exception
            $exception = [System.Management.Automation.ItemNotFoundException]::new($message, $resolve.Exception)
            Write-ImageConverterError -Cmdlet $Cmdlet -Exception $exception -ErrorId 'PathNotFound' -Category 'ObjectNotFound' -TargetObject $item
            continue
        }

        # A pattern resolves within one provider, so a pattern of another provider gets one error, not one per match.
        $provider = $resolve.Result[0].Provider
        if ($provider.ImplementingType -ne [Microsoft.PowerShell.Commands.FileSystemProvider])
        {
            $exception = [System.ArgumentException]::new("The path '$item' belongs to the $($provider.Name) provider. Only file system paths are supported.")
            Write-ImageConverterError -Cmdlet $Cmdlet -Exception $exception -ErrorId 'UnsupportedProvider' -Category 'InvalidArgument' -TargetObject $item
            continue
        }

        foreach ($resolvedPath in $resolve.Result)
        {
            $fullPath = [System.IO.Path]::GetFullPath($resolvedPath.ProviderPath)

            if ([System.IO.Directory]::Exists($fullPath))
            {
                Write-Verbose -Message "Skipping the folder '$fullPath'."
                continue
            }

            $fullPath
        }
    }
}
