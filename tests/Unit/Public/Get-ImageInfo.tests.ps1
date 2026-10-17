BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:fixture = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageInfo' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'When reading a HEIC file' {
        BeforeAll {
            $script:result = Get-ImageInfo -Path $script:fixture
        }

        It 'Should return a PSImageConverter.ImageInfo object' {
            $script:result.PSObject.TypeNames | Should -Contain 'PSImageConverter.ImageInfo'
        }

        It 'Should report the HEIC format' {
            $script:result.Format | Should -BeIn @('Heic', 'Heif')
        }

        It 'Should report positive pixel dimensions' {
            $script:result.Width | Should -BeGreaterThan 0
            $script:result.Height | Should -BeGreaterThan 0
        }

        It 'Should report the full path and the file size' {
            $script:result.Path | Should -Be $script:fixture
            $script:result.FileSize | Should -Be (Get-Item -LiteralPath $script:fixture).Length
        }

        It 'Should report an upright orientation' {
            $script:result.Orientation | Should -Be 'TopLeft'
        }

        It 'Should report no EXIF data' {
            $script:result.HasExif | Should -BeFalse
            $script:result.CameraMake | Should -BeNullOrEmpty
            $script:result.DateTaken | Should -BeNullOrEmpty
        }
    }

    Context 'When the image has EXIF data' {
        It 'Should report camera, date taken and orientation' {
            $image = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.jpg') -Orientation 6

            $result = Get-ImageInfo -Path $image.FullName

            $result.HasExif | Should -BeTrue
            $result.CameraMake | Should -Be 'TestCam Inc.'
            $result.CameraModel | Should -Be 'Model X-100'
            $result.DateTaken | Should -Be ([System.DateTime]::new(2024, 5, 17, 13, 45, 30))
            $result.Orientation | Should -Be 'RightTop'
        }
    }

    Context 'When the image has no orientation tag' {
        It 'Should report TopLeft instead of Undefined for <Format>' -ForEach @(
            @{ Format = 'Jpeg' }
            @{ Format = 'Bmp' }
            @{ Format = 'Gif' }
        ) {
            $image = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath "plain.$Format") -Format $Format

            (Get-ImageInfo -Path $image.FullName).Orientation | Should -Be 'TopLeft'
        }
    }

    Context 'When the file is hidden' {
        It 'Should report the file size without an error' {
            $name = 'hidden.heic'
            if (-not $IsWindows)
            {
                $name = '.hidden.heic'
            }
            $hidden = Join-Path -Path $script:tempDir.FullName -ChildPath $name
            Copy-Item -Path $script:fixture -Destination $hidden
            if ($IsWindows)
            {
                [System.IO.File]::SetAttributes($hidden, [System.IO.FileAttributes]::Hidden)
            }

            $result = Get-ChildItem -Path $script:tempDir.FullName -Force | Get-ImageInfo -ErrorVariable infoError

            $infoError | Should -BeNullOrEmpty
            $result.FileSize | Should -Be (Get-Item -LiteralPath $script:fixture).Length
        }
    }

    Context 'When paths are given in different ways' {
        BeforeEach {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heic')
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG[2].heic')
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'folder')
        }

        It 'Should expand wildcards in -Path' {
            $result = Get-ImageInfo (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_*.heic')

            @($result).Count | Should -Be 1
        }

        It 'Should take -LiteralPath as written' {
            $result = Get-ImageInfo -LiteralPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG[2].heic')

            $result.Path | Should -BeLike '*IMG`[2`].heic'
        }

        It 'Should read a file whose name ends with a bracket expression' {
            $bracketFile = Join-Path -Path $script:tempDir.FullName -ChildPath 'scan[1]'
            Copy-Item -LiteralPath $script:fixture -Destination $bracketFile

            $result = Get-ImageInfo -LiteralPath $bracketFile -ErrorVariable infoError

            $infoError | Should -BeNullOrEmpty
            $result.Path | Should -Be $bracketFile
            $result.Width | Should -Be 64
        }

        It 'Should write one InvalidWildcardPattern error for a -Path that is not a valid pattern' {
            $oddFile = Join-Path -Path $script:tempDir.FullName -ChildPath 'a[.heic'
            Copy-Item -LiteralPath $script:fixture -Destination $oddFile

            $null = Get-ImageInfo -Path $oddFile -ErrorAction SilentlyContinue -ErrorVariable infoError

            $infoError | Should -HaveCount 1
            $infoError[0].FullyQualifiedErrorId | Should -Be 'InvalidWildcardPattern,Get-ImageInfo'
        }

        It 'Should return one object per piped file and skip folders' {
            $result = Get-ChildItem -Path $script:tempDir.FullName | Get-ImageInfo -ErrorVariable infoError

            $infoError | Should -BeNullOrEmpty
            @($result).Count | Should -Be 2
        }
    }

    Context 'When an item fails' {
        BeforeEach {
            $script:missing = Join-Path -Path $script:tempDir.FullName -ChildPath 'does-not-exist.heic'
            $script:textFile = Join-Path -Path $script:tempDir.FullName -ChildPath 'notes.heic'
            Set-Content -Path $script:textFile -Value 'not an image'
        }

        It 'Should write a PathNotFound error for a missing file' {
            $null = Get-ImageInfo -Path $script:missing -ErrorAction SilentlyContinue -ErrorVariable infoError

            $infoError | Should -HaveCount 1
            $infoError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Get-ImageInfo'
            $infoError[0].TargetObject | Should -Be $script:missing
        }

        It 'Should write one ImageReadFailed error with the Magick exception for a file that is not an image' {
            $null = Get-ImageInfo -Path $script:textFile -ErrorAction SilentlyContinue -ErrorVariable infoError

            $infoError | Should -HaveCount 1
            $infoError[0].FullyQualifiedErrorId | Should -Be 'ImageReadFailed,Get-ImageInfo'
            $infoError[0].CategoryInfo.Category | Should -Be 'InvalidData'
            $infoError[0].Exception | Should -BeOfType [ImageMagick.MagickException]
            "$($infoError[0])" | Should -BeLike "Cannot read image '$script:textFile': *"
        }

        It 'Should write an UnsupportedProvider error for a path of another provider' {
            $null = Get-ImageInfo -LiteralPath 'Env:\PATH' -ErrorAction SilentlyContinue -ErrorVariable infoError

            $infoError[0].FullyQualifiedErrorId | Should -Be 'UnsupportedProvider,Get-ImageInfo'
        }

        It 'Should set $? to $false and continue with the next file' {
            $result = Get-ImageInfo -Path $script:missing, $script:textFile, $script:fixture -ErrorAction SilentlyContinue
            $succeeded = $?

            $succeeded | Should -BeFalse
            $result.Path | Should -Be $script:fixture
        }

        It 'Should stop at the first failure with -ErrorAction Stop' {
            { Get-ImageInfo -Path $script:textFile, $script:fixture -ErrorAction Stop } | Should -Throw -ErrorId 'ImageReadFailed,Get-ImageInfo'
        }
    }
}
