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

After step 2 and the fixes from its review — CI run on commit c909e5c, the first run of the whole suite on macOS, green on all three runners:

- Windows: 586 tests pass, 1 skipped (Linux only), coverage 96.95 %.
- Ubuntu: 573 pass, 14 skipped (Windows-only and case-insensitive-volume tests), coverage 95.69 %.
- macOS: 577 pass, 10 skipped (Windows-only tests), coverage 95.87 %.

After step 2b (review decisions and the fixes from their review; local run on Windows and in a Linux container, not in CI yet):

- Windows: 857 tests pass, 3 skipped, coverage 97.87 % (17 missed commands, see the coverage note in step 2).
- Linux (mcr.microsoft.com/dotnet/sdk:10.0, pwsh 7.6, Ubuntu 24.04): 843 pass, 16 skipped, coverage 97.37 %.

## 1. Rename module to PSImageConverter ✅

Done. Native loading uses the DllImport resolver on every platform now; `SetNativeLibraryDirectory` is gone. Initialisation runs under a process-wide lock (concurrent first imports in thread jobs broke Magick.NET for the whole process).

- `source/PSHeic.psd1` / `.psm1` → `source/PSImageConverter.psd1` / `.psm1`; new GUID; `ProjectUri` = `https://github.com/fasteiner/PSImageConverter`; update Description and Tags (add `JpegXL`, `AVIF`).
- `source/en-US/about_PSHeic.help.txt` → `about_PSImageConverter.help.txt`.
- Replace `PSHeic` everywhere: tests (`$script:moduleName`), `.vscode/profile.ps1`, `.vscode/settings.json`, issue template, README, CHANGELOG title, CLAUDE.md, `PSHeic.NativeResolver` C# namespace → `PSImageConverter.NativeResolver`.
- Private helper noun prefix `PSHeic` → `ImageConverter` (e.g. `Get-ImageConverterRuntimeIdentifier`, `Resolve-ImageConverterOutputPath`); rename files and test files accordingly (QA test requires `<FunctionName>.tests.ps1`).
- `PSTypeName` `PSHeic.ImageInfo` → `PSImageConverter.ImageInfo`.
- `git grep -i psheic -- ':!PLAN.md'` must return nothing afterwards.

## 2. Generalise the cmdlets ✅

Done (without `Heic` output, see step 3: Magick.NET 14.17.2 cannot write HEIC, "no encode delegate"). Exported: `Convert-Image`, `ConvertTo-Jpeg`, `ConvertTo-Png`, `ConvertTo-WebP`, `ConvertTo-Avif`, `ConvertTo-JpegXL`, `ConvertFrom-Heic`, `Get-ImageInfo`; `Get-HeicInfo` is removed (never released, no alias).

