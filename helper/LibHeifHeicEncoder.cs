using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;

namespace PSImageConverter
{
    /// <summary>
    /// The HEIC encoder of Linux: the libheif of the distribution (libheif.so.1) with its HEVC encoder,
    /// x265 (built in, or a plugin such as the package libheif-plugin-x265 of Ubuntu 24.04 and Debian
    /// 13). Each call uses its own heif_context and releases every libheif object before it returns,
    /// so calls on several threads at once are independent.
    /// </summary>
    /// <remarks>
    /// Every function called here exists in libheif 1.12 (Ubuntu 22.04); the structures passed
    /// (heif_error, heif_writer, the version 1 fields of heif_color_profile_nclx) have the same layout
    /// from 1.12 to 1.23. heif_init exists from 1.13 on and is called when it is there. .NET loads
    /// libheif without exporting its symbols to the process, so the libheif built into Magick.NET's
    /// native library and the system libheif do not mix.
    /// </remarks>
    internal static class LibHeifHeicEncoder
    {
        private const string LibHeif = "libheif.so.1";

        // Enum values from heif.h, unchanged since libheif 1.0.
        private const int HeifErrorOk = 0;
        private const int HeifErrorEncodingError = 9;
        private const int HeifErrorPluginLoadingError = 11;
        private const int HeifSuberrorCannotWriteOutputData = 5000;
        private const int HeifCompressionHevc = 1;
        private const int HeifColorspaceRgb = 1;
        private const int HeifChromaInterleavedRgb = 10;
        private const int HeifChromaInterleavedRgba = 11;
        private const int HeifChannelInterleaved = 10;

        private const uint MinimumVersion = 0x010C0000;

        // libheif refuses to read an image with a side over 32768 pixels (its security limit), so
        // such a file is not written.
        private const int MaximumSide = 32768;

        // heif_color_profile_nclx, version 1: uint8_t version, then the enums color_primaries,
        // transfer_characteristics and matrix_coefficients (32 bits each), then uint8_t full_range_flag.
        private const int NclxPrimariesOffset = 4;
        private const int NclxTransferOffset = 8;
        private const int NclxMatrixOffset = 12;
        private const int NclxFullRangeOffset = 16;

        // Magick.NET 14.17.2 cannot decode an HEVC slice larger than 16 MiB (a slice of 16,764,740
        // bytes decodes, one of 16,777,499 bytes does not; the system libheif decodes both). So an
        // image is encoded as one slice, as x265 writes it by default, and again in several only when
        // that slice is larger than this limit, which keeps a margin of about 10 % below 16 MiB for a
        // Magick.NET version whose decoder counts a few more bytes against its limit.
        private const int MaximumSliceLength = 15_000_000;

        // x265 4.1 creates no thread pool of its own where the NUMA memory-policy calls are denied, as
        // in a container with Docker's default seccomp profile: it then encodes on one thread (a
        // 12-megapixel photo about five times more slowly) and corrupts its heap (the process aborts
        // or hangs) when it encodes several slices. A pool size given as a number makes it create a
        // pool there too, but then it writes about one line "unable to set thread affinity for NUMA
        // node mask" per thread to the console, which PowerShell cannot redirect. So images above
        // this size and images of several slices get a pool; smaller images and the probe stay quiet
        // and are encoded on one thread there. Where the calls are allowed, the pool changes nothing.
        private const long ThreadPoolPixels = 8_000_000;

        // x265 3.5 and 4.1 crash (segmentation fault, also in heif-enc) when asked for 14 slices or
        // more; 13 encode and decode. x265 itself lowers the count to the rows of coding blocks.
        private const int MaximumSlices = 13;

        // The encode with one slice, then up to two with the estimated number of slices, then one
        // with MaximumSlices. x265 cuts an image into slices of nearly the same number of rows of
        // coding blocks, so the slices of an image with evenly spread detail have nearly the same
        // size, and the first estimate fits.
        private const int MaximumEncodes = 4;

        // libheif picks a 16-pixel coding block for an image with a side shorter than 32 pixels; x265
        // then rejects a long other side (4097x16 encodes, 4352x16 does not), and libheif 1.12 writes
        // a broken file instead of reporting it, so such sizes are rejected before encoding.
        private const int ThinSide = 32;
        private const int ThinMaximumLength = 4096;

        private static readonly object InitLock = new object();
        private static bool initialized;

        // The error of heif_init when it could not load every plugin, or null.
        private static string pluginLoadingError;

