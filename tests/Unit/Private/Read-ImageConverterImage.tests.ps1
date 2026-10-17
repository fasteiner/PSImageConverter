BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:fixture = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath

    function Read-Image
    {
        param ([System.String] $Path)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ ImagePath = $Path } {
            Read-ImageConverterImage -Path $ImagePath
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

        $read = Read-Image -Path $path

        $read.Result | Should -BeNullOrEmpty
        $read.Exception | Should -BeOfType [ImageMagick.MagickException]
    }

    It 'Should return the exception when a file read from a stream cannot be opened' {
        $read = Read-Image -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'missing[1]')

        $read.Result | Should -BeNullOrEmpty
        $read.Exception | Should -BeOfType [System.IO.FileNotFoundException]
    }
}
