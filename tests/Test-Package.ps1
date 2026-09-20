#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$templateRoot = Split-Path -Parent $PSScriptRoot

function Assert-Condition {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)

    if (-not $Condition) { throw $Message }
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$builderPath = Join-Path $templateRoot 'scripts\Build-SysmonPackages.ps1'
$packageManifestPath = Join-Path $templateRoot 'config\generated-package-manifest.json'
$packageManifest = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json
$builderText = Get-Content -LiteralPath $builderPath -Raw

Assert-Condition ($builderText -notmatch 'Invoke-WebRequest') 'The package builder must use vendored configuration inputs without a build-time download.'
Assert-Condition ($packageManifest.configurationSource -eq 'olaf-sysmon-modular-release') 'The checked-in package must use the pinned Olaf catalog.'

foreach ($configurationKey in @($packageManifest.configurationKeys)) {
    $entry = $packageManifest.configurationFiles.PSObject.Properties[[string]$configurationKey].Value
    Assert-Condition ($null -ne $entry) "The package manifest is missing '$configurationKey'."
    $vendorPath = Join-Path $templateRoot ('config\vendor\' + [string]$entry.fileName)
    Assert-Condition (Test-Path -LiteralPath $vendorPath -PathType Leaf) "The vendored XML is missing: $vendorPath"
    Assert-Condition ((Get-Sha256 $vendorPath) -eq [string]$entry.sha256) "The vendored XML hash does not match '$configurationKey'."
}

foreach ($relativePath in $packageManifest.generatedFiles.PSObject.Properties.Name) {
    $path = Join-Path $templateRoot $relativePath.TrimStart('.', '\', '/')
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "Generated package file is missing: $relativePath"
    Assert-Condition ((Get-Sha256 $path) -eq [string]$packageManifest.generatedFiles.$relativePath) "Generated package hash does not match: $relativePath"
}

$remediationPath = Join-Path $templateRoot 'deploy\intune\Remediate-Sysmon.ps1'
$remediation = Get-Content -LiteralPath $remediationPath -Raw
$bundleMatch = [regex]::Match($remediation, '(?m)^\$configBundleBase64 = ''([A-Za-z0-9+/=]+)''$')
Assert-Condition $bundleMatch.Success 'The generated remediation script does not contain an embedded configuration bundle.'

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('azd-sysmon-package-test-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $bundlePath = Join-Path $testRoot 'configs.zip'
    $expandedPath = Join-Path $testRoot 'expanded'
    [IO.File]::WriteAllBytes($bundlePath, [Convert]::FromBase64String($bundleMatch.Groups[1].Value))
    Assert-Condition ((Get-Sha256 $bundlePath) -eq [string]$packageManifest.configBundleSha256) 'The embedded bundle hash does not match the package manifest.'
    Expand-Archive -LiteralPath $bundlePath -DestinationPath $expandedPath -Force

    foreach ($configurationKey in @($packageManifest.configurationKeys)) {
        $entry = $packageManifest.configurationFiles.PSObject.Properties[[string]$configurationKey].Value
        $embeddedPath = Join-Path $expandedPath ([string]$entry.fileName)
        Assert-Condition (Test-Path -LiteralPath $embeddedPath -PathType Leaf) "The embedded bundle is missing '$configurationKey'."
        Assert-Condition ((Get-Sha256 $embeddedPath) -eq [string]$entry.sha256) "The embedded bundle hash does not match '$configurationKey'."
    }
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

$defaultKey = [string]$packageManifest.defaultConfiguration
$defaultHash = [string]$packageManifest.configurationFiles.PSObject.Properties[$defaultKey].Value.sha256
$detectionPath = Join-Path $templateRoot 'deploy\intune\Detect-Sysmon.ps1'
$detection = Get-Content -LiteralPath $detectionPath -Raw
Assert-Condition ($remediation.Contains("'$defaultKey' = '$defaultHash'")) 'The remediation script must verify the selected embedded XML hash before applying it.'
Assert-Condition ($detection.Contains("`$desiredConfigurationSha256 = '$defaultHash'")) 'The detection script must require the selected configuration hash.'

Write-Output 'Package tests passed.'
