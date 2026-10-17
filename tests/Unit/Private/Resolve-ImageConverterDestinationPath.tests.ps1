BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    function Resolve-Destination
    {
        param ([System.String] $DestinationPath)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ DestinationPath = $DestinationPath } {
            Resolve-ImageConverterDestinationPath -DestinationPath $DestinationPath
        }
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Resolve-ImageConverterDestinationPath' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should return the full path of a folder that does not exist yet without creating it' {
        $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'out/jpg'

        $result = Resolve-Destination -DestinationPath $destination

        $result.ErrorId | Should -BeNullOrEmpty
        $result.Path | Should -Be ([System.IO.Path]::GetFullPath($destination))
        $destination | Should -Not -Exist
    }

    It 'Should resolve a relative path against the current location' {
        Push-Location -LiteralPath $script:tempDir.FullName
        try
        {
            $result = Resolve-Destination -DestinationPath 'relative'
        }
        finally
        {
            Pop-Location
        }

        $result.Path | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'relative')
    }

    It 'Should return DestinationNotDirectory when <Case>' -ForEach @(
        @{ Case = 'the destination is a file'; Child = '' }
        @{ Case = 'a parent folder of the destination is a file'; Child = 'sub/deeper' }
    ) {
        $file = Join-Path -Path $script:tempDir.FullName -ChildPath 'file.txt'
        Set-Content -Path $file -Value 'x'
        $destination = $file
        if ($Child)
        {
            $destination = Join-Path -Path $file -ChildPath $Child
        }

        $result = Resolve-Destination -DestinationPath $destination

        $result.Path | Should -BeNullOrEmpty
        $result.ErrorId | Should -Be 'DestinationNotDirectory'
        $result.Exception.Message | Should -BeLike "*'$file' is a file*"
    }

    It 'Should return UnsupportedProvider for <DestinationPath>' -ForEach @(
        @{ DestinationPath = 'Env:\Pictures' }
        @{ DestinationPath = 'Env:\' }
        @{ DestinationPath = 'Function:\' }
    ) {
        $result = Resolve-Destination -DestinationPath $DestinationPath

        $result.ErrorId | Should -Be 'UnsupportedProvider'
        $result.Exception.Message | Should -BeLike '*provider. Only file system paths are supported.'
    }

    It 'Should return InvalidDestinationPath for an unknown provider' {
        $result = Resolve-Destination -DestinationPath 'NoSuchProvider::C:\out'

        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $result.Exception.InnerException | Should -BeOfType [System.Management.Automation.ProviderNotFoundException]
    }

    It 'Should return InvalidDestinationPath for a path that leaves its drive root without recording an error' {
        $null = New-PSDrive -Name 'PsicRoot' -PSProvider FileSystem -Root $script:tempDir.FullName -Scope Global
        $errorCount = $global:Error.Count
        try
        {
            $result = Resolve-Destination -DestinationPath 'PsicRoot:/../../x'
        }
        finally
        {
            Remove-PSDrive -Name 'PsicRoot' -Scope Global
        }

        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $global:Error.Count | Should -Be $errorCount
    }

    It 'Should return InvalidDestinationPath for invalid characters' -Skip:(-not $IsWindows) {
        $result = Resolve-Destination -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'a|b')

        $result.ErrorId | Should -Be 'InvalidDestinationPath'
        $result.Exception.Message | Should -BeLike '*invalid characters*'
    }
}
