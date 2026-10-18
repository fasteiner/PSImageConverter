# PSImageConverter

Cross-platform PowerShell 7 module for converting images — HEIC/HEIF photos from an iPhone, but also JPEG, PNG, WebP and every other format [Magick.NET](https://github.com/dlemstra/Magick.NET) can read — to JPEG, PNG, WebP, AVIF, JPEG XL, TIFF, BMP or GIF.

- Works on PowerShell 7.4 or later on Windows, Linux and macOS (x64 and arm64; Alpine/musl Linux: x64 only)
- No codecs or ImageMagick installation needed — the native library is bundled
- Pipeline-friendly (`Get-ChildItem | ConvertTo-WebP | Get-ImageInfo`), `-WhatIf`, applies the EXIF orientation, keeps the metadata the output format can carry unless you strip it
- Never overwrites the source file, also not when its folder is reached through a junction, a symbolic link or another drive letter, and a failed or stopped conversion never leaves a truncated or temporary file behind

## Installation

```powershell
Install-Module -Name PSImageConverter -Scope CurrentUser
```

Pre-releases are published from the `dev` branch (e.g. `0.2.0-preview0007`):

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

# Formats without a ConvertTo-* shortcut
Convert-Image -Path .\IMG_1234.HEIC -Format Tiff

# Inspect photos, sorted by the date they were taken
Get-ChildItem -Path C:\Pictures -Filter *.heic | Get-ImageInfo | Sort-Object -Property DateTaken

# Convert only the photos wider than 4000 pixels
Get-ImageInfo -Path .\*.heic | Where-Object -Property Width -GT 4000 | ConvertTo-Jpeg -Quality 85
```

| Cmdlet             | Purpose                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------- |
| `Convert-Image`    | Converts any readable image to the `-Format` Jpeg, Png, WebP, Avif, Jxl, Tiff, Bmp or Gif   |
| `ConvertTo-Jpeg`   | `Convert-Image -Format Jpeg`, same parameters without `-Format`                             |
| `ConvertTo-Png`    | `Convert-Image -Format Png`, same parameters without `-Format` and `-Quality` (lossless)     |
| `ConvertTo-WebP`   | `Convert-Image -Format WebP`, same parameters without `-Format`                             |
| `ConvertTo-Avif`   | `Convert-Image -Format Avif`, same parameters without `-Format`                             |
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
| JPEG XL   | `Jxl`     | `.jxl`    | `ConvertTo-JpegXL` | yes                            | EXIF, XMP; ICC colour profile only at `-Quality 100` |
| TIFF      | `Tiff`    | `.tif`    | —                  | no                             | XMP, IPTC, ICC colour profile, comments     |
| BMP       | `Bmp`     | `.bmp`    | —                  | no                             | ICC colour profile                          |
| GIF       | `Gif`     | `.gif`    | —                  | no                             | IPTC, ICC colour profile (browsers ignore it in GIF files), comments |
| HEIC/HEIF | —         | —         | —                  | —                              | read only, see below                        |

- The bundled Magick.NET build writes no EXIF data (date taken, camera, GPS location) to TIFF, BMP and GIF output; the cmdlets write a warning for every source with EXIF data unless `-StripMetadata` is used.
- `-StripMetadata` removes EXIF (including the GPS location), XMP, IPTC and comments but keeps the ICC colour profile.
- The colours are kept when the source carries an ICC profile, as iPhone photos do (e.g. Display P3). A HEIC or AVIF source that signals its colours only through nclx/CICP (no ICC profile) with primaries other than sRGB/BT.709 (e.g. Display P3 or BT.2020, also HDR with PQ or HLG) is converted without colour conversion, so its colours look less saturated; AVIF output keeps the CICP values.
- Lossy JPEG XL (`-Quality` below 100, the default is 90) is always sRGB: the bundled encoder stores an ICC colour profile only in lossless files. The pixels of a source with an ICC profile (e.g. Display P3 or Adobe RGB) are converted to sRGB first, with and without `-StripMetadata`, so the photo looks the same; colours outside sRGB are clipped. Use `-Quality 100` or AVIF to keep a wide gamut. A grey profile in a colour image, which viewers ignore, is ignored here as well. Chrome shows a lossless JPEG XL whose profile describes its tone curve as a table (e.g. Photoshop's "Dot Gain 20%" grey profiles) without colour management; Firefox applies such a profile, and profiles with gamma or parametric curves (Adobe RGB, Display P3) work in both.
- An ICC profile that the colour engine cannot apply, because it is damaged (e.g. cut short) or names an unknown colour space, is left out of every output (`-Verbose` says so): viewers ignore it in the source, PNG and lossless JPEG XL output could not be written with it, and Chrome and Edge would not display an AVIF that carries it.
- Grey images with a grey ICC profile (e.g. Photoshop's "Dot Gain 20%" or "Gray Gamma 1.8", scanned greyscale) keep their grey pixels and the profile in JPEG, PNG, TIFF and lossless JPEG XL. WebP, AVIF, BMP and GIF store grey pixels as RGB, for which a grey profile is not valid (browsers would show the WebP and GIF with wrong grey levels, Chrome and Edge would not display the AVIF, Firefox would show the BMP black), so the pixels are converted to sRGB first, with and without `-StripMetadata`. This includes a grey JPEG XL with a grey profile (e.g. lossless JPEG XL output of such an image), which ImageMagick reads as RGB.
- A profile made for other pixels is not valid. Viewers ignore a grey profile in a colour image; browsers (Chrome, Edge, Firefox) apply an RGB profile to the pixels of a grey JPEG, while Windows (Photos, Explorer) rejects it and shows the grey levels unmanaged. Such a profile is kept, except where the file could not be written or would look different with it: it is left out of lossless JPEG XL and, as a grey profile on colour pixels, out of AVIF and BMP, and out of JPEG, PNG and TIFF when the colour pixels are all neutral grey (these formats store them as grey, for which the grey profile would apply). Lossy JPEG XL writes the pixels unchanged.
- Images whose pixels are all neutral grey but that carry an RGB profile (e.g. a black-and-white photo exported in Adobe RGB) are stored as RGB in JPEG, PNG and TIFF output, so the profile stays valid; ImageMagick alone would store them as grey with the RGB profile.
- JPEG has no transparency: transparent and half-transparent pixels (e.g. of a PNG logo) are placed on a white background (paper white for a CMYK image). The other formats keep the alpha channel (GIF only fully transparent or opaque pixels).
- Only the first frame of an animated GIF or WebP, a multi-page TIFF or a HEIC file with several images is converted; the cmdlets write the warning `Only the first of <N> frames is converted: <path>` for every such source.
- A source that ImageMagick can read but reports as damaged, e.g. a JPEG cut off by an interrupted copy (the missing part becomes grey) or an animated GIF cut off after its first frame (its frames cannot be counted then), is converted with the warning `The image may be damaged (<reasons>): <path>`; `Get-ImageInfo` writes the same warning. A JPEG that lacks only its end marker gets this warning as well, although its pixels are complete: the decoder reports it like a file that is cut off. Other ImageMagick warnings about a source go to the verbose stream.
- When the EXIF orientation is applied to the pixels, an EXIF thumbnail is removed (it would show rotated against the photo) and the XMP orientation and pixel dimensions are updated.
- CMYK images (e.g. print JPEGs) stay CMYK with their colour profile in JPEG and TIFF output; for the other formats they are converted to sRGB through their CMYK profile.
- **Writing HEIC is not supported yet**: the bundled Magick.NET build contains no HEVC encoder. AVIF uses the same container with the royalty-free AV1 codec and is the closest alternative.

## Errors

Errors about a file are non-terminating: the cmdlets continue with the next file, `$?` is `$false` afterwards, `-ErrorVariable` holds one record per failed file and `-ErrorAction Stop` stops at the first one. A `-DestinationPath` that cannot name a folder (`InvalidDestinationPath`, `UnsupportedProvider`, `DestinationNotDirectory` below) is a parameter error instead: it stops the whole call with one terminating error before any file is read, also with `-WhatIf`, and `try`/`catch` catches it without `-ErrorAction Stop`; use `$_` in the `catch` block or `$Error[0]` for the error record, because `-ErrorVariable` holds the exception for these errors (its `ErrorRecord` property has the record). A destination folder that does not exist yet is created when the first file is written; when that fails (no permission, a read-only file system) or the folder cannot be written to, each file gets an `ImageWriteFailed` error. Every error has a stable id (`FullyQualifiedErrorId` `<Id>,<Cmdlet>`):

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
| `ImageReadFailed`, `ImageWriteFailed` | per file    | the source file                   | Magick.NET cannot read the source or write the output, or the destination folder cannot be created or written to |

`ConvertFrom-Heic` and the `ConvertTo-*` shortcuts pass all files of one call to a single `Convert-Image`, so the errors it finds are reported as `<Id>,Convert-Image`. The checks a shortcut makes before are reported with its own name: every shortcut checks `-DestinationPath` (e.g. `DestinationNotDirectory,ConvertTo-Jpeg`), and `ConvertFrom-Heic` also checks the input paths (`PathNotFound`, `InvalidWildcardPattern`, `UnsupportedProvider`, `NotHeicFile`). With `Import-Module -Prefix`, the errors raised inside `Convert-Image` during such a call keep the module's unprefixed name (`TargetExists,Convert-Image`), while a direct call of the prefixed cmdlet and the checks of a prefixed shortcut carry the prefixed name (`TargetExists,Convert-XyImage`, `DestinationNotDirectory,ConvertTo-XyJpeg`).

One call never overwrites a file it wrote itself, and without `-Force` it never overwrites an existing file. Separate calls or processes that write the same output file at the same time without `-Force` (e.g. `a.heic` and `a.heif` converted into one folder by `ForEach-Object -Parallel`) are not coordinated: on Windows the later one fails with `TargetExists` or `ImageWriteFailed`; on Linux and macOS both can succeed and the later file replaces the earlier one, because the final move checks for an existing file and then renames, which is not atomic there. With `-Force` the later file replaces the earlier one on every platform. Give parallel conversions different destination folders.

## Limitations

- **PSDrives that are not global** cannot be used. A script module resolves paths in its own session state, which sees only the global drives; this is a limitation of the PowerShell engine (`Microsoft.PowerShell.Archive` behaves the same). A drive created with `New-PSDrive` without `-Scope Global` inside a function (also by a script dot-sourced there), at the top of a script run by its path or with `&` (`.\setup.ps1`, `& .\setup.ps1`), or in another module therefore fails in `-Path` and `-LiteralPath` with `PathNotFound` and in `-DestinationPath` with `InvalidDestinationPath`, and so does a relative input path while the current location is on such a drive. The message names the drive and its root:

  ```text
  Cannot resolve the path 'Photos:\IMG_1234.HEIC': drive 'Photos' was created in a scope that the PSImageConverter module cannot see (inside a function, in a script run with & or by its path, or in another module). Create the drive with New-PSDrive -Scope Global, or use the file system path; the root of the drive is 'D:\Pictures'.
  ```

  Create the drive with `New-PSDrive -Scope Global`, or use the file system path. A drive created at the prompt, in the profile, at the top level of `pwsh -File` or by a script dot-sourced there (`. .\setup.ps1`) is global and works. When such a drive has the name of a global drive (e.g. a script's own `Temp:`), the module would read and write on the global drive instead, so this fails the same way, and the message names both roots. Files piped from `Get-ChildItem` or `Get-Item` on such a drive work, because their `PSPath` holds the file system path, and so does a relative `-DestinationPath`; strings and the output of `Resolve-Path` (which has no `PSPath`) do not. For a drive of another provider (e.g. a Registry drive created in a function) the message says that only file system paths are supported.

## Development

The module is built with [Sampler](https://github.com/gaelcolas/Sampler). See [CLAUDE.md](CLAUDE.md) for the build commands and conventions.

```powershell
.\build.ps1 -ResolveDependency -Tasks build, test
```

## License

PSImageConverter is licensed under the [GPL-3.0](LICENSE). It bundles Magick.NET and ImageMagick, which are licensed under the Apache License 2.0 and the ImageMagick License; their notices are shipped in the module's `lib` folder.
