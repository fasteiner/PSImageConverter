# Changelog for PSImageConverter

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `ConvertFrom-Heic`: Converts HEIC/HEIF images to JPEG, PNG, WebP, TIFF, BMP, GIF or AVIF. Accepts pipeline input from `Get-ChildItem`, applies the EXIF orientation, keeps metadata unless `-StripMetadata` is used, supports `-DestinationPath`, `-Quality`, `-Force` and `-WhatIf`.
- `Get-HeicInfo`: Returns format, dimensions, orientation, camera make/model, date taken and file size for HEIC/HEIF and other images.
- Bundles Magick.NET (Q8, AnyCPU) for Windows (x64, arm64), Linux (x64, arm64, musl-x64) and macOS (x64, arm64). The libraries are downloaded from nuget.org at build time by the `Get_MagickNet` build task.
- Requires PowerShell 7.4 or later; the native library is loaded through the same DllImport resolver on every platform, also when several runspaces (`Start-ThreadJob`, `ForEach-Object -Parallel`) import the module at the same time.
- Sampler build pipeline with GitHub Actions: test matrix (PowerShell 7 on Windows, Linux and macOS) and publishing to the PowerShell Gallery from `main` via the `release` environment. After a release, `Create_ChangeLog_GitHub_PR` opens a pull request with the CHANGELOG update.
- Every push to `dev` publishes a pre-release (`<version>-previewNNNN`) to GitHub and the PowerShell Gallery through the Sampler workflow `publish_prerelease`.
