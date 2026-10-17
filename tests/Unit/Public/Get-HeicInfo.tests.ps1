BeforeAll {
    $script:moduleName = 'PSHeic'
    Import-Module -Name $script:moduleName

    $script:fixture = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-HeicInfo' {
    Context 'When reading a HEIC file' {
        BeforeAll {
            $script:result = Get-HeicInfo -Path $script:fixture
        }

        It 'Should return a PSHeic.ImageInfo object' {
            $script:result.PSObject.TypeNames | Should -Contain 'PSHeic.ImageInfo'
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

        It 'Should report an orientation' {
            $script:result.Orientation | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When files are piped from Get-ChildItem' {
        It 'Should return one object per file' {
            $result = Get-Item -LiteralPath $script:fixture | Get-HeicInfo

            @($result).Count | Should -Be 1
        }
    }

    Context 'When the file does not exist' {
        It 'Should write an error' {
            $null = Get-HeicInfo -Path (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'does-not-exist.heic') -ErrorAction SilentlyContinue -ErrorVariable infoError

            $infoError | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When the file is not an image' {
        It 'Should write an error' {
            $textFile = New-TemporaryFile
            Set-Content -Path $textFile.FullName -Value 'not an image'

            $null = Get-HeicInfo -Path $textFile.FullName -ErrorAction SilentlyContinue -ErrorVariable infoError

            $infoError | Should -Not -BeNullOrEmpty
            Remove-Item -Path $textFile.FullName -Force
        }
    }
}
