#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$templateRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

$manifestPath = Join-Path $templateRoot 'config\sysmon-modular-release.json'
$packageManifestPath = Join-Path $templateRoot 'config\generated-package-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$packageManifest = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json
Assert-Condition ($manifest.releaseTag -eq 'configs-082cba578667') 'Unexpected Sysmon Modular release tag.'
Assert-Condition ($manifest.commit -eq '082cba578667a5f57b44a8e64bc02548d2338859') 'Sysmon Modular release must record the full resolved upstream commit.'
Assert-Condition ($packageManifest.defaultConfiguration -eq 'balanced') 'Generated package default must be balanced.'
Assert-Condition ($packageManifest.configurationSource -eq 'olaf-sysmon-modular-release') 'The checked-in package must use the pinned Olaf configuration source.'
Assert-Condition (@($packageManifest.configurationKeys).Count -eq 4) 'Expected four packaged configuration choices.'
Assert-Condition (@($packageManifest.configurationKeys) -contains 'mde-augmented') 'The packaged configuration choices must include mde-augmented.'
$customReadmePath = Join-Path $templateRoot 'config\custom\README.md'
Assert-Condition (Test-Path -LiteralPath $customReadmePath -PathType Leaf) 'The custom configuration folder must be documented.'
$mdeAsset = $manifest.configurationAssets.'mde-augmented'
Assert-Condition ($mdeAsset.sourceCommit -match '^[0-9a-f]{40}$') 'The MDE-augmented configuration must be pinned to a full upstream commit.'
Assert-Condition ($mdeAsset.sourceUrl -match '^https://raw\.githubusercontent\.com/olafhartong/sysmon-modular/[0-9a-f]{40}/sysmonconfig-mde-augment\.xml$') 'The MDE-augmented configuration must use an immutable raw upstream URL.'
Assert-Condition ($mdeAsset.sha256 -match '^[0-9a-f]{64}$') 'The MDE-augmented configuration must have a SHA-256 pin.'
foreach ($configurationKey in 'balanced', 'filedelete', 'excludes-only') {
    $asset = $manifest.configurationAssets.$configurationKey
    Assert-Condition ($asset.sourceCommit -eq $manifest.commit) "The $configurationKey configuration must record the full release commit."
    Assert-Condition ($asset.sourceUrl -eq "https://github.com/olafhartong/sysmon-modular/releases/download/$($manifest.releaseTag)/$($asset.fileName)") "The $configurationKey configuration must record its exact release asset URL."
    Assert-Condition ($asset.sha256 -match '^[0-9a-f]{64}$') "The $configurationKey configuration must have a SHA-256 pin."
}

Get-ChildItem -LiteralPath $templateRoot -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' } | ForEach-Object {
    $tokens = $null
    $parseErrors = @()
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in $parseErrors) { $failures.Add("PowerShell parse error in $($_.FullName): $($parseError.Message)") }
}

$remediationPath = Join-Path $templateRoot 'deploy\intune\Remediate-Sysmon.ps1'
$detectionPath = Join-Path $templateRoot 'deploy\intune\Detect-Sysmon.ps1'
Assert-Condition ((Get-Item -LiteralPath $remediationPath).Length -lt 200KB) 'Intune remediation script must remain below 200 KB.'
Assert-Condition ((Get-Item -LiteralPath $detectionPath).Length -lt 200KB) 'Intune detection script must remain below 200 KB.'
foreach ($generatedFile in $packageManifest.generatedFiles.PSObject.Properties) {
    $generatedPath = Join-Path $templateRoot ([string]$generatedFile.Name -replace '^\.\\', '')
    Assert-Condition (Test-Path -LiteralPath $generatedPath -PathType Leaf) "Generated file is missing: $generatedPath"
    if (Test-Path -LiteralPath $generatedPath -PathType Leaf) {
        $actualHash = (Get-FileHash -LiteralPath $generatedPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-Condition ($actualHash -eq [string]$generatedFile.Value) "Generated file hash mismatch: $generatedPath"
    }
}
Assert-Condition ((Get-Content -LiteralPath $remediationPath -Raw) -match 'Microsoft-Windows-Sysmon/Operational') 'Installer must verify the Sysmon event channel.'
Assert-Condition ((Get-Content -LiteralPath $remediationPath -Raw) -match 'Expand-Archive') 'Installer must expand the embedded configuration bundle.'
Assert-Condition ((Get-Content -LiteralPath $remediationPath -Raw) -match 'Enable-WindowsOptionalFeature') 'Installer must enable the Windows Sysmon optional feature.'
Assert-Condition ((Get-Content -LiteralPath $remediationPath -Raw) -match '\& \$sysmonPath -accepteula -i \$configPath') 'Installer must call the built-in sysmon install command with the selected configuration.'
Assert-Condition ((Get-Content -LiteralPath $remediationPath -Raw) -match "'mde-augmented' = 'sysmonconfig-mde-augment\.xml'") 'Installer must include the MDE-augmented configuration mapping.'

$bicepPath = Join-Path $templateRoot 'infra\main.bicep'
$bicep = Get-Content -LiteralPath $bicepPath -Raw
Assert-Condition ($bicep -match 'windowsEventLogs') 'DCR must declare a windowsEventLogs data source.'
Assert-Condition ($bicep -match 'Microsoft-Event') 'DCR must use the Microsoft-Event stream.'
Assert-Condition ($bicep -match 'Microsoft-Windows-Sysmon/Operational') 'DCR must target the Sysmon Operational channel.'
Assert-Condition ($bicep -match 'workspaceResourceId') 'DCR must target the supplied Log Analytics workspace.'

$lock = Get-Content -LiteralPath (Join-Path $templateRoot 'azd-components.lock.json') -Raw | ConvertFrom-Json
foreach ($component in $lock.components) {
    Assert-Condition ($component.sourceRevision -match '^[a-f0-9]{40}$') "Component $($component.id) must pin an exact source revision."
    foreach ($file in $component.files) {
        $path = Join-Path $templateRoot $file.target
        Assert-Condition ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ieq $file.sha256) "Vendored component drift: $($file.target)"
    }
}
Assert-Condition (Test-Path (Join-Path $templateRoot 'LICENSE')) 'A project license is required.'

$forbidden = @('UseDeviceCode', '--use-device-code', 'DeviceCodeCredential')
$filesToScan = Get-ChildItem -LiteralPath $templateRoot -Recurse -Include '*.ps1', '*.psm1', '*.yaml', '*.bicep' |
    Where-Object { $_.FullName -ne $PSCommandPath -and $_.FullName -notmatch '[\\/]\.azure[\\/]' -and $_.FullName -notmatch '[\\/]\.artifacts[\\/]' }
$filesToScan | ForEach-Object {
    $content = Get-Content -LiteralPath $_.FullName -Raw
    foreach ($term in $forbidden) { Assert-Condition (-not $content.Contains($term)) "Forbidden device-code authentication marker '$term' found in $($_.FullName)." }
}

if (Get-Command az -ErrorAction SilentlyContinue) {
    $bicepOutput = & az bicep build --file $bicepPath --stdout 2>&1
    if ($LASTEXITCODE -ne 0) { $failures.Add("Bicep compilation failed: $($bicepOutput -join ' ')") }
} else { $failures.Add('Azure CLI with Bicep is required; compilation must not be silently skipped.') }

if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}
Write-Output 'azd-sysmon static validation passed.'
