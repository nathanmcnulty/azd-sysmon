#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$VmResourceIds
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required.' }

foreach ($vmId in $VmResourceIds) {
    if ($vmId -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Compute/virtualMachines/[^/]+$') {
        throw "Invalid Azure VM resource ID: $vmId"
    }
    Write-Host "Ensuring Azure Monitor Windows Agent is installed on $vmId"
    $arguments = @(
        'vm', 'extension', 'set',
        '--ids', $vmId,
        '--name', 'AzureMonitorWindowsAgent',
        '--publisher', 'Microsoft.Azure.Monitor',
        '--enable-auto-upgrade', 'true',
        '--only-show-errors',
        '--query', '{provisioningState:provisioningState,enableAutomaticUpgrade:enableAutomaticUpgrade}',
        '--output', 'json'
    )
    $extensionOutput = (& az @arguments) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0) { throw "Azure Monitor Agent extension installation failed for $vmId." }
    try {
        $extensionResult = $extensionOutput | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Azure Monitor Agent extension returned success but not a readable result for ${vmId}: $($_.Exception.Message)"
    }
    if ([string]$extensionResult.provisioningState -ine 'Succeeded' -or $extensionResult.enableAutomaticUpgrade -ne $true) {
        throw "Azure Monitor Agent extension was not ready on $vmId. Provisioning state: '$($extensionResult.provisioningState)'; automatic upgrade: '$($extensionResult.enableAutomaticUpgrade)'."
    }
}