        // libheif 1.12 returns the writer's heif_error as it is, so the messages are C strings that
        // live as long as the process.
        private static readonly IntPtr SuccessMessage = Marshal.StringToHGlobalAnsi("Success");
        private static readonly IntPtr WriteErrorMessage = Marshal.StringToHGlobalAnsi("Could not copy the encoded data");

        // Held in a static field, so the delegate behind the function pointer is never collected.
        private static readonly WriteCallback WriteDelegate = WriteToOutput;
        private static readonly IntPtr WritePointer = Marshal.GetFunctionPointerForDelegate(WriteDelegate);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate HeifError WriteCallback(IntPtr context, IntPtr data, UIntPtr size, IntPtr userData);

        internal static byte[] Encode(int width, int height, byte[] pixels, int channels, int quality, byte[] iccProfile, byte[] exif, byte[] xmp)
        {
            return Encode(width, height, pixels, channels, quality, iccProfile, exif, xmp, MaximumSliceLength);
        }

        // maximumSliceLength: the largest slice in bytes that the file may have. The tests pass a
        // small one (through reflection), so that a small image takes the paths that a real image
        // takes only from about 10 megapixels of random noise on.
        internal static byte[] Encode(int width, int height, byte[] pixels, int channels, int quality, byte[] iccProfile, byte[] exif, byte[] xmp, int maximumSliceLength)
        {
            EnsureInitialized();

            if (Math.Max(width, height) > MaximumSide)
            {
                throw new HeicEncoderException(string.Format("libheif cannot encode an image of {0}x{1} pixels: it refuses to read an image with a side over {2} pixels, so it would not read the file back.", width, height, MaximumSide));
            }

            if (Math.Min(width, height) < ThinSide && Math.Max(width, height) > ThinMaximumLength)
            {
                throw new HeicEncoderException(string.Format("The HEVC encoder of libheif cannot encode an image of {0}x{1} pixels: with a side shorter than {2} pixels the other side can have at most {3} pixels.", width, height, ThinSide, ThinMaximumLength));
            }

            IntPtr image = IntPtr.Zero;
            try
            {
                image = CreateImage(width, height, pixels, channels, iccProfile);
                bool largeImage = (long)width * height > ThreadPoolPixels;

                // One slice first (see MaximumSliceLength); more only when a slice is too large for
                // Magick.NET. A slice count that x265 lowered to the rows of the image, or
                // MaximumSlices, cannot be raised further.
                int requested = 1;
                for (int encodes = 1; ; encodes++)
                {
                    byte[] file = EncodeImage(image, quality, exif, xmp, requested, largeImage || requested > 1, out string encoderName);
                    (int slices, int largest) = HeifBoxEditor.MeasureSlices(file);
                    if (largest <= maximumSliceLength)
                    {
                        // libheif 1.17 and older store every slice as an extent of its own, which
                        // Windows' own HEIF decoder refuses; these extents follow each other in the
                        // file and become one. libheif writes the nclx values into the HEVC stream, but
                        // no nclx box next to an ICC profile (two colour boxes need encoding options,
                        // whose layout differs between versions).
                        return HeifBoxEditor.AddNclx(HeifBoxEditor.MergeContiguousExtents(file), 1, 13, 1, true, true);
                    }

                    if (!IsX265(encoderName))
                    {
                        throw new HeicEncoderException(string.Format("The HEVC encoder of libheif, {0}, wrote a slice of {1} bytes for an image of {2}x{3} pixels; for Magick.NET to read the file back (it reads slices up to 16 MiB), a slice may have at most {4} bytes, and only x265 can be asked for several slices. A lower quality or a smaller image needs fewer bytes.", encoderName, largest, width, height, maximumSliceLength));
                    }

                    if (slices < requested || requested >= MaximumSlices)
                    {
                        throw new HeicEncoderException(string.Format("x265 wrote a slice of {0} bytes in {1} slices of an image of {2}x{3} pixels; for Magick.NET to read the file back (it reads slices up to 16 MiB), a slice may have at most {4} bytes, and x265 writes no more slices for this image. A lower quality or a smaller image needs fewer bytes.", largest, slices, width, height, maximumSliceLength));
                    }

                    // An eighth more slices than the size alone asks for, for rows that cost more than
                    // others; the last encode gets the most slices x265 writes.
                    long estimate = (((long)requested * largest * 9 / 8) + maximumSliceLength - 1) / maximumSliceLength;
                    requested = encodes + 1 >= MaximumEncodes ? MaximumSlices : (int)Math.Min(MaximumSlices, Math.Max(requested + 1, estimate));
                }
            }
            finally
            {
                if (image != IntPtr.Zero)
                {
                    heif_image_release(image);
                }
            }
        }

