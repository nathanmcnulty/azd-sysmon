#requires -Version 7.2
# Bootstrap only: verify and select the pinned runtime before any repository work.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'

$version = '7.6.6'
$archiveName = "PowerShell-$version-win-x64.zip"
$archiveUri = "https://github.com/PowerShell/PowerShell/releases/download/v$version/$archiveName"
$expectedSha256 = '02FE458BE20493FBDF43F61EA20610B811EE6C738AB1676C61B9CFCD1A33C860'
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$archivePath = Join-Path $outputRoot $archiveName
$extractRoot = Join-Path $outputRoot ('runtime-' + [Guid]::NewGuid().ToString('N'))
$pwshPath = Join-Path $extractRoot 'pwsh.exe'

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    Invoke-WebRequest -Uri $archiveUri -OutFile $archivePath
}

$actualSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($actualSha256 -ne $expectedSha256) {
    throw "PowerShell $version archive hash mismatch. Expected $expectedSha256, got $actualSha256."
}

New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force

if (-not (Test-Path -LiteralPath $pwshPath -PathType Leaf)) {
    throw "PowerShell runtime was not extracted to '$pwshPath'."
}

$actualVersion = (& $pwshPath -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()').Trim()
if ($LASTEXITCODE -ne 0 -or $actualVersion -ne $version) {
    throw "PowerShell runtime version mismatch. Expected $version, got $actualVersion."
}

Write-Information "Selected PowerShell $actualVersion from the SHA-256-verified portable archive." -InformationAction Continue
Write-Output $pwshPath
