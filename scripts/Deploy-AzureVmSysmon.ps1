#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$VmResourceIds,
    [string]$Configuration = 'balanced'
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required.' }
$templateRoot = Split-Path -Parent $PSScriptRoot
$packageManifestPath = Join-Path $templateRoot 'config\generated-package-manifest.json'
$packageManifest = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json
$availableConfigurations = @($packageManifest.configurationKeys | ForEach-Object { ([string]$_).ToLowerInvariant() })
$Configuration = $Configuration.ToLowerInvariant()
if ($Configuration -notin $availableConfigurations) {
    throw "Configuration '$Configuration' is not in the generated package. Available configurations: $($availableConfigurations -join ', '). Rebuild the package or choose an available configuration."
}
$installerPath = Join-Path $templateRoot 'deploy\azure-vm\Install-Sysmon.ps1'
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) { throw "Generated Azure VM installer not found: $installerPath" }

foreach ($vmId in $VmResourceIds) {
    if ($vmId -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Compute/virtualMachines/[^/]+$') {
        throw "Invalid Azure VM resource ID: $vmId"
    }
    Write-Host "Installing Sysmon on $vmId with '$Configuration'."
    $arguments = @(
        'vm', 'run-command', 'invoke',
        '--ids', $vmId,
        '--command-id', 'RunPowerShellScript',
        '--scripts', "@$installerPath",
        '--parameters', "Configuration=$Configuration",
        '--only-show-errors',
        '--output', 'json'
    )
    $runCommandOutput = (& az @arguments) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0) { throw "Azure VM Run Command failed for $vmId." }

    try {
        $runCommandResult = $runCommandOutput | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Azure VM Run Command returned success but not a readable guest result for ${vmId}: $($_.Exception.Message)"
    }
    $guestStatuses = @($runCommandResult.value)
    if ($guestStatuses.Count -eq 0) {
        throw "Azure VM Run Command returned no guest status for $vmId."
    }
    $failedStatuses = @($guestStatuses | Where-Object {
        ([string]$_.code -match '(?i)(failed|error)') -or
        ([string]$_.level -match '^(?i:error)$') -or
        ([string]$_.displayStatus -match '(?i)(failed|error)')
    })
    if ($failedStatuses.Count -gt 0) {
        $details = ($failedStatuses | ForEach-Object { [string]$_.message } | Where-Object { $_ } | Select-Object -First 3) -join [Environment]::NewLine
        throw "Azure VM Run Command guest execution failed for $vmId. $details"
    }
    $stderrDetails = @($guestStatuses | Where-Object {
        ([string]$_.code -match '^ComponentStatus/StdErr/') -and -not [string]::IsNullOrWhiteSpace([string]$_.message)
    } | ForEach-Object { [string]$_.message })
    if ($stderrDetails.Count -gt 0) {
        $stderrSummary = ($stderrDetails | Select-Object -First 3) -join [Environment]::NewLine
        throw "Azure VM Run Command guest stderr was not empty for $vmId. $stderrSummary"
    }
    $stdoutStatuses = @($guestStatuses | Where-Object { [string]$_.code -match '^ComponentStatus/StdOut/succeeded$' })
    if ($stdoutStatuses.Count -eq 0) {
        throw "Azure VM Run Command did not report a successful guest stdout status for $vmId."
    }
    $installerSucceeded = @($stdoutStatuses | Where-Object {
        [string]$_.message -match '(?s)\[azd-sysmon\] Sysmon is installed and .+ is available\.'
    })
    if ($installerSucceeded.Count -eq 0) {
        throw "Azure VM Run Command did not report the Sysmon installer success marker for $vmId."
    }
}
