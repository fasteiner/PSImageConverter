function Register-PSHeicNativeResolver
{
    <#
        .SYNOPSIS
        Registers a DllImport resolver that loads Magick.Native from the module folder.

        .DESCRIPTION
        Magick.NET only supports a custom native library directory on Windows. On
        Linux and macOS this registers a NativeLibrary DllImport resolver for the
        Magick.NET assembly, so the Magick.Native library is loaded from the module's
        runtimes folder. The resolver is compiled once per session.

        .PARAMETER Assembly
        The Magick.NET assembly whose native imports should be resolved.

        .PARAMETER NativePath
        The folder that contains the Magick.Native library for the current platform.

        .EXAMPLE
        Register-PSHeicNativeResolver -Assembly ([ImageMagick.MagickImage].Assembly) -NativePath '/opt/PSHeic/lib/runtimes/linux-x64/native'
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

    if (-not ('PSHeic.NativeResolver' -as [System.Type]))
    {
        $source = @'
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace PSHeic
{
    public static class NativeResolver
    {
        private static bool registered;

        public static void Register(Assembly assembly, string nativePath)
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
'@
        Add-Type -TypeDefinition $source -Language CSharp
    }

    [PSHeic.NativeResolver]::Register($Assembly, $NativePath)
}
