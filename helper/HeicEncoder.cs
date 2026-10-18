using System;
using System.Threading;

namespace PSImageConverter
{
    /// <summary>
    /// Encodes 8-bit RGB or RGBA pixels as HEIC with the HEVC encoder of the operating system.
    /// </summary>
    /// <remarks>
    /// The module ships no HEVC code: HEVC is covered by patent pools, and shipping an encoder would
    /// pass their licensing duties on to every user. It calls the encoder the user installed: on
    /// Windows the WIC HEIF encoder with the "HEVC Video Extensions", on Linux the libheif of the
    /// distribution with its HEVC encoder x265 (built in or as a plugin), on macOS ImageIO. The caller
    /// turns the pixels upright first and converts them to RGB; the encoder only compresses them and
    /// stores the metadata.
    /// </remarks>
    public static class HeicEncoder
    {
        private static readonly Lazy<HeicEncoderException> ProbeFailure = new Lazy<HeicEncoderException>(Probe, LazyThreadSafetyMode.ExecutionAndPublication);

        /// <summary>
        /// Gets the name of the platform whose encoder is used: Windows, Linux or macOS.
        /// </summary>
        public static string Platform
        {
            get
            {
                if (OperatingSystem.IsWindows())
                {
                    return "Windows";
                }

                return OperatingSystem.IsMacOS() ? "macOS" : "Linux";
            }
        }

        /// <summary>
        /// Gets a value indicating whether the encoder stores an alpha channel. The WIC HEIF encoder of
        /// Windows takes opaque pixels only (32bppBGR), so the caller flattens transparent pixels first;
        /// libheif stores the alpha channel as an auxiliary image, and ImageIO gets it with the pixels.
        /// </summary>
        public static bool StoresAlpha
        {
            get { return !OperatingSystem.IsWindows(); }
        }

        /// <summary>
        /// Gets a value indicating whether the encoder writes EXIF and XMP data. ImageIO of macOS has
        /// no call that takes an EXIF block as it is, so macOS output carries no EXIF and no XMP.
        /// </summary>
        public static bool StoresMetadata
        {
            get { return !OperatingSystem.IsMacOS(); }
        }

        /// <summary>
        /// Returns why HEIC cannot be written on this machine, or null when it can. The first call
        /// encodes a small image with the encoder of the operating system; the result is kept for the
        /// lifetime of the process, so an encoder installed later needs a new process.
        /// </summary>
        /// <returns>Null when HEIC can be written, otherwise the reason.</returns>
        public static string GetUnavailableReason()
        {
            return ProbeFailure.Value?.Message;
        }

        /// <summary>
        /// Returns the error of the test encoding that <see cref="GetUnavailableReason"/> runs, or null
        /// when HEIC can be written. Its <see cref="HeicEncoderException.EncoderMissing"/> tells a
        /// missing encoder (true) from an installed encoder that failed or a fault in the binding to it
        /// (false); an error that did not come from the encoder itself is its inner exception.
        /// </summary>
        /// <returns>Null when HEIC can be written, otherwise the error of the test encoding.</returns>
        public static HeicEncoderException GetProbeFailure()
        {
            return ProbeFailure.Value;
        }

