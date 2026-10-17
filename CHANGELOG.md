# Changelog for PSHeic

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `ConvertFrom-Heic`: Converts HEIC/HEIF images to JPEG, PNG, WebP, TIFF, BMP, GIF or AVIF. Accepts pipeline input from `Get-ChildItem`, applies the EXIF orientation, keeps metadata unless `-StripMetadata` is used, supports `-DestinationPath`, `-Quality`, `-Force` and `-WhatIf`.
- `Get-HeicInfo`: Returns format, dimensions, orientation, camera make/model, date taken and file size for HEIC/HEIF and other images.
- Bundles Magick.NET (Q8, AnyCPU) for Windows (x64, arm64), Linux (x64, arm64, musl-x64) and macOS (x64, arm64). The libraries are downloaded from nuget.org at build time by the `Get_MagickNet` build task.
- Sampler build pipeline with GitHub Actions: test matrix (Windows PowerShell 5.1, PowerShell 7 on Windows, Linux and macOS) and publishing to the PowerShell Gallery from `main` via the `release` environment.
