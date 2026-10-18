# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

`PSImageConverter` is a PowerShell 7 module (7.4 or later, Windows/Linux/macOS; Windows PowerShell 5.1 is not supported) that converts images (HEIC/HEIF and everything else Magick.NET reads) to JPEG, PNG, WebP, AVIF, HEIC, JPEG XL, TIFF, BMP or GIF using a bundled [Magick.NET](https://github.com/dlemstra/Magick.NET) and a small compiled helper assembly (`PSImageConverter.Helper.dll`, built from `helper/`). HEIC is written with the HEVC encoder of the operating system (WIC on Windows, the system libheif on Linux, ImageIO on macOS); the module ships none. The project is scaffolded with [Sampler](https://github.com/gaelcolas/Sampler) and built via InvokeBuild, with the same pipeline as `fasteiner/Xurrent-Helpers`.

## Build Commands

All commands must be run from the repo root (where `build.ps1` lives). Building needs the .NET SDK 8.0 or later (`dotnet`), which compiles `helper/`.

```powershell
.\build.ps1 -ResolveDependency -Tasks noop   # first-time setup
.\build.ps1 -Tasks build                     # build (downloads Magick.NET on first run, compiles helper/)
.\build.ps1 -Tasks test                      # run all tests
.\build.ps1                                  # build + test
.\build.ps1 -Tasks docs                      # generate wiki docs
Invoke-Pester -Path tests\Unit\Public\ConvertFrom-Heic.tests.ps1   # single file, after one build
```

## Architecture

```
(repo root)
  .build/Get-MagickNet.build.ps1  ← custom task: downloads Magick.NET from nuget.org into source/lib (gitignored)
  .build/Build-Helper.build.ps1   ← custom task Build_Helper: dotnet build of helper/ into output/helper, copies PSImageConverter.Helper.dll into source/lib
  helper/        ← C# class library PSImageConverter.Helper (net8.0, namespace PSImageConverter, no package references), one public class per file:
                   NativeResolver (loads Magick.Native), SafeInvoker (Invoke-ImageConverterMethod), FileIdentity (Get-ImageConverterFileIdentity on Windows),
                   HeicEncoder (+ HeicEncoderException, ExifOrientation) with the internal encoders WicHeicEncoder/WicInterop/HeifBoxEditor (Windows),
                   LibHeifHeicEncoder (Linux) and ImageIOHeicEncoder/ImageIONative (macOS)
  source/
    Public/      ← exported functions (one file per function)
    Private/     ← internal helpers (not exported)
    en-US/       ← about_PSImageConverter help
    lib/         ← Magick.NET assemblies + runtimes/<rid>/native + PSImageConverter.Helper.dll (build output, not committed)
    suffix.ps1   ← appended to the built psm1; loads the helper assembly and Magick.NET on import
    PSImageConverter.psd1
    PSImageConverter.psm1 ← empty stub; rebuilt by ModuleBuilder
  tests/
    assets/      ← sample.heic, thumbnail.heic, two-images.heic fixtures (see tests/assets/README.md)
    Helpers/     ← New-TestImage.ps1: writes test images with EXIF/XMP/IPTC/ICC/CMYK/thumbnail data, several frames, transparency, damaged JPEGs;
                   Get-TestHeifInfo.ps1: reads the HEIF boxes Magick.NET does not report (nclx colour box, ICC profile, item types, HEVC slices)
    Unit/Public/, Unit/Private/
    QA/          ← module-level quality tests (PSSA, help, changelog)
```

`build.ps1` additionally dot-sources every `*.build.ps1` in `.build/`. The Magick.NET version is pinned in `.build/Get-MagickNet.build.ps1` (`MagickNetVersion`). The `build` and `minibuild` workflows in `build.yaml` run `Clean`, `Get_MagickNet`, `Build_Helper`, then ModuleBuilder, which copies `source/lib` into the module.

### Helper assembly

`Build_Helper` runs `dotnet build -c Release --artifacts-path output/helper` (bin and obj below `output/`, which `Clean` empties; `Directory.Build.props`/`.targets` and `Directory.Packages.props` above the repo are not imported). The project builds deterministically and writes no pdb or deps.json, so the same sources and SDK give the same DLL bytes, from whatever folder they are built; only `PSImageConverter.Helper.dll` is copied into the module. It targets `net8.0` (PowerShell 7.4) and also loads in PowerShell 7.5/7.6 (.NET 9/10). It has no package references (the module ships only this DLL), so it does not reference `System.Management.Automation`: `SafeInvoker` finds `PSObject` by name to unwrap arguments.

### Loading at import

`Initialize-ImageConverterAssembly` (called from `suffix.ps1`) takes a process-wide lock, loads the helper assembly (`Import-ImageConverterHelper`) and, unless Magick.NET is already initialized, calls `Import-ImageConverterMagickNet`. That loads `Magick.NET.Core.dll` and `Magick.NET-Q8-AnyCPU.dll` (netstandard2.0) and resolves the native library from `lib/runtimes/<rid>/native` through a `NativeLibrary.SetDllImportResolver` (`[PSImageConverter.NativeResolver]::Register`, once per process). The same resolver is used on every platform; Magick.NET's own `SetNativeLibraryDirectory` only works on Windows.

`Import-ImageConverterHelper` loads `lib/PSImageConverter.Helper.dll` with `Add-Type -LiteralPath`. When the same build is already loaded (the module imported again or with `-Force`, after `Remove-Module`, from another folder, in another runspace), `Add-Type` returns the loaded assembly: .NET accepts a second load of an assembly with the same name only when its MVID (module version id, derived from the content by the deterministic build) is the same. When another build is loaded (another module version, or a module rebuilt while the session ran), .NET refuses it ("Assembly with same name is already loaded"), so the loaded one is used and a warning says so: after changing `helper/`, test in a new session. On Windows a loaded DLL cannot be deleted, so the `Clean` task fails while a session has the built module imported (as for the Magick.NET DLLs).

### Writing HEIC

Magick.NET cannot write HEIC, so `Convert-ImageConverterImage` runs its usual steps (orientation, colour profiles, `-StripMetadata`, flattening where `KeepsAlpha` of the format table is false) and then calls `Invoke-ImageConverterHeicEncoder`, which exports the pixels as 8-bit RGB/RGBA, takes the RGB ICC profile, the EXIF block (orientation set to 1 in place by `[PSImageConverter.ExifOrientation]::SetTopLeft`) and the XMP packet, and calls `[PSImageConverter.HeicEncoder]::Encode`; the returned bytes go into the temporary-file stream like every other output. `HeicEncoder` dispatches to the encoder of the platform and says what it keeps (`StoresAlpha`, `StoresMetadata`, which feed `KeepsAlpha` and `KeepsExif` of `Get-ImageConverterFormatInfo`); it wraps every error of an encoder that is not a `HeicEncoderException` in one (original as inner exception), so `Encode` throws only argument exceptions and `HeicEncoderException`. EXIF and XMP are stored as they are on both encoders: libheif takes them through its API, and on Windows `HeifBoxEditor.AddMetadataItems` adds the `Exif` and `mime` items to the file WIC wrote (WIC's own metadata writers parse the blocks and failed the image on one they could not parse). `HeifBoxEditor` also crops the WIC grid (`SetCleanAperture`, padded to whole 512 × 512 tiles, with an offset for a side of 512 × k + 1 pixels) and adds the `nclx` box (`AddNclx`, on Windows to every image item, on Linux to the primary item; libheif also gets the nclx values through `heif_image_set_nclx_color_profile`). `HeicEncoder.GetUnavailableReason()` / `GetProbeFailure()` encode a 16x16 image once per process (`Lazy`) and cache the answer; `Get-ImageConverterHeicEncoderStatus` wraps it (`IsAvailable`, `Reason`, `EncoderMissing`, `Platform`; tests mock this function), and `Assert-ImageConverterHeicEncoder` turns a missing encoder into the terminating `HeicEncoderNotAvailable` in the `begin` block of `Convert-Image`, `ConvertTo-Heic` and `ConvertFrom-Heic`. `EncoderMissing` tells "not installed" (`HeicEncoderException.EncoderMissing`; on macOS also a failed `Finalize` of the probe image) from a fault in the binding, and the real missing-encoder test asserts it, so a broken binding fails the run there. The tests that write HEIC are skipped where `GetUnavailableReason()` returns a reason (`-Skip` from a `BeforeDiscovery` block); on this kind of machine they need the HEVC Video Extensions (Windows) or `libheif1` + `libheif-plugin-x265` (Ubuntu 24.04). Set `PSIC_EXPECT_HEIC_ENCODER=1` where an encoder is installed: a test then fails when the probe does not find it working (CI sets it on Linux).

Code coverage: Sampler's Pester task imports the built module before `Invoke-Pester` runs, so code that only runs at import time is never measured. Keep import-time logic in functions a test can call again (as `Import-ImageConverterHelper` and `Import-ImageConverterMagickNet` are), and keep platform detection out of `param` default values (Pester does not measure those). The C# code is not measured; its tests go through the PowerShell functions that call it.

## Conventions

- Exported cmdlets: `Convert-Image`, the `ConvertTo-<Format>` shortcuts (Jpeg, Png, WebP, Avif, Heic, JpegXL), `ConvertFrom-Heic` and `Get-ImageInfo`; private helpers use the `ImageConverter` noun prefix (`Resolve-ImageConverterOutputPath`).
- Never use backtick line continuation; use splatting or natural line breaks.
- Every function (public and private) needs `.SYNOPSIS`, `.DESCRIPTION` > 40 chars, an `.EXAMPLE` with its name, `.PARAMETER` descriptions > 25 chars, a passing PSScriptAnalyzer run and a `tests/Unit/…/<Name>.tests.ps1`.
- C# code goes into `helper/` (one public class per file, namespace `PSImageConverter`), never into `Add-Type -TypeDefinition` at run time. Every public member has an XML doc comment (missing ones are build errors, CS1591), and comments say what the code does and why, as in the PowerShell code. No package references: the module ships only `PSImageConverter.Helper.dll`. The Windows and macOS encoders are marked `[SupportedOSPlatform]` and called behind `OperatingSystem.IsWindows()`/`IsMacOS()`; the libheif encoder is the fall-through for every other system, and `FileIdentity` (kernel32) returns null where it cannot run (PowerShell calls it on Windows only). Native libraries are bound with `DllImport` (bound on the first call, so the assembly loads on every platform): libheif by its soname `libheif.so.1`, the macOS frameworks by absolute path. Keep the public surface small: platform encoders are `internal`, and PowerShell reaches them only through `HeicEncoder`.
- Code coverage threshold is **85%** (`build.yaml`).
- Update `CHANGELOG.md` under `## [Unreleased]` with every change.
- Tests run on Pester 6: a `Mock` whose `-ParameterFilter` does not match does not fall back to the real command, so add a default mock (e.g. `Use-RealMethodInvoker` in `Convert-Image.tests.ps1`), and `$PSBoundParameters` is empty inside a mock body. Code that only runs in another runspace or process (`[powershell]::Create()`, `pwsh -NonInteractive`) is not measured by coverage.
- Every public cmdlet calls `Import-ImageConverterCallerPreference -Cmdlet $PSCmdlet` first in its `begin` block (add a `begin` block if it has none). A script module function does not see preference variables its caller set in a local scope (PowerShell issue #4568), so without it a user's function called with `-WhatIf` would make the cmdlet really write.
- Every format `ValidateSet` (`-Format`) lists exactly the formats of `Get-ImageConverterFormatInfo`; a test in its test file checks every function of the module.

### Errors and wrappers

- Report every failure about a file through `Write-ImageConverterError` (`$PSCmdlet.WriteError()` with a stable error id and the source path as target, or the input as given when it does not resolve), so `$?` is `$false` and `-ErrorVariable` gets one record per failure.
- A parameter value that makes every file fail (a bad `-DestinationPath`, `-Format Heic` without a working HEVC encoder) is checked once in `begin` and reported with `Write-ImageConverterError -Terminating` (`$PSCmdlet.ThrowTerminatingError()`, target object the parameter value), so N files give one record and nothing is converted.
- Call .NET methods that can throw through `Invoke-ImageConverterMethod`, which returns the exception instead of throwing it: an exception that reaches script code is recorded in `$Error` and `-ErrorVariable` again, even when a `catch` handles it.
- Compare existing files by `Get-ImageConverterFileIdentity`, not by path strings; path strings (`Get-ImageConverterPathComparer`) are only for files that may not exist yet.
- Wrappers (`ConvertTo-*`, `ConvertFrom-Heic`) build the steppable pipeline to `Convert-Image` in their own `begin` block (in a helper, `Convert-Image` would no longer find the private functions) and pass their parameters through `Get-ImageConverterForwardedParameter`, which drops `-ErrorVariable`, `-OutVariable`, `-PipelineVariable` and the like. They invoke the module's own `Convert-Image` through its `FunctionInfo` (`$ExecutionContext.InvokeCommand.GetCommand('Convert-Image', 'Function')`, `{ & $convertCommand @convertParameters }`): by name, a global alias `Convert-Image` would win.
- Paths are resolved through the module's session state, which sees only global PSDrives (an engine limitation, not worked around). Before a path is resolved, `Get-ImageConverterDriveScopeHint` compares the caller's drive of that name with the module's: a drive the caller created in its own scope, which the module does not find or which hides a global drive of the same name, gets `PathNotFound` (inputs) or `InvalidDestinationPath` with a message that names the drive and its root. `Get-ImageConverterPathNotFoundMessage` words every `PathNotFound` message. The hint looks the drive up in the caller's session state: `$PSCmdlet.SessionState` of the public cmdlet, or, for `Convert-Image` run by a wrapper (its caller is then module code), the wrapper's `$PSCmdlet.SessionState`, found in the call stack frame below `Convert-Image`. In tests, a drive created in an `It` block without `-Scope Global` stands for a drive created in a user's function.
- Wrappers check their parameter errors themselves (`Assert-ImageConverterDestinationPath`, and `Assert-ImageConverterHeicEncoder` in `ConvertTo-Heic` and `ConvertFrom-Heic`) before they start the pipeline: a terminating error raised inside the steppable pipeline's `Begin` reaches the wrapper's `begin` block as an ordinary statement error, so the wrapper would run on into `process`, and passing the error on puts it into `-ErrorVariable` three times.

## CI / Release

Branches: `feature/*` → PR into `dev` → `dev` is merged into `main` for a release.

- `.github/workflows/test.yml` — runs on PRs and on pushes to every branch except `main` and `dev`: PowerShell 7 on Windows, Ubuntu, macOS. On Ubuntu it installs `libheif1` and `libheif-plugin-x265` first and sets `PSIC_EXPECT_HEIC_ENCODER=1`, so the Linux HEIC encoder is tested and a broken one fails the run; the Windows runner has no HEVC Video Extensions (it tests the missing-encoder error), and the macOS runner most likely cannot encode HEVC either. Each job uploads `output/testResults/`, which holds `HeicSupport_<platform>.txt`.
- The GitHub-hosted runner images (ubuntu-24.04, windows-2025, macos-26) come with the .NET SDK 8.0, 9.0 and 10.0, which builds `helper/` (`dotnet` takes the newest); the workflows have no setup-dotnet step.
- `.github/workflows/publish.yml` — on push to `main` or `dev`: runs the tests, packs, then runs a Sampler publish workflow from `build.yaml`:
  - `main` → `publish`: GitHub release, PowerShell Gallery release, wiki, then `Create_ChangeLog_GitHub_PR` opens a PR `updateChangelogAfterv<version>` that moves `[Unreleased]` to the release.
  - `dev` → `publish_prerelease`: GitHub pre-release and PowerShell Gallery pre-release (`0.2.0-preview0007`, install with `-AllowPrerelease`); no CHANGELOG update, no wiki.
- The `PSGALLERY_API_KEY` secret lives in the `release` environment, which allows deployments from `main` and `dev` only.
- `main` and `dev` are protected (classic branch protection): changes only through pull requests, which need the checks `Test (ubuntu-latest)`, `Test (macos-latest)` and `Test (windows-latest)` from `test.yml`. The CHANGELOG PR is opened with `GITHUB_TOKEN`, which starts no workflows, so its checks never run: merge it as admin without waiting for the requirements (the rule does not enforce admins). A CHANGELOG-only push to `main` does not start `publish.yml` (`paths-ignore`).

## Versioning

GitVersion drives semver from commit messages:
- `breaking change` / `breaking` / `major` → major bump
- `adds?` / `features?` / `minor` → minor bump
- `fix` / `patch` → patch bump
- `+semver: skip` / `+semver: none` → no bump

On `dev` every commit gets its own pre-release number (`mode: ContinuousDeployment`, label `preview`), so every push can be published without a version clash.
