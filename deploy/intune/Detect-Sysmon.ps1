#requires -Version 5.1
$ErrorActionPreference = 'SilentlyContinue'
$desiredConfiguration = 'balanced'
$desiredConfigurationSha256 = 'f115aac5770dae468e5cfb48c58a8b6e37588208a31f1b746812c534577a244b'
$desiredConfigurationFile = 'sysmonconfig.xml'
$installRoot = 'C:\ProgramData\AzdSysmon'
$statePath = Join-Path $installRoot 'state.json'
$service = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue
if ($null -eq $service) {
    $service = Get-Service -Name 'Sysmon' -ErrorAction SilentlyContinue
}
$state = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $state = $null }
}
$eventLog = Get-WinEvent -ListLog 'Microsoft-Windows-Sysmon/Operational' -ErrorAction SilentlyContinue
$configurationPath = Join-Path (Join-Path $installRoot 'configs') $desiredConfigurationFile
$configurationHash = if (Test-Path -LiteralPath $configurationPath -PathType Leaf) { (Get-FileHash -LiteralPath $configurationPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
if ($null -ne $service -and $service.Status -eq 'Running' -and $null -ne $eventLog -and $null -ne $state -and $state.configuration -eq $desiredConfiguration -and $state.configurationFile -eq $desiredConfigurationFile -and $state.configurationSha256 -eq $desiredConfigurationSha256 -and $configurationHash -eq $desiredConfigurationSha256) {
    Write-Output "Sysmon is healthy with the '$desiredConfiguration' configuration."
    exit 0
}
Write-Output "Sysmon remediation is required for the '$desiredConfiguration' configuration."
exit 1