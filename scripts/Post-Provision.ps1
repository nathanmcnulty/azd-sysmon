#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$templateRoot = Split-Path -Parent $PSScriptRoot

function Get-AzdSetting {
    param([Parameter(Mandatory)][string]$Name)
    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    if (Get-Command azd -ErrorAction SilentlyContinue) {
        $value = (& azd env get-value $Name 2>$null | Select-Object -Last 1)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($value) -and $value -ne 'null') { return ([string]$value).Trim() }
    }
    return $null
}

function ConvertTo-BooleanSetting {
    param([string]$Value)
    return $Value -match '^(?i:true|1|yes|y|on)$'
}

function Invoke-AzureCli {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & az @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: az $($Arguments -join ' ')" }
}

function Get-EnvironmentStatePath {
    param([Parameter(Mandatory)][string]$EnvironmentName)

    if ($EnvironmentName -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') {
        throw "AZURE_ENV_NAME '$EnvironmentName' is not safe for a state-receipt path."
    }
    return Join-Path $templateRoot (Join-Path '.azure' (Join-Path $EnvironmentName 'azd-sysmon-state.json'))
}

$configuration = Get-AzdSetting 'AZD_SYSMON_CONFIG'
if ([string]::IsNullOrWhiteSpace($configuration)) { $configuration = 'balanced' }
$workspaceResourceId = Get-AzdSetting 'AZD_SYSMON_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID'
$dcrName = Get-AzdSetting 'AZD_SYSMON_DCR_NAME'
$resourceGroup = Get-AzdSetting 'AZURE_RESOURCE_GROUP'
if (-not [string]::IsNullOrWhiteSpace($workspaceResourceId) -and [string]::IsNullOrWhiteSpace($resourceGroup)) { throw 'AZURE_RESOURCE_GROUP was not available after azd provision.' }
$environmentName = Get-AzdSetting 'AZURE_ENV_NAME'
if ([string]::IsNullOrWhiteSpace($environmentName)) { $environmentName = 'default' }
$associationName = ('azd-sysmon-' + ($environmentName -replace '[^A-Za-z0-9-]', '-')).ToLowerInvariant()
$subscriptionId = Get-AzdSetting 'AZURE_SUBSCRIPTION_ID'
$tenantId = Get-AzdSetting 'AZURE_TENANT_ID'
$statePath = Get-EnvironmentStatePath $environmentName
$previousClientAmaAssociation = $false
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $previousState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($previousState.template -ne 'azd-sysmon' -or $previousState.environmentName -ne $environmentName) {
        throw "The existing state receipt at '$statePath' does not belong to this AZD environment."
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$previousState.azureSubscriptionId) -and -not [string]::IsNullOrWhiteSpace($subscriptionId) -and $previousState.azureSubscriptionId -ine $subscriptionId) {
        throw 'The existing state receipt belongs to a different Azure subscription. Resolve it before post-provision can continue.'
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$previousState.azureTenantId) -and -not [string]::IsNullOrWhiteSpace($tenantId) -and $previousState.azureTenantId -ine $tenantId) {
        throw 'The existing state receipt belongs to a different Microsoft Entra tenant. Resolve it before post-provision can continue.'
    }
    if ([string]::IsNullOrWhiteSpace($subscriptionId)) { $subscriptionId = [string]$previousState.azureSubscriptionId }
    if ([string]::IsNullOrWhiteSpace($tenantId)) { $tenantId = [string]$previousState.azureTenantId }
    $previousClientAmaAssociation = [bool]$previousState.clientAmaTenantScope -or [bool]$previousState.clientAmaAssociationAttempted
}

$dcrId = $null
if (-not [string]::IsNullOrWhiteSpace($workspaceResourceId)) {
    if ($subscriptionId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw 'AZURE_SUBSCRIPTION_ID must identify the AZD deployment subscription before post-provision actions run.'
    }
    $dcrId = (& az resource show --subscription $subscriptionId --resource-group $resourceGroup --resource-type 'Microsoft.Insights/dataCollectionRules' --name $dcrName --query id --output tsv --only-show-errors).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($dcrId)) {
        throw "The optional Sysmon DCR '$dcrName' was not found in resource group '$resourceGroup'."
    }
    Write-Host "Optional Sysmon DCR: $dcrId" -ForegroundColor Green
}

$state = [ordered]@{
    template = 'azd-sysmon'
    environmentName = $environmentName
    azureSubscriptionId = $subscriptionId
    azureTenantId = $tenantId
    configuration = $configuration
    dcrId = $dcrId
    dcrName = $dcrName
    associationName = $associationName
    vmResourceIds = @()
    vmSysmonAttempted = $false
    vmAmaInstalled = $false
    vmDcrAssociated = $false
    clientAmaTenantScope = $previousClientAmaAssociation
    clientAmaAssociationAttempted = $previousClientAmaAssociation
    intuneRemediation = $false
    intuneAmaApplication = $false
    liveResponseLibrary = $false
    recordedUtc = [DateTime]::UtcNow.ToString('o')
}
function Write-DeploymentState {
    $state.recordedUtc = [DateTime]::UtcNow.ToString('o')
    $stateDirectory = Split-Path -Parent $statePath
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
}

