BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Initialize-ImageConverterMagickNet' {
    It 'Should have loaded Magick.NET when the module was imported' {
        'ImageMagick.MagickImage' -as [System.Type] | Should -Not -BeNullOrEmpty
    }

    It 'Should be able to call into the native library' {
        [ImageMagick.MagickNET]::Version | Should -Not -BeNullOrEmpty
    }

    It 'Should report HEIC read support' {
        $heic = [ImageMagick.MagickNET]::SupportedFormats | Where-Object -FilterScript { $_.Format -eq 'Heic' }

        $heic.SupportsReading | Should -BeTrue
    }

    It 'Should load the native library when several runspaces import the module at the same time' {
        $manifestPath = Join-Path -Path (Get-Module -Name $script:moduleName).ModuleBase -ChildPath "$($script:moduleName).psd1"
        $fixture = Join-Path -Path $PSScriptRoot -ChildPath '../../assets/sample.heic'

        # A fresh process, because the module is already initialized in this one.
        $output = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command {
            param ($ManifestPath, $Fixture)

            $jobs = 1..6 | ForEach-Object -Process {
                Start-ThreadJob -ArgumentList $ManifestPath, $Fixture -ScriptBlock {
                    param ($ManifestPath, $Fixture)

                    Import-Module -Name $ManifestPath
                    (Get-HeicInfo -Path $Fixture -ErrorAction Stop).Width
                }
            }

            $jobs | Receive-Job -Wait -AutoRemoveJob
        } -args $manifestPath, $fixture 2>&1

        $output | Where-Object -FilterScript { $_ -is [System.Management.Automation.ErrorRecord] } | Should -BeNullOrEmpty
        $output | Should -Be @(64, 64, 64, 64, 64, 64)
    }

    It 'Should not throw when Magick.NET is already loaded' {
        {
            InModuleScope -ModuleName $script:moduleName {
                Initialize-ImageConverterMagickNet -LibraryPath (Join-Path -Path $PSScriptRoot -ChildPath 'lib')
            }
        } | Should -Not -Throw
    }
}
