#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$StatePath,
    [string]$ExpectedAccount,
    [switch]$RemoveAdopted,
    [switch]$AllowContextReplacement
)

$ErrorActionPreference = 'Stop'
$state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
if ($state.template -ne 'azd-sysmon' -or $state.objectType -ne 'intune-windows-msi-application') {
    throw "The Intune AMA receipt '$StatePath' does not belong to azd-sysmon."
}
if ($state.status -eq 'removed') {
    Write-Host "Intune AMA application $($state.applicationId) is already recorded as removed." -ForegroundColor DarkGray
    return
}
if ([string]$state.status -notin @('created', 'assigned')) { throw "The Intune AMA receipt has unsupported status '$($state.status)'." }
foreach ($property in 'applicationId', 'groupId', 'tenantId', 'environmentName') {
    if ([string]::IsNullOrWhiteSpace([string]$state.$property)) { throw "The Intune AMA receipt is missing '$property'." }
}
if ([string]$state.applicationId -notmatch '^[0-9a-fA-F-]{20,}$' -or [string]$state.groupId -notmatch '^[0-9a-fA-F-]{36}$' -or [string]$state.tenantId -notmatch '^[0-9a-fA-F-]{36}$') {
    throw 'The Intune AMA receipt contains an invalid application, group, or tenant identifier.'
}
$account = if (-not [string]::IsNullOrWhiteSpace($ExpectedAccount)) { $ExpectedAccount } else { [string]$state.account }
if ([string]::IsNullOrWhiteSpace($account)) { throw 'The Intune AMA receipt has no administrator account. Set AZD_SYSMON_GRAPH_ACCOUNT before cleanup.' }
if ($account -notmatch '^[^@\s]+@[^@\s]+$') { throw 'The Intune AMA administrator account is not a valid UPN.' }
if ($state.account -and $ExpectedAccount -and [string]$state.account -ine $ExpectedAccount) { throw 'The requested Graph account does not match the account recorded for this Intune AMA application.' }
if ([bool]$state.adoptedExisting -and -not $RemoveAdopted) {
    Write-Warning "Preserving adopted Intune AMA application $($state.applicationId). Set AZD_SYSMON_REMOVE_ADOPTED_EXTERNAL_RESOURCES=true to remove it."
    return
}

Import-Module (Join-Path $PSScriptRoot 'vendor/Azd.GraphAuthentication/Azd.GraphAuthentication.psd1') -Force
Connect-AzdGraphSession -TenantId ([guid][string]$state.tenantId) -ExpectedAccount $account -Scopes @('DeviceManagementApps.ReadWrite.All') `
    -ProbeUri '/v1.0/deviceAppManagement/mobileApps?$top=1&$select=id' -AllowInteractive -AllowContextReplacement:$AllowContextReplacement | Out-Null

$baseUri = 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps'
$appUri = "$baseUri/$($state.applicationId)"
$marker = 'Managed by azd-sysmon. The package is an SHA-256-pinned Microsoft Azure Monitor Agent Windows client MSI.'
function Test-NotFound {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    $response = $ErrorRecord.Exception.PSObject.Properties['Response']
    if ($response -and $response.Value -and [int]$response.Value.StatusCode -eq 404) { return $true }
    $message = @(
        [string]$ErrorRecord.Exception.Message
        [string]$ErrorRecord.ErrorDetails
        [string]$ErrorRecord.ToString()
    ) -join "`n"
    return $message -match '(?i)(\b404\b|Request_ResourceNotFound|ResourceNotFound)'
}
function Get-GraphCollection {
    param([Parameter(Mandatory)][string]$Uri)
    $seen = [Collections.Generic.HashSet[string]]::new()
    while ($Uri) {
        $parsed = [Uri]$Uri
        if ($parsed.Scheme -ne 'https' -or $parsed.Host -ne 'graph.microsoft.com' -or -not $parsed.AbsolutePath.StartsWith('/v1.0/deviceManagement/mobileApps', [StringComparison]::Ordinal) -or -not $seen.Add($Uri)) {
            throw 'Graph returned an unexpected or repeated pagination URL.'
        }
        $page = Invoke-MgGraphRequest -Method GET -Uri $Uri
        foreach ($item in @($page.value)) { $item }
        $Uri = [string]$page.'@odata.nextLink'
    }
}
function Write-RemovedState {
    $state.status = 'removed'
    $state | Add-Member -MemberType NoteProperty -Name removedUtc -Value ([DateTime]::UtcNow.ToString('o')) -Force
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

$target = $null
try { $target = Invoke-MgGraphRequest -Method GET -Uri $appUri } catch {
    if (Test-NotFound $_) {
        Write-RemovedState
        Write-Host "Intune AMA application $($state.applicationId) was already absent." -ForegroundColor DarkGray
        return
    }
    throw
}
if ([string]$target.displayName -ne 'Azure Monitor Agent (azd-sysmon)' -or [string]$target.description -ne $marker -or
    ($target.'@odata.type' -and [string]$target.'@odata.type' -ne '#microsoft.graph.windowsMobileMSI')) {
    throw "Refusing to delete Intune AMA application $($state.applicationId): its ownership marker or type no longer matches azd-sysmon."
}
$assignments = @(Get-GraphCollection -Uri "$appUri/assignments?`$top=100")
foreach ($assignment in $assignments) {
    if ($assignment.target.'@odata.type' -ne '#microsoft.graph.groupAssignmentTarget' -or [string]$assignment.target.groupId -ne [string]$state.groupId -or $assignment.target.deviceAndAppManagementAssignmentFilterId) {
        throw "Refusing to delete Intune AMA application $($state.applicationId): its assignment no longer matches the recorded group."
    }
}
if ($assignments.Count -gt 1) { throw "Refusing to delete Intune AMA application $($state.applicationId): duplicate assignments require manual review." }

Invoke-MgGraphRequest -Method DELETE -Uri $appUri | Out-Null
Write-RemovedState
Write-Host "Removed Intune AMA application $($state.applicationId)." -ForegroundColor Green
