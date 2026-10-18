using System;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;
using System.Threading;

namespace PSImageConverter
{
    /// <summary>
    /// P/Invoke declarations for the CoreFoundation, CoreGraphics and ImageIO functions of the macOS
    /// HEIC encoder.
    /// </summary>
    /// <remarks>
    /// The frameworks are named by absolute path, as .NET's own interop does: since macOS 11 the
    /// framework binaries exist only in the dyld shared cache, which dlopen still finds by that path.
    /// DllImport binds on the first call, so the declarations cost nothing on Windows and Linux. The
    /// signatures use blittable types only: CFIndex (signed long) is nint, size_t is nuint, C bool and
    /// CF Boolean (unsigned char) are byte, CGBitmapInfo is uint32_t, CGColorRenderingIntent is int32_t
    /// and CFNumberType is a CFIndex enum (nint; an int would leave the upper half of the register
    /// undefined on arm64). No structure is passed by value.
    /// </remarks>
    [SupportedOSPlatform("macos")]
    internal static class ImageIONative
    {
        internal const string CoreFoundationLibrary = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
        internal const string CoreGraphicsLibrary = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics";
        internal const string ImageIOLibrary = "/System/Library/Frameworks/ImageIO.framework/ImageIO";

        // Values from the macOS SDK headers (CFString.h, CFNumber.h, CGImage.h, CGColorSpace.h).
        internal const uint KCFStringEncodingUTF8 = 0x08000100;
        internal const nint KCFNumberDoubleType = 13;
        internal const uint KCGImageAlphaLast = 3;
        internal const uint KCGImageAlphaNoneSkipLast = 5;
        internal const uint KCGBitmapByteOrderDefault = 0;
        internal const int KCGRenderingIntentDefault = 0;

        [DllImport(CoreFoundationLibrary)]
        internal static extern void CFRelease(IntPtr cf);

        [DllImport(CoreFoundationLibrary)]
        internal static extern IntPtr CFDataCreate(IntPtr allocator, byte[] bytes, nint length);

        [DllImport(CoreFoundationLibrary)]
        internal static extern IntPtr CFDataCreateMutable(IntPtr allocator, nint capacity);

        [DllImport(CoreFoundationLibrary)]
        internal static extern nint CFDataGetLength(IntPtr theData);

        [DllImport(CoreFoundationLibrary)]
        internal static extern IntPtr CFDataGetBytePtr(IntPtr theData);

        [DllImport(CoreFoundationLibrary)]
        internal static extern IntPtr CFNumberCreate(IntPtr allocator, nint theType, ref double valuePtr);

        [DllImport(CoreFoundationLibrary)]
        internal static extern IntPtr CFDictionaryCreate(IntPtr allocator, IntPtr[] keys, IntPtr[] values, nint numValues, IntPtr keyCallBacks, IntPtr valueCallBacks);

        [DllImport(CoreFoundationLibrary)]
        internal static extern IntPtr CFStringCreateWithCString(IntPtr alloc, byte[] cStr, uint encoding);

        [DllImport(CoreGraphicsLibrary)]
        internal static extern IntPtr CGDataProviderCreateWithCFData(IntPtr data);

        [DllImport(CoreGraphicsLibrary)]
        internal static extern void CGDataProviderRelease(IntPtr provider);

        [DllImport(CoreGraphicsLibrary)]
        internal static extern IntPtr CGColorSpaceCreateWithICCData(IntPtr data);

        [DllImport(CoreGraphicsLibrary)]
        internal static extern IntPtr CGColorSpaceCreateWithName(IntPtr name);

        [DllImport(CoreGraphicsLibrary)]
        internal static extern nuint CGColorSpaceGetNumberOfComponents(IntPtr space);

        [DllImport(CoreGraphicsLibrary)]
        internal static extern void CGColorSpaceRelease(IntPtr space);

        // Eleven arguments: the last three go on the stack. On Apple arm64 stack arguments are packed to
        // their natural size (decode at +0, shouldInterpolate at +8, intent at +12), which CoreCLR
        // implements (OSX_ARM64_ABI in callingconvention.h).
        [DllImport(CoreGraphicsLibrary)]
        internal static extern IntPtr CGImageCreate(nuint width, nuint height, nuint bitsPerComponent, nuint bitsPerPixel, nuint bytesPerRow, IntPtr space, uint bitmapInfo, IntPtr provider, IntPtr decode, byte shouldInterpolate, int intent);

        [DllImport(CoreGraphicsLibrary)]
        internal static extern void CGImageRelease(IntPtr image);

        [DllImport(ImageIOLibrary)]
        internal static extern IntPtr CGImageDestinationCreateWithData(IntPtr data, IntPtr type, nuint count, IntPtr options);

        [DllImport(ImageIOLibrary)]
        internal static extern void CGImageDestinationAddImage(IntPtr idst, IntPtr image, IntPtr properties);

        [DllImport(ImageIOLibrary)]
        internal static extern byte CGImageDestinationFinalize(IntPtr idst);

