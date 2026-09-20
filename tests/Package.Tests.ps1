#requires -Version 7.0

BeforeAll {
    $templateRoot = Split-Path -Parent $PSScriptRoot
    $builderPath = Join-Path $templateRoot 'scripts\Build-SysmonPackages.ps1'
    $manifestPath = Join-Path $templateRoot 'config\sysmon-modular-release.json'

    function Restore-DefaultPackage {
        & $builderPath -DefaultConfiguration balanced
    }
}

Describe 'Sysmon package builder' {
    AfterAll { Restore-DefaultPackage }

    It 'builds byte-identical default artifacts twice from the vendored catalog' {
        & $builderPath -DefaultConfiguration balanced
        $first = @('config\generated-package-manifest.json', 'deploy\intune\Detect-Sysmon.ps1', 'deploy\intune\Remediate-Sysmon.ps1', 'deploy\live-response\Install-Sysmon.ps1', 'deploy\azure-vm\Install-Sysmon.ps1') | ForEach-Object {
            (Get-FileHash -LiteralPath (Join-Path $templateRoot $_) -Algorithm SHA256).Hash
        }
        & $builderPath -DefaultConfiguration balanced
        $second = @('config\generated-package-manifest.json', 'deploy\intune\Detect-Sysmon.ps1', 'deploy\intune\Remediate-Sysmon.ps1', 'deploy\live-response\Install-Sysmon.ps1', 'deploy\azure-vm\Install-Sysmon.ps1') | ForEach-Object {
            (Get-FileHash -LiteralPath (Join-Path $templateRoot $_) -Algorithm SHA256).Hash
        }
        $second | Should -BeExactly $first
    }

    It 'rejects malformed custom XML before generating a package' {
        $customRoot = Join-Path ([IO.Path]::GetTempPath()) ('azd-sysmon-malformed-' + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $customRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $customRoot 'workstation.xml') -Value '<Sysmon><EventFiltering>' -NoNewline
            { & $builderPath -CustomConfigurationFolder $customRoot -DefaultConfiguration workstation } | Should -Throw
        } finally {
            if (Test-Path -LiteralPath $customRoot) { Remove-Item -LiteralPath $customRoot -Recurse -Force }
        }
    }

    It 'rejects a custom filename that cannot become a safe configuration key' {
        $customRoot = Join-Path ([IO.Path]::GetTempPath()) ('azd-sysmon-key-' + [Guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $customRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $customRoot 'not safe.xml') -Value '<Sysmon><EventFiltering /></Sysmon>' -NoNewline
            { & $builderPath -CustomConfigurationFolder $customRoot -DefaultConfiguration workstation } | Should -Throw
        } finally {
            if (Test-Path -LiteralPath $customRoot) { Remove-Item -LiteralPath $customRoot -Recurse -Force }
        }
    }

    It 'rejects a vendored input whose hash differs from the manifest lock' {
        $testManifest = Join-Path ([IO.Path]::GetTempPath()) ('azd-sysmon-manifest-' + [Guid]::NewGuid().ToString('N') + '.json')
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest.configurationAssets.balanced.sha256 = '0' * 64
            $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $testManifest -NoNewline
            { & $builderPath -ManifestPath $testManifest -DefaultConfiguration balanced } | Should -Throw
        } finally {
            if (Test-Path -LiteralPath $testManifest) { Remove-Item -LiteralPath $testManifest -Force }
        }
    }
}

Describe 'Generated detection' {
    It 'requires both the expected state hash and untampered local configuration bytes' {
        $package = Get-Content -LiteralPath (Join-Path $templateRoot 'config\generated-package-manifest.json') -Raw | ConvertFrom-Json
        $key = [string]$package.defaultConfiguration
        $entry = $package.configurationFiles.PSObject.Properties[$key].Value
        $testRoot = Join-Path ([IO.Path]::GetTempPath()) ('azd-sysmon-detection-' + [Guid]::NewGuid().ToString('N'))
        try {
            $configRoot = Join-Path $testRoot 'configs'
            New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $templateRoot ('config\vendor\' + $entry.fileName)) -Destination (Join-Path $configRoot $entry.fileName)
            @{ configuration = $key; configurationFile = $entry.fileName; configurationSha256 = $entry.sha256 } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $testRoot 'state.json') -NoNewline
            $detection = Get-Content -LiteralPath (Join-Path $templateRoot 'deploy\intune\Detect-Sysmon.ps1') -Raw
            $detection = $detection.Replace('C:\ProgramData\AzdSysmon', $testRoot).Replace('exit 0', 'return 0').Replace('exit 1', 'return 1')
            function global:Get-Service { [pscustomobject]@{ Status = 'Running' } }
            function global:Get-WinEvent { [pscustomobject]@{ LogName = 'Microsoft-Windows-Sysmon/Operational' } }
            ((& ([scriptblock]::Create($detection))) -join "`n") | Should -Match 'healthy'
            Set-Content -LiteralPath (Join-Path $configRoot $entry.fileName) -Value 'tampered' -NoNewline
            ((& ([scriptblock]::Create($detection))) -join "`n") | Should -Match 'remediation is required'
        } finally {
            Remove-Item -Path function:global:Get-Service -ErrorAction SilentlyContinue
            Remove-Item -Path function:global:Get-WinEvent -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
        }
    }
}
