using System;
using System.Collections.Generic;
using System.IO;

namespace PSImageConverter
{
    /// <summary>
    /// Corrects the boxes of HEIF files written by the WIC HEIF encoder and by libheif: crops the
    /// padding away, adds the nclx colour box, stores EXIF and XMP as metadata items and joins
    /// extents that follow each other. Also measures the HEVC slices of the coded images.
    /// </summary>
    internal static class HeifBoxEditor
    {
        // Crops the primary image item (one coded image, or the grid of tiles) to the width x height
        // pixels that start at left/top: rewrites the clean aperture (clap) the encoder wrote for
        // padding of its own, or adds one to the primary item (essential, as HEIF requires for
        // transformative properties) when there is none.
        internal static byte[] SetCleanAperture(byte[] file, int width, int height, int left, int top)
        {
            int metaStart = FindBox(file, 0, file.Length, "meta");
            int metaEnd = metaStart < 0 ? -1 : metaStart + (int)ReadUInt(file, metaStart, 4);
            int pitm = metaStart < 0 ? -1 : FindBox(file, metaStart + 12, metaEnd, "pitm");
            int iprp = metaStart < 0 ? -1 : FindBox(file, metaStart + 12, metaEnd, "iprp");
            int iprpEnd = iprp < 0 ? -1 : iprp + (int)ReadUInt(file, iprp, 4);
            int ipco = iprp < 0 ? -1 : FindBox(file, iprp + 8, iprpEnd, "ipco");
            int ipma = iprp < 0 ? -1 : FindBox(file, iprp + 8, iprpEnd, "ipma");
            if (pitm < 0 || ipco < 0 || ipma < 0)
            {
                throw new InvalidDataException("The HEIF file has no pitm, ipco or ipma box.");
            }

            uint primary = file[pitm + 8] == 0 ? ReadUInt(file, pitm + 12, 2) : ReadUInt(file, pitm + 12, 4);

            // Offsets of the property boxes in ipco; ipma refers to them by 1-based index.
            List<int> propertyOffsets = new List<int>();
            int ipcoEnd = ipco + (int)ReadUInt(file, ipco, 4);
            for (int position = ipco + 8; position + 8 <= ipcoEnd; position += (int)ReadUInt(file, position, 4))
            {
                propertyOffsets.Add(position);
            }

            int ispe = -1;
            int clap = -1;
            int version = file[ipma + 8];
            bool wide = (file[ipma + 11] & 1) != 0;
            int cursor = ipma + 12;
            uint entryCount = ReadUInt(file, cursor, 4);
            cursor += 4;
            for (uint e = 0; e < entryCount; e++)
            {
                uint itemId = ReadUInt(file, cursor, version < 1 ? 2 : 4);
                cursor += version < 1 ? 2 : 4;
                int count = file[cursor++];
                for (int a = 0; a < count; a++)
                {
                    int index = wide ? (int)ReadUInt(file, cursor, 2) & 0x7FFF : file[cursor] & 0x7F;
                    cursor += wide ? 2 : 1;
                    if (itemId == primary && index >= 1 && index <= propertyOffsets.Count)
                    {
                        int offset = propertyOffsets[index - 1];
                        string type = System.Text.Encoding.ASCII.GetString(file, offset + 4, 4);
                        ispe = type == "ispe" ? offset : ispe;
                        clap = type == "clap" ? offset : clap;
                    }
                }
            }

            if (ispe < 0)
            {
                throw new InvalidDataException("The primary item of the HEIF file has no ispe property.");
            }

            // The offsets give the centre of the crop relative to the centre of the coded image, in
            // halves: (2 * left + width - codedWidth) / 2 puts the left edge of the crop at left.
            uint codedWidth = ReadUInt(file, ispe + 12, 4);
            uint codedHeight = ReadUInt(file, ispe + 16, 4);
            byte[] clapBox = new byte[40];
            WriteUInt(clapBox, 0, 40, 4);
            clapBox[4] = (byte)'c'; clapBox[5] = (byte)'l'; clapBox[6] = (byte)'a'; clapBox[7] = (byte)'p';
            WriteUInt(clapBox, 8, (uint)width, 4);
            WriteUInt(clapBox, 12, 1, 4);
            WriteUInt(clapBox, 16, (uint)height, 4);
            WriteUInt(clapBox, 20, 1, 4);
            WriteUInt(clapBox, 24, unchecked((uint)((2 * left) + width - (int)codedWidth)), 4);
            WriteUInt(clapBox, 28, 2, 4);
            WriteUInt(clapBox, 32, unchecked((uint)((2 * top) + height - (int)codedHeight)), 4);
            WriteUInt(clapBox, 36, 2, 4);

            if (clap < 0)
            {
                return AddProperty(file, clapBox, true, p => p[4] == 'c' && p[5] == 'l' && p[6] == 'a' && p[7] == 'p', id => id == primary);
            }

            if (ReadUInt(file, clap, 4) != 40)
            {
                throw new InvalidDataException("The clap box of the HEIF file does not have 40 bytes.");
            }

            byte[] result = (byte[])file.Clone();
            Buffer.BlockCopy(clapBox, 0, result, clap, 40);
            return result;
        }

