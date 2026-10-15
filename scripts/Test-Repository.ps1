#requires -Version 7.6
[CmdletBinding()]
param(
    [ValidateScript({
        if ($_ -lt [version]'6.2.0') { throw 'PesterVersion must be 6.2.0 or later.' }
        $true
    })]
    [version]$PesterVersion
)
$ErrorActionPreference = 'Stop'
if ($PSBoundParameters.ContainsKey('PesterVersion')) {
    Import-Module Pester -RequiredVersion $PesterVersion -ErrorAction Stop
} else {
    Import-Module Pester -MinimumVersion 6.2.0 -ErrorAction Stop
}
Write-Information "Selected PowerShell $($PSVersionTable.PSVersion); Pester $((Get-Module Pester).Version)." -InformationAction Continue
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $root 'tests/Test-Static.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Static validation failed.' }
& (Join-Path $root 'tests/Test-Package.ps1')
$result = Invoke-Pester -Path (Join-Path $root 'tests') -PassThru -Output Detailed
if ($null -eq $result -or $result.FailedCount -gt 0 -or $result.FailedContainersCount -gt 0 -or $result.TotalCount -eq 0 -or $result.SkippedCount -gt 0 -or $result.NotRunCount -gt 0) { throw 'Behavioral validation failed.' }
