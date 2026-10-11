#requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactRoot,
    [ValidateRange(1,168)][int]$MaximumReceiptAgeHours=24,
    [switch]$Plan
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$lock = Get-Content -LiteralPath (Join-Path $repositoryRoot 'azd-components.lock.json') -Raw | ConvertFrom-Json
$component = @($lock.components | Where-Object id -ceq 'deployment-validation')
if ($component.Count -ne 1 -or $component[0].version -cne '1.1.1' -or
    $component[0].sourceRevision -cne '49b21df0b222a35537b9b75e46f851cc7e514c73') { throw 'ValidationComponentBindingRejected' }
$expected = @{
    'scripts/vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psd1'='96f0773f9b2ebcb2e36cdbc894420fa898f10d99662edefd4a1782c29e9794f0'
    'scripts/vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psm1'='6ad1183fb38b1b11283f0ff08c0dbb9f84b0070355521dfa9ec70cba125c653d'
    'scripts/vendor/Azd.DeploymentValidation/deployment-validation.schema.json'='eeabd298edf86ef88f9143dfef3fbec995f20f7ef0d3c380ab832b7514e83c34'
}
if ($component[0].files.Count -ne 3 -or @($component[0].files.target | Sort-Object -Unique).Count -ne 3) {
    throw 'ValidationComponentBindingRejected'
}
foreach ($file in $component[0].files) {
    if (-not $expected.ContainsKey($file.target) -or $file.sha256 -cne $expected[$file.target] -or
        (Get-FileHash -LiteralPath (Join-Path $repositoryRoot $file.target)).Hash.ToLowerInvariant() -cne $expected[$file.target]) {
        throw 'ValidationComponentBindingRejected'
    }
}
Import-Module (Join-Path $PSScriptRoot 'vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psd1') -Force
Import-Module (Join-Path $PSScriptRoot 'Sysmon.ArtifactValidation.psm1') -Force
New-SysmonArtifactReport -ArtifactRoot $ArtifactRoot -RepositoryRoot $repositoryRoot -MaximumReceiptAgeHours $MaximumReceiptAgeHours -Plan:$Plan
