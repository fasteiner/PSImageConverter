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

Describe 'ConvertTo-Jpeg' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
        $script:source = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.HEIC'
        Copy-Item -Path $script:fixture -Destination $script:source
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'When looking at the parameters' {
        It 'Should have the parameters of Convert-Image without -Format' {
            $expected = (Get-Command -Name 'Convert-Image').Parameters.Keys | Where-Object -FilterScript { $_ -ne 'Format' } | Sort-Object

            (Get-Command -Name 'ConvertTo-Jpeg').Parameters.Keys | Sort-Object | Should -Be $expected
        }

        It 'Should accept the aliases PSPath and LP for -LiteralPath' {
            (Get-Command -Name 'ConvertTo-Jpeg').Parameters['LiteralPath'].Aliases | Should -Be @('PSPath', 'LP')
        }
    }

    Context 'When converting a file' {
        It 'Should write a JPEG file with the extension .jpg next to the source and return it' {
            $result = ConvertTo-Jpeg -Path $script:source

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.Name | Should -Be 'IMG_0001.jpg'
            $result.DirectoryName | Should -Be $script:tempDir.FullName
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Jpeg'
        }

        It 'Should read sources of other formats than HEIC' {
            $otherSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.png') -Format Png

            $result = ConvertTo-Jpeg -Path $otherSource.FullName

            $result.Name | Should -Be 'photo.jpg'
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Jpeg'
        }

        It 'Should take the first positional argument as -Path with wildcards' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.HEIC')

            $result = ConvertTo-Jpeg (Join-Path -Path $script:tempDir.FullName -ChildPath '*.HEIC')

            $result.Name | Sort-Object | Should -Be @('IMG_0001.jpg', 'IMG_0002.jpg')
        }
    }

    Context 'When files are piped in' {
        It 'Should convert every file piped from Get-ChildItem and skip folders' {
            $null = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.png') -Format Png
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'folder')

            $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertTo-Jpeg -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Sort-Object | Should -Be @('IMG_0001.jpg', 'photo.jpg')
        }

        It 'Should bind files piped from Get-ChildItem to -LiteralPath' {
            $bracketSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG[1].heic'
            Copy-Item -LiteralPath $script:fixture -Destination $bracketSource

            $result = Get-ChildItem -LiteralPath $bracketSource | ConvertTo-Jpeg -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be 'IMG[1].jpg'
        }

        It 'Should accept pipeline input from strings' {
            $result = $script:source | ConvertTo-Jpeg

            $result.Name | Should -Be 'IMG_0001.jpg'
        }
    }

    Context 'When the source is already a JPEG file' {
        BeforeEach {
            $script:existing = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.jpg') -Format Jpeg
            $script:existingHash = (Get-FileHash -LiteralPath $script:existing.FullName).Hash
        }

        It 'Should write a TargetIsSource error and keep the source, also with -Force' {
            $result = ConvertTo-Jpeg -Path $script:existing.FullName -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetIsSource,Convert-Image'
            $conversionError[0].TargetObject | Should -Be $script:existing.FullName
            (Get-FileHash -LiteralPath $script:existing.FullName).Hash | Should -Be $script:existingHash
        }

        It 'Should treat a .JPG source as the target .jpg on Windows and macOS' -Skip:$IsLinux {
            $upperCase = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'CAMERA.JPG')

            $null = ConvertTo-Jpeg -Path $upperCase.FullName -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetIsSource,Convert-Image'
            Get-ChildItem -Path $script:tempDir.FullName -Filter 'CAMERA.*' | Should -HaveCount 1
        }

        It 'Should write a re-encoded copy into -DestinationPath' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'small'

            $result = ConvertTo-Jpeg -Path $script:existing.FullName -Quality 50 -DestinationPath $destination

            $result.FullName | Should -Be (Join-Path -Path (Get-Item -LiteralPath $destination).FullName -ChildPath 'photo.jpg')
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Jpeg'
            (Get-FileHash -LiteralPath $script:existing.FullName).Hash | Should -Be $script:existingHash
        }
    }

    Context 'When two sources map to the same target' {
        It 'Should write a DuplicateTarget error for the second source of one piped call, also with -Force' {
            $null = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.png') -Format Png

            $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertTo-Jpeg -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -HaveCount 1
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'DuplicateTarget,Convert-Image'
        }
    }

    Context 'When a file fails' {
        BeforeEach {
            $script:missing = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.png'
        }

        It 'Should set $? to $false and continue with the next file' {
            $result = ConvertTo-Jpeg -Path $script:missing, $script:source -ErrorAction SilentlyContinue
            $succeeded = $?

            $succeeded | Should -BeFalse
            $result.Name | Should -Be 'IMG_0001.jpg'
        }

        It 'Should keep $? at $true when every file is converted' {
            $null = ConvertTo-Jpeg -Path $script:source
            $succeeded = $?

            $succeeded | Should -BeTrue
        }

        It 'Should hold exactly one error record per failed file in -ErrorVariable' {
            $broken = Join-Path -Path $script:tempDir.FullName -ChildPath 'broken.heic'
            Set-Content -Path $broken -Value 'not an image'

            $null = ConvertTo-Jpeg -Path $script:missing, $broken, $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 2
            $conversionError.FullyQualifiedErrorId | Should -Be @('PathNotFound,Convert-Image', 'ImageReadFailed,Convert-Image')
        }

        It 'Should stop at the first failure with -ErrorAction Stop' {
            { ConvertTo-Jpeg -Path $script:missing, $script:source -ErrorAction Stop } | Should -Throw -ErrorId 'PathNotFound,Convert-Image'

            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg' | Should -Not -Exist
        }

        It 'Should make pwsh -Command fail when checking $?' {
            $command = "Import-Module -Name '$script:manifestPath'; ConvertTo-Jpeg -Path '$script:missing' -ErrorAction SilentlyContinue; exit (!`$? ? 1 : 0)"

            & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command $command

            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'When common parameters name a variable' {
        It 'Should append each error once to an existing global variable with -ErrorVariable +name' {
            # A global variable is what the interactive prompt and pwsh -File / -Command scripts use.
            $global:PsicAppendErrors = [System.Collections.ArrayList]::new()
            try
            {
                $null = ConvertTo-Jpeg -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.png') -ErrorAction SilentlyContinue -ErrorVariable +PsicAppendErrors
                $null = ConvertTo-Jpeg -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'missing2.png') -ErrorAction SilentlyContinue -ErrorVariable +PsicAppendErrors

                $global:PsicAppendErrors | Should -HaveCount 2
            }
            finally
            {
                Remove-Variable -Name 'PsicAppendErrors' -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'Should append each written file once to an existing global variable with -OutVariable +name' {
            $global:PsicAppendOutput = [System.Collections.ArrayList]::new()
            try
            {
                $null = ConvertTo-Jpeg -Path $script:source -OutVariable +PsicAppendOutput

                $global:PsicAppendOutput | Should -HaveCount 1
            }
            finally
            {
                Remove-Variable -Name 'PsicAppendOutput' -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'Should set the -PipelineVariable to each written file' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.heic')
            $sources = Get-ChildItem -Path $script:tempDir.FullName -Filter 'IMG_*'

            $names = $sources | ConvertTo-Jpeg -PipelineVariable written | ForEach-Object -Process { $written.Name }

            $names | Should -Be @('IMG_0001.jpg', 'IMG_0002.jpg')
        }

        It 'Should accept a variable name that the cmdlet uses internally' {
            $result = ConvertTo-Jpeg -Path $script:source -OutVariable convertPipeline

            $result.Name | Should -Be 'IMG_0001.jpg'
            $convertPipeline.Name | Should -Be 'IMG_0001.jpg'
        }
    }

    Context 'When the output is piped into the next cmdlet' {
        It 'Should pass a file with wildcard characters in its name on unchanged' {
            $bracketSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'Trip [1].heic'
            Copy-Item -LiteralPath $script:fixture -Destination $bracketSource

            $result = ConvertTo-Jpeg -LiteralPath $bracketSource | ConvertTo-WebP -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be 'Trip [1].webp'
        }
    }

    Context 'When using -WhatIf' {
        It 'Should neither write the file nor create the destination folder' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'whatif'

            $result = ConvertTo-Jpeg -Path $script:source -DestinationPath $destination -WhatIf

            $result | Should -BeNullOrEmpty
            $destination | Should -Not -Exist
            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg' | Should -Not -Exist
        }
    }

    Context 'When a quality is given' {
        It 'Should write a smaller file for a lower quality' {
            $high = ConvertTo-Jpeg -Path $script:source -Quality 100 -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'high')
            $low = ConvertTo-Jpeg -Path $script:source -Quality 10 -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'low')

            $low.Length | Should -BeLessThan $high.Length
        }
    }

    Context 'When the other parameters are passed on' {
        It 'Should remove the EXIF data with -StripMetadata' {
            $exifSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.png') -Format Png -Exif

            $result = ConvertTo-Jpeg -Path $exifSource.FullName -StripMetadata

            (Get-ImageInfo -LiteralPath $result.FullName).HasExif | Should -BeFalse
        }

        It 'Should keep an existing target without -Force and overwrite it with -Force' {
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg'
            Set-Content -Path $target -Value 'existing'

            $null = ConvertTo-Jpeg -Path $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetExists,Convert-Image'
            Get-Content -Path $target | Should -Be 'existing'

            $result = ConvertTo-Jpeg -Path $script:source -Force
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Jpeg'
        }
    }
}
