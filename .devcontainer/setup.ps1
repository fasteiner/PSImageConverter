Write-Host "🔧 Installing PowerShell tooling (Preview versions)..."

# The Linux HEIC tests need the libheif of the distribution with its HEVC encoder x265, as in CI
# (test.yml); without them they are skipped. devcontainer.json sets PSIC_EXPECT_HEIC_ENCODER, so a
# missing or broken encoder fails the tests instead. apt-get needs root, so another user runs it
# through sudo.
$installLibHeif = 'export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y libheif1 libheif-plugin-x265'
if ((id -u) -eq '0') {
    bash -c $installLibHeif
} else {
    sudo bash -c $installLibHeif
}
if ($LASTEXITCODE -ne 0) {
    Write-Warning "libheif and libheif-plugin-x265 could not be installed (exit code $LASTEXITCODE); the HEIC tests will fail."
}

# Trust PSGallery to avoid prompts
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Install preview modules
Install-Module Pester -Force -AllowPrerelease
Install-Module Microsoft.PowerShell.PlatyPS -Force
Install-Module Sampler -Force -AllowPrerelease

# Add NuGet source (safe to re-run)
dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org

# Install GitVersion as global tool
dotnet tool install --global GitVersion.Tool --version 5.12.0

# Ensure the .dotnet/tools path is added to current PATH
$dotnetToolsPath = [System.IO.Path]::Combine($HOME, ".dotnet", "tools")
if ($env:PATH -notlike "*$dotnetToolsPath*") {
    Write-Host "➕ Adding $dotnetToolsPath to PATH"
    $env:PATH = "$dotnetToolsPath`:$env:PATH"
}

# Add to PowerShell profile for persistence
$profileScript = $PROFILE
if (-not (Test-Path -Path $profileScript)) {
    New-Item -ItemType File -Path $profileScript -Force | Out-Null
}
Add-Content -Path $profileScript -Value @"
# Added by devcontainer setup
`$dotnetTools = [System.IO.Path]::Combine(`$HOME, '.dotnet', 'tools')
if (`$env:PATH -notlike "*`$dotnetTools*") {
    `$env:PATH = "`$dotnetTools``:`$env:PATH"
}
"@

Write-Host "✅ Setup complete. Verifying GitVersion..."
dotnet-gitversion /showvariable SemVer

# Resolve build dependencies
./build.ps1 -tasks noop -ResolveDependency -UseModuleFast
