#requires -Version 7.2
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $root 'tests/Test-Static.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Static validation failed.' }
& (Join-Path $root 'tests/Test-Package.ps1')
Import-Module Pester -MinimumVersion 5.7.1 -ErrorAction Stop
$result = Invoke-Pester -Path (Join-Path $root 'tests') -PassThru -Output Detailed
if ($result.FailedCount -gt 0 -or $result.TotalCount -eq 0) { throw 'Behavioral validation failed.' }
