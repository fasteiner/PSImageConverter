# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

`PSImageConverter` is a PowerShell 7 module (7.4 or later, Windows/Linux/macOS; Windows PowerShell 5.1 is not supported) that converts images (HEIC/HEIF and everything else Magick.NET reads) to JPEG, PNG, WebP, AVIF, JPEG XL, TIFF, BMP or GIF using a bundled [Magick.NET](https://github.com/dlemstra/Magick.NET). The project is scaffolded with [Sampler](https://github.com/gaelcolas/Sampler) and built via InvokeBuild, with the same pipeline as `fasteiner/Xurrent-Helpers`.

## Build Commands

All commands must be run from the repo root (where `build.ps1` lives).

```powershell
.\build.ps1 -ResolveDependency -Tasks noop   # first-time setup
.\build.ps1 -Tasks build                     # build (downloads Magick.NET on first run)
.\build.ps1 -Tasks test                      # run all tests
.\build.ps1                                  # build + test
.\build.ps1 -Tasks docs                      # generate wiki docs
Invoke-Pester -Path tests\Unit\Public\ConvertFrom-Heic.tests.ps1   # single file, after one build
```

## Architecture

```
(repo root)
  .build/Get-MagickNet.build.ps1  ← custom task: downloads Magick.NET from nuget.org into source/lib (gitignored)
  source/
    Public/      ← exported functions (one file per function)
    Private/     ← internal helpers (not exported)
    en-US/       ← about_PSImageConverter help
    lib/         ← Magick.NET assemblies + runtimes/<rid>/native (build output, not committed)
    suffix.ps1   ← appended to the built psm1; loads Magick.NET on import
    PSImageConverter.psd1
    PSImageConverter.psm1 ← empty stub; rebuilt by ModuleBuilder
  tests/
    assets/      ← sample.heic, thumbnail.heic, two-images.heic fixtures (see tests/assets/README.md)
    Helpers/     ← New-TestImage.ps1: writes test images with EXIF/XMP/IPTC/ICC/CMYK/thumbnail data, several frames, transparency, damaged JPEGs
    Unit/Public/, Unit/Private/
    QA/          ← module-level quality tests (PSSA, help, changelog)
```

`build.ps1` additionally dot-sources every `*.build.ps1` in `.build/`. The Magick.NET version is pinned in `.build/Get-MagickNet.build.ps1` (`MagickNetVersion`).

### Native library loading

`Initialize-ImageConverterMagickNet` (called from `suffix.ps1`) takes a process-wide lock and, unless Magick.NET is already initialized, calls `Import-ImageConverterMagickNet`. That loads `Magick.NET.Core.dll` and `Magick.NET-Q8-AnyCPU.dll` (netstandard2.0) and resolves the native library from `lib/runtimes/<rid>/native` through a `NativeLibrary.SetDllImportResolver` registered by `Register-ImageConverterNativeResolver`. The same resolver is used on every platform; Magick.NET's own `SetNativeLibraryDirectory` only works on Windows.

Code coverage: Sampler's Pester task imports the built module before `Invoke-Pester` runs, so code that only runs at import time is never measured. Keep import-time logic in functions a test can call again (as `Import-ImageConverterMagickNet` is), and keep platform detection out of `param` default values (Pester does not measure those).

## Conventions

- Exported cmdlets: `Convert-Image`, the `ConvertTo-<Format>` shortcuts, `ConvertFrom-Heic` and `Get-ImageInfo`; private helpers use the `ImageConverter` noun prefix (`Resolve-ImageConverterOutputPath`).
- Never use backtick line continuation; use splatting or natural line breaks.
- Every function (public and private) needs `.SYNOPSIS`, `.DESCRIPTION` > 40 chars, an `.EXAMPLE` with its name, `.PARAMETER` descriptions > 25 chars, a passing PSScriptAnalyzer run and a `tests/Unit/…/<Name>.tests.ps1`.
- Code coverage threshold is **85%** (`build.yaml`).
- Update `CHANGELOG.md` under `## [Unreleased]` with every change.
- Tests run on Pester 6: a `Mock` whose `-ParameterFilter` does not match does not fall back to the real command, so add a default mock (e.g. `Use-RealMethodInvoker` in `Convert-Image.tests.ps1`), and `$PSBoundParameters` is empty inside a mock body. Code that only runs in another runspace or process (`[powershell]::Create()`, `pwsh -NonInteractive`) is not measured by coverage.
- Every public cmdlet calls `Import-ImageConverterCallerPreference -Cmdlet $PSCmdlet` first in its `begin` block (add a `begin` block if it has none). A script module function does not see preference variables its caller set in a local scope (PowerShell issue #4568), so without it a user's function called with `-WhatIf` would make the cmdlet really write.
- Every format `ValidateSet` (`-Format`) lists exactly the formats of `Get-ImageConverterFormatInfo`; a test in its test file checks every function of the module.

### Errors and wrappers

- Report every failure about a file through `Write-ImageConverterError` (`$PSCmdlet.WriteError()` with a stable error id and the source path as target, or the input as given when it does not resolve), so `$?` is `$false` and `-ErrorVariable` gets one record per failure.
- A parameter value that makes every file fail (a bad `-DestinationPath`) is checked once in `begin` and reported with `Write-ImageConverterError -Terminating` (`$PSCmdlet.ThrowTerminatingError()`, target object the parameter value), so N files give one record and nothing is converted.
- Call .NET methods that can throw through `Invoke-ImageConverterMethod`, which returns the exception instead of throwing it: an exception that reaches script code is recorded in `$Error` and `-ErrorVariable` again, even when a `catch` handles it.
- Compare existing files by `Get-ImageConverterFileIdentity`, not by path strings; path strings (`Get-ImageConverterPathComparer`) are only for files that may not exist yet.
- Wrappers (`ConvertTo-*`, `ConvertFrom-Heic`) build the steppable pipeline to `Convert-Image` in their own `begin` block (in a helper, `Convert-Image` would no longer find the private functions) and pass their parameters through `Get-ImageConverterForwardedParameter`, which drops `-ErrorVariable`, `-OutVariable`, `-PipelineVariable` and the like. They invoke the module's own `Convert-Image` through its `FunctionInfo` (`$ExecutionContext.InvokeCommand.GetCommand('Convert-Image', 'Function')`, `{ & $convertCommand @convertParameters }`): by name, a global alias `Convert-Image` would win.
- Paths are resolved through the module's session state, which sees only global PSDrives (an engine limitation, not worked around). Before a path is resolved, `Get-ImageConverterDriveScopeHint` compares the caller's drive of that name with the module's: a drive the caller created in its own scope, which the module does not find or which hides a global drive of the same name, gets `PathNotFound` (inputs) or `InvalidDestinationPath` with a message that names the drive and its root. `Get-ImageConverterPathNotFoundMessage` words every `PathNotFound` message. The hint looks the drive up in the caller's session state: `$PSCmdlet.SessionState` of the public cmdlet, or, for `Convert-Image` run by a wrapper (its caller is then module code), the wrapper's `$PSCmdlet.SessionState`, found in the call stack frame below `Convert-Image`. In tests, a drive created in an `It` block without `-Scope Global` stands for a drive created in a user's function.
- Wrappers check their parameter errors themselves (`Assert-ImageConverterDestinationPath`) before they start the pipeline: a terminating error raised inside the steppable pipeline's `Begin` reaches the wrapper's `begin` block as an ordinary statement error, so the wrapper would run on into `process`, and passing the error on puts it into `-ErrorVariable` three times.

## CI / Release

Branches: `feature/*` → PR into `dev` → `dev` is merged into `main` for a release.

- `.github/workflows/test.yml` — runs on PRs and on pushes to every branch except `main` and `dev`: PowerShell 7 on Windows, Ubuntu, macOS.
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
