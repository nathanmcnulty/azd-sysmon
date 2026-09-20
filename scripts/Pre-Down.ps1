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

$environmentName = Get-AzdSetting 'AZURE_ENV_NAME'
if ([string]::IsNullOrWhiteSpace($environmentName)) { $environmentName = 'default' }
if ($environmentName -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') {
    throw "AZURE_ENV_NAME '$environmentName' is not safe for a state-receipt path."
}
$statePath = Join-Path $templateRoot (Join-Path '.azure' (Join-Path $environmentName 'azd-sysmon-state.json'))
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    Write-Host 'No azd-sysmon state receipt was found. azd down can continue; no external cleanup will be attempted.' -ForegroundColor Yellow
    exit 0
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if ($state.template -ne 'azd-sysmon' -or $state.environmentName -ne $environmentName) {
    throw "The state receipt at '$statePath' does not belong to the selected AZD environment."
}
Write-Host 'azd-sysmon cleanup boundary' -ForegroundColor Cyan
Write-Host '  azd down will remove resources owned by this AZD environment, including the optional DCR.'
Write-Host '  Intune Remediation objects, Intune AMA applications, and MDE Live Response library files are tenant-level external objects and are not removed automatically.'
Write-Host '  The monitored object is intentionally retained; only the owned association can be removed explicitly.'

$removeClientAma = ConvertTo-BooleanSetting (Get-AzdSetting 'AZD_SYSMON_REMOVE_CLIENT_AMA_ASSOCIATION')
$confirmed = (Get-AzdSetting 'AZD_SYSMON_CONFIRM_TENANT_SCOPE') -eq 'I_UNDERSTAND_TENANT_WIDE_SCOPE'
if (($state.clientAmaTenantScope -or $state.clientAmaAssociationAttempted) -and $removeClientAma -and $confirmed) {
    & (Join-Path $PSScriptRoot 'Set-ClientAmaScope.ps1') -Action Remove -AssociationName $state.associationName -TenantId $state.azureTenantId -SubscriptionId $state.azureSubscriptionId -ConfirmTenantWideScope
    $state.clientAmaTenantScope = $false
    $state.clientAmaAssociationAttempted = $false
    $state.recordedUtc = [DateTime]::UtcNow.ToString('o')
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
    Write-Host "Removed only the azd-sysmon DCR association '$($state.associationName)'." -ForegroundColor Green
} elseif ($state.clientAmaTenantScope -or $state.clientAmaAssociationAttempted) {
    Write-Warning "Client AMA tenant-scope association '$($state.associationName)' was retained. Set AZD_SYSMON_REMOVE_CLIENT_AMA_ASSOCIATION=true and AZD_SYSMON_CONFIRM_TENANT_SCOPE=I_UNDERSTAND_TENANT_WIDE_SCOPE to remove it before azd down."
}
