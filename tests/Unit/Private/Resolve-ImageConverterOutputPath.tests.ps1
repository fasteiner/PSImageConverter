BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    # Runs Resolve-ImageConverterOutputPath from an advanced script block, which provides the -Cmdlet it reports through.
    function Invoke-Resolve
    {
        param
        (
            [System.Collections.Hashtable] $Parameters,
            [System.Collections.Hashtable] $Claimed = @{},
            [System.Collections.Hashtable] $Written = @{}
        )

        InModuleScope -ModuleName $script:moduleName -Parameters @{ ResolveParameters = $Parameters; Claimed = $Claimed; Written = $Written } {
            $claimedTargets = [System.Collections.Generic.Dictionary[System.String, System.String]]::new((Get-ImageConverterPathComparer))
            foreach ($key in $Claimed.Keys)
            {
                $claimedTargets[$key] = $Claimed[$key]
            }

            # Keys of -Written are file paths; the cmdlet keys written files by their identity.
            $writtenTargets = [System.Collections.Generic.Dictionary[System.String, System.String]]::new([System.StringComparer]::Ordinal)
            foreach ($key in $Written.Keys)
            {
                $writtenTargets[(Get-ImageConverterFileIdentity -Path $key)] = $Written[$key]
            }

            $resolveErrors = $null
            $output = & {
                [CmdletBinding()]
                param ()

                Resolve-ImageConverterOutputPath -Cmdlet $PSCmdlet -ClaimedTarget $claimedTargets -WrittenTarget $writtenTargets @ResolveParameters
            } -ErrorAction SilentlyContinue -ErrorVariable resolveErrors

            [PSCustomObject] @{
                Output = $output
                Errors = @($resolveErrors)
            }
        }
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Resolve-ImageConverterOutputPath' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
        $script:source = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.HEIC'
        Set-Content -Path $script:source -Value 'x'
        $script:expected = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg'
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should place the output next to the source file by default' {
        $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.jpg' }

        $result.Errors | Should -BeNullOrEmpty
        $result.Output | Should -Be $script:expected
    }

    It 'Should use the destination folder without creating it' {
        $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'out'

        $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.png'; DestinationPath = $destination }

        $result.Output | Should -Be (Join-Path -Path $destination -ChildPath 'IMG_0001.png')
        $destination | Should -Not -Exist
    }

    It 'Should write TargetExists when the target exists and Force is not set' {
        Set-Content -Path $script:expected -Value 'x'

        $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.jpg' }

        $result.Output | Should -BeNullOrEmpty
        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'TargetExists*'
        $result.Errors[0].TargetObject | Should -Be $script:source
        "$($result.Errors[0])" | Should -BeLike '*already exists*'
    }

    It 'Should return the existing target when Force is set' {
        Set-Content -Path $script:expected -Value 'x'

        $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.jpg'; Force = $true }

        $result.Output | Should -Be $script:expected
    }

    It 'Should write TargetExists for a folder at the target path, also with Force' {
        $null = New-Item -ItemType Directory -Path $script:expected

        $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.jpg'; Force = $true }

        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'TargetExists*'
        "$($result.Errors[0])" | Should -BeLike '*existing folder*'
    }

    It 'Should write TargetIsSource when the target is the source, also with Force' {
        $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.HEIC'; Force = $true }

        $result.Output | Should -BeNullOrEmpty
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'TargetIsSource*'
    }

    It 'Should write DuplicateTarget for a target an earlier source claimed, also with Force' {
        $firstSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heif'

        $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.jpg'; Force = $true } -Claimed @{ $script:expected = $firstSource }

        $result.Output | Should -BeNullOrEmpty
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'DuplicateTarget*'
        "$($result.Errors[0])" | Should -BeLike "*$firstSource*"
    }

    It 'Should write DestinationNotDirectory when the destination is a file' {
        $file = Join-Path -Path $script:tempDir.FullName -ChildPath 'file.txt'
        Set-Content -Path $file -Value 'x'

        $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.jpg'; DestinationPath = $file }

        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'DestinationNotDirectory*'
        $result.Errors[0].TargetObject | Should -Be $script:source
    }

    It 'Should write UnsupportedProvider for a destination of another provider' {
        $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.jpg'; DestinationPath = 'Env:\Pictures' }

        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'UnsupportedProvider*'
        "$($result.Errors[0])" | Should -BeLike '*Environment provider*'
    }

    It 'Should write InvalidDestinationPath for a destination of an unknown provider' {
        $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.jpg'; DestinationPath = 'NoSuchProvider::C:\out' }

        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'InvalidDestinationPath*'
    }

    It 'Should write exactly one InvalidDestinationPath error for a destination that leaves its drive root' {
        $null = New-PSDrive -Name 'PsicRoot' -PSProvider FileSystem -Root $script:tempDir.FullName -Scope Global
        try
        {
            $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.jpg'; DestinationPath = 'PsicRoot:/../../x' }
        }
        finally
        {
            Remove-PSDrive -Name 'PsicRoot' -Scope Global
        }

        $result.Errors | Should -HaveCount 1
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'InvalidDestinationPath*'
        $result.Errors[0].Exception.InnerException | Should -Not -BeNullOrEmpty
    }

    Context 'When the target exists under another spelling' {
        BeforeEach {
            $script:realFolder = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'real')
            $script:linkFolder = Join-Path -Path $script:tempDir.FullName -ChildPath 'link'
            $linkType = 'SymbolicLink'
            if ($IsWindows)
            {
                $linkType = 'Junction'
            }
            $null = New-Item -ItemType $linkType -Path $script:linkFolder -Target $script:realFolder.FullName
            $script:realSource = Join-Path -Path $script:realFolder.FullName -ChildPath 'photo.jpg'
            Set-Content -Path $script:realSource -Value 'x'
        }

        AfterEach {
            Remove-Item -LiteralPath $script:linkFolder -Force -ErrorAction SilentlyContinue
        }

        It 'Should write TargetIsSource when the destination reaches the source through a link, also with Force' {
            $result = Invoke-Resolve -Parameters @{ SourcePath = $script:realSource; Extension = '.jpg'; DestinationPath = $script:linkFolder; Force = $true }

            $result.Output | Should -BeNullOrEmpty
            $result.Errors | Should -HaveCount 1
            $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'TargetIsSource*'
        }

        It 'Should write DuplicateTarget when the target is a file written earlier in the call, also with Force' {
            $written = Join-Path -Path $script:realFolder.FullName -ChildPath 'IMG_0001.jpg'
            Set-Content -Path $written -Value 'x'

            $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.jpg'; DestinationPath = $script:linkFolder; Force = $true } -Written @{ $written = 'first.heic' }

            $result.Output | Should -BeNullOrEmpty
            $result.Errors | Should -HaveCount 1
            $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'DuplicateTarget*'
            "$($result.Errors[0])" | Should -BeLike '*first.heic*'
        }

        It 'Should return an existing target that is another file with Force' {
            $other = Join-Path -Path $script:realFolder.FullName -ChildPath 'IMG_0001.jpg'
            Set-Content -Path $other -Value 'x'

            $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.jpg'; DestinationPath = $script:linkFolder; Force = $true } -Written @{ $script:realSource = 'first.heic' }

            $result.Errors | Should -BeNullOrEmpty
            $result.Output | Should -Be (Join-Path -Path $script:linkFolder -ChildPath 'IMG_0001.jpg')
        }
    }

    It 'Should compare the paths with the platform comparer when no file identity can be read' -Skip:$IsLinux {
        Mock -ModuleName $script:moduleName -CommandName Get-ImageConverterFileIdentity -MockWith { $null }

        $result = Invoke-Resolve -Parameters @{ SourcePath = $script:source; Extension = '.heic'; Force = $true }

        $result.Output | Should -BeNullOrEmpty
        $result.Errors[0].FullyQualifiedErrorId | Should -BeLike 'TargetIsSource*'
    }
}