        // The pixels as an interleaved RGB or RGBA heif_image with the ICC profile and the nclx values.
        private static IntPtr CreateImage(int width, int height, byte[] pixels, int channels, byte[] iccProfile)
        {
            IntPtr image = IntPtr.Zero;
            try
            {
                Check(heif_image_create(width, height, HeifColorspaceRgb, channels == 4 ? HeifChromaInterleavedRgba : HeifChromaInterleavedRgb, out image), "heif_image_create");
                Check(heif_image_add_plane(image, HeifChannelInterleaved, width, height, 8), "heif_image_add_plane");

                IntPtr plane = heif_image_get_plane(image, HeifChannelInterleaved, out int stride);
                if (plane == IntPtr.Zero)
                {
                    throw new HeicEncoderException("libheif heif_image_get_plane returned NULL.");
                }

                // libheif aligns its rows, so the stride can be larger than a row of the buffer.
                int rowBytes = width * channels;
                for (int y = 0; y < height; y++)
                {
                    Marshal.Copy(pixels, y * rowBytes, plane + ((nint)y * stride), rowBytes);
                }

                if (iccProfile != null)
                {
                    Check(heif_image_set_raw_color_profile(image, "prof", iccProfile, (UIntPtr)iccProfile.Length), "heif_image_set_raw_color_profile");
                }

                SetNclx(image);
                IntPtr result = image;
                image = IntPtr.Zero;
                return result;
            }
            finally
            {
                if (image != IntPtr.Zero)
                {
                    heif_image_release(image);
                }
            }
        }

        // Encodes the image in a context of its own, in the given number of slices, and returns the
        // HEIF file with the EXIF and XMP items. threadPool: give x265 a pool of one thread per
        // processor (see ThreadPoolPixels). libheif does not change the image, so it is encoded again
        // as it is.
        private static byte[] EncodeImage(IntPtr image, int quality, byte[] exif, byte[] xmp, int slices, bool threadPool, out string encoderName)
        {
            IntPtr context = IntPtr.Zero;
            IntPtr encoder = IntPtr.Zero;
            IntPtr handle = IntPtr.Zero;
            GCHandle output = default;

            try
            {
                context = heif_context_alloc();
                if (context == IntPtr.Zero)
                {
                    throw new OutOfMemoryException("heif_context_alloc returned NULL.");
                }

                // libheif 1.17 without an HEVC plugin returns code 3 (unsupported file type), subcode 0.
                HeifError error = heif_context_get_encoder_for_format(context, HeifCompressionHevc, out encoder);
                if (error.Code != HeifErrorOk || encoder == IntPtr.Zero)
                {
                    string plugins = pluginLoadingError == null ? string.Empty : "; loading its plugins failed: " + pluginLoadingError;
                    throw new HeicEncoderException(string.Format("libheif {0} has no HEVC encoder ({1}){2}.", FormatVersion(heif_get_version_number()), MessageOf(error), plugins), true);
                }

                // x265: CRF = (100 - quality) / 2.
                Check(heif_encoder_set_lossy_quality(encoder, quality), "heif_encoder_set_lossy_quality");

                // Encode asks for several slices only from x265; the parameters of other encoders
                // have other names.
                encoderName = Marshal.PtrToStringUTF8(heif_encoder_get_name(encoder)) ?? string.Empty;
                if (IsX265(encoderName))
                {
                    if (slices > 1)
                    {
                        Check(heif_encoder_set_parameter_string(encoder, "x265:slices", slices.ToString(CultureInfo.InvariantCulture)), "heif_encoder_set_parameter_string(x265:slices)");
                    }

                    if (threadPool)
                    {
                        string pools = Environment.ProcessorCount.ToString(CultureInfo.InvariantCulture);
                        Check(heif_encoder_set_parameter_string(encoder, "x265:pools", pools), "heif_encoder_set_parameter_string(x265:pools)");
                    }
                }

                // NULL options: the layout of heif_encoding_options differs between versions.
                Check(heif_context_encode_image(context, image, encoder, IntPtr.Zero, out handle), "heif_context_encode_image");

                // libheif finds the TIFF header itself and writes the 4-byte offset that HEIF puts in
                // front of the EXIF data.
                if (exif != null)
                {
                    Check(heif_context_add_exif_metadata(context, handle, exif, exif.Length), "heif_context_add_exif_metadata");
                }

                if (xmp != null)
                {
                    Check(heif_context_add_XMP_metadata(context, handle, xmp, xmp.Length), "heif_context_add_XMP_metadata");
                }

                List<byte[]> chunks = new List<byte[]>();
                output = GCHandle.Alloc(chunks);
                HeifWriter writer = new HeifWriter { WriterApiVersion = 1, Write = WritePointer };
                Check(heif_context_write(context, ref writer, GCHandle.ToIntPtr(output)), "heif_context_write");
                return Concat(chunks);
            }
            finally
            {
                if (output.IsAllocated)
                {
                    output.Free();
                }

                if (handle != IntPtr.Zero)
                {
                    heif_image_handle_release(handle);
                }

                if (encoder != IntPtr.Zero)
                {
                    heif_encoder_release(encoder);
                }

                if (context != IntPtr.Zero)
                {
                    heif_context_free(context);
                }
            }
        }

