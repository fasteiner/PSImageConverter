[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'heicAvailable', Justification = 'Set in BeforeDiscovery and read by the -Skip expressions, which PSScriptAnalyzer does not see.')]
param ()

BeforeDiscovery {
    Import-Module -Name 'PSImageConverter'

    $heicAvailable = $null -eq [PSImageConverter.HeicEncoder]::GetUnavailableReason()
}

BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')

    function Invoke-Encoder
    {
        param ([ImageMagick.MagickImage] $Image, [System.Int32] $Quality = 77)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ Image = $Image; Quality = $Quality } {
            Invoke-ImageConverterHeicEncoder -Image $Image -Quality $Quality
        }
    }

    # Pester 6 does not fall back to the real command when a filter does not match, so every other call runs the real helper.
    function Use-RealMethodInvoker
    {
        Mock -ModuleName $script:moduleName -CommandName Invoke-ImageConverterMethod -MockWith {
            $target = $null
            $methodType = $Type
            if ($null -ne $InputObject)
            {
                $target = $InputObject
                $methodType = $InputObject.GetType()
            }

            $result = $null
            $values = $null
            $exception = [PSImageConverter.SafeInvoker]::Invoke($methodType, $target, $Name, $ArgumentList, [ref] $result, [ref] $values)
            [PSCustomObject] @{ Result = $result; Exception = $exception; Arguments = $values }
        }
    }

    function New-Image
    {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture: creates an image in memory and changes no state.')]
        param ([System.String] $Color = '#C03C3B', [System.Int32] $Width = 4, [System.Int32] $Height = 2)

        [ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new($Color), [System.UInt32] $Width, [System.UInt32] $Height)
    }

    <#
        An EXIF block (TIFF structure) whose IFD0 holds Make and the orientation 6 as SHORT or LONG, in
        either byte order, with or without "Exif\0\0" in front. ValueOffset is where the orientation
        value starts in the block.
    #>
    function Get-TestExifBlock
    {
        param ([System.String] $ByteOrder = 'II', [System.Int32] $Type = 3, [System.Management.Automation.SwitchParameter] $Header)

        $bigEndian = $ByteOrder -eq 'MM'
        $bytes = [System.Collections.Generic.List[System.Byte]]::new()
        $add = {
            param ([System.Int64] $Value, [System.Int32] $Size)

            $field = foreach ($index in 0..($Size - 1))
            {
                [System.Byte] (($Value -shr (8 * $index)) -band 0xFF)
            }

            if ($bigEndian)
            {
                [System.Array]::Reverse($field)
            }

            $bytes.AddRange([System.Byte[]] $field)
        }

        if ($Header)
        {
            $bytes.AddRange([System.Text.Encoding]::ASCII.GetBytes("Exif`0`0"))
        }

        $start = $bytes.Count
        $bytes.AddRange([System.Text.Encoding]::ASCII.GetBytes($ByteOrder))
        & $add 42 2
        & $add 8 4
        & $add 2 2
        & $add 0x010F 2
        & $add 2 2
        & $add 5 4
        & $add 38 4
        & $add 0x0112 2
        & $add $Type 2
        & $add 1 4
        $valueOffset = $bytes.Count
        & $add 6 $(if ($Type -eq 4) { 4 } else { 2 })
        if ($Type -ne 4)
        {
            & $add 0 2
        }

        & $add 0 4
        $bytes.AddRange([System.Text.Encoding]::ASCII.GetBytes("Cam1`0"))

        [PSCustomObject] @{ Bytes = $bytes.ToArray(); ValueOffset = $valueOffset; Start = $start }
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Invoke-ImageConverterHeicEncoder' {
    Context 'When looking at what is passed to the encoder' {
        BeforeEach {
            $script:encodeArguments = $null
            Use-RealMethodInvoker
            Mock -ModuleName $script:moduleName -CommandName Invoke-ImageConverterMethod -ParameterFilter { $Name -eq 'Encode' } -MockWith {
                $script:encodeArguments = $ArgumentList
                [PSCustomObject] @{ Result = [System.Byte[]] @(1, 2, 3); Exception = $null; Arguments = $ArgumentList }
            }
        }

        It 'Should pass the size, the RGB pixels, the quality, the RGB profile, the EXIF block with orientation 1 and the XMP packet' {
            $image = New-Image
            try
            {
                $image.SetProfile([ImageMagick.ColorProfiles]::AdobeRGB1998)
                $exifProfile = [ImageMagick.ExifProfile]::new()
                $exifProfile.SetValue([ImageMagick.ExifTag]::Orientation, [System.UInt16] 6)
                $exifProfile.SetValue([ImageMagick.ExifTag]::Make, 'TestCam Inc.')
                $image.SetProfile($exifProfile)
                $exifBytes = $image.GetExifProfile().ToByteArray()
                $xmpBytes = [System.Text.Encoding]::UTF8.GetBytes('<x:xmpmeta xmlns:x="adobe:ns:meta/"/>')
                $image.SetProfile([ImageMagick.XmpProfile]::new($xmpBytes))

                $result = Invoke-Encoder -Image $image
            }
            finally
            {
                $image.Dispose()
            }

            $result.Exception | Should -BeNullOrEmpty
            $result.Result | Should -Be @(1, 2, 3)
            $script:encodeArguments[0] | Should -Be 4
            $script:encodeArguments[1] | Should -Be 2
            $script:encodeArguments[2] | Should -HaveCount 24
            $script:encodeArguments[2][0..5] | Should -Be @(0xC0, 0x3C, 0x3B, 0xC0, 0x3C, 0x3B)
            $script:encodeArguments[3] | Should -Be 3
            $script:encodeArguments[4] | Should -Be 77
            $script:encodeArguments[5] | Should -Be ([ImageMagick.ColorProfiles]::AdobeRGB1998.ToByteArray())
            $script:encodeArguments[6] | Should -HaveCount $exifBytes.Length
            $passedExif = [ImageMagick.ExifProfile]::new([System.Byte[]] $script:encodeArguments[6])
            $passedExif.GetValue([ImageMagick.ExifTag]::Orientation).Value | Should -Be 1
            $passedExif.GetValue([ImageMagick.ExifTag]::Make).Value | Should -Be 'TestCam Inc.'
            $script:encodeArguments[7] | Should -Be $xmpBytes
        }

        It 'Should pass a big-endian EXIF block on as it is, with orientation 1' {
            $block = Get-TestExifBlock -ByteOrder 'MM' -Header
            $image = New-Image
            try
            {
                $image.SetProfile([ImageMagick.ExifProfile]::new($block.Bytes))

                $null = Invoke-Encoder -Image $image
            }
            finally
            {
                $image.Dispose()
            }

            $expected = [System.Byte[]] $block.Bytes.Clone()
            $expected[$block.ValueOffset + 1] = 1
            $script:encodeArguments[6] | Should -Be $expected
        }

        It 'Should pass RGBA pixels for an image with transparent pixels' {
            $image = New-Image -Color '#FF000080'
            try
            {
                $null = Invoke-Encoder -Image $image
            }
            finally
            {
                $image.Dispose()
            }

            $script:encodeArguments[2] | Should -HaveCount 32
            $script:encodeArguments[2][0..3] | Should -Be @(255, 0, 0, 128)
            $script:encodeArguments[3] | Should -Be 4
        }

        It 'Should pass RGB pixels for an image whose alpha channel is opaque' {
            $image = New-Image
            try
            {
                $image.Alpha([ImageMagick.AlphaOption]::Set)
                $image.HasAlpha | Should -BeTrue

                $null = Invoke-Encoder -Image $image
            }
            finally
            {
                $image.Dispose()
            }

            $script:encodeArguments[2] | Should -HaveCount 24
            $script:encodeArguments[3] | Should -Be 3
        }

        It 'Should pass no profile, EXIF block or XMP packet for an image without them' {
            $image = New-Image
            try
            {
                $null = Invoke-Encoder -Image $image
            }
            finally
            {
                $image.Dispose()
            }

            $script:encodeArguments[5] | Should -BeNullOrEmpty
            $script:encodeArguments[6] | Should -BeNullOrEmpty
            $script:encodeArguments[7] | Should -BeNullOrEmpty
        }

        It 'Should pass grey pixels as three equal channels and leave a profile that is not RGB out' {
            $image = New-Image -Color '#808080'
            try
            {
                $image.ColorSpace = [ImageMagick.ColorSpace]::Gray
                $image.SetProfile((Get-TestGrayColorProfile))

                $null = Invoke-Encoder -Image $image
            }
            finally
            {
                $image.Dispose()
            }

            $script:encodeArguments[2] | Select-Object -Unique | Should -Be 128
            $script:encodeArguments[3] | Should -Be 3
            $script:encodeArguments[5] | Should -BeNullOrEmpty
        }

        It 'Should convert the pixels of a Lab image to sRGB' {
            $image = New-Image
            try
            {
                $image.ColorSpace = [ImageMagick.ColorSpace]::Lab

                $null = Invoke-Encoder -Image $image
            }
            finally
            {
                $image.Dispose()
            }

            foreach ($pair in @(@(0, 0xC0), @(1, 0x3C), @(2, 0x3B)))
            {
                [System.Math]::Abs([System.Int32] $script:encodeArguments[2][$pair[0]] - $pair[1]) | Should -BeLessOrEqual 1
            }
        }
    }

    Context 'When the EXIF orientation is set to 1 (PSImageConverter.ExifOrientation)' {
        It 'Should change only the orientation value of a <ByteOrder> block with a <TypeName> value, Exif header <Header>' -ForEach @(
            @{ ByteOrder = 'II'; Type = 3; TypeName = 'SHORT'; Header = $true }
            @{ ByteOrder = 'MM'; Type = 3; TypeName = 'SHORT'; Header = $true }
            @{ ByteOrder = 'II'; Type = 4; TypeName = 'LONG'; Header = $false }
            @{ ByteOrder = 'MM'; Type = 4; TypeName = 'LONG'; Header = $false }
        ) {
            $block = Get-TestExifBlock -ByteOrder $ByteOrder -Type $Type -Header:$Header
            $valueSize = 2
            if ($Type -eq 4)
            {
                $valueSize = 4
            }

            $result = [PSImageConverter.ExifOrientation]::SetTopLeft($block.Bytes)

            $expected = [System.Byte[]] $block.Bytes.Clone()
            [System.Array]::Clear($expected, $block.ValueOffset, $valueSize)
            if ($ByteOrder -eq 'MM')
            {
                $expected[$block.ValueOffset + $valueSize - 1] = 1
            }
            else
            {
                $expected[$block.ValueOffset] = 1
            }

            $result | Should -Be $expected
            $block.Bytes[$block.ValueOffset..($block.ValueOffset + $valueSize - 1)] | Should -Contain 6
        }

        It 'Should return <Case> unchanged' -ForEach @(
            @{ Case = 'a block shorter than a TIFF header'; Change = { param ($Bytes) [System.Byte[]] $Bytes[0..10] } }
            @{ Case = 'a block without a byte order mark'; Change = { param ($Bytes) $Bytes[6] = [System.Byte] [System.Char] 'X'; $Bytes } }
            @{ Case = 'a block whose IFD0 lies beyond its end'; Change = { param ($Bytes) $Bytes[10] = 0x7F; $Bytes } }
            @{ Case = 'a block cut off inside IFD0'; Change = { param ($Bytes) [System.Byte[]] $Bytes[0..30] } }
            @{ Case = 'a block whose orientation has another type'; Change = { param ($Bytes) $Bytes[30] = 9; $Bytes } }
            @{ Case = 'a block without an orientation tag'; Change = { param ($Bytes) $Bytes[28] = 0x13; $Bytes } }
        ) {
            $bytes = & $Change ([System.Byte[]] (Get-TestExifBlock -ByteOrder 'II' -Header).Bytes)
            $original = [System.Byte[]] $bytes.Clone()

            $result = [PSImageConverter.ExifOrientation]::SetTopLeft($bytes)

            $result | Should -Be $original
            [System.Object]::ReferenceEquals($result, $bytes) | Should -BeFalse
        }

        It 'Should return null for null' {
            [PSImageConverter.ExifOrientation]::SetTopLeft($null) | Should -BeNullOrEmpty
        }
    }

    Context 'When the pixels cannot be exported' {
        It 'Should return the exception without calling the encoder' {
            Use-RealMethodInvoker
            Mock -ModuleName $script:moduleName -CommandName Invoke-ImageConverterMethod -ParameterFilter { $Name -eq 'ToByteArray' } -MockWith {
                [PSCustomObject] @{ Result = $null; Exception = [System.OutOfMemoryException]::new('No memory for the pixels.'); Arguments = $ArgumentList }
            }

            $image = New-Image
            try
            {
                $result = Invoke-Encoder -Image $image
            }
            finally
            {
                $image.Dispose()
            }

            $result.Result | Should -BeNullOrEmpty
            $result.Exception.Message | Should -Be 'No memory for the pixels.'
            Should -Invoke -ModuleName $script:moduleName -CommandName Invoke-ImageConverterMethod -ParameterFilter { $Name -eq 'Encode' } -Times 0 -Exactly
        }
    }

    Context 'When the encoder of the operating system works' -Skip:(-not $heicAvailable) {
        It 'Should return the bytes of a HEIC file' {
            $image = New-Image -Width 17 -Height 9
            try
            {
                $result = Invoke-Encoder -Image $image -Quality 90
            }
            finally
            {
                $image.Dispose()
            }

            $result.Exception | Should -BeNullOrEmpty
            $readBack = [ImageMagick.MagickImage]::new([System.Byte[]] $result.Result)
            try
            {
                $readBack.Format | Should -Be 'Heic'
                $readBack.Width | Should -Be 17
                $readBack.Height | Should -Be 9
            }
            finally
            {
                $readBack.Dispose()
            }
        }

        It 'Should return the exception of the encoder for an image it rejects' -Skip:$IsMacOS {
            $image = New-Image -Width 32768 -Height 16
            try
            {
                $result = Invoke-Encoder -Image $image -Quality 90
            }
            finally
            {
                $image.Dispose()
            }

            $result.Result | Should -BeNullOrEmpty
            $result.Exception | Should -BeOfType [PSImageConverter.HeicEncoderException]
            $result.Exception.EncoderMissing | Should -BeFalse
        }
    }
}
