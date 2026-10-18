# PSImageConverter

Cross-platform PowerShell 7 module for converting images — HEIC/HEIF photos from an iPhone, but also JPEG, PNG, WebP and every other format [Magick.NET](https://github.com/dlemstra/Magick.NET) can read — to JPEG, PNG, WebP, AVIF, HEIC, JPEG XL, TIFF, BMP or GIF.

- Works on PowerShell 7.4 or later on Windows, Linux and macOS (x64 and arm64; Alpine/musl Linux: x64 only)
- No codecs or ImageMagick installation needed — the native library is bundled; only HEIC output needs the HEVC encoder of the operating system (see [Writing HEIC files](#writing-heic-files))
- Pipeline-friendly (`Get-ChildItem | ConvertTo-WebP | Get-ImageInfo`), `-WhatIf`, applies the EXIF orientation, keeps the metadata the output format can carry unless you strip it
- Never overwrites the source file, also not when its folder is reached through a junction, a symbolic link or another drive letter, and a failed or stopped conversion never leaves a truncated or temporary file behind

## Installation

PSImageConverter is published on the [PowerShell Gallery](https://www.powershellgallery.com/packages/PSImageConverter/):

```powershell
Install-Module -Name PSImageConverter -Scope CurrentUser
```

Pre-releases are published from the `dev` branch (e.g. `0.2.0-preview0013`). There is no stable release yet, so for now install a pre-release:

```powershell
Install-Module -Name PSImageConverter -Scope CurrentUser -AllowPrerelease
```

## Usage

```powershell
# Convert an iPhone photo to JPEG next to the original
ConvertFrom-Heic -Path .\IMG_1234.HEIC

# Convert a folder of HEIC photos to PNG into another folder
Get-ChildItem -Path C:\Pictures -Filter *.heic | ConvertFrom-Heic -Format Png -DestinationPath C:\Pictures\png

# JPEG with quality 80, remove location data and other metadata, overwrite existing files
Get-ChildItem -Path ~/Photos -Filter *.heic -Recurse | ConvertFrom-Heic -Quality 80 -StripMetadata -Force

# Any readable image to WebP for a website; -WhatIf shows what would be written
Get-ChildItem -Path .\site\images -Recurse -Include *.jpg, *.png | ConvertTo-WebP -Quality 80 -WhatIf

# Smaller copies of existing JPEG files in another folder
ConvertTo-Jpeg -Path .\scans\*.jpg -Quality 60 -DestinationPath .\small

# Write HEIC with the HEVC encoder of the operating system
ConvertTo-Heic -Path .\export\*.png -Quality 80 -DestinationPath .\heic

# Formats without a ConvertTo-* shortcut
Convert-Image -Path .\IMG_1234.HEIC -Format Tiff

# Inspect photos, sorted by the date they were taken
Get-ChildItem -Path C:\Pictures -Filter *.heic | Get-ImageInfo | Sort-Object -Property DateTaken

# Convert only the photos wider than 4000 pixels
Get-ImageInfo -Path .\*.heic | Where-Object -Property Width -GT 4000 | ConvertTo-Jpeg -Quality 85
```

| Cmdlet             | Purpose                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------- |
| `Convert-Image`    | Converts any readable image to the `-Format` Jpeg, Png, WebP, Avif, Heic, Jxl, Tiff, Bmp or Gif |
| `ConvertTo-Jpeg`   | `Convert-Image -Format Jpeg`, same parameters without `-Format`                             |
| `ConvertTo-Png`    | `Convert-Image -Format Png`, same parameters without `-Format` and `-Quality` (lossless)     |
| `ConvertTo-WebP`   | `Convert-Image -Format WebP`, same parameters without `-Format`                             |
| `ConvertTo-Avif`   | `Convert-Image -Format Avif`, same parameters without `-Format`                             |
| `ConvertTo-Heic`   | `Convert-Image -Format Heic`, same parameters without `-Format`; needs the HEVC encoder of the operating system |
| `ConvertTo-JpegXL` | `Convert-Image -Format Jxl`, same parameters without `-Format`                              |
| `ConvertFrom-Heic` | Converts HEIC/HEIF files only (`.heic`, `.heif`, `.hif`); `-Format` defaults to Jpeg        |
| `Get-ImageInfo`    | Returns format, size, orientation, camera and date taken of an image; pipes into the others |

All conversion cmdlets take `-Path` (wildcards, strings from the pipeline) or `-LiteralPath` (aliases `PSPath` and `LP`; files from `Get-ChildItem` and the objects of `Get-ImageInfo` bind here; folders are skipped), `-DestinationPath`, `-StripMetadata`, `-Force`, `-WhatIf` and `-Confirm`, and return a `FileInfo` for every written file — the same object `Get-Item` returns, so it can be piped into the next cmdlet even when its name contains `[` or `]`. The output gets the source's base name and the extension of the format, next to the source or in `-DestinationPath`. A file given more than once in a call (e.g. by the overlapping patterns `*.heic` and `IMG_*`) is converted or described once.

Wildcards follow PowerShell's globbing, which skips hidden files and folders (on Windows those with the Hidden attribute, on Linux and macOS names that start with a dot), as `Get-ChildItem` does without `-Force`; `-LiteralPath`, a folder name without wildcards and `Get-ChildItem -Force | ...` reach them.

Like compiled cmdlets, the cmdlets follow the preference variables of their caller (`$WhatIfPreference`, `$ConfirmPreference`, `$ErrorActionPreference`, `$WarningPreference`, `$InformationPreference`, `$VerbosePreference`, `$DebugPreference`), also when a script or function sets them in its own scope: a function with `SupportsShouldProcess` that is called with `-WhatIf` passes it on, and `$ErrorActionPreference = 'Stop'` in a script makes the first error terminating. A common parameter given to the cmdlet itself wins.

## Formats

The source format is detected from the file content; every format Magick.NET can read is accepted, including HEIC/HEIF.

| Output    | `-Format` | Extension | Shortcut           | `-Quality` (1–100, default 90) | Metadata kept without `-StripMetadata`      |
| --------- | --------- | --------- | ------------------ | ------------------------------ | ------------------------------------------- |
| JPEG      | `Jpeg`    | `.jpg`    | `ConvertTo-Jpeg`   | yes                            | EXIF, XMP, IPTC, ICC colour profile, comments |
| PNG       | `Png`     | `.png`    | `ConvertTo-Png`    | no (lossless)                  | EXIF, XMP, IPTC, ICC colour profile, comments |
| WebP      | `WebP`    | `.webp`   | `ConvertTo-WebP`   | yes                            | EXIF, XMP, ICC colour profile               |
| AVIF      | `Avif`    | `.avif`   | `ConvertTo-Avif`   | yes                            | EXIF, XMP, ICC colour profile               |
| HEIC      | `Heic`    | `.heic`   | `ConvertTo-Heic`   | yes                            | Windows, Linux: EXIF, XMP, ICC colour profile; macOS: ICC colour profile (sRGB as `nclx` colour information), no EXIF or XMP. Written with the encoder of the operating system, see [Writing HEIC files](#writing-heic-files) |
| JPEG XL   | `Jxl`     | `.jxl`    | `ConvertTo-JpegXL` | yes                            | EXIF, XMP; ICC colour profile only at `-Quality 100` |
| TIFF      | `Tiff`    | `.tif`    | —                  | no                             | XMP, IPTC, ICC colour profile, comments     |
| BMP       | `Bmp`     | `.bmp`    | —                  | no                             | ICC colour profile                          |
| GIF       | `Gif`     | `.gif`    | —                  | no                             | IPTC, ICC colour profile (browsers ignore it in GIF files), comments |

- The bundled Magick.NET build writes no EXIF data (date taken, camera, GPS location) to TIFF, BMP and GIF output, and neither does ImageIO to HEIC output on macOS; the cmdlets write a warning for every source with EXIF data unless `-StripMetadata` is used.
- `-StripMetadata` removes EXIF (including the GPS location), XMP, IPTC and comments but keeps the ICC colour profile.
- The colours are kept when the source carries an ICC profile, as iPhone photos do (e.g. Display P3). A HEIC or AVIF source that signals its colours only through nclx/CICP (no ICC profile) with primaries other than sRGB/BT.709 (e.g. Display P3 or BT.2020, also HDR with PQ or HLG) is converted without colour conversion, so its colours look less saturated; AVIF output keeps the CICP values.
- Lossy JPEG XL (`-Quality` below 100, the default is 90) is always sRGB: the bundled encoder stores an ICC colour profile only in lossless files. The pixels of a source with an ICC profile (e.g. Display P3 or Adobe RGB) are converted to sRGB first, with and without `-StripMetadata`, so the photo looks the same; colours outside sRGB are clipped. Use `-Quality 100` or AVIF to keep a wide gamut. A grey profile in a colour image, which viewers ignore, is ignored here as well. Chrome shows a lossless JPEG XL whose profile describes its tone curve as a table (e.g. Photoshop's "Dot Gain 20%" grey profiles) without colour management; Firefox applies such a profile, and profiles with gamma or parametric curves (Adobe RGB, Display P3) work in both.
- Bytes after the size the header of an ICC profile declares are not part of the profile (Samsung Galaxy HEIC photos, for example, have two zero bytes there, and so do JPEGs converted from them). The profile is written without them in every output format, with unchanged colours (`-Verbose` says so). The PNG encoder refuses a profile with such bytes.
- An ICC profile that the colour engine cannot apply, because it is damaged (e.g. cut short inside its tag data) or names an unknown colour space, is left out of every output (`-Verbose` says so): viewers ignore it in the source, PNG and lossless JPEG XL output could not be written with it, and Chrome and Edge would not display an AVIF that carries it. A profile that the colour engine can apply but the PNG or lossless JPEG XL encoder cannot write (e.g. a version 4 profile whose length is not a multiple of 4, a header that declares a few more bytes than the profile has although all its tags are complete, or, for JPEG XL, a rendering intent above 3) is left out of that output only, so the file is still written (`-Verbose` says so).
- Grey images with a grey ICC profile (e.g. Photoshop's "Dot Gain 20%" or "Gray Gamma 1.8", scanned greyscale) keep their grey pixels and the profile in JPEG, PNG, TIFF and lossless JPEG XL. WebP, AVIF, HEIC, BMP and GIF store grey pixels as RGB, for which a grey profile is not valid (browsers would show the WebP and GIF with wrong grey levels, Chrome and Edge would not display the AVIF, Firefox would show the BMP black), so the pixels are converted to sRGB first, with and without `-StripMetadata`. This includes a grey JPEG XL with a grey profile (e.g. lossless JPEG XL output of such an image), which ImageMagick reads as RGB.
- A profile made for other pixels is not valid. Viewers ignore a grey profile in a colour image; browsers (Chrome, Edge, Firefox) apply an RGB profile to the pixels of a grey JPEG, while Windows (Photos, Explorer) rejects it and shows the grey levels unmanaged. Such a profile is kept, except where the file could not be written or would look different with it: it is left out of lossless JPEG XL and, as a grey profile on colour pixels, out of AVIF, HEIC and BMP, and out of JPEG, PNG and TIFF when the colour pixels are all neutral grey (these formats store them as grey, for which the grey profile would apply). Lossy JPEG XL writes the pixels unchanged.
- Images whose pixels are all neutral grey but that carry an RGB profile (e.g. a black-and-white photo exported in Adobe RGB) are stored as RGB in JPEG, PNG and TIFF output, so the profile stays valid; ImageMagick alone would store them as grey with the RGB profile.
- JPEG has no transparency: transparent and half-transparent pixels (e.g. of a PNG logo) are placed on a white background (paper white for a CMYK image). So does HEIC output on Windows, whose encoder takes opaque pixels only. The other formats keep the alpha channel (GIF only fully transparent or opaque pixels; Windows' own viewer ignores the alpha channel of HEIC files).
- Only the first frame of an animated GIF or WebP, a multi-page TIFF or a HEIC file with several images is converted; the cmdlets write the warning `Only the first of <N> frames is converted: <path>` for every such source.
- A source that ImageMagick can read but reports as damaged, e.g. a JPEG cut off by an interrupted copy (the missing part becomes grey) or an animated GIF cut off after its first frame (its frames cannot be counted then), is converted with the warning `The image may be damaged (<reasons>): <path>`; `Get-ImageInfo` writes the same warning. A JPEG that lacks only its end marker gets this warning as well, although its pixels are complete: the decoder reports it like a file that is cut off. Other ImageMagick warnings about a source go to the verbose stream.
- When the EXIF orientation is applied to the pixels, an EXIF thumbnail is removed (it would show rotated against the photo) and the XMP orientation and pixel dimensions are updated.
- CMYK images (e.g. print JPEGs) stay CMYK with their colour profile in JPEG and TIFF output; for the other formats they are converted to sRGB through their CMYK profile.

## Writing HEIC files

HEIC stores the image with the HEVC (H.265) codec. The bundled Magick.NET build has no HEVC encoder, and the module ships none: HEVC is covered by patent pools, and distributing an HEVC encoder (such as x265) with the module would pass the licensing duties of those patents on to every user. `ConvertTo-Heic` and `Convert-Image -Format Heic` use the encoder of the operating system instead, which comes with, or is installed into, the operating system:

| Platform | Encoder | What to install |
| -------- | ------- | --------------- |
| Windows 10 1809 or later, Windows 11 | the HEIF encoder of the Windows Imaging Component (WIC) | the **HEVC Video Extensions** from the Microsoft Store ([9NMZLZ57R3T7](https://apps.microsoft.com/detail/9NMZLZ57R3T7)), and the **HEIF Image Extension** ([9PMMSR1CGPWG](https://apps.microsoft.com/detail/9PMMSR1CGPWG)) if it is not installed |
| macOS (every version that runs PowerShell 7.4) | ImageIO | nothing; the Mac needs an HEVC encoder |
| Linux | the libheif of the distribution (1.12 or later) with its HEVC encoder x265, built in or as a plugin | see below |

Linux packages; the module was tested in containers of these releases, after the command in the table, with the libheif and x265 versions shown:

| Distribution | Command | Tested with |
| ------------ | ------- | ----------- |
| Ubuntu 24.04 and 26.04, Debian 13 | `sudo apt install libheif1 libheif-plugin-x265` | Ubuntu 24.04: libheif 1.17.6, x265 3.5; Ubuntu 26.04: libheif 1.21.2, x265 4.1; Debian 13: libheif 1.23.4, x265 4.1 |
| Ubuntu 22.04, Debian 12 | `sudo apt install libheif1` (x265 is built in) | Ubuntu 22.04: libheif 1.12.0, x265 3.5; Debian 12: libheif 1.15.1, x265 3.5 |
| Fedora 44 | Fedora's libheif has no HEVC encoder; enable [RPM Fusion](https://rpmfusion.org/) free and install `libheif-freeworld`: `sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm`, then `sudo dnf install libheif-freeworld` | libheif-freeworld 1.23.6, x265 4.1 |
| Arch Linux | `sudo pacman -S libheif` (x265 is built in) | libheif 1.23.6, x265 4.3 |
| Alpine 3.24 | `apk add libheif libheif-x265` | libheif 1.23.4, x265 4.1 |

On Arch Linux, libheif also installs plugins whose libraries are optional dependencies (dav1d, svt-av1, openjpeg2, rav1e, ffmpeg). Without them it writes harmless lines such as `dlopen: libdav1d.so.7: cannot open shared object file` to the console during a HEIC conversion; installing those packages (or having ffmpeg installed, which depends on them) silences them.

The first HEIC conversion in a PowerShell session encodes a small test image to check that the encoder works; the answer is kept for the session, so after installing an encoder start a new session. When the encoder is missing or does not work, the call stops before any file is read, also with `-WhatIf`, with one terminating `HeicEncoderNotAvailable` error that gives the reason and says what to install, for example on Ubuntu 24.04 without the x265 plugin:

```text
HEIC cannot be written on this computer: the module uses the HEVC encoder of the operating system and ships none of its own. libheif 1.17.6 has no HEVC encoder (Unsupported file-type: Unspecified (code 3, subcode 0)). Install libheif with its HEVC encoder x265, e.g. 'sudo apt install libheif1 libheif-plugin-x265' on Ubuntu 24.04 and 26.04 and Debian 13 ('sudo apt install libheif1' on Ubuntu 22.04 and Debian 12; for Fedora, Arch and Alpine see 'Get-Help about_PSImageConverter'), then start a new PowerShell session. Or use -Format Avif, which stores the image in the same HEIF container with the royalty-free AV1 codec and needs nothing installed.
```

`-Format Avif` (`ConvertTo-Avif`) is the patent-free alternative in the same HEIF container: its AV1 encoder comes with Magick.NET, so it works everywhere.

The pixels are turned upright (EXIF orientation 1), converted to sRGB where the other formats are (CMYK, grey pixels with a grey profile) and passed to the encoder as 8-bit RGB, or RGBA where the alpha channel is kept. What the output keeps differs by encoder:

|                    | Windows (WIC)                                   | Linux (libheif, x265)               | macOS (ImageIO)                    |
| ------------------ | ----------------------------------------------- | ----------------------------------- | ---------------------------------- |
| EXIF               | yes, as it is (orientation set to 1)            | yes, as it is (orientation set to 1) | no (warning, as for TIFF)         |
| XMP                | yes, as it is                                   | yes, as it is                       | no                                 |
| ICC colour profile | yes                                             | yes                                 | yes, except sRGB, which ImageIO stores as `nclx` colour information instead |
| Colour signalling  | BT.709 (`nclx` box)                             | BT.709 (`nclx` box and HEVC stream) | ImageIO's own (an `nclx` box with the BT.601 matrix where no ICC profile is stored) |
| Alpha channel      | no: placed on a white background, as for JPEG   | yes (Windows' own viewer ignores it, see below) | yes (Windows' own viewer ignores it, see below) |
| `-Quality`         | WIC `ImageQuality` = Quality / 100              | libheif quality (x265: CRF = (100 − Quality) / 2) | ImageIO quality = Quality / 100 |
| Image size         | a side longer than 22528 pixels fails           | a side longer than 32768 pixels fails (libheif would not read the file back), and so does a side shorter than 32 pixels next to one longer than 4096, and an image whose slices stay larger than Magick.NET reads even when it is cut into 13 (see below) | not checked yet |

IPTC data and comments are not written. `-Quality 100` is not lossless. An image the encoder rejects fails that file with `ImageWriteFailed`. EXIF and XMP are stored as they are, so a block that another program could not parse is kept, as in the other output formats. Further notes:

- **Viewing on Windows**: Windows' own viewer (Photos, Explorer) does not show a HEIC image with a side shorter than 8 pixels, whichever program wrote it; other viewers do. It also ignores the alpha channel of a HEIC file (written on Linux or macOS): transparent and half-transparent areas show the colours stored under them, opaque. And it does not open HEIC files written on Linux that have a side longer than 16384 pixels. Nor does it open an image stored in several extents (parts) of the file, which libheif 1.17 and older (Ubuntu 22.04 and 24.04, Debian 12) write for an image of several slices, one extent per slice; the module joins these extents into one, as libheif 1.21 and later store them, so the viewer also opens the files of several slices that the module writes for an image whose single slice would be larger than Magick.NET can read (see below). Windows reads its own output up to the limit in the table.
- **Size and quality**: at the default `-Quality 90` HEIC files are larger than JPEG files at quality 90: in the module's tests 1.1 to 2 times as large on Windows (and further from the source than JPEG) and about 2.4 to 3.4 times with x265 on Linux (closer to the source than JPEG). `-Quality` 60 to 80 gives about the size of JPEG at 90 (the lower values on Linux); AVIF at quality 90 is smaller than both.
- **Colour resolution**: HEIC output, like AVIF and WebP output, stores colour at half the resolution of the brightness (4:2:0 chroma subsampling), so thin coloured lines and sharp colour edges blur slightly. JPEG at `-Quality` 90 or above, PNG and the lossless formats keep full colour resolution.
- **Windows**: the encoder writes a single coded image for small images, which crashed the process or wrote files libheif cannot decode for some sizes, so the module always lets it write a grid of whole 512 × 512 tiles: the image is padded by repeating its edge pixels, and a crop box restores its size (the encoder fills a partly used tile with data that changes from call to call, which made the size of the same image vary up to tenfold). The encoder converts the colours with the BT.709 matrix but does not say so, so the module adds that information (an `nclx` box); otherwise viewers based on libheif (ImageMagick, GIMP) would show pure red as 232, 0, 3. Two conversions of one image give files of nearly the same size (within a few dozen bytes), but not always identical bytes.
- **Linux**: the colours are converted and signalled with the BT.709 matrix, as on Windows; libheif 1.17 and later would otherwise convert with BT.601 but signal BT.709 primaries, and Windows' own viewer would show shifted colours (pure green as 0, 216, 0). An image is encoded as one HEVC slice. Magick.NET cannot decode a slice larger than 16 MiB, so when that slice is larger than 15,000,000 bytes, the image is encoded again in as many slices as keep each of them below that size, at most 13 (x265 crashes with more): a 12-megapixel phone photo took 7.1 MB at `-Quality 90`, so a photo with as much detail reaches the limit at about 25 megapixels, and random noise at about 10 megapixels. x265 is given an explicit thread pool (one thread per processor) for images larger than 8 megapixels and for images of several slices, because x265 4.1 makes none of its own in some containers (see below) and then crashes the process when it encodes several slices. An image whose slices are still larger than 15,000,000 bytes in 13 slices fails with `ImageWriteFailed` (at the 1.6 bytes per pixel that random noise takes at `-Quality 100`, from about 120 megapixels). x265 marks an image beyond the limits of the highest regular HEVC level, 6.2 (about 35.6 megapixels, or a side longer than 16888 pixels), with level 8.5, which many hardware decoders do not accept. x265 is slower than the Windows encoder: an 8000 × 6000 image took about 2 s (smooth gradient) to 23 s (random noise, encoded twice) on 22 cores, against 1 to 2.5 s on Windows.
- **Linux in containers**: where the NUMA memory-policy calls are denied, as in a Docker container with the default seccomp profile, x265 writes harmless lines to the console that PowerShell cannot redirect: with x265 3.5 about 50 lines `set_mempolicy: Operation not permitted` for each image up to 8 megapixels (and once more for the encoder check at the first HEIC conversion of a session) and about one per processor for a larger one, and with x265 4.1 about one line `x265 [error]: unable to set thread affinity for NUMA node mask` per processor for every image that gets the thread pool (larger than 8 megapixels or of several slices). x265 4.1 creates no thread pool of its own there, so it encodes smaller images on one thread, 3 to 5 times more slowly. `docker run --cap-add SYS_NICE` avoids both.
- **macOS**: ImageIO gets the pixels as 32-bit RGBX or RGBA (with 24-bit RGB it leaves the last column and row of an image with an odd width or height empty) and no orientation property, so it writes no EXIF item of its own. The macOS runners of GitHub Actions (macOS 26) have the HEVC encoder, so CI runs the HEIC tests there; `output/testResults/HeicSupport_macOS.txt` of a CI run records what the runner could do.

## Errors

Errors about a file are non-terminating: the cmdlets continue with the next file, `$?` is `$false` afterwards, `-ErrorVariable` holds one record per failed file and `-ErrorAction Stop` stops at the first one. A `-DestinationPath` that cannot name a folder (`InvalidDestinationPath`, `UnsupportedProvider`, `DestinationNotDirectory` below), and a missing HEIC encoder for `-Format Heic` (`HeicEncoderNotAvailable`), is a parameter error instead: it stops the whole call with one terminating error before any file is read, also with `-WhatIf`, and `try`/`catch` catches it without `-ErrorAction Stop`; use `$_` in the `catch` block or `$Error[0]` for the error record, because `-ErrorVariable` holds the exception for these errors (its `ErrorRecord` property has the record). A destination folder that does not exist yet is created when the first file is written; when that fails (no permission, a read-only file system) or the folder cannot be written to, each file gets an `ImageWriteFailed` error. Every error has a stable id (`FullyQualifiedErrorId` `<Id>,<Cmdlet>`):

| Id                                    | Kind        | Target object                     | Meaning                                                                                 |
| ------------------------------------- | ----------- | --------------------------------- | --------------------------------------------------------------------------------------- |
| `PathNotFound`                        | per file    | the input as given                | The input matches no file; for a wildcard pattern the message names a drive or folder that does not exist, a folder part that is a file, a folder part with wildcards that no folder matches (or only hidden folders), or, when the folder exists, adds that wildcards do not match hidden files and `-LiteralPath` does, and for a pattern with `[` or `]` that these are wildcard characters and how to match them; for a PSDrive that is not global it names the drive (see [Limitations](#limitations)) |
| `InvalidWildcardPattern`              | per file    | the input as given                | A `-Path` is not a valid wildcard pattern (`a[.jpg`); use `-LiteralPath`                |
| `UnsupportedProvider`                 | per file    | the input as given                | The input is not a file system path (Registry, Env:, ...); one error per input, also for a pattern that matches several items there |
| `UnsupportedProvider`                 | terminating | the `-DestinationPath` value      | `-DestinationPath` is not a file system path                                            |
| `InvalidDestinationPath`              | terminating | the `-DestinationPath` value      | `-DestinationPath` is white space only, has an unknown drive or provider or invalid characters (on Windows also a colon after the drive, `C:\x:y`), is a drive-qualified path that climbs above the root of its drive (`Temp:\..\x`; a relative path that climbs above the root stays at the root, as in other cmdlets), or is on a PSDrive that is not global (see [Limitations](#limitations)) |
| `DestinationNotDirectory`             | terminating | the `-DestinationPath` value      | `-DestinationPath` or one of its parent folders is an existing file, a junction or symbolic link whose target does not exist, or a link that cannot be resolved (e.g. one that points to itself) |
| `NotHeicFile`                         | per file    | the source file                   | `ConvertFrom-Heic` only: the file has no `.heic`, `.heif` or `.hif` extension           |
| `TargetIsSource`                      | per file    | the source file                   | The output would overwrite the source, e.g. `ConvertTo-Jpeg a.jpg` without `-DestinationPath`; also with `-Force` and when the folder is reached through a junction, symbolic link, other drive letter or UNC path |
| `DuplicateTarget`                     | per file    | the source file                   | Two sources of one call map to the same output file (`a.heic` and `a.png`); also with `-Force` |
| `TargetExists`                        | per file    | the source file                   | The output file exists and `-Force` is not set                                          |
| `ConfirmationFailed`                  | per file    | the source file                   | `-Confirm` (or the caller's `$ConfirmPreference`) asks for a confirmation the host cannot show, e.g. in `pwsh -NonInteractive`; use `-Confirm:$false` |
| `HeicEncoderNotAvailable`             | terminating | `Heic`                            | `-Format Heic` or `ConvertTo-Heic` on a computer without a working HEVC encoder; the message says what to install (see [Writing HEIC files](#writing-heic-files)) |
| `ImageReadFailed`, `ImageWriteFailed` | per file    | the source file                   | Magick.NET cannot read the source or write the output (for HEIC: the encoder of the operating system rejects the image), or the destination folder cannot be created or written to |

`ConvertFrom-Heic` and the `ConvertTo-*` shortcuts pass all files of one call to a single `Convert-Image`, so the errors it finds are reported as `<Id>,Convert-Image`. The checks a shortcut makes before are reported with its own name: every shortcut checks `-DestinationPath` (e.g. `DestinationNotDirectory,ConvertTo-Jpeg`), `ConvertTo-Heic` and `ConvertFrom-Heic -Format Heic` check the HEIC encoder (`HeicEncoderNotAvailable,ConvertTo-Heic`), and `ConvertFrom-Heic` also checks the input paths (`PathNotFound`, `InvalidWildcardPattern`, `UnsupportedProvider`, `NotHeicFile`). With `Import-Module -Prefix`, the errors raised inside `Convert-Image` during such a call keep the module's unprefixed name (`TargetExists,Convert-Image`), while a direct call of the prefixed cmdlet and the checks of a prefixed shortcut carry the prefixed name (`TargetExists,Convert-XyImage`, `DestinationNotDirectory,ConvertTo-XyJpeg`).

One call never overwrites a file it wrote itself, and without `-Force` it never overwrites an existing file. Separate calls or processes that write the same output file at the same time without `-Force` (e.g. `a.heic` and `a.heif` converted into one folder by `ForEach-Object -Parallel`) are not coordinated: on Windows the later one fails with `TargetExists` or `ImageWriteFailed`; on Linux and macOS both can succeed and the later file replaces the earlier one, because the final move checks for an existing file and then renames, which is not atomic there. With `-Force` the later file replaces the earlier one on every platform. Give parallel conversions different destination folders.

## Limitations

- **PSDrives that are not global** cannot be used. A script module resolves paths in its own session state, which sees only the global drives; this is a limitation of the PowerShell engine (`Microsoft.PowerShell.Archive` behaves the same). A drive created with `New-PSDrive` without `-Scope Global` inside a function (also by a script dot-sourced there), at the top of a script run by its path or with `&` (`.\setup.ps1`, `& .\setup.ps1`), or in another module therefore fails in `-Path` and `-LiteralPath` with `PathNotFound` and in `-DestinationPath` with `InvalidDestinationPath`, and so does a relative input path while the current location is on such a drive. The message names the drive and its root:

  ```text
  Cannot resolve the path 'Photos:\IMG_1234.HEIC': drive 'Photos' was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module). Create the drive with New-PSDrive -Scope Global, or use the file system path; the root of the drive is 'D:\Pictures'.
  ```

  Create the drive with `New-PSDrive -Scope Global`, or use the file system path. A drive created at the prompt, in the profile, at the top level of `pwsh -File` or by a script dot-sourced there (`. .\setup.ps1`) is global and works. When such a drive has the name of a global drive (e.g. a script's own `Temp:`), the module would read and write on the global drive instead, so this fails the same way, and the message names both roots. Files piped from `Get-ChildItem` or `Get-Item` on such a drive work, because their `PSPath` holds the file system path, and so does a relative `-DestinationPath`; strings and the output of `Resolve-Path` (which has no `PSPath`) do not. For a drive of another provider (e.g. a Registry drive created in a function) the message says that only file system paths are supported.

## Development

The module is built with [Sampler](https://github.com/gaelcolas/Sampler). Development happens on the [`dev`](https://github.com/fasteiner/PSImageConverter/tree/dev) branch, from which every pre-release is built; `main` gets the code with each stable release. See [CLAUDE.md](https://github.com/fasteiner/PSImageConverter/blob/dev/CLAUDE.md) for the build commands and conventions.

```powershell
.\build.ps1 -ResolveDependency -Tasks build, test
```

Building needs PowerShell 7.4 or later and the [.NET SDK](https://dot.net) 8.0 or later: the build compiles the module's C# helper assembly (`helper/`, `PSImageConverter.Helper.dll`, which also holds the bindings to the HEIC encoders of Windows, Linux and macOS) with `dotnet build` and downloads Magick.NET from nuget.org. The GitHub-hosted runners and the devcontainer have the .NET SDK. Using the built module needs only PowerShell.

The tests that write HEIC run where the encoder of the operating system works and are skipped elsewhere; the tests of the missing encoder mock the check and run everywhere, and where no encoder works the real error is checked too, including that the check found no encoder rather than a fault in the module's binding to it. On Windows the HEIC tests need the HEVC Video Extensions, so they run on a developer machine but neither on GitHub-hosted Windows runners nor in Windows containers (no Microsoft Store, no Media Foundation codecs); the Windows runner tests the real missing-encoder error. Where an encoder is expected, the environment variable `PSIC_EXPECT_HEIC_ENCODER=1` makes a test fail when it does not work, instead of letting every HEIC test be skipped: CI installs `libheif1` and `libheif-plugin-x265` on `ubuntu-latest` and sets it there, the devcontainer does the same, and a developer with the HEVC Video Extensions can set it as well. `macos-latest` (macOS 26) can encode HEVC, so the HEIC tests run there too, without the variable. On Windows, the HEIC tests also read the output back with Windows' own HEIF decoder. Every test run writes `output/testResults/HeicSupport_<platform>.txt` with the read and write support of Magick.NET for HEIC, AVIF, JPEG XL and WebP and the state of the HEIC encoder.

## License

PSImageConverter is licensed under the [GPL-3.0](LICENSE). It bundles Magick.NET and ImageMagick, which are licensed under the Apache License 2.0 and the ImageMagick License; their notices are shipped in the module's `lib` folder.