        // x265 gives its name with its version, e.g. "x265 HEVC encoder (3.5+1-f0c1022b6)".
        private static bool IsX265(string encoderName)
        {
            return encoderName.StartsWith("x265", StringComparison.Ordinal);
        }

        private static void EnsureInitialized()
        {
            lock (InitLock)
            {
                if (initialized)
                {
                    return;
                }

                if (!NativeLibrary.TryLoad(LibHeif, typeof(LibHeifHeicEncoder).Assembly, null, out IntPtr library))
                {
                    throw new HeicEncoderException(LibHeif + " was not found.", true);
                }

                uint version = heif_get_version_number();
                if (version < MinimumVersion)
                {
                    throw new HeicEncoderException(string.Format("libheif {0} is older than 1.12.", FormatVersion(version)), true);
                }

                // From libheif 1.13 on, heif_init loads the codec plugins (x265 is one on Ubuntu 24.04).
                // It is reference counted; heif_deinit is never called, because another runspace of this
                // process may be encoding at that moment. A plugin that cannot be loaded (Arch Linux
                // installs plugins whose libraries are optional dependencies) does not stop the others
                // or the built-in codecs, so the HEVC encoder is looked up anyway.
                if (NativeLibrary.TryGetExport(library, "heif_init", out _))
                {
                    HeifError error = heif_init(IntPtr.Zero);
                    if (error.Code == HeifErrorPluginLoadingError)
                    {
                        pluginLoadingError = MessageOf(error);
                    }
                    else if (error.Code != HeifErrorOk)
                    {
                        throw new HeicEncoderException("libheif heif_init failed: " + MessageOf(error) + ".", true);
                    }
                }

                initialized = true;
            }
        }

        // Signals BT.709 primaries and matrix, sRGB transfer and full range, as the Windows encoder does.
        // libheif converts the RGB pixels to YCbCr with that matrix and writes the values into the HEVC
        // stream. Without it libheif 1.17 converts with BT.601 but signals BT.709 primaries, and the
        // Windows HEIF decoder, which picks its matrix by the primaries, shows wrong colours.
        private static void SetNclx(IntPtr image)
        {
            IntPtr nclx = heif_nclx_color_profile_alloc();
            if (nclx == IntPtr.Zero)
            {
                throw new OutOfMemoryException("heif_nclx_color_profile_alloc returned NULL.");
            }

            try
            {
                Marshal.WriteInt32(nclx, NclxPrimariesOffset, 1);
                Marshal.WriteInt32(nclx, NclxTransferOffset, 13);
                Marshal.WriteInt32(nclx, NclxMatrixOffset, 1);
                Marshal.WriteByte(nclx, NclxFullRangeOffset, 1);
                Check(heif_image_set_nclx_color_profile(image, nclx), "heif_image_set_nclx_color_profile");
            }
            finally
            {
                heif_nclx_color_profile_free(nclx);
            }
        }

        private static HeifError WriteToOutput(IntPtr context, IntPtr data, UIntPtr size, IntPtr userData)
        {
            // An exception must not leave a callback that native code called.
            try
            {
                List<byte[]> chunks = (List<byte[]>)GCHandle.FromIntPtr(userData).Target;
                byte[] bytes = new byte[checked((int)size)];
                Marshal.Copy(data, bytes, 0, bytes.Length);
                chunks.Add(bytes);
                return new HeifError { Code = HeifErrorOk, Subcode = 0, Message = SuccessMessage };
            }
            catch (Exception)
            {
                return new HeifError { Code = HeifErrorEncodingError, Subcode = HeifSuberrorCannotWriteOutputData, Message = WriteErrorMessage };
            }
        }

        // libheif 1.12 to 1.17 call the writer once with the whole file; more calls are appended.
        private static byte[] Concat(List<byte[]> chunks)
        {
            if (chunks.Count == 1)
            {
                return chunks[0];
            }

            int length = 0;
            foreach (byte[] chunk in chunks)
            {
                length = checked(length + chunk.Length);
            }

            byte[] result = new byte[length];
            int offset = 0;
            foreach (byte[] chunk in chunks)
            {
                Buffer.BlockCopy(chunk, 0, result, offset, chunk.Length);
                offset += chunk.Length;
            }

            return result;
        }

