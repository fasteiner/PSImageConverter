using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Runtime.Versioning;

namespace PSImageConverter
{
    /// <summary>
    /// The HEIC encoder of Windows: the WIC HEIF encoder of the "HEIF Image Extensions", which
    /// compresses with the HEVC encoder of the "HEVC Video Extensions". Every call creates its own WIC
    /// factory and releases every COM object it created, so calls on several threads (the STA thread of
    /// the console, the MTA threads of ForEach-Object -Parallel) share no COM object.
    /// </summary>
    /// <remarks>
    /// How the encoder behaves (HEIF Image Extensions 1.2.62, HEVC Video Extensions 2.5.48) and how
    /// this class keeps clear of it:
    /// - Up to a long side of 1920 pixels it writes one coded image, above that a grid of 512x512
    ///   tiles. The single coded image fails or ends the process for some sizes: an access violation
    ///   in the HEVC encoder (836x328 nearly every time, about 1 in 300 random sizes), a fail-fast
    ///   (STATUS_STACK_BUFFER_OVERRUN) for narrow images such as 1x100, and HEVC tile layouts with more
    ///   than 10 tile rows (300x1200) that libde265, and with it libheif and ImageMagick, cannot
    ///   decode. Grids showed none of this, so every image is written as a grid of at least 4x1 tiles.
    /// - It fills the part of a tile outside the image with data that changes from call to call, and
    ///   codes it: a partly used tile costs from 1 KB to several hundred KB for the same image (worst
    ///   with calls on several threads at once), and partial tile columns narrower than 34 pixels can
    ///   fail at CommitFrame. So the image is padded to whole tiles by repeating its edge pixels, which
    ///   also keeps the coded size even (4:2:0 chroma).
    /// - The WIC HEIF decoder (Photos, Explorer) refuses a clean aperture that ends 1 pixel into a tile
    ///   column or row (a side of 512 * k + 1 pixels). Such a side gets two more pixels on the left or
    ///   top (the first column or row, repeated), and the clean aperture starts there.
    /// A clean aperture (clap) box on the grid crops the padding away again. The encoder converts RGB
    /// to YCbCr with the BT.709 matrix but does not say so, so an nclx colour box is added (see
    /// <see cref="HeifBoxEditor.AddNclx"/>). EXIF and XMP are stored as metadata items as they are given
    /// (see <see cref="HeifBoxEditor.AddMetadataItems"/>): the encoder's own metadata writers parse the
    /// blocks again and fail the whole image on a block they cannot parse.
    /// </remarks>
    [SupportedOSPlatform("windows")]
    internal static class WicHeicEncoder
    {
        /// <summary>
        /// The longest side the encoder takes: CommitFrame fails with 0xC00D36B4 for a grid side of 45
        /// tiles (23040 pixels) or more, measured with HEIF Image Extensions 1.2.62.
        /// </summary>
        internal const int MaximumSide = 44 * GridTileSize;

        // HRESULTs that mean "no HEIC encoder", by the step that returns them.
        private const int WINCODEC_ERR_COMPONENTNOTFOUND = unchecked((int)0x88982F50);
        private const int REGDB_E_CLASSNOTREG = unchecked((int)0x80040154);
        private const int MF_E_TOPO_CODEC_NOT_FOUND = unchecked((int)0xC00D5212);

        private const int StripBytes = 4 * 1024 * 1024;
        private const int GridTileSize = 512;
        private const int MinimumGridLongSide = 4 * GridTileSize;
        private const int EdgeShift = 2;

        internal static byte[] Encode(int width, int height, byte[] pixels, int channels, int quality, byte[] iccProfile, byte[] exif, byte[] xmp)
        {
            if (Math.Max(width, height) > MaximumSide)
            {
                throw new HeicEncoderException(string.Format("The HEIC encoder of Windows cannot encode an image of {0}x{1} pixels: a side can have at most {2} pixels.", width, height, MaximumSide));
            }

            int left = width > GridTileSize && width % GridTileSize == 1 ? EdgeShift : 0;
            int top = height > GridTileSize && height % GridTileSize == 1 ? EdgeShift : 0;
            int codedWidth = WholeTiles(width + left);
            int codedHeight = WholeTiles(height + top);
            if (Math.Max(codedWidth, codedHeight) < MinimumGridLongSide)
            {
                if (codedWidth >= codedHeight)
                {
                    codedWidth = MinimumGridLongSide;
                }
                else
                {
                    codedHeight = MinimumGridLongSide;
                }
            }

            byte[] file;
            if (codedWidth == width && codedHeight == height)
            {
                file = EncodeCore(width, height, pixels, channels, quality, iccProfile);
            }
            else
            {
                byte[] padded = Pad(pixels, width, height, channels, codedWidth, codedHeight, left, top);
                file = EncodeCore(codedWidth, codedHeight, padded, channels, quality, iccProfile);
                file = HeifBoxEditor.SetCleanAperture(file, width, height, left, top);
            }

            return exif == null && xmp == null ? file : HeifBoxEditor.AddMetadataItems(file, exif, xmp);
        }

