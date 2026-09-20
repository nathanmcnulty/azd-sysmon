#requires -Version 7.2
[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$OutputDirectory,
    [string]$MsiPath
)

$ErrorActionPreference = 'Stop'
$templateRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path $templateRoot 'config\ama-client-release.json' }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $templateRoot '.artifacts\ama' }

function Assert-AmaMsi {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Release)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Azure Monitor Agent MSI was not found: $Path" }
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne ([string]$Release.sha256).ToLowerInvariant()) {
        throw "Azure Monitor Agent MSI SHA-256 mismatch. Expected $($Release.sha256), got $actualHash."
    }
    $signature = Get-AuthenticodeSignature -FilePath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch ([string]$Release.signerSubjectPattern)) {
        throw 'Azure Monitor Agent MSI does not have the expected valid Microsoft Authenticode signature.'
    }
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.OpenDatabase($Path, 0)
    foreach ($expected in @(
        @{ Name = 'ProductCode'; Value = [string]$Release.productCode },
        @{ Name = 'ProductVersion'; Value = [string]$Release.release },
        @{ Name = 'Manufacturer'; Value = [string]$Release.publisher }
    )) {
        $view = $database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = '$($expected.Name)'")
        $view.Execute() | Out-Null
        $record = $view.Fetch()
        $actual = if ($null -eq $record) { $null } else { [string]$record.StringData(1) }
        if ($actual -ne $expected.Value) { throw "Azure Monitor Agent MSI $($expected.Name) does not match the pinned release manifest." }
    }
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "AMA release manifest was not found: $ManifestPath" }
$release = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
foreach ($property in 'release', 'fileName', 'downloadUri', 'sha256', 'productCode', 'publisher', 'signerSubjectPattern') {
    if ([string]::IsNullOrWhiteSpace([string]$release.$property)) { throw "AMA release manifest is missing '$property'." }
}
if ([string]$release.downloadUri -notmatch '^https://download\.microsoft\.com/') { throw 'AMA release manifest must use a direct download.microsoft.com HTTPS URL.' }
if ([string]$release.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'AMA release manifest SHA-256 is invalid.' }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$destination = Join-Path $OutputDirectory ("AzureMonitorAgentClientSetup-$($release.release).msi")
if (-not [string]::IsNullOrWhiteSpace($MsiPath)) {
    Assert-AmaMsi -Path $MsiPath -Release $release
    Copy-Item -LiteralPath $MsiPath -Destination $destination -Force
} elseif (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
    $downloadPath = "$destination.download"
    try {
        Invoke-WebRequest -Uri $release.downloadUri -OutFile $downloadPath -ErrorAction Stop
        Assert-AmaMsi -Path $downloadPath -Release $release
        Move-Item -LiteralPath $downloadPath -Destination $destination -Force
    } finally {
        if (Test-Path -LiteralPath $downloadPath) { Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue }
    }
}
Assert-AmaMsi -Path $destination -Release $release
Write-Output "Validated Azure Monitor Agent $($release.release): $destination"
