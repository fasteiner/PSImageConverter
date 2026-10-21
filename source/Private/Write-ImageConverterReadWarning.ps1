function Write-ImageConverterReadWarning
{
    <#
        .SYNOPSIS
        Reports the warnings ImageMagick raised while reading a source image.

        .DESCRIPTION
        Magick.NET reads a damaged file such as a truncated JPEG without an exception: libjpeg
        reports the missing data as a warning and the missing part is filled in grey. Magick.NET
        raises one warning per read, the one of the highest severity, and attaches the other
        warnings of that read as its RelatedExceptions, so every warning and every related
        exception is evaluated. Those of the type MagickCorruptImageWarningException, and a
        MagickCorruptImageErrorException that Read-ImageConverterImage got when it counted the
        frames of a file whose first frame it could read, become one PowerShell warning per
        source, written through the cmdlet passed in -Cmdlet: 'The image may be damaged
        (<messages>): <path>', with every distinct message once. All other warnings (e.g.
        libpng complaining about a known incorrect sRGB profile) do not affect the image and
        only go to the verbose stream. The file name and the source code location ImageMagick
        appends to its messages are removed. Nothing is written when there are no warnings.

        .PARAMETER Cmdlet
        The $PSCmdlet of the public cmdlet that writes the warning, e.g. Convert-Image.

        .PARAMETER Path
        The path of the source image the warnings are about, shown at the end of the warning.

        .PARAMETER Warning
        The warnings raised while reading the image, as returned by Read-ImageConverterImage.

        .EXAMPLE
        Write-ImageConverterReadWarning -Cmdlet $PSCmdlet -Path $sourcePath -Warning $read.Warnings

        Writes 'The image may be damaged (Premature end of JPEG file; Corrupt JPEG data:
        premature end of data segment): C:\Pictures\cut.jpg' for a truncated JPEG.
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]
        $Cmdlet,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [ImageMagick.MagickException[]]
        $Warning
    )

    $damage = [System.Collections.Generic.List[System.String]]::new()
    $other = [System.Collections.Generic.List[System.String]]::new()

    $items = foreach ($item in $Warning)
    {
        $item
        $item.RelatedExceptions
    }

    foreach ($item in $items)
    {
        # ImageMagick formats its messages as "<reason> `<file name>' @ <severity>/<source file>/<function>/<line>".
        $message = $item.Message -replace ' @ [^ ]+$', '' -replace ' `.*''$', ''

        if ($item -is [ImageMagick.MagickCorruptImageWarningException] -or $item -is [ImageMagick.MagickCorruptImageErrorException])
        {
            if (-not $damage.Contains($message))
            {
                $damage.Add($message)
            }
        }
        elseif (-not $other.Contains($message))
        {
            $other.Add($message)
        }
    }

    foreach ($message in $other)
    {
        Write-Verbose -Message "ImageMagick warning while reading '$Path': $message"
    }

    if ($damage.Count -gt 0)
    {
        $Cmdlet.WriteWarning(('The image may be damaged ({0}): {1}' -f ($damage -join '; '), $Path))
    }
}
