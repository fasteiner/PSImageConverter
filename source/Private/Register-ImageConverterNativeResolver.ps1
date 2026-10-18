function Register-ImageConverterNativeResolver
{
    <#
        .SYNOPSIS
        Registers a DllImport resolver that loads Magick.Native from the module folder.

        .DESCRIPTION
        Registers a NativeLibrary DllImport resolver for the Magick.NET assembly, so
        the Magick.Native library is loaded from the module's runtimes folder on every
        platform. Magick.NET's own SetNativeLibraryDirectory only works on Windows.
        The resolver is compiled once per process and registered only once.

        .PARAMETER Assembly
        The Magick.NET assembly whose native imports should be resolved.

        .PARAMETER NativePath
        The folder that contains the Magick.Native library for the current platform.

        .EXAMPLE
        Register-ImageConverterNativeResolver -Assembly ([ImageMagick.MagickImage].Assembly) -NativePath '/opt/PSImageConverter/lib/runtimes/linux-x64/native'
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Reflection.Assembly]
        $Assembly,

        [Parameter(Mandatory = $true)]
        [System.String]
        $NativePath
    )

    if (-not ('PSImageConverter.NativeResolver' -as [System.Type]))
    {
        $source = @'
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace PSImageConverter
{
    public static class NativeResolver
    {
        private static readonly object sync = new object();
        private static volatile bool registered;

        public static bool IsRegistered
        {
            get { return registered; }
        }

        public static void Register(Assembly assembly, string nativePath)
        {
            lock (sync)
            {
                if (registered)
                {
                    return;
                }

                NativeLibrary.SetDllImportResolver(assembly, (name, requestingAssembly, searchPath) =>
                {
                    if (!name.StartsWith("Magick.Native", StringComparison.Ordinal))
                    {
                        return IntPtr.Zero;
                    }

                    foreach (string candidate in new[] { name, name + ".so", name + ".dylib" })
                    {
                        string fullPath = Path.Combine(nativePath, candidate);
                        if (File.Exists(fullPath))
                        {
                            return NativeLibrary.Load(fullPath);
                        }
                    }

                    return IntPtr.Zero;
                });

                registered = true;
            }
        }
    }
}
'@
        Add-Type -TypeDefinition $source -Language CSharp
    }

    [PSImageConverter.NativeResolver]::Register($Assembly, $NativePath)
}
