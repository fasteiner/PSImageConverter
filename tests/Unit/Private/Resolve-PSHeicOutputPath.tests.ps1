BeforeAll {
    $script:moduleName = 'PSHeic'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Resolve-PSHeicOutputPath' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString()))
        $script:source = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.HEIC'
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should place the output next to the source file by default' {
        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Source = $script:source } {
            Resolve-PSHeicOutputPath -SourcePath $Source -Extension '.jpg'
        }

        $result | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg')
    }

    It 'Should use the destination folder without creating it' {
        $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'out'

        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Source = $script:source; Destination = $destination } {
            Resolve-PSHeicOutputPath -SourcePath $Source -Extension '.png' -DestinationPath $Destination
        }

        $result | Should -Be (Join-Path -Path $destination -ChildPath 'IMG_0001.png')
        Test-Path -Path $destination | Should -BeFalse
    }

    It 'Should throw when the target exists and Force is not set' {
        Set-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') -Value 'x'

        {
            InModuleScope -ModuleName $script:moduleName -Parameters @{ Source = $script:source } {
                Resolve-PSHeicOutputPath -SourcePath $Source -Extension '.jpg'
            }
        } | Should -Throw -ExpectedMessage '*already exists*'
    }

    It 'Should return the existing target when Force is set' {
        $existing = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg'
        Set-Content -Path $existing -Value 'x'

        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ Source = $script:source } {
            Resolve-PSHeicOutputPath -SourcePath $Source -Extension '.jpg' -Force
        }

        $result | Should -Be $existing
    }
}
