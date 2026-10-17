BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')

    # Reads the image, applies its orientation as Convert-Image does, repairs the metadata and returns the image.
    function Invoke-Repair
    {
        param ([System.String] $Path)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ ImagePath = $Path } {
            $image = [ImageMagick.MagickImage]::new($ImagePath)
            $image.AutoOrient()
            Repair-ImageConverterProfileOrientation -Image $image
            $image
        }
    }

    function Get-XmpPacket
    {
        param ([ImageMagick.MagickImage] $Image)

        [System.Text.Encoding]::UTF8.GetString($Image.GetXmpProfile().ToByteArray())
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Repair-ImageConverterProfileOrientation' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should remove the EXIF thumbnail and keep the other EXIF values' {
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'camera.jpg') -Width 60 -Height 40 -Orientation 6 -ExifThumbnail

        $image = Invoke-Repair -Path $source.FullName
        try
        {
            $exifProfile = $image.GetExifProfile()
            $exifProfile.ThumbnailLength | Should -Be 0
            $exifProfile.GetValue([ImageMagick.ExifTag]::Orientation).Value | Should -Be 1
            $exifProfile.GetValue([ImageMagick.ExifTag]::Make).Value | Should -Be 'TestCam'
        }
        finally
        {
            $image.Dispose()
        }
    }

    It 'Should leave an EXIF profile without thumbnail as it is' {
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'plain.jpg') -Orientation 6
        $original = [ImageMagick.MagickImage]::new($source.FullName)
        try
        {
            $originalBytes = $original.GetExifProfile().ToByteArray()
        }
        finally
        {
            $original.Dispose()
        }

        $image = Invoke-Repair -Path $source.FullName
        try
        {
            [System.Convert]::ToBase64String($image.GetExifProfile().ToByteArray()) | Should -Be ([System.Convert]::ToBase64String($originalBytes))
        }
        finally
        {
            $image.Dispose()
        }
    }

    It 'Should set the XMP orientation to 1 and the XMP dimensions to the new size in the <Form> form' -ForEach @(
        @{ Form = 'attribute'; Template = '<rdf:Description rdf:about="" xmlns:tiff="http://ns.adobe.com/tiff/1.0/" xmlns:exif="http://ns.adobe.com/exif/1.0/" tiff:Orientation="6" exif:PixelXDimension="60" exif:PixelYDimension="20"/>' }
        @{ Form = 'element'; Template = '<rdf:Description rdf:about="" xmlns:tiff="http://ns.adobe.com/tiff/1.0/" xmlns:exif="http://ns.adobe.com/exif/1.0/"><tiff:Orientation>6</tiff:Orientation><exif:PixelXDimension>60</exif:PixelXDimension><exif:PixelYDimension>20</exif:PixelYDimension></rdf:Description>' }
    ) {
        $path = Join-Path -Path $script:tempDir.FullName -ChildPath 'exported.jpg'
        $image = [ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new('#4080C0'), 60, 20)
        try
        {
            $packet = '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?><x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">{0}</rdf:RDF></x:xmpmeta><?xpacket end="w"?>' -f $Template
            $image.SetProfile([ImageMagick.XmpProfile]::new([System.Text.Encoding]::UTF8.GetBytes($packet)))
            # The EXIF orientation is what the image is rotated by, as in a real export.
            $exifProfile = [ImageMagick.ExifProfile]::new()
            $exifProfile.SetValue([ImageMagick.ExifTag]::Orientation, [System.UInt16] 6)
            $image.SetProfile($exifProfile)
            $image.Orientation = [ImageMagick.OrientationType]::RightTop
            $image.Write($path, [ImageMagick.MagickFormat]::Jpeg)
        }
        finally
        {
            $image.Dispose()
        }

        $repaired = Invoke-Repair -Path $path
        try
        {
            $result = Get-XmpPacket -Image $repaired
        }
        finally
        {
            $repaired.Dispose()
        }

        $result | Should -Match 'tiff:Orientation(="|>)1'
        $result | Should -Match 'exif:PixelXDimension(="|>)20'
        $result | Should -Match 'exif:PixelYDimension(="|>)60'
    }

    It 'Should leave an XMP packet without orientation as it is' {
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'creator.jpg') -Orientation 6 -Xmp
        $original = [ImageMagick.MagickImage]::new($source.FullName)
        try
        {
            $originalPacket = Get-XmpPacket -Image $original
        }
        finally
        {
            $original.Dispose()
        }

        $image = Invoke-Repair -Path $source.FullName
        try
        {
            Get-XmpPacket -Image $image | Should -Be $originalPacket
        }
        finally
        {
            $image.Dispose()
        }
    }

    It 'Should do nothing for an image without EXIF and XMP data' {
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'bare.png') -Format Png

        $image = Invoke-Repair -Path $source.FullName
        try
        {
            $image.GetExifProfile() | Should -BeNullOrEmpty
            $image.GetXmpProfile() | Should -BeNullOrEmpty
        }
        finally
        {
            $image.Dispose()
        }
    }
}
