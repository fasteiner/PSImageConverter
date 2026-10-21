using System;

namespace PSImageConverter
{
    /// <summary>
    /// Sets the orientation tag of an EXIF block to 1 (top left) without moving any other data.
    /// </summary>
    /// <remarks>
    /// The module turns the pixels upright before it encodes them, so the EXIF orientation of the output
    /// has to be 1. Magick.NET returns the EXIF block of the source unchanged after AutoOrient, and
    /// libheif stores the block as it is given. Writing the block again with Magick.NET's EXIF writer
    /// could move data that other tags point to (maker notes), so the value is changed in place, as
    /// ImageMagick does when it writes a file itself.
    /// </remarks>
    public static class ExifOrientation
    {
        private const int OrientationTag = 0x0112;
        private const int TypeShort = 3;
        private const int TypeLong = 4;

        /// <summary>
        /// Returns a copy of the EXIF block whose orientation tag in IFD0 is 1. A block without the tag,
        /// or one whose TIFF structure cannot be read, is returned unchanged.
        /// </summary>
        /// <param name="exif">The EXIF block as TIFF structure, optionally after "Exif\0\0"; null is returned as null.</param>
        /// <returns>A copy of the block with the orientation set to 1, or null for null.</returns>
        public static byte[] SetTopLeft(byte[] exif)
        {
            if (exif == null)
            {
                return null;
            }

            byte[] result = (byte[])exif.Clone();
            int start = 0;
            if (result.Length >= 6 && result[0] == (byte)'E' && result[1] == (byte)'x' && result[2] == (byte)'i' && result[3] == (byte)'f' && result[4] == 0 && result[5] == 0)
            {
                start = 6;
            }

            if (result.Length - start < 8)
            {
                return result;
            }

            bool bigEndian;
            if (result[start] == (byte)'I' && result[start + 1] == (byte)'I')
            {
                bigEndian = false;
            }
            else if (result[start] == (byte)'M' && result[start + 1] == (byte)'M')
            {
                bigEndian = true;
            }
            else
            {
                return result;
            }

            // Offsets in a TIFF structure count from its byte order mark.
            long ifd = start + Read(result, start + 4, 4, bigEndian);
            if (ifd + 2 > result.Length)
            {
                return result;
            }

            long entryCount = Read(result, (int)ifd, 2, bigEndian);
            for (long index = 0; index < entryCount; index++)
            {
                long entry = ifd + 2 + (index * 12);
                if (entry + 12 > result.Length)
                {
                    break;
                }

                if (Read(result, (int)entry, 2, bigEndian) != OrientationTag)
                {
                    continue;
                }

                // A value of up to 4 bytes is stored in the entry itself, left-aligned.
                long type = Read(result, (int)entry + 2, 2, bigEndian);
                if (type == TypeShort)
                {
                    Write(result, (int)entry + 8, 1, 2, bigEndian);
                }
                else if (type == TypeLong)
                {
                    Write(result, (int)entry + 8, 1, 4, bigEndian);
                }

                break;
            }

            return result;
        }

        private static long Read(byte[] data, int position, int size, bool bigEndian)
        {
            long value = 0;
            for (int index = 0; index < size; index++)
            {
                int shift = bigEndian ? (size - 1 - index) * 8 : index * 8;
                value |= (long)data[position + index] << shift;
            }

            return value;
        }

        private static void Write(byte[] data, int position, long value, int size, bool bigEndian)
        {
            for (int index = 0; index < size; index++)
            {
                int shift = bigEndian ? (size - 1 - index) * 8 : index * 8;
                data[position + index] = (byte)(value >> shift);
            }
        }
    }
}
