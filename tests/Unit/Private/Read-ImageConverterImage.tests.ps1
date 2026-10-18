BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:fixture = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath
    $script:assets = Split-Path -Path $script:fixture -Parent
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')

    function Read-Image
    {
        param ([System.String] $Path, [System.Management.Automation.SwitchParameter] $CountFrames)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ ImagePath = $Path; CountFrames = $CountFrames } {
            Read-ImageConverterImage -Path $ImagePath -CountFrames:$CountFrames
        }
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Read-ImageConverterImage' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should read the image <Name>' -ForEach @(
        @{ Name = 'IMG_0001.heic' }
        @{ Name = 'scan[1]' }
        @{ Name = 'page.heic[2]' }
    ) {
        $path = Join-Path -Path $script:tempDir.FullName -ChildPath $Name
        Copy-Item -LiteralPath $script:fixture -Destination $path

        $read = Read-Image -Path $path

        try
        {
            $read.Exception | Should -BeNullOrEmpty
            $read.Result | Should -BeOfType [ImageMagick.MagickImage]
            $read.Result.Width | Should -Be 64
            $read.Warnings | Should -BeNullOrEmpty
            $read.FrameCount | Should -BeNullOrEmpty
        }
        finally
        {
            $read.Result.Dispose()
        }
    }

    It 'Should return the exception for a file that is not an image: <Name>' -ForEach @(
        @{ Name = 'notes.heic' }
        @{ Name = 'notes[1]' }
    ) {
        $path = Join-Path -Path $script:tempDir.FullName -ChildPath $Name
        Set-Content -LiteralPath $path -Value 'not an image'

        $read = Read-Image -Path $path -CountFrames

        $read.Result | Should -BeNullOrEmpty
        $read.Exception | Should -BeOfType [ImageMagick.MagickException]
        $read.FrameCount | Should -BeNullOrEmpty
    }

    It 'Should return the exception when a file read from a stream cannot be opened' {
        $read = Read-Image -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'missing[1]')

        $read.Result | Should -BeNullOrEmpty
        $read.Exception | Should -BeOfType [System.IO.FileNotFoundException]
        $read.Warnings | Should -BeNullOrEmpty
    }

    Context 'When the file is damaged' {
        It 'Should return the image and the CorruptImageWarning of a truncated JPEG named <Name>' -ForEach @(
            @{ Name = 'cut.jpg' }
            @{ Name = 'cut[1]' }
        ) {
            $damaged = New-TestDamagedJpeg -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'damaged.jpg')
            $path = Join-Path -Path $script:tempDir.FullName -ChildPath $Name
            Move-Item -LiteralPath $damaged.FullName -Destination $path

            $read = Read-Image -Path $path

            try
            {
                $read.Exception | Should -BeNullOrEmpty
                $read.Result.Width | Should -Be 320
                $read.Warnings | Should -HaveCount 1
                $read.Warnings[0] | Should -BeOfType [ImageMagick.MagickCorruptImageWarningException]
                $read.Warnings[0].Message | Should -BeLike 'Premature end of JPEG file*'
            }
            finally
            {
                $read.Result.Dispose()
            }
        }

        It 'Should return the first frame and the MagickCorruptImageErrorException of an animated GIF cut off after its first frame' {
            $damaged = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'cut.gif') -FrameCount 3 -Keep 0.8

            $read = Read-Image -Path $damaged.FullName -CountFrames

            try
            {
                $read.Exception | Should -BeNullOrEmpty
                $read.Result.Width | Should -Be 16
                $read.FrameCount | Should -BeNullOrEmpty
                $read.Warnings | Should -HaveCount 1
                $read.Warnings[0] | Should -BeOfType [ImageMagick.MagickCorruptImageErrorException]
            }
            finally
            {
                $read.Result.Dispose()
            }
        }

        It 'Should return no warnings for an intact file' {
            $image = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'clean.jpg') -Width 320 -Height 240

            $read = Read-Image -Path $image.FullName -CountFrames

            try
            {
                $read.Warnings | Should -BeNullOrEmpty
                $read.FrameCount | Should -Be 1
            }
            finally
            {
                $read.Result.Dispose()
            }
        }
    }

    Context 'When the image is not handed back' {
        It 'Should dispose the image when <Case>' -ForEach @(
            @{ Case = 'the frame count is interrupted, as by Ctrl+C'; Stop = $true }
            @{ Case = 'the file cannot be read'; Stop = $false }
        ) {
            $path = Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.heic'
            Copy-Item -LiteralPath $script:fixture -Destination $path
            if (-not $Stop)
            {
                Set-Content -LiteralPath $path -Value 'not an image'
            }

            $outcome = InModuleScope -ModuleName $script:moduleName -Parameters @{ ImagePath = $path } {
                $script:readImages = [System.Collections.Generic.List[System.Object]]::new()

                # Keeps the image the function reads, so the test can check it afterwards.
                Mock -CommandName Invoke-ImageConverterMethod -ParameterFilter { $Name -eq 'Read' } -MockWith {
                    $script:readImages.Add($InputObject)
                    $exception = $null
                    try
                    {
                        $InputObject.Read([System.String] $ArgumentList[0])
                    }
                    catch
                    {
                        $exception = $_.Exception.InnerException
                    }

                    [PSCustomObject] @{ Result = $null; Exception = $exception; Arguments = $ArgumentList }
                }
                Mock -CommandName Get-ImageConverterFrameCount -MockWith { throw [System.InvalidOperationException]::new('interrupted') }

                $stopped = $false
                try
                {
                    $null = Read-ImageConverterImage -Path $ImagePath -CountFrames
                }
                catch
                {
                    $stopped = $true
                }

                [PSCustomObject] @{
                    Stopped = $stopped
                    Image   = $script:readImages[0]
                }
            }

            $outcome.Stopped | Should -Be $Stop
            # A disposed MagickImage throws ObjectDisposedException when it is used.
            { $null = $outcome.Image.ToByteArray([ImageMagick.MagickFormat]::Png) } | Should -Throw -ExpectedMessage '*disposed object*'
        }
    }

    Context 'When the frames are counted' {
        It 'Should count <Expected> frame(s) in <Name>' -ForEach @(
            @{ Name = 'sample.heic'; Expected = 1 }
            @{ Name = 'thumbnail.heic'; Expected = 1 }
            @{ Name = 'two-images.heic'; Expected = 2 }
        ) {
            $read = Read-Image -Path (Join-Path -Path $script:assets -ChildPath $Name) -CountFrames

            try
            {
                $read.FrameCount | Should -Be $Expected
                $read.Result.Width | Should -BeGreaterThan 0
            }
            finally
            {
                $read.Result.Dispose()
            }
        }

        It 'Should count the frames of a <Format> file named <Name>' -ForEach @(
            @{ Format = 'Gif'; Name = 'anim.gif' }
            @{ Format = 'WebP'; Name = 'anim.webp' }
            @{ Format = 'Tiff'; Name = 'pages.tif' }
            @{ Format = 'Gif'; Name = 'anim[1]' }
        ) {
            $frames = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'frames.bin') -Format $Format -FrameCount 3
            $path = Join-Path -Path $script:tempDir.FullName -ChildPath $Name
            Move-Item -LiteralPath $frames.FullName -Destination $path

            $read = Read-Image -Path $path -CountFrames

            try
            {
                $read.FrameCount | Should -Be 3
                $read.Result.Width | Should -Be 16
            }
            finally
            {
                $read.Result.Dispose()
            }
        }
    }
}
