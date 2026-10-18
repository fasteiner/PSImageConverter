param
(
    [Parameter()]
    [System.String]
    $OutputDirectory = (property OutputDirectory (Join-Path -Path $BuildRoot -ChildPath 'output'))
)

# Synopsis: Builds the C# helper assembly (helper/) with the .NET SDK and copies it into source/lib so ModuleBuilder copies it into the built module.
task Build_Helper {
    if (-not (Get-Command -Name 'dotnet' -CommandType Application -ErrorAction SilentlyContinue))
    {
        throw 'Building PSImageConverter needs the .NET SDK 8.0 or later (https://dot.net), which provides the dotnet command: it compiles the helper assembly in helper/.'
    }

    $projectPath = Join-Path -Path $BuildRoot -ChildPath 'helper/PSImageConverter.Helper.csproj'
    $artifactsPath = Join-Path -Path (Get-SamplerAbsolutePath -Path $OutputDirectory -RelativeTo $BuildRoot) -ChildPath 'helper'
    $libPath = Join-Path -Path $BuildRoot -ChildPath 'source/lib'

    <#
        bin and obj go below output/, which the Clean task empties, so every build compiles from scratch.
        Directory.Build.props/.targets and Directory.Packages.props in folders above the repository would
        change the build, so they are not imported.
    #>
    $buildArguments = @(
        'build', $projectPath
        '--configuration', 'Release'
        '--artifacts-path', $artifactsPath
        '--nologo'
        '-p:ImportDirectoryBuildProps=false'
        '-p:ImportDirectoryBuildTargets=false'
        '-p:ImportDirectoryPackagesProps=false'
    )

    exec { dotnet @buildArguments }

    $assemblyPath = Join-Path -Path $artifactsPath -ChildPath 'bin/PSImageConverter.Helper/release/PSImageConverter.Helper.dll'

    if (-not (Test-Path -LiteralPath $assemblyPath))
    {
        throw "dotnet build did not write '$assemblyPath'."
    }

    $null = New-Item -Path $libPath -ItemType Directory -Force
    Copy-Item -LiteralPath $assemblyPath -Destination $libPath -Force

    Write-Build Green "PSImageConverter.Helper.dll built and copied to '$libPath'."
}
