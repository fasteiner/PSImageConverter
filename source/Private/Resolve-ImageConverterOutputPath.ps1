function Resolve-ImageConverterOutputPath
{
    <#
        .SYNOPSIS
        Builds and checks the full output path for a converted image.

        .DESCRIPTION
        Combines the destination folder (or the source file's folder when none is given)
        with the source file's base name and the new extension, and returns the full path.
        Returns nothing and writes an error through the cmdlet passed in -Cmdlet when the
        destination is not usable (InvalidDestinationPath, UnsupportedProvider,
        DestinationNotDirectory), the target is the source file itself (TargetIsSource), an
        earlier source of the same call already maps to it or wrote it (DuplicateTarget) or it
        already exists (TargetExists). -Force only lifts TargetExists for an existing file.
        An existing target is compared with the source and with the files written earlier in
        the call by file identity, so another spelling of the same file (a junction, a symbolic
        link to a folder, a subst drive, a UNC path, another letter case on a case-insensitive
        file system) is detected as well. Nothing is created here, so -WhatIf callers stay free
        of side effects.

        .PARAMETER Cmdlet
        The $PSCmdlet of the public cmdlet that reports the errors, e.g. Convert-Image.

        .PARAMETER SourcePath
        The full path of the source image file the output path is derived from.

        .PARAMETER Extension
        The extension of the output file including the leading dot, e.g. '.jpg'.

        .PARAMETER DestinationPath
        Optional folder for the output file. Defaults to the source file's folder.

        .PARAMETER ClaimedTarget
        The targets earlier sources of the same call map to (target path to source path).

        .PARAMETER WrittenTarget
        The files written earlier in the same call (file identity to source path).

        .PARAMETER Force
        Allows an existing output file, which the conversion then overwrites.

        .EXAMPLE
        Resolve-ImageConverterOutputPath -Cmdlet $PSCmdlet -SourcePath 'C:\Pictures\IMG_1234.HEIC' -Extension '.jpg' -ClaimedTarget $claimedTargets

        Returns 'C:\Pictures\IMG_1234.jpg' unless that file already exists.
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
        $SourcePath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Extension,

        [Parameter()]
        [System.String]
        $DestinationPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[System.String, System.String]]
        $ClaimedTarget,

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[System.String, System.String]]
        $WrittenTarget,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    $folder = $null

    if (-not [System.String]::IsNullOrEmpty($DestinationPath))
    {
        $destination = Resolve-ImageConverterDestinationPath -DestinationPath $DestinationPath

        if ($null -ne $destination.ErrorId)
        {
            Write-ImageConverterError -Cmdlet $Cmdlet -Exception $destination.Exception -ErrorId $destination.ErrorId -Category 'InvalidArgument' -TargetObject $SourcePath
            return
        }

        $folder = $destination.Path
    }

    $targetPath = Get-ImageConverterTargetPath -SourcePath $SourcePath -Extension $Extension -Folder $folder
    $sourceFullPath = [System.IO.Path]::GetFullPath($SourcePath)
    $isSource = [System.String]::Equals($targetPath, $sourceFullPath, [System.StringComparison]::Ordinal)
    $writtenBy = $null

    if (-not $isSource -and -not $ClaimedTarget.ContainsKey($targetPath) -and [System.IO.File]::Exists($targetPath))
    {
        <#
            The source exists, so a target that does not exist cannot be the source. For an existing
            one the file identity decides, independent of the path spelling and of whether the file
            system ignores case. Without an identity, the platform's usual case rule is the fallback.
        #>
        $targetIdentity = Get-ImageConverterFileIdentity -Path $targetPath
        $sourceIdentity = Get-ImageConverterFileIdentity -Path $sourceFullPath

        if ($null -ne $targetIdentity -and $null -ne $sourceIdentity)
        {
            $isSource = $targetIdentity -eq $sourceIdentity
        }
        else
        {
            $isSource = (Get-ImageConverterPathComparer).Equals($targetPath, $sourceFullPath)
        }

        if ($null -ne $targetIdentity -and $null -ne $WrittenTarget -and $WrittenTarget.ContainsKey($targetIdentity))
        {
            $writtenBy = $WrittenTarget[$targetIdentity]
        }
    }

    if ($isSource)
    {
        $exception = [System.ArgumentException]::new("The target '$targetPath' is the source file itself. Choose another output format or a -DestinationPath.")
        Write-ImageConverterError -Cmdlet $Cmdlet -Exception $exception -ErrorId 'TargetIsSource' -Category 'InvalidArgument' -TargetObject $SourcePath
        return
    }

    if ($ClaimedTarget.ContainsKey($targetPath))
    {
        $writtenBy = $ClaimedTarget[$targetPath]
    }

    if ($null -ne $writtenBy)
    {
        $exception = [System.IO.IOException]::new("The target '$targetPath' is already the target of '$writtenBy' in this call. Convert the files into different folders.")
        Write-ImageConverterError -Cmdlet $Cmdlet -Exception $exception -ErrorId 'DuplicateTarget' -Category 'ResourceExists' -TargetObject $SourcePath
        return
    }

    if ([System.IO.Directory]::Exists($targetPath))
    {
        $exception = [System.IO.IOException]::new("The target '$targetPath' is an existing folder.")
        Write-ImageConverterError -Cmdlet $Cmdlet -Exception $exception -ErrorId 'TargetExists' -Category 'ResourceExists' -TargetObject $SourcePath
        return
    }

    if ([System.IO.File]::Exists($targetPath) -and -not $Force)
    {
        $exception = [System.IO.IOException]::new("The file '$targetPath' already exists. Use -Force to overwrite it.")
        Write-ImageConverterError -Cmdlet $Cmdlet -Exception $exception -ErrorId 'TargetExists' -Category 'ResourceExists' -TargetObject $SourcePath
        return
    }

    return $targetPath
}