        // Adds an "nclx" colour box (ISO/IEC 23008-12, ITU-T H.273 code points) to every image item
        // that has none, or only to the primary item. The WIC HEIF encoder converts RGB to YCbCr with
        // the BT.709 matrix but writes no nclx box and signals "matrix unspecified" in the HEVC VUI.
        // Readers then fall back to the HEIF default BT.601 (libheif, and with it ImageMagick, GIMP and
        // most Linux viewers), which turns pure red 255,0,0 into 232,0,3. libheif writes only the ICC
        // profile when an image has one, so its nclx values would reach readers only through the HEVC
        // VUI. The meta box grows, so the item offsets in iloc that point behind it move by the same
        // amount.
        internal static byte[] AddNclx(byte[] file, ushort primaries, ushort transfer, ushort matrix, bool fullRange, bool primaryOnly)
        {
            byte[] nclx = new byte[19];
            WriteUInt(nclx, 0, 19, 4);
            nclx[4] = (byte)'c'; nclx[5] = (byte)'o'; nclx[6] = (byte)'l'; nclx[7] = (byte)'r';
            nclx[8] = (byte)'n'; nclx[9] = (byte)'c'; nclx[10] = (byte)'l'; nclx[11] = (byte)'x';
            WriteUInt(nclx, 12, primaries, 2);
            WriteUInt(nclx, 14, transfer, 2);
            WriteUInt(nclx, 16, matrix, 2);
            nclx[18] = fullRange ? (byte)0x80 : (byte)0;

            // Not essential: a reader that ignores nclx still shows the image.
            uint primary = primaryOnly ? PrimaryItem(file) : 0;
            return AddProperty(file, nclx, false, p => p.Length >= 12 && p[4] == 'c' && p[5] == 'o' && p[6] == 'l' && p[7] == 'r' && p[8] == 'n' && p[9] == 'c' && p[10] == 'l' && p[11] == 'x', primaryOnly ? id => id == primary : null);
        }

