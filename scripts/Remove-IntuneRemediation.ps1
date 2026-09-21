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
if ($state.template -ne 'azd-sysmon' -or $state.objectType -ne 'intune-device-health-script') {
    throw "The Intune remediation receipt '$StatePath' does not belong to azd-sysmon."
}
if ($state.status -eq 'removed') {
    Write-Host "Intune Remediation $($state.scriptId) is already recorded as removed." -ForegroundColor DarkGray
    return
}
if ([string]$state.status -notin @('created', 'assigned')) { throw "The Intune remediation receipt has unsupported status '$($state.status)'." }
foreach ($property in 'scriptId', 'groupId', 'tenantId', 'environmentName') {
    if ([string]::IsNullOrWhiteSpace([string]$state.$property)) { throw "The Intune remediation receipt is missing '$property'." }
}
if ([string]$state.scriptId -notmatch '^[0-9a-fA-F-]{20,}$' -or [string]$state.groupId -notmatch '^[0-9a-fA-F-]{36}$' -or [string]$state.tenantId -notmatch '^[0-9a-fA-F-]{36}$') {
    throw 'The Intune remediation receipt contains an invalid object, group, or tenant identifier.'
}
$account = if (-not [string]::IsNullOrWhiteSpace($ExpectedAccount)) { $ExpectedAccount } else { [string]$state.account }
if ([string]::IsNullOrWhiteSpace($account)) { throw 'The Intune remediation receipt has no administrator account. Set AZD_SYSMON_GRAPH_ACCOUNT before cleanup.' }
if ($account -notmatch '^[^@\s]+@[^@\s]+$') { throw 'The Intune remediation administrator account is not a valid UPN.' }
if ($state.account -and $ExpectedAccount -and [string]$state.account -ine $ExpectedAccount) { throw 'The requested Graph account does not match the account recorded for this Intune remediation.' }
if ([bool]$state.adoptedExisting -and -not $RemoveAdopted) {
    Write-Warning "Preserving adopted Intune Remediation $($state.scriptId). Set AZD_SYSMON_REMOVE_ADOPTED_EXTERNAL_RESOURCES=true to remove it."
    return
}

Import-Module (Join-Path $PSScriptRoot 'vendor/Azd.GraphAuthentication/Azd.GraphAuthentication.psd1') -Force
Connect-AzdGraphSession -TenantId ([guid][string]$state.tenantId) -ExpectedAccount $account -Scopes @('DeviceManagementScripts.ReadWrite.All') `
    -ProbeUri '/beta/deviceManagement/deviceHealthScripts?$top=1&$select=id' -AllowInteractive -AllowContextReplacement:$AllowContextReplacement | Out-Null

$baseUri = 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'
$scriptUri = "$baseUri/$($state.scriptId)"
$marker = 'Managed by azd-sysmon; changing this object outside the template can be overwritten.'
function Test-NotFound {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    return $ErrorRecord.Exception.Message -match '(?i)(\b404\b|Request_ResourceNotFound|ResourceNotFound)'
}
function Get-GraphCollection {
    param([Parameter(Mandatory)][string]$Uri)
    $seen = [Collections.Generic.HashSet[string]]::new()
    while ($Uri) {
        if ($Uri -notmatch '^https://graph\.microsoft\.com/beta/deviceManagement/deviceHealthScripts(?:[/?]|$)' -or -not $seen.Add($Uri)) {
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
try { $target = Invoke-MgGraphRequest -Method GET -Uri $scriptUri } catch {
    if (Test-NotFound $_) {
        Write-RemovedState
        Write-Host "Intune Remediation $($state.scriptId) was already absent." -ForegroundColor DarkGray
        return
    }
    throw
}
if ([string]$target.displayName -ne 'AZD Sysmon Remediation' -or [string]$target.publisher -ne 'azd-sysmon' -or [string]$target.description -ne $marker) {
    throw "Refusing to delete Intune Remediation $($state.scriptId): its ownership marker no longer matches azd-sysmon."
}
$assignments = @(Get-GraphCollection -Uri "$scriptUri/assignments")
foreach ($assignment in $assignments) {
    if ($assignment.target.'@odata.type' -ne '#microsoft.graph.groupAssignmentTarget' -or [string]$assignment.target.groupId -ne [string]$state.groupId -or
        ($assignment.target.deviceAndAppManagementAssignmentFilterId -and $assignment.target.deviceAndAppManagementAssignmentFilterId -ne [guid]::Empty.ToString()) -or
        ($assignment.target.deviceAndAppManagementAssignmentFilterType -and $assignment.target.deviceAndAppManagementAssignmentFilterType -ne 'none')) {
        throw "Refusing to delete Intune Remediation $($state.scriptId): its assignment no longer matches the recorded group."
    }
}
if ($assignments.Count -gt 1) { throw "Refusing to delete Intune Remediation $($state.scriptId): duplicate assignments require manual review." }

Invoke-MgGraphRequest -Method DELETE -Uri $scriptUri | Out-Null
Write-RemovedState
Write-Host "Removed Intune Remediation $($state.scriptId)." -ForegroundColor Green
