function Write-ImageConverterError
{
    <#
        .SYNOPSIS
        Writes an error with a stable error id through the calling cmdlet.

        .DESCRIPTION
        Creates an ErrorRecord with the given exception, error id, category and target object
        and writes it with WriteError of the public cmdlet passed in -Cmdlet, so the record's
        FullyQualifiedErrorId is '<ErrorId>,<cmdlet name>', $? is $false after the call and
        -ErrorAction of that cmdlet applies (Stop makes the error terminating). Wrapper
        exceptions (MethodInvocationException, TargetInvocationException) are replaced by the
        exception they contain. With -MessagePrefix the message shown is
        '<MessagePrefix>: <exception message>'; the exception itself stays unchanged. With
        -Terminating the record is thrown with ThrowTerminatingError of that cmdlet instead: the
        whole call stops (the caller's statement fails, try/catch catches it without
        -ErrorAction Stop), for a parameter value that would make every item fail.

        .PARAMETER Cmdlet
        The $PSCmdlet of the public cmdlet that reports the error, e.g. Convert-Image.

        .PARAMETER Exception
        The exception that describes the failure; wrapper exceptions are unwrapped first.

        .PARAMETER ErrorId
        The stable error id, e.g. TargetExists. It becomes the first part of the FullyQualifiedErrorId.

        .PARAMETER Category
        The error category of the record, e.g. ResourceExists or InvalidData.

        .PARAMETER TargetObject
        The object the error is about, normally the path of the source file.

        .PARAMETER MessagePrefix
        Optional text put in front of the exception message, e.g. "Cannot read image 'C:\a.heic'".

        .PARAMETER Terminating
        Throws the error as terminating error of the cmdlet instead of writing it.

        .EXAMPLE
        Write-ImageConverterError -Cmdlet $PSCmdlet -Exception $exception -ErrorId 'ImageReadFailed' -Category 'InvalidData' -TargetObject $sourcePath -MessagePrefix "Cannot read image '$sourcePath'"

        Writes the error 'ImageReadFailed,Convert-Image' when called from Convert-Image.
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]
        $Cmdlet,

        [Parameter(Mandatory = $true)]
        [System.Exception]
        $Exception,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ErrorId,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorCategory]
        $Category,

        [Parameter()]
        [AllowNull()]
        [System.Object]
        $TargetObject,

        [Parameter()]
        [System.String]
        $MessagePrefix,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Terminating
    )

    while (($Exception -is [System.Management.Automation.MethodInvocationException] -or $Exception -is [System.Reflection.TargetInvocationException]) -and $null -ne $Exception.InnerException)
    {
        $Exception = $Exception.InnerException
    }

    $errorRecord = [System.Management.Automation.ErrorRecord]::new($Exception, $ErrorId, $Category, $TargetObject)

    if (-not [System.String]::IsNullOrEmpty($MessagePrefix))
    {
        $errorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new("$($MessagePrefix): $($Exception.Message)")
    }

    if ($Terminating)
    {
        $Cmdlet.ThrowTerminatingError($errorRecord)
    }

    $Cmdlet.WriteError($errorRecord)
}
