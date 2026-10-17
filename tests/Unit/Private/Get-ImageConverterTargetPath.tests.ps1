BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:folder = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterTargetPath' {
    It 'Should use the folder of the source file by default' {
        $source = Join-Path -Path $script:folder -ChildPath 'IMG_1234.HEIC'

        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Source = $source } {
            Get-ImageConverterTargetPath -SourcePath $Source -Extension '.jpg'
        }

        $result | Should -Be (Join-Path -Path $script:folder -ChildPath 'IMG_1234.jpg')
    }

    It 'Should use the given folder and normalise it' {
        $source = Join-Path -Path $script:folder -ChildPath 'a.b.heic'
        $destination = Join-Path -Path $script:folder -ChildPath 'x/../out'

        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Source = $source; Destination = $destination } {
            Get-ImageConverterTargetPath -SourcePath $Source -Extension '.png' -Folder $Destination
        }

        $result | Should -Be ([System.IO.Path]::Combine($script:folder, 'out', 'a.b.png'))
    }
}