        private static int WholeTiles(int side)
        {
            return (side + GridTileSize - 1) / GridTileSize * GridTileSize;
        }

        // Places the image at left/top in the coded size and fills the margins with its nearest edge pixels.
        private static byte[] Pad(byte[] pixels, int width, int height, int channels, int codedWidth, int codedHeight, int left, int top)
        {
            byte[] padded = new byte[(long)codedWidth * codedHeight * channels];
            long rowBytes = (long)width * channels;
            for (int y = 0; y < codedHeight; y++)
            {
                long sourceRow = (long)Math.Clamp(y - top, 0, height - 1) * rowBytes;
                long targetRow = (long)y * codedWidth * channels;
                Array.Copy(pixels, sourceRow, padded, targetRow + ((long)left * channels), rowBytes);
                for (int x = 0; x < left; x++)
                {
                    Array.Copy(pixels, sourceRow, padded, targetRow + ((long)x * channels), channels);
                }

                for (int x = left + width; x < codedWidth; x++)
                {
                    Array.Copy(pixels, sourceRow + rowBytes - channels, padded, targetRow + ((long)x * channels), channels);
                }
            }

            return padded;
        }

        private static byte[] EncodeCore(int width, int height, byte[] pixels, int channels, int quality, byte[] iccProfile)
        {
            IWICImagingFactory factory = null;
            IStream stream = null;
            IWICBitmapEncoder encoder = null;
            IWICBitmapFrameEncode frame = null;
            IPropertyBag2 options = null;
            IWICColorContext colorContext = null;

            try
            {
                factory = (IWICImagingFactory)Activator.CreateInstance(Type.GetTypeFromCLSID(WicConstants.ClsidImagingFactory, true));
                Check(WicNativeMethods.CreateStreamOnHGlobal(IntPtr.Zero, true, out stream), "CreateStreamOnHGlobal");

                Guid container = WicConstants.ContainerFormatHeif;
                Check(factory.CreateEncoder(ref container, IntPtr.Zero, out encoder), "CreateEncoder");
                Check(encoder.Initialize(stream, WicConstants.BitmapEncoderNoCache), "Initialize");
                Check(encoder.CreateNewFrame(out frame, out options), "CreateNewFrame");

                // ImageQuality 0.0-1.0 changes the size; "Lossless" would write an uncompressed item
                // instead of HEVC. HEVC is asked for explicitly: with the default the encoder may pick
                // another codec, so a missing HEVC encoder would not be noticed.
                WriteOption(options, "ImageQuality", WicConstants.VT_R4, (IntPtr)BitConverter.SingleToInt32Bits(quality / 100f));
                WriteOption(options, "HeifCompressionMethod", WicConstants.VT_UI1, (IntPtr)WicConstants.HeifCompressionHevc);
                Check(frame.Initialize(options), "InitializeFrame");
                Check(frame.SetSize(width, height), "SetSize");

                // The HEIF encoder takes 32bppBGR only (it stores no alpha); SetPixelFormat answers
                // with the format it takes.
                Guid pixelFormat = WicConstants.PixelFormat32bppBGR;
                Check(frame.SetPixelFormat(ref pixelFormat), "SetPixelFormat");
                if (pixelFormat != WicConstants.PixelFormat32bppBGR)
                {
                    throw new HeicEncoderException(string.Format("The HEIC encoder of Windows asked for pixel format {0} instead of 32bppBGR.", pixelFormat));
                }

                if (iccProfile != null)
                {
                    Check(factory.CreateColorContext(out colorContext), "CreateColorContext");
                    Check(colorContext.InitializeFromMemory(iccProfile, iccProfile.Length), "InitializeColorContext");
                    Check(frame.SetColorContexts(1, new[] { colorContext }), "SetColorContexts");
                }

                WritePixels(frame, width, height, pixels, channels);
                Check(frame.Commit(), "CommitFrame");
                Check(encoder.Commit(), "Commit");

                // nclx: primaries BT.709 (1), transfer sRGB (13), matrix BT.709 (1), full range.
                return HeifBoxEditor.AddNclx(ReadStream(stream), 1, 13, 1, true, false);
            }
            finally
            {
                Release(colorContext);
                Release(options);
                Release(frame);
                Release(encoder);
                Release(stream);
                Release(factory);
            }
        }

