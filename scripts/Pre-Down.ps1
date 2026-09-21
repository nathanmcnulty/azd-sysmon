#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$templateRoot = Split-Path -Parent $PSScriptRoot

function ConvertTo-BooleanSetting {
    param([string]$Value)
    return $Value -match '^(?i:true|1|yes|y|on)$'
}

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

function Get-StatePath {
    param([Parameter(Mandatory)][string]$Name)
    return Join-Path $stateRoot $Name
}

function Read-Receipt {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $receipt = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($receipt.template -ne 'azd-sysmon' -or $receipt.environmentName -ne $environmentName) {
        throw "The state receipt at '$Path' does not belong to the selected AZD environment."
    }
    return $receipt
}

function Invoke-CleanupHelper {
    param(
        [Parameter(Mandatory)][string]$ScriptName,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [switch]$RemoveAdopted
    )

    $helperPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw "Cleanup helper is missing: $helperPath" }
    if ($RemoveAdopted) {
        & $helperPath -StatePath $ReceiptPath -RemoveAdopted
    } else {
        & $helperPath -StatePath $ReceiptPath
    }
}

$environmentName = Get-AzdSetting 'AZURE_ENV_NAME'
if ([string]::IsNullOrWhiteSpace($environmentName)) { $environmentName = 'default' }
if ($environmentName -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') {
    throw "AZURE_ENV_NAME '$environmentName' is not safe for a state-receipt path."
}
$stateRoot = Join-Path $templateRoot (Join-Path '.azure' $environmentName)
$statePath = Get-StatePath 'azd-sysmon-state.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    Write-Host 'No azd-sysmon state receipt was found. azd down can continue; no external cleanup will be attempted.' -ForegroundColor Yellow
    exit 0
}

$state = Read-Receipt -Path $statePath
Write-Host 'azd-sysmon cleanup boundary' -ForegroundColor Cyan
Write-Host '  azd down removes the AZD resource group, including the optional Sysmon DCR.'
Write-Host '  Receipt-bound Intune objects, Defender Live Response files, and Azure VM DCR associations are removed here.'
Write-Host '  The tenant monitored object is retained; its named association still requires the exact tenant-wide confirmation.'

$preserveExternal = ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_PRESERVE_EXTERNAL_RESOURCES')
$removeAdopted = ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_REMOVE_ADOPTED_EXTERNAL_RESOURCES')
if ($preserveExternal) {
    Write-Warning 'AZD_SYSMON_PRESERVE_EXTERNAL_RESOURCES is enabled. Receipt-bound Intune, Defender, and client AMA objects will be retained. The VM association to the AZD-owned DCR is still removed to avoid leaving a dangling reference after the resource group is deleted.'
} else {
    $intuneReceiptPath = Get-StatePath 'azd-sysmon-intune-state.json'
    if (Test-Path -LiteralPath $intuneReceiptPath -PathType Leaf) {
        Invoke-CleanupHelper -ScriptName 'Remove-IntuneRemediation.ps1' -ReceiptPath $intuneReceiptPath -RemoveAdopted:$removeAdopted
        if ((Read-Receipt -Path $intuneReceiptPath).status -eq 'removed') { $state.intuneRemediation = $false }
    } elseif ($state.intuneRemediation) {
        throw 'The deployment receipt says an Intune Remediation was attempted, but its object receipt is missing; refusing to delete the AZD resource group.'
    }

    $amaReceiptPath = Get-StatePath 'azd-sysmon-ama-application-state.json'
    if (Test-Path -LiteralPath $amaReceiptPath -PathType Leaf) {
        Invoke-CleanupHelper -ScriptName 'Remove-IntuneAmaApplication.ps1' -ReceiptPath $amaReceiptPath -RemoveAdopted:$removeAdopted
        if ((Read-Receipt -Path $amaReceiptPath).status -eq 'removed') { $state.intuneAmaApplication = $false }
    } elseif ($state.intuneAmaApplication) {
        throw 'The deployment receipt says an Intune AMA application was attempted, but its object receipt is missing; refusing to delete the AZD resource group.'
    }

    $liveReceiptPath = Get-StatePath 'azd-sysmon-live-response-state.json'
    if (Test-Path -LiteralPath $liveReceiptPath -PathType Leaf) {
        Invoke-CleanupHelper -ScriptName 'Remove-LiveResponseScript.ps1' -ReceiptPath $liveReceiptPath -RemoveAdopted:$removeAdopted
        if ((Read-Receipt -Path $liveReceiptPath).status -eq 'removed') { $state.liveResponseLibrary = $false }
    } elseif ($state.liveResponseLibrary) {
        throw 'The deployment receipt says a Live Response file was published, but its object receipt is missing; refusing to delete the AZD resource group.'
    }

}

