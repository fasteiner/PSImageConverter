BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:fixture = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath
    $script:manifestPath = Join-Path -Path (Get-Module -Name $script:moduleName).ModuleBase -ChildPath "$($script:moduleName).psd1"
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')

    function Get-ProfileName
    {
        param ([System.String] $Path)

        $image = [ImageMagick.MagickImage]::new($Path)
        try
        {
            @($image.ProfileNames)
        }
        finally
        {
            $image.Dispose()
        }
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Convert-Image' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
        $script:source = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.HEIC'
        Copy-Item -Path $script:fixture -Destination $script:source
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'When converting to each format' {
        It 'Should write a <Format> file with extension <Extension> and return it' -ForEach @(
            @{ Format = 'Jpeg'; Extension = '.jpg' }
            @{ Format = 'Png'; Extension = '.png' }
            @{ Format = 'WebP'; Extension = '.webp' }
            @{ Format = 'Avif'; Extension = '.avif' }
            @{ Format = 'Jxl'; Extension = '.jxl' }
            @{ Format = 'Tiff'; Extension = '.tif' }
            @{ Format = 'Bmp'; Extension = '.bmp' }
            @{ Format = 'Gif'; Extension = '.gif' }
        ) {
            $result = Convert-Image -Path $script:source -Format $Format

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.FullName | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath "IMG_0001$Extension")
            $info = Get-ImageInfo -LiteralPath $result.FullName
            $info.Format | Should -Be $Format
            $info.Width | Should -Be (Get-ImageInfo -LiteralPath $script:source).Width
        }

        It 'Should not leave a temporary file behind' {
            $null = Convert-Image -Path $script:source -Format Png

            Get-ChildItem -Path $script:tempDir.FullName -Force -Filter '*.tmp' | Should -BeNullOrEmpty
        }

        It 'Should read sources of any format, not only HEIC' {
            $png = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'picture.png') -Format Png

            $result = Convert-Image -Path $png.FullName -Format WebP

            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'WebP'
        }
    }

    Context 'When -Path contains wildcards' {
        BeforeEach {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.HEIC')
        }

        It 'Should convert every matching file' {
            $result = Convert-Image (Join-Path -Path $script:tempDir.FullName -ChildPath '*.HEIC') -Format Png

            $result.Name | Sort-Object | Should -Be @('IMG_0001.png', 'IMG_0002.png')
        }

        It 'Should write a PathNotFound error when the pattern matches nothing' {
            $pattern = Join-Path -Path $script:tempDir.FullName -ChildPath '*.nomatch'

            $null = Convert-Image -Path $pattern -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Convert-Image'
            $conversionError[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $conversionError[0].TargetObject | Should -Be $pattern
        }
    }

    Context 'When file names contain wildcard characters' {
        BeforeEach {
            $script:bracketSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG[1].heic'
            Copy-Item -LiteralPath $script:fixture -Destination $script:bracketSource
        }

        It 'Should convert the file given by -LiteralPath' {
            $result = Convert-Image -LiteralPath $script:bracketSource -Format Png

            $result.Name | Should -Be 'IMG[1].png'
        }

        It 'Should accept the alias <Alias> for -LiteralPath' -ForEach @(
            @{ Alias = 'LP' }
            @{ Alias = 'PSPath' }
        ) {
            $parameters = @{ $Alias = $script:bracketSource; Format = 'Png' }

            $result = Convert-Image @parameters

            $result.Name | Should -Be 'IMG[1].png'
        }

        It 'Should bind files piped from Get-ChildItem to -LiteralPath' {
            $result = Get-ChildItem -LiteralPath $script:bracketSource | Convert-Image -Format Png

            $result.Name | Should -Be 'IMG[1].png'
        }

        It 'Should treat the brackets in -Path as a wildcard pattern' {
            $null = Convert-Image -Path $script:bracketSource -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Convert-Image'
        }
    }

    Context 'When folders are piped in' {
        It 'Should skip the folders silently and convert the files' {
            $subFolder = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'sub')
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $subFolder.FullName -ChildPath 'IMG_0002.heic')

            $result = Get-ChildItem -Path $script:tempDir.FullName -Recurse | Convert-Image -Format Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Sort-Object | Should -Be @('IMG_0001.png', 'IMG_0002.png')
        }

        It 'Should report the skipped folder in the verbose output' {
            $verbose = Convert-Image -LiteralPath $script:tempDir.FullName -Format Png -Verbose 4>&1

            "$verbose" | Should -Match 'Skipping the folder'
        }
    }

    Context 'When a path is not a file system path' {
        It 'Should write an UnsupportedProvider error for the input' {
            $null = Convert-Image -LiteralPath 'Env:\PATH' -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'UnsupportedProvider,Convert-Image'
            $conversionError[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        }

        It 'Should write an UnsupportedProvider error for the destination' {
            $null = Convert-Image -Path $script:source -Format Png -DestinationPath 'Env:\Pictures' -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'UnsupportedProvider,Convert-Image'
            $conversionError[0].TargetObject | Should -Be $script:source
        }

        It 'Should write an InvalidDestinationPath error for an unknown provider' {
            $null = Convert-Image -Path $script:source -Format Png -DestinationPath 'NoSuchProvider::C:\out' -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'InvalidDestinationPath,Convert-Image'
        }
    }

    Context 'When a conversion fails' {
        BeforeEach {
            $script:broken = Join-Path -Path $script:tempDir.FullName -ChildPath 'broken.heic'
            Set-Content -Path $script:broken -Value 'not an image'
            $script:missing = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.heic'
        }

        It 'Should write one ImageReadFailed record with the Magick exception and the source as target' {
            $null = Convert-Image -Path $script:broken -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'ImageReadFailed,Convert-Image'
            $conversionError[0].CategoryInfo.Category | Should -Be 'InvalidData'
            $conversionError[0].TargetObject | Should -Be $script:broken
            $conversionError[0].Exception | Should -BeOfType [ImageMagick.MagickException]
            "$($conversionError[0])" | Should -BeLike "Cannot read image '$script:broken': *"
        }

        It 'Should hold exactly one error record per failed file in -ErrorVariable' {
            $null = Convert-Image -Path $script:missing, $script:broken, $script:source -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 2
            $conversionError.FullyQualifiedErrorId | Should -Be @('PathNotFound,Convert-Image', 'ImageReadFailed,Convert-Image')
        }

        It 'Should set $? to $false and continue with the next file' {
            $result = Convert-Image -Path $script:broken, $script:source -Format Png -ErrorAction SilentlyContinue
            $succeeded = $?

            $succeeded | Should -BeFalse
            $result.Name | Should -Be 'IMG_0001.png'
        }

        It 'Should keep $? at $true when every file is converted' {
            $null = Convert-Image -Path $script:source -Format Png
            $succeeded = $?

            $succeeded | Should -BeTrue
        }

        It 'Should stop at the first failure with -ErrorAction Stop' {
            { Convert-Image -Path $script:broken, $script:source -Format Png -ErrorAction Stop } | Should -Throw -ErrorId 'ImageReadFailed,Convert-Image'

            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.png' | Should -Not -Exist
        }

        It 'Should make pwsh -Command fail when checking $?' {
            $command = "Import-Module -Name '$script:manifestPath'; Convert-Image -Path '$script:missing' -Format Png -ErrorAction SilentlyContinue; exit (!`$? ? 1 : 0)"

            & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command $command

            $LASTEXITCODE | Should -Be 1
        }

        It 'Should delete the temporary file when the pipeline is stopped while it is written' {
            # Random pixels make the AVIF encoder slow enough to stop the pipeline while it runs.
            $big = Join-Path -Path $script:tempDir.FullName -ChildPath 'big.png'
            $noise = [ImageMagick.MagickImage]::new([ImageMagick.MagickColor]::new('#808080'), 2000, 2000)
            try
            {
                $noise.AddNoise([ImageMagick.NoiseType]::Random)
                $noise.Write($big, [ImageMagick.MagickFormat]::Png)
            }
            finally
            {
                $noise.Dispose()
            }
            $conversion = {
                param ($Manifest, $Source, $Destination)

                Import-Module -Name $Manifest
                Convert-Image -LiteralPath $Source -Format Avif -Quality 100 -DestinationPath $Destination
            }

            # The poll does not sleep, so the stop also lands right after the temporary file is created.
            $leftovers = foreach ($round in 1..3)
            {
                $destination = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath "out$round")
                $powerShell = [System.Management.Automation.PowerShell]::Create()
                try
                {
                    $null = $powerShell.AddScript($conversion).AddArgument($script:manifestPath).AddArgument($big).AddArgument($destination.FullName)
                    $invocation = $powerShell.BeginInvoke()
                    $deadline = [System.DateTime]::UtcNow.AddSeconds(120)
                    while (-not $invocation.IsCompleted -and [System.DateTime]::UtcNow -lt $deadline -and -not [System.IO.Directory]::GetFiles($destination.FullName, '*.tmp'))
                    {
                    }

                    $powerShell.Stop()
                }
                finally
                {
                    $powerShell.Dispose()
                }

                [System.IO.Directory]::GetFiles($destination.FullName, '*.tmp')
            }

            $leftovers | Should -BeNullOrEmpty
        }
        It 'Should keep an existing target and leave no temporary file when writing fails' {
            # JPEG supports at most 65500 pixels per side, so the encoder fails after it opened the temporary file.
            $wide = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'wide.png') -Format Png -Width 70000 -Height 1
            $existing = Join-Path -Path $script:tempDir.FullName -ChildPath 'wide.jpg'
            Set-Content -Path $existing -Value 'existing'

            $null = Convert-Image -Path $wide.FullName -Format Jpeg -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'ImageWriteFailed,Convert-Image'
            $conversionError[0].CategoryInfo.Category | Should -Be 'WriteError'
            "$($conversionError[0])" | Should -BeLike "Cannot write image '$existing': *"
            Get-Content -Path $existing | Should -Be 'existing'
            Get-ChildItem -Path $script:tempDir.FullName -Force -Filter '*.tmp' | Should -BeNullOrEmpty
        }

        It 'Should write a clean error record for a path longer than 260 characters' -Skip:(-not $IsWindows) {
            $longFolder = $script:tempDir.FullName
            while ($longFolder.Length -lt 280)
            {
                $longFolder = Join-Path -Path $longFolder -ChildPath ('x' * 40)
            }
            $null = [System.IO.Directory]::CreateDirectory($longFolder)
            $longSource = Join-Path -Path $longFolder -ChildPath 'IMG_0002.heic'
            [System.IO.File]::Copy($script:fixture, $longSource)

            $result = Convert-Image -LiteralPath $longSource -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            # Magick.NET cannot open such paths on Windows; the conversion has to fail cleanly, if at all.
            if ($null -eq $result)
            {
                $conversionError | Should -HaveCount 1
                $conversionError[0].FullyQualifiedErrorId | Should -BeIn @('ImageReadFailed,Convert-Image', 'ImageWriteFailed,Convert-Image')
            }
            [System.IO.Directory]::GetFiles($longFolder, '*.tmp') | Should -BeNullOrEmpty
        }
    }

    Context 'When the target is the source file itself' {
        BeforeEach {
            $script:jpeg = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.jpg')
            $script:jpegHash = (Get-FileHash -LiteralPath $script:jpeg.FullName).Hash
        }

        It 'Should write a TargetIsSource error and keep the source, also with -Force' {
            $result = Convert-Image -Path $script:jpeg.FullName -Format Jpeg -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetIsSource,Convert-Image'
            $conversionError[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            (Get-FileHash -LiteralPath $script:jpeg.FullName).Hash | Should -Be $script:jpegHash
        }

        It 'Should treat a source that differs only in case as the target on Windows and macOS' -Skip:$IsLinux {
            $upper = Join-Path -Path $script:tempDir.FullName -ChildPath 'PHOTO2.JPG'
            Copy-Item -LiteralPath $script:jpeg.FullName -Destination $upper

            $null = Convert-Image -LiteralPath $upper -Format Jpeg -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetIsSource,Convert-Image'
        }

        It 'Should convert a source that differs only in case on Linux' -Skip:(-not $IsLinux) {
            $upper = Join-Path -Path $script:tempDir.FullName -ChildPath 'PHOTO2.JPG'
            Copy-Item -LiteralPath $script:jpeg.FullName -Destination $upper

            $result = Convert-Image -LiteralPath $upper -Format Jpeg

            $result.Name | Should -Be 'PHOTO2.jpg'
        }
    }

    Context 'When two sources map to the same target' {
        BeforeEach {
            # Different size than sample.heic, so the tests can tell which source the output came from.
            $script:otherSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heif') -Width 32 -Height 16
        }

        It 'Should write a DuplicateTarget error for the second source, also with -Force' {
            $result = Convert-Image -Path $script:source, $script:otherSource.FullName -Format Png -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -HaveCount 1
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'DuplicateTarget,Convert-Image'
            $conversionError[0].CategoryInfo.Category | Should -Be 'ResourceExists'
            $conversionError[0].TargetObject | Should -Be $script:otherSource.FullName
            (Get-ImageInfo -LiteralPath $result.FullName).Width | Should -Be 64
        }

        It 'Should predict the DuplicateTarget error with -WhatIf' {
            $null = Convert-Image -Path $script:source, $script:otherSource.FullName -Format Png -WhatIf -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError[0].FullyQualifiedErrorId | Should -Be 'DuplicateTarget,Convert-Image'
            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.png' | Should -Not -Exist
        }

        It 'Should detect files of different folders piped into one -DestinationPath' {
            $tree = Join-Path -Path $script:tempDir.FullName -ChildPath 'tree'
            foreach ($folder in 'a', 'b')
            {
                $null = New-Item -ItemType Directory -Path (Join-Path -Path $tree -ChildPath $folder)
                Copy-Item -Path $script:fixture -Destination (Join-Path -Path $tree -ChildPath "$folder/IMG_0009.heic")
            }
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'out'

            $result = Get-ChildItem -Path $tree -Recurse | Convert-Image -Format Png -DestinationPath $destination -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -HaveCount 1
            $conversionError.FullyQualifiedErrorId | Should -Be 'DuplicateTarget,Convert-Image'
        }

        It 'Should convert a source given twice only once' {
            Remove-Item -LiteralPath $script:otherSource.FullName

            $output = Convert-Image -Path $script:source, (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_*') -Format Png -Verbose -ErrorVariable conversionError 4>&1

            $conversionError | Should -BeNullOrEmpty
            @($output | Where-Object -FilterScript { $_ -is [System.IO.FileInfo] }) | Should -HaveCount 1
            "$($output | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] })" | Should -Match 'already given earlier'
        }

        It 'Should skip a source that an earlier source of the same call has written' {
            $existing = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.png') -Format Png
            Remove-Item -LiteralPath $script:otherSource.FullName

            $output = Convert-Image -Path $script:source, $existing.FullName -Format Png -Force -Verbose -ErrorVariable conversionError 4>&1

            $conversionError | Should -BeNullOrEmpty
            @($output | Where-Object -FilterScript { $_ -is [System.IO.FileInfo] }) | Should -HaveCount 1
            "$($output | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] })" | Should -Match 'is the output of'
        }
    }

    Context 'When the target file already exists' {
        BeforeEach {
            $script:target = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg'
            Set-Content -Path $script:target -Value 'existing'
        }

        It 'Should write a TargetExists error and keep the file without -Force' {
            $result = Convert-Image -Path $script:source -Format Jpeg -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetExists,Convert-Image'
            $conversionError[0].CategoryInfo.Category | Should -Be 'ResourceExists'
            Get-Content -Path $script:target | Should -Be 'existing'
        }

        It 'Should overwrite the file with -Force' {
            $result = Convert-Image -Path $script:source -Format Jpeg -Force

            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Jpeg'
        }

        It 'Should overwrite a read-only file with -Force' {
            Set-ItemProperty -Path $script:target -Name IsReadOnly -Value $true

            $result = Convert-Image -Path $script:source -Format Jpeg -Force

            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Jpeg'
        }

        It 'Should overwrite a hidden file with -Force' -Skip:(-not $IsWindows) {
            [System.IO.File]::SetAttributes($script:target, [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::ReadOnly)

            $result = Convert-Image -Path $script:source -Format Jpeg -Force

            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Jpeg'
        }

        It 'Should keep the attributes of a read-only, hidden file it cannot replace with -Force' -Skip:(-not $IsWindows) {
            $protected = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::ReadOnly
            [System.IO.File]::SetAttributes($script:target, $protected)
            # Another program that has the file open without delete sharing keeps it from being replaced.
            $lock = [System.IO.File]::Open($script:target, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try
            {
                $null = Convert-Image -Path $script:source -Format Jpeg -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            finally
            {
                $lock.Dispose()
            }

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'ImageWriteFailed,Convert-Image'
            [System.IO.File]::GetAttributes($script:target) | Should -Be $protected
            Get-Content -Path $script:target -Force | Should -Be 'existing'
            Get-ChildItem -Path $script:tempDir.FullName -Force -Filter '*.tmp' | Should -BeNullOrEmpty
        }
    }

    Context 'When a destination folder is given' {
        It 'Should create the folder and write the file into it' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'out/png'

            $result = Convert-Image -Path $script:source -Format Png -DestinationPath $destination

            $result.DirectoryName | Should -Be (Get-Item -LiteralPath $destination).FullName
        }

        It 'Should resolve a relative folder against the current location' {
            Push-Location -LiteralPath $script:tempDir.FullName
            try
            {
                $result = Convert-Image -Path 'IMG_0001.HEIC' -Format Png -DestinationPath 'relative'
            }
            finally
            {
                Pop-Location
            }

            $result.FullName | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'relative/IMG_0001.png' | Convert-Path)
        }

        It 'Should write a DestinationNotDirectory error when the destination is a file' {
            $file = Join-Path -Path $script:tempDir.FullName -ChildPath 'file.txt'
            Set-Content -Path $file -Value 'x'

            $null = Convert-Image -Path $script:source -Format Png -DestinationPath $file -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'DestinationNotDirectory,Convert-Image'
            $conversionError[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            Get-Content -Path $file | Should -Be 'x'
        }
    }

    Context 'When using -WhatIf' {
        It 'Should neither write the file nor create the destination folder' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'whatif'

            $result = Convert-Image -Path $script:source -Format Png -DestinationPath $destination -WhatIf

            $result | Should -BeNullOrEmpty
            $destination | Should -Not -Exist
        }
    }

    Context 'When a quality is given' {
        It 'Should write a smaller lossy file for a lower quality' {
            $high = Convert-Image -Path $script:source -Format Jpeg -Quality 100 -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'high')
            $low = Convert-Image -Path $script:source -Format Jpeg -Quality 10 -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'low')

            $low.Length | Should -BeLessThan $high.Length
        }

        It 'Should report that the quality is ignored for <Format>' -ForEach @(
            @{ Format = 'Png' }
            @{ Format = 'Tiff' }
        ) {
            $verbose = Convert-Image -Path $script:source -Format $Format -Quality 50 -Verbose 4>&1 | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] }

            "$verbose" | Should -Match 'Quality is ignored'
        }
    }

    Context 'When metadata should be stripped' {
        BeforeEach {
            $script:richSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'rich.jpg') -Exif -ColorProfile -Xmp -Iptc -Comment 'secret comment'
        }

        It 'Should remove EXIF, XMP, IPTC and the comment but keep the ICC profile for <Format>' -ForEach @(
            @{ Format = 'Jpeg' }
            @{ Format = 'Png' }
            @{ Format = 'WebP' }
            @{ Format = 'Tiff' }
        ) {
            $result = Convert-Image -Path $script:richSource.FullName -Format $Format -StripMetadata -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'stripped')

            Get-ProfileName -Path $result.FullName | Should -Be @('icc')
            $content = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($result.FullName))
            $content | Should -Not -Match 'TestCam|XmpTester|IptcTester|secret comment'
            $output = [ImageMagick.MagickImage]::new($result.FullName)
            try
            {
                $output.GetColorProfile().Description | Should -Be 'Adobe RGB (1998)'
            }
            finally
            {
                $output.Dispose()
            }
        }

        It 'Should keep the EXIF data without -StripMetadata' {
            $result = Convert-Image -Path $script:richSource.FullName -Format Png

            $info = Get-ImageInfo -LiteralPath $result.FullName
            $info.HasExif | Should -BeTrue
            $info.CameraMake | Should -Be 'TestCam Inc.'
        }

        It 'Should strip a source without ICC profile' {
            $result = Convert-Image -Path $script:source -Format Png -StripMetadata

            Get-ProfileName -Path $result.FullName | Should -BeNullOrEmpty
        }
    }

    Context 'When the output format cannot carry EXIF data' {
        BeforeEach {
            $script:exifSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.jpg') -Exif
        }

        It 'Should warn once per file for <Format>' -ForEach @(
            @{ Format = 'Tiff' }
            @{ Format = 'Bmp' }
            @{ Format = 'Gif' }
        ) {
            $null = Convert-Image -Path $script:exifSource.FullName -Format $Format -WarningAction SilentlyContinue -WarningVariable conversionWarning

            $conversionWarning | Should -HaveCount 1
            "$($conversionWarning[0])" | Should -Be "EXIF metadata (date taken, camera, GPS) is not written to $Format output: $($script:exifSource.FullName)"
        }

        It 'Should not warn with -StripMetadata' {
            $null = Convert-Image -Path $script:exifSource.FullName -Format Tiff -StripMetadata -WarningVariable conversionWarning

            $conversionWarning | Should -BeNullOrEmpty
        }

        It 'Should not warn for a source without EXIF data' {
            $null = Convert-Image -Path $script:source -Format Gif -WarningVariable conversionWarning

            $conversionWarning | Should -BeNullOrEmpty
        }

        It 'Should not warn for <Format>, which keeps the EXIF data' -ForEach @(
            @{ Format = 'Jpeg' }
            @{ Format = 'Avif' }
        ) {
            $null = Convert-Image -Path $script:exifSource.FullName -Format $Format -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out') -WarningVariable conversionWarning

            $conversionWarning | Should -BeNullOrEmpty
        }
    }

    Context 'When the source has an EXIF orientation' {
        It 'Should apply the orientation to the pixels' {
            $rotated = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'rotated.jpg') -Width 60 -Height 20 -Orientation 6

            $result = Convert-Image -Path $rotated.FullName -Format Png

            $info = Get-ImageInfo -LiteralPath $result.FullName
            $info.Width | Should -Be 20
            $info.Height | Should -Be 60
            $info.Orientation | Should -Be 'TopLeft'
        }

        It 'Should remove the EXIF thumbnail, which still shows the stored orientation' {
            $camera = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'camera.jpg') -Width 60 -Height 40 -Orientation 6 -ExifThumbnail
            $before = [ImageMagick.MagickImage]::new($camera.FullName)
            try
            {
                $before.GetExifProfile().ThumbnailLength | Should -BeGreaterThan 0
            }
            finally
            {
                $before.Dispose()
            }

            $result = Convert-Image -LiteralPath $camera.FullName -Format Jpeg -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out')

            $output = [ImageMagick.MagickImage]::new($result.FullName)
            try
            {
                $output.GetExifProfile().ThumbnailLength | Should -Be 0
                $output.GetExifProfile().GetValue([ImageMagick.ExifTag]::Make).Value | Should -Be 'TestCam'
                $output.Orientation | Should -Be 'TopLeft'
                $output.Width | Should -Be 40
            }
            finally
            {
                $output.Dispose()
            }
        }

        It 'Should keep the EXIF thumbnail of an image that is stored upright' {
            $camera = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'camera.jpg') -Orientation 1 -ExifThumbnail

            $result = Convert-Image -LiteralPath $camera.FullName -Format Jpeg -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out')

            $output = [ImageMagick.MagickImage]::new($result.FullName)
            try
            {
                $output.GetExifProfile().ThumbnailLength | Should -BeGreaterThan 0
            }
            finally
            {
                $output.Dispose()
            }
        }

        It 'Should set the XMP orientation to 1 and swap the XMP pixel dimensions for <Format>' -ForEach @(
            @{ Format = 'Jpeg' }
            @{ Format = 'Png' }
        ) {
            $exported = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exported.jpg') -Width 60 -Height 20 -Orientation 6 -XmpOrientation

            $result = Convert-Image -LiteralPath $exported.FullName -Format $Format -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out')

            $output = [ImageMagick.MagickImage]::new($result.FullName)
            try
            {
                $packet = [System.Text.Encoding]::UTF8.GetString($output.GetXmpProfile().ToByteArray())
            }
            finally
            {
                $output.Dispose()
            }
            $packet | Should -Match 'tiff:Orientation="1"'
            $packet | Should -Match 'exif:PixelXDimension="20"'
            $packet | Should -Match 'exif:PixelYDimension="60"'
        }
    }

    Context 'When the output is piped into the next cmdlet' {
        BeforeEach {
            # IMG[1] as a wildcard pattern matches IMG1, which is a different, smaller image.
            $script:bracketSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG[1].heic'
            Copy-Item -LiteralPath $script:fixture -Destination $script:bracketSource
            $null = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG1.png') -Format Png -Width 10 -Height 10
        }

        It 'Should return the item with the PSPath that Get-Item returns' {
            $result = Convert-Image -LiteralPath $script:bracketSource -Format Png

            $result.PSPath | Should -Be (Get-Item -LiteralPath $result.FullName).PSPath
        }

        It 'Should pass a file with wildcard characters in its name on to Get-ImageInfo unchanged' {
            $info = Convert-Image -LiteralPath $script:bracketSource -Format Png | Get-ImageInfo -ErrorVariable infoError

            $infoError | Should -BeNullOrEmpty
            $info.Path | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG[1].png')
            $info.Width | Should -Be 64
        }

        It 'Should pass a file with wildcard characters in its name on to a second conversion unchanged' {
            $result = Convert-Image -LiteralPath $script:bracketSource -Format Png | Convert-Image -Format WebP -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be 'IMG[1].webp'
            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG1.webp' | Should -Not -Exist
        }
    }

    Context 'When a folder is reached through a link or another spelling' {
        BeforeEach {
            $script:realFolder = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'real')
            $script:linkFolder = Join-Path -Path $script:tempDir.FullName -ChildPath 'link'
            # A junction needs no administrator rights on Windows.
            $linkType = 'SymbolicLink'
            if ($IsWindows)
            {
                $linkType = 'Junction'
            }
            $null = New-Item -ItemType $linkType -Path $script:linkFolder -Target $script:realFolder.FullName
            $script:photo = New-TestImage -Path (Join-Path -Path $script:realFolder.FullName -ChildPath 'photo.jpg') -Exif
            $script:photoHash = (Get-FileHash -LiteralPath $script:photo.FullName).Hash
        }

        AfterEach {
            Remove-Item -LiteralPath $script:linkFolder -Force -ErrorAction SilentlyContinue
        }

        It 'Should write a TargetIsSource error with -Force when -DestinationPath reaches the source folder through a link' {
            $result = Convert-Image -LiteralPath $script:photo.FullName -Format Jpeg -DestinationPath $script:linkFolder -Force -StripMetadata -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetIsSource,Convert-Image'
            (Get-FileHash -LiteralPath $script:photo.FullName).Hash | Should -Be $script:photoHash
        }

        It 'Should write a TargetIsSource error with -Force when the source is given through a link' {
            $null = Convert-Image -LiteralPath (Join-Path -Path $script:linkFolder -ChildPath 'photo.jpg') -Format Jpeg -DestinationPath $script:realFolder.FullName -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetIsSource,Convert-Image'
            (Get-FileHash -LiteralPath $script:photo.FullName).Hash | Should -Be $script:photoHash
        }

        It 'Should write a TargetIsSource error with -Force for a source given with the \\?\ prefix' -Skip:(-not $IsWindows) {
            $null = Convert-Image -LiteralPath ('\\?\' + $script:photo.FullName) -Format Jpeg -DestinationPath $script:realFolder.FullName -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetIsSource,Convert-Image'
            (Get-FileHash -LiteralPath $script:photo.FullName).Hash | Should -Be $script:photoHash
        }

        It 'Should write a DuplicateTarget error with -Force when a second source reaches a file written in the same call through a link' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:realFolder.FullName -ChildPath 'x.heic')
            $null = New-TestImage -Path (Join-Path -Path $script:realFolder.FullName -ChildPath 'x.heif') -Width 32 -Height 16
            $sources = @(
                (Join-Path -Path $script:realFolder.FullName -ChildPath 'x.heic')
                (Join-Path -Path $script:linkFolder -ChildPath 'x.heif')
            )

            $result = Convert-Image -LiteralPath $sources -Format Png -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -HaveCount 1
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'DuplicateTarget,Convert-Image'
            (Get-ImageInfo -LiteralPath (Join-Path -Path $script:realFolder.FullName -ChildPath 'x.png')).Width | Should -Be 64
        }

        It 'Should skip a file written in the same call when it is piped in again through a link' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:realFolder.FullName -ChildPath 'x.heic')
            $sources = @(
                (Join-Path -Path $script:realFolder.FullName -ChildPath 'x.heic')
                (Join-Path -Path $script:linkFolder -ChildPath 'x.png')
            )

            $output = $sources | ForEach-Object -Process { [PSCustomObject] @{ LiteralPath = $_ } } | Convert-Image -Format Png -Verbose -ErrorVariable conversionError 4>&1

            $conversionError | Should -BeNullOrEmpty
            @($output | Where-Object -FilterScript { $_ -is [System.IO.FileInfo] }) | Should -HaveCount 1
            "$($output | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] })" | Should -Match 'is the output of'
        }
    }

    Context 'When the file system ignores case but paths are compared case-sensitively' -Skip:$IsLinux {
        <#
            Linux compares paths case-sensitively, but an exFAT camera card, a CIFS share or /mnt/c in WSL
            ignore case. Windows and macOS file systems ignore case by default, so the Linux comparer
            reproduces that situation here.
        #>
        BeforeEach {
            Mock -ModuleName $script:moduleName -CommandName Get-ImageConverterPathComparer -MockWith { [System.StringComparer]::Ordinal }
        }

        It 'Should write a TargetIsSource error with -Force for a source whose extension differs only in case' {
            $camera = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'CAMERA.JPG') -Exif
            $cameraHash = (Get-FileHash -LiteralPath $camera.FullName).Hash

            $null = Convert-Image -LiteralPath $camera.FullName -Format Jpeg -Force -StripMetadata -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetIsSource,Convert-Image'
            (Get-FileHash -LiteralPath $camera.FullName).Hash | Should -Be $cameraHash
        }

        It 'Should write a DuplicateTarget error with -Force for two sources whose names differ only in case' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'y.heic')
            $null = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'Y.heif') -Width 32 -Height 16
            $sources = @(
                (Join-Path -Path $script:tempDir.FullName -ChildPath 'y.heic')
                (Join-Path -Path $script:tempDir.FullName -ChildPath 'Y.heif')
            )

            $result = Convert-Image -LiteralPath $sources -Format Png -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -HaveCount 1
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'DuplicateTarget,Convert-Image'
            (Get-ImageInfo -LiteralPath $result.FullName).Width | Should -Be 64
        }
    }

    Context 'When a file is given by its short 8.3 path and its long path' -Skip:(-not $IsWindows) {
        It 'Should convert it once without an error' {
            $longFolder = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'LongFolderNameForShortTest')
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $longFolder.FullName -ChildPath 'photo.heic')
            $shortFolder = (New-Object -ComObject 'Scripting.FileSystemObject').GetFolder($longFolder.FullName).ShortPath
            if ($shortFolder -notmatch '~')
            {
                Set-ItResult -Skipped -Because 'the volume creates no 8.3 names'
                return
            }
            $sources = @(
                (Join-Path -Path $shortFolder -ChildPath 'photo.heic')
                (Join-Path -Path $longFolder.FullName -ChildPath 'photo.heic')
            )

            $result = Convert-Image -LiteralPath $sources -Format Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result | Should -HaveCount 1
            $result.FullName | Should -Be (Join-Path -Path $longFolder.FullName -ChildPath 'photo.png')
        }
    }

    Context 'When -Path is not a valid wildcard pattern' {
        BeforeEach {
            $script:oddSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'a[.heic'
            Copy-Item -LiteralPath $script:fixture -Destination $script:oddSource
        }

        It 'Should write exactly one InvalidWildcardPattern error' {
            $errorCount = $global:Error.Count

            $null = Convert-Image -Path $script:oddSource -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'InvalidWildcardPattern,Convert-Image'
            $conversionError[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $conversionError[0].TargetObject | Should -Be $script:oddSource
            "$($conversionError[0])" | Should -Match 'LiteralPath'
            $global:Error.Count - $errorCount | Should -Be 1
        }

        It 'Should stop with the InvalidWildcardPattern id with -ErrorAction Stop' {
            { Convert-Image -Path $script:oddSource -Format Png -ErrorAction Stop } | Should -Throw -ErrorId 'InvalidWildcardPattern,Convert-Image'
        }

        It 'Should convert the file given by -LiteralPath' {
            $result = Convert-Image -LiteralPath $script:oddSource -Format Png

            $result.Name | Should -Be 'a[.png'
        }
    }

    Context 'When -DestinationPath cannot be used' {
        It 'Should write exactly one InvalidDestinationPath error for a path that leaves its drive root' {
            $null = New-PSDrive -Name 'PsicRoot' -PSProvider FileSystem -Root $script:tempDir.FullName -Scope Global
            try
            {
                $errorCount = $global:Error.Count

                $null = Convert-Image -Path $script:source -Format Png -DestinationPath 'PsicRoot:/../../x' -ErrorAction SilentlyContinue -ErrorVariable conversionError

                $conversionError | Should -HaveCount 1
                $conversionError[0].FullyQualifiedErrorId | Should -Be 'InvalidDestinationPath,Convert-Image'
                $global:Error.Count - $errorCount | Should -Be 1
                { Convert-Image -Path $script:source -Format Png -DestinationPath 'PsicRoot:/../../x' -ErrorAction Stop } | Should -Throw -ErrorId 'InvalidDestinationPath,Convert-Image'
            }
            finally
            {
                Remove-PSDrive -Name 'PsicRoot' -Scope Global
            }
        }

        It 'Should write an UnsupportedProvider error for the root <Root> of another provider' -ForEach @(
            @{ Root = 'Env:\' }
            @{ Root = 'Function:\' }
        ) {
            $null = Convert-Image -Path $script:source -Format Png -DestinationPath $Root -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'UnsupportedProvider,Convert-Image'
        }

        It 'Should write a DestinationNotDirectory error when a parent folder of the destination is a file, also with -WhatIf' {
            $file = Join-Path -Path $script:tempDir.FullName -ChildPath 'file.txt'
            Set-Content -Path $file -Value 'x'
            $destination = Join-Path -Path $file -ChildPath 'sub'

            $null = Convert-Image -Path $script:source -Format Png -DestinationPath $destination -WhatIf -ErrorAction SilentlyContinue -ErrorVariable predictedError
            $null = Convert-Image -Path $script:source -Format Png -DestinationPath $destination -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $predictedError | Should -HaveCount 1
            $predictedError[0].FullyQualifiedErrorId | Should -Be 'DestinationNotDirectory,Convert-Image'
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'DestinationNotDirectory,Convert-Image'
            Get-Content -Path $file | Should -Be 'x'
        }
    }

    Context 'When names contain characters that ImageMagick interprets' {
        It 'Should keep the name <Name> and leave no temporary file' -ForEach @(
            @{ Name = 'my%20docs' }
            @{ Name = 'seq%03d' }
            @{ Name = 'a%x' }
        ) {
            $percentSource = Join-Path -Path $script:tempDir.FullName -ChildPath "$Name.heic"
            Copy-Item -LiteralPath $script:fixture -Destination $percentSource

            $result = Convert-Image -LiteralPath $percentSource -Format Jpeg -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be "$Name.jpg"
            Get-ChildItem -LiteralPath $script:tempDir.FullName -Force -Filter '*.tmp' | Should -BeNullOrEmpty
        }

        It 'Should write into a destination folder with a percent sign in its name' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'out%20dir'

            $result = Convert-Image -Path $script:source -Format Png -DestinationPath $destination

            $result.DirectoryName | Should -Be $destination
        }

        It 'Should read a source whose name ends with a bracket expression' {
            $bracketSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'scan[1]'
            Copy-Item -LiteralPath $script:fixture -Destination $bracketSource

            $result = Convert-Image -LiteralPath $bracketSource -Format Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be 'scan[1].png'
        }

        It 'Should write a target whose name or path is close to the length limit' {
            # 255 characters is the longest file name on every platform and, on Windows, almost the longest path without long path support.
            $nameLength = 250
            if ($IsWindows)
            {
                $nameLength = 255 - $script:tempDir.FullName.Length - 1
            }
            $baseName = 'L' * ($nameLength - '.png'.Length)
            $longSource = Join-Path -Path $script:tempDir.FullName -ChildPath "$baseName.heic"
            [System.IO.File]::Copy($script:fixture, $longSource)

            $result = Convert-Image -LiteralPath $longSource -Format Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be "$baseName.png"
        }
    }

    Context 'When the source is a CMYK image' {
        BeforeAll {
            function Get-DisplayedColor
            {
                param ([System.String] $Path, [System.Management.Automation.SwitchParameter] $FromCmyk)

                $image = [ImageMagick.MagickImage]::new($Path)
                try
                {
                    if ($FromCmyk)
                    {
                        $null = $image.TransformColorSpace([ImageMagick.ColorProfiles]::USWebCoatedSWOP, [ImageMagick.ColorProfiles]::SRGB)
                    }

                    $color = $image.GetPixels().GetPixel(0, 0).ToColor()
                    @([System.Int32] $color.R, [System.Int32] $color.G, [System.Int32] $color.B)
                }
                finally
                {
                    $image.Dispose()
                }
            }
        }

        BeforeEach {
            $script:cmykSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'print.jpg') -Color '#C03C3B' -Cmyk
        }

        It 'Should convert the colours through the CMYK profile for <Format> output' -ForEach @(
            @{ Format = 'Png' }
            @{ Format = 'WebP' }
            @{ Format = 'Avif' }
            @{ Format = 'Jxl' }
            @{ Format = 'Bmp' }
            @{ Format = 'Gif' }
        ) {
            $expected = Get-DisplayedColor -Path $script:cmykSource.FullName -FromCmyk

            $result = Convert-Image -LiteralPath $script:cmykSource.FullName -Format $Format -Quality 100

            $actual = Get-DisplayedColor -Path $result.FullName
            foreach ($channel in 0..2)
            {
                [System.Math]::Abs($actual[$channel] - $expected[$channel]) | Should -BeLessOrEqual 12 -Because "channel $channel is $($actual[$channel]), the source shows $($expected[$channel])"
            }
        }

        It 'Should keep CMYK and the CMYK profile for <Format> output' -ForEach @(
            @{ Format = 'Jpeg' }
            @{ Format = 'Tiff' }
        ) {
            $result = Convert-Image -LiteralPath $script:cmykSource.FullName -Format $Format -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out')

            $output = [ImageMagick.MagickImage]::new($result.FullName)
            try
            {
                $output.ColorSpace | Should -Be 'CMYK'
                $output.GetColorProfile().Description | Should -BeLike 'U.S. Web Coated (SWOP)*'
            }
            finally
            {
                $output.Dispose()
            }
        }
    }

    Context 'When comparing the metadata table with the written files' {
        It 'Should write EXIF data to <Format> output exactly when the format table says so' -ForEach @(
            @{ Format = 'Jpeg' }
            @{ Format = 'Png' }
            @{ Format = 'WebP' }
            @{ Format = 'Avif' }
            @{ Format = 'Jxl' }
            @{ Format = 'Tiff' }
            @{ Format = 'Bmp' }
            @{ Format = 'Gif' }
        ) {
            $exifSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.jpg') -Exif
            $keepsExif = InModuleScope -ModuleName $script:moduleName -Parameters @{ Format = $Format } { (Get-ImageConverterFormatInfo -Format $Format).KeepsExif }

            $result = Convert-Image -LiteralPath $exifSource.FullName -Format $Format -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out') -WarningAction SilentlyContinue

            (Get-ImageInfo -LiteralPath $result.FullName).HasExif | Should -Be $keepsExif
        }
    }
}
