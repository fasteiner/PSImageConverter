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
        $result.Paths | Should -HaveCount 1
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
    }
}
