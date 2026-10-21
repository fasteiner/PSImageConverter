BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    # Runs Resolve-ImageConverterInputPath from an advanced script block, which provides the -Cmdlet it reports through.
    function Invoke-Resolve
    {
        param ([System.Collections.Hashtable] $Parameters)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ ResolveParameters = $Parameters } {
            $resolveErrors = $null
            $output = & {
                [CmdletBinding()]
                param ()

                Resolve-ImageConverterInputPath -Cmdlet $PSCmdlet @ResolveParameters
            } -ErrorAction SilentlyContinue -ErrorVariable resolveErrors -Verbose 4>&1

            [PSCustomObject] @{
                Paths   = @($output | Where-Object -FilterScript { $_ -is [System.String] })
                Verbose = @($output | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] })
                Errors  = @($resolveErrors)
            }
        }
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Resolve-ImageConverterInputPath' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
        foreach ($name in 'a.heic', 'b.heic', 'c[1].heic')
        {
            Set-Content -LiteralPath (Join-Path -Path $script:tempDir.FullName -ChildPath $name) -Value 'x'
        }
        $script:folder = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'folder.heic')
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should expand wildcards in -Path and skip folders' {
        $result = Invoke-Resolve -Parameters @{ Path = (Join-Path -Path $script:tempDir.FullName -ChildPath '?.heic'), (Join-Path -Path $script:tempDir.FullName -ChildPath 'folder.*') }

        $result.Errors | Should -BeNullOrEmpty
        $result.Paths | Sort-Object | Should -Be @(
            (Join-Path -Path $script:tempDir.FullName -ChildPath 'a.heic')
            (Join-Path -Path $script:tempDir.FullName -ChildPath 'b.heic')
        )
        "$($result.Verbose)" | Should -BeLike "*Skipping the folder '$($script:folder.FullName)'*"
    }

    It 'Should take -LiteralPath as written' {
        $literal = Join-Path -Path $script:tempDir.FullName -ChildPath 'c[1].heic'

        $result = Invoke-Resolve -Parameters @{ LiteralPath = $literal }

        $result.Paths | Should -Be $literal
    }

    It 'Should resolve a provider-qualified path from Get-ChildItem' {
        $item = Get-Item -LiteralPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'a.heic')

        $result = Invoke-Resolve -Parameters @{ LiteralPath = $item.PSPath }

        $result.Paths | Should -Be $item.FullName
    }

    It 'Should resolve a relative path against the current location' {
        Push-Location -LiteralPath $script:tempDir.FullName
        try
        {
            $result = Invoke-Resolve -Parameters @{ Path = 'b.heic' }
        }
        finally
        {
            Pop-Location
        }

        $result.Paths | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'b.heic')
    }

    It 'Should write PathNotFound for an item that matches nothing and continue' {
        $missing = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.heic'

        $result = Invoke-Resolve -Parameters @{ LiteralPath = $missing, (Join-Path -Path $script:tempDir.FullName -ChildPath 'a.heic') }

        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PathNotFound*'
        $result.Errors[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $result.Errors[0].TargetObject | Should -Be $missing
        "$($result.Errors[0])" | Should -Be "Cannot find path '$missing' because it does not exist."
        $result.Paths | Should -HaveCount 1
    }

    It 'Should say that a wildcard pattern matches no file, with the pattern as target' {
        $pattern = Join-Path -Path $script:tempDir.FullName -ChildPath '*.nomatch'

        $result = Invoke-Resolve -Parameters @{ Path = $pattern }

        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PathNotFound*'
        $result.Errors[0].Exception | Should -BeOfType [System.Management.Automation.ItemNotFoundException]
        $result.Errors[0].TargetObject | Should -Be $pattern
        "$($result.Errors[0])" | Should -BeLike "No file matches the pattern '$([System.Management.Automation.WildcardPattern]::Escape($pattern))'. *"
    }

    It 'Should say that the folder of a pattern does not exist instead of naming hidden files' {
        $folder = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing'
        $pattern = Join-Path -Path $folder -ChildPath '*.heic'

        $result = Invoke-Resolve -Parameters @{ Path = $pattern }

        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PathNotFound*'
        $result.Errors[0].TargetObject | Should -Be $pattern
        "$($result.Errors[0])" | Should -Be "No file matches the pattern '$pattern': the folder '$folder' does not exist."
    }

    It 'Should keep the plain message for a -Path without wildcard characters' {
        $missing = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.heic'

        $result = Invoke-Resolve -Parameters @{ Path = $missing }

        "$($result.Errors[0])" | Should -Be "Cannot find path '$missing' because it does not exist."
    }

    It 'Should name the hidden files that wildcards skip when only a hidden file matches' {
        $name = 'secret.heic'
        if (-not $IsWindows)
        {
            $name = '.secret.heic'
        }
        $hidden = Join-Path -Path $script:tempDir.FullName -ChildPath $name
        Set-Content -LiteralPath $hidden -Value 'x'
        if ($IsWindows)
        {
            [System.IO.File]::SetAttributes($hidden, [System.IO.FileAttributes]::Hidden)
        }
        $expected = 'hidden (dot) files'
        if ($IsWindows)
        {
            $expected = 'hidden files'
        }

        $result = Invoke-Resolve -Parameters @{ Path = $hidden.Replace('secret', 'secr?t') }

        $result.Paths | Should -BeNullOrEmpty
        "$($result.Errors[0])" | Should -BeLike "*. Wildcards do not match $expected; -LiteralPath does."
        (Invoke-Resolve -Parameters @{ LiteralPath = $hidden }).Paths | Should -Be $hidden
    }

    It 'Should write exactly one InvalidWildcardPattern error for a -Path that is not a valid pattern' {
        $odd = Join-Path -Path $script:tempDir.FullName -ChildPath 'd[.heic'
        Set-Content -LiteralPath $odd -Value 'x'

        $result = Invoke-Resolve -Parameters @{ Path = $odd }

        $result.Paths | Should -BeNullOrEmpty
        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'InvalidWildcardPattern*'
        $result.Errors[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        $result.Errors[0].Exception.InnerException | Should -BeOfType [System.Management.Automation.WildcardPatternException]
    }

    It 'Should write InvalidWildcardPattern also when no file has that literal name' {
        $odd = Join-Path -Path $script:tempDir.FullName -ChildPath 'zz[.heic'
        $errorCount = $global:Error.Count

        $result = Invoke-Resolve -Parameters @{ Path = $odd }

        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'InvalidWildcardPattern*'
        $result.Errors[0].TargetObject | Should -Be $odd
        $result.Errors[0].Exception.InnerException | Should -BeOfType [System.Management.Automation.WildcardPatternException]
        $global:Error.Count - $errorCount | Should -Be 1
    }

    It 'Should name the brackets as wildcard characters when a pattern with [ ] matches nothing' {
        # c[1].heic exists, but as a pattern it stands for c1.heic.
        $pattern = Join-Path -Path $script:tempDir.FullName -ChildPath 'c[1].heic'
        $hiddenFiles = 'hidden (dot) files'
        if ($IsWindows)
        {
            $hiddenFiles = 'hidden files'
        }

        $result = Invoke-Resolve -Parameters @{ Path = $pattern }

        $result.Paths | Should -BeNullOrEmpty
        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PathNotFound*'
        "$($result.Errors[0])" | Should -Be "No file matches the pattern '$pattern'. [ and ] are wildcard characters, and wildcards do not match $hiddenFiles; -LiteralPath takes the name as written."
    }

    It 'Should not name the brackets when they are escaped' {
        $pattern = Join-Path -Path $script:tempDir.FullName -ChildPath 'x`[1`]*.heic'

        $result = Invoke-Resolve -Parameters @{ Path = $pattern }

        "$($result.Errors[0])" | Should -BeLike '*. Wildcards do not match *'
    }

    It 'Should take such a name as written with -LiteralPath' {
        $odd = Join-Path -Path $script:tempDir.FullName -ChildPath 'd[.heic'
        Set-Content -LiteralPath $odd -Value 'x'

        $result = Invoke-Resolve -Parameters @{ LiteralPath = $odd }

        $result.Errors | Should -BeNullOrEmpty
        $result.Paths | Should -Be $odd
    }

    It 'Should write PathNotFound for a path on a drive that does not exist' {
        $result = Invoke-Resolve -Parameters @{ LiteralPath = 'PsicNoSuchDrive:\a.heic' }

        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'PathNotFound*'
        $result.Errors[0].Exception.InnerException | Should -BeOfType [System.Management.Automation.DriveNotFoundException]
    }

    It 'Should take a hidden file given by -LiteralPath' {
        $name = 'hidden.heic'
        if (-not $IsWindows)
        {
            $name = '.hidden.heic'
        }
        $hidden = Join-Path -Path $script:tempDir.FullName -ChildPath $name
        Set-Content -LiteralPath $hidden -Value 'x'
        if ($IsWindows)
        {
            [System.IO.File]::SetAttributes($hidden, [System.IO.FileAttributes]::Hidden)
        }

        $result = Invoke-Resolve -Parameters @{ LiteralPath = $hidden }

        $result.Paths | Should -Be $hidden
    }

    It 'Should return the long form of a short 8.3 path' -Skip:(-not $IsWindows) {
        $longFolder = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'LongFolderNameForShortTest')
        Set-Content -LiteralPath (Join-Path -Path $longFolder.FullName -ChildPath 'a.heic') -Value 'x'
        $shortFolder = (New-Object -ComObject 'Scripting.FileSystemObject').GetFolder($longFolder.FullName).ShortPath
        if ($shortFolder -notmatch '~')
        {
            Set-ItResult -Skipped -Because 'the volume creates no 8.3 names'
            return
        }

        $result = Invoke-Resolve -Parameters @{ LiteralPath = (Join-Path -Path $shortFolder -ChildPath 'a.heic') }

        $result.Paths | Should -Be (Join-Path -Path $longFolder.FullName -ChildPath 'a.heic')
    }

    It 'Should write UnsupportedProvider for the root of another provider' {
        $result = Invoke-Resolve -Parameters @{ LiteralPath = 'Env:\' }

        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'UnsupportedProvider*'
    }

    It 'Should write UnsupportedProvider for a path of another provider' {
        $result = Invoke-Resolve -Parameters @{ Path = 'Env:\PATH' }

        $result.Paths | Should -BeNullOrEmpty
        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'UnsupportedProvider*'
        $result.Errors[0].TargetObject | Should -Be 'Env:\PATH'
        "$($result.Errors[0])" | Should -Be "The path 'Env:\PATH' belongs to the Environment provider. Only file system paths are supported."
    }

    It 'Should write one UnsupportedProvider error for a pattern that matches several items of another provider' {
        $env:PSIC_RESOLVE_A = 'a'
        $env:PSIC_RESOLVE_B = 'b'
        try
        {
            $result = Invoke-Resolve -Parameters @{ Path = 'Env:\PSIC_RESOLVE_*', (Join-Path -Path $script:tempDir.FullName -ChildPath 'a.heic') }
        }
        finally
        {
            Remove-Item -Path 'Env:\PSIC_RESOLVE_A', 'Env:\PSIC_RESOLVE_B'
        }

        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'UnsupportedProvider*'
        $result.Errors[0].TargetObject | Should -Be 'Env:\PSIC_RESOLVE_*'
        $result.Paths | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'a.heic')
    }
}