- `-Path` (wildcards) and `-LiteralPath` (aliases `PSPath`, `LP`; `Get-ChildItem` output and, since step 2b, `Get-ImageInfo` output bind here) on every public cmdlet; folders in the input are skipped, non-FileSystem paths get `UnsupportedProvider`.
- Errors through `$PSCmdlet.WriteError()` with stable ids (`PathNotFound`, `InvalidWildcardPattern`, `UnsupportedProvider`, `NotHeicFile`, `TargetIsSource`, `DuplicateTarget`, `TargetExists`, `ConfirmationFailed` (since step 2b), `ImageReadFailed`, `ImageWriteFailed`) and the source path as target (the input as given for `PathNotFound`, `InvalidWildcardPattern` and an input `UnsupportedProvider`; the `-DestinationPath` errors are terminating since step 2b): `$?` is `$false`, one record per failure in `-ErrorVariable`. Exceptions never reach script code (`Invoke-ImageConverterMethod`, which also returns out parameters), otherwise PowerShell records them a second time.
- `TargetIsSource` and `DuplicateTarget` also with `-Force`; `-Force` overwrites only files that existed before the call, and clears ReadOnly/Hidden first (restored when the file cannot be replaced). An existing target is compared with the source and with this call's outputs by file identity (`Get-ImageConverterFileIdentity`: volume serial + file id on Windows, device + inode on Unix), so junctions, symbolic links, subst/mapped drives, UNC paths, `\\?\`, 8.3 names and case-insensitive volumes on Linux are covered. Input paths are normalised with `GetFullPath` (8.3 names expanded).
- Writing goes through a temporary file `.<16 hex>.tmp` in the target folder, written through a .NET stream (ImageMagick does not see the name, so `%d`/`%x` in names and long target paths work) and moved over the target; the temporary file is deleted in `finally`, also when the pipeline is stopped. A source name ending in `[n]` is read from a stream (ImageMagick would take it as a frame selector).
- The written file is returned as the FileSystem provider returns it (PSPath), so `ConvertTo-Png 'a[1].heic' | Get-ImageInfo` binds `-LiteralPath`.
- After auto-orient the EXIF thumbnail is removed and the XMP `tiff:Orientation` / pixel dimensions are updated; CMYK sources are converted to sRGB through their profile for every format except Jpeg and Tiff.
- `-StripMetadata` keeps the ICC profile (also for PNG; lossy Jxl gets sRGB pixels instead since step 2b); Tiff/Gif/Bmp output warns when EXIF is lost; per-format metadata is documented in the `Convert-Image` help and the README.
- `ConvertFrom-Heic` and the `ConvertTo-*` wrappers forward their whole pipeline through a steppable pipeline to one `Convert-Image` call. `ConvertTo-*` start it with `Begin($PSCmdlet)` and pass `$_` on; `ConvertFrom-Heic` resolves the paths itself (extension check; files that are targets of this call are skipped) and starts it with `Begin($true, $ExecutionContext)`. The `*Variable` and `OutBuffer` common parameters are not forwarded (`Get-ImageConverterForwardedParameter`); the wrapper applies them.

### Step 2b: decisions on the review findings ✅

