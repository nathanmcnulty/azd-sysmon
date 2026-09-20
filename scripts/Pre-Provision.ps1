#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$templateRoot = Split-Path -Parent $PSScriptRoot

function Get-AzdSetting {
    param([Parameter(Mandatory)][string]$Name)

    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value
    }

    if (Get-Command azd -ErrorAction SilentlyContinue) {
        $value = (& azd env get-value $Name 2>$null | Select-Object -Last 1)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($value) -and $value -ne 'null') {
            return ([string]$value).Trim()
        }
    }

    return $null
}

function Set-AzdSetting {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Value)

    if (-not (Get-Command azd -ErrorAction SilentlyContinue)) {
        throw "The azd command is required to persist $Name."
    }
    & azd env set $Name $Value | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "azd env set failed for $Name."
    }
    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

function ConvertTo-BooleanSetting {
    param([string]$Value)
    return $Value -match '^(?i:true|1|yes|y|on)$'
}

function Get-SafeName {
    param([string]$Value)
    $safe = ($Value -replace '[^A-Za-z0-9-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'default' }
    if ($safe.Length -gt 40) { $safe = $safe.Substring(0, 40).Trim('-') }
    return $safe.ToLowerInvariant()
}

$manifestPath = Join-Path $templateRoot 'config\sysmon-modular-release.json'
$packageManifestPath = Join-Path $templateRoot 'config\generated-package-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$packageManifest = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json

$configuration = Get-AzdSetting 'AZD_SYSMON_CONFIG'
if ([string]::IsNullOrWhiteSpace($configuration)) {
    $configuration = 'balanced'
    Set-AzdSetting 'AZD_SYSMON_CONFIG' $configuration
}
$configuration = $configuration.ToLowerInvariant()
$availableConfigurations = @($packageManifest.configurationKeys | ForEach-Object { ([string]$_).ToLowerInvariant() })
if ($availableConfigurations.Count -eq 0 -or $configuration -notin $availableConfigurations) {
    throw "AZD_SYSMON_CONFIG '$configuration' is not in the generated package. Available configurations: $($availableConfigurations -join ', '). Rebuild with the desired configuration source."
}
if ($packageManifest.defaultConfiguration -ne $configuration) {
    throw "The checked-in Intune package is built for '$($packageManifest.defaultConfiguration)' but AZD_SYSMON_CONFIG is '$configuration'. Rebuild with .\scripts\Build-SysmonPackages.ps1 -DefaultConfiguration $configuration and review the diff."
}

$environmentName = Get-AzdSetting 'AZURE_ENV_NAME'
if ([string]::IsNullOrWhiteSpace($environmentName)) { $environmentName = 'default' }
$dcrName = Get-AzdSetting 'AZD_SYSMON_DCR_NAME'
if ([string]::IsNullOrWhiteSpace($dcrName)) {
    $dcrName = "dcr-sysmon-$(Get-SafeName $environmentName)"
    Set-AzdSetting 'AZD_SYSMON_DCR_NAME' $dcrName
}
if ($dcrName -notmatch '^[A-Za-z0-9-]{1,64}$') {
    throw 'AZD_SYSMON_DCR_NAME must contain only letters, numbers, and hyphens and be 64 characters or fewer.'
}

$workspaceResourceId = Get-AzdSetting 'AZD_SYSMON_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID'
$promptForOptional = ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_PROMPT_FOR_OPTIONAL_SETTINGS')
if ($promptForOptional -and [string]::IsNullOrWhiteSpace($workspaceResourceId)) {
    $workspaceResourceId = Read-Host 'Optional existing Log Analytics workspace resource ID (press Enter to skip Sentinel integration)'
    if (-not [string]::IsNullOrWhiteSpace($workspaceResourceId)) {
        Set-AzdSetting 'AZD_SYSMON_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID' $workspaceResourceId.Trim()
    }
}
if (-not [string]::IsNullOrWhiteSpace($workspaceResourceId) -and $workspaceResourceId -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.OperationalInsights/workspaces/[^/]+$') {
    throw 'AZD_SYSMON_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID must be a full Log Analytics workspace resource ID.'
}

$vmResourceIds = @(Get-AzdSetting 'AZD_SYSMON_AZURE_VM_RESOURCE_IDS') -join ''
$vmIds = @()
if (-not [string]::IsNullOrWhiteSpace($vmResourceIds)) {
    $vmIds = @($vmResourceIds -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($vmId in $vmIds) {
        if ($vmId -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Compute/virtualMachines/[^/]+$') {
            throw "Invalid Azure VM resource ID: $vmId"
        }
    }
}

$deployIntune = ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_DEPLOY_INTUNE')
$deployAmaApplication = ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_DEPLOY_AMA_APPLICATION')
if ($deployAmaApplication) {
    $amaRelease = Get-Content -LiteralPath (Join-Path $templateRoot 'config/ama-client-release.json') -Raw | ConvertFrom-Json
    $amaPackagePath = Join-Path $templateRoot ".artifacts/ama/AzureMonitorAgentClientSetup-$($amaRelease.release).msi"
    if (-not (Test-Path -LiteralPath $amaPackagePath -PathType Leaf)) {
        throw 'Build the verified AMA MSI first with scripts/Build-AmaPackage.ps1 before enabling AZD_SYSMON_DEPLOY_AMA_APPLICATION.'
    }
}
$intuneGroupId = Get-AzdSetting 'AZD_SYSMON_INTUNE_GROUP_ID'
if ($deployIntune -or $deployAmaApplication) {
    if ([string]::IsNullOrWhiteSpace($intuneGroupId) -or $intuneGroupId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw 'Intune deployment requires AZD_SYSMON_INTUNE_GROUP_ID to be a Microsoft Entra group GUID.'
    }
    if ((Get-AzdSetting 'AZD_SYSMON_GRAPH_ACCOUNT') -notmatch '^[^@\s]+@[^@\s]+$') {
        throw 'Intune publishing requires AZD_SYSMON_GRAPH_ACCOUNT (the intended administrator UPN).'
    }
}

$tenantScope = ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_CLIENT_AMA_TENANT_SCOPE')
if ($tenantScope) {
    if ([string]::IsNullOrWhiteSpace($workspaceResourceId)) {
        throw 'AZD_SYSMON_CLIENT_AMA_TENANT_SCOPE=true requires AZD_SYSMON_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID.'
    }
    if ((Get-AzdSetting 'AZD_SYSMON_CONFIRM_TENANT_SCOPE') -ne 'I_UNDERSTAND_TENANT_WIDE_SCOPE') {
        throw 'Refusing tenant-wide client AMA association. Set AZD_SYSMON_CONFIRM_TENANT_SCOPE=I_UNDERSTAND_TENANT_WIDE_SCOPE after reviewing the documented blast radius.'
    }
}

$publishLiveResponse = ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_PUBLISH_LIVE_RESPONSE_LIBRARY')
if ($publishLiveResponse -and (Get-AzdSetting 'AZD_SYSMON_MDE_ACCOUNT') -notmatch '^[^@\s]+@[^@\s]+$') {
    throw 'MDE library publishing requires AZD_SYSMON_MDE_ACCOUNT (the intended administrator UPN).'
}

if ($vmIds.Count -gt 0 -or $deployIntune -or $deployAmaApplication -or $tenantScope -or $publishLiveResponse -or $workspaceResourceId) {
    $subscriptionId = Get-AzdSetting 'AZURE_SUBSCRIPTION_ID'
    if ($subscriptionId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw 'An explicit AZURE_SUBSCRIPTION_ID is required before enabling external deployment targets.'
    }
    $accountJson = & az account show --subscription $subscriptionId --output json --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Cannot verify the selected Azure subscription. Use normal az login to authenticate.' }
    $account = $accountJson | ConvertFrom-Json
    if ($account.environmentName -ne 'AzureCloud') { throw 'This template currently supports AzureCloud only.' }
    $tenantId = Get-AzdSetting 'AZURE_TENANT_ID'
    if ($tenantId -and $tenantId -ne $account.tenantId) { throw 'AZURE_TENANT_ID does not match the selected Azure subscription.' }
    Set-AzdSetting 'AZURE_TENANT_ID' ([string]$account.tenantId)
    foreach ($resourceId in @($workspaceResourceId) + $vmIds) {
        if ($resourceId -and ($resourceId -split '/')[2] -ne $subscriptionId) {
            throw 'Workspace and VM targets must belong to AZURE_SUBSCRIPTION_ID. Cross-subscription deployment is not supported.'
        }
    }
    Write-Host "Verified deployment tenant $($account.tenantId), subscription $subscriptionId."
}

Write-Host ''
Write-Host 'azd-sysmon pre-provision plan' -ForegroundColor Cyan
if ($packageManifest.configurationSource -eq 'custom-folder') {
    Write-Host '  Sysmon configuration source: custom folder (embedded package)'
} else {
    Write-Host "  Sysmon Modular release: $($manifest.releaseTag)"
}
Write-Host "  Configuration: $configuration"
Write-Host "  Sentinel/Log Analytics DCR: $(if ([string]::IsNullOrWhiteSpace($workspaceResourceId)) { 'SKIP (no workspace resource ID)' } else { 'CREATE/UPDATE optional DCR' })"
Write-Host "  Azure VM installation: $(if ($vmIds.Count -eq 0) { 'SKIP (no VM resource IDs)' } else { "$($vmIds.Count) VM(s)" })"
Write-Host "  Intune Remediation: $(if ($deployIntune) { "ENABLED for group $intuneGroupId" } else { 'SKIP' })"
Write-Host "  Intune AMA application: $(if ($deployAmaApplication) { "ENABLED for group $intuneGroupId" } else { 'SKIP' })"
Write-Host "  Client AMA tenant-wide scope: $(if ($tenantScope) { 'ENABLED (explicit confirmation present)' } else { 'SKIP' })"
Write-Host "  MDE Live Response library: $(if ($publishLiveResponse) { 'PUBLISH enabled' } else { 'SKIP; checked-in script remains available for manual upload' })"
Write-Host ''
Write-Host 'No optional external tenant/device target is selected unless its AZD_SYSMON_* setting is explicitly populated.' -ForegroundColor Yellow
