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
        pattern (e.g. 'a[.jpg') an InvalidWildcardPattern error and a path of another provider
        (Registry, Env:, ...) an UnsupportedProvider error; each is written once through the
        cmdlet passed in -Cmdlet and processing continues with the next item.

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

        <#
            Resolve-Path throws a terminating error for an invalid pattern that names an existing
            file, which -ErrorAction Ignore does not suppress; the compiled call returns it instead.
        #>
        $resolve = Invoke-ImageConverterMethod -InputObject $Cmdlet.SessionState.Path -Name 'GetResolvedPSPathFromPSPath' -ArgumentList $pattern

        if ($resolve.Exception -is [System.Management.Automation.WildcardPatternException])
        {
            $exception = [System.ArgumentException]::new("The path '$item' is not a valid wildcard pattern. Use -LiteralPath for a file name that contains [ or ].", $resolve.Exception)
            Write-ImageConverterError -Cmdlet $Cmdlet -Exception $exception -ErrorId 'InvalidWildcardPattern' -Category 'InvalidArgument' -TargetObject $item
            continue
        }

        if ($null -ne $resolve.Exception -or $resolve.Result.Count -eq 0)
        {
            $exception = [System.Management.Automation.ItemNotFoundException]::new("Cannot find path '$item' because it does not exist.", $resolve.Exception)
            Write-ImageConverterError -Cmdlet $Cmdlet -Exception $exception -ErrorId 'PathNotFound' -Category 'ObjectNotFound' -TargetObject $item
            continue
        }

        foreach ($resolvedPath in $resolve.Result)
        {
            if ($resolvedPath.Provider.ImplementingType -ne [Microsoft.PowerShell.Commands.FileSystemProvider])
            {
                $exception = [System.ArgumentException]::new("The path '$($resolvedPath.Path)' belongs to the $($resolvedPath.Provider.Name) provider. Only file system paths are supported.")
                Write-ImageConverterError -Cmdlet $Cmdlet -Exception $exception -ErrorId 'UnsupportedProvider' -Category 'InvalidArgument' -TargetObject $item
                continue
            }

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
