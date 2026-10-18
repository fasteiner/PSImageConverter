BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:fixture = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'ConvertTo-Png' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
        $script:source = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.HEIC'
        Copy-Item -Path $script:fixture -Destination $script:source
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'When looking at the parameters' {
        It 'Should have the parameters of Convert-Image without -Format and -Quality' {
            $expected = (Get-Command -Name 'Convert-Image').Parameters.Keys | Where-Object -FilterScript { $_ -notin @('Format', 'Quality') } | Sort-Object

            (Get-Command -Name 'ConvertTo-Png').Parameters.Keys | Sort-Object | Should -Be $expected
        }

        It 'Should have no -Quality parameter, because PNG is lossless' {
            (Get-Command -Name 'ConvertTo-Png').Parameters.ContainsKey('Quality') | Should -BeFalse
        }

        It 'Should accept the aliases PSPath and LP for -LiteralPath' {
            (Get-Command -Name 'ConvertTo-Png').Parameters['LiteralPath'].Aliases | Should -Be @('PSPath', 'LP')
        }
    }

    Context 'When converting a file' {
        It 'Should write a PNG file with the extension .png next to the source and return it' {
            $result = ConvertTo-Png -Path $script:source

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.Name | Should -Be 'IMG_0001.png'
            $result.DirectoryName | Should -Be $script:tempDir.FullName
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Png'
        }

        It 'Should read sources of other formats than HEIC' {
            $otherSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.jpg') -Format Jpeg

            $result = ConvertTo-Png -Path $otherSource.FullName

            $result.Name | Should -Be 'photo.png'
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Png'
        }

        It 'Should take the first positional argument as -Path with wildcards' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.HEIC')

            $result = ConvertTo-Png (Join-Path -Path $script:tempDir.FullName -ChildPath '*.HEIC')

            $result.Name | Sort-Object | Should -Be @('IMG_0001.png', 'IMG_0002.png')
        }
    }

    Context 'When files are piped in' {
        It 'Should convert every file piped from Get-ChildItem and skip folders' {
            $null = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.jpg') -Format Jpeg
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'folder')

            $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertTo-Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Sort-Object | Should -Be @('IMG_0001.png', 'photo.png')
        }

        It 'Should bind files piped from Get-ChildItem to -LiteralPath' {
            $bracketSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG[1].heic'
            Copy-Item -LiteralPath $script:fixture -Destination $bracketSource

            $result = Get-ChildItem -LiteralPath $bracketSource | ConvertTo-Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be 'IMG[1].png'
        }

        It 'Should accept pipeline input from strings' {
            $result = $script:source | ConvertTo-Png

            $result.Name | Should -Be 'IMG_0001.png'
        }
    }

    Context 'When the source is already a PNG file' {
        BeforeEach {
            $script:existing = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.png') -Format Png
            $script:existingHash = (Get-FileHash -LiteralPath $script:existing.FullName).Hash
        }

        It 'Should write a TargetIsSource error and keep the source, also with -Force' {
            $result = ConvertTo-Png -Path $script:existing.FullName -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetIsSource,Convert-Image'
            $conversionError[0].TargetObject | Should -Be $script:existing.FullName
            (Get-FileHash -LiteralPath $script:existing.FullName).Hash | Should -Be $script:existingHash
        }

        It 'Should write a re-encoded copy into -DestinationPath' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'copy'

            $result = ConvertTo-Png -Path $script:existing.FullName -DestinationPath $destination

            $result.FullName | Should -Be (Join-Path -Path (Get-Item -LiteralPath $destination).FullName -ChildPath 'photo.png')
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Png'
            (Get-FileHash -LiteralPath $script:existing.FullName).Hash | Should -Be $script:existingHash
        }
    }

    Context 'When two sources map to the same target' {
        It 'Should write a DuplicateTarget error for the second source of one piped call, also with -Force' {
            $null = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') -Format Jpeg

            $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertTo-Png -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

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
            $result = ConvertTo-Png -Path $script:missing, $script:source -ErrorAction SilentlyContinue
            $succeeded = $?

            $succeeded | Should -BeFalse
            $result.Name | Should -Be 'IMG_0001.png'
        }

        It 'Should keep $? at $true when every file is converted' {
            $null = ConvertTo-Png -Path $script:source
            $succeeded = $?

            $succeeded | Should -BeTrue
        }

        It 'Should hold exactly one error record per failed file in -ErrorVariable' {
            $broken = Join-Path -Path $script:tempDir.FullName -ChildPath 'broken.heic'
            Set-Content -Path $broken -Value 'not an image'

            $null = ConvertTo-Png -Path $script:missing, $broken, $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 2
            $conversionError.FullyQualifiedErrorId | Should -Be @('PathNotFound,Convert-Image', 'ImageReadFailed,Convert-Image')
        }

        It 'Should stop at the first failure with -ErrorAction Stop' {
            { ConvertTo-Png -Path $script:missing, $script:source -ErrorAction Stop } | Should -Throw -ErrorId 'PathNotFound,Convert-Image'

            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.png' | Should -Not -Exist
        }
    }

    Context 'When using -WhatIf' {
        It 'Should neither write the file nor create the destination folder' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'whatif'

            $result = ConvertTo-Png -Path $script:source -DestinationPath $destination -WhatIf

            $result | Should -BeNullOrEmpty
            $destination | Should -Not -Exist
            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.png' | Should -Not -Exist
        }
    }

    Context 'When the other parameters are passed on' {
        It 'Should remove the EXIF data with -StripMetadata' {
            $exifSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.jpg') -Format Jpeg -Exif

            $result = ConvertTo-Png -Path $exifSource.FullName -StripMetadata

            (Get-ImageInfo -LiteralPath $result.FullName).HasExif | Should -BeFalse
        }

        It 'Should keep an existing target without -Force and overwrite it with -Force' {
            $target = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.png'
            Set-Content -Path $target -Value 'existing'

            $null = ConvertTo-Png -Path $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetExists,Convert-Image'
            Get-Content -Path $target | Should -Be 'existing'

            $result = ConvertTo-Png -Path $script:source -Force
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Png'
        }
    }

    Context 'When the session has an alias named Convert-Image' {
        It 'Should still call the module''s Convert-Image' {
            # An alias wins over every function of the same name, in every scope.
            function global:Invoke-PsicHijack
            {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Arguments', Justification = 'Takes every argument the wrapper passes to Convert-Image, so the call binds; the values do not matter.')]
                param ([Parameter(ValueFromRemainingArguments = $true)] $Arguments)

                'hijacked'
            }
            Set-Alias -Name 'Convert-Image' -Value 'Invoke-PsicHijack' -Scope Global
            try
            {
                $result = ConvertTo-Png -LiteralPath $script:source
            }
            finally
            {
                Remove-Item -LiteralPath 'Alias:\Convert-Image', 'Function:\Invoke-PsicHijack' -Force
            }

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.Name | Should -Be 'IMG_0001.png'
        }
    }

    Context 'When a photo with an RGB profile has only grey pixels' {
        It 'Should write a PNG whose Adobe RGB profile readers accept, StripMetadata <StripMetadata>' -ForEach @(
            @{ StripMetadata = $false }
            @{ StripMetadata = $true }
        ) {
            # A black-and-white photo tagged Adobe RGB; ImageMagick stores it as a one-channel JPEG with the profile.
            $source = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'mono.jpg') -Color '#808080' -ColorProfile

            $result = ConvertTo-Png -LiteralPath $source.FullName -StripMetadata:$StripMetadata

            $readWarnings = [System.Collections.Generic.List[System.String]]::new()
            $output = [ImageMagick.MagickImage]::new()
            try
            {
                $output.add_Warning([System.EventHandler[ImageMagick.WarningEventArgs]] { $readWarnings.Add($args[1].Message) }.GetNewClosure())
                $output.Read($result.FullName)

                $output.GetColorProfile().Description | Should -Be 'Adobe RGB (1998)'
                $readWarnings | Should -BeNullOrEmpty -Because 'libpng rejects an RGB profile in a greyscale PNG'
            }
            finally
            {
                $output.Dispose()
            }
        }
    }

    Context 'When a path uses a PSDrive that the caller created in its own scope' {
        BeforeEach {
            # The module resolves paths in its own session state, which sees only the global drives.
            $script:hint = "drive 'PsicScopeDrive' was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module). Create the drive with New-PSDrive -Scope Global, or use the file system path; the root of the drive is '$($script:tempDir.FullName)'."
        }

        It 'Should write PathNotFound of Convert-Image that explains the drive for <Case>' -ForEach @(
            @{ Case = '-Path'; Parameters = @{ Path = 'PsicScopeDrive:\IMG_0001.HEIC' }; Location = $null }
            @{ Case = '-LiteralPath'; Parameters = @{ LiteralPath = 'PsicScopeDrive:\IMG_0001.HEIC' }; Location = $null }
            @{ Case = 'a relative path'; Parameters = @{ Path = 'IMG_0001.HEIC' }; Location = 'PsicScopeDrive:\' }
        ) {
            # Without -Scope Global the drive exists in this It block's scope only, like a drive created in a function.
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
            $errorCount = $global:Error.Count
            if ($Location)
            {
                Push-Location -Path $Location
            }

            # 'PsicScopeDrive:\' on Windows, 'PsicScopeDrive:/' on Linux and macOS.
            $currentLocation = (Get-Location).Path
            try
            {
                $result = ConvertTo-Png @Parameters -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            finally
            {
                if ($Location)
                {
                    Pop-Location
                }
            }

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $global:Error.Count - $errorCount | Should -Be 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Convert-Image'
            $conversionError[0].TargetObject | Should -Be @($Parameters.Values)[0]
            $expected = "Cannot resolve the path '$(@($Parameters.Values)[0])': $($script:hint)"
            if ($Location)
            {
                $expected = "Cannot resolve the path '$(@($Parameters.Values)[0])', which is relative to the current location '$currentLocation': $($script:hint)"
            }
            "$($conversionError[0])" | Should -Be $expected

        }

        It 'Should stop the call with one terminating InvalidDestinationPath error of ConvertTo-Png that explains the drive' {
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
            $errorCount = $global:Error.Count
            $caught = $null

            try
            {
                $null = ConvertTo-Png -LiteralPath $script:source -DestinationPath 'PsicScopeDrive:\out'
            }
            catch
            {
                $caught = $_
            }

            $caught.FullyQualifiedErrorId | Should -Be 'InvalidDestinationPath,ConvertTo-Png'
            $caught.TargetObject | Should -Be 'PsicScopeDrive:\out'
            "$caught" | Should -Be "The destination path 'PsicScopeDrive:\out' is not valid: $($script:hint)"
            $global:Error.Count - $errorCount | Should -Be 1
        }

        It 'Should use a global drive for -Path and -DestinationPath' {
            $null = New-PSDrive -Name 'PsicGlobalDrive' -PSProvider FileSystem -Root $script:tempDir.FullName -Scope Global
            try
            {
                $result = ConvertTo-Png -Path 'PsicGlobalDrive:\IMG_0001.HEIC' -DestinationPath 'PsicGlobalDrive:\out'
            }
            finally
            {
                Remove-PSDrive -Name 'PsicGlobalDrive' -Scope Global
            }

            $result.DirectoryName | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'out' | Convert-Path)
        }

        It 'Should report a drive of the caller that hides a global drive of the same name for <Case>' -ForEach @(
            @{ Case = '-Path'; ErrorId = 'PathNotFound,Convert-Image'; Terminating = $false }
            @{ Case = '-DestinationPath'; ErrorId = 'InvalidDestinationPath,ConvertTo-Png'; Terminating = $true }
        ) {
            $globalRoot = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'global')
            Copy-Item -LiteralPath $script:source -Destination $globalRoot.FullName
            $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $globalRoot.FullName -Scope Global
            $caught = $null
            $result = $null
            try
            {
                # This It block's drive hides the global one for the test, but not for the module.
                $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
                $parameters = @{ Path = 'PsicShadowDrive:\IMG_0001.HEIC'; DestinationPath = 'PsicShadowDrive:\out' }
                if ($Case -eq '-Path')
                {
                    $parameters['DestinationPath'] = Join-Path -Path $script:tempDir.FullName -ChildPath 'out'
                }

                $result = ConvertTo-Png @parameters -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            catch
            {
                $caught = $_
            }
            finally
            {
                Remove-PSDrive -Name 'PsicShadowDrive' -Scope Global
            }

            $record = $caught
            if (-not $Terminating)
            {
                $record = $conversionError[0]
                $conversionError | Should -HaveCount 1
            }

            $result | Should -BeNullOrEmpty
            $record.FullyQualifiedErrorId | Should -Be $ErrorId
            "$record" | Should -BeLike "*drive 'PsicShadowDrive' was created in a scope that the PSImageConverter module cannot see (*), so the module would use the global drive of that name, whose root is '$($globalRoot.FullName)'.*"
            Join-Path -Path $globalRoot.FullName -ChildPath 'out' | Should -Not -Exist
        }
    }
}
