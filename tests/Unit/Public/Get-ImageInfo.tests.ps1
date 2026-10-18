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

        It 'Should write PathNotFound that explains a drive the caller created in its own scope for <Case>' -ForEach @(
            @{ Case = '-Path'; Parameters = @{ Path = 'PsicScopeDrive:\IMG_0001.heic' }; Location = $null }
            @{ Case = 'a -Path pattern'; Parameters = @{ Path = 'PsicScopeDrive:\*.heic' }; Location = $null }
            @{ Case = '-LiteralPath'; Parameters = @{ LiteralPath = 'PsicScopeDrive:\IMG_0001.heic' }; Location = $null }
            @{ Case = 'a relative path'; Parameters = @{ Path = 'IMG_0001.heic' }; Location = 'PsicScopeDrive:\' }
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
                $result = Get-ImageInfo @Parameters -ErrorAction SilentlyContinue -ErrorVariable infoError
            }
            finally
            {
                if ($Location)
                {
                    Pop-Location
                }
            }

            $result | Should -BeNullOrEmpty
            $infoError | Should -HaveCount 1
            $global:Error.Count - $errorCount | Should -Be 1
            $infoError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Get-ImageInfo'
            $infoError[0].TargetObject | Should -Be @($Parameters.Values)[0]
            $hint = "drive 'PsicScopeDrive' was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module). Create the drive with New-PSDrive -Scope Global, or use the file system path; the root of the drive is '$($script:tempDir.FullName)'."
            $expected = "Cannot resolve the path '$(@($Parameters.Values)[0])': $hint"
            if ($Location)
            {
                $expected = "Cannot resolve the path '$(@($Parameters.Values)[0])', which is relative to the current location '$currentLocation': $hint"
            }

            "$($infoError[0])" | Should -Be $expected
        }

        It 'Should read a file on a global drive' {
            $null = New-PSDrive -Name 'PsicGlobalDrive' -PSProvider FileSystem -Root $script:tempDir.FullName -Scope Global
            try
            {
                $result = Get-ImageInfo -Path 'PsicGlobalDrive:\IMG_0*.heic'
            }
            finally
            {
                Remove-PSDrive -Name 'PsicGlobalDrive' -Scope Global
            }

            $result.Path | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heic')
        }

        It 'Should not read the files of a global drive that a drive of the caller hides' {
            $globalRoot = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'global')
            Copy-Item -LiteralPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heic') -Destination $globalRoot.FullName
            $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $globalRoot.FullName -Scope Global
            try
            {
                # This It block's drive hides the global one for the test, but not for the module.
                $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
                $errorCount = $global:Error.Count

                $result = Get-ImageInfo -Path 'PsicShadowDrive:\IMG_0001.heic' -ErrorAction SilentlyContinue -ErrorVariable infoError
            }
            finally
            {
                Remove-PSDrive -Name 'PsicShadowDrive' -Scope Global
            }

            $result | Should -BeNullOrEmpty
            $infoError | Should -HaveCount 1
            $global:Error.Count - $errorCount | Should -Be 1
            $infoError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,Get-ImageInfo'
            "$($infoError[0])" | Should -BeLike "Cannot resolve the path 'PsicShadowDrive:\IMG_0001.heic': drive 'PsicShadowDrive' was created in a scope *, so the module would use the global drive of that name, whose root is '$($globalRoot.FullName)'. *"
        }

        It 'Should describe a file named by overlapping patterns once' {
            $output = Get-ImageInfo -Path (Join-Path -Path $script:tempDir.FullName -ChildPath '*.heic'), (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_*') -Verbose 4>&1

            $result = @($output | Where-Object -FilterScript { $_.PSObject.TypeNames -contains 'PSImageConverter.ImageInfo' })
            $result.Path | Sort-Object | Should -Be (@((Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heic'), (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG[2].heic')) | Sort-Object)
            "$($output | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] })" | Should -Match 'already given earlier'
        }
    }

    Context 'When the objects are piped into the next cmdlet' {
        BeforeEach {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heic')
            # Trip[1] as a wildcard pattern matches Trip1, which must not be converted in its place.
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'Trip[1].heic')
            $null = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'Trip1.heic') -Width 8 -Height 8
        }

        It 'Should carry the provider-qualified path in PSPath' {
            $result = Get-ImageInfo -LiteralPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heic')

            $result.PSPath | Should -Be (Get-Item -LiteralPath $result.Path).PSPath
        }

        It 'Should convert the files that a filter on its output passes, also a name with [ ]' {
            $result = Get-ImageInfo -Path (Join-Path -Path $script:tempDir.FullName -ChildPath '*.heic') | Where-Object -Property Width -GT 10 | ConvertTo-Jpeg -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Sort-Object | Should -Be @('IMG_0001.jpg', 'Trip[1].jpg')
            Join-Path -Path $script:tempDir.FullName -ChildPath 'Trip1.jpg' | Should -Not -Exist
            (Get-ImageInfo -LiteralPath $result[0].FullName).Format | Should -Be 'Jpeg'
        }

        It 'Should bind to -LiteralPath of Get-ImageInfo itself' {
            $result = Get-ImageInfo -LiteralPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'Trip[1].heic') | Get-ImageInfo -ErrorVariable infoError

            $infoError | Should -BeNullOrEmpty
            $result.Width | Should -Be 64
        }

        It 'Should not show PSPath in the default view of <View>' -ForEach @(
            @{ View = 'Out-String' }
            @{ View = 'Format-List' }
            @{ View = 'Format-Table' }
        ) {
            $result = Get-ImageInfo -LiteralPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heic')

            $text = switch ($View)
            {
                'Out-String' { $result | Out-String -Width 400 }
                'Format-List' { $result | Format-List | Out-String -Width 400 }
                'Format-Table' { $result | Format-Table | Out-String -Width 400 }
            }

            $text | Should -Not -Match 'PSPath'
            foreach ($property in 'Path', 'Format', 'Width', 'Height', 'Orientation', 'CameraMake', 'CameraModel', 'DateTaken', 'HasExif', 'FileSize')
            {
                $text | Should -Match "\b$property\b"
            }
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

        It 'Should stop at the first failure with $ErrorActionPreference = ''Stop'' in the calling script' {
            $script:described = $null

            {
                $ErrorActionPreference = 'Stop'
                $script:described = Get-ImageInfo -Path $script:missing, $script:fixture
            } | Should -Throw -ErrorId 'PathNotFound,Get-ImageInfo'

            $script:described | Should -BeNullOrEmpty
        }

        It 'Should say that a wildcard pattern matches no file' {
            $null = Get-ImageInfo -Path (Join-Path -Path $script:tempDir.FullName -ChildPath '*.nomatch') -ErrorAction SilentlyContinue -ErrorVariable infoError

            "$($infoError[0])" | Should -BeLike 'No file matches the pattern *'
        }

        It 'Should write InvalidWildcardPattern for a -Path that is not a valid pattern, also when no file of that name exists' {
            $null = Get-ImageInfo -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'zz[.heic') -ErrorAction SilentlyContinue -ErrorVariable infoError

            $infoError | Should -HaveCount 1
            $infoError[0].FullyQualifiedErrorId | Should -Be 'InvalidWildcardPattern,Get-ImageInfo'
        }

        It 'Should write one UnsupportedProvider error for a pattern that matches several items of another provider' {
            $env:PSIC_INFO_A = 'a'
            $env:PSIC_INFO_B = 'b'
            try
            {
                $null = Get-ImageInfo -Path 'Env:\PSIC_INFO_*' -ErrorAction SilentlyContinue -ErrorVariable infoError
            }
            finally
            {
                Remove-Item -Path 'Env:\PSIC_INFO_A', 'Env:\PSIC_INFO_B'
            }

            $infoError | Should -HaveCount 1
            $infoError[0].FullyQualifiedErrorId | Should -Be 'UnsupportedProvider,Get-ImageInfo'
            $infoError[0].TargetObject | Should -Be 'Env:\PSIC_INFO_*'
        }
    }

    Context 'When the image is damaged' {
        It 'Should warn once and still describe a JPEG cut off at 60 %' {
            $damaged = New-TestDamagedJpeg -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'cut.jpg') -Keep 0.6
            $errorCount = $global:Error.Count

            $result = Get-ImageInfo -LiteralPath $damaged.FullName -WarningAction SilentlyContinue -WarningVariable infoWarning -ErrorVariable infoError

            $? | Should -BeTrue
            $infoError | Should -BeNullOrEmpty
            # The warning handler runs inside Magick.NET, where -ErrorVariable and $? would not see an error it raised.
            $global:Error.Count - $errorCount | Should -Be 0
            $result.Width | Should -Be 320
            $infoWarning | Should -HaveCount 1
            "$($infoWarning[0])" | Should -Be "The image may be damaged (Premature end of JPEG file; Corrupt JPEG data: premature end of data segment): $($damaged.FullName)"
        }

        It 'Should warn once for a JPEG that lacks only its end marker' {
            $damaged = New-TestDamagedJpeg -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'noend.jpg') -WithoutEndMarker
            $errorCount = $global:Error.Count

            $result = Get-ImageInfo -LiteralPath $damaged.FullName -WarningAction SilentlyContinue -WarningVariable infoWarning -ErrorVariable infoError

            $? | Should -BeTrue
            $infoError | Should -BeNullOrEmpty
            $global:Error.Count - $errorCount | Should -Be 0
            $result.Width | Should -Be 320
            $infoWarning | Should -HaveCount 1
            "$($infoWarning[0])" | Should -Be "The image may be damaged (Premature end of JPEG file): $($damaged.FullName)"
        }

        It 'Should warn about an animated GIF cut off after its first frame and describe that frame' {
            $damaged = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'cut.gif') -FrameCount 3 -Keep 0.8
            $errorCount = $global:Error.Count

            $result = Get-ImageInfo -LiteralPath $damaged.FullName -WarningAction SilentlyContinue -WarningVariable infoWarning -ErrorVariable infoError

            $infoError | Should -BeNullOrEmpty
            $global:Error.Count - $errorCount | Should -Be 0
            $result.Width | Should -Be 16
            $infoWarning | Should -HaveCount 1
            "$($infoWarning[0])" | Should -BeLike "The image may be damaged (*): $($damaged.FullName)"
        }

        It 'Should not warn about the frames of an intact animated GIF' {
            $frames = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'anim.gif') -FrameCount 3

            $null = Get-ImageInfo -LiteralPath $frames.FullName -WarningVariable infoWarning

            $infoWarning | Should -BeNullOrEmpty
        }

        It 'Should dispose the image when the damage warning stops the call' {
            $outcome = InModuleScope -ModuleName $script:moduleName -Parameters @{ SourcePath = $script:fixture } {
                $script:readImage = [ImageMagick.MagickImage]::new($SourcePath)
                Mock -CommandName Read-ImageConverterImage -MockWith {
                    [PSCustomObject] @{
                        Result     = $script:readImage
                        Exception  = $null
                        Warnings   = @([ImageMagick.MagickCorruptImageWarningException]::new('Premature end of JPEG file'))
                        FrameCount = 1
                    }
                }

                $caught = $null
                $result = $null
                try
                {
                    $result = Get-ImageInfo -LiteralPath $SourcePath -WarningAction Stop
                }
                catch
                {
                    $caught = $_
                }

                [PSCustomObject] @{
                    Caught = $caught
                    Result = $result
                    Image  = $script:readImage
                }
            }

            $outcome.Caught.Exception | Should -BeOfType [System.Management.Automation.ActionPreferenceStopException]
            $outcome.Result | Should -BeNullOrEmpty
            { $null = $outcome.Image.ToByteArray([ImageMagick.MagickFormat]::Png) } | Should -Throw -ExpectedMessage '*disposed object*'
        }

        It 'Should not warn for intact images' {
            $jpeg = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.jpg') -Width 320 -Height 240 -Exif -ColorProfile
            $heic = Join-Path -Path (Split-Path -Path $script:fixture -Parent) -ChildPath 'thumbnail.heic'

            $result = Get-ImageInfo -LiteralPath $script:fixture, $heic, $jpeg.FullName -WarningVariable infoWarning

            $result | Should -HaveCount 3
            $infoWarning | Should -BeNullOrEmpty
        }
    }
}
