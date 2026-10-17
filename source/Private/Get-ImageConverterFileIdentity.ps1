function Get-ImageConverterFileIdentity
{
    <#
        .SYNOPSIS
        Returns a string that identifies a file independently of how its path is spelled.

        .DESCRIPTION
        Returns the volume serial number and file id on Windows, or the device id and inode on
        Linux and macOS, as one string. Two paths that name the same file give the same string,
        also when one of them reaches it through a junction, a symbolic link to a folder, a subst
        or mapped drive, a UNC path, the \\?\ prefix, a short 8.3 name or another letter case on
        a case-insensitive file system. Hard links of one file share the identity. On Linux and
        macOS a symbolic link to a file has an identity of its own, because replacing the link
        does not touch the file it points to. Returns $null when the file does not exist or its
        identity cannot be read; the callers then compare the path strings instead.

        .PARAMETER Path
        The full path of the file whose identity is returned.

        .PARAMETER Platform
        The platform whose API is used, Windows or Unix. Defaults to the current platform.

        .EXAMPLE
        Get-ImageConverterFileIdentity -Path 'C:\Pictures\IMG_1234.jpg'

        Returns e.g. '2c94326c:00000000000000000005000000185ed7'.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [ValidateSet('Windows', 'Unix')]
        [System.String]
        $Platform
    )

    if (-not [System.IO.File]::Exists($Path))
    {
        return $null
    }

    if (-not $PSBoundParameters.ContainsKey('Platform'))
    {
        $Platform = 'Unix'

        if ($IsWindows)
        {
            $Platform = 'Windows'
        }
    }

    if ($Platform -eq 'Unix')
    {
        # pwsh adds UnixStat (the lstat of the path) to the items of the FileSystem provider on Linux and macOS.
        $stat = (Get-ImageConverterFileItem -Path $Path).UnixStat

        if ($null -eq $stat)
        {
            return $null
        }

        return '{0}:{1}' -f $stat.DeviceId, $stat.Inode
    }

    $source = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace PSImageConverter
{
    public static class FileIdentity
    {
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

        private const int FileIdInfoClass = 18;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandleEx(SafeFileHandle file, int informationClass, out FileIdInfo information, int size);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle file, out ByHandleFileInformation information);

        // The 128-bit id of FileIdInfo is unique on ReFS, too; the 64-bit file index is the fallback for
        // file systems without it. On NTFS both give the same value, so the string has one format.
        public static string Get(string path)
        {
            try
            {
                using (SafeFileHandle handle = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
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
                return null;
            }
        }
    }
}
'@
    Add-ImageConverterType -TypeName 'PSImageConverter.FileIdentity' -TypeDefinition $source

    [PSImageConverter.FileIdentity]::Get($Path)
}
