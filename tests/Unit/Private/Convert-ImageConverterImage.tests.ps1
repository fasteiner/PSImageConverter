BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:fixture = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')

    # Runs Convert-ImageConverterImage from an advanced script block, which provides the -Cmdlet it reports through.
    function Invoke-Conversion
    {
        param ([System.Collections.Hashtable] $Parameters)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ ConvertParameters = $Parameters } {
            $conversionErrors = $null
            $conversionWarnings = $null

            $output = & {
                [CmdletBinding()]
                param ()

                Convert-ImageConverterImage -Cmdlet $PSCmdlet @ConvertParameters
            } -ErrorAction SilentlyContinue -ErrorVariable conversionErrors -WarningAction SilentlyContinue -WarningVariable conversionWarnings

            [PSCustomObject] @{
                Output   = $output
                Errors   = @($conversionErrors)
                Warnings = @($conversionWarnings)
            }
        }
    }

    # Converts the image (lossy Jxl by default) and returns the verbose messages, the error records and the first pixel of the output.
    function Invoke-ProfileConversion
    {
        param ([System.String] $SourcePath, [System.String] $TargetPath, [System.String] $Format = 'Jxl', [System.Int32] $Quality = 90)

        $records = InModuleScope -ModuleName $script:moduleName -Parameters @{ SourcePath = $SourcePath; TargetPath = $TargetPath; Format = $Format; Quality = $Quality } {
            $verboseRecords = & {
                [CmdletBinding()]
                param ()

                Convert-ImageConverterImage -Cmdlet $PSCmdlet -SourcePath $SourcePath -TargetPath $TargetPath -Format $Format -Quality $Quality
            } -Verbose -ErrorAction SilentlyContinue -ErrorVariable conversionErrors 4>&1 | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] }

            [PSCustomObject] @{
                Verbose = "$verboseRecords"
                Errors  = @($conversionErrors)
            }
        }

        $output = [ImageMagick.MagickImage]::new($TargetPath)
        try
        {
            $color = $output.GetPixels().GetPixel(0, 0).ToColor()
            [PSCustomObject] @{
                Verbose = $records.Verbose
                Errors  = $records.Errors
                Color   = @([System.Int32] $color.R, [System.Int32] $color.G, [System.Int32] $color.B)
            }
        }
        finally
        {
            $output.Dispose()
        }
    }

    # Returns the chunk types of a PNG file, text chunks with their keyword, e.g. 'zTXt:Raw profile type icc'.
    function Get-PngChunkName
    {
        param ([System.String] $Path)

        $data = [System.IO.File]::ReadAllBytes($Path)
        $position = 8
        while ($position + 12 -le $data.Length)
        {
            $length = ([System.Int64] $data[$position] -shl 24) -bor ([System.Int64] $data[$position + 1] -shl 16) -bor ([System.Int64] $data[$position + 2] -shl 8) -bor [System.Int64] $data[$position + 3]
            $type = [System.Text.Encoding]::ASCII.GetString($data, $position + 4, 4)

            if ($type -cin @('tEXt', 'zTXt', 'iTXt'))
            {
                $keywordEnd = [System.Array]::IndexOf($data, [System.Byte] 0, $position + 8)
                $type = '{0}:{1}' -f $type, [System.Text.Encoding]::ASCII.GetString($data, $position + 8, $keywordEnd - $position - 8)
            }

            $type
            $position += 12 + $length
        }
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Convert-ImageConverterImage' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
        $script:target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.jpg'
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should write a <Format> file and return it' -ForEach @(
        @{ Format = 'Jpeg'; Extension = '.jpg' }
        @{ Format = 'Png'; Extension = '.png' }
        @{ Format = 'Gif'; Extension = '.gif' }
    ) {
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath "out$Extension"

        $result = Invoke-Conversion -Parameters @{ SourcePath = $script:fixture; TargetPath = $target; Format = $Format; Quality = 50; StripMetadata = $true }

        $result.Errors | Should -BeNullOrEmpty
        $result.Output | Should -BeOfType [System.IO.FileInfo]
        $result.Output.FullName | Should -Be $target
        (Get-ImageInfo -LiteralPath $target).Format | Should -Be $Format
    }

    It 'Should apply the quality to lossy formats' {
        $null = Invoke-Conversion -Parameters @{ SourcePath = $script:fixture; TargetPath = $script:target; Format = 'Jpeg'; Quality = 50 }

        $image = [ImageMagick.MagickImage]::new($script:target)
        try
        {
            $image.Quality | Should -Be 50
        }
        finally
        {
            $image.Dispose()
        }
    }

    It 'Should not apply the quality to <Format>, which is lossless' -ForEach @(
        @{ Format = 'Png'; Extension = '.png' }
    ) {
        # ImageMagick reads the quality of a PNG as zlib level and filter, so applying it would change the file.
        $low = Join-Path -Path $script:tempDir.FullName -ChildPath "low$Extension"
        $high = Join-Path -Path $script:tempDir.FullName -ChildPath "high$Extension"

        $null = Invoke-Conversion -Parameters @{ SourcePath = $script:fixture; TargetPath = $low; Format = $Format; Quality = 1 }
        $null = Invoke-Conversion -Parameters @{ SourcePath = $script:fixture; TargetPath = $high; Format = $Format; Quality = 100 }

        (Get-Item -LiteralPath $low).Length | Should -Be (Get-Item -LiteralPath $high).Length
    }

    It 'Should return the item of the FileSystem provider with its PSPath' {
        $result = Invoke-Conversion -Parameters @{ SourcePath = $script:fixture; TargetPath = $script:target; Format = 'Jpeg' }

        $result.Output.PSPath | Should -Be (Get-Item -LiteralPath $script:target).PSPath
        $result.Output.PSParentPath | Should -Not -BeNullOrEmpty
    }

    It 'Should write ImageWriteFailed and leave nothing behind when a step before the writing throws' {
        $rotated = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'rotated.jpg') -Orientation 6
        Mock -ModuleName $script:moduleName -CommandName Repair-ImageConverterProfileOrientation -MockWith { throw [System.InvalidOperationException]::new('broken profile') }

        $result = Invoke-Conversion -Parameters @{ SourcePath = $rotated.FullName; TargetPath = $script:target; Format = 'Jpeg' }

        $result.Output | Should -BeNullOrEmpty
        $result.Errors[-1].FullyQualifiedErrorId | Should -BeLike 'ImageWriteFailed*'
        "$($result.Errors[-1])" | Should -BeLike '*broken profile*'
        $script:target | Should -Not -Exist
        Get-ChildItem -Path $script:tempDir.FullName -Force -Filter '*.tmp' | Should -BeNullOrEmpty
    }

    It 'Should create a missing target folder' {
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'new/folder/out.png'

        $result = Invoke-Conversion -Parameters @{ SourcePath = $script:fixture; TargetPath = $target; Format = 'Png' }

        $result.Output.FullName | Should -Be $target
    }

    It 'Should write ImageReadFailed for a source that is not an image' {
        $textFile = Join-Path -Path $script:tempDir.FullName -ChildPath 'broken.heic'
        Set-Content -Path $textFile -Value 'not an image'

        $result = Invoke-Conversion -Parameters @{ SourcePath = $textFile; TargetPath = $script:target; Format = 'Jpeg' }

        $result.Output | Should -BeNullOrEmpty
        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'ImageReadFailed*'
        $result.Errors[0].TargetObject | Should -Be $textFile
        "$($result.Errors[0])" | Should -BeLike "Cannot read image '$textFile': *"
    }

    It 'Should write ImageWriteFailed when the target folder cannot be created' {
        $file = Join-Path -Path $script:tempDir.FullName -ChildPath 'file.txt'
        Set-Content -Path $file -Value 'x'

        $result = Invoke-Conversion -Parameters @{ SourcePath = $script:fixture; TargetPath = (Join-Path -Path $file -ChildPath 'out.jpg'); Format = 'Jpeg' }

        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'ImageWriteFailed*'
    }

    Context 'When writing fails' {
        It 'Should keep the existing target and delete the temporary file when Magick.NET cannot write the image' {
            Set-Content -Path $script:target -Value 'existing'
            # JPEG supports at most 65500 pixels per side, so the encoder fails after it opened the temporary file.
            $wide = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'wide.png') -Format Png -Width 70000 -Height 1

            $result = Invoke-Conversion -Parameters @{ SourcePath = $wide.FullName; TargetPath = $script:target; Format = 'Jpeg'; Force = $true }

            $result.Output | Should -BeNullOrEmpty
            $result.Errors | Should -HaveCount 1
            $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'ImageWriteFailed*'
            $result.Errors[0].CategoryInfo.Category | Should -Be 'WriteError'
            $result.Errors[0].TargetObject | Should -Be $wide.FullName
            "$($result.Errors[0])" | Should -BeLike "Cannot write image '$script:target': *65500*"
            Get-Content -Path $script:target | Should -Be 'existing'
            Get-ChildItem -Path $script:tempDir.FullName -Force -Filter '*.tmp' | Should -BeNullOrEmpty
        }

        It 'Should delete the temporary file when the target cannot be replaced' {
            # A folder at the target path cannot be replaced by a file on any platform.
            $null = New-Item -ItemType Directory -Path $script:target

            $result = Invoke-Conversion -Parameters @{ SourcePath = $script:fixture; TargetPath = $script:target; Format = 'Jpeg'; Force = $true }

            $result.Errors | Should -HaveCount 1
            $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'ImageWriteFailed*'
            Get-ChildItem -Path $script:tempDir.FullName -Force -Filter '*.tmp' | Should -BeNullOrEmpty
        }
    }

    It 'Should replace a read-only target with Force' {
        Set-Content -Path $script:target -Value 'existing'
        Set-ItemProperty -Path $script:target -Name IsReadOnly -Value $true

        $result = Invoke-Conversion -Parameters @{ SourcePath = $script:fixture; TargetPath = $script:target; Format = 'Jpeg'; Force = $true }

        $result.Errors | Should -BeNullOrEmpty
        (Get-ImageInfo -LiteralPath $script:target).Format | Should -Be 'Jpeg'
    }

    It 'Should keep the ICC profile of a PNG when stripping the metadata' {
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'rich.jpg') -Exif -ColorProfile -Xmp
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.png'

        $null = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = 'Png'; StripMetadata = $true }

        $image = [ImageMagick.MagickImage]::new($target)
        try
        {
            @($image.ProfileNames) | Should -Be @('icc')
            $image.GetColorProfile().Description | Should -Be 'Adobe RGB (1998)'
        }
        finally
        {
            $image.Dispose()
        }
    }

    It 'Should write the ICC profile of a PNG only as iCCP chunk, StripMetadata <StripMetadata>' -ForEach @(
        @{ StripMetadata = $false }
        @{ StripMetadata = $true }
    ) {
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'rich.jpg') -Exif -ColorProfile -Xmp -Iptc -Comment 'secret comment'
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.png'

        $result = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = 'Png'; StripMetadata = $StripMetadata }

        $result.Errors | Should -BeNullOrEmpty
        $chunks = Get-PngChunkName -Path $target
        @($chunks | Where-Object -FilterScript { $_ -eq 'iCCP' }) | Should -HaveCount 1
        $chunks | Should -Not -Contain 'zTXt:Raw profile type icc'
        $chunks | Should -Not -Contain 'tEXt:Raw profile type icc'
        $chunks[-1] | Should -Be 'IEND'
        if ($StripMetadata)
        {
            # Only the image structure and the colour profile are left.
            $chunks | Where-Object -FilterScript { $_ -like '*:*' -or $_ -in @('eXIf', 'tIME') } | Should -BeNullOrEmpty
        }
        else
        {
            $chunks | Should -Contain 'eXIf'
        }
    }

    It 'Should write the PNG through the encoder when the source has no ICC profile' {
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.png'

        $result = Invoke-Conversion -Parameters @{ SourcePath = $script:fixture; TargetPath = $target; Format = 'Png' }

        $result.Errors | Should -BeNullOrEmpty
        Get-PngChunkName -Path $target | Should -Not -Contain 'iCCP'
    }

    Context 'When lcms cannot apply the ICC profile of the source' {
        BeforeAll {
            $adobeRgb = [ImageMagick.ColorProfiles]::AdobeRGB1998.ToByteArray()

            # A valid header but a destroyed tag table: ImageMagick reads the profile, lcms cannot use it.
            $tagTable = [System.Byte[]] $adobeRgb.Clone()
            for ($index = 132; $index -lt $tagTable.Length; $index++)
            {
                $tagTable[$index] = 0xAB
            }

            # An unknown data colour space in the header (byte 16).
            $unknownSpace = [System.Byte[]] $adobeRgb.Clone()
            [System.Text.Encoding]::ASCII.GetBytes('XXXX').CopyTo($unknownSpace, 16)

            $script:damagedProfiles = @{
                tagTable      = $tagTable
                unknownSpace  = $unknownSpace
                # Cut short, as when the second of two APP2 segments is lost: the header still names the full length.
                truncated     = [System.Byte[]] $adobeRgb[0..299]
                truncatedGray = [System.Byte[]] (Get-TestGrayColorProfile).ToByteArray()[0..199]
            }
        }

        It 'Should leave the <Case> out of <Format> output and write the colours unchanged' -ForEach @(
            foreach ($format in @('Jpeg', 'Png', 'WebP', 'Avif', 'Jxl', 'Tiff', 'Bmp', 'Gif'))
            {
                @{ Format = $format; Case = 'profile with a destroyed tag table'; ProfileName = 'tagTable'; Gray = $false; Quality = 100 }
                @{ Format = $format; Case = 'profile of an unknown colour space'; ProfileName = 'unknownSpace'; Gray = $false; Quality = 100 }
                @{ Format = $format; Case = 'profile that is cut short'; ProfileName = 'truncated'; Gray = $false; Quality = 100 }
                @{ Format = $format; Case = 'grey profile that is cut short'; ProfileName = 'truncatedGray'; Gray = $true; Quality = 100 }
            }
            @{ Format = 'Jxl'; Case = 'profile that is cut short (lossy)'; ProfileName = 'truncated'; Gray = $false; Quality = 90 }
        ) {
            <#
                Before, Png and lossless Jxl output failed with such a profile ('Incorrect data in iCCP',
                UnableToWriteImageData), and Chrome and Edge did not display the Avif that kept it.
            #>
            $color = '#4080C0'
            if ($Gray)
            {
                $color = '#808080'
            }

            $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'source.jpg') -Color $color
            $null = Add-TestJpegColorProfile -Path $source.FullName -ColorProfile $script:damagedProfiles[$ProfileName]
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath "out.$Format"

            $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = $Format; Quality = $Quality } {
                $verboseRecords = & {
                    [CmdletBinding()]
                    param ()

                    Convert-ImageConverterImage -Cmdlet $PSCmdlet -SourcePath $SourcePath -TargetPath $TargetPath -Format $Format -Quality $Quality
                } -ErrorAction SilentlyContinue -ErrorVariable conversionErrors -WarningAction SilentlyContinue -Verbose 4>&1 | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] }

                [PSCustomObject] @{
                    Verbose = "$verboseRecords"
                    Errors  = @($conversionErrors)
                }
            }

            $result.Errors | Should -BeNullOrEmpty
            $result.Verbose | Should -BeLike "*The ICC colour profile cannot be applied (*), so it is left out of the $Format output: $($source.FullName)*"
            if ($Format -ne 'Jxl')
            {
                (Get-TestStoredColorLayout -Path $target).ProfileSpace | Should -BeNullOrEmpty
            }

            $output = [ImageMagick.MagickImage]::new($target)
            try
            {
                # Viewers ignore such a profile in the source, so they show the stored values.
                $expected = [ImageMagick.MagickColor]::new($color)
                $actual = $output.GetPixels().GetPixel(0, 0).ToColor()
                [System.Math]::Abs([System.Int32] $actual.R - $expected.R) | Should -BeLessOrEqual 6
                [System.Math]::Abs([System.Int32] $actual.B - $expected.B) | Should -BeLessOrEqual 6
            }
            finally
            {
                $output.Dispose()
            }
        }

        It 'Should convert a CMYK source whose profile cannot be applied through the SWOP profile' {
            # The CMYK profile of a print JPEG with a destroyed tag table, cut to fit into one APP2 segment.
            $print = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'print.jpg') -Cmyk
            $image = [ImageMagick.MagickImage]::new($print.FullName)
            try
            {
                $expected = $image.Clone()
                $null = $expected.TransformColorSpace([ImageMagick.ColorProfiles]::SRGB)
                $expectedColor = $expected.GetPixels().GetPixel(0, 0).ToColor()
                $expected.Dispose()

                $image.RemoveProfile('icc')
                $source = Join-Path -Path $script:tempDir.FullName -ChildPath 'damaged-print.jpg'
                $image.Write($source)
            }
            finally
            {
                $image.Dispose()
            }

            $cmykProfile = [System.Byte[]] [ImageMagick.ColorProfiles]::USWebCoatedSWOP.ToByteArray()[0..59999]
            for ($index = 132; $index -lt $cmykProfile.Length; $index++)
            {
                $cmykProfile[$index] = 0xAB
            }

            $null = Add-TestJpegColorProfile -Path $source -ColorProfile $cmykProfile
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.png'

            $result = Invoke-ProfileConversion -SourcePath $source -TargetPath $target -Format 'Png'

            $result.Errors | Should -BeNullOrEmpty
            $result.Verbose | Should -BeLike '*The ICC colour profile cannot be applied (*), so it is left out of the Png output*'
            [System.Math]::Abs($result.Color[0] - $expectedColor.R) | Should -BeLessOrEqual 2
            [System.Math]::Abs($result.Color[2] - $expectedColor.B) | Should -BeLessOrEqual 2
        }

        It 'Should keep a profile that lcms can apply' {
            $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'wide.jpg') -ColorProfile
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.avif'

            $result = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = 'Avif' }

            $result.Errors | Should -BeNullOrEmpty
            (Get-TestStoredColorLayout -Path $target).ProfileSpace | Should -Be 'RGB'
        }
    }

    Context 'When the ICC profile is made for other pixels' {
        BeforeAll {
            # A colour JPEG (#4080C0) with a grey profile, which viewers ignore.
            function New-ColorJpegWithGrayProfile
            {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture: writes a file into the temporary folder of a test.')]
                param ([System.String] $Path)

                $jpeg = New-TestImage -Path $Path -Color '#4080C0'
                Add-TestJpegColorProfile -Path $jpeg.FullName -ColorProfile (Get-TestGrayColorProfile).ToByteArray()
            }
        }

        It 'Should write lossy Jxl with the colours unchanged for a colour JPEG with a grey profile' {
            # Viewers ignore a grey profile in a colour image; converted through it the colours would turn grey.
            $source = New-ColorJpegWithGrayProfile -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'colour.jpg')

            $result = Invoke-ProfileConversion -SourcePath $source.FullName -TargetPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out.jxl')

            $result.Verbose | Should -BeLike "*The ICC colour profile is made for grey pixels and does not match the image, so the colours are written unchanged: $($source.FullName)*"
            $expected = @(64, 128, 192)
            foreach ($channel in 0..2)
            {
                [System.Math]::Abs($result.Color[$channel] - $expected[$channel]) | Should -BeLessOrEqual 4 -Because "channel $channel is $($result.Color[$channel])"
            }
        }

        It 'Should write lossy Jxl with the grey unchanged for a grey JPEG with a colour profile' {
            # ImageMagick writes neutral grey pixels as a one-channel JPEG and keeps the Adobe RGB profile.
            $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'grey.jpg') -Color '#808080' -ColorProfile

            $result = Invoke-ProfileConversion -SourcePath $source.FullName -TargetPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out.jxl')

            $result.Verbose | Should -BeLike "*The ICC colour profile is made for colour pixels and does not match the image, so the colours are written unchanged: $($source.FullName)*"
            [System.Math]::Abs($result.Color[0] - 128) | Should -BeLessOrEqual 2
        }

        It 'Should convert a grey image with a grey profile to sRGB for lossy Jxl' {
            $image = [ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new('#808080'), 16, 16)
            try
            {
                $image.ColorSpace = [ImageMagick.ColorSpace]::Gray
                $image.SetProfile((Get-TestGrayColorProfile))
                $source = Join-Path -Path $script:tempDir.FullName -ChildPath 'grey.png'
                $image.Write($source, [ImageMagick.MagickFormat]::Png)
            }
            finally
            {
                $image.Dispose()
            }

            $result = Invoke-ProfileConversion -SourcePath $source -TargetPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out.jxl')

            $result.Verbose | Should -BeLike '*Converted the colours to sRGB*'
            # Grey 128 with gamma 1.8 shows as about 146 in sRGB.
            [System.Math]::Abs($result.Color[0] - 146) | Should -BeLessOrEqual 3
        }

        It 'Should leave a grey profile on colour pixels out of <Format> output, which browsers do not show correctly with it' -ForEach @(
            @{ Format = 'Avif'; Extension = '.avif' }
            @{ Format = 'Bmp'; Extension = '.bmp' }
        ) {
            $source = New-ColorJpegWithGrayProfile -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'colour.jpg')
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath "out$Extension"

            $result = Invoke-ProfileConversion -SourcePath $source.FullName -TargetPath $target -Format $Format

            $result.Errors | Should -BeNullOrEmpty
            $result.Verbose | Should -BeLike "*The ICC colour profile is made for grey pixels and does not match the image, so it is left out of the $Format output: $($source.FullName)*"
            (Get-TestStoredColorLayout -Path $target).ProfileSpace | Should -BeNullOrEmpty
            $expected = @(64, 128, 192)
            foreach ($channel in 0..2)
            {
                [System.Math]::Abs($result.Color[$channel] - $expected[$channel]) | Should -BeLessOrEqual 4 -Because "channel $channel is $($result.Color[$channel])"
            }
        }

        It 'Should keep a grey profile on colour pixels in <Format> output, whose viewers ignore it' -ForEach @(
            @{ Format = 'Jpeg'; Extension = '.jpg' }
            @{ Format = 'Png'; Extension = '.png' }
            @{ Format = 'WebP'; Extension = '.webp' }
            @{ Format = 'Tiff'; Extension = '.tif' }
            @{ Format = 'Gif'; Extension = '.gif' }
        ) {
            $source = New-ColorJpegWithGrayProfile -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'colour.jpg')
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath "out$Extension"

            $result = Invoke-ProfileConversion -SourcePath $source.FullName -TargetPath $target -Format $Format

            $result.Errors | Should -BeNullOrEmpty
            $result.Verbose | Should -Not -BeLike '*ICC colour profile*'
            (Get-TestStoredColorLayout -Path $target).ProfileSpace | Should -Be 'GRAY'
        }

        It 'Should leave a profile made for <Kind> pixels out of lossless Jxl output, which cannot be written with it' -ForEach @(
            @{ Kind = 'grey' }
            @{ Kind = 'colour' }
        ) {
            $sourcePath = Join-Path -Path $script:tempDir.FullName -ChildPath 'source.jpg'
            if ($Kind -eq 'grey')
            {
                $source = New-ColorJpegWithGrayProfile -Path $sourcePath
                $expected = 64
            }
            else
            {
                # ImageMagick writes neutral grey pixels as a one-channel JPEG and keeps the Adobe RGB profile.
                $source = New-TestImage -Path $sourcePath -Color '#808080' -ColorProfile
                $expected = 128
            }

            $result = Invoke-ProfileConversion -SourcePath $source.FullName -TargetPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out.jxl') -Quality 100

            $result.Errors | Should -BeNullOrEmpty
            $result.Verbose | Should -BeLike "*The ICC colour profile is made for $Kind pixels and does not match the image, so it is left out of the Jxl output: $($source.FullName)*"
            [System.Math]::Abs($result.Color[0] - $expected) | Should -BeLessOrEqual 1
        }

        It 'Should keep an RGB profile on grey pixels in <Format> output, which stores them as RGB' -ForEach @(
            @{ Format = 'WebP'; Extension = '.webp' }
            @{ Format = 'Avif'; Extension = '.avif' }
            @{ Format = 'Bmp'; Extension = '.bmp' }
            @{ Format = 'Gif'; Extension = '.gif' }
        ) {
            $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'grey.jpg') -Color '#808080' -ColorProfile
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath "out$Extension"

            $result = Invoke-ProfileConversion -SourcePath $source.FullName -TargetPath $target -Format $Format

            $result.Errors | Should -BeNullOrEmpty
            $layout = Get-TestStoredColorLayout -Path $target
            $layout.Channels | Should -Be 'RGB'
            $layout.ProfileSpace | Should -Be 'RGB'
        }

        It 'Should leave a grey profile on neutral colour pixels out of <Format> output, which stores them as grey' -ForEach @(
            @{ Format = 'Jpeg'; Extension = '.jpg' }
            @{ Format = 'Png'; Extension = '.png' }
            @{ Format = 'Tiff'; Extension = '.tif' }
        ) {
            <#
                An RGB JPEG whose pixels are all neutral grey, with a grey profile that viewers ignore: these
                encoders store the pixels as grey, which would make the profile valid, and viewers would
                then show grey 128 as 146.
            #>
            $image = [ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new('#808080'), 16, 16)
            try
            {
                $image.Settings.ColorType = [ImageMagick.ColorType]::TrueColor
                $sourcePath = Join-Path -Path $script:tempDir.FullName -ChildPath 'neutral.jpg'
                $image.Write($sourcePath, [ImageMagick.MagickFormat]::Jpeg)
            }
            finally
            {
                $image.Dispose()
            }

            $null = Add-TestJpegColorProfile -Path $sourcePath -ColorProfile (Get-TestGrayColorProfile).ToByteArray()
            (Get-TestStoredColorLayout -Path $sourcePath).Channels | Should -Be 'RGB' -Because 'the fixture stores its grey pixels as RGB'
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath "out$Extension"

            $result = Invoke-ProfileConversion -SourcePath $sourcePath -TargetPath $target -Format $Format

            $result.Errors | Should -BeNullOrEmpty
            $result.Verbose | Should -BeLike "*The ICC colour profile is made for grey pixels and does not match the image, so it is left out of the $Format output: $sourcePath*"
            (Get-TestStoredColorLayout -Path $target).ProfileSpace | Should -BeNullOrEmpty
            [System.Math]::Abs($result.Color[0] - 128) | Should -BeLessOrEqual 1
        }
    }

    Context 'When the source is a grey JPEG XL with a grey profile' {
        BeforeEach {
            <#
                Lossless Jxl output of a grey JPEG with a grey profile, which a colour-managed viewer shows
                as 146. ImageMagick reads such a file as sRGB with three equal channels.
            #>
            $grayJpeg = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'grey.jpg') -GrayColorProfile -Color '#808080'
            $script:grayJxl = Join-Path -Path $script:tempDir.FullName -ChildPath 'grey.jxl'
            $null = Invoke-Conversion -Parameters @{ SourcePath = $grayJpeg.FullName; TargetPath = $script:grayJxl; Format = 'Jxl'; Quality = 100 }
            $image = [ImageMagick.MagickImage]::new($script:grayJxl)
            try
            {
                $image.ColorSpace | Should -Be 'sRGB' -Because 'the fixture is read as sRGB'
                $image.GetColorProfile().ColorSpace | Should -Be 'Gray'
            }
            finally
            {
                $image.Dispose()
            }
        }

        It 'Should convert the grey to sRGB for <Format> output, StripMetadata <StripMetadata>' -ForEach @(
            foreach ($format in @('WebP', 'Avif', 'Bmp', 'Gif'))
            {
                foreach ($strip in @($false, $true))
                {
                    @{ Format = $format; StripMetadata = $strip }
                }
            }
        ) {
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath "out.$Format"

            $result = Invoke-Conversion -Parameters @{ SourcePath = $script:grayJxl; TargetPath = $target; Format = $Format; StripMetadata = $StripMetadata }

            $result.Errors | Should -BeNullOrEmpty
            $layout = Get-TestStoredColorLayout -Path $target
            $layout.Channels | Should -Be 'RGB'
            $layout.ProfileSpace | Should -Not -Be 'GRAY'
            $output = [ImageMagick.MagickImage]::new($target)
            try
            {
                # Grey 128 with gamma 1.8 shows as about 146 in sRGB.
                [System.Math]::Abs([System.Int32] $output.GetPixels().GetPixel(0, 0).ToColor().R - 146) | Should -BeLessOrEqual 3
            }
            finally
            {
                $output.Dispose()
            }
        }

        It 'Should keep the grey pixels and the grey profile in <Format> output, StripMetadata <StripMetadata>' -ForEach @(
            foreach ($format in @('Jpeg', 'Png', 'Tiff'))
            {
                foreach ($strip in @($false, $true))
                {
                    @{ Format = $format; StripMetadata = $strip }
                }
            }
        ) {
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath "out.$Format"

            $result = Invoke-Conversion -Parameters @{ SourcePath = $script:grayJxl; TargetPath = $target; Format = $Format; StripMetadata = $StripMetadata }

            $result.Errors | Should -BeNullOrEmpty
            $layout = Get-TestStoredColorLayout -Path $target
            $layout.Channels | Should -Be 'Grey'
            $layout.ProfileSpace | Should -Be 'GRAY'
        }

        It 'Should keep the grey profile in lossless Jxl output and convert lossy Jxl output to sRGB, Quality <Quality>' -ForEach @(
            @{ Quality = 100; Expected = 128; ProfileSpace = 'Gray' }
            @{ Quality = 90; Expected = 146; ProfileSpace = 'sRGB' }
        ) {
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.jxl'

            $result = Invoke-ProfileConversion -SourcePath $script:grayJxl -TargetPath $target -Quality $Quality

            $result.Errors | Should -BeNullOrEmpty
            $result.Verbose | Should -Not -BeLike '*does not match*'
            [System.Math]::Abs($result.Color[0] - $Expected) | Should -BeLessOrEqual 3
            $output = [ImageMagick.MagickImage]::new($target)
            try
            {
                $output.GetColorProfile().ColorSpace | Should -Be $ProfileSpace
            }
            finally
            {
                $output.Dispose()
            }
        }
    }

    It 'Should store <Format> output of neutral grey pixels with an RGB profile as RGB, alpha <Alpha>, StripMetadata <StripMetadata>' -ForEach @(
        foreach ($strip in @($false, $true))
        {
            @{ Format = 'Jpeg'; Alpha = $false; StripMetadata = $strip }
            @{ Format = 'Tiff'; Alpha = $false; StripMetadata = $strip }
            @{ Format = 'Tiff'; Alpha = $true; StripMetadata = $strip }
        }
    ) {
        # ImageMagick alone would write a greyscale JPEG or TIFF with the RGB profile, which WIC rejects, so Windows shows the grey unmanaged.
        $color = '#808080'
        if ($Alpha)
        {
            $color = '#80808080'
        }
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'grey.png') -Format $(if ($Alpha) { 'Png32' } else { 'Png24' }) -Color $color -ColorProfile
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath "out.$Format"

        $result = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = $Format; StripMetadata = $StripMetadata }

        $result.Errors | Should -BeNullOrEmpty
        $layout = Get-TestStoredColorLayout -Path $target
        $layout.Channels | Should -Be 'RGB'
        $layout.ProfileSpace | Should -Be 'RGB'
        $output = [ImageMagick.MagickImage]::new($target)
        try
        {
            $output.HasAlpha | Should -Be $Alpha
            [System.Math]::Abs([System.Int32] $output.GetPixels().GetPixel(0, 0).ToColor().R - 128) | Should -BeLessOrEqual 1
        }
        finally
        {
            $output.Dispose()
        }
    }

    It 'Should keep CMYK in <Format> output of a CMYK source' -ForEach @(
        @{ Format = 'Jpeg' }
        @{ Format = 'Tiff' }
    ) {
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'print.jpg') -Cmyk
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath "out.$Format"

        $result = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = $Format }

        $result.Errors | Should -BeNullOrEmpty
        $layout = Get-TestStoredColorLayout -Path $target
        $layout.Channels | Should -Be 'CMYK'
        $layout.ProfileSpace | Should -Be 'CMYK'
    }

    It 'Should not write the icc:* text chunks of the CMYK profile into Png output, whose pixels are converted to sRGB' {
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'print.jpg') -Cmyk
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.png'
        $sourceImage = [ImageMagick.MagickImage]::new($source.FullName)
        try
        {
            $sourceImage.GetAttribute('icc:description') | Should -BeLike 'U.S. Web Coated (SWOP)*' -Because 'ImageMagick reads the description of the source profile as a property'
        }
        finally
        {
            $sourceImage.Dispose()
        }

        $result = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = 'Png' }

        $result.Errors | Should -BeNullOrEmpty
        Get-PngChunkName -Path $target | Where-Object -FilterScript { $_ -like '*:icc:*' } | Should -BeNullOrEmpty
    }

    It 'Should write an RGB PNG that keeps the RGB profile of neutral grey pixels, alpha <Alpha>, StripMetadata <StripMetadata>' -ForEach @(
        foreach ($alpha in @($false, $true))
        {
            foreach ($strip in @($false, $true))
            {
                @{ Alpha = $alpha; StripMetadata = $strip; ColorType = $(if ($alpha) { 6 } else { 2 }) }
            }
        }
    ) {
        # ImageMagick alone would write a greyscale PNG with the RGB profile, which readers drop.
        $color = '#808080'
        if ($Alpha)
        {
            $color = '#80808080'
        }
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'grey.png') -Format $(if ($Alpha) { 'Png32' } else { 'Png24' }) -Color $color -ColorProfile -Exif
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.png'

        $result = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = 'Png'; StripMetadata = $StripMetadata }

        $result.Errors | Should -BeNullOrEmpty
        [System.IO.File]::ReadAllBytes($target)[25] | Should -Be $ColorType -Because 'byte 25 is the colour type in the IHDR chunk'
        $readWarnings = [System.Collections.Generic.List[System.String]]::new()
        $output = [ImageMagick.MagickImage]::new()
        try
        {
            $output.add_Warning([System.EventHandler[ImageMagick.WarningEventArgs]] { $readWarnings.Add($args[1].Message) }.GetNewClosure())
            $output.Read($target)

            $output.GetColorProfile().Description | Should -Be 'Adobe RGB (1998)'
            $readWarnings | Should -BeNullOrEmpty
            [System.Math]::Abs([System.Int32] $output.GetPixels().GetPixel(0, 0).ToColor().R - 128) | Should -BeLessOrEqual 1
        }
        finally
        {
            $output.Dispose()
        }
    }

    It 'Should keep the colour type ImageMagick chooses for a coloured PNG with an RGB profile' {
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'colour.png') -Format Png -ColorProfile
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.png'
        $direct = [ImageMagick.MagickImage]::new($source.FullName)
        try
        {
            $expected = $direct.ToByteArray([ImageMagick.MagickFormat]::Png)[25]
        }
        finally
        {
            $direct.Dispose()
        }

        $null = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = 'Png' }

        [System.IO.File]::ReadAllBytes($target)[25] | Should -Be $expected
    }

    It 'Should warn about a damaged source and convert it' {
        $source = New-TestDamagedJpeg -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'cut.jpg')
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.png'

        $result = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = 'Png' }

        $result.Errors | Should -BeNullOrEmpty
        $result.Output.FullName | Should -Be $target
        $result.Warnings | Should -HaveCount 1
        "$($result.Warnings[0])" | Should -Be "The image may be damaged (Premature end of JPEG file; Corrupt JPEG data: premature end of data segment): $($source.FullName)"
    }

    It 'Should dispose the image and write no file when the damage warning stops the call' {
        $outcome = InModuleScope -ModuleName $script:moduleName -Parameters @{ SourcePath = $script:fixture; TargetPath = $script:target } {
            $script:readImage = [ImageMagick.MagickImage]::new($SourcePath)
            Mock -CommandName Read-ImageConverterImage -MockWith {
                [PSCustomObject] @{
                    Result     = $script:readImage
                    Exception  = $null
                    Warnings   = @([ImageMagick.MagickCorruptImageWarningException]::new('Premature end of JPEG file'))
                    FrameCount = 1
                }
            }

            $caught = $null
            try
            {
                & {
                    [CmdletBinding()]
                    param ()

                    Convert-ImageConverterImage -Cmdlet $PSCmdlet -SourcePath $SourcePath -TargetPath $TargetPath -Format 'Jpeg'
                } -WarningAction Stop -ErrorVariable conversionErrors
            }
            catch
            {
                $caught = $_
            }

            [PSCustomObject] @{
                Caught = $caught
                Errors = @($conversionErrors)
                Image  = $script:readImage
            }
        }

        $outcome.Caught.Exception | Should -BeOfType [System.Management.Automation.ActionPreferenceStopException]
        $outcome.Errors | Where-Object -FilterScript { $_.FullyQualifiedErrorId -like 'ImageWriteFailed*' } | Should -BeNullOrEmpty
        { $null = $outcome.Image.ToByteArray([ImageMagick.MagickFormat]::Png) } | Should -Throw -ExpectedMessage '*disposed object*'
        $script:target | Should -Not -Exist
    }

    It 'Should warn that only the first frame of a source with several frames is converted' {
        $source = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'anim.gif') -Format Gif -FrameCount 3
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.png'

        $result = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = 'Png' }

        $result.Errors | Should -BeNullOrEmpty
        $result.Warnings | Should -HaveCount 1
        "$($result.Warnings[0])" | Should -Be "Only the first of 3 frames is converted: $($source.FullName)"
    }

    It 'Should not warn about the frames when the conversion fails' {
        $source = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'anim.gif') -Format Gif -FrameCount 3
        $null = New-Item -ItemType Directory -Path $script:target

        $result = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $script:target; Format = 'Jpeg'; Force = $true }

        $result.Errors | Should -HaveCount 1
        $result.Warnings | Should -BeNullOrEmpty
    }

    It 'Should warn when the EXIF data cannot be written to the format' {
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.jpg') -Exif
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.gif'

        $result = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = 'Gif' }

        $result.Warnings | Should -HaveCount 1
        "$($result.Warnings[0])" | Should -Be "EXIF metadata (date taken, camera, GPS) is not written to Gif output: $($source.FullName)"
    }
}