        // CFRelease(NULL) ends the process; the CG*Release functions accept NULL.
        internal static void Release(ref IntPtr cf)
        {
            if (cf != IntPtr.Zero)
            {
                CFRelease(cf);
                cf = IntPtr.Zero;
            }
        }

        // Create rule: the caller releases the CFData, which holds a copy of the bytes.
        internal static IntPtr CreateData(byte[] bytes)
        {
            IntPtr data = CFDataCreate(IntPtr.Zero, bytes, bytes.Length);
            if (data == IntPtr.Zero)
            {
                throw new OutOfMemoryException("CFDataCreate returned NULL.");
            }

            return data;
        }

        internal static byte[] CopyBytes(IntPtr data)
        {
            long length = CFDataGetLength(data);
            if (length > Array.MaxLength)
            {
                throw new HeicEncoderException(string.Format("The encoded image ({0} bytes) is larger than a .NET array can hold.", length));
            }

            byte[] bytes = new byte[length];
            if (length > 0)
            {
                Marshal.Copy(CFDataGetBytePtr(data), bytes, 0, (int)length);
            }

            return bytes;
        }

        // Create rule: the caller releases the CFString.
        internal static IntPtr CreateString(string value)
        {
            IntPtr cfString = CFStringCreateWithCString(IntPtr.Zero, Encoding.UTF8.GetBytes(value + "\0"), KCFStringEncodingUTF8);
            if (cfString == IntPtr.Zero)
            {
                throw new OutOfMemoryException("CFStringCreateWithCString returned NULL.");
            }

            return cfString;
        }

        // Create rule: the caller releases the CFNumber.
        internal static IntPtr CreateNumber(double value)
        {
            IntPtr number = CFNumberCreate(IntPtr.Zero, KCFNumberDoubleType, ref value);
            if (number == IntPtr.Zero)
            {
                throw new OutOfMemoryException("CFNumberCreate returned NULL.");
            }

            return number;
        }

        // The dictionary retains its keys and values, so the caller may release its own references
        // right after this call.
        internal static IntPtr CreateDictionary(IntPtr[] keys, IntPtr[] values)
        {
            ImageIOConstants constants = ImageIOConstants.Instance;
            IntPtr dictionary = CFDictionaryCreate(IntPtr.Zero, keys, values, keys.Length, constants.TypeDictionaryKeyCallBacks, constants.TypeDictionaryValueCallBacks);
            if (dictionary == IntPtr.Zero)
            {
                throw new OutOfMemoryException("CFDictionaryCreate returned NULL.");
            }

            return dictionary;
        }
    }

    /// <summary>
    /// The exported constants of CoreFoundation, CoreGraphics and ImageIO, read once per process.
    /// </summary>
    /// <remarks>
    /// A CFStringRef constant such as kCGImageDestinationLossyCompressionQuality is a global variable
    /// that holds the string pointer: GetExport returns the variable's address, which is read with
    /// Marshal.ReadIntPtr. kCFTypeDictionaryKeyCallBacks and kCFTypeDictionaryValueCallBacks are
    /// structures whose address CFDictionaryCreate takes, so the export address itself is used. The
    /// frameworks stay loaded for the process, and the constants belong to them and are never released.
    /// </remarks>
    [SupportedOSPlatform("macos")]
    internal sealed class ImageIOConstants
    {
        private static readonly Lazy<ImageIOConstants> Shared = new Lazy<ImageIOConstants>(() => new ImageIOConstants(), LazyThreadSafetyMode.ExecutionAndPublication);

        private ImageIOConstants()
        {
            IntPtr coreFoundation = NativeLibrary.Load(ImageIONative.CoreFoundationLibrary);
            IntPtr coreGraphics = NativeLibrary.Load(ImageIONative.CoreGraphicsLibrary);
            IntPtr imageIO = NativeLibrary.Load(ImageIONative.ImageIOLibrary);

            TypeDictionaryKeyCallBacks = NativeLibrary.GetExport(coreFoundation, "kCFTypeDictionaryKeyCallBacks");
            TypeDictionaryValueCallBacks = NativeLibrary.GetExport(coreFoundation, "kCFTypeDictionaryValueCallBacks");
            ColorSpaceSrgb = ReadPointer(coreGraphics, "kCGColorSpaceSRGB");
            DestinationLossyCompressionQuality = ReadPointer(imageIO, "kCGImageDestinationLossyCompressionQuality");
        }

        internal static ImageIOConstants Instance
        {
            get { return Shared.Value; }
        }

        internal IntPtr TypeDictionaryKeyCallBacks { get; }

        internal IntPtr TypeDictionaryValueCallBacks { get; }

        internal IntPtr ColorSpaceSrgb { get; }

        internal IntPtr DestinationLossyCompressionQuality { get; }

        private static IntPtr ReadPointer(IntPtr library, string name)
        {
            IntPtr value = Marshal.ReadIntPtr(NativeLibrary.GetExport(library, name));
            if (value == IntPtr.Zero)
            {
                throw new EntryPointNotFoundException(string.Format("The exported constant {0} is NULL.", name));
            }

            return value;
        }
    }
}
