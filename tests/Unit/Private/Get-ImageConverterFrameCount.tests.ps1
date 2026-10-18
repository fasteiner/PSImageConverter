BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:assets = Split-Path -Path (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath -Parent
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')

    function Get-FrameCount
    {
        param ([System.Object] $Source)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ FrameSource = $Source } {
            Get-ImageConverterFrameCount -Source $FrameSource
        }
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterFrameCount' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should count the <FrameCount> frames of a <Format> file' -ForEach @(
        @{ Format = 'Gif'; FrameCount = 3 }
        @{ Format = 'WebP'; FrameCount = 2 }
        @{ Format = 'Tiff'; FrameCount = 4 }
    ) {
        $file = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath "frames.$Format") -Format $Format -FrameCount $FrameCount

        (Get-FrameCount -Source $file.FullName).Count | Should -Be $FrameCount
    }

    It 'Should count <Expected> image(s) in the HEIC file <Name>' -ForEach @(
        @{ Name = 'sample.heic'; Expected = 1 }
        @{ Name = 'thumbnail.heic'; Expected = 1 }
        @{ Name = 'two-images.heic'; Expected = 2 }
    ) {
        (Get-FrameCount -Source (Join-Path -Path $script:assets -ChildPath $Name)).Count | Should -Be $Expected
    }

    It 'Should count a layered Photoshop file as one image' {
        $file = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'layers.psd') -Format Psd -FrameCount 3

        (Get-FrameCount -Source $file.FullName).Count | Should -Be 1
    }

    It 'Should count the frames of a stream from its beginning' {
        $file = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'anim.gif') -Format Gif -FrameCount 3
        $stream = [System.IO.File]::OpenRead($file.FullName)

        try
        {
            $stream.Position = $stream.Length

            (Get-FrameCount -Source $stream).Count | Should -Be 3
        }
        finally
        {
            $stream.Dispose()
        }
    }

    It 'Should return the MagickCorruptImageErrorException of an animated GIF cut off after its first frame' {
        $file = New-TestFrameImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'cut.gif') -FrameCount 3 -Keep 0.8

        $Error.Clear()
        $result = Get-FrameCount -Source $file.FullName

        $result.Count | Should -BeNullOrEmpty
        $result.Exception | Should -BeOfType [ImageMagick.MagickCorruptImageErrorException]
        $Error | Should -BeNullOrEmpty
    }

    It 'Should return no count but the exception, without an error record, for <Case>' -ForEach @(
        @{ Case = 'a file that is not an image'; Kind = 'Text' }
        @{ Case = 'a missing file'; Kind = 'Missing' }
        @{ Case = 'a stream that cannot be read any more'; Kind = 'Closed' }
    ) {
        $path = Join-Path -Path $script:tempDir.FullName -ChildPath 'notes.txt'
        $source = $path

        if ($Kind -eq 'Text')
        {
            Set-Content -LiteralPath $path -Value 'not an image'
        }
        elseif ($Kind -eq 'Closed')
        {
            Set-Content -LiteralPath $path -Value 'not an image'
            $source = [System.IO.File]::OpenRead($path)
            $source.Dispose()
        }

        $Error.Clear()
        $result = Get-FrameCount -Source $source

        $result.Count | Should -BeNullOrEmpty
        $result.Exception | Should -BeOfType [System.Exception]
        $Error | Should -BeNullOrEmpty
    }
}
