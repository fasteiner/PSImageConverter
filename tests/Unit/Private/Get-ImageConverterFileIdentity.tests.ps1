BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    function Get-Identity
    {
        param ([System.String] $Path, [System.String] $Platform)

        $parameters = @{ Path = $Path }
        if ($Platform)
        {
            $parameters['Platform'] = $Platform
        }

        InModuleScope -ModuleName $script:moduleName -Parameters @{ IdentityParameters = $parameters } {
            Get-ImageConverterFileIdentity @IdentityParameters
        }
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterFileIdentity' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
        $script:realFolder = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'real')
        $script:linkFolder = Join-Path -Path $script:tempDir.FullName -ChildPath 'link'
        $linkType = 'SymbolicLink'
        if ($IsWindows)
        {
            $linkType = 'Junction'
        }
        $null = New-Item -ItemType $linkType -Path $script:linkFolder -Target $script:realFolder.FullName
        $script:file = Join-Path -Path $script:realFolder.FullName -ChildPath 'photo.jpg'
        Set-Content -Path $script:file -Value 'a'
    }

    AfterEach {
        Remove-Item -LiteralPath $script:linkFolder -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should return the same identity for a file reached through a link to its folder' {
        $identity = Get-Identity -Path $script:file

        $identity | Should -Not -BeNullOrEmpty
        Get-Identity -Path (Join-Path -Path $script:linkFolder -ChildPath 'photo.jpg') | Should -Be $identity
    }

    It 'Should return different identities for different files' {
        $other = Join-Path -Path $script:realFolder.FullName -ChildPath 'other.jpg'
        Set-Content -Path $other -Value 'a'

        Get-Identity -Path $other | Should -Not -Be (Get-Identity -Path $script:file)
    }

    It 'Should return the same identity for the \\?\ prefix and another letter case' -Skip:(-not $IsWindows) {
        $identity = Get-Identity -Path $script:file

        Get-Identity -Path ('\\?\' + $script:file) | Should -Be $identity
        Get-Identity -Path $script:file.ToUpperInvariant() | Should -Be $identity
    }

    It 'Should return $null for a path that is not a file' -ForEach @(
        @{ Name = 'missing.jpg' }
        @{ Name = 'real' }
    ) {
        Get-Identity -Path (Join-Path -Path $script:tempDir.FullName -ChildPath $Name) | Should -BeNullOrEmpty
    }

    It 'Should return $null when the API of the other platform is not available' {
        $otherPlatform = 'Windows'
        if ($IsWindows)
        {
            $otherPlatform = 'Unix'
        }

        Get-Identity -Path $script:file -Platform $otherPlatform | Should -BeNullOrEmpty
    }
}
