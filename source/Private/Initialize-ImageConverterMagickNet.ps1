function Initialize-ImageConverterMagickNet
{
    <#
        .SYNOPSIS
        Loads the bundled Magick.NET once per process when the module is imported.

        .DESCRIPTION
        Runs Import-ImageConverterMagickNet under a process-wide lock, so the Magick.NET
        assemblies are loaded and the native resolver is registered exactly once, even
        when several runspaces import the module at the same time. Does nothing when
        Magick.NET is already initialized or loaded in the process.

        .PARAMETER LibraryPath
        The folder that contains the Magick.NET assemblies and the runtimes folder.

        .EXAMPLE
        Initialize-ImageConverterMagickNet -LibraryPath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
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

        if (('PSImageConverter.NativeResolver' -as [System.Type]) -and [PSImageConverter.NativeResolver]::IsRegistered)
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
