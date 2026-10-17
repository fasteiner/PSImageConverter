function Initialize-PSHeicMagickNet
{
    <#
        .SYNOPSIS
        Loads the bundled Magick.NET assemblies and wires up the native library.

        .DESCRIPTION
        Loads Magick.NET.Core and Magick.NET-Q8-AnyCPU from the module's lib folder
        and makes sure the platform specific Magick.Native library is found: on
        Windows via SetNativeLibraryDirectory, on Linux and macOS via a DllImport
        resolver. Does nothing when Magick.NET is already loaded in the session.

        .PARAMETER LibraryPath
        The folder that contains the Magick.NET assemblies and the runtimes folder.

        .EXAMPLE
        Initialize-PSHeicMagickNet -LibraryPath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $LibraryPath
    )

    if ('ImageMagick.MagickImage' -as [System.Type])
    {
        Write-Verbose -Message 'Magick.NET is already loaded in this session.'
        return
    }

    $runtimeIdentifier = Get-PSHeicRuntimeIdentifier
    $nativePath = Join-Path -Path $LibraryPath -ChildPath "runtimes/$runtimeIdentifier/native"

    if (-not (Test-Path -Path $nativePath))
    {
        throw "The Magick.NET native library for '$runtimeIdentifier' was not found in '$nativePath'."
    }

    Add-Type -Path (Join-Path -Path $LibraryPath -ChildPath 'Magick.NET.Core.dll')
    Add-Type -Path (Join-Path -Path $LibraryPath -ChildPath 'Magick.NET-Q8-AnyCPU.dll')

    if ($runtimeIdentifier -like 'win-*')
    {
        [ImageMagick.MagickNET]::SetNativeLibraryDirectory($nativePath)
    }
    else
    {
        Register-PSHeicNativeResolver -Assembly ([ImageMagick.MagickImage].Assembly) -NativePath $nativePath
    }
}
