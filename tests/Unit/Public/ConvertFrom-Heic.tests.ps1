BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:fixture = Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic'
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'ConvertFrom-Heic' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString()))
        $script:source = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.HEIC'
        Copy-Item -Path $script:fixture -Destination $script:source
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'When converting with default parameters' {
        It 'Should write a JPEG next to the source file and return it' {
            $result = ConvertFrom-Heic -Path $script:source

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.Name | Should -Be 'IMG_0001.jpg'
            $result.DirectoryName | Should -Be $script:tempDir.FullName
            $result.Exists | Should -BeTrue
        }

        It 'Should produce a JPEG with the same dimensions as the source' {
            $result = ConvertFrom-Heic -Path $script:source
            $sourceInfo = Get-HeicInfo -Path $script:source
            $targetInfo = Get-HeicInfo -Path $result.FullName

            $targetInfo.Format | Should -Be 'Jpeg'
            $targetInfo.Width | Should -Be $sourceInfo.Width
            $targetInfo.Height | Should -Be $sourceInfo.Height
        }
    }

    Context 'When choosing another output format' {
        It 'Should write a <Format> file with extension <Extension>' -ForEach @(
            @{ Format = 'Png'; Extension = '.png' }
            @{ Format = 'WebP'; Extension = '.webp' }
            @{ Format = 'Tiff'; Extension = '.tif' }
            @{ Format = 'Bmp'; Extension = '.bmp' }
        ) {
            $result = ConvertFrom-Heic -Path $script:source -Format $Format -Quality 75

            $result.Extension | Should -Be $Extension
            (Get-HeicInfo -Path $result.FullName).Format | Should -Be $Format
        }
    }

    Context 'When a destination folder is given' {
        It 'Should create the folder and write the file into it' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'out/jpg'

            $result = ConvertFrom-Heic -Path $script:source -DestinationPath $destination

            $result.DirectoryName | Should -Be (Get-Item -LiteralPath $destination).FullName
        }
    }

    Context 'When the target file already exists' {
        BeforeEach {
            Set-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') -Value 'existing'
        }

        It 'Should write an error and keep the existing file without -Force' {
            $result = ConvertFrom-Heic -Path $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -Not -BeNullOrEmpty
            "$conversionError" | Should -Match 'already exists'
            Get-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') | Should -Be 'existing'
        }

        It 'Should overwrite the file with -Force' {
            $result = ConvertFrom-Heic -Path $script:source -Force

            $result.Length | Should -BeGreaterThan 8
        }
    }

    Context 'When the input is invalid' {
        It 'Should write an error for a file that is not HEIC/HEIF' {
            $textFile = Join-Path -Path $script:tempDir.FullName -ChildPath 'notes.txt'
            Set-Content -Path $textFile -Value 'not an image'

            $null = ConvertFrom-Heic -Path $textFile -ErrorAction SilentlyContinue -ErrorVariable conversionError

            "$conversionError" | Should -Match 'not a HEIC/HEIF image'
        }

        It 'Should write an error for a missing file' {
            $null = ConvertFrom-Heic -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.heic') -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -Not -BeNullOrEmpty
        }

        It 'Should continue with the remaining files after an error' {
            $result = ConvertFrom-Heic -Path @((Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.heic'), $script:source) -ErrorAction SilentlyContinue

            $result.Name | Should -Be 'IMG_0001.jpg'
        }
    }

    Context 'When using -WhatIf' {
        It 'Should neither write the file nor create the destination folder' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'whatif'

            $result = ConvertFrom-Heic -Path $script:source -DestinationPath $destination -WhatIf

            $result | Should -BeNullOrEmpty
            Test-Path -Path $destination | Should -BeFalse
        }
    }

    Context 'When files are piped from Get-ChildItem' {
        It 'Should convert every piped file' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.heif')

            $result = Get-ChildItem -Path $script:tempDir.FullName -File | ConvertFrom-Heic -Format Png

            $result.Name | Sort-Object | Should -Be @('IMG_0001.png', 'IMG_0002.png')
        }
    }

    Context 'When metadata should be stripped' {
        It 'Should write a file without EXIF data' {
            $result = ConvertFrom-Heic -Path $script:source -StripMetadata

            (Get-HeicInfo -Path $result.FullName).HasExif | Should -BeFalse
        }
    }
}
