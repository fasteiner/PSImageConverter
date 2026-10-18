[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'heicAvailable', Justification = 'Set in BeforeDiscovery and read by the -Skip expressions, which PSScriptAnalyzer does not see.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The -ErrorVariable, -WarningVariable and -OutVariable +name tests append to a global variable, as the interactive prompt and pwsh -File scripts do.')]
param ()

BeforeDiscovery {
    Import-Module -Name 'PSImageConverter'

    # The tests that write HEIC run only where the encoder of the operating system works; the probe runs once per process.
    $heicAvailable = $null -eq [PSImageConverter.HeicEncoder]::GetUnavailableReason()
}

BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    $script:fixture = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic')).ProviderPath
    $script:manifestPath = Join-Path -Path (Get-Module -Name $script:moduleName).ModuleBase -ChildPath "$($script:moduleName).psd1"
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'ConvertFrom-Heic' {
    BeforeEach {
        $script:tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
        $script:source = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.HEIC'
        Copy-Item -Path $script:fixture -Destination $script:source
    }

    AfterEach {
        Remove-Item -Path $script:tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'When converting with default parameters' {
        It 'Should write a JPEG next to the source file and return it' {
            $result = ConvertFrom-Heic -Path $script:source

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.Name | Should -Be 'IMG_0001.jpg'
            $result.DirectoryName | Should -Be $script:tempDir.FullName
            $result.Exists | Should -BeTrue
        }

        It 'Should produce a JPEG with the same dimensions as the source' {
            $result = ConvertFrom-Heic -Path $script:source
            $sourceInfo = Get-ImageInfo -Path $script:source
            $targetInfo = Get-ImageInfo -Path $result.FullName

            $targetInfo.Format | Should -Be 'Jpeg'
            $targetInfo.Width | Should -Be $sourceInfo.Width
            $targetInfo.Height | Should -Be $sourceInfo.Height
        }
    }

    Context 'When choosing another output format' {
        It 'Should write a <Format> file with extension <Extension>' -ForEach @(
            @{ Format = 'Png'; Extension = '.png' }
            @{ Format = 'WebP'; Extension = '.webp' }
            @{ Format = 'Avif'; Extension = '.avif' }
            @{ Format = 'Jxl'; Extension = '.jxl' }
            @{ Format = 'Tiff'; Extension = '.tif' }
            @{ Format = 'Bmp'; Extension = '.bmp' }
            @{ Format = 'Gif'; Extension = '.gif' }
        ) {
            $result = ConvertFrom-Heic -Path $script:source -Format $Format -Quality 75

            $result.Extension | Should -Be $Extension
            (Get-ImageInfo -Path $result.FullName).Format | Should -Be $Format
        }
    }

    Context 'When checking the source extension' {
        It 'Should accept the extension <Name>' -ForEach @(
            @{ Name = 'a.heic' }
            @{ Name = 'b.HEIF' }
            @{ Name = 'c.Hif' }
        ) {
            $path = Join-Path -Path $script:tempDir.FullName -ChildPath $Name
            Copy-Item -Path $script:fixture -Destination $path

            $result = ConvertFrom-Heic -LiteralPath $path -Format Png

            $result.Extension | Should -Be '.png'
        }

        It 'Should write a NotHeicFile error for a file with another extension' {
            $jpeg = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'photo.jpg')

            $result = ConvertFrom-Heic -Path $jpeg.FullName -Format Png -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'NotHeicFile,ConvertFrom-Heic'
            $conversionError[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $conversionError[0].TargetObject | Should -Be $jpeg.FullName
            "$($conversionError[0])" | Should -Match 'not a HEIC/HEIF image'
        }
    }

    Context 'When -Path contains wildcards' {
        It 'Should convert every matching file' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.HEIC')

            $result = ConvertFrom-Heic (Join-Path -Path $script:tempDir.FullName -ChildPath '*.HEIC') -Format Png

            $result.Name | Sort-Object | Should -Be @('IMG_0001.png', 'IMG_0002.png')
        }

        It 'Should write a PathNotFound error when the pattern matches nothing' {
            $null = ConvertFrom-Heic -Path (Join-Path -Path $script:tempDir.FullName -ChildPath '*.nomatch') -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,ConvertFrom-Heic'
        }
    }

    Context 'When file names contain wildcard characters' {
        BeforeEach {
            $script:bracketSource = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG[1].heic'
            Copy-Item -LiteralPath $script:fixture -Destination $script:bracketSource
        }

        It 'Should convert the file given by -LiteralPath without expanding it a second time' {
            $result = ConvertFrom-Heic -LiteralPath $script:bracketSource -Format Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be 'IMG[1].png'
        }

        It 'Should convert the file matched by a -Path pattern without expanding it a second time' {
            $result = ConvertFrom-Heic -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG`[1`].heic') -Format Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Should -Be 'IMG[1].png'
        }

        It 'Should bind files piped from Get-ChildItem to -LiteralPath' {
            $result = Get-ChildItem -LiteralPath $script:bracketSource | ConvertFrom-Heic -Format Png

            $result.Name | Should -Be 'IMG[1].png'
        }
    }

    Context 'When files are piped from Get-ChildItem' {
        It 'Should convert every piped file and skip folders' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.heif')
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'folder.heic')

            $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertFrom-Heic -Format Png -ErrorVariable conversionError

            $conversionError | Should -BeNullOrEmpty
            $result.Name | Sort-Object | Should -Be @('IMG_0001.png', 'IMG_0002.png')
        }

        It 'Should accept pipeline input from strings' {
            $result = $script:source | ConvertFrom-Heic -Format Png

            $result.Name | Should -Be 'IMG_0001.png'
        }

        It 'Should skip the files it writes itself into a -DestinationPath inside the piped tree' {
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'sub')
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'sub/IMG_0002.heic')
            # Get-ChildItem enters the existing folder jpg after it has passed IMG_0001.HEIC on, so IMG_0001.jpg is listed.
            $destination = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'jpg')

            $result = Get-ChildItem -Path $script:tempDir.FullName -Recurse | ConvertFrom-Heic -DestinationPath $destination.FullName -ErrorVariable conversionError
            $succeeded = $?

            $conversionError | Should -BeNullOrEmpty
            $succeeded | Should -BeTrue
            $result.Name | Sort-Object | Should -Be @('IMG_0001.jpg', 'IMG_0002.jpg')
        }

        It 'Should convert every file of such a tree with -ErrorAction Stop' {
            $null = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'sub')
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'sub/IMG_0002.heic')
            $destination = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'jpg')

            $null = Get-ChildItem -Path $script:tempDir.FullName -Recurse | ConvertFrom-Heic -DestinationPath $destination.FullName -ErrorAction Stop

            Join-Path -Path $destination.FullName -ChildPath 'IMG_0002.jpg' | Should -Exist
        }

        It 'Should still write a NotHeicFile error for another file in the destination' {
            $destination = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'jpg')
            $null = New-TestImage -Path (Join-Path -Path $destination.FullName -ChildPath 'other.jpg')

            $null = Get-ChildItem -Path $script:tempDir.FullName -Recurse | ConvertFrom-Heic -DestinationPath $destination.FullName -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'NotHeicFile,ConvertFrom-Heic'
            $conversionError[0].TargetObject | Should -Be (Join-Path -Path $destination.FullName -ChildPath 'other.jpg')
        }

        It 'Should write a DuplicateTarget error for sources with the same base name, also with -Force' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.heif')

            $result = Get-ChildItem -Path $script:tempDir.FullName | ConvertFrom-Heic -Force -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -HaveCount 1
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'DuplicateTarget,Convert-Image'
        }
    }

    Context 'When the target file already exists' {
        BeforeEach {
            Set-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') -Value 'existing'
        }

        It 'Should write a TargetExists error and keep the existing file without -Force' {
            $result = ConvertFrom-Heic -Path $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetExists,Convert-Image'
            "$($conversionError[0])" | Should -Match 'already exists'
            Get-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') | Should -Be 'existing'
        }

        It 'Should overwrite the file with -Force' {
            $result = ConvertFrom-Heic -Path $script:source -Force

            $result.FullName | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg')
            (Get-ImageInfo -LiteralPath $result.FullName).Format | Should -Be 'Jpeg'
        }
    }

    Context 'When a file fails' {
        BeforeEach {
            $script:missing = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.heic'
            $script:textFile = Join-Path -Path $script:tempDir.FullName -ChildPath 'notes.txt'
            Set-Content -Path $script:textFile -Value 'not an image'
        }

        It 'Should hold exactly one error record per failed file in -ErrorVariable' {
            $broken = Join-Path -Path $script:tempDir.FullName -ChildPath 'broken.heic'
            Set-Content -Path $broken -Value 'not an image'

            $null = ConvertFrom-Heic -Path $script:missing, $script:textFile, $broken, $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 3
            $conversionError.FullyQualifiedErrorId | Should -Be @('PathNotFound,ConvertFrom-Heic', 'NotHeicFile,ConvertFrom-Heic', 'ImageReadFailed,Convert-Image')
        }

        It 'Should set $? to $false and continue with the next file' {
            $result = ConvertFrom-Heic -Path $script:missing, $script:source -ErrorAction SilentlyContinue
            $succeeded = $?

            $succeeded | Should -BeFalse
            $result.Name | Should -Be 'IMG_0001.jpg'
        }

        It 'Should set $? to $false for an error of Convert-Image' {
            Set-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') -Value 'existing'

            $null = ConvertFrom-Heic -Path $script:source -ErrorAction SilentlyContinue
            $succeeded = $?

            $succeeded | Should -BeFalse
        }

        It 'Should keep $? at $true when every file is converted' {
            $null = ConvertFrom-Heic -Path $script:source
            $succeeded = $?

            $succeeded | Should -BeTrue
        }

        It 'Should stop at the first failure with -ErrorAction Stop' {
            { ConvertFrom-Heic -Path $script:textFile, $script:source -ErrorAction Stop } | Should -Throw -ErrorId 'NotHeicFile,ConvertFrom-Heic'

            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg' | Should -Not -Exist
        }

        It 'Should stop at the first failure of Convert-Image with -ErrorAction Stop' {
            Set-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') -Value 'existing'
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.heic')

            { ConvertFrom-Heic -LiteralPath $script:source, (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.heic') -ErrorAction Stop } | Should -Throw -ErrorId 'TargetExists,Convert-Image'

            Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.jpg' | Should -Not -Exist
        }

        It 'Should make pwsh -Command fail when checking $?' {
            $command = "Import-Module -Name '$script:manifestPath'; ConvertFrom-Heic -Path '$script:missing' -ErrorAction SilentlyContinue; exit (!`$? ? 1 : 0)"

            & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command $command

            $LASTEXITCODE | Should -Be 1
        }
    }

    Context 'When common parameters name a variable' {
        It 'Should append each error of Convert-Image once to an existing global variable with -ErrorVariable +name' {
            Set-Content -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg') -Value 'existing'
            $global:PsicAppendErrors = [System.Collections.ArrayList]::new()
            try
            {
                $null = ConvertFrom-Heic -Path $script:source -ErrorAction SilentlyContinue -ErrorVariable +PsicAppendErrors

                $global:PsicAppendErrors | Should -HaveCount 1
                $global:PsicAppendErrors[0].FullyQualifiedErrorId | Should -Be 'TargetExists,Convert-Image'
            }
            finally
            {
                Remove-Variable -Name 'PsicAppendErrors' -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'Should append each warning once to an existing global variable with -WarningVariable +name' {
            $exifSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.heic') -Exif
            $global:PsicAppendWarnings = [System.Collections.ArrayList]::new()
            try
            {
                $null = ConvertFrom-Heic -Path $exifSource.FullName -Format Gif -WarningAction SilentlyContinue -WarningVariable +PsicAppendWarnings

                $global:PsicAppendWarnings | Should -HaveCount 1
            }
            finally
            {
                Remove-Variable -Name 'PsicAppendWarnings' -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'Should set the -PipelineVariable to each written file' {
            Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.heic')

            $names = ConvertFrom-Heic -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_*') -PipelineVariable written | ForEach-Object -Process { $written.Name }

            $names | Should -Be @('IMG_0001.jpg', 'IMG_0002.jpg')
        }

        It 'Should accept a variable name that the cmdlet uses internally' {
            $result = ConvertFrom-Heic -Path $script:source -OutVariable convertPipeline

            $result.Name | Should -Be 'IMG_0001.jpg'
            $convertPipeline.Name | Should -Be 'IMG_0001.jpg'
        }
    }

    Context 'When using -WhatIf' {
        It 'Should neither write the file nor create the destination folder' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'whatif'

            $result = ConvertFrom-Heic -Path $script:source -DestinationPath $destination -WhatIf

            $result | Should -BeNullOrEmpty
            $destination | Should -Not -Exist
        }
    }

    Context 'When the parameters are passed on to Convert-Image' {
        It 'Should create the destination folder and write the file into it' {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'out/jpg'

            $result = ConvertFrom-Heic -Path $script:source -DestinationPath $destination

            $result.DirectoryName | Should -Be (Get-Item -LiteralPath $destination).FullName
        }

        It 'Should apply the quality' {
            $high = ConvertFrom-Heic -Path $script:source -Quality 100 -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'high')
            $low = ConvertFrom-Heic -Path $script:source -Quality 10 -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'low')

            $low.Length | Should -BeLessThan $high.Length
        }

        It 'Should write a file without EXIF data with -StripMetadata' {
            $exifSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.heic') -Exif

            $result = ConvertFrom-Heic -Path $exifSource.FullName -StripMetadata

            (Get-ImageInfo -Path $result.FullName).HasExif | Should -BeFalse
        }

        It 'Should pass the EXIF warning on' {
            $exifSource = New-TestImage -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'exif.heic') -Exif

            $null = ConvertFrom-Heic -Path $exifSource.FullName -Format Tiff -WarningAction SilentlyContinue -WarningVariable conversionWarning

            $conversionWarning | Should -HaveCount 1
            "$($conversionWarning[0])" | Should -Match 'EXIF metadata'
        }

        It 'Should name a -Format given in another casing as documented' {
            $output = ConvertFrom-Heic -Path $script:source -Format 'webp' -Verbose 4>&1
            $verbose = @($output | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object -Process { "$_" })

            ($output | Where-Object -FilterScript { $_ -is [System.IO.FileInfo] }).Name | Should -BeExactly 'IMG_0001.webp'
            @($verbose | Where-Object -FilterScript { $_ -clike "*Convert to WebP '*" }) | Should -HaveCount 1
        }
    }

    Context 'When a confirmation cannot be asked' {
        It 'Should write ConfirmationFailed of Convert-Image once per file and convert nothing' {
            $second = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0002.HEIC'
            Copy-Item -LiteralPath $script:fixture -Destination $second
            # A runspace without a user interface, where a confirmation prompt fails.
            $powerShell = [System.Management.Automation.PowerShell]::Create()
            try
            {
                $script = "Import-Module -Name '$($script:manifestPath)'; ConvertFrom-Heic -LiteralPath '$($script:source)', '$second' -Format Png -Confirm"
                $output = $powerShell.AddScript($script).Invoke()
                $errors = @($powerShell.Streams.Error)
            }
            finally
            {
                $powerShell.Dispose()
            }

            $output | Should -BeNullOrEmpty
            $errors | Should -HaveCount 2
            $errors.FullyQualifiedErrorId | Sort-Object -Unique | Should -Be 'ConfirmationFailed,Convert-Image'
            $errors.TargetObject | Should -Be @($script:source, $second)
            Get-ChildItem -Path $script:tempDir.FullName -Filter '*.png' | Should -BeNullOrEmpty
        }
    }

    Context 'When an input path is not a file' {
        It 'Should write InvalidWildcardPattern for a -Path that is not a valid pattern, also when no file of that name exists' {
            $null = ConvertFrom-Heic -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'zz[.heic') -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'InvalidWildcardPattern,ConvertFrom-Heic'
        }

        It 'Should write one UnsupportedProvider error for a pattern that matches several items of another provider' {
            $env:PSIC_HEIC_A = 'a'
            $env:PSIC_HEIC_B = 'b'
            try
            {
                $result = ConvertFrom-Heic -Path 'Env:\PSIC_HEIC_*', $script:source -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            finally
            {
                Remove-Item -Path 'Env:\PSIC_HEIC_A', 'Env:\PSIC_HEIC_B'
            }

            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'UnsupportedProvider,ConvertFrom-Heic'
            $conversionError[0].TargetObject | Should -Be 'Env:\PSIC_HEIC_*'
            $result.Name | Should -Be 'IMG_0001.jpg'
        }
    }

    Context 'When -DestinationPath cannot name a folder' {
        BeforeEach {
            foreach ($name in 'IMG_0002.HEIC', 'IMG_0003.HEIC')
            {
                Copy-Item -Path $script:fixture -Destination (Join-Path -Path $script:tempDir.FullName -ChildPath $name)
            }
            $script:file = Join-Path -Path $script:tempDir.FullName -ChildPath 'file.txt'
            Set-Content -Path $script:file -Value 'x'
        }

        It 'Should stop the call for 3 sources with one terminating <ErrorId> error of ConvertFrom-Heic for <Destination>, WhatIf <WhatIf>' -ForEach @(
            @{ ErrorId = 'DestinationNotDirectory'; Destination = 'file'; WhatIf = $false }
            @{ ErrorId = 'DestinationNotDirectory'; Destination = 'file'; WhatIf = $true }
            @{ ErrorId = 'UnsupportedProvider'; Destination = 'Env:\Pictures'; WhatIf = $false }
            @{ ErrorId = 'InvalidDestinationPath'; Destination = 'NoSuchProvider::C:\out'; WhatIf = $false }
            @{ ErrorId = 'InvalidDestinationPath'; Destination = 'PsicNoSuchDrive:\out'; WhatIf = $false }
            @{ ErrorId = 'InvalidDestinationPath'; Destination = 'nul-character'; WhatIf = $true }
            @{ ErrorId = 'InvalidDestinationPath'; Destination = ' '; WhatIf = $false }
        ) {
            $destinationPath = switch ($Destination)
            {
                'file' { $script:file }
                'nul-character' { Join-Path -Path $script:tempDir.FullName -ChildPath "a`0b" }
                default { $Destination }
            }
            $errorCount = $global:Error.Count
            $result = $null
            $caught = $null

            try
            {
                $result = Get-ChildItem -Path $script:tempDir.FullName -Filter '*.HEIC' | ConvertFrom-Heic -DestinationPath $destinationPath -WhatIf:$WhatIf -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            catch
            {
                $caught = $_
            }

            $caught.FullyQualifiedErrorId | Should -Be "$ErrorId,ConvertFrom-Heic"
            $caught.TargetObject | Should -Be $destinationPath
            $global:Error.Count - $errorCount | Should -Be 1
            $conversionError | Should -HaveCount 1
            $result | Should -BeNullOrEmpty
            Get-ChildItem -Path $script:tempDir.FullName -Recurse -Force | Where-Object -FilterScript { $_.Extension -ne '.HEIC' -and $_.Name -ne 'file.txt' } | Should -BeNullOrEmpty
        }
    }

    Context 'When the caller sets preference variables in its own scope' {
        BeforeAll {
            function Invoke-UserFunction
            {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'A user function that only receives -WhatIf and -Confirm; whether the cmdlet it calls follows them is what the tests check.')]
                [CmdletBinding(SupportsShouldProcess = $true)]
                param ([System.Collections.Hashtable] $Parameters)

                ConvertFrom-Heic @Parameters
            }
        }

        BeforeEach {
            $script:missing = Join-Path -Path $script:tempDir.FullName -ChildPath 'missing.heic'
            $script:target = Join-Path -Path $script:tempDir.FullName -ChildPath 'IMG_0001.jpg'
        }

        It 'Should write nothing when a user function is called with -WhatIf' {
            $result = Invoke-UserFunction -Parameters @{ LiteralPath = $script:source } -WhatIf

            $result | Should -BeNullOrEmpty
            $script:target | Should -Not -Exist
        }

        It 'Should not overwrite an existing file with -Force when a user function is called with -WhatIf' {
            Set-Content -Path $script:target -Value 'existing'

            $null = Invoke-UserFunction -Parameters @{ LiteralPath = $script:source; Force = $true } -WhatIf

            Get-Content -Path $script:target | Should -Be 'existing'
        }

        It 'Should make the first failure terminating with $ErrorActionPreference = ''Stop'' in the calling script' {
            {
                $ErrorActionPreference = 'Stop'
                ConvertFrom-Heic -Path $script:missing, $script:source
            } | Should -Throw -ErrorId 'PathNotFound,ConvertFrom-Heic'

            $script:target | Should -Not -Exist
        }

        It 'Should let an explicit -ErrorAction Continue win over the caller''s $ErrorActionPreference' {
            $outcome = & {
                $ErrorActionPreference = 'Stop'
                $written = ConvertFrom-Heic -Path $script:missing, $script:source -ErrorAction Continue -ErrorVariable conversionError 2>$null

                [PSCustomObject] @{
                    Written = $written
                    Errors  = @($conversionError)
                }
            }

            $outcome.Errors.FullyQualifiedErrorId | Should -Be 'PathNotFound,ConvertFrom-Heic'
            $outcome.Written.FullName | Should -Be $script:target
        }
    }

    Context 'When the session has an alias named Convert-Image' {
        It 'Should still call the module''s Convert-Image' {
            # An alias wins over every function of the same name, in every scope.
            function global:Invoke-PsicHijack
            {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Arguments', Justification = 'Takes every argument the wrapper passes to Convert-Image, so the call binds; the values do not matter.')]
                param ([Parameter(ValueFromRemainingArguments = $true)] $Arguments)

                'hijacked'
            }
            Set-Alias -Name 'Convert-Image' -Value 'Invoke-PsicHijack' -Scope Global
            try
            {
                $result = ConvertFrom-Heic -LiteralPath $script:source
            }
            finally
            {
                Remove-Item -LiteralPath 'Alias:\Convert-Image', 'Function:\Invoke-PsicHijack' -Force
            }

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.Name | Should -Be 'IMG_0001.jpg'
        }
    }

    Context 'When a path uses a PSDrive that the caller created in its own scope' {
        BeforeEach {
            # The module resolves paths in its own session state, which sees only the global drives.
            $script:hint = "drive 'PsicScopeDrive' was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module). Create the drive with New-PSDrive -Scope Global, or use the file system path; the root of the drive is '$($script:tempDir.FullName)'."
        }

        It 'Should write PathNotFound of ConvertFrom-Heic that explains the drive for <Case>' -ForEach @(
            @{ Case = '-Path'; Parameters = @{ Path = 'PsicScopeDrive:\IMG_0001.HEIC' }; Location = $null }
            @{ Case = '-LiteralPath'; Parameters = @{ LiteralPath = 'PsicScopeDrive:\IMG_0001.HEIC' }; Location = $null }
            @{ Case = 'a relative path'; Parameters = @{ Path = 'IMG_0001.HEIC' }; Location = 'PsicScopeDrive:\' }
        ) {
            # Without -Scope Global the drive exists in this It block's scope only, like a drive created in a function.
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
            $errorCount = $global:Error.Count
            if ($Location)
            {
                Push-Location -Path $Location
            }

            # 'PsicScopeDrive:\' on Windows, 'PsicScopeDrive:/' on Linux and macOS.
            $currentLocation = (Get-Location).Path
            try
            {
                $result = ConvertFrom-Heic @Parameters -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            finally
            {
                if ($Location)
                {
                    Pop-Location
                }
            }

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $global:Error.Count - $errorCount | Should -Be 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,ConvertFrom-Heic'
            $conversionError[0].TargetObject | Should -Be @($Parameters.Values)[0]
            $expected = "Cannot resolve the path '$(@($Parameters.Values)[0])': $($script:hint)"
            if ($Location)
            {
                $expected = "Cannot resolve the path '$(@($Parameters.Values)[0])', which is relative to the current location '$currentLocation': $($script:hint)"
            }
            "$($conversionError[0])" | Should -Be $expected

        }

        It 'Should stop the call with one terminating InvalidDestinationPath error of ConvertFrom-Heic that explains the drive' {
            $null = New-PSDrive -Name 'PsicScopeDrive' -PSProvider FileSystem -Root $script:tempDir.FullName
            $errorCount = $global:Error.Count
            $caught = $null

            try
            {
                $null = ConvertFrom-Heic -LiteralPath $script:source -DestinationPath 'PsicScopeDrive:\out'
            }
            catch
            {
                $caught = $_
            }

            $caught.FullyQualifiedErrorId | Should -Be 'InvalidDestinationPath,ConvertFrom-Heic'
            $caught.TargetObject | Should -Be 'PsicScopeDrive:\out'
            "$caught" | Should -Be "The destination path 'PsicScopeDrive:\out' is not valid: $($script:hint)"
            $global:Error.Count - $errorCount | Should -Be 1
        }

        It 'Should use a global drive for -Path and -DestinationPath' {
            $null = New-PSDrive -Name 'PsicGlobalDrive' -PSProvider FileSystem -Root $script:tempDir.FullName -Scope Global
            try
            {
                $result = ConvertFrom-Heic -Path 'PsicGlobalDrive:\IMG_0001.HEIC' -DestinationPath 'PsicGlobalDrive:\out'
            }
            finally
            {
                Remove-PSDrive -Name 'PsicGlobalDrive' -Scope Global
            }

            $result.DirectoryName | Should -Be (Join-Path -Path $script:tempDir.FullName -ChildPath 'out' | Convert-Path)
        }

        It 'Should not convert the files of a global drive that a drive of the caller hides' {
            $globalRoot = New-Item -ItemType Directory -Path (Join-Path -Path $script:tempDir.FullName -ChildPath 'global')
            Copy-Item -LiteralPath $script:source -Destination $globalRoot.FullName
            $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $globalRoot.FullName -Scope Global
            try
            {
                # This It block's drive hides the global one for the test, but not for the module.
                $null = New-PSDrive -Name 'PsicShadowDrive' -PSProvider FileSystem -Root $script:tempDir.FullName

                $result = ConvertFrom-Heic -Path 'PsicShadowDrive:\IMG_0001.HEIC' -ErrorAction SilentlyContinue -ErrorVariable conversionError
            }
            finally
            {
                Remove-PSDrive -Name 'PsicShadowDrive' -Scope Global
            }

            $result | Should -BeNullOrEmpty
            $conversionError | Should -HaveCount 1
            $conversionError[0].FullyQualifiedErrorId | Should -Be 'PathNotFound,ConvertFrom-Heic'
            "$($conversionError[0])" | Should -BeLike "*so the module would use the global drive of that name, whose root is '$($globalRoot.FullName)'.*"
            Join-Path -Path $globalRoot.FullName -ChildPath 'IMG_0001.jpg' | Should -Not -Exist
        }
    }

    Context 'When the output format is Heic' {
        It 'Should stop the call with one terminating HeicEncoderNotAvailable error of ConvertFrom-Heic when the encoder is missing' {
            Mock -ModuleName $script:moduleName -CommandName Get-ImageConverterHeicEncoderStatus -MockWith {
                [PSCustomObject] @{ IsAvailable = $false; Reason = 'No encoder in this test.'; Platform = 'macOS' }
            }
            Mock -ModuleName $script:moduleName -CommandName Read-ImageConverterImage
            $errorCount = $global:Error.Count
            $caught = $null

            try
            {
                $null = ConvertFrom-Heic -Path $script:source -Format Heic -DestinationPath (Join-Path -Path $script:tempDir.FullName -ChildPath 'out')
            }
            catch
            {
                $caught = $_
            }

            $caught.FullyQualifiedErrorId | Should -Be 'HeicEncoderNotAvailable,ConvertFrom-Heic'
            $caught.TargetObject | Should -Be 'Heic'
            "$caught" | Should -BeLike '*No encoder in this test. ImageIO writes HEIC on macOS 10.13 or later*-Format Avif*'
            $global:Error.Count - $errorCount | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName -CommandName Read-ImageConverterImage -Times 0 -Exactly
        }

        It 'Should re-encode a HEIC file into -DestinationPath and refuse to overwrite the source' -Skip:(-not $heicAvailable) {
            $destination = Join-Path -Path $script:tempDir.FullName -ChildPath 'smaller'

            $copy = ConvertFrom-Heic -Path $script:source -Format Heic -Quality 40 -DestinationPath $destination
            $same = ConvertFrom-Heic -LiteralPath $script:source -Format Heic -ErrorAction SilentlyContinue -ErrorVariable conversionError

            $copy.Name | Should -Be 'IMG_0001.heic'
            (Get-ImageInfo -LiteralPath $copy.FullName).Format | Should -Be 'Heic'
            if ($IsLinux)
            {
                # IMG_0001.HEIC and IMG_0001.heic are two files on a case-sensitive file system.
                $same.Name | Should -Be 'IMG_0001.heic'
            }
            else
            {
                $same | Should -BeNullOrEmpty
                $conversionError[0].FullyQualifiedErrorId | Should -Be 'TargetIsSource,Convert-Image'
            }
        }
    }
}
