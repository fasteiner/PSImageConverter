BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterFormatInfo' {
    It 'Should return extension <Extension>, IsLossy <IsLossy>, KeepsExif <KeepsExif> and SupportsCmyk <SupportsCmyk> for <Format>' -ForEach @(
        @{ Format = 'Jpeg'; Extension = '.jpg'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $true }
        @{ Format = 'Png'; Extension = '.png'; IsLossy = $false; KeepsExif = $true; SupportsCmyk = $false }
        @{ Format = 'WebP'; Extension = '.webp'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false }
        @{ Format = 'Avif'; Extension = '.avif'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false }
        @{ Format = 'Jxl'; Extension = '.jxl'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false }
        @{ Format = 'Tiff'; Extension = '.tif'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $true }
        @{ Format = 'Bmp'; Extension = '.bmp'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $false }
        @{ Format = 'Gif'; Extension = '.gif'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $false }
    ) {
        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Format = $Format } {
            Get-ImageConverterFormatInfo -Format $Format
        }

        $result.Format | Should -Be $Format
        $result.Extension | Should -Be $Extension
        $result.IsLossy | Should -Be $IsLossy
        $result.KeepsExif | Should -Be $KeepsExif
        $result.SupportsCmyk | Should -Be $SupportsCmyk
    }

    It 'Should reject a format that cannot be written' {
        {
            InModuleScope -ModuleName $script:moduleName {
                Get-ImageConverterFormatInfo -Format 'Heic'
            }
        } | Should -Throw
    }
}
