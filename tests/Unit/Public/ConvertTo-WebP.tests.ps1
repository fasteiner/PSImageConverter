BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:fixture = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'ConvertTo-WebP' {
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

            (Get-Command -Name 'ConvertTo-WebP').Parameters.Keys | Sort-Object | Should -Be $expected
        }

        It 'Should accept the aliases PSPath and LP for -LiteralPath' {
            (Get-Command -Name 'ConvertTo-WebP').Parameters['LiteralPath'].Aliases | Should -Be @('PSPath', 'LP')
        }
    }

    Context 'When converting a file' {
        It 'Should write a WebP file with the extension .webp next to the source and return it' {
            $result = ConvertTo-WebP -Path $script:source

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.Name | Should -Be 'IMG_0001.webp'
            $result.DirectoryName | Should -Be $script:tempDir.FullName
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'WebP'
        }

        It 'Should read sources of other formats than HEIC' {
            $otherSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.jpg') -Format Jpeg

            $result = ConvertTo-WebP -Path $otherSource.FullName

            $result.Name | Should -Be 'photo.webp'
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'WebP'
        }

        It 'Should take the first positional argument as -Path with wildcards' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.HEIC')

            $result = ConvertTo-WebP (Join-Path -Path $script:tempDir.FullName -ChildPath '*.HEIC')

            $result.Name | Sort-Object | Should -Be @('IMG_0001.webp', 'IMG_0002.webp')
        }
    }

    Context 'When files are piped in' {
        It 'Should convert every file piped from Get-ChildItem and skip folders' {
            $null = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.jpg') -Format Jpeg
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'folder')

            $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertTo-WebP -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Sort-Object | Should -Be @('IMG_0001.webp', 'photo.webp')
        }

        It 'Should bind files piped from Get-ChildItem to -LiteralPath' {
            $bracketSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG[1].heic'
            Copy-Item -LiteralPath $script:fixture -Destination $bracketSource

            $result = Get-ChildItem -LiteralPath $bracketSource | ConvertTo-WebP -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be 'IMG[1].webp'
        }

        It 'Should accept pipeline input from strings' {
            $result = $script:source | ConvertTo-WebP

            $result.Name | Should -Be 'IMG_0001.webp'
        }
    }

    Context 'When the source is already a WebP file' {
        BeforeEach {
            $script:existing = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.webp') -Format WebP
            $script:existingHash = (Get-FileHash -LiteralPath $script:existing.FullName).Hash
        }

        It 'Should write a TargetIsSource error and keep the source, also with -Force' {
            $result = ConvertTo-WebP -Path $script:existing.FullName -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetIsSource,Convert-Image'
            $conversionError[0].TargetObject | Should -Be $script:existing.FullName
            (Get-FileHash -LiteralPath $script:existing.FullName).Hash | Should -Be $script:existingHash
        }

        It 'Should write a re-encoded copy into -DestinationPath' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'copy'

            $result = ConvertTo-WebP -Path $script:existing.FullName -Quality 50 -DestinationPath $destination

            $result.FullName | Should -Be (Join-Path -Path (Get-Item -LiteralPath $destination).FullName -ChildPath 'photo.webp')
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'WebP'
            (Get-FileHash -LiteralPath $script:existing.FullName).Hash | Should -Be $script:existingHash
        }
    }

    Context 'When two sources map to the same target' {
        It 'Should write a DuplicateTarget error for the second source of one piped call, also with -Force' {
            $null = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') -Format Jpeg

            $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertTo-WebP -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

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
            $result = ConvertTo-WebP -Path $script:missing, $script:source -ErrorAction SilentlyContinue
            $succeeded = $?

            $succeeded | Should -BeFalse
            $result.Name | Should -Be 'IMG_0001.webp'
        }

        It 'Should keep $? at $true when every file is converted' {
            $null = ConvertTo-WebP -Path $script:source
            $succeeded = $?

            $succeeded | Should -BeTrue
        }

        It 'Should hold exactly one error record per failed file in -ErrorVariable' {
            $broken = Join-Path -Path $script:tempDir.FullName -ChildPath 'broken.heic'
            Set-Content -Path $broken -Value 'not an image'

            $null = ConvertTo-WebP -Path $script:missing, $broken, $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 2
            $conversionError.FullyQualifiedErrorId | Should -Be @('PathNotFound,Convert-Image', 'ImageReadFailed,Convert-Image')
        }

        It 'Should stop at the first failure with -ErrorAction Stop' {
            { ConvertTo-WebP -Path $script:missing, $script:source -ErrorAction Stop } | Should -Throw -ErrorId 'PathNotFound,Convert-Image'

            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.webp' | Should -Not -Exist
        }
    }

    Context 'When using -WhatIf' {
        It 'Should neither write the file nor create the destination folder' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'whatif'

            $result = ConvertTo-WebP -Path $script:source -DestinationPath $destination -WhatIf

            $result | Should -BeNullOrEmpty
            $destination | Should -Not -Exist
            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.webp' | Should -Not -Exist
        }
    }

    Context 'When a quality is given' {
        It 'Should write a smaller file for a lower quality' {
            $high = ConvertTo-WebP -Path $script:source -Quality 100 -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'high')
            $low = ConvertTo-WebP -Path $script:source -Quality 10 -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'low')

            $low.Length | Should -BeLessThan $high.Length
        }
    }

    Context 'When the other parameters are passed on' {
        It 'Should remove the EXIF data with -StripMetadata' {
            $exifSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.jpg') -Format Jpeg -Exif

            $result = ConvertTo-WebP -Path $exifSource.FullName -StripMetadata

            (Get-ImageInfo -LiteralPath $result.FullName).HasExif | Should -BeFalse
        }

        It 'Should keep an existing target without -Force and overwrite it with -Force' {
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.webp'
            Set-Content -Path $target -Value 'existing'

            $null = ConvertTo-WebP -Path $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetExists,Convert-Image'
            Get-Content -Path $target | Should -Be 'existing'

            $result = ConvertTo-WebP -Path $script:source -Force
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'WebP'
        }
    }

    Context 'When the session has an alias named Convert-Image' {
        It 'Should still call the module''s Convert-Image' {
            # An alias wins over every function of the same name, in every scope.
            function global:Invoke-PsicHijack
            {
                param ([Parameter(ValueFromRemainingArguments = $true)] $Arguments)

                'hijacked'
            }
            Set-Alias -Name 'Convert-Image' -Value 'Invoke-PsicHijack' -Scope Global
            try
            {
                $result = ConvertTo-WebP -LiteralPath $script:source
            }
            finally
            {
                Remove-Item -LiteralPath 'Alias:\Convert-Image', 'Function:\Invoke-PsicHijack' -Force
            }

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.Name | Should -Be 'IMG_0001.webp'
        }
    }
}
