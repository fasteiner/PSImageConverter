using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace PSImageConverter
{
    /// <summary>
    /// Loads the Magick.Native library of Magick.NET from the module's runtimes folder.
    /// </summary>
    /// <remarks>
    /// Magick.NET's own SetNativeLibraryDirectory only works on Windows, so the module resolves the
    /// native library through this resolver on every platform. .NET accepts one DllImport resolver per
    /// assembly, and the Magick.NET assembly is shared by every runspace of the process, so the
    /// resolver is registered once per process.
    /// </remarks>
    public static class NativeResolver
    {
        private static readonly object Sync = new object();
        private static volatile bool registered;

        /// <summary>
        /// Gets a value indicating whether the resolver has been registered in this process.
        /// </summary>
        public static bool IsRegistered
        {
            get { return registered; }
        }

        /// <summary>
        /// Registers the resolver for the native imports of the Magick.NET assembly. Later calls do nothing.
        /// </summary>
        /// <param name="assembly">The Magick.NET assembly whose native imports are resolved.</param>
        /// <param name="nativePath">The folder that contains the Magick.Native library for the current platform.</param>
        /// <exception cref="ArgumentNullException"><paramref name="assembly"/> is null.</exception>
        /// <exception cref="InvalidOperationException">Another resolver is already set for <paramref name="assembly"/>.</exception>
        public static void Register(Assembly assembly, string nativePath)
        {
            lock (Sync)
            {
                if (registered)
                {
                    return;
                }

                NativeLibrary.SetDllImportResolver(assembly, (name, requestingAssembly, searchPath) =>
                {
                    // Every other import keeps the default probing.
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
