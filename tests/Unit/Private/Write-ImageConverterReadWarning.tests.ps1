BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    # Runs Write-ImageConverterReadWarning from an advanced script block, which provides the -Cmdlet it writes through.
    function Invoke-ReadWarning
    {
        param ([System.String] $Path, [System.Object[]] $Warning)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ WarningPath = $Path; ReadWarning = $Warning } {
            $writtenWarnings = $null

            $verbose = & {
                [CmdletBinding()]
                param ()

                Write-ImageConverterReadWarning -Cmdlet $PSCmdlet -Path $WarningPath -Warning $ReadWarning
            } -WarningAction SilentlyContinue -WarningVariable writtenWarnings -Verbose 4>&1

            [PSCustomObject] @{
                Warnings = @($writtenWarnings | ForEach-Object -Process { "$_" })
                Verbose  = @($verbose | ForEach-Object -Process { "$_" })
            }
        }
    }

    # Magick.NET attaches the other warnings of a read to the one it raises; the setter is internal.
    function Add-RelatedException
    {
        param ([ImageMagick.MagickException] $Exception, [ImageMagick.MagickException[]] $Related)

        $list = [System.Collections.Generic.List[ImageMagick.MagickException]]::new([ImageMagick.MagickException[]] $Related)
        $method = [ImageMagick.MagickException].GetMethod('SetRelatedException', [System.Reflection.BindingFlags] 'Public, NonPublic, Instance')
        $null = $method.Invoke($Exception, @(, $list))
        $Exception
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Write-ImageConverterReadWarning' {
    It 'Should write nothing when there are no warnings' {
        $result = Invoke-ReadWarning -Path 'C:\Pictures\clean.jpg' -Warning @()

        $result.Warnings | Should -BeNullOrEmpty
        $result.Verbose | Should -BeNullOrEmpty
    }

    It 'Should write one warning per source with every distinct damage message once, without file name and code location' {
        $warnings = @(
            [ImageMagick.MagickCorruptImageWarningException]::new("Corrupt JPEG data: premature end of data segment ``/photos/cut.jpg' @ warning/jpeg.c/JPEGWarningHandler/669")
            [ImageMagick.MagickCorruptImageWarningException]::new("Premature end of JPEG file ``/photos/cut.jpg' @ warning/jpeg.c/JPEGWarningHandler/669")
            [ImageMagick.MagickCorruptImageWarningException]::new("Premature end of JPEG file ``/photos/cut.jpg' @ warning/jpeg.c/JPEGWarningHandler/669")
        )

        $result = Invoke-ReadWarning -Path '/photos/cut.jpg' -Warning $warnings

        $result.Warnings | Should -Be @('The image may be damaged (Corrupt JPEG data: premature end of data segment; Premature end of JPEG file): /photos/cut.jpg')
        $result.Verbose | Should -BeNullOrEmpty
    }

    It 'Should take a message without file name, as ImageMagick writes it for a stream' {
        $warnings = @([ImageMagick.MagickCorruptImageWarningException]::new("Premature end of JPEG file ``' @ warning/jpeg.c/JPEGWarningHandler/669"))

        $result = Invoke-ReadWarning -Path '/photos/cut[1]' -Warning $warnings

        $result.Warnings | Should -Be @('The image may be damaged (Premature end of JPEG file): /photos/cut[1]')
    }

    It 'Should write other warnings only to the verbose stream, each distinct message once' {
        $warnings = @(
            [ImageMagick.MagickCoderWarningException]::new("iCCP: known incorrect sRGB profile ``/photos/logo.png' @ warning/png.c/MagickPNGWarningHandler/1526")
            [ImageMagick.MagickCoderWarningException]::new("iCCP: known incorrect sRGB profile ``/photos/logo.png' @ warning/png.c/MagickPNGWarningHandler/1526")
        )

        $result = Invoke-ReadWarning -Path '/photos/logo.png' -Warning $warnings

        $result.Warnings | Should -BeNullOrEmpty
        $result.Verbose | Should -Be @("ImageMagick warning while reading '/photos/logo.png': iCCP: known incorrect sRGB profile")
    }

    It 'Should report damage and other warnings of one source separately' {
        $warnings = @(
            [ImageMagick.MagickCoderWarningException]::new("tEXt: CRC error ``/photos/a.png' @ warning/png.c/MagickPNGWarningHandler/1526")
            [ImageMagick.MagickCorruptImageWarningException]::new("Premature end of JPEG file ``/photos/a.png' @ warning/jpeg.c/JPEGWarningHandler/669")
        )

        $result = Invoke-ReadWarning -Path '/photos/a.png' -Warning $warnings

        $result.Warnings | Should -Be @('The image may be damaged (Premature end of JPEG file): /photos/a.png')
        $result.Verbose | Should -Be @("ImageMagick warning while reading '/photos/a.png': tEXt: CRC error")
    }

    It 'Should list the related warnings Magick.NET attaches to the warning it raises' {
        $raised = [ImageMagick.MagickCorruptImageWarningException]::new("Corrupt JPEG data: 4 extraneous bytes before marker 0xda ``/photos/cut.jpg' @ warning/jpeg.c/JPEGWarningHandler/669")
        $related = @(
            [ImageMagick.MagickCorruptImageWarningException]::new("Premature end of JPEG file ``/photos/cut.jpg' @ warning/jpeg.c/JPEGWarningHandler/669")
            [ImageMagick.MagickCorruptImageWarningException]::new("Corrupt JPEG data: 4 extraneous bytes before marker 0xda ``/photos/cut.jpg' @ warning/jpeg.c/JPEGWarningHandler/669")
        )

        $result = Invoke-ReadWarning -Path '/photos/cut.jpg' -Warning @(Add-RelatedException -Exception $raised -Related $related)

        $result.Warnings | Should -Be @('The image may be damaged (Corrupt JPEG data: 4 extraneous bytes before marker 0xda; Premature end of JPEG file): /photos/cut.jpg')
    }

    It 'Should write the damage warning when a warning of higher severity carries the damage as related warning' {
        $raised = [ImageMagick.MagickCoderWarningException]::new("tEXt: CRC error ``/photos/a.png' @ warning/png.c/MagickPNGWarningHandler/1526")
        $related = @([ImageMagick.MagickCorruptImageWarningException]::new("Premature end of JPEG file ``/photos/a.png' @ warning/jpeg.c/JPEGWarningHandler/669"))

        $result = Invoke-ReadWarning -Path '/photos/a.png' -Warning @(Add-RelatedException -Exception $raised -Related $related)

        $result.Warnings | Should -Be @('The image may be damaged (Premature end of JPEG file): /photos/a.png')
        $result.Verbose | Should -Be @("ImageMagick warning while reading '/photos/a.png': tEXt: CRC error")
    }

    It 'Should report a MagickCorruptImageErrorException of the frame count as damage' {
        $countError = [ImageMagick.MagickCorruptImageErrorException]::new("corrupt image ``/photos/anim.gif' @ error/gif.c/PingGIFImage/1032")

        $result = Invoke-ReadWarning -Path '/photos/anim.gif' -Warning @($countError)

        $result.Warnings | Should -Be @('The image may be damaged (corrupt image): /photos/anim.gif')
    }

    It 'Should list every message of a real truncated JPEG' {
        . (Join-Path -Path $PSScriptRoot -ChildPath '../../Helpers/New-TestImage.ps1')
        $tempDir = New-Item -ItemType Directory -Path (Join-Path -Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) -ChildPath ([System.Guid]::NewGuid().ToString()))
        try
        {
            $damaged = New-TestDamagedJpeg -Path (Join-Path -Path $tempDir.FullName -ChildPath 'cut.jpg') -Keep 0.6
            $read = InModuleScope -ModuleName $script:moduleName -Parameters @{ ImagePath = $damaged.FullName } {
                Read-ImageConverterImage -Path $ImagePath
            }
            $read.Result.Dispose()

            $result = Invoke-ReadWarning -Path $damaged.FullName -Warning $read.Warnings

            $read.Warnings | Should -HaveCount 1 -Because 'Magick.NET raises one warning per read'
            $result.Warnings | Should -Be @("The image may be damaged (Premature end of JPEG file; Corrupt JPEG data: premature end of data segment): $($damaged.FullName)")
        }
        finally
        {
            Remove-Item -LiteralPath $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