- Lossy Jxl (`-Quality` below 100): the bundled encoder stores no ICC profile there, so the pixels of a source with a profile are converted to sRGB first (with and without `-StripMetadata`, after the CMYK step); Quality 100 keeps the profile. Tested over all 8 formats with the colour a colour-managed viewer shows. A profile made for other pixels (grey profile in a colour image or the other way round) is ignored, as Chromium does; ImageMagick would turn the colour image grey.
- Jpeg output flattens transparency onto white (for a CMYK source, which stays CMYK, the CMYK white C=M=Y=K=0; ImageMagick takes the numbers of an sRGB background colour as CMYK ink); the other formats keep the alpha channel. Tiff output of an image with alpha and a bit depth below 8 (palette PNGs with up to 16 colours) is written with 8 bits per sample, otherwise ImageMagick rounds colours and alpha to that depth.
- Several frames (animated GIF/WebP, multi-page TIFF, HEIC with several images): the first frame is converted with the warning `Only the first of <N> frames is converted: <path>`; the frames are counted without decoding pixels (`Get-ImageConverterFrameCount`). A layered PSD counts as one frame.
- Damaged sources: a `CorruptImageWarning` of Magick.NET becomes the warning `The image may be damaged (<reasons>): <path>` (once per source, in `Convert-Image` and `Get-ImageInfo`), with the related warnings Magick.NET attaches to the one it raises; other ImageMagick warnings go to the verbose stream. A file whose first frame reads but whose frames cannot be counted (`CorruptImageError` of the ping, e.g. an animated GIF cut off after frame 1) gets the same warning. With `-WarningAction Stop` the decoded image is still disposed.
- PNG output with an ICC profile has it only as iCCP chunk (`Select-ImageConverterPngChunk` removes ImageMagick's zTXt copy). When ImageMagick writes neutral grey pixels as a greyscale PNG with an RGB profile (which readers drop), the image is encoded again with `png:color-type` 2 or 6.
- `-Confirm` (or a caller's `$ConfirmPreference`) in a host that cannot prompt gives `ConfirmationFailed` per file (ShouldProcess through `Invoke-ImageConverterMethod`). It is not terminating: a terminating error from `Convert-Image`'s process block reaches a wrapper's process block only as a statement error, so the wrapper's next pipeline object hit the stopped steppable pipeline (NullReferenceException), and passing it on with `ThrowTerminatingError` gave three `-ErrorVariable` entries and the wrapper's name.
- Errors raised inside `Convert-Image` keep the FullyQualifiedErrorId `<Id>,Convert-Image` also when a wrapper was called (accepted and documented; it comes with the steppable pipeline).
- `Get-ImageInfo` objects carry a `PSPath` property hidden from the default view (`DefaultDisplayPropertySet` with the 10 visible properties), so they pipe into the conversion cmdlets; a file named twice is described once.
- A bad `-DestinationPath` (`InvalidDestinationPath`, `UnsupportedProvider`, `DestinationNotDirectory`; also white space only, a provider-qualified path without a folder and a junction or symbolic link whose target is gone) is a parameter error: checked once in `begin` (`Assert-ImageConverterDestinationPath`), one terminating error (`Write-ImageConverterError -Terminating`, target the `-DestinationPath` value), nothing converted, also with `-WhatIf`. A folder that cannot be created or written to (permissions, read-only file system) is not checked up front and fails each file with `ImageWriteFailed`. A relative path above the drive root stays at the root (PowerShell path semantics). The wrappers make the same check themselves before they start `Convert-Image`, so through a wrapper the error carries the wrapper's name (`DestinationNotDirectory,ConvertTo-Jpeg`): a terminating error from the steppable pipeline's `Begin` reaches the wrapper's `begin` block only as a statement error (the wrapper would run on into `process`), and passing it on puts three entries into `-ErrorVariable`.
- Every public cmdlet imports the caller's `WhatIf`/`Confirm`/`ErrorAction`/`Warning`/`Information`/`Verbose`/`Debug` preference variables (`Import-ImageConverterCallerPreference`, PowerShell issue #4568) unless the common parameter is bound, so a user's function called with `-WhatIf` no longer makes `Convert-Image` write. `Set-Variable` inside the helper needs `-WhatIf:$false -Confirm:$false`, otherwise it follows a WhatIfPreference it has just imported.
- Concurrent writers to one target without `-Force`: on Linux/macOS `File.Move(temp, target, $false)` is check-then-rename, so both can succeed — documented only (Convert-Image help, README, about help).
- The wrappers call the module's `Convert-Image` through its `FunctionInfo`, so a global alias `Convert-Image` no longer diverts them.
- `PathNotFound` for a wildcard pattern says that no file matches and that wildcards skip hidden files (Windows: Hidden attribute; Linux/macOS: dot files), which `-LiteralPath` reaches, and for a pattern with unescaped `[` or `]` that these are wildcard characters. An invalid pattern is `InvalidWildcardPattern` also when no file has that literal name (the resolver checks the pattern only against such a file; `WildcardPattern.IsMatch` checks it otherwise). A pattern of another provider gets one `UnsupportedProvider` per input, not one per match. Help has `.INPUTS`/`.OUTPUTS` on every public cmdlet; a test compares every `-Format` ValidateSet with the table of `Get-ImageConverterFormatInfo`.

Deferred / open:

- Source paths over 260 characters on Windows still fail to read (a clean `ImageReadFailed` record): ImageMagick opens the source by name. Writing goes through .NET and works for long target paths.
- `-WhatIf` predicts `TargetIsSource`/`DuplicateTarget` by path string only; an alias of a folder (junction, symlink, UNC) or a case-insensitive volume on Linux is only detected in the real run, by file identity, when the target exists.
- Hard links of one file share the identity: converting one onto the other is refused as `TargetIsSource` although replacing the link would not touch the source.
- A JPEG that lacks only its 2-byte end marker (FF D9) gets the damage warning ("Premature end of JPEG file") although its pixels are complete: libjpeg reports it as corrupt. Not covered by a test; whether this warning is wanted is open.
- An animated GIF cut off so early in its second frame that the ping still succeeds (it then reports 1 frame) converts without any warning; only a cut that makes the ping fail is reported.
- Malformed profiles with lossless Jxl (`-Quality 100`): an RGB image with a grey ICC profile, or a grey image with an RGB profile, fails with `ImageWriteFailed` ("UnableToWriteImageData", jxl.c). Avif output that keeps a grey profile on RGB pixels is not displayed by Chromium. Tiff output of neutral grey pixels with an RGB profile is a greyscale TIFF with that profile (ImageMagick reads it; stricter readers may not).
- Coverage (17 misses on Windows): the `{ & $convertCommand @convertParameters }` command in each wrapper counts as missed (a steppable pipeline never runs the script block; 6 misses — moving the pipeline creation into a shared helper does not work: `Convert-Image` then no longer finds the private functions); the stream dispose in the `finally` block of `Convert-ImageConverterImage` runs only in the Ctrl+C test's own runspace, which coverage does not measure; the Unix branches of `Get-ImageConverterFileIdentity`, `Get-ImageConverterPathComparer` and `Get-ImageConverterRuntimeIdentifier`; and the import-time code listed in step 4.

Original step-2 plan (the Done summary above describes what was implemented):

| Cmdlet             | Behaviour |
| ------------------ | --------- |
| `Convert-Image`    | Any readable source → `-Format`. Same parameters as today's `ConvertFrom-Heic` (`-Path` pipeline, `-Format`, `-Quality`, `-DestinationPath`, `-StripMetadata`, `-Force`, `-WhatIf`). Target == source gives a non-terminating `TargetIsSource` error, also with `-Force`. Logic moves here from `ConvertFrom-Heic`. |
| `ConvertFrom-Heic` | Thin wrapper: validates `.heic/.heif/.hif`, then calls `Convert-Image`. Default format Jpeg. |
| `ConvertTo-Jpeg`, `ConvertTo-Png`, `ConvertTo-WebP`, `ConvertTo-Avif`, `ConvertTo-JpegXL` | Thin wrappers: any readable source → `Convert-Image -Format Jpeg/Png/WebP/Avif/Jxl`. Same parameters as `Convert-Image` minus `-Format`; `ConvertTo-Png` has no `-Quality` (lossless). |
| `ConvertTo-Heic`   | Not in step 2 — see step 3. Same wrapper shape as the other `ConvertTo-*`. |
| `Get-ImageInfo`    | Renamed from `Get-HeicInfo`; `Orientation` `Undefined` is reported as `TopLeft`. |

`ConvertTo-*` wrappers:

- One per common target format only; Tiff, Bmp and Gif stay with `Convert-Image -Format`. No `ConvertFrom-*` besides `ConvertFrom-Heic`: Magick.NET detects the source format from the content, so `Convert-Image` / `ConvertTo-*` already read every source.
- Pass the bound parameters through to `Convert-Image` (splatting), so pipeline input (`Get-ChildItem | ConvertTo-WebP`), `-WhatIf`/`-Confirm` and errors behave exactly like `Convert-Image`.
- Each gets its own help (with an example per wrapper) and `tests/Unit/Public/ConvertTo-<Format>.tests.ps1`: output extension and re-read format, pipeline input, `-WhatIf`, `-Quality` where it applies, and that a source already in the target format (e.g. `ConvertTo-Jpeg` on a `.jpg` without `-DestinationPath`) fails with the same-path error instead of overwriting the source.

Behaviour found by the interactive tests in step 1 (original notes, all fixed in step 2; e.g. the `-LiteralPath` aliases became `PSPath` and `LP`, without `FullName`):

- Tiff, Gif and Bmp output silently drop EXIF without `-StripMetadata` (Jpeg, Png, WebP, Avif keep it), contrary to help/README. Document per format and warn.
- With `-Force`, sources sharing a base name (`x.heic` + `x.heif`, or `-Recurse` into one `-DestinationPath`) overwrite each other's output. `-Force` should only overwrite files that existed before the call.
- `-Path` takes no wildcards (`ConvertFrom-Heic *.heic` fails) and there is no `-LiteralPath`. Add both parameter sets; `PSPath`/`FullName` aliases belong to `-LiteralPath`.
- Errors use `Write-Error -ErrorRecord $_`: `$?` stays `$true`, `pwsh -Command` exits 0, the FullyQualifiedErrorId is the message text, TargetObject is empty, Magick errors arrive wrapped in `MethodInvocationException`, and `-ErrorVariable` collects 3–5 records per failure. Use `$PSCmdlet.WriteError()` with stable ids and the source path as target.
- `-Force` cannot overwrite a read-only or hidden target (raw "Permission denied"); `Get-HeicInfo` on a hidden file reports `FileSize` 0 plus an ItemNotFound error (`Get-Item` without `-Force`).
- `-StripMetadata` removes the ICC profile without converting the pixels, so wide-gamut (e.g. Display P3) photos change colour. Keep the ICC profile or convert to sRGB first.
- `Orientation` is reported as `Undefined` or `TopLeft` for upright images depending on the format; normalise it.
- Low priority: `-DestinationPath` that points at a file or contains invalid characters ends in raw Magick errors; non-FileSystem provider paths reach Magick unrooted; paths over 260 characters fail inside Magick on Windows.

Formats (`ValidateSet` + extension map): `Jpeg .jpg`, `Png .png`, `WebP .webp`, `Avif .avif`, `Jxl .jxl`, `Tiff .tif`, `Bmp .bmp`, `Gif .gif` (`Heic .heic` follows in step 3).
Quality applies to lossy formats: Jpeg, WebP, Avif, Jxl (and Heic in step 3).

## 3. ConvertTo-Heic — encoders of the operating system

Verified: the bundled Magick.NET 14.17.2 reads HEIC/HEIF but cannot write it (`SupportsWriting = False`, "no encode delegate for this image format `HEIC'"). It does write Jxl and Avif.

HEIC is written with the encoder the operating system or distribution provides. The module ships nothing HEVC-related (HEVC patent pools, x265 licence); the encoder is the user's installation.

| Platform | Encoder | Requirement on the user's machine | CI |
| -------- | ------- | --------------------------------- | -- |
| Windows  | WIC HEIF encoder (`GUID_ContainerFormatHeif`; reference: DavidAnson/ConvertTo-Heic) | Windows 10 1809+ and the "HEVC Video Extensions" from the Store | runner has no HEVC extension: test skips |
| macOS    | ImageIO (`CGImageDestinationCreateWithURL`, type `public.heic`) | none (macOS 10.13+) | `macos-latest` |
| Linux    | system `libheif` via P/Invoke (`heif_context_get_encoder_for_format(heif_compression_HEVC)`) | `libheif1` + x265 plugin, e.g. `sudo apt install libheif1 libheif-plugin-x265` (verified on Ubuntu 24.04: libheif 1.17.6, x265 3.5) | `ubuntu-latest`, CI installs the packages |

- `ConvertTo-Heic` is a wrapper like the other `ConvertTo-*`; `Convert-Image -Format Heic` uses the same path (Heic joins the format list with `.heic`, lossy, so `-Quality` applies).
- Magick.NET decodes and auto-orients; the pixels go to the OS encoder as an RGB(A) buffer. EXIF and the ICC profile are passed on where the encoder API allows it; document per platform what is kept.
- Encoder missing → error per item (stable id, e.g. `HeicEncoderNotAvailable`) that names what to install on this platform and suggests `-Format Avif`.
- C# helper assembly (one small DLL in `lib`, target `net8.0` = PowerShell 7.4): the native resolver plus the three encoder bindings, built with `dotnet build` by a task in `.build/`, loaded with `Add-Type -LiteralPath`. It also takes the three classes that are compiled at runtime today: the native resolver (`Add-Type -TypeDefinition` on every import), `PSImageConverter.SafeInvoker` (`Invoke-ImageConverterMethod`) and `PSImageConverter.FileIdentity` (`Get-ImageConverterFileIdentity`, Windows), both compiled on the first conversion; `Add-ImageConverterType` then goes away. After step 2 on Windows: import ~1.1 s, first conversion of a 64x64 image ~0.65 s. The build then needs the .NET SDK (GitHub runners and the devcontainer have it).
- Windows binding: prefer classic COM WIC (`IWICImagingFactory`, `IWICBitmapEncoder` with `GUID_ContainerFormatHeif`) over `Windows.Graphics.Imaging`: WinRT projections are not built into .NET 5+ and would need CsWinRT / the large Windows SDK projection assembly.
- Windows path is tested locally: Fabian's machine has the HEVC Video Extension 2.5.48, the HEIF Image Extension 1.2.62 and hardware HEVC encoders (Intel Arc, NVIDIA RTX 500), so the WIC test runs in every local `./build.ps1 -Tasks test`. GitHub-hosted Windows runners cannot provide it (no Store, no GPU; downloading the paid extension from the Store CDN is a licence grey zone) and Docker cannot either (Windows containers have no AppX, Media Foundation codecs or GPU). No self-hosted runner: the Windows path stays a local test.
- README (same commit as the code, so it never promises more than the module does):
  - section "Writing HEIC files": why the module ships no HEVC encoder (patents, x265 licence) and uses the one of the operating system;
    the platform table above as user instructions — Windows: install "HEVC Video Extensions" from the Microsoft Store (Windows 10 1809+);
    macOS: nothing to install; Linux: install commands per distribution (Ubuntu/Debian `sudo apt install libheif1 libheif-plugin-x265`,
    Fedora `libheif-freeworld` from RPM Fusion, Arch `libheif` + `x265`, Alpine `libheif` + `x265`; verify the non-Ubuntu package names before writing them down);
    what the error says when the encoder is missing, and `-Format Avif` as the patent-free alternative in the same HEIF container;
  - format table: Heic becomes writable "with the OS encoder", with the per-platform requirement;
  - Development section: the Windows HEIC test only runs where the HEVC extension is installed (locally, not on GitHub-hosted runners, not in Docker), the CI installs libheif on ubuntu-latest, macOS uses ImageIO; the C# helper is built with `dotnet build`, so building needs the .NET SDK.
- about_PSImageConverter.help.txt gets the same platform requirements in short form.
- Tests: one per platform path, `-Skip` when the encoder is not available (and assert the error message in that case); a test that records `[ImageMagick.MagickNET]::SupportedFormats` read/write support for Heic, Avif, Jxl, WebP on every runner (put the result in the PR description).

## 4. Fix CI

- **Coverage ≥ 85 %** ✅ (97.87 % on Windows after step 2b) — at the time 93.85 % on Windows, 94.62 % in the Linux devcontainer (123 tests, no `ExcludeFromCodeCoverage`). Cause of the gap: Sampler's `Invoke-Pester` task imports the built module before Pester starts, so the full Magick.NET initialisation always ran unmeasured. The load path moved into `Import-ImageConverterMagickNet`, which a unit test calls again; the platform detection in `Get-ImageConverterRuntimeIdentifier` moved from the `param` default (not measured by Pester) into the body. Remaining misses (8 on Windows): the two other OS branches of the platform detection, the "Magick.NET loaded by someone else" branch and the `Import-*` call in `Initialize-*` (only reachable before the first import), and the C# compile in `Register-*NativeResolver` (once per process, at import).
- Remove the temporary annotation step from `test.yml` when green (CI has been green since step 2, commit c909e5c; the step is still there).

## 5. Docs and release

- README: new name, cmdlet table, format table (with per-format metadata) ✅ in step 2; HEIC-writing support matrix from step 3 still open.
- CHANGELOG `[Unreleased]`: describe the module as PSImageConverter (no release under the PSHeic name happened) ✅ in step 2; add step 3.
- CLAUDE.md: update names, architecture tree and cmdlet conventions ✅ in step 2 (review fixes); add step 3.
- Branch flow: `feature/initial-module` → `dev` (every push to `dev` publishes a pre-release to GitHub and the PSGallery) → `main` (release). **Push to `dev` and merge to `main` only after Fabian's OK** — both publish via the `release` environment.
- `main` and `dev` have classic branch protection (PR required, checks `Test (ubuntu-latest)`, `Test (macos-latest)`, `Test (windows-latest)`), so the `dev` branch has to be created from a PR-able state: create it from `main`, then open a PR `feature/initial-module` → `dev`.
- After the first release from `main`, merge the CHANGELOG PR opened by `Create_ChangeLog_GitHub_PR` (as admin; its checks do not run). Requires the repo setting "Allow GitHub Actions to create and approve pull requests".
- Commit messages: use `adds`/`feature` for the minor bump; `+semver: skip` for CI-only fixes.
