function Repair-ImageConverterProfileOrientation
{
    <#
        .SYNOPSIS
        Updates the metadata that still describes the stored orientation after auto-orient.

        .DESCRIPTION
        After AutoOrient() the pixels are upright and ImageMagick writes EXIF Orientation 1, but
        two parts of the metadata still describe the image as it was stored. The EXIF thumbnail
        (IFD1) keeps the stored orientation, so viewers that show it display it rotated against
        the photo; it is removed. The XMP packet keeps tiff:Orientation and the pixel dimensions
        exif:PixelXDimension / exif:PixelYDimension (ImageMagick only updates the element form
        of the orientation); they are set to 1 and to the new width and height, so software that
        reads the XMP orientation does not rotate the upright pixels a second time. Call it only
        after AutoOrient() changed the image, i.e. when the orientation was neither TopLeft nor
        Undefined.

        .PARAMETER Image
        The MagickImage after AutoOrient(); its EXIF and XMP profiles are replaced in place.

        .EXAMPLE
        Repair-ImageConverterProfileOrientation -Image $image

        Removes the EXIF thumbnail and sets the XMP orientation of $image to 1.
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ImageMagick.MagickImage]
        $Image
    )

    $exifProfile = $Image.GetExifProfile()

    # The EXIF profile is rewritten only when needed: rewriting can move data that other tags point to (maker notes).
    if ($null -ne $exifProfile -and $exifProfile.ThumbnailLength -gt 0)
    {
        $exifProfile.RemoveThumbnail()
        $exifProfile.SetValue([ImageMagick.ExifTag]::Orientation, [System.UInt16] 1)
        $Image.SetProfile($exifProfile)
    }

    $xmpProfile = $Image.GetXmpProfile()

    if ($null -ne $xmpProfile)
    {
        $packet = [System.Text.Encoding]::UTF8.GetString($xmpProfile.ToByteArray())
        $updated = $packet

        # Attribute form (tiff:Orientation="6") and element form (<tiff:Orientation>6</tiff:Orientation>).
        foreach ($property in @(
                @{ Name = 'tiff:Orientation'; Value = 1 }
                @{ Name = 'exif:PixelXDimension'; Value = $Image.Width }
                @{ Name = 'exif:PixelYDimension'; Value = $Image.Height }
            ))
        {
            $name = [System.Text.RegularExpressions.Regex]::Escape($property.Name)
            $updated = $updated -replace "($name\s*=\s*[`"'])\d+([`"'])", "`${1}$($property.Value)`${2}"
            $updated = $updated -replace "(<$name>)\s*\d+\s*(</$name>)", "`${1}$($property.Value)`${2}"
        }

        if ($updated -cne $packet)
        {
            $Image.SetProfile([ImageMagick.XmpProfile]::new([System.Text.Encoding]::UTF8.GetBytes($updated)))
        }
    }
}