        // CreateEncoder fails without the "HEIF Image Extensions" (no WIC component for the HEIF
        // container). With the HEIF extension but no HEVC encoder the encoder is created, and
        // CommitFrame fails, because the frame is compressed there.
        private static void Check(int hresult, string step)
        {
            if (hresult >= 0)
            {
                return;
            }

            // The system text of the HRESULT ends with the code in parentheses, which the message names already.
            string code = string.Format("0x{0:X8}", hresult);
            string text = (Marshal.GetExceptionForHR(hresult)?.Message ?? string.Empty).Replace("(" + code + ")", string.Empty).Trim().TrimEnd('.');
            string failure = string.Format("WIC {0} failed with HRESULT {1}", step, code) + (text.Length > 0 ? " (" + text + ")" : string.Empty);
            if (step == "CreateEncoder" && (hresult == WINCODEC_ERR_COMPONENTNOTFOUND || hresult == REGDB_E_CLASSNOTREG))
            {
                throw new HeicEncoderException("Windows has no HEIF encoder: " + failure + ".", true);
            }

            if (step == "CommitFrame" && hresult == MF_E_TOPO_CODEC_NOT_FOUND)
            {
                throw new HeicEncoderException("The HEIF encoder of Windows found no HEVC encoder: " + failure + ".", true);
            }

            throw new HeicEncoderException("The HEIC encoder of Windows failed: " + failure + ".");
        }

        private static void WriteOption(IPropertyBag2 options, string name, ushort type, IntPtr value)
        {
            PropBag2 property = new PropBag2();
            IntPtr namePointer = Marshal.StringToCoTaskMemUni(name);
            try
            {
                property.Name = namePointer;
                PropVariant variant = new PropVariant { Type = type, Value = value };
                Check(options.Write(1, ref property, ref variant), "SetOption " + name);
            }
            finally
            {
                Marshal.FreeCoTaskMem(namePointer);
            }
        }

        // Writes the rows as 32bppBGR (blue, green, red, unused byte), in strips of a few MB. The
        // encoder stores no alpha, so RGBA pixels are composited onto white, as Jpeg output is.
        private static void WritePixels(IWICBitmapFrameEncode frame, int width, int height, byte[] pixels, int channels)
        {
            int targetStride = width * 4;
            int rowsPerStrip = Math.Max(1, Math.Min(height, StripBytes / targetStride));
            byte[] strip = new byte[rowsPerStrip * targetStride];
            GCHandle handle = GCHandle.Alloc(strip, GCHandleType.Pinned);
            try
            {
                for (int row = 0; row < height; row += rowsPerStrip)
                {
                    int rows = Math.Min(rowsPerStrip, height - row);
                    long source = (long)row * width * channels;
                    int target = 0;
                    int count = rows * width;
                    for (int index = 0; index < count; index++)
                    {
                        byte red = pixels[source];
                        byte green = pixels[source + 1];
                        byte blue = pixels[source + 2];
                        if (channels == 4)
                        {
                            int alpha = pixels[source + 3];
                            int white = 255 * (255 - alpha);
                            red = (byte)(((red * alpha) + white + 127) / 255);
                            green = (byte)(((green * alpha) + white + 127) / 255);
                            blue = (byte)(((blue * alpha) + white + 127) / 255);
                        }

                        strip[target] = blue;
                        strip[target + 1] = green;
                        strip[target + 2] = red;
                        strip[target + 3] = 255;
                        source += channels;
                        target += 4;
                    }

                    Check(frame.WritePixels(rows, targetStride, rows * targetStride, handle.AddrOfPinnedObject()), "WritePixels");
                }
            }
            finally
            {
                handle.Free();
            }
        }

        private static byte[] ReadStream(IStream stream)
        {
            stream.Stat(out STATSTG stat, WicConstants.StatFlagNoName);
            byte[] result = new byte[stat.cbSize];
            stream.Seek(0, 0, IntPtr.Zero);
            stream.Read(result, result.Length, IntPtr.Zero);
            return result;
        }

        private static void Release(object comObject)
        {
            if (comObject != null && Marshal.IsComObject(comObject))
            {
                Marshal.FinalReleaseComObject(comObject);
            }
        }
    }
}
