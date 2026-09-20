#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$VmResourceIds,
    [Parameter(Mandatory)][string]$DcrId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]{1,64}$')][string]$AssociationName,
    [ValidateSet('Ensure', 'Remove')][string]$Action = 'Ensure'
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required.' }
if ($DcrId -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Insights/dataCollectionRules/[^/]+$') { throw 'DcrId must be a full data collection rule resource ID.' }

foreach ($vmId in $VmResourceIds) {
    if ($vmId -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Compute/virtualMachines/[^/]+$') {
        throw "Invalid Azure VM resource ID: $vmId"
    }
    $uri = "https://management.azure.com$vmId/providers/Microsoft.Insights/dataCollectionRuleAssociations/$AssociationName?api-version=2022-06-01"
    if ($Action -eq 'Ensure') {
        $body = @{ properties = @{ dataCollectionRuleId = $DcrId } } | ConvertTo-Json -Compress -Depth 4
        Write-Host "Associating Sysmon DCR to $vmId"
        & az rest --method put --url $uri --body $body --only-show-errors | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "DCR association failed for $vmId." }
    } else {
        Write-Host "Removing Sysmon DCR association from $vmId"
        & az rest --method delete --url $uri --only-show-errors | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "DCR association removal failed for $vmId." }
    }
}
