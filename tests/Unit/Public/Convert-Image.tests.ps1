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

    # The colour a colour-managed viewer shows: the pixel converted from the embedded profile to sRGB; an untagged image is sRGB.
    function Get-ViewerColor
    {
        param ([System.String] $Path)

        $image = [ImageMagick.MagickImage]::new($Path)
        try
        {
            if ($null -ne $image.GetColorProfile())
            {
                $null = $image.TransformColorSpace([ImageMagick.ColorProfiles]::SRGB)
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
            "$($conversionError[0])" | Should -BeLike 'No file matches the pattern *'
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

        It 'Should treat the brackets in -Path as a wildcard pattern and say so' {
            $null = Convert-Image -Path $script:bracketSource -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Convert-Image'
            $expected = [System.Management.Automation.WildcardPattern]::Escape("No file matches the pattern '$($script:bracketSource)'. [ and ] are wildcard characters, ") + '*' + [System.Management.Automation.WildcardPattern]::Escape('; -LiteralPath takes the name as written.')
            "$($conversionError[0])" | Should -BeLike $expected
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
        It 'Should write an UnsupportedProvider error for the input, with the input as target' {
            $null = Convert-Image -LiteralPath 'Env:\PATH' -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'UnsupportedProvider,Convert-Image'
            $conversionError[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $conversionError[0].TargetObject | Should -Be 'Env:\PATH'
        }

        It 'Should write one UnsupportedProvider error for a pattern that matches several items of another provider' {
            $env:PSIC_CONVERT_A = 'a'
            $env:PSIC_CONVERT_B = 'b'
            try
            {
                $result = Convert-Image -Path 'Env:\PSIC_CONVERT_*', $script:source -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            finally
            {
                Remove-Item -Path 'Env:\PSIC_CONVERT_A', 'Env:\PSIC_CONVERT_B'
            }

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'UnsupportedProvider,Convert-Image'
            $conversionError[0].TargetObject | Should -Be 'Env:\PSIC_CONVERT_*'
            $result.Name | Should -Be 'IMG_0001.png'
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
            [System.IO.File]::SetAttributes($script:target, [System.IO.FileAttributes]::Hidden)

            $result = Convert-Image -Path $script:source -Format Jpeg -Force -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.FullName | Should -Be $script:target
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Jpeg'
        }

        It 'Should overwrite a read-only, hidden file with -Force' -Skip:(-not $IsWindows) {
            [System.IO.File]::SetAttributes($script:target, [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::ReadOnly)

            $result = Convert-Image -Path $script:source -Format Jpeg -Force

            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Jpeg'
        }

        It 'Should overwrite a hidden dot file with -Force' -Skip:$IsWindows {
            $dotSource = Join-Path -Path $script:tempDir.FullName -ChildPath '.IMG_0002.HEIC'
            Copy-Item -LiteralPath $script:fixture -Destination $dotSource
            $dotTarget = Join-Path -Path $script:tempDir.FullName -ChildPath '.IMG_0002.jpg'
            Set-Content -Path $dotTarget -Value 'existing'

            $result = Convert-Image -LiteralPath $dotSource -Format Jpeg -Force

            $result.FullName | Should -Be $dotTarget
            (Get-ImageInfo -LiteralPath $dotTarget).Format | Should -Be 'Jpeg'
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
    }

    Context 'When a path uses a PSDrive that the caller created in its own scope' {
        BeforeEach {
            # The module resolves paths in its own session state, which sees only the global drives.
            $script:hint = "drive 'PsicScopeDrive' was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module). Create the drive with New-PSDrive -Scope Global, or use the file system path; the root of the drive is '$($script:tempDir.FullName)'."
        }

        It 'Should write PathNotFound that explains the drive for <Parameter> <Path>' -ForEach @(
            @{ Parameter = 'Path'; Path = 'PsicScopeDrive:\IMG_0001.HEIC' }
            @{ Parameter = 'Path'; Path = 'PsicScopeDrive:\*.HEIC' }
            @{ Parameter = 'LiteralPath'; Path = 'PsicScopeDrive:\IMG_0001.HEIC' }
        ) {
            # Without -Scope Global the drive exists in this It block's scope only, like a drive created in a function.
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
            $parameters = @{ $Parameter = $Path }
            $errorCount = $global:Error.Count

            $result = Convert-Image @parameters -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $global:Error.Count - $errorCount | Should -Be 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Convert-Image'
            $conversionError[0].TargetObject | Should -Be $Path
            "$($conversionError[0])" | Should -Be "Cannot resolve the path '$Path': $($script:hint)"
        }

        It 'Should write PathNotFound that explains the drive of the current location for the relative path <Path>' -ForEach @(
            @{ Path = 'IMG_0001.HEIC' }
            @{ Path = '.\*.HEIC' }
        ) {
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
            Push-Location -Path 'PsicScopeDrive:\'
            try
            {
                # 'PsicScopeDrive:\' on Windows, 'PsicScopeDrive:/' on Linux and macOS.
                $location = (Get-Location).Path
                $result = Convert-Image -Path $Path -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            finally
            {
                Pop-Location
            }

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Convert-Image'
            "$($conversionError[0])" | Should -Be "Cannot resolve the path '$Path', which is relative to the current location '$location': $($script:hint)"
        }

        It 'Should stop the call with one terminating InvalidDestinationPath error that explains the drive' {
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
            $errorCount = $global:Error.Count
            $caught = $null

            try
            {
                $null = Convert-Image -LiteralPath $script:source -Format Png -DestinationPath 'PsicScopeDrive:\out'
            }
            catch
            {
                $caught = $_
            }

            $caught.FullyQualifiedErrorId | Should -Be 'InvalidDestinationPath,Convert-Image'
            $caught.TargetObject | Should -Be 'PsicScopeDrive:\out'
            "$caught" | Should -Be "The destination path 'PsicScopeDrive:\out' is not valid: $($script:hint)"
            $global:Error.Count - $errorCount | Should -Be 1
            Join-Path -Path $script:tempDir.FullName -ChildPath 'out' | Should -Not -Exist
        }

        It 'Should resolve a relative -DestinationPath while the current location is on such a drive' {
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
            Push-Location -Path 'PsicScopeDrive:\'
            try
            {
                $result = Convert-Image -LiteralPath $script:source -Format Png -DestinationPath 'out'
            }
            finally
            {
                Pop-Location
            }

            $result.FullName | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'out/IMG_0001.png' | Convert-Path)
        }

        It 'Should explain a drive created at the top of a script run with &' {
            $scriptFile = Join-Path -Path $script:tempDir.FullName -ChildPath 'drive-script.ps1'
            Set-Content -LiteralPath $scriptFile -Value @(
                'param ($Root)'
                '$null = New-PSDrive -Name PsicScriptDrive -PSProvider FileSystem -Root $Root'
                '$conversionError = $null'
                '$null = Convert-Image -Path PsicScriptDrive:\IMG_0001.HEIC -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError'
                '$conversionError'
            )

            $conversionError = & $scriptFile -Root $script:tempDir.FullName

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Convert-Image'
            "$($conversionError[0])" | Should -BeLike "Cannot resolve the path 'PsicScriptDrive:\IMG_0001.HEIC': drive 'PsicScriptDrive' was created in a scope *"
        }

        It 'Should convert files piped from Get-ChildItem on such a drive' {
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName

            $result = Get-ChildItem -Path 'PsicScopeDrive:\' -Filter '*.HEIC' | Convert-Image -Format Png

            $result.FullName | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.png')
        }

        It 'Should use a global drive for -Path, -LiteralPath and -DestinationPath' {
            $null = New-PSDrive -Name 'PsicGlobalDrive' -PSProvider FileSystem -Root $script:tempDir.FullName -Scope Global
            try
            {
                $fromPath = Convert-Image -Path 'PsicGlobalDrive:\*.HEIC' -Format Png -DestinationPath 'PsicGlobalDrive:\out'
                $fromLiteralPath = Convert-Image -LiteralPath 'PsicGlobalDrive:\IMG_0001.HEIC' -Format Gif -DestinationPath 'PsicGlobalDrive:\out'
            }
            finally
            {
                Remove-PSDrive -Name 'PsicGlobalDrive' -Scope Global
            }

            $fromPath.FullName | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'out/IMG_0001.png' | Convert-Path)
            $fromLiteralPath.FullName | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'out/IMG_0001.gif' | Convert-Path)
        }

        It 'Should use a drive created by a script dot-sourced in the global scope' {
            $scriptFile = Join-Path -Path $script:tempDir.FullName -ChildPath 'drive-setup.ps1'
            Set-Content -LiteralPath $scriptFile -Value "`$null = New-PSDrive -Name PsicDotDrive -PSProvider FileSystem -Root '$($script:tempDir.FullName)'"

            # A script of a new runspace runs in its global scope, as a command typed at the prompt does.
            $prompt = [System.Management.Automation.PowerShell]::Create()
            try
            {
                $null = $prompt.AddScript("Import-Module -Name '$($script:manifestPath)'; . '$scriptFile'; Convert-Image -Path 'PsicDotDrive:\IMG_0001.HEIC' -Format Png")
                $result = $prompt.Invoke()
                $errors = @($prompt.Streams.Error)
            }
            finally
            {
                $prompt.Dispose()
            }

            $errors | Should -BeNullOrEmpty
            $result.FullName | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.png')
        }

        It 'Should name the provider of a drive of another provider instead of suggesting -Scope Global' {
            $null = New-PSDrive -Name 'PsicEnvDrive' -PSProvider Environment -Root ''

            $result = Convert-Image -Path 'PsicEnvDrive:\PATH' -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Convert-Image'
            "$($conversionError[0])" | Should -Be "Cannot resolve the path 'PsicEnvDrive:\PATH': drive 'PsicEnvDrive' belongs to the Environment provider. Only file system paths are supported."
        }
    }

    Context 'When the caller''s drive hides a global drive of the same name' {
        BeforeEach {
            # The global drive points to another folder with a file of the same name, which must not be read or written.
            $script:globalRoot = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'global')
            $script:localRoot = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'local')
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:globalRoot.FullName -ChildPath 'IMG_0001.HEIC')
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:localRoot.FullName -ChildPath 'IMG_0001.HEIC')
            $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $script:globalRoot.FullName -Scope Global
            $script:hint = "drive 'PsicShadowDrive' was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module), so the module would use the global drive of that name, whose root is '$($script:globalRoot.FullName)'. Give the drive a name that no global drive has, or use the file system path; the root of the drive is '$($script:localRoot.FullName)'."
        }

        AfterEach {
            Remove-PSDrive -Name 'PsicShadowDrive' -Scope Global
        }

        It 'Should write PathNotFound that explains the drive for <Parameter> <Path>' -ForEach @(
            @{ Parameter = 'Path'; Path = 'PsicShadowDrive:\IMG_0001.HEIC' }
            @{ Parameter = 'Path'; Path = 'PsicShadowDrive:\*.HEIC' }
            @{ Parameter = 'LiteralPath'; Path = 'PsicShadowDrive:\IMG_0001.HEIC' }
        ) {
            # This It block's drive hides the global one for the test, but not for the module.
            $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $script:localRoot.FullName
            $parameters = @{ $Parameter = $Path }
            $errorCount = $global:Error.Count

            $result = Convert-Image @parameters -Format Png -DestinationPath $script:tempDir.FullName -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $global:Error.Count - $errorCount | Should -Be 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Convert-Image'
            $conversionError[0].TargetObject | Should -Be $Path
            "$($conversionError[0])" | Should -Be "Cannot resolve the path '$Path': $($script:hint)"
        }

        It 'Should write PathNotFound that explains the drive of the current location for a relative path' {
            $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $script:localRoot.FullName
            Push-Location -Path 'PsicShadowDrive:\'
            try
            {
                $location = (Get-Location).Path
                $result = Convert-Image -Path 'IMG_0001.HEIC' -Format Png -DestinationPath $script:tempDir.FullName -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            finally
            {
                Pop-Location
            }

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            "$($conversionError[0])" | Should -Be "Cannot resolve the path 'IMG_0001.HEIC', which is relative to the current location '$location': $($script:hint)"
        }

        It 'Should stop the call with one terminating InvalidDestinationPath error and write nothing to the global drive' {
            $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $script:localRoot.FullName
            $source = Join-Path -Path $script:localRoot.FullName -ChildPath 'IMG_0001.HEIC'
            $caught = $null

            try
            {
                $null = Convert-Image -LiteralPath $source -Format Png -DestinationPath 'PsicShadowDrive:\out' -Force
            }
            catch
            {
                $caught = $_
            }

            $caught.FullyQualifiedErrorId | Should -Be 'InvalidDestinationPath,Convert-Image'
            "$caught" | Should -Be "The destination path 'PsicShadowDrive:\out' is not valid: $($script:hint)"
            Join-Path -Path $script:globalRoot.FullName -ChildPath 'out' | Should -Not -Exist
            Join-Path -Path $script:localRoot.FullName -ChildPath 'out' | Should -Not -Exist
        }

        It 'Should resolve a relative -DestinationPath on the caller''s drive' {
            $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $script:localRoot.FullName
            Push-Location -Path 'PsicShadowDrive:\'
            try
            {
                $result = Convert-Image -LiteralPath $script:source -Format Png -DestinationPath 'out'
            }
            finally
            {
                Pop-Location
            }

            $result.FullName | Should -Be (Join-Path -Path $script:localRoot.FullName -ChildPath 'out/IMG_0001.png' | Convert-Path)
        }

        It 'Should convert the caller''s files piped from Get-ChildItem' {
            $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $script:localRoot.FullName

            $result = Get-ChildItem -Path 'PsicShadowDrive:\' -Filter '*.HEIC' | Convert-Image -Format Png

            $result.FullName | Should -Be (Join-Path -Path $script:localRoot.FullName -ChildPath 'IMG_0001.png')
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

    Context 'When -Format is given in another casing' {
        It 'Should name the format as documented in the ShouldProcess message' {
            $output = Convert-Image -LiteralPath $script:source -Format 'webp' -Verbose 4>&1
            $verbose = @($output | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object -Process { "$_" })

            ($output | Where-Object -FilterScript { $_ -is [System.IO.FileInfo] }).Name | Should -BeExactly 'IMG_0001.webp'
            @($verbose | Where-Object -FilterScript { $_ -clike "*Convert to WebP '*" }) | Should -HaveCount 1
            @($verbose | Where-Object -FilterScript { $_ -clike '*webp output*' -or $_ -clike '*Convert to webp*' }) | Should -BeNullOrEmpty
        }

        It 'Should name the format as documented when -Quality is ignored' {
            $verbose = Convert-Image -LiteralPath $script:source -Format 'PNG' -Quality 50 -WhatIf -Verbose 4>&1 | ForEach-Object -Process { "$_" }

            $verbose -ccontains '-Quality is ignored for Png output, which is not a lossy format.' | Should -BeTrue
        }
    }

    Context 'When the caller sets preference variables in its own scope' {
        BeforeAll {
            # A user's function: -WhatIf sets $WhatIfPreference in its own scope, which a module function does not see by itself.
            function Invoke-UserFunction
            {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'A user function that only receives -WhatIf and -Confirm; whether the cmdlet it calls follows them is what the tests check.')]
                [CmdletBinding(SupportsShouldProcess = $true)]
                param ([System.Collections.Hashtable] $Parameters)

                Convert-Image @Parameters
            }
        }

        BeforeEach {
            $script:missing = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.heic'
            $script:target = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.png'
        }

        It 'Should write nothing when a user function is called with -WhatIf' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'whatif'

            $result = Invoke-UserFunction -Parameters @{ Path = $script:source; Format = 'Png'; DestinationPath = $destination } -WhatIf

            $result | Should -BeNullOrEmpty
            $destination | Should -Not -Exist
        }

        It 'Should not overwrite an existing file with -Force when a user function is called with -WhatIf' {
            Set-Content -Path $script:target -Value 'existing'

            $result = Invoke-UserFunction -Parameters @{ Path = $script:source; Format = 'Png'; Force = $true } -WhatIf

            $result | Should -BeNullOrEmpty
            Get-Content -Path $script:target | Should -Be 'existing'
        }

        It 'Should let -WhatIf:$false given to Convert-Image win over the caller''s -WhatIf' {
            $result = Invoke-UserFunction -Parameters @{ Path = $script:source; Format = 'Png'; WhatIf = $false } -WhatIf

            $result.FullName | Should -Be $script:target
        }

        It 'Should make the first failure terminating with $ErrorActionPreference = ''Stop'' in the calling script' {
            {
                $ErrorActionPreference = 'Stop'
                Convert-Image -Path $script:missing, $script:source -Format Png
            } | Should -Throw -ErrorId 'PathNotFound,Convert-Image'

            $script:target | Should -Not -Exist
        }

        It 'Should let an explicit -ErrorAction Continue win over the caller''s $ErrorActionPreference' {
            $outcome = & {
                $ErrorActionPreference = 'Stop'
                $written = Convert-Image -Path $script:missing, $script:source -Format Png -ErrorAction Continue -ErrorVariable conversionError 2>$null

                [PSCustomObject] @{
                    Written = $written
                    Errors  = @($conversionError)
                }
            }

            $outcome.Errors.FullyQualifiedErrorId | Should -Be 'PathNotFound,Convert-Image'
            $outcome.Written.FullName | Should -Be $script:target
        }

        Context 'When a confirmation cannot be asked' {
            BeforeAll {
                # Runs a script in a runspace without a user interface, where a confirmation prompt fails.
                function Invoke-WithoutUserInterface
                {
                    param ([System.String] $Script)

                    $powerShell = [System.Management.Automation.PowerShell]::Create()
                    try
                    {
                        $output = $powerShell.AddScript("Import-Module -Name '$($script:manifestPath)'; $Script").Invoke()

                        [PSCustomObject] @{
                            Output = @($output)
                            Errors = @($powerShell.Streams.Error)
                        }
                    }
                    finally
                    {
                        $powerShell.Dispose()
                    }
                }

                <#
                    Pester does not fall back to the real command when no -ParameterFilter matches, so this
                    default mock does what Invoke-ImageConverterMethod does, through its compiled helper.
                #>
                function Use-RealMethodInvoker
                {
                    InModuleScope -ModuleName $script:moduleName {
                        $null = Invoke-ImageConverterMethod -Type ([System.Object])
                    }

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
            }

            BeforeEach {
                $script:secondSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.HEIC'
                Copy-Item -LiteralPath $script:fixture -Destination $script:secondSource
                $script:conversion = "Convert-Image -LiteralPath '$($script:source)', '$($script:secondSource)' -Format Png"
            }

            It 'Should write one ConfirmationFailed error per file and convert nothing for <Case>' -ForEach @(
                @{ Case = '-Confirm'; Script = '<conversion> -Confirm' }
                @{ Case = 'a user function called with -Confirm'; Script = 'function Invoke-UserFunction { [CmdletBinding(SupportsShouldProcess = $true)] param () <conversion> }; Invoke-UserFunction -Confirm' }
                @{ Case = '$ConfirmPreference = ''Low'' in the calling script'; Script = '& { $ConfirmPreference = ''Low''; <conversion> }' }
            ) {
                $result = Invoke-WithoutUserInterface -Script $Script.Replace('<conversion>', $script:conversion)

                $result.Output | Should -BeNullOrEmpty
                $result.Errors | Should -HaveCount 2
                $result.Errors.FullyQualifiedErrorId | Sort-Object -Unique | Should -Be 'ConfirmationFailed,Convert-Image'
                $result.Errors.TargetObject | Should -Be @($script:source, $script:secondSource)
                $result.Errors[0].CategoryInfo.Category | Should -Be 'InvalidOperation'
                "$($result.Errors[0])" | Should -BeLike "Cannot ask whether to convert '$($script:source)': *"
                Get-ChildItem -Path $script:tempDir.FullName -Filter '*.png' | Should -BeNullOrEmpty
            }

            It 'Should report the exception of ShouldProcess as ConfirmationFailed in this session' {
                # The same path in-process: ShouldProcess fails the way it does in a host without a user interface.
                Use-RealMethodInvoker
                Mock -ModuleName $script:moduleName -CommandName Invoke-ImageConverterMethod -ParameterFilter { $Name -eq 'ShouldProcess' } -MockWith {
                    [PSCustomObject] @{ Result = $null; Exception = [System.Management.Automation.Host.HostException]::new('The host cannot prompt.'); Arguments = $ArgumentList }
                }

                $result = Convert-Image -LiteralPath $script:source, $script:secondSource -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

                $result | Should -BeNullOrEmpty
                $conversionError | Should -HaveCount 2
                $conversionError.FullyQualifiedErrorId | Sort-Object -Unique | Should -Be 'ConfirmationFailed,Convert-Image'
                "$($conversionError[0])" | Should -Be "Cannot ask whether to convert '$($script:source)': The host cannot prompt."
                Get-ChildItem -Path $script:tempDir.FullName -Filter '*.png' | Should -BeNullOrEmpty
            }

            It 'Should write no error record when the pipeline is stopped at the prompt' {
                # Ctrl+C at the prompt: the pipeline is stopping, so the next command call ends the cmdlet anyway.
                Use-RealMethodInvoker
                Mock -ModuleName $script:moduleName -CommandName Invoke-ImageConverterMethod -ParameterFilter { $Name -eq 'ShouldProcess' } -MockWith {
                    [PSCustomObject] @{ Result = $null; Exception = [System.Management.Automation.PipelineStoppedException]::new(); Arguments = $ArgumentList }
                }

                $result = Convert-Image -LiteralPath $script:source -Format Png -ErrorVariable conversionError

                $result | Should -BeNullOrEmpty
                $conversionError | Should -BeNullOrEmpty
                Get-ChildItem -Path $script:tempDir.FullName -Filter '*.png' | Should -BeNullOrEmpty
            }

            It 'Should let -Confirm:$false given to Convert-Image win over the caller''s $ConfirmPreference' {
                $result = Invoke-WithoutUserInterface -Script "& { `$ConfirmPreference = 'Low'; $($script:conversion) -Confirm:`$false }"

                $result.Errors | Should -BeNullOrEmpty
                $result.Output | Should -HaveCount 2
            }

            It 'Should report ConfirmationFailed in pwsh -NonInteractive' {
                $command = "Import-Module -Name '$script:manifestPath'; $($script:conversion) -Confirm -ErrorVariable conversionError 2>`$null; `$conversionError.Count; `$conversionError[0].FullyQualifiedErrorId"

                $output = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command $command

                $output | Should -Be @('2', 'ConfirmationFailed,Convert-Image')
                Get-ChildItem -Path $script:tempDir.FullName -Filter '*.png' | Should -BeNullOrEmpty
            }
        }

        It 'Should follow $VerbosePreference and $WarningPreference of the calling script' {
            $exifSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.png') -Format Png -Exif

            # Without the caller's values the EXIF warning would be shown and the verbose message not.
            $streams = & {
                $VerbosePreference = 'Continue'
                $WarningPreference = 'SilentlyContinue'
                Convert-Image -LiteralPath $exifSource.FullName -Format Tiff -Quality 50
            } 3>&1 4>&1

            "$($streams | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] })" | Should -Match 'Quality is ignored'
            $streams | Where-Object -FilterScript { $_ -is [System.Management.Automation.WarningRecord] } | Should -BeNullOrEmpty
            $streams | Where-Object -FilterScript { $_ -is [System.IO.FileInfo] } | Should -HaveCount 1
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

        It 'Should convert the files described by Get-ImageInfo' {
            $result = Get-ImageInfo -LiteralPath $script:bracketSource | Convert-Image -Format Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be 'IMG[1].png'
            (Get-ImageInfo -LiteralPath $result.FullName).Width | Should -Be 64
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

        It 'Should write InvalidWildcardPattern also when no file of that name exists' {
            $pattern = Join-Path -Path $script:tempDir.FullName -ChildPath 'zz[.heic'
            $errorCount = $global:Error.Count

            $null = Convert-Image -Path $pattern -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'InvalidWildcardPattern,Convert-Image'
            $conversionError[0].TargetObject | Should -Be $pattern
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

    Context 'When -DestinationPath cannot name a folder' {
        BeforeEach {
            foreach ($name in 'IMG_0002.HEIC', 'IMG_0003.HEIC')
            {
                Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath $name)
            }
            $script:pattern = Join-Path -Path $script:tempDir.FullName -ChildPath '*.HEIC'
            $script:file = Join-Path -Path $script:tempDir.FullName -ChildPath 'file.txt'
            Set-Content -Path $script:file -Value 'x'

            # A drive whose root is the test folder, for a path that climbs above the root.
            $null = New-PSDrive -Name 'PsicRoot' -PSProvider FileSystem -Root $script:tempDir.FullName -Scope Global

            # A junction (Windows) or symbolic link (Linux, macOS) whose target folder is gone.
            $script:danglingLink = Join-Path -Path $script:tempDir.FullName -ChildPath 'dangling'
            $linkTarget = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'gone')
            $linkType = 'SymbolicLink'
            if ($IsWindows)
            {
                $linkType = 'Junction'
            }
            $null = New-Item -ItemType $linkType -Path $script:danglingLink -Target $linkTarget.FullName
            Remove-Item -LiteralPath $linkTarget.FullName
        }

        AfterEach {
            Remove-PSDrive -Name 'PsicRoot' -Scope Global
        }

        It 'Should stop the call for 3 sources with one terminating <ErrorId> error for <Case>, WhatIf <WhatIf>' -ForEach @(
            @{ Case = 'a file'; ErrorId = 'DestinationNotDirectory'; Destination = 'file'; WhatIf = $false }
            @{ Case = 'a file'; ErrorId = 'DestinationNotDirectory'; Destination = 'file'; WhatIf = $true }
            @{ Case = 'a folder below a file'; ErrorId = 'DestinationNotDirectory'; Destination = 'below-file'; WhatIf = $false }
            @{ Case = 'a link whose target is gone'; ErrorId = 'DestinationNotDirectory'; Destination = 'dangling'; WhatIf = $false }
            @{ Case = 'a folder below a link whose target is gone'; ErrorId = 'DestinationNotDirectory'; Destination = 'below-dangling'; WhatIf = $true }
            @{ Case = 'a path of another provider'; ErrorId = 'UnsupportedProvider'; Destination = 'Env:\Pictures'; WhatIf = $false }
            @{ Case = 'the root of another provider'; ErrorId = 'UnsupportedProvider'; Destination = 'Function:\'; WhatIf = $true }
            @{ Case = 'an unknown provider'; ErrorId = 'InvalidDestinationPath'; Destination = 'NoSuchProvider::C:\out'; WhatIf = $false }
            @{ Case = 'an unknown drive'; ErrorId = 'InvalidDestinationPath'; Destination = 'PsicNoSuchDrive:\out'; WhatIf = $false }
            @{ Case = 'a drive-qualified path that climbs above the drive root'; ErrorId = 'InvalidDestinationPath'; Destination = 'PsicRoot:/../../x'; WhatIf = $false }
            @{ Case = 'a NUL character'; ErrorId = 'InvalidDestinationPath'; Destination = 'nul-character'; WhatIf = $false }
            @{ Case = 'white space only'; ErrorId = 'InvalidDestinationPath'; Destination = ' '; WhatIf = $false }
            @{ Case = 'a provider-qualified path without a folder'; ErrorId = 'InvalidDestinationPath'; Destination = 'Microsoft.PowerShell.Core\FileSystem::'; WhatIf = $true }
            @{ Case = 'a link that points to itself'; ErrorId = 'DestinationNotDirectory'; Destination = 'loop'; WhatIf = $true }
            @{ Case = 'a folder below a link that points to itself'; ErrorId = 'DestinationNotDirectory'; Destination = 'below-loop'; WhatIf = $false }
            if ($IsWindows)
            {
                @{ Case = 'a character Windows does not allow'; ErrorId = 'InvalidDestinationPath'; Destination = 'pipe-character'; WhatIf = $false }
                @{ Case = 'a colon in a folder below the root'; ErrorId = 'InvalidDestinationPath'; Destination = 'colon'; WhatIf = $false }
                @{ Case = 'a colon in a folder below the root'; ErrorId = 'InvalidDestinationPath'; Destination = 'colon'; WhatIf = $true }
            }
        ) {
            # A junction loop on Windows needs no privilege; Linux and macOS report a symbolic link loop as a file.
            $loop = Join-Path -Path $script:tempDir.FullName -ChildPath 'loop'
            if ($Destination -like '*loop')
            {
                if ($IsWindows)
                {
                    $null = cmd.exe /c mklink /J $loop $loop
                }
                else
                {
                    $null = [System.IO.File]::CreateSymbolicLink($loop, $loop)
                }
            }

            $destinationPath = switch ($Destination)
            {
                'file' { $script:file }
                'below-file' { Join-Path -Path $script:file -ChildPath 'sub' }
                'dangling' { $script:danglingLink }
                'below-dangling' { Join-Path -Path $script:danglingLink -ChildPath 'sub' }
                'loop' { $loop }
                'below-loop' { Join-Path -Path $loop -ChildPath 'sub' }
                'nul-character' { Join-Path -Path $script:tempDir.FullName -ChildPath "a`0b" }
                'pipe-character' { Join-Path -Path $script:tempDir.FullName -ChildPath 'a|b' }
                'colon' { Join-Path -Path $script:tempDir.FullName -ChildPath 'partial/x:stream' }
                default { $Destination }
            }
            $errorCount = $global:Error.Count
            $result = $null
            $caught = $null

            # No -ErrorAction Stop: a parameter error is terminating by itself.
            try
            {
                $result = Convert-Image -Path $script:pattern -Format Png -DestinationPath $destinationPath -WhatIf:$WhatIf -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            catch
            {
                $caught = $_
            }

            $caught.FullyQualifiedErrorId | Should -Be "$ErrorId,Convert-Image"
            $caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
            $caught.TargetObject | Should -Be $destinationPath
            $global:Error.Count - $errorCount | Should -Be 1
            $conversionError | Should -HaveCount 1
            # For a terminating error -ErrorVariable holds the exception; its ErrorRecord is a copy of the record.
            $conversionError[0] | Should -BeOfType [System.Management.Automation.CmdletInvocationException]
            $conversionError[0].ErrorRecord.FullyQualifiedErrorId | Should -Be $caught.FullyQualifiedErrorId
            $conversionError[0].ErrorRecord.TargetObject | Should -Be $destinationPath
            $result | Should -BeNullOrEmpty
            Get-ChildItem -Path $script:tempDir.FullName -Recurse -Force -Attributes !ReparsePoint | Where-Object -FilterScript { $_.Extension -ne '.HEIC' -and $_.Name -notin @('file.txt') } | Should -BeNullOrEmpty
            Get-Content -Path $script:file | Should -Be 'x'
        }

        It 'Should keep a relative path that climbs above the drive root at the root, as other cmdlets do' {
            Push-Location -LiteralPath 'PsicRoot:\'
            try
            {
                $result = Convert-Image -LiteralPath $script:source -Format Png -DestinationPath '../../climbed'
            }
            finally
            {
                Pop-Location
            }

            $result.FullName | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'climbed/IMG_0001.png')
        }

        It 'Should write ImageWriteFailed for each file when the destination folder cannot be created' -Skip:(-not $IsWindows) {
            # A folder that denies creating subfolders: the destination itself is valid, so the check in begin lets it pass.
            $locked = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'locked')
            $acl = Get-Acl -LiteralPath $locked.FullName
            $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new([System.Security.Principal.WindowsIdentity]::GetCurrent().User, 'CreateDirectories, CreateFiles', 'Deny'))
            Set-Acl -LiteralPath $locked.FullName -AclObject $acl
            try
            {
                $result = Convert-Image -Path $script:pattern -Format Png -DestinationPath (Join-Path -Path $locked.FullName -ChildPath 'out') -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            finally
            {
                $acl = Get-Acl -LiteralPath $locked.FullName
                $null = $acl.RemoveAccessRuleAll([System.Security.AccessControl.FileSystemAccessRule]::new([System.Security.Principal.WindowsIdentity]::GetCurrent().User, 'CreateDirectories', 'Deny'))
                Set-Acl -LiteralPath $locked.FullName -AclObject $acl
            }

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 3
            $conversionError.FullyQualifiedErrorId | Sort-Object -Unique | Should -Be 'ImageWriteFailed,Convert-Image'
        }

        It 'Should stop also when no file is piped in' {
            { @() | Convert-Image -Format Png -DestinationPath $script:file } | Should -Throw -ErrorId 'DestinationNotDirectory,Convert-Image'
        }

        It 'Should end only the statement, so a script goes on with the next one' {
            $command = "Import-Module -Name '$script:manifestPath'; Convert-Image -Path '$script:pattern' -Format Png -DestinationPath '$script:file' 2>`$null; 'next statement'"

            $output = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command $command

            $output | Should -Be 'next statement'
            Get-ChildItem -Path $script:tempDir.FullName -Filter '*.png' | Should -BeNullOrEmpty
        }
    }

    Context 'When the session defines another command named Convert-Image' {
        It 'Should make every wrapper call the module''s Convert-Image' {
            <#
                A separate process: a global function of that name replaces the module's exported entry,
                which cannot be put back without importing the module again.
            #>
            $command = @(
                "Import-Module -Name '$script:manifestPath'"
                "function global:Convert-Image { 'hijacked' }"
                "Set-Location -LiteralPath '$($script:tempDir.FullName)'"
                "(ConvertTo-Jpeg -LiteralPath IMG_0001.HEIC).Name"
                "(ConvertTo-Png -LiteralPath IMG_0001.HEIC).Name"
                "(ConvertTo-WebP -LiteralPath IMG_0001.HEIC).Name"
                "(ConvertTo-Avif -LiteralPath IMG_0001.HEIC).Name"
                "(ConvertTo-JpegXL -LiteralPath IMG_0001.HEIC).Name"
                "(ConvertFrom-Heic -LiteralPath IMG_0001.HEIC -Format Gif).Name"
                "Set-Alias -Name Convert-Image -Value Get-Date -Scope Global"
                "(ConvertFrom-Heic -LiteralPath IMG_0001.HEIC -Format Bmp).Name"
            ) -join '; '

            $output = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command $command

            $output | Should -Be @('IMG_0001.jpg', 'IMG_0001.png', 'IMG_0001.webp', 'IMG_0001.avif', 'IMG_0001.jxl', 'IMG_0001.gif', 'IMG_0001.bmp')
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

            $result = Convert-Image -LiteralPath $percentSource -Format Jpeg -ErrorVariable conversionError -WarningVariable conversionWarning

            $conversionError | Should -BeNullOrEmpty
            # A single-frame source cannot show whether the name was taken as a file sequence; the test with 3-frame sources named seq%03d.gif and a%x.gif does.
            $conversionWarning | Should -BeNullOrEmpty -Because 'a single-frame source that is read completely gets no frame or damage warning'
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

        It 'Should convert the colours through the CMYK profile for lossy Jxl output' {
            $expected = Get-DisplayedColor -Path $script:cmykSource.FullName -FromCmyk

            $result = Convert-Image -LiteralPath $script:cmykSource.FullName -Format Jxl

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

    Context 'When the source has a wide-gamut ICC profile' {
        BeforeAll {
            function Get-ColorProfileByte
            {
                param ([System.String] $Path)

                $image = [ImageMagick.MagickImage]::new($Path)
                try
                {
                    $colorProfile = $image.GetColorProfile()
                    if ($null -ne $colorProfile)
                    {
                        $colorProfile.ToByteArray()
                    }
                }
                finally
                {
                    $image.Dispose()
                }
            }

            $script:adobeRgb = [ImageMagick.ColorProfiles]::AdobeRGB1998.ToByteArray()
        }

        BeforeEach {
            <#
                Adobe RGB #6496C8 shows as about #4297CB; read as sRGB it would show as #6496C8, 34 levels
                more red. A colour without channels near 0 or 255: lossy Jxl moves such channels of
                saturated colours by 30 levels and more (encoder noise), far beyond the tolerance.
            #>
            $script:wideSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'wide.png') -Format Png -Color '#6496C8' -ColorProfile -Exif -Xmp
            $script:sourceColor = Get-ViewerColor -Path $script:wideSource.FullName
        }

        It 'Should show the colours of the source in <Format> output, StripMetadata <StripMetadata>' -ForEach @(
            foreach ($format in @('Jpeg', 'Png', 'WebP', 'Avif', 'Jxl', 'Tiff', 'Bmp', 'Gif'))
            {
                foreach ($strip in @($false, $true))
                {
                    @{ Format = $format; StripMetadata = $strip }
                }
            }
        ) {
            $result = Convert-Image -LiteralPath $script:wideSource.FullName -Format $Format -StripMetadata:$StripMetadata -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out') -WarningAction SilentlyContinue

            100 - $script:sourceColor[0] | Should -BeGreaterOrEqual 24 -Because 'the fixture must differ visibly from its raw values'
            $actual = Get-ViewerColor -Path $result.FullName
            foreach ($channel in 0..2)
            {
                [System.Math]::Abs($actual[$channel] - $script:sourceColor[$channel]) | Should -BeLessOrEqual 6 -Because "channel $channel shows $($actual[$channel]), the source shows $($script:sourceColor[$channel])"
            }
        }

        It 'Should store the ICC profile of the source in <Format> output, StripMetadata <StripMetadata>' -ForEach @(
            foreach ($format in @('Jpeg', 'Png', 'WebP', 'Avif', 'Tiff', 'Bmp', 'Gif'))
            {
                foreach ($strip in @($false, $true))
                {
                    @{ Format = $format; StripMetadata = $strip }
                }
            }
        ) {
            $result = Convert-Image -LiteralPath $script:wideSource.FullName -Format $Format -StripMetadata:$StripMetadata -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out') -WarningAction SilentlyContinue

            Get-ColorProfileByte -Path $result.FullName | Should -Be $script:adobeRgb
        }

        It 'Should store sRGB instead of the ICC profile in lossy Jxl output, StripMetadata <StripMetadata>' -ForEach @(
            @{ StripMetadata = $false }
            @{ StripMetadata = $true }
        ) {
            $result = Convert-Image -LiteralPath $script:wideSource.FullName -Format Jxl -StripMetadata:$StripMetadata

            $output = [ImageMagick.MagickImage]::new($result.FullName)
            try
            {
                # The JPEG XL decoder describes the sRGB colour encoding of the file with a generated profile.
                $output.GetColorProfile().ToByteArray() | Should -Not -Be $script:adobeRgb
                $output.GetAttribute('icc:description') | Should -Be 'sRGB'
                $color = $output.GetPixels().GetPixel(0, 0).ToColor()
                [System.Math]::Abs([System.Int32] $color.R - $script:sourceColor[0]) | Should -BeLessOrEqual 6 -Because 'the pixels themselves are sRGB'
            }
            finally
            {
                $output.Dispose()
            }
        }

        It 'Should keep the ICC profile and the pixels in lossless Jxl output (-Quality 100), StripMetadata <StripMetadata>' -ForEach @(
            @{ StripMetadata = $false }
            @{ StripMetadata = $true }
        ) {
            $result = Convert-Image -LiteralPath $script:wideSource.FullName -Format Jxl -Quality 100 -StripMetadata:$StripMetadata -Verbose 4>&1

            $file = $result | Where-Object -FilterScript { $_ -is [System.IO.FileInfo] }
            Get-ColorProfileByte -Path $file.FullName | Should -Be $script:adobeRgb
            $actual = Get-ViewerColor -Path $file.FullName
            $actual | Should -Be $script:sourceColor
            "$($result | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] })" | Should -Not -Match 'sRGB'
        }

        It 'Should report the conversion to sRGB for lossy Jxl in the verbose stream' {
            $verbose = Convert-Image -LiteralPath $script:wideSource.FullName -Format Jxl -Quality 75 -Verbose 4>&1 | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] }

            "$verbose" | Should -BeLike "*Converted the colours to sRGB, because lossy Jxl output stores no ICC colour profile: $($script:wideSource.FullName)*"
        }

        It 'Should not convert a source without ICC profile' {
            $verbose = Convert-Image -LiteralPath $script:source -Format Jxl -Verbose 4>&1 | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] }

            "$verbose" | Should -Not -Match 'sRGB'
        }

        It 'Should write <Format> output of a photo whose ICC profile is followed by bytes after its declared size, StripMetadata <StripMetadata>' -ForEach @(
            foreach ($format in @('Jpeg', 'Png', 'WebP', 'Avif', 'Tiff', 'Bmp', 'Gif'))
            {
                foreach ($strip in @($false, $true))
                {
                    @{ Format = $format; StripMetadata = $strip }
                }
            }
        ) {
            # Two zero bytes after the profile, as in Samsung Galaxy HEIC photos. Before, Png output failed with 'Incorrect data in iCCP'.
            $photo = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.jpg') -Color '#6496C8' -Exif
            $null = Add-TestJpegColorProfile -Path $photo.FullName -ColorProfile ([System.Byte[]] ($script:adobeRgb + [System.Byte[]]::new(2)))
            $photoColor = Get-ViewerColor -Path $photo.FullName

            $result = Convert-Image -LiteralPath $photo.FullName -Format $Format -StripMetadata:$StripMetadata -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out') -ErrorVariable conversionErrors -WarningAction SilentlyContinue

            $conversionErrors | Should -BeNullOrEmpty
            $result | Should -BeOfType [System.IO.FileInfo]
            (Get-TestStoredColorLayout -Path $result.FullName).ProfileData | Should -Be $script:adobeRgb
            $actual = Get-ViewerColor -Path $result.FullName
            foreach ($channel in 0..2)
            {
                [System.Math]::Abs($actual[$channel] - $photoColor[$channel]) | Should -BeLessOrEqual 6 -Because "channel $channel shows $($actual[$channel]), the source shows $($photoColor[$channel])"
            }
        }
    }

    Context 'When the source is grey with a grey ICC profile' {
        BeforeEach {
            # A greyscale JPEG as Photoshop exports it: one channel, grey 128 with a gamma 1.8 profile, shown as about 146.
            $script:greySource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'grey.jpg') -Color '#808080' -GrayColorProfile
            $script:greyColor = Get-ViewerColor -Path $script:greySource.FullName
        }

        It 'Should show the grey of the source and store no grey profile on RGB pixels in <Format> output, Quality <Quality>, StripMetadata <StripMetadata>' -ForEach @(
            foreach ($format in @('Jpeg', 'Png', 'WebP', 'Avif', 'Jxl', 'Tiff', 'Bmp', 'Gif'))
            {
                foreach ($strip in @($false, $true))
                {
                    @{ Format = $format; Quality = 90; StripMetadata = $strip }
                }
            }
            @{ Format = 'Jxl'; Quality = 100; StripMetadata = $false }
            @{ Format = 'Jxl'; Quality = 100; StripMetadata = $true }
        ) {
            $result = Convert-Image -LiteralPath $script:greySource.FullName -Format $Format -Quality $Quality -StripMetadata:$StripMetadata -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out') -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $script:greyColor[0] - 128 | Should -BeGreaterOrEqual 12 -Because 'the fixture must differ visibly from its raw values'
            if ($Format -ne 'Jxl')
            {
                # Read from the file structure: ImageMagick reports some grey files as sRGB. JPEG XL keeps grey as grey at Quality 100 (kGrey) and stores no profile below.
                $layout = Get-TestStoredColorLayout -Path $result.FullName
                if ($layout.ProfileSpace -eq 'GRAY')
                {
                    $layout.Channels | Should -Be 'Grey' -Because "a grey profile is valid only for grey pixels, and $Format output stores them as $($layout.Channels)"
                }
            }

            $actual = Get-ViewerColor -Path $result.FullName
            foreach ($channel in 0..2)
            {
                [System.Math]::Abs($actual[$channel] - $script:greyColor[$channel]) | Should -BeLessOrEqual 3 -Because "channel $channel shows $($actual[$channel]), the source shows $($script:greyColor[$channel])"
            }
        }

        It 'Should convert the grey to sRGB for <Format> output, which stores grey pixels as RGB' -ForEach @(
            @{ Format = 'WebP' }
            @{ Format = 'Avif' }
            @{ Format = 'Bmp' }
            @{ Format = 'Gif' }
        ) {
            $result = Convert-Image -LiteralPath $script:greySource.FullName -Format $Format -Verbose 4>&1

            $file = $result | Where-Object -FilterScript { $_ -is [System.IO.FileInfo] }
            "$($result | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] })" | Should -BeLike "*Converted the colours to sRGB, because $Format output stores grey pixels as RGB, for which a grey ICC colour profile is not valid: $($script:greySource.FullName)*"
            $layout = Get-TestStoredColorLayout -Path $file.FullName
            $layout.Channels | Should -Be 'RGB'
            $layout.ProfileSpace | Should -BeIn @('RGB', $null)
        }

        It 'Should keep the grey pixels and the grey profile in <Format> output' -ForEach @(
            @{ Format = 'Jpeg' }
            @{ Format = 'Png' }
            @{ Format = 'Tiff' }
        ) {
            $result = Convert-Image -LiteralPath $script:greySource.FullName -Format $Format -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out') -Verbose 4>&1

            $file = $result | Where-Object -FilterScript { $_ -is [System.IO.FileInfo] }
            "$($result | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] })" | Should -Not -Match 'sRGB'
            $layout = Get-TestStoredColorLayout -Path $file.FullName
            $layout.Channels | Should -Be 'Grey'
            $layout.ProfileSpace | Should -Be 'GRAY'
        }
    }

    Context 'When the source has transparent pixels' {
        BeforeAll {
            function Get-BlockColor
            {
                param ([System.String] $Path)

                $image = [ImageMagick.MagickImage]::new($Path)
                try
                {
                    foreach ($x in @(8, 24, 40))
                    {
                        $color = $image.GetPixels().GetPixel($x, 8).ToColor()
                        , @([System.Int32] $color.R, [System.Int32] $color.G, [System.Int32] $color.B, [System.Int32] $color.A)
                    }
                }
                finally
                {
                    $image.Dispose()
                }
            }
        }

        BeforeEach {
            # Blocks: transparent black, red with alpha 128, opaque blue.
            $script:transparentSource = New-TestTransparentImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'logo.png')
        }

        It 'Should flatten the transparent pixels onto white for Jpeg output' {
            $result = Convert-Image -LiteralPath $script:transparentSource.FullName -Format Jpeg -Quality 100

            $output = [ImageMagick.MagickImage]::new($result.FullName)
            try
            {
                $output.HasAlpha | Should -BeFalse
            }
            finally
            {
                $output.Dispose()
            }

            $expected = @(@(255, 255, 255), @(255, 128, 128), @(0, 0, 255))
            $blocks = Get-BlockColor -Path $result.FullName
            foreach ($block in 0..2)
            {
                foreach ($channel in 0..2)
                {
                    [System.Math]::Abs($blocks[$block][$channel] - $expected[$block][$channel]) | Should -BeLessOrEqual 4 -Because "block $block channel $channel is $($blocks[$block][$channel])"
                }
            }
        }

        It 'Should flatten a CMYK source with transparent pixels onto paper white for Jpeg output, with profile <WithProfile>' -ForEach @(
            @{ WithProfile = $true }
            @{ WithProfile = $false }
        ) {
            # A print cut-out: CMYK with alpha. Jpeg keeps CMYK, so white has to be C = M = Y = K = 0 there.
            $cmykSource = New-TestTransparentImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'cutout.tif') -Cmyk -WithoutColorProfile:(-not $WithProfile)

            $result = Convert-Image -LiteralPath $cmykSource.FullName -Format Jpeg -Quality 100

            $output = [ImageMagick.MagickImage]::new($result.FullName)
            try
            {
                $output.ColorSpace | Should -Be 'CMYK'
                $output.HasAlpha | Should -BeFalse
                # The colour a viewer shows: through the embedded profile, or SWOP for an untagged CMYK file.
                if ($null -ne $output.GetColorProfile())
                {
                    $null = $output.TransformColorSpace([ImageMagick.ColorProfiles]::SRGB)
                }
                else
                {
                    $null = $output.TransformColorSpace([ImageMagick.ColorProfiles]::USWebCoatedSWOP, [ImageMagick.ColorProfiles]::SRGB)
                }

                $transparent = $output.GetPixels().GetPixel(8, 8).ToColor()
                $half = $output.GetPixels().GetPixel(24, 8).ToColor()
                $opaque = $output.GetPixels().GetPixel(40, 8).ToColor()
            }
            finally
            {
                $output.Dispose()
            }

            foreach ($channel in @($transparent.R, $transparent.G, $transparent.B))
            {
                $channel | Should -BeGreaterOrEqual 250 -Because 'the transparent block is white'
            }
            # Red at alpha 128 on white is light red: lighter in G and B than the opaque blue block, R stays high.
            $half.R | Should -BeGreaterOrEqual 230
            $half.G | Should -BeGreaterOrEqual 100
            $half.B | Should -BeGreaterOrEqual 90
            $opaque.B | Should -BeGreaterThan $opaque.R -Because 'the opaque block stays blue'
        }

        It 'Should keep the colours and the alpha of a palette PNG with <ColorCount> colour(s) in Tiff output' -ForEach @(
            @{ ColorCount = 1; Depth = 1 }
            @{ ColorCount = 2; Depth = 2 }
            @{ ColorCount = 5; Depth = 4 }
        ) {
            $paletteSource = New-TestPaletteImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'logo.png') -ColorCount $ColorCount
            $sourceImage = [ImageMagick.MagickImage]::new($paletteSource.FullName)
            try
            {
                $sourceImage.Depth | Should -Be $Depth -Because 'the fixture must be a palette PNG of that bit depth'
            }
            finally
            {
                $sourceImage.Dispose()
            }

            $result = Convert-Image -LiteralPath $paletteSource.FullName -Format Tiff

            $output = [ImageMagick.MagickImage]::new($result.FullName)
            try
            {
                foreach ($y in @(8, 14))
                {
                    $color = $output.GetPixels().GetPixel(8, $y).ToColor()
                    $expected = @(200, 60, 60, $(if ($y -eq 8) { 255 } else { 128 }))
                    $actual = @([System.Int32] $color.R, [System.Int32] $color.G, [System.Int32] $color.B, [System.Int32] $color.A)
                    foreach ($channel in 0..3)
                    {
                        [System.Math]::Abs($actual[$channel] - $expected[$channel]) | Should -BeLessOrEqual 2 -Because "row $y channel $channel is $($actual[$channel])"
                    }
                }
            }
            finally
            {
                $output.Dispose()
            }
        }

        It 'Should keep the alpha channel in <Format> output' -ForEach @(
            @{ Format = 'Png'; HalfAlpha = 128 }
            @{ Format = 'WebP'; HalfAlpha = 128 }
            @{ Format = 'Avif'; HalfAlpha = 128 }
            @{ Format = 'Jxl'; HalfAlpha = 128 }
            @{ Format = 'Tiff'; HalfAlpha = 128 }
            @{ Format = 'Bmp'; HalfAlpha = 128 }
            # GIF has only fully transparent or opaque pixels.
            @{ Format = 'Gif'; HalfAlpha = 255 }
        ) {
            $result = Convert-Image -LiteralPath $script:transparentSource.FullName -Format $Format -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out')

            $blocks = Get-BlockColor -Path $result.FullName
            $blocks[0][3] | Should -BeLessOrEqual 2
            [System.Math]::Abs($blocks[1][3] - $HalfAlpha) | Should -BeLessOrEqual 2
            $blocks[1][0] | Should -BeGreaterOrEqual 250
            $blocks[2][3] | Should -Be 255
        }
    }

    Context 'When the source has several frames' {
        It 'Should warn and convert the first frame of a 3-frame <Format> source' -ForEach @(
            @{ Format = 'Gif'; Extension = '.gif' }
            @{ Format = 'WebP'; Extension = '.webp' }
            @{ Format = 'Tiff'; Extension = '.tif' }
        ) {
            $frames = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath "anim$Extension") -Format $Format -FrameCount 3
            $errorCount = $global:Error.Count

            $result = Convert-Image -LiteralPath $frames.FullName -Format Png -WarningAction SilentlyContinue -WarningVariable frameWarning -ErrorVariable frameError

            $? | Should -BeTrue
            $frameError | Should -BeNullOrEmpty
            $global:Error.Count - $errorCount | Should -Be 0 -Because 'counting the frames writes no error record'
            $frameWarning | Should -HaveCount 1
            "$($frameWarning[0])" | Should -Be "Only the first of 3 frames is converted: $($frames.FullName)"
            $output = [ImageMagick.MagickImageCollection]::new($result.FullName)
            try
            {
                $output | Should -HaveCount 1
                $color = $output[0].GetPixels().GetPixel(8, 8).ToColor()
                $color.R | Should -BeGreaterOrEqual 240 -Because 'the first frame is red'
                $color.G + $color.B | Should -BeLessOrEqual 16 -Because 'the first frame is red'
            }
            finally
            {
                $output.Dispose()
            }
        }

        It 'Should warn once per source' {
            $first = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'a.gif') -FrameCount 3
            $second = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'b[1].gif') -FrameCount 2

            $result = Convert-Image -LiteralPath $first.FullName, $second.FullName -Format WebP -WarningAction SilentlyContinue -WarningVariable frameWarning

            $result | Should -HaveCount 2
            @($frameWarning | ForEach-Object -Process { "$_" }) | Should -Be @(
                "Only the first of 3 frames is converted: $($first.FullName)"
                "Only the first of 2 frames is converted: $($second.FullName)"
            )
        }

        It 'Should count the frames of a source named <Name>, which ImageMagick would interpret' -ForEach @(
            @{ Name = 'seq%03d.gif' }
            @{ Name = 'a%x.gif' }
            @{ Name = 'scan[1]' }
        ) {
            $frames = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'frames.gif') -FrameCount 3
            $source = Join-Path -Path $script:tempDir.FullName -ChildPath $Name
            Move-Item -LiteralPath $frames.FullName -Destination $source

            $result = Convert-Image -LiteralPath $source -Format Png -WarningAction SilentlyContinue -WarningVariable frameWarning -ErrorVariable frameError

            $frameError | Should -BeNullOrEmpty
            $result | Should -HaveCount 1
            "$frameWarning" | Should -Be "Only the first of 3 frames is converted: $source"
        }

        It 'Should warn for a HEIC file with two images' {
            $source = Join-Path -Path $script:tempDir.FullName -ChildPath 'burst.heic'
            Copy-Item -LiteralPath (Join-Path -Path (Split-Path -Path $script:fixture -Parent) -ChildPath 'two-images.heic') -Destination $source

            $null = Convert-Image -LiteralPath $source -Format Jpeg -WarningAction SilentlyContinue -WarningVariable frameWarning

            "$frameWarning" | Should -Be "Only the first of 2 frames is converted: $source"
        }

        It 'Should not warn for <Name>' -ForEach @(
            @{ Name = 'sample.heic' }
            @{ Name = 'thumbnail.heic' }
        ) {
            $source = Join-Path -Path $script:tempDir.FullName -ChildPath $Name
            Copy-Item -LiteralPath (Join-Path -Path (Split-Path -Path $script:fixture -Parent) -ChildPath $Name) -Destination $source

            $result = Convert-Image -LiteralPath $source -Format Jpeg -WarningVariable frameWarning

            $result | Should -Not -BeNullOrEmpty
            $frameWarning | Should -BeNullOrEmpty
        }

        It 'Should not warn for a layered Photoshop file, whose first image is the merged picture' {
            $layers = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'layers.psd') -Format Psd -FrameCount 3

            $null = Convert-Image -LiteralPath $layers.FullName -Format Png -WarningVariable frameWarning

            $frameWarning | Should -BeNullOrEmpty
        }
    }

    Context 'When the source is damaged' {
        It 'Should warn once and still convert a JPEG cut off at 60 %' {
            $damaged = New-TestDamagedJpeg -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'cut.jpg') -Keep 0.6
            $errorCount = $global:Error.Count

            $result = Convert-Image -LiteralPath $damaged.FullName -Format Png -WarningAction SilentlyContinue -WarningVariable damageWarning -ErrorVariable damageError

            $? | Should -BeTrue
            $damageError | Should -BeNullOrEmpty
            # The warning handler runs inside Magick.NET, where -ErrorVariable and $? would not see an error it raised.
            $global:Error.Count - $errorCount | Should -Be 0
            $result.Name | Should -Be 'cut.png'
            $damageWarning | Should -HaveCount 1
            "$($damageWarning[0])" | Should -Be "The image may be damaged (Premature end of JPEG file; Corrupt JPEG data: premature end of data segment): $($damaged.FullName)"
        }

        It 'Should warn once for a JPEG that lacks only its end marker and write the pixels of the complete file' {
            # libjpeg reports a missing end marker like a cut file; a progressive JPEG cut at a scan boundary, whose pixels are degraded, reads the same way.
            $complete = New-TestDamagedJpeg -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'complete.jpg') -Keep 1
            $damaged = New-TestDamagedJpeg -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'noend.jpg') -WithoutEndMarker
            $expected = Convert-Image -LiteralPath $complete.FullName -Format Png -WarningVariable completeWarning
            $errorCount = $global:Error.Count

            $result = Convert-Image -LiteralPath $damaged.FullName -Format Png -WarningAction SilentlyContinue -WarningVariable damageWarning -ErrorVariable damageError

            $? | Should -BeTrue
            $damageError | Should -BeNullOrEmpty
            $global:Error.Count - $errorCount | Should -Be 0
            $completeWarning | Should -BeNullOrEmpty -Because 'the complete file is intact'
            $damageWarning | Should -HaveCount 1
            "$($damageWarning[0])" | Should -Be "The image may be damaged (Premature end of JPEG file): $($damaged.FullName)"
            $expectedImage = [ImageMagick.MagickImage]::new($expected.FullName)
            $actualImage = [ImageMagick.MagickImage]::new($result.FullName)
            try
            {
                $actualImage.Compare($expectedImage, [ImageMagick.ErrorMetric]::Absolute) | Should -Be 0 -Because 'the pixels are complete'
            }
            finally
            {
                $expectedImage.Dispose()
                $actualImage.Dispose()
            }
        }

        It 'Should warn about an animated GIF cut off after its first frame and convert that frame' {
            $damaged = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'cut.gif') -FrameCount 3 -Keep 0.8
            $errorCount = $global:Error.Count

            $result = Convert-Image -LiteralPath $damaged.FullName -Format Png -WarningAction SilentlyContinue -WarningVariable damageWarning -ErrorVariable damageError

            $? | Should -BeTrue
            $damageError | Should -BeNullOrEmpty
            $global:Error.Count - $errorCount | Should -Be 0
            $result.Name | Should -Be 'cut.png'
            $damageWarning | Should -HaveCount 1
            "$($damageWarning[0])" | Should -BeLike "The image may be damaged (*): $($damaged.FullName)"
        }

        It 'Should stop at the damage warning with -WarningAction Stop and write nothing' {
            $damaged = New-TestDamagedJpeg -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'cut.jpg') -Keep 0.6

            { Convert-Image -LiteralPath $damaged.FullName -Format Png -WarningAction Stop } | Should -Throw

            Join-Path -Path $script:tempDir.FullName -ChildPath 'cut.png' | Should -Not -Exist
            Get-ChildItem -Path $script:tempDir.FullName -Force -Filter '*.tmp' | Should -BeNullOrEmpty
        }

        It 'Should not warn for intact sources' {
            $jpeg = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.jpg') -Width 320 -Height 240 -Exif -ColorProfile
            $png = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'logo.png') -Format Png -ColorProfile

            $result = Convert-Image -LiteralPath $script:source, $jpeg.FullName, $png.FullName -Format WebP -WarningVariable damageWarning

            $result | Should -HaveCount 3
            $damageWarning | Should -BeNullOrEmpty
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
