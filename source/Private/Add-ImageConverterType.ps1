function Add-ImageConverterType
{
    <#
        .SYNOPSIS
        Compiles a C# type once per process unless it exists already.

        .DESCRIPTION
        Compiles the C# source in -TypeDefinition with Add-Type when the type named in -TypeName
        does not exist yet, and does nothing otherwise. Runspaces of one process share compiled
        types, so the check and the compilation run under a process-wide lock: two runspaces
        (Start-ThreadJob, ForEach-Object -Parallel) that need the type at the same time compile
        it only once.

        .PARAMETER TypeName
        The full name of the type the source defines, e.g. 'PSImageConverter.SafeInvoker'.

        .PARAMETER TypeDefinition
        The C# source code that defines the type named in -TypeName.

        .EXAMPLE
        Add-ImageConverterType -TypeName 'PSImageConverter.SafeInvoker' -TypeDefinition $source

        Compiles the SafeInvoker class on first use.
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $TypeName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $TypeDefinition
    )

    if ($TypeName -as [System.Type])
    {
        return
    }

    $lockObject = [System.String]::Intern($TypeName)
    $lockTaken = $false

    try
    {
        [System.Threading.Monitor]::Enter($lockObject, [ref] $lockTaken)

        # Another runspace may have compiled the type while this one waited for the lock.
        if (-not ($TypeName -as [System.Type]))
        {
            Add-Type -TypeDefinition $TypeDefinition -Language CSharp
        }
    }
    finally
    {
        if ($lockTaken)
        {
            [System.Threading.Monitor]::Exit($lockObject)
        }
    }
}
