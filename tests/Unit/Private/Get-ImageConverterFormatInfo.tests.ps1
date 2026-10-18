BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterFormatInfo' {
    It 'Should return extension <Extension>, IsLossy <IsLossy>, KeepsExif <KeepsExif>, SupportsCmyk <SupportsCmyk>, StoresGray <StoresGray> and KeepsAlpha <KeepsAlpha> for <Format>' -ForEach @(
        @{ Format = 'Jpeg'; Extension = '.jpg'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $true; StoresGray = $true; KeepsAlpha = $false }
        @{ Format = 'Png'; Extension = '.png'; IsLossy = $false; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $true; KeepsAlpha = $true }
        @{ Format = 'WebP'; Extension = '.webp'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $false; KeepsAlpha = $true }
        @{ Format = 'Avif'; Extension = '.avif'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $false; KeepsAlpha = $true }
        # The WIC encoder of Windows stores no alpha channel, ImageIO of macOS writes no EXIF.
        @{ Format = 'Heic'; Extension = '.heic'; IsLossy = $true; KeepsExif = -not $IsMacOS; SupportsCmyk = $false; StoresGray = $false; KeepsAlpha = -not $IsWindows }
        @{ Format = 'Jxl'; Extension = '.jxl'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $true; KeepsAlpha = $true }
        @{ Format = 'Tiff'; Extension = '.tif'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $true; StoresGray = $true; KeepsAlpha = $true }
        @{ Format = 'Bmp'; Extension = '.bmp'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $false; StoresGray = $false; KeepsAlpha = $true }
        @{ Format = 'Gif'; Extension = '.gif'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $false; StoresGray = $false; KeepsAlpha = $true }
    ) {
        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Format = $Format } {
            Get-ImageConverterFormatInfo -Format $Format
        }

        $result.Format | Should -Be $Format
        $result.Extension | Should -Be $Extension
        $result.IsLossy | Should -Be $IsLossy
        $result.KeepsExif | Should -Be $KeepsExif
        $result.SupportsCmyk | Should -Be $SupportsCmyk
        $result.StoresGray | Should -Be $StoresGray
        $result.KeepsAlpha | Should -Be $KeepsAlpha
    }

    It 'Should return the name spelled as in the table for -Format <Given>' -ForEach @(
        @{ Given = 'webp'; Expected = 'WebP' }
        @{ Given = 'JXL'; Expected = 'Jxl' }
        @{ Given = 'jPeG'; Expected = 'Jpeg' }
        @{ Given = 'HEIC'; Expected = 'Heic' }
    ) {
        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Format = $Given } {
            Get-ImageConverterFormatInfo -Format $Format
        }

        $result | Should -HaveCount 1
        $result.Format | Should -BeExactly $Expected
    }

    It 'Should reject a format that cannot be written' {
        {
            InModuleScope -ModuleName $script:moduleName {
                Get-ImageConverterFormatInfo -Format 'Heif'
            }
        } | Should -Throw
    }

    It 'Should return every format without -Format' {
        $result = InModuleScope -ModuleName $script:moduleName {
            Get-ImageConverterFormatInfo
        }

        $result.Format | Should -Be @('Jpeg', 'Png', 'WebP', 'Avif', 'Heic', 'Jxl', 'Tiff', 'Bmp', 'Gif')
        $result.Extension | Should -Be @('.jpg', '.png', '.webp', '.avif', '.heic', '.jxl', '.tif', '.bmp', '.gif')
    }

    It 'Should list exactly the formats of this table in every -Format ValidateSet of the module' {
        # Every function of the module, public or private, whose -Format parameter has a ValidateSet.
        $validateSets = InModuleScope -ModuleName $script:moduleName {
            foreach ($command in Get-ChildItem -Path 'function:' | Where-Object -FilterScript { $_.Module -eq $ExecutionContext.SessionState.Module })
            {
                $validateSet = $command.Parameters['Format'].Attributes | Where-Object -FilterScript { $_ -is [System.Management.Automation.ValidateSetAttribute] }
                if ($validateSet)
                {
                    [PSCustomObject] @{
                        Name        = $command.Name
                        ValidValues = @($validateSet.ValidValues)
                    }
                }
            }
        }
        $tableFormats = InModuleScope -ModuleName $script:moduleName {
            (Get-ImageConverterFormatInfo).Format
        }

        $validateSets.Name | Should -Contain 'Convert-Image'
        $validateSets.Name | Should -Contain 'ConvertFrom-Heic'
        $validateSets.Name | Should -Contain 'Convert-ImageConverterImage'
        $validateSets.Name | Should -Contain 'Get-ImageConverterFormatInfo'
        foreach ($validateSet in $validateSets)
        {
            $validateSet.ValidValues | Sort-Object | Should -Be ($tableFormats | Sort-Object) -Because "the -Format ValidateSet of $($validateSet.Name) has to match the format table"
        }
    }
}
