#requires -Version 7.6
[CmdletBinding()]
param([switch]$Run, [string]$TenantId, [string]$SubscriptionId, [string]$ExpectedPrincipalId, [string]$ReportPath)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Sysmon.ApiSmoke.psm1') -Force
$report = Invoke-SysmonApiSmoke -Run:$Run -TenantId $TenantId -SubscriptionId $SubscriptionId -ExpectedPrincipalId $ExpectedPrincipalId
$json = $report | ConvertTo-Json -Depth 8
if ($ReportPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), $json, [Text.UTF8Encoding]::new($false)) }
$json
if ($Run -and -not $report.passed) { throw 'One or more read-only service probes were inconclusive or failed. See the redacted report.' }