        // Stores the EXIF block and the XMP packet as metadata items of the primary item, byte for
        // byte, as libheif does: an "Exif" item (the 4-byte offset of the TIFF header, then the block)
        // and a "mime" item of type application/rdf+xml, each with a "cdsc" reference to the primary
        // item. Their data goes into an mdat box at the end of the file. Nothing parses the blocks, so
        // a block that a program could not parse is kept, as the other output formats keep it.
        internal static byte[] AddMetadataItems(byte[] file, byte[] exif, byte[] xmp)
        {
            int metaStart = FindBox(file, 0, file.Length, "meta");
            if (metaStart < 0)
            {
                throw new InvalidDataException("The HEIF file has no meta box.");
            }

            int metaSize = (int)ReadUInt(file, metaStart, 4);
            int metaEnd = metaStart + metaSize;
            uint primary = PrimaryItem(file);
            List<KeyValuePair<string, byte[]>> metaChildren = Children(file, metaStart + 12, metaEnd);
            int iinfIndex = metaChildren.FindIndex(c => c.Key == "iinf");
            int ilocIndex = metaChildren.FindIndex(c => c.Key == "iloc");
            int irefIndex = metaChildren.FindIndex(c => c.Key == "iref");
            if (iinfIndex < 0 || ilocIndex < 0)
            {
                throw new InvalidDataException("The HEIF file has no iinf or iloc box.");
            }

            // The items to add: item type, content type of a mime item, data.
            List<(string Type, string ContentType, byte[] Data)> items = new List<(string Type, string ContentType, byte[] Data)>();
            if (exif != null)
            {
                // HEIF puts the offset of the TIFF header within the block in front of it: 6 after "Exif\0\0".
                bool exifHeader = exif.Length >= 6 && exif[0] == (byte)'E' && exif[1] == (byte)'x' && exif[2] == (byte)'i' && exif[3] == (byte)'f' && exif[4] == 0 && exif[5] == 0;
                byte[] data = new byte[exif.Length + 4];
                WriteUInt(data, 0, exifHeader ? 6u : 0u, 4);
                Buffer.BlockCopy(exif, 0, data, 4, exif.Length);
                items.Add(("Exif", null, data));
            }

            if (xmp != null)
            {
                items.Add(("mime", "application/rdf+xml", xmp));
            }

            byte[] iinf = metaChildren[iinfIndex].Value;
            byte[] iloc = metaChildren[ilocIndex].Value;
            int iinfVersion = iinf[8];
            int ilocVersion = iloc[8];
            int offsetSize = iloc[12] >> 4;
            int lengthSize = iloc[12] & 0xF;
            int baseOffsetSize = iloc[13] >> 4;
            int indexSize = ilocVersion >= 1 ? iloc[13] & 0xF : 0;
            int ilocIdSize = ilocVersion < 2 ? 2 : 4;
            if (offsetSize != 4 && offsetSize != 8)
            {
                throw new InvalidDataException("The iloc box of the HEIF file has no 4- or 8-byte extent offsets.");
            }

            // New item IDs follow the largest one in iinf.
            int countSize = iinfVersion == 0 ? 2 : 4;
            uint nextId = 0;
            foreach (KeyValuePair<string, byte[]> entry in Children(iinf, 12 + countSize, iinf.Length))
            {
                nextId = Math.Max(nextId, entry.Value[8] >= 3 ? ReadUInt(entry.Value, 12, 4) : ReadUInt(entry.Value, 12, 2));
            }

            nextId++;
            if (nextId + items.Count > 0xFFFF)
            {
                throw new InvalidDataException("The HEIF file has too many items to add metadata items.");
            }

            // infe version 2: item ID, protection index, item type, empty name, content type of a mime
            // item. Flag 1 hides the item, as libheif and the WIC encoder mark metadata items.
            List<byte[]> newEntries = new List<byte[]>();
            for (int i = 0; i < items.Count; i++)
            {
                MemoryStream body = new MemoryStream();
                WriteUInt(body, nextId + (uint)i, 2);
                WriteUInt(body, 0, 2);
                body.Write(System.Text.Encoding.ASCII.GetBytes(items[i].Type), 0, 4);
                body.WriteByte(0);
                if (items[i].ContentType != null)
                {
                    byte[] contentType = System.Text.Encoding.ASCII.GetBytes(items[i].ContentType);
                    body.Write(contentType, 0, contentType.Length);
                    body.WriteByte(0);
                }

                newEntries.Add(Box("infe", body.ToArray(), new byte[] { 2, 0, 0, 1 }));
            }

            // cdsc references from the new items to the primary item; a version 1 iref box has 32-bit
            // item IDs, version 0 (also a new box) 16-bit ones.
            byte[] iref = irefIndex < 0 ? null : metaChildren[irefIndex].Value;
            int irefIdSize = iref != null && iref[8] == 1 ? 4 : 2;
            List<byte[]> references = new List<byte[]>();
            for (int i = 0; i < items.Count; i++)
            {
                MemoryStream body = new MemoryStream();
                WriteUInt(body, nextId + (uint)i, irefIdSize);
                WriteUInt(body, 1, 2);
                WriteUInt(body, primary, irefIdSize);
                references.Add(Box("cdsc", body.ToArray(), null));
            }

            int ilocEntrySize = ilocIdSize + (ilocVersion >= 1 ? 2 : 0) + 2 + baseOffsetSize + 2 + indexSize + offsetSize + lengthSize;
            int delta = (items.Count * ilocEntrySize) + Sum(newEntries) + Sum(references) + (iref == null ? 12 : 0);

            // The meta box grows by delta, so the data behind it moves by delta; the new mdat box goes
            // at the end of the file, with the item data right after its 8-byte header.
            byte[] shiftedIloc = (byte[])iloc.Clone();
            ShiftItemLocations(shiftedIloc, metaEnd, delta);
            WriteUInt(shiftedIloc, 14, ReadUInt(shiftedIloc, 14, ilocIdSize) + (uint)items.Count, ilocIdSize);
            MemoryStream ilocBody = new MemoryStream();
            ilocBody.Write(shiftedIloc, 12, shiftedIloc.Length - 12);
            long dataPosition = file.Length + delta + 8;
            for (int i = 0; i < items.Count; i++)
            {
                WriteUInt(ilocBody, nextId + (uint)i, ilocIdSize);
                if (ilocVersion >= 1)
                {
                    // Reserved bits and construction method 0 (file offset).
                    WriteUInt(ilocBody, 0, 2);
                }

                WriteUInt(ilocBody, 0, 2);
                WriteULong(ilocBody, 0, baseOffsetSize);
                WriteUInt(ilocBody, 1, 2);
                WriteULong(ilocBody, 0, indexSize);
                WriteULong(ilocBody, (ulong)dataPosition, offsetSize);
                WriteULong(ilocBody, (ulong)items[i].Data.Length, lengthSize);
                dataPosition += items[i].Data.Length;
            }

            byte[] newIinf = new byte[iinf.Length + Sum(newEntries)];
            Buffer.BlockCopy(iinf, 0, newIinf, 0, iinf.Length);
            WriteUInt(newIinf, 0, (uint)newIinf.Length, 4);
            WriteUInt(newIinf, 12, ReadUInt(newIinf, 12, countSize) + (uint)items.Count, countSize);
            int at = iinf.Length;
            foreach (byte[] entry in newEntries)
            {
                Buffer.BlockCopy(entry, 0, newIinf, at, entry.Length);
                at += entry.Length;
            }

            MemoryStream irefBody = new MemoryStream();
            if (iref != null)
            {
                irefBody.Write(iref, 12, iref.Length - 12);
            }

            foreach (byte[] reference in references)
            {
                irefBody.Write(reference, 0, reference.Length);
            }

            metaChildren[iinfIndex] = new KeyValuePair<string, byte[]>("iinf", newIinf);
            metaChildren[ilocIndex] = new KeyValuePair<string, byte[]>("iloc", Box("iloc", ilocBody.ToArray(), Header(iloc)));
            byte[] newIref = Box("iref", irefBody.ToArray(), iref == null ? new byte[4] : Header(iref));
            if (iref == null)
            {
                metaChildren.Add(new KeyValuePair<string, byte[]>("iref", newIref));
            }
            else
            {
                metaChildren[irefIndex] = new KeyValuePair<string, byte[]>("iref", newIref);
            }

            byte[] newMeta = Box("meta", Concat(metaChildren), Header(file, metaStart));
            if (newMeta.Length - metaSize != delta)
            {
                throw new InvalidDataException("The meta box of the HEIF file did not grow as computed.");
            }

            MemoryStream mdatBody = new MemoryStream();
            foreach ((string Type, string ContentType, byte[] Data) item in items)
            {
                mdatBody.Write(item.Data, 0, item.Data.Length);
            }

            byte[] mdat = Box("mdat", mdatBody.ToArray(), null);
            byte[] result = new byte[file.Length + delta + mdat.Length];
            Buffer.BlockCopy(file, 0, result, 0, metaStart);
            Buffer.BlockCopy(newMeta, 0, result, metaStart, newMeta.Length);
            Buffer.BlockCopy(file, metaEnd, result, metaStart + newMeta.Length, file.Length - metaEnd);
            Buffer.BlockCopy(mdat, 0, result, file.Length + delta, mdat.Length);
            return result;
        }

