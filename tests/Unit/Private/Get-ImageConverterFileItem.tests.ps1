BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterFileItem' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
        $script:file = Join-Path -Path $script:tempDir.FullName -ChildPath 'Holiday [2026].jpg'
        Set-Content -LiteralPath $script:file -Value 'x'
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should return the item Get-Item returns, also for a name with wildcard characters' {
        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ FilePath = $script:file } {
            Get-ImageConverterFileItem -Path $FilePath
        }

        $result | Should -BeOfType [System.IO.FileInfo]
        $result.PSPath | Should -Be (Get-Item -LiteralPath $script:file).PSPath
        $result.PSParentPath | Should -Be (Get-Item -LiteralPath $script:file).PSParentPath
    }

    It 'Should return a hidden file' -Skip:(-not $IsWindows) {
        [System.IO.File]::SetAttributes($script:file, [System.IO.FileAttributes]::Hidden)

        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ FilePath = $script:file } {
            Get-ImageConverterFileItem -Path $FilePath
        }

        $result.FullName | Should -Be $script:file
    }

    It 'Should return a FileInfo with PSPath when the provider cannot return the item' {
        Mock -ModuleName $script:moduleName -CommandName Invoke-ImageConverterMethod -MockWith {
            [PSCustomObject] @{ Result = $null; Exception = [System.InvalidOperationException]::new('provider failure'); Arguments = $null }
        }

        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ FilePath = $script:file } {
            Get-ImageConverterFileItem -Path $FilePath
        }

        $result | Should -BeOfType [System.IO.FileInfo]
        $result.FullName | Should -Be $script:file
        $result.PSPath | Should -Be ('Microsoft.PowerShell.Core\FileSystem::' + $script:file)
    }

    It 'Should bind the result to -LiteralPath of the next cmdlet' {
        $result = InModuleScope -ModuleName $script:moduleName -Parameters @{ FilePath = $script:file } {
            Get-ImageConverterFileItem -Path $FilePath
        }

        # As -Path, 'Holiday [2026].jpg' would be a pattern that matches 'Holiday 2.jpg' and not the file itself.
        ($result | Get-Item -ErrorAction SilentlyContinue).FullName | Should -Be $script:file
    }
}
