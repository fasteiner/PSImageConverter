BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName

    # Runs the check from a named advanced function, as the public cmdlets do, and catches its terminating error.
    function Invoke-Assert
    {
        param ([System.String] $Format)

        InModuleScope -ModuleName $script:moduleName -Parameters @{ Format = $Format } {
            function Test-ImageConverterCaller
            {
                [CmdletBinding()]
                [OutputType([System.String])]
                param ([System.String] $Format)

                Assert-ImageConverterHeicEncoder -Cmdlet $PSCmdlet -Format $Format
                'continued'
            }

            $errorCount = $global:Error.Count
            $output = $null
            $caught = $null
            try
            {
                $output = Test-ImageConverterCaller -Format $Format
            }
            catch
            {
                $caught = $_
            }

            [PSCustomObject] @{
                Output     = $output
                Error      = $caught
                ErrorCount = $global:Error.Count - $errorCount
            }
        }
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Assert-ImageConverterHeicEncoder' {
    BeforeEach {
        Mock -ModuleName $script:moduleName -CommandName Get-ImageConverterHeicEncoderStatus -MockWith {
            [PSCustomObject] @{ IsAvailable = $true; Reason = $null; Platform = 'Windows' }
        }
    }

    It 'Should not probe the encoder for <Format> output' -ForEach @(
        @{ Format = 'Jpeg' }
        @{ Format = 'Avif' }
    ) {
        $result = Invoke-Assert -Format $Format

        $result.Error | Should -BeNullOrEmpty
        $result.Output | Should -Be 'continued'
        Should -Invoke -ModuleName $script:moduleName -CommandName Get-ImageConverterHeicEncoderStatus -Times 0 -Exactly
    }

    It 'Should let the call go on when the encoder works' {
        $result = Invoke-Assert -Format 'Heic'

        $result.Error | Should -BeNullOrEmpty
        $result.Output | Should -Be 'continued'
        Should -Invoke -ModuleName $script:moduleName -CommandName Get-ImageConverterHeicEncoderStatus -Times 1 -Exactly
    }

    It 'Should stop the call with one terminating HeicEncoderNotAvailable error that says what to install on <Platform>' -ForEach @(
        @{
            Platform = 'Windows'
            Reason   = 'Windows has no HEIF encoder: WIC CreateEncoder failed with HRESULT 0x88982F50 (The component cannot be found).'
            Advice   = "Install the 'HEVC Video Extensions' from the Microsoft Store (Windows 10 1809 or later, ms-windows-store://pdp/?ProductId=9NMZLZ57R3T7), and the 'HEIF Image Extension' (ms-windows-store://pdp/?ProductId=9PMMSR1CGPWG) if it is missing too, then start a new PowerShell session."
        }
        @{
            Platform = 'Linux'
            Reason   = 'libheif 1.17.6 has no HEVC encoder (Unsupported file-type: Unspecified (code 3, subcode 0)).'
            Advice   = "Install libheif with its HEVC encoder x265, e.g. 'sudo apt install libheif1 libheif-plugin-x265' on Ubuntu 24.04 and 26.04 and Debian 13 ('sudo apt install libheif1' on Ubuntu 22.04 and Debian 12; for Fedora, Arch and Alpine see 'Get-Help about_PSImageConverter'), then start a new PowerShell session."
        }
        @{
            Platform = 'macOS'
            Reason   = "ImageIO cannot write HEIC on this Mac (CGImageDestinationCreateWithData returned NULL for 'public.heic')."
            Advice   = 'ImageIO writes HEIC on macOS 10.13 or later, on a Mac that provides an HEVC encoder; virtual machines often have none.'
        }
    ) {
        $script:status = [PSCustomObject] @{ IsAvailable = $false; Reason = $Reason; Platform = $Platform }
        Mock -ModuleName $script:moduleName -CommandName Get-ImageConverterHeicEncoderStatus -MockWith { $script:status }

        $result = Invoke-Assert -Format 'Heic'

        $result.Output | Should -BeNullOrEmpty
        $result.ErrorCount | Should -Be 1
        $result.Error.FullyQualifiedErrorId | Should -Be 'HeicEncoderNotAvailable,Test-ImageConverterCaller'
        $result.Error.CategoryInfo.Category | Should -Be 'NotInstalled'
        $result.Error.TargetObject | Should -Be 'Heic'
        $result.Error.Exception | Should -BeOfType [System.PlatformNotSupportedException]
        "$($result.Error)" | Should -BeExactly "HEIC cannot be written on this computer: the module uses the HEVC encoder of the operating system and ships none of its own. $Reason $Advice Or use -Format Avif, which stores the image in the same HEIF container with the royalty-free AV1 codec and needs nothing installed."
    }
}
