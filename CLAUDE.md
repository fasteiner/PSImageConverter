# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

`PSImageConverter` is a PowerShell 7 module (7.4 or later, Windows/Linux/macOS; Windows PowerShell 5.1 is not supported) that converts HEIC/HEIF images using a bundled [Magick.NET](https://github.com/dlemstra/Magick.NET). The project is scaffolded with [Sampler](https://github.com/gaelcolas/Sampler) and built via InvokeBuild, with the same pipeline as `fasteiner/Xurrent-Helpers`.

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
    assets/      ← sample.heic fixture (see tests/assets/README.md)
    Unit/Public/, Unit/Private/
    QA/          ← module-level quality tests (PSSA, help, changelog)
```

`build.ps1` additionally dot-sources every `*.build.ps1` in `.build/`. The Magick.NET version is pinned in `.build/Get-MagickNet.build.ps1` (`MagickNetVersion`).

### Native library loading

`Initialize-ImageConverterMagickNet` (called from `suffix.ps1`) takes a process-wide lock and, unless Magick.NET is already initialized, calls `Import-ImageConverterMagickNet`. That loads `Magick.NET.Core.dll` and `Magick.NET-Q8-AnyCPU.dll` (netstandard2.0) and resolves the native library from `lib/runtimes/<rid>/native` through a `NativeLibrary.SetDllImportResolver` registered by `Register-ImageConverterNativeResolver`. The same resolver is used on every platform; Magick.NET's own `SetNativeLibraryDirectory` only works on Windows.

Code coverage: Sampler's Pester task imports the built module before `Invoke-Pester` runs, so code that only runs at import time is never measured. Keep import-time logic in functions a test can call again (as `Import-ImageConverterMagickNet` is), and keep platform detection out of `param` default values (Pester does not measure those).

## Conventions

- Exported cmdlets use the `Heic` noun (`ConvertFrom-Heic`, `Get-HeicInfo`); private helpers use the `ImageConverter` noun prefix (`Resolve-ImageConverterOutputPath`).
- Never use backtick line continuation; use splatting or natural line breaks.
- Every function (public and private) needs `.SYNOPSIS`, `.DESCRIPTION` > 40 chars, an `.EXAMPLE` with its name, `.PARAMETER` descriptions > 25 chars, a passing PSScriptAnalyzer run and a `tests/Unit/…/<Name>.tests.ps1`.
- Code coverage threshold is **85%** (`build.yaml`).
- Update `CHANGELOG.md` under `## [Unreleased]` with every change.

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
