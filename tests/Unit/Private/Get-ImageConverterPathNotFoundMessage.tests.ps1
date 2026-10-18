BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    # Returns the exception the module's own path resolution gets for the path, or nothing when it finds the path.
    function Get-ModuleResolveException
    {
        param ([System.String] $Path)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ ResolvePath = $Path } {
            (Invoke-ImageConverterMethod -InputObject $ExecutionContext.SessionState.Path -Name 'GetResolvedPSPathFromPSPath' -ArgumentList $ResolvePath).Exception
        }
    }

    # A user's advanced function, so the message sees the drives and the location of the scope that calls it, as a public cmdlet does.
    function Get-Message
    {
        [CmdletBinding()]
        [OutputType([System.String])]
        param ([System.String] $Path, [System.Management.Automation.SwitchParameter] $IsPattern)

        $exception = Get-ModuleResolveException -Path $Path

        & (Get-Module -Name $script:moduleName) {
            param ($Cmdlet, $Path, $IsPattern, $Exception)

            Get-ImageConverterPathNotFoundMessage -Cmdlet $Cmdlet -Path $Path -IsPattern:$IsPattern -Exception $Exception
        } $PSCmdlet $Path $IsPattern $exception
    }

    $script:hiddenFiles = 'hidden (dot) files'
    if ($IsWindows)
    {
        $script:hiddenFiles = 'hidden files'
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterPathNotFoundMessage' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'When the input is no pattern' {
        It 'Should say that the path does not exist' {
            $missing = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.heic'

            Get-Message -Path $missing | Should -Be "Cannot find path '$missing' because it does not exist."
        }

        It 'Should say so also for a drive that does not exist' {
            Get-Message -Path 'PsicNoSuchDrive:\a.heic' | Should -Be "Cannot find path 'PsicNoSuchDrive:\a.heic' because it does not exist."
        }
    }

    Context 'When the input is a pattern' {
        It 'Should name the hidden files when the folder exists' {
            $pattern = Join-Path -Path $script:tempDir.FullName -ChildPath '*.nomatch'

            Get-Message -Path $pattern -IsPattern | Should -Be "No file matches the pattern '$pattern'. Wildcards do not match $($script:hiddenFiles); -LiteralPath does."
        }

        It 'Should name the hidden files for a pattern relative to the current location' {
            Push-Location -LiteralPath $script:tempDir.FullName
            try
            {
                $result = Get-Message -Path '*.nomatch' -IsPattern
            }
            finally
            {
                Pop-Location
            }

            $result | Should -Be "No file matches the pattern '*.nomatch'. Wildcards do not match $($script:hiddenFiles); -LiteralPath does."
        }

        It 'Should name [ and ] as wildcard characters when the folder exists' {
            $pattern = Join-Path -Path $script:tempDir.FullName -ChildPath 'c[1].heic'

            Get-Message -Path $pattern -IsPattern | Should -Be "No file matches the pattern '$pattern'. [ and ] are wildcard characters, and wildcards do not match $($script:hiddenFiles); -LiteralPath takes the name as written."
        }

        It 'Should not name escaped brackets' {
            $pattern = Join-Path -Path $script:tempDir.FullName -ChildPath 'x`[1`]*.heic'

            Get-Message -Path $pattern -IsPattern | Should -BeLike '*. Wildcards do not match *; -LiteralPath does.'
        }

        It 'Should say that the folder does not exist, without the hidden-file hint' {
            $folder = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing'
            $pattern = Join-Path -Path $folder -ChildPath '*.heic'

            Get-Message -Path $pattern -IsPattern | Should -Be "No file matches the pattern '$pattern': the folder '$folder' does not exist."
        }

        It 'Should say that the folder does not exist also when the name has brackets' {
            $folder = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing'
            $pattern = Join-Path -Path $folder -ChildPath 'c[1].heic'

            Get-Message -Path $pattern -IsPattern | Should -Be "No file matches the pattern '$pattern': the folder '$folder' does not exist."
        }

        It 'Should say that the parent is a file, not a folder' {
            $file = Join-Path -Path $script:tempDir.FullName -ChildPath 'file.txt'
            Set-Content -LiteralPath $file -Value 'x'
            $pattern = Join-Path -Path $file -ChildPath '*.heic'

            Get-Message -Path $pattern -IsPattern | Should -Be "No file matches the pattern '$pattern': '$file' is a file, not a folder."
        }

        It 'Should say that no folder matches a folder part with wildcards' {
            $folder = Join-Path -Path $script:tempDir.FullName -ChildPath 'nofolder*'
            $pattern = Join-Path -Path $folder -ChildPath '*.heic'

            Get-Message -Path $pattern -IsPattern | Should -Be "No file matches the pattern '$pattern': no folder matches '$folder'."
        }

        It 'Should name the hidden folders when only hidden folders match a folder part with wildcards' {
            # Windows hides a folder with the Hidden attribute, Linux and macOS one whose name starts with a dot.
            $hiddenName = '.hiddenfolder'
            $folderPattern = '.hidden*'
            if ($IsWindows)
            {
                $hiddenName = 'hiddenfolder'
                $folderPattern = 'hidden*'
            }

            $hidden = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath $hiddenName)
            if ($IsWindows)
            {
                $hidden.Attributes = $hidden.Attributes -bor [System.IO.FileAttributes]::Hidden
            }

            $folder = Join-Path -Path $script:tempDir.FullName -ChildPath $folderPattern
            $pattern = Join-Path -Path $folder -ChildPath '*.heic'
            $hiddenFolders = 'hidden (dot) folders'
            if ($IsWindows)
            {
                $hiddenFolders = 'hidden folders'
            }

            Get-Message -Path $pattern -IsPattern | Should -Be "No file matches the pattern '$pattern': no folder matches '$folder'. Wildcards do not match $hiddenFolders; a folder name without wildcards reaches them."
        }

        It 'Should name [ and ] as wildcard characters that can be escaped when they keep the folder from matching' {
            # 'Photos [2024]' exists, but as a pattern it matches 'Photos 2', 'Photos 0' and 'Photos 4' only; -LiteralPath would take '*' literally, too.
            $folder = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'Photos [2024]')
            $pattern = Join-Path -Path $folder.FullName -ChildPath '*.heic'

            Get-Message -Path $pattern -IsPattern | Should -Be "No file matches the pattern '$pattern': no folder matches '$($folder.FullName)'. [ and ] are wildcard characters; escape them with a backtick (``[ and ``]) to match them as written."
        }

        It 'Should point to -LiteralPath for [ and ] in the folder part when the file name has no wildcards' {
            $folder = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'Photos [2024]')
            $pattern = Join-Path -Path $folder.FullName -ChildPath 'IMG_1.heic'

            Get-Message -Path $pattern -IsPattern | Should -Be "No file matches the pattern '$pattern': no folder matches '$($folder.FullName)'. [ and ] are wildcard characters; -LiteralPath takes the name as written."
        }

        It 'Should suggest ? for [ and ] in a file name that has other wildcards' {
            # PowerShell finds nothing for 'scan`[1`]*.heic' on Windows, and -LiteralPath takes '*' literally.
            $pattern = Join-Path -Path $script:tempDir.FullName -ChildPath 'scan[1]*.heic'

            Get-Message -Path $pattern -IsPattern | Should -Be "No file matches the pattern '$pattern'. [ and ] are wildcard characters, and wildcards do not match $($script:hiddenFiles); put ? in place of [ and ] to match them, as -LiteralPath takes no wildcards."
        }

        It 'Should keep the hidden-file hint when a folder part with wildcards matches a folder' {
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photos')
            $pattern = Join-Path -Path $script:tempDir.FullName -ChildPath 'pho*/*.heic'

            Get-Message -Path $pattern -IsPattern | Should -BeLike "No file matches the pattern '*'. Wildcards do not match $($script:hiddenFiles); -LiteralPath does."
        }

        It 'Should give no hint for a container of another provider: <Path>' -ForEach @(
            @{ Path = 'Env:\PSIC_NO_SUCH_*'; WindowsOnly = $false }
            @{ Path = 'HKCU:\Software\PSIC_NO_SUCH_*'; WindowsOnly = $true }
        ) {
            if ($WindowsOnly -and -not $IsWindows)
            {
                Set-ItResult -Skipped -Because 'the Registry provider exists on Windows only'
                return
            }

            Get-Message -Path $Path -IsPattern | Should -Be "No file matches the pattern '$Path'."
        }

        It 'Should say that the drive does not exist' {
            Get-Message -Path 'PsicNoSuchDrive:\photos\*.heic' -IsPattern | Should -Be "No file matches the pattern 'PsicNoSuchDrive:\photos\*.heic': the drive 'PsicNoSuchDrive' does not exist."
        }
    }

    Context 'When the drive was created in a scope the module cannot see' {
        BeforeEach {
            $script:hint = "drive 'PsicScopeDrive' was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module). Create the drive with New-PSDrive -Scope Global, or use the file system path; the root of the drive is '$($script:tempDir.FullName)'."
        }

        It 'Should explain the drive for a path on it, pattern <IsPattern>' -ForEach @(
            @{ IsPattern = $false; Path = 'PsicScopeDrive:\a.heic' }
            @{ IsPattern = $true; Path = 'PsicScopeDrive:\*.heic' }
        ) {
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName

            Get-Message -Path $Path -IsPattern:$IsPattern | Should -Be "Cannot resolve the path '$Path': $($script:hint)"
        }

        It 'Should explain the drive of the current location for a relative path, pattern <IsPattern>' -ForEach @(
            @{ IsPattern = $false; Path = 'a.heic' }
            @{ IsPattern = $true; Path = '.\*.heic' }
        ) {
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
            Push-Location -Path 'PsicScopeDrive:\'
            try
            {
                # 'PsicScopeDrive:\' on Windows, 'PsicScopeDrive:/' on Linux and macOS.
                $location = (Get-Location).Path
                $result = Get-Message -Path $Path -IsPattern:$IsPattern
            }
            finally
            {
                Pop-Location
            }

            $result | Should -Be "Cannot resolve the path '$Path', which is relative to the current location '$location': $($script:hint)"
        }

        It 'Should explain a drive of the caller that hides a global drive of the same name, relative <Relative>' -ForEach @(
            @{ Relative = $false; Path = 'PsicScopeDrive:\a.heic' }
            @{ Relative = $true; Path = 'a.heic' }
        ) {
            $globalRoot = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'global')
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $globalRoot.FullName -Scope Global
            try
            {
                $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
                Push-Location -Path 'PsicScopeDrive:\'
                try
                {
                    $location = (Get-Location).Path
                    $result = Get-Message -Path $Path
                }
                finally
                {
                    Pop-Location
                }
            }
            finally
            {
                Remove-PSDrive -Name 'PsicScopeDrive' -Scope Global
            }

            $hint = "drive 'PsicScopeDrive' was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module), so the module would use the global drive of that name, whose root is '$($globalRoot.FullName)'. Give the drive a name that no global drive has, or use the file system path; the root of the drive is '$($script:tempDir.FullName)'."
            $expected = "Cannot resolve the path '$Path': $hint"
            if ($Relative)
            {
                $expected = "Cannot resolve the path '$Path', which is relative to the current location '$location': $hint"
            }

            $result | Should -Be $expected
        }
    }
}
