#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$StatePath,
    [switch]$RemoveAdopted,
    [System.Net.Http.HttpClient]$HttpClient
)

$ErrorActionPreference = 'Stop'
$state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
if ($state.template -ne 'azd-sysmon' -or $state.objectType -ne 'defender-live-response-library-file') {
    throw "The Defender Live Response receipt '$StatePath' does not belong to azd-sysmon."
}
if ($state.status -eq 'removed') {
    Write-Host "Defender Live Response file $($state.fileName) is already recorded as removed." -ForegroundColor DarkGray
    return
}
if ([string]$state.status -ne 'published') { throw "The Defender Live Response receipt has unsupported status '$($state.status)'." }
foreach ($property in 'fileName', 'tenantId', 'environmentName') {
    if ([string]::IsNullOrWhiteSpace([string]$state.$property)) { throw "The Defender Live Response receipt is missing '$property'." }
}
if ([IO.Path]::GetFileName([string]$state.fileName) -ne [string]$state.fileName -or [string]$state.fileName -notmatch '^[A-Za-z0-9._ -]{1,128}$') {
    throw 'The Defender Live Response receipt contains an unsafe filename.'
}
if ([string]$state.tenantId -notmatch '^[0-9a-fA-F-]{36}$' -or [string]$state.account -notmatch '^[^@\s]+@[^@\s]+$') {
    throw 'The Defender Live Response receipt contains an invalid tenant or administrator account.'
}
if ([bool]$state.adoptedExisting -and -not $RemoveAdopted) {
    Write-Warning "Preserving adopted Defender Live Response file '$($state.fileName)'. Set AZD_SYSMON_REMOVE_ADOPTED_EXTERNAL_RESOURCES=true to remove it."
    return
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required for Defender Live Response cleanup.' }
$accountJson = (& az account show --query '{tenantId:tenantId,user:user.name}' --output json --only-show-errors) -join [Environment]::NewLine
if ($LASTEXITCODE -ne 0) { throw 'Azure CLI could not inspect the active account before Defender Live Response cleanup.' }
$account = $accountJson | ConvertFrom-Json
if ([string]$account.tenantId -ine [string]$state.tenantId -or [string]$account.user -ine [string]$state.account) {
    throw "Azure CLI is signed into '$($account.user)' in tenant '$($account.tenantId)', not the account recorded for this Defender Live Response file."
}
$token = (& az account get-access-token --resource 'https://api.securitycenter.microsoft.com' --tenant ([string]$state.tenantId) --query accessToken --output tsv --only-show-errors).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) { throw 'Azure CLI could not obtain a Defender for Endpoint token for cleanup.' }

$ownsHttpClient = $null -eq $HttpClient
$client = if ($ownsHttpClient) { [System.Net.Http.HttpClient]::new() } else { $HttpClient }
$client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token)
$markerPattern = '(?i)managed by azd-sysmon'
function Write-RemovedState {
    $state.status = 'removed'
    $state.removedUtc = [DateTime]::UtcNow.ToString('o')
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}
function Get-LibraryFiles {
    $response = $client.GetAsync('https://api.security.microsoft.com/api/libraryfiles').GetAwaiter().GetResult()
    $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if ([int]$response.StatusCode -eq 404) { return @() }
    if (-not $response.IsSuccessStatusCode) { throw "Defender Live Response library query failed with $([int]$response.StatusCode)." }
    try { return @((ConvertFrom-Json -InputObject $body -ErrorAction Stop).value) } catch { throw 'Defender Live Response library query returned unreadable JSON.' }
}

try {
    $matches = @(Get-LibraryFiles | Where-Object {
        [string]$_.fileName -ieq [string]$state.fileName -and [string]$_.description -match $markerPattern -and
        ([string]::IsNullOrWhiteSpace([string]$state.fileId) -or [string]$_.id -eq [string]$state.fileId)
    })
    if ($matches.Count -eq 0) {
        Write-RemovedState
        Write-Host "Defender Live Response file '$($state.fileName)' was already absent." -ForegroundColor DarkGray
        return
    }
    if ($matches.Count -gt 1) { throw "More than one owned Defender Live Response file matches '$($state.fileName)'; resolve the duplicate before cleanup." }
    $target = $matches[0]
    if ([string]::IsNullOrWhiteSpace([string]$target.id)) { throw "The owned Defender Live Response file '$($state.fileName)' has no deletion identifier." }
    $deleteResponse = $client.DeleteAsync("https://api.security.microsoft.com/api/libraryfiles/$([Uri]::EscapeDataString([string]$target.id))").GetAwaiter().GetResult()
    if (-not $deleteResponse.IsSuccessStatusCode -and [int]$deleteResponse.StatusCode -ne 404) {
        throw "Defender Live Response file deletion failed with $([int]$deleteResponse.StatusCode)."
    }
    Write-RemovedState
    Write-Host "Removed Defender Live Response file '$($state.fileName)'." -ForegroundColor Green
} finally {
    if ($ownsHttpClient) { $client.Dispose() }
}
