BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterFormatInfo' {
    It 'Should return extension <Extension>, IsLossy <IsLossy>, KeepsExif <KeepsExif>, SupportsCmyk <SupportsCmyk> and StoresGray <StoresGray> for <Format>' -ForEach @(
        @{ Format = 'Jpeg'; Extension = '.jpg'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $true; StoresGray = $true }
        @{ Format = 'Png'; Extension = '.png'; IsLossy = $false; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $true }
        @{ Format = 'WebP'; Extension = '.webp'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $false }
        @{ Format = 'Avif'; Extension = '.avif'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $false }
        @{ Format = 'Jxl'; Extension = '.jxl'; IsLossy = $true; KeepsExif = $true; SupportsCmyk = $false; StoresGray = $true }
        @{ Format = 'Tiff'; Extension = '.tif'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $true; StoresGray = $true }
        @{ Format = 'Bmp'; Extension = '.bmp'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $false; StoresGray = $false }
        @{ Format = 'Gif'; Extension = '.gif'; IsLossy = $false; KeepsExif = $false; SupportsCmyk = $false; StoresGray = $false }
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
    }

    It 'Should return the name spelled as in the table for -Format <Given>' -ForEach @(
        @{ Given = 'webp'; Expected = 'WebP' }
        @{ Given = 'JXL'; Expected = 'Jxl' }
        @{ Given = 'jPeG'; Expected = 'Jpeg' }
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
                Get-ImageConverterFormatInfo -Format 'Heic'
            }
        } | Should -Throw
    }

    It 'Should return every format without -Format' {
        $result = InModuleScope -ModuleName $script:moduleName {
            Get-ImageConverterFormatInfo
        }

        $result.Format | Should -Be @('Jpeg', 'Png', 'WebP', 'Avif', 'Jxl', 'Tiff', 'Bmp', 'Gif')
        $result.Extension | Should -Be @('.jpg', '.png', '.webp', '.avif', '.jxl', '.tif', '.bmp', '.gif')
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
