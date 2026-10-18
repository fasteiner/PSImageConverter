function Assert-ImageConverterHeicEncoder
{
    <#
        .SYNOPSIS
        Stops the call with one terminating error when -Format is Heic and HEIC cannot be written.

        .DESCRIPTION
        Does nothing for other formats than Heic. For Heic it asks Get-ImageConverterHeicEncoderStatus
        whether the encoder of the operating system works. A missing encoder would fail every file, so,
        like a -DestinationPath that cannot name a folder, it is reported once in the begin block of
        the cmdlet passed in -Cmdlet, before any file is read and also with -WhatIf: one terminating
        error HeicEncoderNotAvailable (category NotInstalled, target object the -Format value). The
        message gives the reason, says what to install on this platform (Windows: the HEVC Video
        Extensions from the Microsoft Store; Linux: libheif with its HEVC encoder x265, built in or as
        a plugin, with the apt commands and a pointer to about_PSImageConverter for the other
        distributions; macOS: the macOS version and an HEVC encoder) and suggests -Format Avif,
        which needs nothing installed.

        .PARAMETER Cmdlet
        The $PSCmdlet of the public cmdlet that reports the error, e.g. Convert-Image or ConvertTo-Heic.

        .PARAMETER Format
        The output format of the call as the table spells it, e.g. Heic or Jpeg; only Heic is checked.

        .EXAMPLE
        Assert-ImageConverterHeicEncoder -Cmdlet $PSCmdlet -Format $Format

        Returns nothing, or throws HeicEncoderNotAvailable when -Format is Heic and no HEVC encoder is
        installed.
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet]
        $Cmdlet,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Format
    )

    if ($Format -ne 'Heic')
    {
        return
    }

    $status = Get-ImageConverterHeicEncoderStatus

    if ($status.IsAvailable)
    {
        return
    }

    $advice = @{
        Windows = "Install the 'HEVC Video Extensions' from the Microsoft Store (Windows 10 1809 or later, ms-windows-store://pdp/?ProductId=9NMZLZ57R3T7), and the 'HEIF Image Extension' (ms-windows-store://pdp/?ProductId=9PMMSR1CGPWG) if it is missing too, then start a new PowerShell session."
        Linux   = "Install libheif with its HEVC encoder x265, e.g. 'sudo apt install libheif1 libheif-plugin-x265' on Ubuntu 24.04 and 26.04 and Debian 13 ('sudo apt install libheif1' on Ubuntu 22.04 and Debian 12; for Fedora, Arch and Alpine see 'Get-Help about_PSImageConverter'), then start a new PowerShell session."
        macOS   = 'ImageIO writes HEIC on macOS 10.13 or later, on a Mac that provides an HEVC encoder; virtual machines often have none.'
    }[$status.Platform]

    $message = "HEIC cannot be written on this computer: the module uses the HEVC encoder of the operating system and ships none of its own. $($status.Reason) $advice Or use -Format Avif, which stores the image in the same HEIF container with the royalty-free AV1 codec and needs nothing installed."
    $exception = [System.PlatformNotSupportedException]::new($message)

    Write-ImageConverterError -Cmdlet $Cmdlet -Exception $exception -ErrorId 'HeicEncoderNotAvailable' -Category 'NotInstalled' -TargetObject $Format -Terminating
}
