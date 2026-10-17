function Read-ImageConverterImage
{
    <#
        .SYNOPSIS
        Reads an image file with Magick.NET and returns the image or the exception.

        .DESCRIPTION
        Reads the image file into a MagickImage and returns an object with the properties Result
        (the image, which the caller disposes) and Exception (why it could not be read); exactly
        one of them is set, and no exception reaches the caller. ImageMagick treats a file name
        that ends with a bracket expression such as 'scan[1]' as a frame selector and opens
        'scan' instead, so such a file is read from a stream; the format is then detected from
        the content. Every other file is read by name, where ImageMagick also uses the extension
        for formats it cannot detect from the content.

        .PARAMETER Path
        The full path of the image file to read.

        .EXAMPLE
        Read-ImageConverterImage -Path 'C:\Pictures\IMG_1234.HEIC'

        Returns an object whose Result property holds the decoded image.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    if (-not [System.IO.Path]::GetFileName($Path).EndsWith(']'))
    {
        return Invoke-ImageConverterMethod -Type ([ImageMagick.MagickImage]) -ArgumentList $Path
    }

    $open = Invoke-ImageConverterMethod -Type ([System.IO.FileStream]) -ArgumentList $Path, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::ReadWrite)

    if ($null -ne $open.Exception)
    {
        return $open
    }

    try
    {
        Invoke-ImageConverterMethod -Type ([ImageMagick.MagickImage]) -ArgumentList $open.Result
    }
    finally
    {
        $open.Result.Dispose()
    }
}
