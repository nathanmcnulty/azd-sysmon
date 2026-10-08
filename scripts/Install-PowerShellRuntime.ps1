#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'

$version = '7.2.24'
$archiveName = "PowerShell-$version-win-x64.zip"
$archiveUri = "https://github.com/PowerShell/PowerShell/releases/download/v$version/$archiveName"
$expectedSha256 = 'A1CCB6D8AD52F917470A136C3752AF4465F261BCBE570CF44F52AA69AE6E867E'
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
if ($actualVersion -ne $version) {
    throw "PowerShell runtime version mismatch. Expected $version, got $actualVersion."
}

Write-Output $pwshPath
