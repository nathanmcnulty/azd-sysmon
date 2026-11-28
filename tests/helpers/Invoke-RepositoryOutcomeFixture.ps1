#requires -Version 7.6
param(
    [Parameter(Mandatory)][string] $RepositoryRoot,
    [Parameter(Mandatory)][string] $FixtureRoot,
    [Parameter(Mandatory)][ValidateSet('pass', 'inconclusive')][string] $Case
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path (Join-Path $FixtureRoot 'scripts'), (Join-Path $FixtureRoot 'tests') | Out-Null
Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'scripts/Test-Repository.ps1') -Destination (Join-Path $FixtureRoot 'scripts/Test-Repository.ps1')
# Isolate the outcome boundary from package/static checks; the copied runner and Pester are real.
foreach ($name in 'Test-Static.ps1', 'Test-Package.ps1') {
    Set-Content -LiteralPath (Join-Path $FixtureRoot "tests/$name") -Value '$global:LASTEXITCODE = 0'
}
$env:SYSMON_OUTCOME_MARKER = Join-Path $FixtureRoot 'executed.txt'
$statement = if ($Case -eq 'pass') { '1 | Should -Be 1' } else { "Set-ItResult -Inconclusive -Because 'Controlled fixture'" }
$fixture = 'Describe ''Controlled suite'' { It ''executes'' { [IO.File]::WriteAllText($env:SYSMON_OUTCOME_MARKER, ''executed''); ' + $statement + ' } }'
Set-Content -LiteralPath (Join-Path $FixtureRoot 'tests/Fixture.Tests.ps1') -Value $fixture
$succeeded = $false
$failure = $null
try {
    & (Join-Path $FixtureRoot 'scripts/Test-Repository.ps1') -PesterVersion 6.2.0
    $succeeded = $true
}
catch { $failure = $_.Exception.Message }
[ordered]@{
    succeeded = $succeeded
    fixtureRan = Test-Path -LiteralPath $env:SYSMON_OUTCOME_MARKER
    failure = $failure
    pester = (Get-Module Pester).Version.ToString()
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $FixtureRoot 'receipt.json')
