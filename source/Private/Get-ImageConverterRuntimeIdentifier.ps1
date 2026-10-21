function Get-ImageConverterRuntimeIdentifier
{
    <#
        .SYNOPSIS
        Returns the .NET runtime identifier (RID) for the current platform.

        .DESCRIPTION
        Maps platform, process architecture and C library flavour to the runtime
        identifier used by the Magick.NET package layout (runtimes/<rid>/native),
        for example win-x64, linux-arm64, linux-musl-x64 or osx-arm64. Throws for
        combinations Magick.NET does not ship a native library for.

        .PARAMETER Platform
        The operating system platform. Defaults to the platform of the current session.

        .PARAMETER Architecture
        The process architecture. Defaults to the architecture of the current process.

        .PARAMETER IsMusl
        Indicates a Linux distribution based on the musl C library (e.g. Alpine).

        .EXAMPLE
        Get-ImageConverterRuntimeIdentifier -Platform Linux -Architecture Arm64
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter()]
        [ValidateSet('Windows', 'Linux', 'OSX')]
        [System.String]
        $Platform,

        [Parameter()]
        [ValidateSet('X64', 'Arm64', 'X86')]
        [System.String]
        $Architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString(),

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $IsMusl = (Test-Path -Path '/etc/alpine-release')
    )

    if (-not $PSBoundParameters.ContainsKey('Platform'))
    {
        if ($IsWindows)
        {
            $Platform = 'Windows'
        }
        elseif ($IsMacOS)
        {
            $Platform = 'OSX'
        }
        else
        {
            $Platform = 'Linux'
        }
    }

    if ($Architecture -eq 'X86')
    {
        throw '32-bit processes are not supported by PSImageConverter. Please use a 64-bit PowerShell.'
    }

    $arch = $Architecture.ToLowerInvariant()

    switch ($Platform)
    {
        'Windows'
        {
            return "win-$arch"
        }

        'OSX'
        {
            return "osx-$arch"
        }

        'Linux'
        {
            if ($IsMusl)
            {
                if ($arch -ne 'x64')
                {
                    throw "Magick.NET does not ship a native library for linux-musl-$arch."
                }

                return 'linux-musl-x64'
            }

            return "linux-$arch"
        }
    }
}