        /// <summary>
        /// Encodes an image as HEIC and returns the bytes of the HEIC file.
        /// </summary>
        /// <param name="width">The width of the image in pixels.</param>
        /// <param name="height">The height of the image in pixels.</param>
        /// <param name="pixels">The pixels row by row from the top left without padding: R, G, B (and A) with 8 bits each, straight alpha.</param>
        /// <param name="channels">3 for RGB or 4 for RGBA. Windows composites RGBA onto white (see <see cref="StoresAlpha"/>).</param>
        /// <param name="quality">The quality from 1 (smallest file) to 100 (best quality), mapped to the scale of the encoder.</param>
        /// <param name="iccProfile">The RGB ICC profile of the pixels, or null to write none.</param>
        /// <param name="exif">The EXIF block as TIFF structure, optionally after "Exif\0\0", or null; it is stored as it is. Its orientation should be 1 (see <see cref="ExifOrientation.SetTopLeft"/>). Not written on macOS.</param>
        /// <param name="xmp">The XMP packet as UTF-8, or null; it is stored as it is. Not written on macOS.</param>
        /// <returns>The encoded HEIC file.</returns>
        /// <exception cref="ArgumentNullException"><paramref name="pixels"/> is null.</exception>
        /// <exception cref="ArgumentException">The size, the length of the pixel buffer, the channel count or the quality is out of range.</exception>
        /// <exception cref="HeicEncoderException">The encoder of the operating system is missing, rejected the image (e.g. a side longer than it can encode) or failed in another way. Errors that did not come from the encoder itself (a missing native function, too little memory, a HEIF structure the box editor does not expect, a COM error) are wrapped: the original error is the inner exception.</exception>
        public static byte[] Encode(int width, int height, byte[] pixels, int channels, int quality, byte[] iccProfile, byte[] exif, byte[] xmp)
        {
            CheckArguments(width, height, pixels, channels, quality);
            return EncodeCore(width, height, pixels, channels, quality, iccProfile, exif, xmp, false);
        }

        private static void CheckArguments(int width, int height, byte[] pixels, int channels, int quality)
        {
            ArgumentNullException.ThrowIfNull(pixels);
            if (width < 1 || height < 1)
            {
                throw new ArgumentException(string.Format("The image size {0}x{1} is not valid.", width, height));
            }

            if (channels != 3 && channels != 4)
            {
                throw new ArgumentException("Only 3 (RGB) or 4 (RGBA) channels are supported.", nameof(channels));
            }

            if (pixels.LongLength != (long)width * height * channels)
            {
                throw new ArgumentException(string.Format("The pixel buffer has {0} bytes; {1}x{2}x{3} needs {4}.", pixels.LongLength, width, height, channels, (long)width * height * channels), nameof(pixels));
            }

            if (quality < 1 || quality > 100)
            {
                throw new ArgumentException("The quality must be between 1 and 100.", nameof(quality));
            }
        }

        // probing: the call encodes the test image of the probe, so a failure of the encoder means that
        // it does not work at all (ImageIO reports a missing HEVC encoder only as a failed Finalize).
        private static byte[] EncodeCore(int width, int height, byte[] pixels, int channels, int quality, byte[] iccProfile, byte[] exif, byte[] xmp, bool probing)
        {
            // Empty arrays come from PowerShell as easily as null; neither is written.
            iccProfile = iccProfile == null || iccProfile.Length == 0 ? null : iccProfile;
            exif = exif == null || exif.Length == 0 ? null : exif;
            xmp = xmp == null || xmp.Length == 0 ? null : xmp;

            // Any other error (COM or I/O, too little memory for the padded pixels, a missing native
            // function, a HEIF structure the box editor does not expect) is wrapped, so a caller tells
            // the encoder's failures apart from wrong arguments by the type alone.
            try
            {
                if (OperatingSystem.IsWindows())
                {
                    return WicHeicEncoder.Encode(width, height, pixels, channels, quality, iccProfile, exif, xmp);
                }

                if (OperatingSystem.IsMacOS())
                {
                    return ImageIOHeicEncoder.Encode(width, height, pixels, channels, quality, iccProfile, probing);
                }

                return LibHeifHeicEncoder.Encode(width, height, pixels, channels, quality, iccProfile, exif, xmp);
            }
            catch (HeicEncoderException)
            {
                throw;
            }
            catch (Exception exception)
            {
                throw new HeicEncoderException(string.Format("The HEIC encoder of {0} failed: {1} ({2}).", Platform, exception.Message.TrimEnd('.'), exception.GetType().FullName), exception);
            }
        }

        // A failure here makes every file fail, so any error counts: a missing library, a missing HEVC
        // encoder, an installed encoder that does not work, or a fault in the binding to it.
        private static HeicEncoderException Probe()
        {
            byte[] pixels = new byte[16 * 16 * 3];
            for (int index = 0; index < pixels.Length; index++)
            {
                pixels[index] = (byte)(index * 7);
            }

            try
            {
                EncodeCore(16, 16, pixels, 3, 50, null, null, null, true);
                return null;
            }
            catch (HeicEncoderException exception)
            {
                return exception;
            }
        }
    }
}
