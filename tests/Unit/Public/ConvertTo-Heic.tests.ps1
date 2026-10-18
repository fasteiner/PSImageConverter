[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'heicAvailable', Justification = 'Set in BeforeDiscovery and read by the -Skip expressions, which PSScriptAnalyzer does not see.')]
param ()

BeforeDiscovery {
    Import-Module -Name 'PSImageConverter'

    # The tests that write HEIC run only where the encoder of the operating system works; the probe runs once per process.
    $heicAvailable = $null -eq [PSImageConverter.HeicEncoder]::GetUnavailableReason()
}

BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:fixture = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath
    $script:manifestPath = Join-Path -Path (Get-Module -Name $script:moduleName).ModuleBase -ChildPath "$($script:moduleName).psd1"
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/Get-TestHeifInfo.ps1')

    # What the encoders keep: the WIC encoder of Windows stores no alpha, ImageIO of macOS writes no EXIF and XMP.
    $script:keepsAlpha = -not $IsWindows
    $script:keepsMetadata = -not $IsMacOS

    # The sample photo as PNG, so a .heic target never collides with the source.
    $script:fixtureFolder = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
    $script:pngFixture = Join-Path -Path $script:fixtureFolder.FullName -ChildPath 'sample.png'
    $sample = [ImageMagick.MagickImage]::new($script:fixture)
    try
    {
        $sample.Write($script:pngFixture, [ImageMagick.MagickFormat]::Png)
    }
    finally
    {
        $sample.Dispose()
    }

    # What Magick.NET reads back from a written file.
    function Get-ReadBack
    {
        param ([System.String] $Path)

        $image = [ImageMagick.MagickImage]::new($Path)
        try
        {
            $exif = $image.GetExifProfile()
            $colorProfile = $image.GetColorProfile()
            $exifOrientation = $null
            $make = $null
            $thumbnailLength = $null
            if ($null -ne $exif)
            {
                $exifOrientation = $exif.GetValue([ImageMagick.ExifTag]::Orientation).Value
                $make = $exif.GetValue([ImageMagick.ExifTag]::Make).Value
                $thumbnailLength = $exif.ThumbnailLength
            }

            [PSCustomObject] @{
                Format          = $image.Format
                Width           = [System.Int32] $image.Width
                Height          = [System.Int32] $image.Height
                HasAlpha        = $image.HasAlpha
                HasExif         = $null -ne $exif
                ExifOrientation = $exifOrientation
                Make            = $make
                ThumbnailLength = $thumbnailLength
                HasXmp          = $null -ne $image.GetXmpProfile()
                ProfileName     = $(if ($null -ne $colorProfile) { $colorProfile.Description })
                ProfileSpace    = $(if ($null -ne $colorProfile) { $colorProfile.ColorSpace })
            }
        }
        finally
        {
            $image.Dispose()
        }
    }

    # The colours a colour-managed viewer shows at the given pixels (R, G, B, A each): converted from the embedded profile to sRGB.
    function Get-ViewerColor
    {
        param ([System.String] $Path, [System.Int32] $X = 0, [System.Int32] $Y = 0, [System.Int32[][]] $Point = @(, @($X, $Y)))

        $image = [ImageMagick.MagickImage]::new($Path)
        try
        {
            $image.AutoOrient()
            if ($null -ne $image.GetColorProfile())
            {
                $null = $image.TransformColorSpace([ImageMagick.ColorProfiles]::SRGB)
            }

            $pixels = $image.GetPixels()
            # @() keeps one point as a list of one colour, so [0] is that colour and not its red value.
            $colors = @(
                foreach ($location in $Point)
                {
                    $color = $pixels.GetPixel($location[0], $location[1]).ToColor()
                    , @([System.Int32] $color.R, [System.Int32] $color.G, [System.Int32] $color.B, [System.Int32] $color.A)
                }
            )

            if ($Point.Count -eq 1)
            {
                return $colors[0]
            }

            $colors
        }
        finally
        {
            $image.Dispose()
        }
    }

    # What the HEIF decoder of Windows (WIC, used by Photos and Explorer) shows: size, R, G, B at the given pixels, ICC profiles, EXIF Make.
    function Get-WicDecode
    {
        param ([System.String] $Path, [System.Int32[][]] $Point = @(, @(0, 0)))

        Add-Type -AssemblyName 'PresentationCore', 'WindowsBase'
        $stream = [System.IO.File]::OpenRead($Path)
        try
        {
            $decoder = [System.Windows.Media.Imaging.BitmapDecoder]::Create($stream, [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
            $frame = $decoder.Frames[0]
            $converted = [System.Windows.Media.Imaging.FormatConvertedBitmap]::new($frame, [System.Windows.Media.PixelFormats]::Bgra32, $null, 0)
            $pixels = [System.Byte[]]::new($converted.PixelWidth * $converted.PixelHeight * 4)
            $converted.CopyPixels($pixels, $converted.PixelWidth * 4, 0)
            $make = $null
            try
            {
                $make = $frame.Metadata.GetQuery('/ifd/{ushort=271}')
            }
            catch [System.Exception]
            {
                $make = $null
            }

            [PSCustomObject] @{
                Width         = $frame.PixelWidth
                Height        = $frame.PixelHeight
                Colors        = @(
                    foreach ($location in $Point)
                    {
                        $index = (($location[1] * $converted.PixelWidth) + $location[0]) * 4
                        , @([System.Int32] $pixels[$index + 2], [System.Int32] $pixels[$index + 1], [System.Int32] $pixels[$index])
                    }
                )
                ColorContexts = @($frame.ColorContexts).Count
                Make          = $make
            }
        }
        finally
        {
            $stream.Dispose()
        }
    }

    # The mean difference of the R, G and B values a viewer shows for two images of one size.
    function Get-MeanDifference
    {
        param ([System.String] $ExpectedPath, [System.String] $ActualPath)

        $images = foreach ($path in $ExpectedPath, $ActualPath)
        {
            $image = [ImageMagick.MagickImage]::new($path)
            $image.AutoOrient()
            if ($null -ne $image.GetColorProfile())
            {
                $null = $image.TransformColorSpace([ImageMagick.ColorProfiles]::SRGB)
            }

            $image
        }

        try
        {
            # Magick.NET returns the mean absolute error on a scale of 0 to 1.
            $images[0].Compare($images[1], [ImageMagick.ErrorMetric]::MeanAbsolute) * 255
        }
        finally
        {
            $images.Dispose()
        }
    }
}

AfterAll {
    Remove-Item -LiteralPath $script:fixtureFolder.FullName -Recurse -Force -ErrorAction SilentlyContinue
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'ConvertTo-Heic' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
        $script:source = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.png'
        Copy-Item -LiteralPath $script:pngFixture -Destination $script:source
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'When looking at the parameters' {
        It 'Should have the parameters of Convert-Image without -Format' {
            $expected = (Get-Command -Name 'Convert-Image').Parameters.Keys | Where-Object -FilterScript { $_ -ne 'Format' } | Sort-Object

            (Get-Command -Name 'ConvertTo-Heic').Parameters.Keys | Sort-Object | Should -Be $expected
        }

        It 'Should accept the aliases PSPath and LP for -LiteralPath' {
            (Get-Command -Name 'ConvertTo-Heic').Parameters['LiteralPath'].Aliases | Should -Be @('PSPath', 'LP')
        }
    }

    Context 'When recording the HEIC support of this machine' {
        It 'Should write the formats Magick.NET reads and writes and the state of the HEIC encoder into the test results' {
            # CI keeps output/testResults, so every runner's answer can be looked up after the run.
            $resultsFolder = Join-Path -Path $PSScriptRoot -ChildPath '../../../output/testResults'
            $null = New-Item -ItemType Directory -Path $resultsFolder -Force
            $status = InModuleScope -ModuleName $script:moduleName { Get-ImageConverterHeicEncoderStatus }
            $formats = [ImageMagick.MagickNET]::SupportedFormats | Where-Object -FilterScript { $_.Format -in @('Heic', 'Heif', 'Avif', 'Jxl', 'WebP') }
            $report = @(
                "OS: $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription) ($([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture))"
                "PowerShell: $($PSVersionTable.PSVersion); .NET: $([System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription)"
                "Magick.NET: $([ImageMagick.MagickNET]::Version)"
                ''
                'Format SupportsReading SupportsWriting'
                foreach ($format in $formats)
                {
                    '{0,-6} {1,-15} {2}' -f $format.Format, $format.SupportsReading, $format.SupportsWriting
                }
                ''
                "HEIC encoder of the operating system ($($status.Platform)): IsAvailable $($status.IsAvailable)"
                "Reason: $($status.Reason)"
            )
            $reportPath = Join-Path -Path $resultsFolder -ChildPath "HeicSupport_$($status.Platform).txt"
            Set-Content -LiteralPath $reportPath -Value $report

            $reportPath | Should -Exist
            ($formats | Where-Object -FilterScript { $_.Format -eq 'Heic' }).SupportsReading | Should -BeTrue
            ($formats | Where-Object -FilterScript { $_.Format -eq 'Heic' }).SupportsWriting | Should -BeFalse
            ($formats | Where-Object -FilterScript { $_.Format -in @('Avif', 'Jxl', 'WebP') }).SupportsWriting | Should -Be @($true, $true, $true)
        }
    }

    Context 'When the HEIC encoder of the operating system is missing' {
        BeforeEach {
            Mock -ModuleName $script:moduleName -CommandName Get-ImageConverterHeicEncoderStatus -MockWith {
                [PSCustomObject] @{ IsAvailable = $false; Reason = 'libheif.so.1 was not found.'; Platform = 'Linux' }
            }
            Mock -ModuleName $script:moduleName -CommandName Read-ImageConverterImage

            $null = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.jpg')
        }

        It 'Should stop the call for 2 sources with one terminating HeicEncoderNotAvailable error of ConvertTo-Heic before any file is read, WhatIf <WhatIf>' -ForEach @(
            @{ WhatIf = $false }
            @{ WhatIf = $true }
        ) {
            $errorCount = $global:Error.Count
            $result = $null
            $caught = $null

            try
            {
                $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertTo-Heic -WhatIf:$WhatIf -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            catch
            {
                $caught = $_
            }

            $caught.FullyQualifiedErrorId | Should -Be 'HeicEncoderNotAvailable,ConvertTo-Heic'
            $caught.CategoryInfo.Category | Should -Be 'NotInstalled'
            $caught.TargetObject | Should -Be 'Heic'
            "$caught" | Should -BeLike 'HEIC cannot be written on this computer: *libheif.so.1 was not found.*sudo apt install libheif1 libheif-plugin-x265*-Format Avif*'
            $global:Error.Count - $errorCount | Should -Be 1
            $conversionError | Should -HaveCount 1
            $result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName -CommandName Read-ImageConverterImage -Times 0 -Exactly
            Get-ChildItem -Path $script:tempDir.FullName -Filter '*.heic' | Should -BeNullOrEmpty
        }

        It 'Should report a -DestinationPath that cannot name a folder first' {
            $file = Join-Path -Path $script:tempDir.FullName -ChildPath 'file.txt'
            Set-Content -Path $file -Value 'x'

            { ConvertTo-Heic -LiteralPath $script:source -DestinationPath $file } | Should -Throw -ErrorId 'DestinationNotDirectory,ConvertTo-Heic'
        }

        It 'Should not check the encoder for another output format' {
            $result = ConvertTo-Avif -LiteralPath $script:source -WhatIf

            $result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName -CommandName Get-ImageConverterHeicEncoderStatus -Times 0 -Exactly
        }
    }

    Context 'When this machine has no working HEIC encoder' -Skip:$heicAvailable {
        It 'Should have found no encoder, not a fault in the binding to it' {
            # A wrong signature or a missing native function would also make the probe fail; then this fails instead of every HEIC test being skipped.
            $failure = [PSImageConverter.HeicEncoder]::GetProbeFailure()

            $failure.EncoderMissing | Should -BeTrue -Because "$($failure.Message) $($failure.InnerException)"
        }

        It 'Should name the reason of the probe and what to install in the terminating error' {
            $reason = [PSImageConverter.HeicEncoder]::GetUnavailableReason()

            { ConvertTo-Heic -LiteralPath $script:source } | Should -Throw -ErrorId 'HeicEncoderNotAvailable,ConvertTo-Heic' -ExpectedMessage "HEIC cannot be written on this computer: the module uses the HEVC encoder of the operating system and ships none of its own. $reason *-Format Avif*"
            Get-ChildItem -Path $script:tempDir.FullName -Filter '*.heic' | Should -BeNullOrEmpty
        }
    }

    Context 'When converting a file' -Skip:(-not $heicAvailable) {
        It 'Should write a HEIC file with the extension .heic next to the source and return it' {
            $result = ConvertTo-Heic -Path $script:source

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.Name | Should -Be 'IMG_0001.heic'
            $result.DirectoryName | Should -Be $script:tempDir.FullName
            $info = Get-ImageInfo -LiteralPath $result.FullName
            $info.Format | Should -Be 'Heic'
            $info.Width | Should -Be 64
            $info.Height | Should -Be 64
            $info.Orientation | Should -Be 'TopLeft'
            Get-MeanDifference -ExpectedPath $script:source -ActualPath $result.FullName | Should -BeLessThan 3
        }

        It 'Should take the first positional argument as -Path with wildcards' {
            Copy-Item -LiteralPath $script:pngFixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.png')

            $result = ConvertTo-Heic (Join-Path -Path $script:tempDir.FullName -ChildPath '*.png')

            $result.Name | Sort-Object | Should -Be @('IMG_0001.heic', 'IMG_0002.heic')
        }

        It 'Should convert every file piped from Get-ChildItem and skip folders' {
            $null = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.jpg')
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'folder')

            $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertTo-Heic -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Sort-Object | Should -Be @('IMG_0001.heic', 'photo.heic')
        }

        It 'Should bind files piped from Get-ChildItem to -LiteralPath and accept strings' {
            $bracketSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG[1].png'
            Copy-Item -LiteralPath $script:pngFixture -Destination $bracketSource

            $fromFile = Get-ChildItem -LiteralPath $bracketSource | ConvertTo-Heic
            $fromString = $script:source | ConvertTo-Heic

            $fromFile.Name | Should -Be 'IMG[1].heic'
            $fromString.Name | Should -Be 'IMG_0001.heic'
        }

        It 'Should write a TargetIsSource error for a .heic source and re-encode it into -DestinationPath' {
            $heicSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.heic'
            Copy-Item -LiteralPath $script:fixture -Destination $heicSource
            $hash = (Get-FileHash -LiteralPath $heicSource).Hash
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'copy'

            $same = ConvertTo-Heic -LiteralPath $heicSource -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError
            $copy = ConvertTo-Heic -LiteralPath $heicSource -Quality 50 -DestinationPath $destination

            $same | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetIsSource,Convert-Image'
            (Get-FileHash -LiteralPath $heicSource).Hash | Should -Be $hash
            $copy.FullName | Should -Be (Join-Path -Path (Get-Item -LiteralPath $destination).FullName -ChildPath 'photo.heic')
            (Get-ImageInfo -LiteralPath $copy.FullName).Format | Should -Be 'Heic'
        }

        It 'Should write a DuplicateTarget error for the second source of one call, also with -Force' {
            $null = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg')

            $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertTo-Heic -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -HaveCount 1
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'DuplicateTarget,Convert-Image'
        }

        It 'Should hold exactly one error record per failed file, set $? to $false and continue' {
            $missing = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.png'
            $broken = Join-Path -Path $script:tempDir.FullName -ChildPath 'broken.jpg'
            Set-Content -Path $broken -Value 'not an image'

            $result = ConvertTo-Heic -Path $missing, $broken, $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError
            $succeeded = $?

            $succeeded | Should -BeFalse
            $result.Name | Should -Be 'IMG_0001.heic'
            $conversionError.FullyQualifiedErrorId | Should -Be @('PathNotFound,Convert-Image', 'ImageReadFailed,Convert-Image')
        }

        It 'Should neither write the file nor create the destination folder with -WhatIf' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'whatif'

            $result = ConvertTo-Heic -Path $script:source -DestinationPath $destination -WhatIf

            $result | Should -BeNullOrEmpty
            $destination | Should -Not -Exist
            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heic' | Should -Not -Exist
        }

        It 'Should write a smaller file for a lower quality' {
            $detailed = Join-Path -Path $script:tempDir.FullName -ChildPath 'logo.png'
            $logo = [ImageMagick.MagickImage]::new('logo:')
            try
            {
                $logo.Write($detailed, [ImageMagick.MagickFormat]::Png)
            }
            finally
            {
                $logo.Dispose()
            }

            $high = ConvertTo-Heic -Path $detailed -Quality 100 -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'high')
            $low = ConvertTo-Heic -Path $detailed -Quality 10 -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'low')

            $low.Length | Should -BeLessThan ($high.Length / 2)
            Get-MeanDifference -ExpectedPath $detailed -ActualPath $high.FullName | Should -BeLessThan (Get-MeanDifference -ExpectedPath $detailed -ActualPath $low.FullName)
        }

        It 'Should keep an existing target without -Force and replace it, also read-only, with -Force' {
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heic'
            Set-Content -Path $target -Value 'existing'
            Set-ItemProperty -LiteralPath $target -Name IsReadOnly -Value $true

            $null = ConvertTo-Heic -Path $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetExists,Convert-Image'
            Get-Content -Path $target | Should -Be 'existing'

            $result = ConvertTo-Heic -Path $script:source -Force
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Heic'
        }

        It 'Should write a name that ImageMagick would read as a frame or file pattern unchanged' {
            # The encoder never sees the target name: it encodes into memory, and the bytes go into a temporary file.
            $patternSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_%d [x].png'
            Copy-Item -LiteralPath $script:pngFixture -Destination $patternSource

            $result = ConvertTo-Heic -LiteralPath $patternSource

            $result.Name | Should -Be 'IMG_%d [x].heic'
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Heic'
            Get-ChildItem -Path $script:tempDir.FullName -Force -Filter '*.tmp' | Should -BeNullOrEmpty
        }

        It 'Should write HEIC files from several runspaces at once, starting with the first conversion of the process' {
            # A fresh process, so the probe of the encoder and the first conversion run in four runspaces at the same time.
            $sources = foreach ($size in @(@(64, 48), @(17, 9), @(1025, 100)))
            {
                (New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath "parallel-$($size[0]).png") -Format Png -Width $size[0] -Height $size[1]).FullName
            }

            # Standard error goes into a file: x265 in a container writes lines of its own there.
            $errorFile = Join-Path -Path $script:tempDir.FullName -ChildPath 'stderr.txt'
            $output = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command {
                param ($ManifestPath, $Sources, $Folder)

                1..4 | ForEach-Object -ThrottleLimit 4 -Parallel {
                    Import-Module -Name $using:ManifestPath
                    ConvertTo-Heic -LiteralPath $using:Sources -DestinationPath (Join-Path -Path $using:Folder -ChildPath "runspace$_") -ErrorAction Stop | ForEach-Object -Process { $_.FullName }
                }
            } -args $script:manifestPath, $sources, $script:tempDir.FullName 2> $errorFile

            $output | Should -HaveCount 12 -Because (Get-Content -LiteralPath $errorFile -Raw)
            foreach ($path in $output)
            {
                $readBack = Get-ReadBack -Path $path
                $readBack.Format | Should -Be 'Heic'
                "$($readBack.Width)x$($readBack.Height)" | Should -BeIn @('64x48', '17x9', '1025x100')
            }

            Get-ChildItem -Path $script:tempDir.FullName -Recurse -Force -Filter '*.tmp' | Should -BeNullOrEmpty
        }

        It 'Should still call the module''s Convert-Image when the session has an alias named Convert-Image' {
            function global:Invoke-PsicHijack
            {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Arguments', Justification = 'Takes every argument the wrapper passes to Convert-Image, so the call binds; the values do not matter.')]
                param ([Parameter(ValueFromRemainingArguments = $true)] $Arguments)

                'hijacked'
            }
            Set-Alias -Name 'Convert-Image' -Value 'Invoke-PsicHijack' -Scope Global
            try
            {
                $result = ConvertTo-Heic -LiteralPath $script:source
            }
            finally
            {
                Remove-Item -LiteralPath 'Alias:\Convert-Image', 'Function:\Invoke-PsicHijack' -Force
            }

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.Name | Should -Be 'IMG_0001.heic'
        }

        It 'Should write PathNotFound of Convert-Image for a PSDrive the caller created in its own scope' {
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName

            $result = ConvertTo-Heic -Path 'PsicScopeDrive:\IMG_0001.png' -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Convert-Image'
            "$($conversionError[0])" | Should -BeLike "Cannot resolve the path 'PsicScopeDrive:\IMG_0001.png': drive 'PsicScopeDrive' was created in a scope that the PSImageConverter module cannot see*"
        }

        It 'Should stop the call with one terminating InvalidDestinationPath error of ConvertTo-Heic for such a drive in -DestinationPath' {
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName

            { ConvertTo-Heic -LiteralPath $script:source -DestinationPath 'PsicScopeDrive:\out' } | Should -Throw -ErrorId 'InvalidDestinationPath,ConvertTo-Heic'
        }
    }

    Context 'When checking what the encoder of the operating system keeps' -Skip:(-not $heicAvailable) {
        It 'Should write upright pixels with EXIF orientation 1 and keep the ICC profile, and EXIF and XMP where the encoder writes them' {
            $rotated = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'rotated.jpg') -Width 64 -Height 48 -Orientation 6 -ColorProfile -Xmp

            $result = ConvertTo-Heic -LiteralPath $rotated.FullName -WarningVariable conversionWarning -WarningAction SilentlyContinue
            $readBack = Get-ReadBack -Path $result.FullName

            $readBack.Width | Should -Be 48
            $readBack.Height | Should -Be 64
            (Get-ImageInfo -LiteralPath $result.FullName).Orientation | Should -Be 'TopLeft'
            $readBack.ProfileName | Should -Be 'Adobe RGB (1998)'
            $readBack.HasExif | Should -Be $script:keepsMetadata
            $readBack.HasXmp | Should -Be $script:keepsMetadata
            if ($script:keepsMetadata)
            {
                $readBack.ExifOrientation | Should -Be 1
                $readBack.Make | Should -Be 'TestCam Inc.'
                $conversionWarning | Should -BeNullOrEmpty
            }
            else
            {
                "$conversionWarning" | Should -Be "EXIF metadata (date taken, camera, GPS) is not written to Heic output: $($rotated.FullName)"
            }

            $expected = Get-ViewerColor -Path $rotated.FullName -X 10 -Y 10
            $actual = Get-ViewerColor -Path $result.FullName -X 10 -Y 10
            foreach ($channel in 0..2)
            {
                [System.Math]::Abs($actual[$channel] - $expected[$channel]) | Should -BeLessOrEqual 4
            }
        }

        It 'Should set the orientation of a big-endian EXIF block to 1 and keep the block otherwise' -Skip:$IsMacOS {
            # Camera EXIF is often big-endian (MM); Magick.NET passes such a block on as it is, and only the orientation value changes.
            $tiff = [System.Byte[]] @(
                0x4D, 0x4D, 0x00, 0x2A, 0, 0, 0, 8, 0, 2
                0x01, 0x0F, 0, 2, 0, 0, 0, 13, 0, 0, 0, 38
                0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 6, 0, 0
                0, 0, 0, 0
            ) + [System.Text.Encoding]::ASCII.GetBytes("BigEndianCam`0")
            $exif = [System.Text.Encoding]::ASCII.GetBytes("Exif`0`0") + $tiff
            $bigEndian = Join-Path -Path $script:tempDir.FullName -ChildPath 'bigendian.jpg'
            $image = [ImageMagick.MagickImage]::new([ImageMagick.MagickColors]::Red, 64, 48)
            try
            {
                $image.SetProfile([ImageMagick.ExifProfile]::new([System.Byte[]] $exif))
                $image.Orientation = [ImageMagick.OrientationType]::RightTop
                $image.Write($bigEndian, [ImageMagick.MagickFormat]::Jpeg)
            }
            finally
            {
                $image.Dispose()
            }

            $result = ConvertTo-Heic -LiteralPath $bigEndian
            $readBack = Get-ReadBack -Path $result.FullName
            $written = [ImageMagick.MagickImage]::new($result.FullName)
            try
            {
                $writtenExif = $written.GetExifProfile().ToByteArray()
            }
            finally
            {
                $written.Dispose()
            }

            $readBack.Width | Should -Be 48
            $readBack.Height | Should -Be 64
            $readBack.ExifOrientation | Should -Be 1
            $readBack.Make | Should -Be 'BigEndianCam'
            $writtenExif | Should -HaveCount $exif.Length
            [System.Text.Encoding]::ASCII.GetString($writtenExif, 6, 2) | Should -Be 'MM'
            $writtenExif[36..37] | Should -Be @(0, 1)
        }

        It 'Should keep an EXIF block and an XMP packet that cannot be parsed, as the other formats do' -Skip:$IsMacOS {
            # An IFD0 offset beyond the block and an undeclared namespace prefix: the encoder's own metadata writers refused both.
            $exifProfile = [ImageMagick.ExifProfile]::new()
            $exifProfile.SetValue([ImageMagick.ExifTag]::Make, 'TestCam')
            $exif = $exifProfile.ToByteArray()
            $tiffStart = 0
            if ([System.Text.Encoding]::ASCII.GetString($exif, 0, 4) -eq 'Exif')
            {
                $tiffStart = 6
            }

            $exif[$tiffStart + 4] = 0x7F
            $exif[$tiffStart + 5] = 0xFF
            $xmp = '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?><x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" foo:bar="1"/></rdf:RDF></x:xmpmeta><?xpacket end="w"?>'
            $damaged = Join-Path -Path $script:tempDir.FullName -ChildPath 'damaged.jpg'
            $image = [ImageMagick.MagickImage]::new([ImageMagick.MagickColors]::Blue, 64, 48)
            try
            {
                $image.SetProfile([ImageMagick.ExifProfile]::new($exif))
                $image.SetProfile([ImageMagick.XmpProfile]::new([System.Text.Encoding]::UTF8.GetBytes($xmp)))
                $image.Write($damaged, [ImageMagick.MagickFormat]::Jpeg)
            }
            finally
            {
                $image.Dispose()
            }

            $result = ConvertTo-Heic -LiteralPath $damaged -ErrorVariable conversionError
            $written = [ImageMagick.MagickImage]::new($result.FullName)
            try
            {
                $writtenExif = $written.GetExifProfile().ToByteArray()
                $writtenXmp = [System.Text.Encoding]::UTF8.GetString($written.GetXmpProfile().ToByteArray())
            }
            finally
            {
                $written.Dispose()
            }

            $conversionError | Should -BeNullOrEmpty
            $writtenExif | Should -Be $exif
            $writtenXmp | Should -BeExactly $xmp
        }

        It 'Should drop the EXIF thumbnail of a rotated camera photo' -Skip:$IsMacOS {
            $camera = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'camera.jpg') -Width 64 -Height 48 -Orientation 6 -ExifThumbnail

            $result = ConvertTo-Heic -LiteralPath $camera.FullName
            $readBack = Get-ReadBack -Path $result.FullName

            $readBack.Width | Should -Be 48
            $readBack.ExifOrientation | Should -Be 1
            $readBack.ThumbnailLength | Should -Be 0
            $readBack.Make | Should -Be 'TestCam'
        }

        It 'Should remove EXIF and XMP but keep the ICC profile with -StripMetadata' {
            $rich = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'rich.jpg') -Exif -ColorProfile -Xmp

            $result = ConvertTo-Heic -LiteralPath $rich.FullName -StripMetadata -WarningVariable conversionWarning
            $readBack = Get-ReadBack -Path $result.FullName

            $readBack.HasExif | Should -BeFalse
            $readBack.HasXmp | Should -BeFalse
            $readBack.ProfileName | Should -Be 'Adobe RGB (1998)'
            $conversionWarning | Should -BeNullOrEmpty
        }

        It 'Should keep the alpha channel where the encoder stores it and flatten onto white elsewhere' {
            $transparent = New-TestTransparentImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'logo.png')

            $result = ConvertTo-Heic -LiteralPath $transparent.FullName
            $readBack = Get-ReadBack -Path $result.FullName
            $transparentBlock, $halfBlock, $opaqueBlock = Get-ViewerColor -Path $result.FullName -Point @(@(8, 8), @(24, 8), @(40, 8))

            $readBack.HasAlpha | Should -Be $script:keepsAlpha
            if ($script:keepsAlpha)
            {
                $transparentBlock[3] | Should -BeLessOrEqual 2
                $halfBlock[3] | Should -BeIn (124..132)
                $halfBlock[0] | Should -BeGreaterOrEqual 240
                $opaqueBlock[3] | Should -Be 255
            }
            else
            {
                # Red with alpha 128 on white is 255, 127, 127, as Jpeg output shows it.
                $transparentBlock[0..2] | ForEach-Object -Process { $_ | Should -BeGreaterOrEqual 250 }
                $halfBlock[0] | Should -BeGreaterOrEqual 250
                $halfBlock[1] | Should -BeIn (120..135)
                $halfBlock[2] | Should -BeIn (120..135)
            }

            $opaqueBlock[2] | Should -BeGreaterOrEqual 240
            $opaqueBlock[0] | Should -BeLessOrEqual 15
        }

        It 'Should signal BT.709 colours in an nclx box of the primary image, also next to an ICC profile' -Skip:$IsMacOS {
            # The Windows HEIF decoder picks its YCbCr matrix by the primaries and libheif readers by the nclx box; both have to say BT.709.
            $red = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'red.png') -Format Png -Color '#FF0000'
            $profiled = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'profiled.jpg') -ColorProfile

            $plain = Get-TestHeifInfo -Path (ConvertTo-Heic -LiteralPath $red.FullName).FullName
            $withProfile = Get-TestHeifInfo -Path (ConvertTo-Heic -LiteralPath $profiled.FullName).FullName

            foreach ($info in $plain, $withProfile)
            {
                $info.Nclx.Primaries | Should -Be 1
                $info.Nclx.Transfer | Should -Be 13
                $info.Nclx.Matrix | Should -Be 1
                $info.Nclx.FullRange | Should -BeTrue
            }

            $plain.HasProfile | Should -BeFalse
            $withProfile.HasProfile | Should -BeTrue
        }

        It 'Should write files of the same size for the same image' -Skip:$IsMacOS {
            # The Windows encoder codes the part of a tile outside the image with data that changes from call to call, unless the tiles are filled.
            $noisy = Join-Path -Path $script:tempDir.FullName -ChildPath 'noisy.png'
            $image = [ImageMagick.MagickImage]::new('plasma:', 60, 80)
            try
            {
                $image.Write($noisy, [ImageMagick.MagickFormat]::Png)
            }
            finally
            {
                $image.Dispose()
            }

            $lengths = foreach ($run in 1..4)
            {
                (ConvertTo-Heic -LiteralPath $noisy -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath "run$run")).Length
            }

            $spread = ($lengths | Measure-Object -Maximum -Minimum)
            $spread.Maximum - $spread.Minimum | Should -BeLessOrEqual ($spread.Maximum / 100)
        }

        It 'Should write an image of <Width>x<Height> pixels that the HEIF decoder of Windows shows' -Skip:(-not $IsWindows) -ForEach @(
            @{ Width = 8; Height = 8 }
            @{ Width = 513; Height = 400 }
            @{ Width = 1025; Height = 100 }
            @{ Width = 100; Height = 1025 }
            @{ Width = 2049; Height = 200 }
        ) {
            # A side of 512 * k + 1 pixels used to end the clean aperture 1 pixel into a tile, which WIC refuses; WIC shows no side under 8 pixels at all.
            $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'wic.png') -Format Png -Width $Width -Height $Height -Color '#C03C3B'

            $result = ConvertTo-Heic -LiteralPath $source.FullName
            $decoded = Get-WicDecode -Path $result.FullName -Point @(@(0, 0), @(($Width - 1), ($Height - 1)))

            $decoded.Width | Should -Be $Width
            $decoded.Height | Should -Be $Height
            foreach ($color in $decoded.Colors)
            {
                [System.Math]::Abs($color[0] - 0xC0) | Should -BeLessOrEqual 8
                [System.Math]::Abs($color[1] - 0x3C) | Should -BeLessOrEqual 8
                [System.Math]::Abs($color[2] - 0x3B) | Should -BeLessOrEqual 8
            }
        }

        It 'Should give the HEIF decoder of Windows the ICC profile and the EXIF data' -Skip:(-not $IsWindows) {
            $rich = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'rich.jpg') -Exif -ColorProfile

            $result = ConvertTo-Heic -LiteralPath $rich.FullName
            $decoded = Get-WicDecode -Path $result.FullName

            $decoded.ColorContexts | Should -BeGreaterOrEqual 1
            $decoded.Make | Should -Be 'TestCam Inc.'
        }

        It 'Should show pure red as red' {
            # The WIC encoder converts with the BT.709 matrix; without an nclx box saying so, libheif readers would show 232, 0, 3.
            $red = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'red.png') -Format Png -Color '#FF0000'

            $result = ConvertTo-Heic -LiteralPath $red.FullName
            $color = Get-ViewerColor -Path $result.FullName -X 32 -Y 24

            $color[0] | Should -BeGreaterOrEqual 250
            $color[1] | Should -BeLessOrEqual 5
            $color[2] | Should -BeLessOrEqual 5
        }

        It 'Should write an image of <Width>x<Height> pixels with its exact size and colour' -ForEach @(
            @{ Width = 1; Height = 1 }
            @{ Width = 3; Height = 5 }
            @{ Width = 5; Height = 3 }
            @{ Width = 17; Height = 9 }
            @{ Width = 1921; Height = 33 }
        ) {
            $small = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'small.png') -Format Png -Width $Width -Height $Height -Color '#C03C3B'

            $result = ConvertTo-Heic -LiteralPath $small.FullName
            $readBack = Get-ReadBack -Path $result.FullName
            $color = Get-ViewerColor -Path $result.FullName -X ($Width - 1) -Y ($Height - 1)

            # The last column and row: the Windows encoder gets them repeated up to its padded size.
            $readBack.Width | Should -Be $Width
            $readBack.Height | Should -Be $Height
            [System.Math]::Abs($color[0] - 0xC0) | Should -BeLessOrEqual 6
            [System.Math]::Abs($color[1] - 0x3C) | Should -BeLessOrEqual 6
            [System.Math]::Abs($color[2] - 0x3B) | Should -BeLessOrEqual 6
        }

        It 'Should write a 12-megapixel image' {
            $large = Join-Path -Path $script:tempDir.FullName -ChildPath 'large.png'
            $image = [ImageMagick.MagickImage]::new('gradient:#FF0000-#0000FF', 4000, 3000)
            try
            {
                $image.Write($large, [ImageMagick.MagickFormat]::Png)
            }
            finally
            {
                $image.Dispose()
            }

            $result = ConvertTo-Heic -LiteralPath $large -Quality 50
            $readBack = Get-ReadBack -Path $result.FullName

            $readBack.Width | Should -Be 4000
            $readBack.Height | Should -Be 3000
            if ($IsLinux)
            {
                # Magick.NET cannot read an HEVC slice over about 16 MiB, so x265 is asked for one slice per 8 megapixels.
                (Get-TestHeifInfo -Path $result.FullName).SliceCount | Should -Be 2
            }

            $points = @(@(0, 0), @(3999, 2999), @(2000, 1500))
            $expected = Get-ViewerColor -Path $large -Point $points
            $actual = Get-ViewerColor -Path $result.FullName -Point $points
            foreach ($index in 0..2)
            {
                foreach ($channel in 0..2)
                {
                    [System.Math]::Abs($actual[$index][$channel] - $expected[$index][$channel]) | Should -BeLessOrEqual 6
                }
            }
        }

        It 'Should convert <Case> to sRGB pixels that show the same colour' -ForEach @(
            @{ Case = 'a grey image with a grey profile'; Parameters = @{ Format = 'Png'; GrayColorProfile = $true; Color = '#808080' }; ProfileSpace = 'sRGB' }
            @{ Case = 'a CMYK JPEG'; Parameters = @{ Format = 'Jpeg'; Cmyk = $true; Color = '#C03C3B' }; ProfileSpace = 'sRGB' }
        ) {
            $converted = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'converted.img') @Parameters

            $result = ConvertTo-Heic -LiteralPath $converted.FullName
            $readBack = Get-ReadBack -Path $result.FullName
            $expected = Get-ViewerColor -Path $converted.FullName -X 10 -Y 10
            $actual = Get-ViewerColor -Path $result.FullName -X 10 -Y 10

            $readBack.ProfileSpace | Should -Be $ProfileSpace
            foreach ($channel in 0..2)
            {
                [System.Math]::Abs($actual[$channel] - $expected[$channel]) | Should -BeLessOrEqual 4
            }
        }

        It 'Should leave a grey profile on colour pixels out' {
            $mismatch = Join-Path -Path $script:tempDir.FullName -ChildPath 'mismatch.png'
            $image = [ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new('#C03C3B'), 16, 16)
            try
            {
                $image.SetProfile((Get-TestGrayColorProfile))
                $image.Write($mismatch, [ImageMagick.MagickFormat]::Png)
            }
            finally
            {
                $image.Dispose()
            }

            $result = ConvertTo-Heic -LiteralPath $mismatch -Verbose 4>&1 | Where-Object -FilterScript { $_ -is [System.IO.FileInfo] }

            (Get-ReadBack -Path $result.FullName).ProfileName | Should -BeNullOrEmpty
        }

        It 'Should convert the pixels of a Lab image to sRGB' {
            $lab = Join-Path -Path $script:tempDir.FullName -ChildPath 'lab.tif'
            $image = [ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new('#C03C3B'), 16, 16)
            try
            {
                $image.ColorSpace = [ImageMagick.ColorSpace]::Lab
                $image.Write($lab, [ImageMagick.MagickFormat]::Tiff)
            }
            finally
            {
                $image.Dispose()
            }

            $result = ConvertTo-Heic -LiteralPath $lab
            $color = Get-ViewerColor -Path $result.FullName -X 8 -Y 8

            [System.Math]::Abs($color[0] - 0xC0) | Should -BeLessOrEqual 4
            [System.Math]::Abs($color[1] - 0x3C) | Should -BeLessOrEqual 4
            [System.Math]::Abs($color[2] - 0x3B) | Should -BeLessOrEqual 4
        }

        It 'Should write a 16-bit source as 8-bit HEIC' {
            $deep = Join-Path -Path $script:tempDir.FullName -ChildPath 'deep.png'
            $image = [ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new('#C03C3B'), 16, 16)
            try
            {
                $image.Depth = 16
                $image.Write($deep, [ImageMagick.MagickFormat]::Png48)
            }
            finally
            {
                $image.Dispose()
            }

            $result = ConvertTo-Heic -LiteralPath $deep
            $color = Get-ViewerColor -Path $result.FullName -X 8 -Y 8

            [System.Math]::Abs($color[0] - 0xC0) | Should -BeLessOrEqual 4
            [System.Math]::Abs($color[1] - 0x3C) | Should -BeLessOrEqual 4
        }

        It 'Should fail a <Width>x<Height> image on <Platform> with ImageWriteFailed and leave no temporary file' -ForEach @(
            @{ Platform = 'Windows'; Width = 22529; Height = 16; Message = '*a side can have at most 22528 pixels*' }
            @{ Platform = 'Linux'; Width = 33000; Height = 40; Message = '*refuses to read an image with a side over 32768 pixels*' }
            @{ Platform = 'Linux'; Width = 6000; Height = 16; Message = '*with a side shorter than 32 pixels the other side can have at most 4096 pixels*' }
        ) {
            # Windows' encoder rejects a grid side of 45 tiles; libheif refuses to read a side over 32768 pixels, and x265 a side shorter than 32 next to one longer than 4096.
            if ([PSImageConverter.HeicEncoder]::Platform -ne $Platform)
            {
                Set-ItResult -Skipped -Because "the limit belongs to the encoder of $Platform"
                return
            }

            $wide = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'wide.png') -Format Png -Width $Width -Height $Height

            $result = ConvertTo-Heic -LiteralPath $wide.FullName, $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result.Name | Should -Be 'IMG_0001.heic'
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'ImageWriteFailed,Convert-Image'
            $conversionError[0].TargetObject | Should -Be $wide.FullName
            "$($conversionError[0])" | Should -BeLike "Cannot write image '$(Join-Path -Path $script:tempDir.FullName -ChildPath 'wide.heic')': *"
            "$($conversionError[0])" | Should -BeLike $Message
            Join-Path -Path $script:tempDir.FullName -ChildPath 'wide.heic' | Should -Not -Exist
            Get-ChildItem -Path $script:tempDir.FullName -Force -Filter '*.tmp' | Should -BeNullOrEmpty
        }
    }
}
