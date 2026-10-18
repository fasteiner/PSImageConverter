using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace PSImageConverter
{
    // Declarations of the classic COM Windows Imaging Component (wincodec.h) used by
    // WicHeicEncoder. .NET COM interop does not inherit vtables between [ComImport] interfaces, so every
    // interface repeats the methods of its base interfaces in vtable order. Methods the encoder never
    // calls keep their slot with a parameterless placeholder signature. DllImport and COM activation
    // bind on the first call, so the declarations cost nothing on Linux and macOS.

    internal static class WicConstants
    {
        internal static readonly Guid ClsidImagingFactory = new Guid("317d06e8-5f24-433d-bdf7-79ce68d8abc2");
        internal static readonly Guid ContainerFormatHeif = new Guid("e1e62521-6787-405b-a339-500715b5763f");
        internal static readonly Guid PixelFormat32bppBGR = new Guid("6fddc324-4e03-4bfe-b185-3d77768dc90e");

        internal const int BitmapEncoderNoCache = 2;
        internal const int StatFlagNoName = 1;

        // WICHeifCompressionOption: HEVC.
        internal const byte HeifCompressionHevc = 2;

        internal const ushort VT_UI1 = 17;
        internal const ushort VT_R4 = 4;
    }

    // PROPVARIANT: vt, three reserved words, then the value. Two pointer-sized fields give the native
    // size (16 bytes in a 32-bit, 24 bytes in a 64-bit process).
    [StructLayout(LayoutKind.Sequential)]
    internal struct PropVariant
    {
        public ushort Type;
        public ushort Reserved1;
        public ushort Reserved2;
        public ushort Reserved3;
        public IntPtr Value;
        public IntPtr Value2;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PropBag2
    {
        public int Type;
        public ushort VarType;
        public ushort ClipboardFormat;
        public int Hint;
        public IntPtr Name;
        public Guid Clsid;
    }

    [ComImport, Guid("ec5ec8a9-c395-4314-9c77-54d7a935ff70"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IWICImagingFactory
    {
        [PreserveSig] int CreateDecoderFromFilename();
        [PreserveSig] int CreateDecoderFromStream();
        [PreserveSig] int CreateDecoderFromFileHandle();
        [PreserveSig] int CreateComponentInfo();
        [PreserveSig] int CreateDecoder();
        [PreserveSig] int CreateEncoder(ref Guid containerFormat, IntPtr vendor, out IWICBitmapEncoder encoder);
        [PreserveSig] int CreatePalette();
        [PreserveSig] int CreateFormatConverter();
        [PreserveSig] int CreateBitmapScaler();
        [PreserveSig] int CreateBitmapClipper();
        [PreserveSig] int CreateBitmapFlipRotator();
        [PreserveSig] int CreateStream();
        [PreserveSig] int CreateColorContext(out IWICColorContext context);
        [PreserveSig] int CreateColorTransformer();
        [PreserveSig] int CreateBitmap();
        [PreserveSig] int CreateBitmapFromSource();
        [PreserveSig] int CreateBitmapFromSourceRect();
        [PreserveSig] int CreateBitmapFromMemory();
        [PreserveSig] int CreateBitmapFromHBITMAP();
        [PreserveSig] int CreateBitmapFromHICON();
        [PreserveSig] int CreateComponentEnumerator();
        [PreserveSig] int CreateFastMetadataEncoderFromDecoder();
        [PreserveSig] int CreateFastMetadataEncoderFromFrameDecode();
        [PreserveSig] int CreateQueryWriter();
        [PreserveSig] int CreateQueryWriterFromReader();
    }

    [ComImport, Guid("00000103-a8f2-4877-ba0a-fd2b6645fb94"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IWICBitmapEncoder
    {
        [PreserveSig] int Initialize(IStream stream, int cacheOption);
        [PreserveSig] int GetContainerFormat(out Guid containerFormat);
        [PreserveSig] int GetEncoderInfo();
        [PreserveSig] int SetColorContexts();
        [PreserveSig] int SetPalette();
        [PreserveSig] int SetThumbnail();
        [PreserveSig] int SetPreview();
        [PreserveSig] int CreateNewFrame(out IWICBitmapFrameEncode frame, out IPropertyBag2 options);
        [PreserveSig] int Commit();
        [PreserveSig] int GetMetadataQueryWriter();
    }

    [ComImport, Guid("00000105-a8f2-4877-ba0a-fd2b6645fb94"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IWICBitmapFrameEncode
    {
        [PreserveSig] int Initialize(IPropertyBag2 options);
        [PreserveSig] int SetSize(int width, int height);
        [PreserveSig] int SetResolution(double dpiX, double dpiY);
        [PreserveSig] int SetPixelFormat(ref Guid pixelFormat);
        [PreserveSig] int SetColorContexts(int count, [MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 0)] IWICColorContext[] contexts);
        [PreserveSig] int SetPalette();
        [PreserveSig] int SetThumbnail();
        [PreserveSig] int WritePixels(int lineCount, int stride, int bufferSize, IntPtr pixels);
        [PreserveSig] int WriteSource();
        [PreserveSig] int Commit();
        [PreserveSig] int GetMetadataQueryWriter();
    }

    [ComImport, Guid("22F55882-280B-11d0-A8A9-00A0C90C2004"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyBag2
    {
        [PreserveSig] int Read();
        [PreserveSig] int Write(int count, ref PropBag2 propBag, ref PropVariant value);
        [PreserveSig] int CountProperties();
        [PreserveSig] int GetPropertyInfo();
        [PreserveSig] int LoadObject();
    }

    [ComImport, Guid("3C613A02-34B2-44EA-9A7C-45AEA9C6FD6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IWICColorContext
    {
        [PreserveSig] int InitializeFromFilename();
        [PreserveSig] int InitializeFromMemory([MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 1)] byte[] buffer, int size);
        [PreserveSig] int InitializeFromExifColorSpace();
        [PreserveSig] int GetContextType();
        [PreserveSig] int GetProfileBytes();
        [PreserveSig] int GetExifColorSpace();
    }

    internal static class WicNativeMethods
    {
        [DllImport("ole32.dll", ExactSpelling = true)]
        internal static extern int CreateStreamOnHGlobal(IntPtr global, [MarshalAs(UnmanagedType.Bool)] bool deleteOnRelease, out IStream stream);
    }
}
