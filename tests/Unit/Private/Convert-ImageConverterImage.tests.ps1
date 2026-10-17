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

    It 'Should warn when the EXIF data cannot be written to the format' {
        $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.jpg') -Exif
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'out.gif'

        $result = Invoke-Conversion -Parameters @{ SourcePath = $source.FullName; TargetPath = $target; Format = 'Gif' }

        $result.Warnings | Should -HaveCount 1
        "$($result.Warnings[0])" | Should -Be "EXIF metadata (date taken, camera, GPS) is not written to Gif output: $($source.FullName)"
    }
}
