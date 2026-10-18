using System;
using System.Runtime.Versioning;

namespace PSImageConverter
{
    /// <summary>
    /// The HEIC encoder of macOS: ImageIO (CGImageDestination of type public.heic). The pixels are
    /// copied into a CFData, wrapped in a CGImage with the colour space of the ICC profile (sRGB
    /// without one) and written into memory. Every CoreFoundation and CoreGraphics object is released
    /// before the method returns.
    /// </summary>
    /// <remarks>
    /// ImageIO reports a failure only as NULL or false and writes the reason to the unified log
    /// (log show --predicate 'process == "pwsh"'), so the exceptions name the function that failed.
    /// EXIF and XMP are not written: ImageIO takes metadata only as dictionaries of single values or
    /// as CGImageMetadata, not as the EXIF block of the source, and a tag-by-tag mapping would drop
    /// every tag it does not know without notice.
    /// </remarks>
    [SupportedOSPlatform("macos")]
    internal static class ImageIOHeicEncoder
    {
        private const string HeicTypeIdentifier = "public.heic";

        // probing: the image is the 16x16 test image of HeicEncoder's probe. ImageIO reports a Mac
        // without a working HEVC encoder only as a failed Finalize, and a test image that fails there
        // means just that.
        internal static byte[] Encode(int width, int height, byte[] pixels, int channels, int quality, byte[] iccProfile, bool probing)
        {
            ImageIOConstants constants = ImageIOConstants.Instance;

            // Magick.NET returns straight (not premultiplied) alpha.
            uint alphaInfo = channels == 4 ? ImageIONative.KCGImageAlphaLast : ImageIONative.KCGImageAlphaNone;

            IntPtr pixelData = IntPtr.Zero;
            IntPtr provider = IntPtr.Zero;
            IntPtr colorSpace = IntPtr.Zero;
            IntPtr image = IntPtr.Zero;
            IntPtr properties = IntPtr.Zero;
            IntPtr output = IntPtr.Zero;
            IntPtr typeIdentifier = IntPtr.Zero;
            IntPtr destination = IntPtr.Zero;
            try
            {
                // CFDataCreate copies the pixels, so ImageIO never points into a managed array the
                // garbage collector could move; the data provider retains the CFData.
                pixelData = ImageIONative.CreateData(pixels);
                provider = ImageIONative.CGDataProviderCreateWithCFData(pixelData);
                if (provider == IntPtr.Zero)
                {
                    throw new HeicEncoderException("ImageIO failed: CGDataProviderCreateWithCFData returned NULL.");
                }

                colorSpace = CreateColorSpace(iccProfile, constants);
                image = ImageIONative.CGImageCreate((nuint)width, (nuint)height, 8, (nuint)(8 * channels), (nuint)width * (nuint)channels, colorSpace, alphaInfo | ImageIONative.KCGBitmapByteOrderDefault, provider, IntPtr.Zero, 0, ImageIONative.KCGRenderingIntentDefault);
                if (image == IntPtr.Zero)
                {
                    throw new HeicEncoderException(string.Format("ImageIO failed: CGImageCreate returned NULL for {0}x{1} pixels with {2} channels.", width, height, channels));
                }

                properties = CreateProperties(quality, constants);
                output = ImageIONative.CFDataCreateMutable(IntPtr.Zero, 0);
                if (output == IntPtr.Zero)
                {
                    throw new HeicEncoderException("ImageIO failed: CFDataCreateMutable returned NULL.");
                }

                typeIdentifier = ImageIONative.CreateString(HeicTypeIdentifier);
                destination = ImageIONative.CGImageDestinationCreateWithData(output, typeIdentifier, 1, IntPtr.Zero);
                if (destination == IntPtr.Zero)
                {
                    throw new HeicEncoderException("ImageIO cannot write HEIC on this Mac (CGImageDestinationCreateWithData returned NULL for 'public.heic').", true);
                }

                ImageIONative.CGImageDestinationAddImage(destination, image, properties);
                if (ImageIONative.CGImageDestinationFinalize(destination) == 0)
                {
                    if (probing)
                    {
                        throw new HeicEncoderException("ImageIO could not encode a small test image as HEIC (CGImageDestinationFinalize returned false): this Mac has no working HEVC encoder.", true);
                    }

                    throw new HeicEncoderException(string.Format("ImageIO could not encode the {0}x{1} image as HEIC (CGImageDestinationFinalize returned false; the unified log has the reason).", width, height));
                }

                // The destination writes into the CFData only up to Finalize; it is released first, so
                // nothing else touches the bytes while they are copied.
                ImageIONative.Release(ref destination);
                byte[] encoded = ImageIONative.CopyBytes(output);
                if (encoded.Length == 0)
                {
                    throw new HeicEncoderException("ImageIO reported success but wrote no HEIC data.");
                }

                return encoded;
            }
            finally
            {
                ImageIONative.Release(ref destination);
                ImageIONative.Release(ref typeIdentifier);
                ImageIONative.Release(ref output);
                ImageIONative.Release(ref properties);
                ImageIONative.CGImageRelease(image);
                ImageIONative.CGColorSpaceRelease(colorSpace);
                ImageIONative.CGDataProviderRelease(provider);
                ImageIONative.Release(ref pixelData);
            }
        }

        // The colour space of the pixels: from the ICC profile, or sRGB without one.
        private static IntPtr CreateColorSpace(byte[] iccProfile, ImageIOConstants constants)
        {
            if (iccProfile == null)
            {
                IntPtr srgb = ImageIONative.CGColorSpaceCreateWithName(constants.ColorSpaceSrgb);
                if (srgb == IntPtr.Zero)
                {
                    throw new HeicEncoderException("ImageIO failed: CGColorSpaceCreateWithName(kCGColorSpaceSRGB) returned NULL.");
                }

                return srgb;
            }

            IntPtr iccData = ImageIONative.CreateData(iccProfile);
            IntPtr colorSpace;
            try
            {
                colorSpace = ImageIONative.CGColorSpaceCreateWithICCData(iccData);
            }
            finally
            {
                ImageIONative.Release(ref iccData);
            }

            if (colorSpace == IntPtr.Zero)
            {
                throw new HeicEncoderException("CoreGraphics cannot use the ICC profile (CGColorSpaceCreateWithICCData returned NULL).");
            }

            // CGImageCreate needs as many colour components as the pixels have; with a grey or CMYK
            // profile it would return NULL without a reason.
            nuint components = ImageIONative.CGColorSpaceGetNumberOfComponents(colorSpace);
            if (components != 3)
            {
                ImageIONative.CGColorSpaceRelease(colorSpace);
                throw new HeicEncoderException(string.Format("The ICC profile has {0} colour components; HEIC output needs an RGB profile.", components));
            }

            return colorSpace;
        }

        // The lossy quality (0.01 to 1.0) and orientation 1, because the pixels are already upright.
        private static IntPtr CreateProperties(int quality, ImageIOConstants constants)
        {
            IntPtr qualityNumber = IntPtr.Zero;
            IntPtr orientationNumber = IntPtr.Zero;
            try
            {
                qualityNumber = ImageIONative.CreateNumber(quality / 100.0);
                orientationNumber = ImageIONative.CreateNumber(1);
                return ImageIONative.CreateDictionary(new[] { constants.DestinationLossyCompressionQuality, constants.PropertyOrientation }, new[] { qualityNumber, orientationNumber });
            }
            finally
            {
                ImageIONative.Release(ref qualityNumber);
                ImageIONative.Release(ref orientationNumber);
            }
        }
    }
}
