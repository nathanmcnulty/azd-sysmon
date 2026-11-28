#requires -Version 7.6
Describe 'Built-in Sysmon path output: <Installer>' -ForEach @(
    @{ Installer = 'deploy/azure-vm/Install-Sysmon.ps1' }
    @{ Installer = 'deploy/live-response/Install-Sysmon.ps1' }
    @{ Installer = 'deploy/intune/Remediate-Sysmon.ps1' }
) {
    BeforeAll {
        $savedWindir = $env:WINDIR
        $path = Join-Path (Split-Path $PSScriptRoot -Parent) $Installer
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
        if ($errors) { throw 'Generated installer did not parse.' }
        foreach ($name in 'Write-Status', 'Enable-BuiltInSysmon') {
            $definition = $ast.Find({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
            }, $true)
            if (-not $definition) { throw "Missing generated function: $name" }
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        # Fail-closed Windows boundary stubs keep this fixture credential-free
        # and prevent accidental feature or service operations on any test host.
        function Get-WindowsOptionalFeature { param([switch]$Online, $FeatureName, $ErrorAction) throw 'Unmocked feature read.' }
        function Enable-WindowsOptionalFeature { param([switch]$Online, $FeatureName, [switch]$NoRestart) throw 'Real feature enablement is forbidden.' }
        function Get-Service { param($Name, $ErrorAction) throw 'Unmocked service read.' }
        function Get-AuthenticodeSignature { param($FilePath) throw 'Unmocked signature read.' }
        $env:WINDIR = $TestDrive
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'System32') -Force | Out-Null
        $binary = Join-Path $TestDrive 'System32/sysmon.exe'
        Set-Content -LiteralPath $binary -Value 'fixture bytes; never executed'
    }

    AfterAll { $env:WINDIR = $savedWindir }

    It 'returns one executable path when the feature starts <State>' -ForEach @(
        @{ State = 'Disabled'; ExpectedEnables = 1 }
        @{ State = 'Enabled'; ExpectedEnables = 0 }
    ) {
        $script:featureState = $State
        Mock Get-WindowsOptionalFeature { [pscustomobject]@{ State = $script:featureState } }
        Mock Enable-WindowsOptionalFeature { [pscustomobject]@{ RestartNeeded = $false } }
        Mock Get-Service { @() }
        Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation' } } }

        $result = @(Enable-BuiltInSysmon)

        $result.Count | Should -Be 1
        $result[0] | Should -BeExactly $binary
        Should -Invoke Enable-WindowsOptionalFeature -Exactly -Times $ExpectedEnables -ParameterFilter {
            $Online -and $FeatureName -ceq 'Sysmon' -and $NoRestart
        }
    }
}
