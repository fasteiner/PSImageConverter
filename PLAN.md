# Plan: PSHeic → PSImageConverter

Working branch: `feature/initial-module` (not merged yet — merging to `main` publishes to the PowerShell Gallery).
Read `CLAUDE.md` first for build commands and conventions. Never use backtick line continuation.

## Current state (CI run on commit 155d041)

- Build works on all runners; Magick.NET 14.17.2 is downloaded by `.build/Get-MagickNet.build.ps1`.
- **All Pester tests pass** on ubuntu, macOS and Windows with PowerShell 7 (native loading works everywhere).
- ❌ Code coverage 78–80 % (threshold 85 %).
- ❌ Windows PowerShell 5.1 job: the build itself fails because `Sampler.CustomTasks` 0.3.1 uses `??` (PS 7 syntax) — not a module problem.
- `.github/workflows/test.yml` contains a temporary "Report failures as annotations" step (added for remote debugging) — remove it once CI is green.

## 1. Rename module to PSImageConverter

- `source/PSHeic.psd1` / `.psm1` → `source/PSImageConverter.psd1` / `.psm1`; new GUID; `ProjectUri` = `https://github.com/fasteiner/PSImageConverter`; update Description and Tags (add `JpegXL`, `AVIF`).
- `source/en-US/about_PSHeic.help.txt` → `about_PSImageConverter.help.txt`.
- Replace `PSHeic` everywhere: tests (`$script:moduleName`), `.vscode/profile.ps1`, `.vscode/settings.json`, issue template, README, CHANGELOG title, CLAUDE.md, `PSHeic.NativeResolver` C# namespace → `PSImageConverter.NativeResolver`.
- Private helper noun prefix `PSHeic` → `ImageConverter` (e.g. `Get-ImageConverterRuntimeIdentifier`, `Resolve-ImageConverterOutputPath`); rename files and test files accordingly (QA test requires `<FunctionName>.tests.ps1`).
- `PSTypeName` `PSHeic.ImageInfo` → `PSImageConverter.ImageInfo`.
- `git grep -i psheic` must return nothing afterwards.

## 2. Generalise the cmdlets

| Cmdlet             | Behaviour |
| ------------------ | --------- |
| `Convert-Image`    | Any readable source → `-Format`. Same parameters as today's `ConvertFrom-Heic` (`-Path` pipeline, `-Format`, `-Quality`, `-DestinationPath`, `-StripMetadata`, `-Force`, `-WhatIf`). Throws if target path == source path. Logic moves here from `ConvertFrom-Heic`. |
| `ConvertFrom-Heic` | Thin wrapper: validates `.heic/.heif/.hif`, then calls `Convert-Image`. Default format Jpeg. |
| `ConvertTo-Heic`   | New — see step 3. |
| `Get-ImageInfo`    | Renamed from `Get-HeicInfo` (same output). |

Formats (`ValidateSet` + extension map): `Jpeg .jpg`, `Png .png`, `WebP .webp`, `Avif .avif`, `Jxl .jxl`, `Heic .heic`, `Tiff .tif`, `Bmp .bmp`, `Gif .gif`.
Quality applies to lossy formats: Jpeg, WebP, Avif, Jxl, Heic.

## 3. ConvertTo-Heic — verify first, then implement

1. Add a test that dumps `[ImageMagick.MagickNET]::SupportedFormats | Where-Object Format -in 'Heic','Avif','Jxl','WebP'` with `SupportsReading` / `SupportsWriting` and run it in CI on all runners. **Do not assume** — record the result in the PR description.
2. If Magick.NET can write Heic: `ConvertTo-Heic` = `Convert-Image -Format Heic`. Done.
3. If not (expected): **ask Fabian before implementing** — proposed fallback:
   - Windows: encode via WIC (`Windows.Graphics.Imaging.BitmapEncoder.HeifEncoderId`; reference: DavidAnson/ConvertTo-Heic). Requires Windows 10 1809+ and the "HEVC Video Extensions" from the Store; give a clear error when missing.
   - Linux/macOS: terminating error that explains the limitation and suggests `-Format Avif`.
   - `Convert-Image -Format Heic` uses the same path.
   - Tests for the WIC path run only on Windows (`-Skip:(-not $IsWindows)`) and must skip gracefully when the HEVC extension is absent on the runner.

## 4. Fix CI

- **Windows PowerShell 5.1**: build with `pwsh` (`./build.ps1 -ResolveDependency -Tasks build`), then run only the tests under `powershell` (e.g. `Invoke-Pester` on `tests/Unit` with the built module on `PSModulePath`), without the coverage threshold task.
- **Coverage ≥ 85 %**: find the uncovered lines in `output/testResults/` (JaCoCo). Likely candidates: `Initialize-*` body (runs at import, possibly before coverage starts), `Register-*NativeResolver` on Windows, OS default branches in `Get-*RuntimeIdentifier`. Fix with targeted tests first; only use `ExcludeFromCodeCoverage` in `build.yaml` for genuinely platform-specific code, and say so in the PR.
- Remove the temporary annotation step from `test.yml` when green.

## 5. Docs and release

- README: new name, cmdlet table, format table, HEIC-writing support matrix from step 3.
- CHANGELOG `[Unreleased]`: describe the module as PSImageConverter (no release under the PSHeic name happened).
- CLAUDE.md: update names, architecture tree and cmdlet conventions.
- Open a PR `feature/initial-module` → `main`; **merge only after Fabian's OK** (merge triggers the PSGallery publish via the `release` environment).
- Commit messages: use `adds`/`feature` for the minor bump; `+semver: skip` for CI-only fixes.