        // Stores every item whose extents follow each other without a gap as one extent. libheif 1.17
        // and older store each slice of a coded image as an extent of its own, and Windows' own HEIF
        // decoder (Photos, Explorer) refuses an item of several extents (E_UNEXPECTED); it opens the
        // same data as one extent, as libheif 1.21 and later write it. The data of an item is its
        // extents one after the other, so it stays the same. Items with extent indexes or without
        // offset or length fields, items of construction method 2 (data of other items) and extents
        // with gaps are left as they are. The meta box shrinks, so the item offsets in iloc that point
        // behind it move back by the same amount.
        internal static byte[] MergeContiguousExtents(byte[] file)
        {
            int metaStart = FindBox(file, 0, file.Length, "meta");
            if (metaStart < 0)
            {
                throw new InvalidDataException("The HEIF file has no meta box.");
            }

            int metaSize = (int)ReadUInt(file, metaStart, 4);
            int metaEnd = metaStart + metaSize;
            List<KeyValuePair<string, byte[]>> metaChildren = Children(file, metaStart + 12, metaEnd);
            int ilocIndex = metaChildren.FindIndex(c => c.Key == "iloc");
            if (ilocIndex < 0)
            {
                throw new InvalidDataException("The HEIF file has no iloc box.");
            }

            byte[] iloc = metaChildren[ilocIndex].Value;
            int version = iloc[8];
            int offsetSize = iloc[12] >> 4;
            int lengthSize = iloc[12] & 0xF;
            int baseOffsetSize = iloc[13] >> 4;
            int indexSize = version >= 1 ? iloc[13] & 0xF : 0;
            int idSize = version < 2 ? 2 : 4;
            if (offsetSize == 0 || lengthSize == 0 || indexSize != 0)
            {
                return file;
            }

            // The body of the new iloc box: the field sizes and the item count as they are, then
            // every item, with one extent where its extents follow each other.
            MemoryStream body = new MemoryStream();
            body.Write(iloc, 12, 2 + idSize);
            int position = 14;
            uint itemCount = ReadUInt(iloc, position, idSize);
            position += idSize;
            bool merged = false;
            for (uint i = 0; i < itemCount; i++)
            {
                int entryStart = position;
                position += idSize;
                int constructionMethod = 0;
                if (version >= 1)
                {
                    constructionMethod = iloc[position + 1] & 0xF;
                    position += 2;
                }

                position += 2 + baseOffsetSize;
                int extentCountPosition = position;
                int extentCount = (int)ReadUInt(iloc, position, 2);
                position += 2;
                ulong firstOffset = 0;
                ulong end = 0;
                bool contiguous = constructionMethod <= 1;
                for (int e = 0; e < extentCount; e++)
                {
                    ulong offset = ReadULong(iloc, position, offsetSize);
                    ulong length = ReadULong(iloc, position + offsetSize, lengthSize);
                    position += offsetSize + lengthSize;
                    if (e == 0)
                    {
                        firstOffset = offset;
                    }
                    else if (offset != end)
                    {
                        contiguous = false;
                    }

                    end = offset + length;
                    if (end < offset)
                    {
                        contiguous = false;
                    }
                }

                // The lengths added up must fit the length field.
                ulong total = end - firstOffset;
                if (extentCount > 1 && contiguous && (lengthSize == 8 || total >> (lengthSize * 8) == 0))
                {
                    body.Write(iloc, entryStart, extentCountPosition - entryStart);
                    WriteUInt(body, 1, 2);
                    WriteULong(body, firstOffset, offsetSize);
                    WriteULong(body, total, lengthSize);
                    merged = true;
                }
                else
                {
                    body.Write(iloc, entryStart, position - entryStart);
                }
            }

            if (!merged)
            {
                return file;
            }

            body.Write(iloc, position, iloc.Length - position);
            metaChildren[ilocIndex] = new KeyValuePair<string, byte[]>("iloc", Box("iloc", body.ToArray(), Header(iloc)));
            byte[] newMeta = Box("meta", Concat(metaChildren), Header(file, metaStart));
            int delta = newMeta.Length - metaSize;

            int newIloc = FindBox(newMeta, 12, newMeta.Length, "iloc");
            byte[] shiftedIloc = new byte[ReadUInt(newMeta, newIloc, 4)];
            Buffer.BlockCopy(newMeta, newIloc, shiftedIloc, 0, shiftedIloc.Length);
            ShiftItemLocations(shiftedIloc, metaEnd, delta);
            Buffer.BlockCopy(shiftedIloc, 0, newMeta, newIloc, shiftedIloc.Length);

            byte[] result = new byte[file.Length + delta];
            Buffer.BlockCopy(file, 0, result, 0, metaStart);
            Buffer.BlockCopy(newMeta, 0, result, metaStart, newMeta.Length);
            Buffer.BlockCopy(file, metaEnd, result, metaStart + newMeta.Length, file.Length - metaEnd);
            return result;
        }