        private static void Check(HeifError error, string function)
        {
            if (error.Code != HeifErrorOk)
            {
                throw new HeicEncoderException(string.Format("libheif {0} failed: {1}.", function, MessageOf(error)));
            }
        }

        private static string MessageOf(HeifError error)
        {
            string text = error.Message == IntPtr.Zero ? string.Empty : Marshal.PtrToStringUTF8(error.Message) ?? string.Empty;
            return string.Format("{0} (code {1}, subcode {2})", text, error.Code, error.Subcode);
        }

        private static string FormatVersion(uint version)
        {
            return string.Format("{0}.{1}.{2}", version >> 24, (version >> 16) & 0xFF, (version >> 8) & 0xFF);
        }

        // struct heif_error { enum heif_error_code code; enum heif_suberror_code subcode; const char* message; },
        // returned by value.
        [StructLayout(LayoutKind.Sequential)]
        private struct HeifError
        {
            public int Code;
            public int Subcode;
            public IntPtr Message;
        }

        // struct heif_writer { int writer_api_version; struct heif_error (*write)(struct heif_context*, const void* data, size_t size, void* userdata); }
        [StructLayout(LayoutKind.Sequential)]
        private struct HeifWriter
        {
            public int WriterApiVersion;
            public IntPtr Write;
        }

        [DllImport(LibHeif)]
        private static extern HeifError heif_init(IntPtr parameters);

        [DllImport(LibHeif)]
        private static extern uint heif_get_version_number();

        [DllImport(LibHeif)]
        private static extern IntPtr heif_context_alloc();

        [DllImport(LibHeif)]
        private static extern void heif_context_free(IntPtr context);

        [DllImport(LibHeif)]
        private static extern HeifError heif_context_get_encoder_for_format(IntPtr context, int format, out IntPtr encoder);

        [DllImport(LibHeif)]
        private static extern IntPtr heif_encoder_get_name(IntPtr encoder);

        [DllImport(LibHeif)]
        private static extern void heif_encoder_release(IntPtr encoder);

        [DllImport(LibHeif)]
        private static extern HeifError heif_encoder_set_lossy_quality(IntPtr encoder, int quality);

        [DllImport(LibHeif, BestFitMapping = false, ThrowOnUnmappableChar = true)]
        private static extern HeifError heif_encoder_set_parameter_string(IntPtr encoder, [MarshalAs(UnmanagedType.LPUTF8Str)] string name, [MarshalAs(UnmanagedType.LPUTF8Str)] string value);

        [DllImport(LibHeif)]
        private static extern HeifError heif_image_create(int width, int height, int colorspace, int chroma, out IntPtr image);

        [DllImport(LibHeif)]
        private static extern HeifError heif_image_add_plane(IntPtr image, int channel, int width, int height, int bitDepth);

        [DllImport(LibHeif)]
        private static extern IntPtr heif_image_get_plane(IntPtr image, int channel, out int stride);

        [DllImport(LibHeif)]
        private static extern void heif_image_release(IntPtr image);

        [DllImport(LibHeif, BestFitMapping = false, ThrowOnUnmappableChar = true)]
        private static extern HeifError heif_image_set_raw_color_profile(IntPtr image, [MarshalAs(UnmanagedType.LPUTF8Str)] string type, byte[] data, UIntPtr size);

        [DllImport(LibHeif)]
        private static extern IntPtr heif_nclx_color_profile_alloc();

        [DllImport(LibHeif)]
        private static extern void heif_nclx_color_profile_free(IntPtr profile);

        [DllImport(LibHeif)]
        private static extern HeifError heif_image_set_nclx_color_profile(IntPtr image, IntPtr profile);

        [DllImport(LibHeif)]
        private static extern HeifError heif_context_encode_image(IntPtr context, IntPtr image, IntPtr encoder, IntPtr options, out IntPtr handle);

        [DllImport(LibHeif)]
        private static extern void heif_image_handle_release(IntPtr handle);

        [DllImport(LibHeif)]
        private static extern HeifError heif_context_add_exif_metadata(IntPtr context, IntPtr handle, byte[] data, int size);

        [DllImport(LibHeif)]
        private static extern HeifError heif_context_add_XMP_metadata(IntPtr context, IntPtr handle, byte[] data, int size);

        [DllImport(LibHeif)]
        private static extern HeifError heif_context_write(IntPtr context, ref HeifWriter writer, IntPtr userData);
    }
}
