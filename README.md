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
| `Get-ImageInfo`    | Returns format, size, orientation, camera and date taken of an image                        |

All conversion cmdlets take `-Path` (wildcards, strings from the pipeline) or `-LiteralPath` (aliases `PSPath` and `LP`; files from `Get-ChildItem`; folders are skipped), `-DestinationPath`, `-StripMetadata`, `-Force`, `-WhatIf` and `-Confirm`, and return a `FileInfo` for every written file — the same object `Get-Item` returns, so it can be piped into the next cmdlet even when its name contains `[` or `]`. The output gets the source's base name and the extension of the format, next to the source or in `-DestinationPath`.

## Formats

The source format is detected from the file content; every format Magick.NET can read is accepted, including HEIC/HEIF.

| Output    | `-Format` | Extension | Shortcut           | `-Quality` (1–100, default 90) | Metadata kept without `-StripMetadata`      |
| --------- | --------- | --------- | ------------------ | ------------------------------ | ------------------------------------------- |
| JPEG      | `Jpeg`    | `.jpg`    | `ConvertTo-Jpeg`   | yes                            | EXIF, XMP, IPTC, ICC colour profile, comments |
| PNG       | `Png`     | `.png`    | `ConvertTo-Png`    | no (lossless)                  | EXIF, XMP, IPTC, ICC colour profile, comments |
| WebP      | `WebP`    | `.webp`   | `ConvertTo-WebP`   | yes                            | EXIF, XMP, ICC colour profile               |
| AVIF      | `Avif`    | `.avif`   | `ConvertTo-Avif`   | yes                            | EXIF, XMP, ICC colour profile               |
| JPEG XL   | `Jxl`     | `.jxl`    | `ConvertTo-JpegXL` | yes                            | EXIF, XMP, ICC colour profile               |
| TIFF      | `Tiff`    | `.tif`    | —                  | no                             | XMP, IPTC, ICC colour profile, comments     |
| BMP       | `Bmp`     | `.bmp`    | —                  | no                             | ICC colour profile                          |
| GIF       | `Gif`     | `.gif`    | —                  | no                             | IPTC, ICC colour profile, comments          |
| HEIC/HEIF | —         | —         | —                  | —                              | read only, see below                        |

- The bundled Magick.NET build writes no EXIF data (date taken, camera, GPS location) to TIFF, BMP and GIF output; the cmdlets write a warning for every source with EXIF data unless `-StripMetadata` is used.
- `-StripMetadata` removes EXIF (including the GPS location), XMP, IPTC and comments but keeps the ICC colour profile, so wide-gamut photos (e.g. Display P3) keep their colours.
- When the EXIF orientation is applied to the pixels, an EXIF thumbnail is removed (it would show rotated against the photo) and the XMP orientation and pixel dimensions are updated.
- CMYK images (e.g. print JPEGs) stay CMYK with their colour profile in JPEG and TIFF output; for the other formats they are converted to sRGB through their CMYK profile.
- **Writing HEIC is not supported yet**: the bundled Magick.NET build contains no HEVC encoder. AVIF uses the same container with the royalty-free AV1 codec and is the closest alternative.

## Errors

Errors are non-terminating: the cmdlets continue with the next file, `$?` is `$false` afterwards, `-ErrorVariable` holds one record per failed file and `-ErrorAction Stop` stops at the first one. Every error has a stable id (`FullyQualifiedErrorId` `<Id>,<Cmdlet>`) and the source path as target object:

| Id                                                  | Meaning                                                                                 |
| --------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `PathNotFound`                                      | The input matches no file                                                               |
| `InvalidWildcardPattern`                            | A `-Path` is not a valid wildcard pattern (`a[.jpg`); use `-LiteralPath`                |
| `UnsupportedProvider`                               | The input or `-DestinationPath` is not a file system path (Registry, Env:, ...)         |
| `NotHeicFile`                                       | `ConvertFrom-Heic` only: the file has no `.heic`, `.heif` or `.hif` extension           |
| `InvalidDestinationPath`                            | `-DestinationPath` has an unknown drive, leaves its drive root or has invalid characters |
| `DestinationNotDirectory`                           | `-DestinationPath` or one of its parent folders is an existing file                     |
| `TargetIsSource`                                    | The output would overwrite the source, e.g. `ConvertTo-Jpeg a.jpg` without `-DestinationPath`; also with `-Force` and when the folder is reached through a junction, symbolic link, other drive letter or UNC path |
| `DuplicateTarget`                                   | Two sources of one call map to the same output file (`a.heic` and `a.png`); also with `-Force` |
| `TargetExists`                                      | The output file exists and `-Force` is not set                                          |
| `ImageReadFailed`, `ImageWriteFailed`               | Magick.NET cannot read the source or write the output                                   |

`ConvertFrom-Heic` and the `ConvertTo-*` shortcuts pass all files of one call to a single `Convert-Image`, so the errors it finds are reported as `<Id>,Convert-Image`. Only the checks `ConvertFrom-Heic` makes itself on the input paths (`PathNotFound`, `InvalidWildcardPattern`, `UnsupportedProvider`, `NotHeicFile`) are reported as `<Id>,ConvertFrom-Heic`.

## Development

The module is built with [Sampler](https://github.com/gaelcolas/Sampler). See [CLAUDE.md](CLAUDE.md) for the build commands and conventions.

```powershell
.\build.ps1 -ResolveDependency -Tasks build, test
```

## License

PSImageConverter is licensed under the [GPL-3.0](LICENSE). It bundles Magick.NET and ImageMagick, which are licensed under the Apache License 2.0 and the ImageMagick License; their notices are shipped in the module's `lib` folder.
