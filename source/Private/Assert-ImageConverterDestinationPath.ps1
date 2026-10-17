function Assert-ImageConverterDestinationPath
{
    <#
        .SYNOPSIS
        Checks -DestinationPath once per call and stops the call when it cannot name a folder.

        .DESCRIPTION
        Resolves -DestinationPath with Resolve-ImageConverterDestinationPath and returns the full
        path of the destination folder, or nothing when no destination is given. A destination
        that cannot name a folder fails every file, so it is a parameter error and stops the
        whole call with one terminating error through the cmdlet passed in -Cmdlet instead of
        one error per source: InvalidDestinationPath (white space only, unknown drive or provider, a
        drive-qualified path that climbs above the root of its drive, invalid characters),
        UnsupportedProvider (not a file system path) or DestinationNotDirectory (the path or one
        of its parent folders is an existing file, or a link whose target does not exist). The
        target object of the error is the -DestinationPath value as given. A folder that does not
        exist yet is fine; it is created later, inside ShouldProcess, so a folder that cannot be
        created or written to fails each file with ImageWriteFailed.

        .PARAMETER Cmdlet
        The $PSCmdlet of the public cmdlet that reports the error, e.g. Convert-Image.

        .PARAMETER DestinationPath
        The destination folder as given by the user; empty or null when none is given.

        .EXAMPLE
        $destinationFolder = Assert-ImageConverterDestinationPath -Cmdlet $PSCmdlet -DestinationPath $DestinationPath

        Returns the full folder path, or throws DestinationNotDirectory when the path is a file.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]
        $Cmdlet,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $DestinationPath
    )

    if ([System.String]::IsNullOrEmpty($DestinationPath))
    {
        return
    }

    $destination = Resolve-ImageConverterDestinationPath -DestinationPath $DestinationPath

    if ($null -ne $destination.ErrorId)
    {
        Write-ImageConverterError -Cmdlet $Cmdlet -Exception $destination.Exception -ErrorId $destination.ErrorId -Category 'InvalidArgument' -TargetObject $DestinationPath -Terminating
    }

    $destination.Path
}
