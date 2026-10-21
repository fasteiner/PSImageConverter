function Import-ImageConverterHelper
{
    <#
        .SYNOPSIS
        Loads the compiled helper assembly of the module, or reuses the one loaded in the process.

        .DESCRIPTION
        Loads PSImageConverter.Helper.dll from the lib folder with Add-Type. The assembly holds the
        resolver for the Magick.Native library, the SafeInvoker class behind Invoke-ImageConverterMethod,
        the FileIdentity class behind Get-ImageConverterFileIdentity and the HeicEncoder class with the
        bindings to the HEIC encoders of Windows, Linux and macOS. When the same build is already
        loaded (the module imported again, another copy of the same module version, another runspace),
        Add-Type returns the loaded assembly, also from another folder. .NET cannot load a second
        assembly of the same name, so when a different build is loaded (another version of the module,
        or a module rebuilt while this process ran), that one is used and a warning says so: commands
        that need a type or member this build added would fail. Builds are compared by the module
        version id (MVID), which the deterministic build derives from the content. Called under the
        process-wide lock of Initialize-ImageConverterAssembly.

        .PARAMETER LibraryPath
        The folder that contains PSImageConverter.Helper.dll, normally the lib folder of the module.

        .EXAMPLE
        Import-ImageConverterHelper -LibraryPath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')

        Loads the helper assembly from the lib folder of the module.
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $LibraryPath
    )

    $helperPath = Join-Path -Path $LibraryPath -ChildPath 'PSImageConverter.Helper.dll'
    $loaded = [System.AppDomain]::CurrentDomain.GetAssemblies().Where({ $_.GetName().Name -eq 'PSImageConverter.Helper' }, 'First')

    if ($loaded.Count -gt 0)
    {
        $peReader = [System.Reflection.PortableExecutable.PEReader]::new([System.IO.MemoryStream]::new([System.IO.File]::ReadAllBytes($helperPath)))

        try
        {
            $metadata = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($peReader)
            $fileVersionId = $metadata.GetGuid($metadata.GetModuleDefinition().Mvid)
        }
        finally
        {
            $peReader.Dispose()
        }

        if ($loaded[0].ManifestModule.ModuleVersionId -ne $fileVersionId)
        {
            Write-Warning -Message ("Another build of PSImageConverter.Helper.dll is already loaded in this process ('{0}'); it is used instead of '{1}'. Commands of this module may fail. Start a new PowerShell session to use this version of the module." -f $loaded[0].Location, $helperPath)
            return
        }
    }

    # Not loaded yet, or the same build: Add-Type then returns the loaded assembly, whichever folder it came from.
    Add-Type -LiteralPath $helperPath
}