        // Measures the HEVC slices of every coded image (hvc1 item, so also an alpha image) of a HEIF
        // file: returns the most slices that one image has and the length in bytes of the largest
        // slice (VCL NAL unit, types 0 to 31) of all of them. In an item every NAL unit is prefixed
        // with its length, in lengthSizeMinusOne + 1 bytes of the item's hvcC property. Items in the
        // file (construction method 0) and in idat (1) are read.
        internal static (int Slices, int LargestSlice) MeasureSlices(byte[] file)
        {
            int metaStart = FindBox(file, 0, file.Length, "meta");
            int metaEnd = metaStart < 0 ? -1 : metaStart + (int)ReadUInt(file, metaStart, 4);
            int iinf = metaStart < 0 ? -1 : FindBox(file, metaStart + 12, metaEnd, "iinf");
            int iloc = metaStart < 0 ? -1 : FindBox(file, metaStart + 12, metaEnd, "iloc");
            int idat = metaStart < 0 ? -1 : FindBox(file, metaStart + 12, metaEnd, "idat");
            int iprp = metaStart < 0 ? -1 : FindBox(file, metaStart + 12, metaEnd, "iprp");
            int iprpEnd = iprp < 0 ? -1 : iprp + (int)ReadUInt(file, iprp, 4);
            int ipco = iprp < 0 ? -1 : FindBox(file, iprp + 8, iprpEnd, "ipco");
            int ipma = iprp < 0 ? -1 : FindBox(file, iprp + 8, iprpEnd, "ipma");
            if (iinf < 0 || iloc < 0 || ipco < 0 || ipma < 0)
            {
                throw new InvalidDataException("The HEIF file has no iinf, iloc, ipco or ipma box.");
            }

            // iinf: the hvc1 items; an infe box of version 2 has a 16-bit item ID, version 3 a 32-bit one.
            HashSet<uint> codedItems = new HashSet<uint>();
            foreach (int entry in BoxOffsets(file, iinf + 12 + (file[iinf + 8] == 0 ? 2 : 4), iinf + (int)ReadUInt(file, iinf, 4)))
            {
                int infeVersion = file[entry + 8];
                int idSize = infeVersion == 2 ? 2 : 4;
                if (infeVersion >= 2 && System.Text.Encoding.ASCII.GetString(file, entry + 12 + idSize + 2, 4) == "hvc1")
                {
                    codedItems.Add(ReadUInt(file, entry + 12, idSize));
                }
            }

            // ipco and ipma: the NAL length size from the hvcC property of each hvc1 item.
            List<int> properties = BoxOffsets(file, ipco + 8, ipco + (int)ReadUInt(file, ipco, 4));
            Dictionary<uint, int> nalLengthSizes = new Dictionary<uint, int>();
            int ipmaVersion = file[ipma + 8];
            bool wide = (file[ipma + 11] & 1) != 0;
            int cursor = ipma + 12;
            uint entryCount = ReadUInt(file, cursor, 4);
            cursor += 4;
            for (uint e = 0; e < entryCount; e++)
            {
                uint itemId = ReadUInt(file, cursor, ipmaVersion < 1 ? 2 : 4);
                cursor += ipmaVersion < 1 ? 2 : 4;
                int count = file[cursor++];
                for (int a = 0; a < count; a++)
                {
                    int index = wide ? (int)ReadUInt(file, cursor, 2) & 0x7FFF : file[cursor] & 0x7F;
                    cursor += wide ? 2 : 1;
                    if (codedItems.Contains(itemId) && index >= 1 && index <= properties.Count)
                    {
                        int property = properties[index - 1];
                        if (System.Text.Encoding.ASCII.GetString(file, property + 4, 4) == "hvcC" && ReadUInt(file, property, 4) >= 31)
                        {
                            nalLengthSizes[itemId] = (file[property + 8 + 21] & 3) + 1;
                        }
                    }
                }
            }

            // iloc: the bytes of each hvc1 item, then its NAL units.
            int version = file[iloc + 8];
            int position = iloc + 12;
            int offsetSize = file[position] >> 4;
            int lengthSize = file[position] & 0xF;
            int baseOffsetSize = file[position + 1] >> 4;
            int indexSize = version >= 1 ? file[position + 1] & 0xF : 0;
            int ilocIdSize = version < 2 ? 2 : 4;
            position += 2;
            uint itemCount = ReadUInt(file, position, ilocIdSize);
            position += ilocIdSize;
            int slices = 0;
            int largest = 0;
            for (uint i = 0; i < itemCount; i++)
            {
                uint itemId = ReadUInt(file, position, ilocIdSize);
                position += ilocIdSize;
                int constructionMethod = 0;
                if (version >= 1)
                {
                    constructionMethod = file[position + 1] & 0xF;
                    position += 2;
                }

                position += 2;
                ulong baseOffset = ReadULong(file, position, baseOffsetSize);
                position += baseOffsetSize;
                int extentCount = (int)ReadUInt(file, position, 2);
                position += 2;
                MemoryStream data = new MemoryStream();
                for (int extent = 0; extent < extentCount; extent++)
                {
                    position += indexSize;
                    ulong offset = ReadULong(file, position, offsetSize);
                    position += offsetSize;
                    ulong length = ReadULong(file, position, lengthSize);
                    position += lengthSize;
                    if (codedItems.Contains(itemId))
                    {
                        ulong start = baseOffset + offset + (constructionMethod == 1 && idat >= 0 ? (ulong)idat + 8 : 0);
                        if ((constructionMethod != 0 && (constructionMethod != 1 || idat < 0)) || start + length > (ulong)file.Length)
                        {
                            throw new InvalidDataException("An HEVC item of the HEIF file lies outside the file.");
                        }

                        data.Write(file, (int)start, (int)length);
                    }
                }

                if (codedItems.Contains(itemId))
                {
                    if (!nalLengthSizes.TryGetValue(itemId, out int nalLengthSize))
                    {
                        throw new InvalidDataException("An HEVC item of the HEIF file has no hvcC property.");
                    }

                    (int itemSlices, int itemLargest) = ScanNalUnits(data.GetBuffer(), (int)data.Length, nalLengthSize);
                    slices = Math.Max(slices, itemSlices);
                    largest = Math.Max(largest, itemLargest);
                }
            }

            return (slices, largest);
        }