$vmResourceIds = @($state.vmResourceIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
if ($state.vmDcrAssociated) {
    if ($vmResourceIds.Count -eq 0) {
        throw 'The deployment receipt says a VM DCR association exists, but it records no VM resource IDs; refusing to guess during cleanup.'
    }
    if ([string]$state.dcrId -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Insights/dataCollectionRules/[^/]+$') {
        throw 'The recorded VM DCR association has no valid DCR resource ID; refusing to guess during cleanup.'
    }
    if ([string]$state.associationName -notmatch '^[A-Za-z0-9-]{1,64}$') { throw 'The recorded VM DCR association name is invalid.' }
    $accountJson = (& az account show --query '{tenantId:tenantId,id:id}' --output json --only-show-errors) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI could not inspect the active account before VM DCR cleanup.' }
    $account = $accountJson | ConvertFrom-Json
    if ([string]$account.id -ine [string]$state.azureSubscriptionId -or [string]$account.tenantId -ine [string]$state.azureTenantId) {
        throw 'Azure CLI is signed into a different subscription or tenant than the recorded azd-sysmon VM deployment.'
    }
    & (Join-Path $PSScriptRoot 'Associate-AzureVmDcr.ps1') -VmResourceIds $vmResourceIds -DcrId ([string]$state.dcrId) -AssociationName ([string]$state.associationName) -Action Remove
    $state.vmDcrAssociated = $false
}

$removeClientAma = ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_REMOVE_CLIENT_AMA_ASSOCIATION')
$confirmed = (Get-AzdSetting 'AZD_SYSMON_CONFIRM_TENANT_SCOPE') -eq 'I_UNDERSTAND_TENANT_WIDE_SCOPE'
if (-not $preserveExternal -and ($state.clientAmaTenantScope -or $state.clientAmaAssociationAttempted) -and $removeClientAma -and $confirmed) {
    & (Join-Path $PSScriptRoot 'Set-ClientAmaScope.ps1') -Action Remove -AssociationName $state.associationName -TenantId $state.azureTenantId -SubscriptionId $state.azureSubscriptionId -ConfirmTenantWideScope
    $state.clientAmaTenantScope = $false
    $state.clientAmaAssociationAttempted = $false
    Write-Host "Removed only the azd-sysmon client AMA DCR association '$($state.associationName)'." -ForegroundColor Green
} elseif (-not $preserveExternal -and ($state.clientAmaTenantScope -or $state.clientAmaAssociationAttempted)) {
    Write-Warning "Client AMA tenant-scope association '$($state.associationName)' was retained. Set AZD_SYSMON_REMOVE_CLIENT_AMA_ASSOCIATION=true and AZD_SYSMON_CONFIRM_TENANT_SCOPE=I_UNDERSTAND_TENANT_WIDE_SCOPE to remove it before azd down."
} elseif ($preserveExternal -and ($state.clientAmaTenantScope -or $state.clientAmaAssociationAttempted)) {
    Write-Warning "Client AMA tenant-scope association '$($state.associationName)' was retained because AZD_SYSMON_PRESERVE_EXTERNAL_RESOURCES is enabled."
}

$state | Add-Member -MemberType NoteProperty -Name recordedUtc -Value ([DateTime]::UtcNow.ToString('o')) -Force
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
