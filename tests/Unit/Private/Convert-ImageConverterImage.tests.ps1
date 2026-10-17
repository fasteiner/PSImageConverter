BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:fixture = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Convert-ImageConverterImage' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString()))
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should write a <Format> file' -ForEach @(
        @{ Format = 'Jpeg'; Extension = '.jpg' }
        @{ Format = 'Png'; Extension = '.png' }
        @{ Format = 'Gif'; Extension = '.gif' }
    ) {
        $target = Join-Path -Path $script:tempDir.FullName -ChildPath "out$Extension"

        InModuleScope -ModuleName $script:moduleName -Parameters @{ Source = $script:fixture; Target = $target; Format = $Format } {
            Convert-ImageConverterImage -SourcePath $Source -TargetPath $Target -Format $Format -Quality 50 -StripMetadata
        }

        Test-Path -Path $target | Should -BeTrue
        (Get-HeicInfo -Path $target).Format | Should -Be $Format
    }

    It 'Should throw for an unreadable source' {
        $textFile = Join-Path -Path $script:tempDir.FullName -ChildPath 'broken.heic'
        Set-Content -Path $textFile -Value 'not an image'

        {
            InModuleScope -ModuleName $script:moduleName -Parameters @{ Source = $textFile; Target = (Join-Path -Path $script:tempDir.FullName -ChildPath 'out.jpg') } {
                Convert-ImageConverterImage -SourcePath $Source -TargetPath $Target -Format Jpeg
            }
        } | Should -Throw
    }
}
