param
(
    [Parameter()]
    [System.String]
    $MagickNetVersion = (property MagickNetVersion '14.17.2'),

    [Parameter()]
    [System.String]
    $MagickNetPackage = (property MagickNetPackage 'Magick.NET-Q8-AnyCPU')
)

# Synopsis: Downloads Magick.NET from nuget.org into source/lib so ModuleBuilder copies it into the built module.
task Get_MagickNet {
    $libPath = Join-Path -Path $BuildRoot -ChildPath 'source/lib'
    $versionFile = Join-Path -Path $libPath -ChildPath 'MagickNet.version'

    if ((Test-Path -Path $versionFile) -and ((Get-Content -Path $versionFile -Raw).Trim() -eq "$MagickNetPackage $MagickNetVersion"))
    {
        Write-Build DarkGray "Magick.NET $MagickNetVersion already present in '$libPath', skipping download."
        return
    }

    if (Test-Path -Path $libPath)
    {
        Remove-Item -Path $libPath -Recurse -Force
    }

    $null = New-Item -Path $libPath -ItemType Directory -Force
    $downloadPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
    $null = New-Item -Path $downloadPath -ItemType Directory -Force

    Add-Type -AssemblyName 'System.IO.Compression.FileSystem'

    try
    {
        foreach ($packageId in @($MagickNetPackage, 'Magick.NET.Core'))
        {
            $id = $packageId.ToLowerInvariant()
            $uri = "https://api.nuget.org/v3-flatcontainer/$id/$MagickNetVersion/$id.$MagickNetVersion.nupkg"
            $nupkg = Join-Path -Path $downloadPath -ChildPath "$id.zip"
            $extractPath = Join-Path -Path $downloadPath -ChildPath $id

            Write-Build DarkGray "Downloading $uri"
            Invoke-WebRequest -Uri $uri -OutFile $nupkg -UseBasicParsing
            [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkg, $extractPath)

            # netstandard2.0 assemblies load in every PowerShell 7 release, whatever .NET version it runs on.
            $netStandardFolder = Get-ChildItem -Path (Join-Path -Path $extractPath -ChildPath 'lib') -Directory |
                Where-Object -FilterScript { $_.Name -match '^netstandard2\.?0$' } |
                    Select-Object -First 1

            if (-not $netStandardFolder)
            {
                throw "No netstandard2.0 assembly found in package $packageId $MagickNetVersion."
            }

            Copy-Item -Path (Join-Path -Path $netStandardFolder.FullName -ChildPath '*.dll') -Destination $libPath

            $runtimesPath = Join-Path -Path $extractPath -ChildPath 'runtimes'
            if (Test-Path -Path $runtimesPath)
            {
                Copy-Item -Path $runtimesPath -Destination $libPath -Recurse

                # 32-bit Windows is not supported by PSImageConverter, keep the package small.
                Remove-Item -Path (Join-Path -Path $libPath -ChildPath 'runtimes/win-x86') -Recurse -Force -ErrorAction SilentlyContinue
            }

            foreach ($noticeName in @('Notice.txt', 'Copyright.txt'))
            {
                $noticePath = Join-Path -Path $extractPath -ChildPath $noticeName
                if (Test-Path -Path $noticePath)
                {
                    Copy-Item -Path $noticePath -Destination (Join-Path -Path $libPath -ChildPath "$packageId.$noticeName")
                }
            }
        }

        Set-Content -Path $versionFile -Value "$MagickNetPackage $MagickNetVersion" -NoNewline
        Write-Build Green "Magick.NET $MagickNetVersion staged in '$libPath'."
    }
    finally
    {
        Remove-Item -Path $downloadPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
