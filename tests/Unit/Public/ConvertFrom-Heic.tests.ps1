BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:fixture = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath
    $script:manifestPath = Join-Path -Path (Get-Module -Name $script:moduleName).ModuleBase -ChildPath "$($script:moduleName).psd1"
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'ConvertFrom-Heic' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
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
            $sourceInfo = Get-ImageInfo -Path $script:source
            $targetInfo = Get-ImageInfo -Path $result.FullName

            $targetInfo.Format | Should -Be 'Jpeg'
            $targetInfo.Width | Should -Be $sourceInfo.Width
            $targetInfo.Height | Should -Be $sourceInfo.Height
        }
    }

    Context 'When choosing another output format' {
        It 'Should write a <Format> file with extension <Extension>' -ForEach @(
            @{ Format = 'Png'; Extension = '.png' }
            @{ Format = 'WebP'; Extension = '.webp' }
            @{ Format = 'Avif'; Extension = '.avif' }
            @{ Format = 'Jxl'; Extension = '.jxl' }
            @{ Format = 'Tiff'; Extension = '.tif' }
            @{ Format = 'Bmp'; Extension = '.bmp' }
            @{ Format = 'Gif'; Extension = '.gif' }
        ) {
            $result = ConvertFrom-Heic -Path $script:source -Format $Format -Quality 75

            $result.Extension | Should -Be $Extension
            (Get-ImageInfo -Path $result.FullName).Format | Should -Be $Format
        }
    }

    Context 'When checking the source extension' {
        It 'Should accept the extension <Name>' -ForEach @(
            @{ Name = 'a.heic' }
            @{ Name = 'b.HEIF' }
            @{ Name = 'c.Hif' }
        ) {
            $path = Join-Path -Path $script:tempDir.FullName -ChildPath $Name
            Copy-Item -Path $script:fixture -Destination $path

            $result = ConvertFrom-Heic -LiteralPath $path -Format Png

            $result.Extension | Should -Be '.png'
        }

        It 'Should write a NotHeicFile error for a file with another extension' {
            $jpeg = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.jpg')

            $result = ConvertFrom-Heic -Path $jpeg.FullName -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'NotHeicFile,ConvertFrom-Heic'
            $conversionError[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $conversionError[0].TargetObject | Should -Be $jpeg.FullName
            "$($conversionError[0])" | Should -Match 'not a HEIC/HEIF image'
        }
    }

    Context 'When -Path contains wildcards' {
        It 'Should convert every matching file' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.HEIC')

            $result = ConvertFrom-Heic (Join-Path -Path $script:tempDir.FullName -ChildPath '*.HEIC') -Format Png

            $result.Name | Sort-Object | Should -Be @('IMG_0001.png', 'IMG_0002.png')
        }

        It 'Should write a PathNotFound error when the pattern matches nothing' {
            $null = ConvertFrom-Heic -Path (Join-Path -Path $script:tempDir.FullName -ChildPath '*.nomatch') -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,ConvertFrom-Heic'
        }
    }

    Context 'When file names contain wildcard characters' {
        BeforeEach {
            $script:bracketSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG[1].heic'
            Copy-Item -LiteralPath $script:fixture -Destination $script:bracketSource
        }

        It 'Should convert the file given by -LiteralPath without expanding it a second time' {
            $result = ConvertFrom-Heic -LiteralPath $script:bracketSource -Format Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be 'IMG[1].png'
        }

        It 'Should convert the file matched by a -Path pattern without expanding it a second time' {
            $result = ConvertFrom-Heic -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG`[1`].heic') -Format Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be 'IMG[1].png'
        }

        It 'Should bind files piped from Get-ChildItem to -LiteralPath' {
            $result = Get-ChildItem -LiteralPath $script:bracketSource | ConvertFrom-Heic -Format Png

            $result.Name | Should -Be 'IMG[1].png'
        }
    }

    Context 'When files are piped from Get-ChildItem' {
        It 'Should convert every piped file and skip folders' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.heif')
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'folder.heic')

            $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertFrom-Heic -Format Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Sort-Object | Should -Be @('IMG_0001.png', 'IMG_0002.png')
        }

        It 'Should accept pipeline input from strings' {
            $result = $script:source | ConvertFrom-Heic -Format Png

            $result.Name | Should -Be 'IMG_0001.png'
        }

        It 'Should skip the files it writes itself into a -DestinationPath inside the piped tree' {
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'sub')
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'sub/IMG_0002.heic')
            # Get-ChildItem enters the existing folder jpg after it has passed IMG_0001.HEIC on, so IMG_0001.jpg is listed.
            $destination = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'jpg')

            $result = Get-ChildItem -Path $script:tempDir.FullName -Recurse | ConvertFrom-Heic -DestinationPath $destination.FullName -ErrorVariable conversionError
            $succeeded = $?

            $conversionError | Should -BeNullOrEmpty
            $succeeded | Should -BeTrue
            $result.Name | Sort-Object | Should -Be @('IMG_0001.jpg', 'IMG_0002.jpg')
        }

        It 'Should convert every file of such a tree with -ErrorAction Stop' {
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'sub')
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'sub/IMG_0002.heic')
            $destination = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'jpg')

            $null = Get-ChildItem -Path $script:tempDir.FullName -Recurse | ConvertFrom-Heic -DestinationPath $destination.FullName -ErrorAction Stop

            Join-Path -Path $destination.FullName -ChildPath 'IMG_0002.jpg' | Should -Exist
        }

        It 'Should still write a NotHeicFile error for another file in the destination' {
            $destination = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'jpg')
            $null = New-TestImage -Path (Join-Path -Path $destination.FullName -ChildPath 'other.jpg')

            $null = Get-ChildItem -Path $script:tempDir.FullName -Recurse | ConvertFrom-Heic -DestinationPath $destination.FullName -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'NotHeicFile,ConvertFrom-Heic'
            $conversionError[0].TargetObject | Should -Be (Join-Path -Path $destination.FullName -ChildPath 'other.jpg')
        }

        It 'Should write a DuplicateTarget error for sources with the same base name, also with -Force' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heif')

            $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertFrom-Heic -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -HaveCount 1
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'DuplicateTarget,Convert-Image'
        }
    }

    Context 'When the target file already exists' {
        BeforeEach {
            Set-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') -Value 'existing'
        }

        It 'Should write a TargetExists error and keep the existing file without -Force' {
            $result = ConvertFrom-Heic -Path $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetExists,Convert-Image'
            "$($conversionError[0])" | Should -Match 'already exists'
            Get-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') | Should -Be 'existing'
        }

        It 'Should overwrite the file with -Force' {
            $result = ConvertFrom-Heic -Path $script:source -Force

            $result.Length | Should -BeGreaterThan 8
        }
    }

    Context 'When a file fails' {
        BeforeEach {
            $script:missing = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.heic'
            $script:textFile = Join-Path -Path $script:tempDir.FullName -ChildPath 'notes.txt'
            Set-Content -Path $script:textFile -Value 'not an image'
        }

        It 'Should hold exactly one error record per failed file in -ErrorVariable' {
            $broken = Join-Path -Path $script:tempDir.FullName -ChildPath 'broken.heic'
            Set-Content -Path $broken -Value 'not an image'

            $null = ConvertFrom-Heic -Path $script:missing, $script:textFile, $broken, $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 3
            $conversionError.FullyQualifiedErrorId | Should -Be @('PathNotFound,ConvertFrom-Heic', 'NotHeicFile,ConvertFrom-Heic', 'ImageReadFailed,Convert-Image')
        }

        It 'Should set $? to $false and continue with the next file' {
            $result = ConvertFrom-Heic -Path $script:missing, $script:source -ErrorAction SilentlyContinue
            $succeeded = $?

            $succeeded | Should -BeFalse
            $result.Name | Should -Be 'IMG_0001.jpg'
        }

        It 'Should set $? to $false for an error of Convert-Image' {
            Set-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') -Value 'existing'

            $null = ConvertFrom-Heic -Path $script:source -ErrorAction SilentlyContinue
            $succeeded = $?

            $succeeded | Should -BeFalse
        }

        It 'Should keep $? at $true when every file is converted' {
            $null = ConvertFrom-Heic -Path $script:source
            $succeeded = $?

            $succeeded | Should -BeTrue
        }

        It 'Should stop at the first failure with -ErrorAction Stop' {
            { ConvertFrom-Heic -Path $script:textFile, $script:source -ErrorAction Stop } | Should -Throw -ErrorId 'NotHeicFile,ConvertFrom-Heic'

            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg' | Should -Not -Exist
        }

        It 'Should stop at the first failure of Convert-Image with -ErrorAction Stop' {
            Set-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') -Value 'existing'
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.heic')

            { ConvertFrom-Heic -LiteralPath $script:source, (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.heic') -ErrorAction Stop } | Should -Throw -ErrorId 'TargetExists,Convert-Image'

            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.jpg' | Should -Not -Exist
        }

        It 'Should make pwsh -Command fail when checking $?' {
            $command = "Import-Module -Name '$script:manifestPath'; ConvertFrom-Heic -Path '$script:missing' -ErrorAction SilentlyContinue; exit (!`$? ? 1 : 0)"

            & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command $command

            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'When common parameters name a variable' {
        It 'Should append each error of Convert-Image once to an existing global variable with -ErrorVariable +name' {
            Set-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') -Value 'existing'
            $global:PsicAppendErrors = [System.Collections.ArrayList]::new()
            try
            {
                $null = ConvertFrom-Heic -Path $script:source -ErrorAction SilentlyContinue -ErrorVariable +PsicAppendErrors

                $global:PsicAppendErrors | Should -HaveCount 1
                $global:PsicAppendErrors[0].FullyQualifiedErrorId | Should -Be 'TargetExists,Convert-Image'
            }
            finally
            {
                Remove-Variable -Name 'PsicAppendErrors' -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'Should append each warning once to an existing global variable with -WarningVariable +name' {
            $exifSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.heic') -Exif
            $global:PsicAppendWarnings = [System.Collections.ArrayList]::new()
            try
            {
                $null = ConvertFrom-Heic -Path $exifSource.FullName -Format Gif -WarningAction SilentlyContinue -WarningVariable +PsicAppendWarnings

                $global:PsicAppendWarnings | Should -HaveCount 1
            }
            finally
            {
                Remove-Variable -Name 'PsicAppendWarnings' -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'Should set the -PipelineVariable to each written file' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.heic')

            $names = ConvertFrom-Heic -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_*') -PipelineVariable written | ForEach-Object -Process { $written.Name }

            $names | Should -Be @('IMG_0001.jpg', 'IMG_0002.jpg')
        }

        It 'Should accept a variable name that the cmdlet uses internally' {
            $result = ConvertFrom-Heic -Path $script:source -OutVariable convertPipeline

            $result.Name | Should -Be 'IMG_0001.jpg'
            $convertPipeline.Name | Should -Be 'IMG_0001.jpg'
        }
    }

    Context 'When using -WhatIf' {
        It 'Should neither write the file nor create the destination folder' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'whatif'

            $result = ConvertFrom-Heic -Path $script:source -DestinationPath $destination -WhatIf

            $result | Should -BeNullOrEmpty
            $destination | Should -Not -Exist
        }
    }

    Context 'When the parameters are passed on to Convert-Image' {
        It 'Should create the destination folder and write the file into it' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'out/jpg'

            $result = ConvertFrom-Heic -Path $script:source -DestinationPath $destination

            $result.DirectoryName | Should -Be (Get-Item -LiteralPath $destination).FullName
        }

        It 'Should apply the quality' {
            $high = ConvertFrom-Heic -Path $script:source -Quality 100 -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'high')
            $low = ConvertFrom-Heic -Path $script:source -Quality 10 -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'low')

            $low.Length | Should -BeLessThan $high.Length
        }

        It 'Should write a file without EXIF data with -StripMetadata' {
            $exifSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.heic') -Exif

            $result = ConvertFrom-Heic -Path $exifSource.FullName -StripMetadata

            (Get-ImageInfo -Path $result.FullName).HasExif | Should -BeFalse
        }

        It 'Should pass the EXIF warning on' {
            $exifSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.heic') -Exif

            $null = ConvertFrom-Heic -Path $exifSource.FullName -Format Tiff -WarningAction SilentlyContinue -WarningVariable conversionWarning

            $conversionWarning | Should -HaveCount 1
            "$($conversionWarning[0])" | Should -Match 'EXIF metadata'
        }
    }
}
