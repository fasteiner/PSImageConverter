using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace PSImageConverter
{
    /// <summary>
    /// Reads the identity of a file on Windows: the volume serial number and the file id.
    /// </summary>
    /// <remarks>
    /// Two paths that name the same file give the same identity, also through a junction, a symbolic link
    /// to a folder, a subst or mapped drive, a UNC path, the \\?\ prefix or a short 8.3 name.
    /// Get-ImageConverterFileIdentity uses this class on Windows and the inode on Linux and macOS.
    /// </remarks>
    public static class FileIdentity
    {
        private const int FileIdInfoClass = 18;

        /// <summary>
        /// Returns the identity of a file as "&lt;volume serial, 8 hex digits&gt;:&lt;file id, 32 hex digits&gt;".
        /// </summary>
        /// <param name="path">The full path of the file.</param>
        /// <returns>The identity, or null when the file cannot be opened or its identity cannot be read, also on other platforms than Windows.</returns>
        public static string Get(string path)
        {
            try
            {
                using (SafeFileHandle handle = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    // The 128-bit id of FileIdInfo is unique on ReFS, too; the 64-bit file index is the fallback for
                    // file systems without it. On NTFS both give the same value, so the string has one format.
                    FileIdInfo id;
                    if (GetFileInformationByHandleEx(handle, FileIdInfoClass, out id, Marshal.SizeOf(typeof(FileIdInfo))))
                    {
                        return string.Format("{0:x8}:{1:x16}{2:x16}", (uint)id.VolumeSerialNumber, id.FileIdHigh, id.FileIdLow);
                    }

                    ByHandleFileInformation information;
                    if (GetFileInformationByHandle(handle, out information))
                    {
                        ulong index = ((ulong)information.FileIndexHigh << 32) | information.FileIndexLow;
                        return string.Format("{0:x8}:{1:x16}{2:x16}", information.VolumeSerialNumber, 0UL, index);
                    }

                    return null;
                }
            }
            catch (Exception)
            {
                // Also DllNotFoundException and EntryPointNotFoundException outside Windows.
                return null;
            }
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandleEx(SafeFileHandle file, int informationClass, out FileIdInfo information, int size);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle file, out ByHandleFileInformation information);

        [StructLayout(LayoutKind.Sequential)]
        private struct FileIdInfo
        {
            public ulong VolumeSerialNumber;
            public ulong FileIdLow;
            public ulong FileIdHigh;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ByHandleFileInformation
        {
            public uint FileAttributes;
            public uint CreationTimeLow;
            public uint CreationTimeHigh;
            public uint LastAccessTimeLow;
            public uint LastAccessTimeHigh;
            public uint LastWriteTimeLow;
            public uint LastWriteTimeHigh;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }
    }
}
