# Plan: PSHeic → PSImageConverter

Working branch: `feature/initial-module` (not merged yet — merging to `main` publishes to the PowerShell Gallery).
Read `CLAUDE.md` first for build commands and conventions. Never use backtick line continuation.

## Current state

CI run on commit 155d041 (before step 1):

- Build works on all runners; Magick.NET 14.17.2 is downloaded by `.build/Get-MagickNet.build.ps1`.
- **All Pester tests pass** on ubuntu, macOS and Windows with PowerShell 7 (native loading works everywhere).
- ❌ Code coverage 78–80 % (threshold 85 %).

After step 1 (local run on Windows only; the resolver-only loading on Windows has not run in CI yet):

- Windows PowerShell 5.1 is not supported: the module targets PowerShell 7.4+ only (manifest `CompatiblePSEditions = Core`), the 5.1 CI job is removed.
- 114 tests pass, coverage 83.59 %.
- `.github/workflows/test.yml` contains a temporary "Report failures as annotations" step (added for remote debugging) — remove it once CI is green.

## 1. Rename module to PSImageConverter ✅

Done. Native loading uses the DllImport resolver on every platform now; `SetNativeLibraryDirectory` is gone. Initialisation runs under a process-wide lock (concurrent first imports in thread jobs broke Magick.NET for the whole process).

- `source/PSHeic.psd1` / `.psm1` → `source/PSImageConverter.psd1` / `.psm1`; new GUID; `ProjectUri` = `https://github.com/fasteiner/PSImageConverter`; update Description and Tags (add `JpegXL`, `AVIF`).
- `source/en-US/about_PSHeic.help.txt` → `about_PSImageConverter.help.txt`.
- Replace `PSHeic` everywhere: tests (`$script:moduleName`), `.vscode/profile.ps1`, `.vscode/settings.json`, issue template, README, CHANGELOG title, CLAUDE.md, `PSHeic.NativeResolver` C# namespace → `PSImageConverter.NativeResolver`.
- Private helper noun prefix `PSHeic` → `ImageConverter` (e.g. `Get-ImageConverterRuntimeIdentifier`, `Resolve-ImageConverterOutputPath`); rename files and test files accordingly (QA test requires `<FunctionName>.tests.ps1`).
- `PSTypeName` `PSHeic.ImageInfo` → `PSImageConverter.ImageInfo`.
- `git grep -i psheic -- ':!PLAN.md'` must return nothing afterwards.

## 2. Generalise the cmdlets

| Cmdlet             | Behaviour |
| ------------------ | --------- |
| `Convert-Image`    | Any readable source → `-Format`. Same parameters as today's `ConvertFrom-Heic` (`-Path` pipeline, `-Format`, `-Quality`, `-DestinationPath`, `-StripMetadata`, `-Force`, `-WhatIf`). Throws if target path == source path. Logic moves here from `ConvertFrom-Heic`. |
| `ConvertFrom-Heic` | Thin wrapper: validates `.heic/.heif/.hif`, then calls `Convert-Image`. Default format Jpeg. |
| `ConvertTo-Heic`   | New — see step 3. |
| `Get-ImageInfo`    | Renamed from `Get-HeicInfo` (same output). |

Behaviour found by the interactive tests in step 1 (already present before it; fix while writing `Convert-Image` / `Get-ImageInfo`, each with a Pester test):

- Tiff, Gif and Bmp output silently drop EXIF without `-StripMetadata` (Jpeg, Png, WebP, Avif keep it), contrary to help/README. Document per format and warn.
- With `-Force`, sources sharing a base name (`x.heic` + `x.heif`, or `-Recurse` into one `-DestinationPath`) overwrite each other's output. `-Force` should only overwrite files that existed before the call.
- `-Path` takes no wildcards (`ConvertFrom-Heic *.heic` fails) and there is no `-LiteralPath`. Add both parameter sets; `PSPath`/`FullName` aliases belong to `-LiteralPath`.
- Errors use `Write-Error -ErrorRecord $_`: `$?` stays `$true`, `pwsh -Command` exits 0, the FullyQualifiedErrorId is the message text, TargetObject is empty, Magick errors arrive wrapped in `MethodInvocationException`, and `-ErrorVariable` collects 3–5 records per failure. Use `$PSCmdlet.WriteError()` with stable ids and the source path as target.
- `-Force` cannot overwrite a read-only or hidden target (raw "Permission denied"); `Get-HeicInfo` on a hidden file reports `FileSize` 0 plus an ItemNotFound error (`Get-Item` without `-Force`).
- `-StripMetadata` removes the ICC profile without converting the pixels, so wide-gamut (e.g. Display P3) photos change colour. Keep the ICC profile or convert to sRGB first.
- `Orientation` is reported as `Undefined` or `TopLeft` for upright images depending on the format; normalise it.
- Low priority: `-DestinationPath` that points at a file or contains invalid characters ends in raw Magick errors; non-FileSystem provider paths reach Magick unrooted; paths over 260 characters fail inside Magick on Windows.

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

- **Coverage ≥ 85 %** ✅ — 93.85 % on Windows, 94.62 % in the Linux devcontainer (123 tests, no `ExcludeFromCodeCoverage`). Cause of the gap: Sampler's `Invoke-Pester` task imports the built module before Pester starts, so the full Magick.NET initialisation always ran unmeasured. The load path moved into `Import-ImageConverterMagickNet`, which a unit test calls again; the platform detection in `Get-ImageConverterRuntimeIdentifier` moved from the `param` default (not measured by Pester) into the body. Remaining misses (8 on Windows): the two other OS branches of the platform detection, the "Magick.NET loaded by someone else" branch and the `Import-*` call in `Initialize-*` (only reachable before the first import), and the C# compile in `Register-*NativeResolver` (once per process, at import).
- Remove the temporary annotation step from `test.yml` when green.

## 5. Docs and release

- README: new name, cmdlet table, format table, HEIC-writing support matrix from step 3.
- CHANGELOG `[Unreleased]`: describe the module as PSImageConverter (no release under the PSHeic name happened).
- CLAUDE.md: update names, architecture tree and cmdlet conventions.
- Branch flow: `feature/initial-module` → `dev` (every push to `dev` publishes a pre-release to GitHub and the PSGallery) → `main` (release). **Push to `dev` and merge to `main` only after Fabian's OK** — both publish via the `release` environment.
- `main` and `dev` have classic branch protection (PR required, checks `Test (ubuntu-latest)`, `Test (macos-latest)`, `Test (windows-latest)`), so the `dev` branch has to be created from a PR-able state: create it from `main`, then open a PR `feature/initial-module` → `dev`.
- After the first release from `main`, merge the CHANGELOG PR opened by `Create_ChangeLog_GitHub_PR` (as admin; its checks do not run). Requires the repo setting "Allow GitHub Actions to create and approve pull requests".
- Commit messages: use `adds`/`feature` for the minor bump; `+semver: skip` for CI-only fixes.
