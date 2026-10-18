function Get-ImageConverterHeicEncoderStatus
{
    <#
        .SYNOPSIS
        Returns whether the HEIC encoder of the operating system can write HEIC on this machine.

        .DESCRIPTION
        Asks the helper assembly (PSImageConverter.HeicEncoder) whether HEIC can be written. The
        module ships no HEVC encoder: it uses the WIC HEIF encoder with the HEVC Video Extensions on
        Windows, the libheif of the distribution with its HEVC encoder x265 (built in or as a plugin)
        on Linux and ImageIO on macOS. The first call in a process encodes a 16x16 test image with
        that encoder; the result is kept for the lifetime of the process, so an encoder installed
        later needs a new PowerShell session. Returns an object with IsAvailable, Reason (why HEIC
        cannot be written, $null when it can), EncoderMissing ($true when no encoder is installed;
        $false when HEIC can be written, or when an installed encoder or the module's binding to it
        failed) and Platform (Windows, Linux or macOS). The cmdlets call it through
        Assert-ImageConverterHeicEncoder; the tests mock it to show the error of a missing encoder on
        every machine.

        .EXAMPLE
        Get-ImageConverterHeicEncoderStatus

        Returns IsAvailable $true, Reason $null, EncoderMissing $false and Platform 'Windows' on a
        Windows machine with the HEVC Video Extensions.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param ()

    $failure = [PSImageConverter.HeicEncoder]::GetProbeFailure()

    [PSCustomObject] @{
        IsAvailable    = $null -eq $failure
        Reason         = [PSImageConverter.HeicEncoder]::GetUnavailableReason()
        EncoderMissing = $null -ne $failure -and $failure.EncoderMissing
        Platform       = [PSImageConverter.HeicEncoder]::Platform
    }
}