        // Counts the VCL NAL units (slices) among the length-prefixed NAL units of an HEVC item and
        // returns their number and the length of the largest one.
        private static (int Slices, int Largest) ScanNalUnits(byte[] data, int end, int nalLengthSize)
        {
            int slices = 0;
            int largest = 0;
            int position = 0;
            while (position + nalLengthSize < end)
            {
                ulong length = ReadULong(data, position, nalLengthSize);
                position += nalLengthSize;
                if (length > (ulong)(end - position))
                {
                    throw new InvalidDataException("A NAL unit of an HEVC item of the HEIF file is longer than the item.");
                }

                // The NAL unit type is bits 1 to 6 of the first header byte.
                if (length > 0 && ((data[position] >> 1) & 0x3F) < 32)
                {
                    slices++;
                    largest = Math.Max(largest, (int)length);
                }

                position += (int)length;
            }

            return (slices, largest);
        }

        // The offsets of the boxes between start and end.
        private static List<int> BoxOffsets(byte[] data, int start, int end)
        {
            List<int> offsets = new List<int>();
            int position = start;
            while (position + 8 <= end)
            {
                uint size = ReadUInt(data, position, 4);
                if (size < 8 || position + size > end)
                {
                    throw new InvalidDataException("A HEIF box has an invalid size.");
                }

                offsets.Add(position);
                position += (int)size;
            }

            return offsets;
        }

        // The ID of the primary item (pitm).
        private static uint PrimaryItem(byte[] file)
        {
            int metaStart = FindBox(file, 0, file.Length, "meta");
            int pitm = metaStart < 0 ? -1 : FindBox(file, metaStart + 12, metaStart + (int)ReadUInt(file, metaStart, 4), "pitm");
            if (pitm < 0)
            {
                throw new InvalidDataException("The HEIF file has no pitm box.");
            }

            return file[pitm + 8] == 0 ? ReadUInt(file, pitm + 12, 2) : ReadUInt(file, pitm + 12, 4);
        }

