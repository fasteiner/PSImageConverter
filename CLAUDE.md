# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

`PSHeic` is a PowerShell module (Windows PowerShell 5.1 and PowerShell 7, Windows/Linux/macOS) that converts HEIC/HEIF images using a bundled [Magick.NET](https://github.com/dlemstra/Magick.NET). The project is scaffolded with [Sampler](https://github.com/gaelcolas/Sampler) and built via InvokeBuild, with the same pipeline as `fasteiner/Xurrent-Helpers`.

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
    en-US/       ← about_PSHeic help
    lib/         ← Magick.NET assemblies + runtimes/<rid>/native (build output, not committed)
    suffix.ps1   ← appended to the built psm1; loads Magick.NET on import
    PSHeic.psd1
    PSHeic.psm1  ← empty stub; rebuilt by ModuleBuilder
  tests/
    assets/      ← sample.heic fixture (see tests/assets/README.md)
    Unit/Public/, Unit/Private/
    QA/          ← module-level quality tests (PSSA, help, changelog)
```

`build.ps1` additionally dot-sources every `*.build.ps1` in `.build/`. The Magick.NET version is pinned in `.build/Get-MagickNet.build.ps1` (`MagickNetVersion`).

### Native library loading

`Initialize-PSHeicMagickNet` (called from `suffix.ps1`) loads `Magick.NET.Core.dll` and `Magick.NET-Q8-AnyCPU.dll` (netstandard2.0) and resolves the native library from `lib/runtimes/<rid>/native`:
- Windows: `MagickNET.SetNativeLibraryDirectory`
- Linux/macOS: a `NativeLibrary.SetDllImportResolver` registered by `Register-PSHeicNativeResolver` (Magick.NET's own directory setting is Windows-only)

## Conventions

- Exported cmdlets use the `Heic` noun (`ConvertFrom-Heic`, `Get-HeicInfo`); private helpers use the `PSHeic` noun prefix.
- Never use backtick line continuation; use splatting or natural line breaks.
- Every function (public and private) needs `.SYNOPSIS`, `.DESCRIPTION` > 40 chars, an `.EXAMPLE` with its name, `.PARAMETER` descriptions > 25 chars, a passing PSScriptAnalyzer run and a `tests/Unit/…/<Name>.tests.ps1`.
- Code coverage threshold is **85%** (`build.yaml`).
- Update `CHANGELOG.md` under `## [Unreleased]` with every change.

## CI / Release

- `.github/workflows/test.yml` — runs on PRs and non-main pushes: Windows PowerShell 5.1, PowerShell 7 on Windows, Ubuntu, macOS.
- `.github/workflows/publish.yml` — on push to `main`: runs the tests, then packs and publishes to the PowerShell Gallery. The `PSGALLERY_API_KEY` secret lives in the `release` environment (scoped to `main`).

## Versioning

GitVersion drives semver from commit messages:
- `breaking change` / `breaking` / `major` → major bump
- `adds?` / `features?` / `minor` → minor bump
- `fix` / `patch` → patch bump
- `+semver: skip` / `+semver: none` → no bump
