BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-ImageConverterHeicEncoderStatus' {
    BeforeAll {
        $script:status = InModuleScope -ModuleName $script:moduleName { Get-ImageConverterHeicEncoderStatus }
    }

    It 'Should name the platform whose encoder is used' {
        $expected = 'Linux'
        if ($IsWindows)
        {
            $expected = 'Windows'
        }
        elseif ($IsMacOS)
        {
            $expected = 'macOS'
        }

        $script:status.Platform | Should -BeExactly $expected
    }

    It 'Should report the result of the probe of the helper assembly' {
        $reason = [PSImageConverter.HeicEncoder]::GetUnavailableReason()

        $script:status.IsAvailable | Should -Be ($null -eq $reason)
        $script:status.Reason | Should -Be $reason
    }

    It 'Should say that the encoder is missing exactly when the probe failed because no encoder is installed' {
        $failure = [PSImageConverter.HeicEncoder]::GetProbeFailure()

        $script:status.EncoderMissing | Should -Be ($null -ne $failure -and $failure.EncoderMissing)
    }

    It 'Should find a working encoder where the run expects one (PSIC_EXPECT_HEIC_ENCODER)' -Skip:(-not $env:PSIC_EXPECT_HEIC_ENCODER) {
        # CI sets the variable where it installs an encoder, so a broken encoder binding fails the run instead of skipping every HEIC test.
        $script:status.IsAvailable | Should -BeTrue -Because $script:status.Reason
    }

    It 'Should give a reason exactly when HEIC cannot be written' {
        if ($script:status.IsAvailable)
        {
            $script:status.Reason | Should -BeNullOrEmpty
        }
        else
        {
            $script:status.Reason | Should -Not -BeNullOrEmpty
        }
    }
}