        // Adds a property box to ipco and associates it with every item in ipma that has no property
        // for which matches() is true.
        private static byte[] AddProperty(byte[] file, byte[] newProperty, bool essential, Func<byte[], bool> matches, Func<uint, bool> itemFilter = null)
        {
            int metaStart = FindBox(file, 0, file.Length, "meta");
            if (metaStart < 0)
            {
                throw new InvalidDataException("The HEIF file has no meta box.");
            }

            int metaSize = (int)ReadUInt(file, metaStart, 4);
            int metaEnd = metaStart + metaSize;
            List<KeyValuePair<string, byte[]>> metaChildren = Children(file, metaStart + 12, metaEnd);
            int iprpIndex = metaChildren.FindIndex(c => c.Key == "iprp");
            if (iprpIndex < 0)
            {
                throw new InvalidDataException("The HEIF file has no iprp box.");
            }

            byte[] iprp = metaChildren[iprpIndex].Value;
            List<KeyValuePair<string, byte[]>> iprpChildren = Children(iprp, 8, iprp.Length);
            int ipcoIndex = iprpChildren.FindIndex(c => c.Key == "ipco");
            int ipmaIndex = iprpChildren.FindIndex(c => c.Key == "ipma");
            if (ipcoIndex < 0 || ipmaIndex < 0)
            {
                throw new InvalidDataException("The HEIF file has no ipco or ipma box.");
            }

            byte[] ipco = iprpChildren[ipcoIndex].Value;
            List<KeyValuePair<string, byte[]>> properties = Children(ipco, 8, ipco.Length);
            HashSet<int> matchingIndexes = new HashSet<int>();
            for (int i = 0; i < properties.Count; i++)
            {
                if (matches(properties[i].Value))
                {
                    matchingIndexes.Add(i + 1);
                }
            }

            // ipma: version, flags (bit 0: 15-bit indexes), entry count, then per item its ID and
            // its associations (essential bit, property index).
            byte[] ipma = iprpChildren[ipmaIndex].Value;
            int version = ipma[8];
            bool wide = (ipma[11] & 1) != 0;
            int position = 12;
            uint entryCount = ReadUInt(ipma, position, 4);
            position += 4;
            List<KeyValuePair<uint, List<(bool Essential, int Index)>>> entries = new List<KeyValuePair<uint, List<(bool Essential, int Index)>>>();
            for (uint e = 0; e < entryCount; e++)
            {
                uint itemId = ReadUInt(ipma, position, version < 1 ? 2 : 4);
                position += version < 1 ? 2 : 4;
                int count = ipma[position++];
                List<(bool Essential, int Index)> associations = new List<(bool Essential, int Index)>();
                for (int a = 0; a < count; a++)
                {
                    int value = wide ? (int)ReadUInt(ipma, position, 2) : ipma[position];
                    position += wide ? 2 : 1;
                    associations.Add(wide ? ((value & 0x8000) != 0, value & 0x7FFF) : ((value & 0x80) != 0, value & 0x7F));
                }

                entries.Add(new KeyValuePair<uint, List<(bool Essential, int Index)>>(itemId, associations));
            }

            int newIndex = properties.Count + 1;
            bool changed = false;
            foreach (KeyValuePair<uint, List<(bool Essential, int Index)>> entry in entries)
            {
                if ((itemFilter == null || itemFilter(entry.Key)) && !entry.Value.Exists(a => matchingIndexes.Contains(a.Index)))
                {
                    // HEIF lists the descriptive properties of an item before its transformative
                    // ones (clap, irot, imir), which are applied in the order they are listed.
                    int at = entry.Value.Count;
                    if (!IsTransformative(newProperty))
                    {
                        int first = entry.Value.FindIndex(a => a.Index >= 1 && a.Index <= properties.Count && IsTransformative(properties[a.Index - 1].Value));
                        at = first < 0 ? at : first;
                    }

                    entry.Value.Insert(at, (essential, newIndex));
                    changed = true;
                }
            }

            if (!changed)
            {
                return file;
            }

            properties.Add(new KeyValuePair<string, byte[]>("new", newProperty));
            bool newWide = wide || newIndex > 0x7F;
            MemoryStream ipmaBody = new MemoryStream();
            ipmaBody.WriteByte((byte)version);
            ipmaBody.WriteByte(ipma[9]);
            ipmaBody.WriteByte(ipma[10]);
            ipmaBody.WriteByte((byte)((ipma[11] & 0xFE) | (newWide ? 1 : 0)));
            WriteUInt(ipmaBody, entryCount, 4);
            foreach (KeyValuePair<uint, List<(bool Essential, int Index)>> entry in entries)
            {
                WriteUInt(ipmaBody, entry.Key, version < 1 ? 2 : 4);
                ipmaBody.WriteByte((byte)entry.Value.Count);
                foreach ((bool Essential, int Index) association in entry.Value)
                {
                    if (newWide)
                    {
                        WriteUInt(ipmaBody, (uint)((association.Essential ? 0x8000 : 0) | association.Index), 2);
                    }
                    else
                    {
                        ipmaBody.WriteByte((byte)((association.Essential ? 0x80 : 0) | association.Index));
                    }
                }
            }

            iprpChildren[ipcoIndex] = new KeyValuePair<string, byte[]>("ipco", Box("ipco", Concat(properties), null));
            iprpChildren[ipmaIndex] = new KeyValuePair<string, byte[]>("ipma", Box("ipma", ipmaBody.ToArray(), null));
            metaChildren[iprpIndex] = new KeyValuePair<string, byte[]>("iprp", Box("iprp", Concat(iprpChildren), null));

            byte[] newMeta = Box("meta", Concat(metaChildren), Header(file, metaStart));
            int delta = newMeta.Length - metaSize;
            int iloc = FindBox(newMeta, 12, newMeta.Length, "iloc");
            if (iloc < 0)
            {
                throw new InvalidDataException("The HEIF file has no iloc box.");
            }

            byte[] shiftedIloc = new byte[ReadUInt(newMeta, iloc, 4)];
            Buffer.BlockCopy(newMeta, iloc, shiftedIloc, 0, shiftedIloc.Length);
            ShiftItemLocations(shiftedIloc, metaEnd, delta);
            Buffer.BlockCopy(shiftedIloc, 0, newMeta, iloc, shiftedIloc.Length);

            byte[] result = new byte[file.Length + delta];
            Buffer.BlockCopy(file, 0, result, 0, metaStart);
            Buffer.BlockCopy(newMeta, 0, result, metaStart, newMeta.Length);
            Buffer.BlockCopy(file, metaEnd, result, metaStart + newMeta.Length, file.Length - metaEnd);
            return result;
        }

        private static bool IsTransformative(byte[] property)
        {
            string type = System.Text.Encoding.ASCII.GetString(property, 4, 4);
            return type == "clap" || type == "irot" || type == "imir";
        }

