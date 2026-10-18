BeforeAll {
    $script:moduleName = 'PSImageConverter'
    Import-Module -Name $script:moduleName
    $script:manifestPath = Join-Path -Path (Get-Module -Name $script:moduleName).ModuleBase -ChildPath "$($script:moduleName).psd1"

    <#
        A function of the module's session state that imports its caller's preferences, like a public
        cmdlet, and returns the values it sees afterwards. The tests call it through its FunctionInfo
        from script blocks of this file, which are outside the module's session state: there a module
        function sees neither these local values nor any other caller value without the import.
    #>
    $script:caller = InModuleScope -ModuleName $script:moduleName {
        function script:Test-ImageConverterCaller
        {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Stands for a public cmdlet that receives -WhatIf and -Confirm; it returns the preference values it sees instead of asking.')]
            [CmdletBinding(SupportsShouldProcess = $true)]
            param ()

            Import-ImageConverterCallerPreference -Cmdlet $PSCmdlet

            [PSCustomObject] @{
                WhatIfPreference      = $WhatIfPreference
                ConfirmPreference     = $ConfirmPreference
                ErrorActionPreference = $ErrorActionPreference
                WarningPreference     = $WarningPreference
                InformationPreference = $InformationPreference
                VerbosePreference     = $VerbosePreference
                DebugPreference       = $DebugPreference
            }
        }

        Get-Command -Name 'Test-ImageConverterCaller' -CommandType Function
    }
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Import-ImageConverterCallerPreference' {
    It 'Should import <Name> set in the caller''s own scope' -ForEach @(
        @{ Name = 'WhatIfPreference'; Value = $true }
        @{ Name = 'ConfirmPreference'; Value = 'Low' }
        @{ Name = 'ErrorActionPreference'; Value = 'SilentlyContinue' }
        @{ Name = 'WarningPreference'; Value = 'SilentlyContinue' }
        @{ Name = 'InformationPreference'; Value = 'Continue' }
        @{ Name = 'VerbosePreference'; Value = 'Continue' }
        @{ Name = 'DebugPreference'; Value = 'Continue' }
    ) {
        (Get-Variable -Name $Name -Scope Global).Value | Should -Not -Be $Value -Because 'the test needs a value that differs from the global one'

        $result = & {
            Set-Variable -Name $Name -Value $Value -WhatIf:$false -Confirm:$false
            & $script:caller
        }

        $result.$Name | Should -Be $Value
    }

    It 'Should leave the preference of every bound common parameter alone' {
        $result = & {
            $WhatIfPreference = $true
            $ConfirmPreference = 'Low'
            $ErrorActionPreference = 'Stop'
            $WarningPreference = 'Stop'
            $InformationPreference = 'Stop'
            $VerbosePreference = 'Stop'
            $DebugPreference = 'Stop'

            & $script:caller -WhatIf:$false -Confirm:$false -ErrorAction Continue -WarningAction Continue -InformationAction Continue -Verbose:$false -Debug:$false
        }

        $result.WhatIfPreference | Should -BeFalse
        $result.ConfirmPreference | Should -Not -Be 'Low'
        $result.ErrorActionPreference | Should -Be 'Continue'
        $result.WarningPreference | Should -Be 'Continue'
        $result.InformationPreference | Should -Be 'Continue'
        $result.VerbosePreference | Should -Be 'SilentlyContinue'
        $result.DebugPreference | Should -Be 'SilentlyContinue'
    }

    It 'Should take the values the caller sees when it sets none itself' {
        # The caller's lookup goes on to its parent scopes; a build script may have set $ErrorActionPreference there.
        $result = & $script:caller

        $result.WhatIfPreference | Should -Be $WhatIfPreference
        $result.ConfirmPreference | Should -Be $ConfirmPreference
        $result.ErrorActionPreference | Should -Be $ErrorActionPreference
    }

    It 'Should make ShouldProcess follow an imported <Name>' -ForEach @(
        @{ Name = 'WhatIfPreference'; Value = '$true'; Expected = 'False' }
        @{ Name = 'ConfirmPreference'; Value = '''Low'''; Expected = 'prompted' }
        @{ Name = 'ConfirmPreference'; Value = '''High'''; Expected = 'True' }
    ) {
        <#
            A runspace of its own, which has no user interface: the 'What if:' line goes nowhere, and a
            confirmation prompt throws, which shows that ShouldProcess wanted to ask. The function is
            defined in the module's session state there, too, and called from outside it.
        #>
        $powerShell = [System.Management.Automation.PowerShell]::Create()
        try
        {
            $script = @"
Import-Module -Name '$($script:manifestPath)'
`$caller = & (Get-Module -Name '$($script:moduleName)') {
    function script:Test-ImageConverterDecision
    {
        [CmdletBinding(SupportsShouldProcess = `$true)]
        param ()

        Import-ImageConverterCallerPreference -Cmdlet `$PSCmdlet
        `$PSCmdlet.ShouldProcess('target', 'action')
    }

    Get-Command -Name 'Test-ImageConverterDecision' -CommandType Function
}
& {
    `$$Name = $Value
    try
    {
        "`$(& `$caller)"
    }
    catch
    {
        'prompted'
    }
}
"@
            $output = $powerShell.AddScript($script).Invoke()

            $powerShell.Streams.Error | Should -BeNullOrEmpty
            "$output" | Should -Be $Expected
        }
        finally
        {
            $powerShell.Dispose()
        }
    }
}
