function Initialize-ImageConverterAssembly
{
    <#
        .SYNOPSIS
        Loads the helper assembly and the bundled Magick.NET once per process when the module is imported.

        .DESCRIPTION
        Loads the compiled helper assembly (Import-ImageConverterHelper) and then Magick.NET
        (Import-ImageConverterMagickNet) under a process-wide lock, so the assemblies are loaded and
        the native resolver is registered exactly once, even when several runspaces import the module
        at the same time. Magick.NET is skipped when it is already initialized or loaded in the process.

        .PARAMETER LibraryPath
        The folder that contains the helper assembly, the Magick.NET assemblies and the runtimes folder.

        .EXAMPLE
        Initialize-ImageConverterAssembly -LibraryPath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')

        Loads the assemblies from the lib folder of the module.
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $LibraryPath
    )

    <#
        Runspaces of one process (Start-ThreadJob, ForEach-Object -Parallel) can import the module at the
        same time. The Magick.NET types are visible to all of them as soon as one runspace has added them,
        but Magick.Native is only found after the resolver is registered. A runspace that calls Magick.NET
        in between fails, and .NET keeps that failed type initializer for the lifetime of the process.
        The interned string is the same object in every runspace, so it serves as a process-wide lock.
    #>
    $lockObject = [System.String]::Intern('PSImageConverter.Initialize')
    $lockTaken = $false

    try
    {
        [System.Threading.Monitor]::Enter($lockObject, [ref] $lockTaken)

        # The resolver for Magick.Native is part of the helper assembly, so it is loaded first.
        Import-ImageConverterHelper -LibraryPath $LibraryPath

        if ([PSImageConverter.NativeResolver]::IsRegistered)
        {
            Write-Verbose -Message 'Magick.NET is already initialized in this process.'
            return
        }

        if ('ImageMagick.MagickImage' -as [System.Type])
        {
            Write-Verbose -Message 'Magick.NET is already loaded in this session.'
            return
        }

        Import-ImageConverterMagickNet -LibraryPath $LibraryPath
    }
    finally
    {
        if ($lockTaken)
        {
            [System.Threading.Monitor]::Exit($lockObject)
        }
    }
}
