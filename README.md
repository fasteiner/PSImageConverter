# PSImageConverter

Cross-platform PowerShell 7 module for converting HEIC/HEIF images (e.g. iPhone photos) to JPEG, PNG, WebP and more, powered by [Magick.NET](https://github.com/dlemstra/Magick.NET).

- Works on PowerShell 7.4 or later on Windows, Linux and macOS (x64 and arm64; Alpine/musl Linux: x64 only)
- No codecs or ImageMagick installation needed — the native library is bundled
- Pipeline-friendly, applies the EXIF orientation, keeps metadata unless you strip it

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
# Convert a single file to JPEG next to the original
ConvertFrom-Heic -Path .\IMG_1234.HEIC

# Convert a folder to PNG into another folder
Get-ChildItem -Path C:\Pictures -Filter *.heic | ConvertFrom-Heic -Format Png -DestinationPath C:\Pictures\png

# JPEG with quality 80, remove location data and other metadata, overwrite existing files
Get-ChildItem -Path ~/Photos -Filter *.heic -Recurse | ConvertFrom-Heic -Quality 80 -StripMetadata -Force

# Inspect photos, sorted by the date they were taken
Get-ChildItem -Path C:\Pictures -Filter *.heic | Get-HeicInfo | Sort-Object -Property DateTaken
```

| Cmdlet             | Purpose                                                                 |
| ------------------ | ----------------------------------------------------------------------- |
| `ConvertFrom-Heic` | Converts HEIC/HEIF to Jpeg, Png, WebP, Tiff, Bmp, Gif or Avif           |
| `Get-HeicInfo`     | Returns format, size, orientation, camera and date taken of an image    |

Writing HEIC is not supported: the bundled Magick.NET build contains no HEVC encoder.

## Development

The module is built with [Sampler](https://github.com/gaelcolas/Sampler). See [CLAUDE.md](CLAUDE.md) for the build commands and conventions.

```powershell
.\build.ps1 -ResolveDependency -Tasks build, test
```

## License

PSImageConverter is licensed under the [GPL-3.0](LICENSE). It bundles Magick.NET and ImageMagick, which are licensed under the Apache License 2.0 and the ImageMagick License; their notices are shipped in the module's `lib` folder.