        // Moves every file offset in an iloc box (construction method 0) that points behind the old
        // meta box by delta bytes: forward when the meta box grew, back when it shrank.
        private static void ShiftItemLocations(byte[] iloc, int oldMetaEnd, int delta)
        {
            int version = iloc[8];
            int position = 12;
            int offsetSize = iloc[position] >> 4;
            int lengthSize = iloc[position] & 0xF;
            int baseOffsetSize = iloc[position + 1] >> 4;
            int indexSize = version >= 1 ? iloc[position + 1] & 0xF : 0;
            position += 2;
            uint itemCount = ReadUInt(iloc, position, version < 2 ? 2 : 4);
            position += version < 2 ? 2 : 4;
            for (uint i = 0; i < itemCount; i++)
            {
                position += version < 2 ? 2 : 4;
                int constructionMethod = 0;
                if (version >= 1)
                {
                    constructionMethod = iloc[position + 1] & 0xF;
                    position += 2;
                }

                position += 2;
                bool fileOffsets = constructionMethod == 0;
                bool baseShifted = false;
                ulong baseOffset = 0;
                if (baseOffsetSize > 0)
                {
                    baseOffset = ReadULong(iloc, position, baseOffsetSize);
                    if (fileOffsets && baseOffset >= (ulong)oldMetaEnd)
                    {
                        WriteULong(iloc, position, (ulong)((long)baseOffset + delta), baseOffsetSize);
                        baseShifted = true;
                    }
                }

                position += baseOffsetSize;
                int extentCount = (int)ReadUInt(iloc, position, 2);
                position += 2;
                for (int e = 0; e < extentCount; e++)
                {
                    position += indexSize;
                    if (offsetSize > 0)
                    {
                        ulong offset = ReadULong(iloc, position, offsetSize);
                        if (fileOffsets && !baseShifted && baseOffset + offset >= (ulong)oldMetaEnd)
                        {
                            WriteULong(iloc, position, (ulong)((long)offset + delta), offsetSize);
                        }
                    }

                    position += offsetSize + lengthSize;
                }
            }
        }

        private static int FindBox(byte[] data, int start, int end, string type)
        {
            int position = start;
            while (position + 8 <= end)
            {
                uint size = ReadUInt(data, position, 4);
                if (size < 8 || position + size > end)
                {
                    return -1;
                }

                if (data[position + 4] == type[0] && data[position + 5] == type[1] && data[position + 6] == type[2] && data[position + 7] == type[3])
                {
                    return position;
                }

                position += (int)size;
            }

            return -1;
        }

        private static List<KeyValuePair<string, byte[]>> Children(byte[] data, int start, int end)
        {
            List<KeyValuePair<string, byte[]>> children = new List<KeyValuePair<string, byte[]>>();
            int position = start;
            while (position + 8 <= end)
            {
                uint size = ReadUInt(data, position, 4);
                if (size < 8 || position + size > end)
                {
                    throw new InvalidDataException("A HEIF box has an invalid size.");
                }

                byte[] box = new byte[size];
                Buffer.BlockCopy(data, position, box, 0, (int)size);
                children.Add(new KeyValuePair<string, byte[]>(System.Text.Encoding.ASCII.GetString(data, position + 4, 4), box));
                position += (int)size;
            }

            return children;
        }

        private static byte[] Box(string type, byte[] body, byte[] fullBoxHeader)
        {
            int headerLength = 8 + (fullBoxHeader == null ? 0 : 4);
            byte[] box = new byte[headerLength + body.Length];
            WriteUInt(box, 0, (uint)box.Length, 4);
            for (int i = 0; i < 4; i++)
            {
                box[4 + i] = (byte)type[i];
            }

            if (fullBoxHeader != null)
            {
                Buffer.BlockCopy(fullBoxHeader, 0, box, 8, 4);
            }

            Buffer.BlockCopy(body, 0, box, headerLength, body.Length);
            return box;
        }

        private static byte[] Concat(List<KeyValuePair<string, byte[]>> boxes)
        {
            MemoryStream stream = new MemoryStream();
            foreach (KeyValuePair<string, byte[]> box in boxes)
            {
                stream.Write(box.Value, 0, box.Value.Length);
            }

            return stream.ToArray();
        }

        private static uint ReadUInt(byte[] data, int position, int size)
        {
            return (uint)ReadULong(data, position, size);
        }

        private static ulong ReadULong(byte[] data, int position, int size)
        {
            ulong value = 0;
            for (int i = 0; i < size; i++)
            {
                value = value << 8 | data[position + i];
            }

            return value;
        }

        private static void WriteUInt(byte[] data, int position, uint value, int size)
        {
            WriteULong(data, position, value, size);
        }

        private static void WriteULong(byte[] data, int position, ulong value, int size)
        {
            if (size < 8 && value >> (size * 8) != 0)
            {
                throw new InvalidDataException("A HEIF item offset does not fit its field after the meta box grew.");
            }

            for (int i = size - 1; i >= 0; i--)
            {
                data[position + i] = (byte)value;
                value >>= 8;
            }
        }

        private static void WriteUInt(MemoryStream stream, uint value, int size)
        {
            WriteULong(stream, value, size);
        }

        private static void WriteULong(MemoryStream stream, ulong value, int size)
        {
            if (size < 8 && value >> (size * 8) != 0)
            {
                throw new InvalidDataException("A HEIF field value does not fit its field.");
            }

            for (int i = size - 1; i >= 0; i--)
            {
                stream.WriteByte((byte)(value >> (i * 8)));
            }
        }

        // The version and flags of a full box.
        private static byte[] Header(byte[] data, int box = 0)
        {
            byte[] header = new byte[4];
            Buffer.BlockCopy(data, box + 8, header, 0, 4);
            return header;
        }

        private static int Sum(List<byte[]> boxes)
        {
            int length = 0;
            foreach (byte[] box in boxes)
            {
                length += box.Length;
            }

            return length;
        }
    }
}