$vmSetting = Get-AzdSetting 'AZD_SYSMON_AZURE_VM_RESOURCE_IDS'
$vmIds = @()
if (-not [string]::IsNullOrWhiteSpace($vmSetting)) {
    $vmIds = @($vmSetting -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $state.vmResourceIds = $vmIds
    $state.vmSysmonAttempted = $true
    Write-DeploymentState
    & (Join-Path $PSScriptRoot 'Deploy-AzureVmSysmon.ps1') -VmResourceIds $vmIds -Configuration $configuration
    Write-DeploymentState
    if ($null -ne $dcrId) {
        & (Join-Path $PSScriptRoot 'Install-AzureVmAma.ps1') -VmResourceIds $vmIds
        $state.vmAmaInstalled = $true
        Write-DeploymentState
        & (Join-Path $PSScriptRoot 'Associate-AzureVmDcr.ps1') -VmResourceIds $vmIds -DcrId $dcrId -AssociationName $associationName
        $state.vmDcrAssociated = $true
        Write-DeploymentState
    } else {
        Write-Warning 'Azure VM Sysmon was installed, but no workspace was supplied, so no DCR association was created.'
    }
}

if (ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_CLIENT_AMA_TENANT_SCOPE')) {
    if ($null -eq $dcrId) { throw 'Client AMA tenant scope was enabled but the Sysmon DCR ID is unavailable.' }
    if ($tenantId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { throw 'AZURE_TENANT_ID must identify the intended tenant before client AMA scope is enabled.' }
    if ((Get-AzdSetting 'AZD_SYSMON_CONFIRM_TENANT_SCOPE') -ne 'I_UNDERSTAND_TENANT_WIDE_SCOPE') { throw 'Refusing tenant-wide client AMA association without the exact confirmation string.' }
    $location = Get-AzdSetting 'AZURE_LOCATION'
    $state.clientAmaAssociationAttempted = $true
    Write-DeploymentState
    & (Join-Path $PSScriptRoot 'Set-ClientAmaScope.ps1') -Action Ensure -DcrId $dcrId -DcrLocation $location -TenantId $tenantId -SubscriptionId $subscriptionId -AssociationName $associationName -ConfirmTenantWideScope
    $state.clientAmaTenantScope = $true
    Write-DeploymentState
}

if (ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_DEPLOY_AMA_APPLICATION')) {
    Write-DeploymentState
    & (Join-Path $PSScriptRoot 'Deploy-IntuneAmaApplication.ps1') -GroupId (Get-AzdSetting 'AZD_SYSMON_INTUNE_GROUP_ID') -TenantId $tenantId -ExpectedAccount (Get-AzdSetting 'AZD_SYSMON_GRAPH_ACCOUNT') -EnvironmentName $environmentName
    $state.intuneAmaApplication = $true
    Write-DeploymentState
}

if (ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_DEPLOY_INTUNE')) {
    Write-DeploymentState
    & (Join-Path $PSScriptRoot 'Deploy-IntuneRemediation.ps1') -GroupId (Get-AzdSetting 'AZD_SYSMON_INTUNE_GROUP_ID') -Configuration $configuration -TenantId $tenantId -ExpectedAccount (Get-AzdSetting 'AZD_SYSMON_GRAPH_ACCOUNT') -EnvironmentName $environmentName
    $state.intuneRemediation = $true
    Write-DeploymentState
}

if (ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_PUBLISH_LIVE_RESPONSE_LIBRARY')) {
    Write-DeploymentState
    & (Join-Path $PSScriptRoot 'Publish-LiveResponseScript.ps1') -ExpectedTenantId $tenantId -ExpectedAccount (Get-AzdSetting 'AZD_SYSMON_MDE_ACCOUNT') -EnvironmentName $environmentName
    $state.liveResponseLibrary = $true
    Write-DeploymentState
}

Write-DeploymentState

Write-Host ''
Write-Host 'Post-provision work completed.' -ForegroundColor Green
if ($null -ne $dcrId) {
    Write-Host 'Verify Event-table ingestion with:' -ForegroundColor Cyan
    Write-Host "  Event | where EventLog == 'Microsoft-Windows-Sysmon/Operational' | where Computer =~ '<target-device-name>'"
} else {
    Write-Host 'Sentinel integration was skipped because AZD_SYSMON_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID is empty.' -ForegroundColor Yellow
}
