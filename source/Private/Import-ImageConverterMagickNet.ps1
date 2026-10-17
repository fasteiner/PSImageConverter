function Import-ImageConverterMagickNet
{
    <#
        .SYNOPSIS
        Loads the Magick.NET assemblies and registers the resolver for Magick.Native.

        .DESCRIPTION
        Loads Magick.NET.Core and Magick.NET-Q8-AnyCPU from the given lib folder and
        registers a DllImport resolver, so the Magick.Native library for the current
        platform is loaded from the runtimes folder. Throws when the lib folder has no
        native library for the current platform. Calling it again is harmless: the
        assemblies are already loaded and the resolver is only registered once.

        .PARAMETER LibraryPath
        The folder that contains the Magick.NET assemblies and the runtimes folder.

        .EXAMPLE
        Import-ImageConverterMagickNet -LibraryPath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $LibraryPath
    )

    $runtimeIdentifier = Get-ImageConverterRuntimeIdentifier
    $nativePath = Join-Path -Path $LibraryPath -ChildPath "runtimes/$runtimeIdentifier/native"

    if (-not (Test-Path -LiteralPath $nativePath))
    {
        throw "The Magick.NET native library for '$runtimeIdentifier' was not found in '$nativePath'."
    }

    Add-Type -LiteralPath (Join-Path -Path $LibraryPath -ChildPath 'Magick.NET.Core.dll')
    Add-Type -LiteralPath (Join-Path -Path $LibraryPath -ChildPath 'Magick.NET-Q8-AnyCPU.dll')

    Register-ImageConverterNativeResolver -Assembly ([ImageMagick.MagickImage].Assembly) -NativePath $nativePath
}
