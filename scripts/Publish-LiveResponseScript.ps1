#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ScriptPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'deploy\live-response\Install-Sysmon.ps1'),
    [string]$Description = 'Managed by azd-sysmon; Sysmon installer. Use RunScript with a configuration key from config/generated-package-manifest.json.',
    [string]$ExpectedTenantId = $env:AZURE_TENANT_ID,
    [string]$ExpectedAccount = $env:AZD_SYSMON_MDE_ACCOUNT,
    [switch]$AdoptExisting,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')][string]$EnvironmentName = 'default',
    [System.Net.Http.HttpClient]$HttpClient
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) { throw "Live Response script not found: $ScriptPath" }
if ((Get-Item -LiteralPath $ScriptPath).Length -gt 20MB) { throw 'The Live Response library upload exceeds the documented 20 MB API limit.' }
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI is required for its cached browser/WAM access token.' }
if ($ExpectedTenantId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    throw 'AZURE_TENANT_ID must contain the intended Microsoft Entra tenant GUID before publishing to the MDE library.'
}
if ($ExpectedAccount -notmatch '^[^@\s]+@[^@\s]+$') {
    throw 'AZD_SYSMON_MDE_ACCOUNT must contain the intended MDE administrator UPN before publishing to the library.'
}
$accountJson = (& az account show --query '{tenantId:tenantId,user:user.name}' --output json --only-show-errors) -join [Environment]::NewLine
if ($LASTEXITCODE -ne 0) { throw 'Azure CLI could not inspect the active account before MDE library publishing.' }
try {
    $account = $accountJson | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw "Azure CLI returned an unreadable account context: $($_.Exception.Message)"
}
if ([string]$account.tenantId -ine $ExpectedTenantId -or [string]$account.user -ine $ExpectedAccount) {
    throw "Azure CLI is signed into '$($account.user)' in tenant '$($account.tenantId)', not the explicitly selected MDE account and tenant."
}

# The Defender API endpoint is api.security.microsoft.com, but the current API
# still expects the token audience for its legacy resource registration.
$token = (& az account get-access-token --resource 'https://api.securitycenter.microsoft.com' --tenant $ExpectedTenantId --query accessToken --output tsv --only-show-errors).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Azure CLI could not obtain a Defender for Endpoint token. Use standard az login/browser authentication and ensure the signed-in identity has Library.Manage.'
}

$ownsHttpClient = $null -eq $HttpClient
$client = if ($ownsHttpClient) { [System.Net.Http.HttpClient]::new() } else { $HttpClient }
$client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token)
$fileStream = [System.IO.File]::OpenRead($ScriptPath)
$fileContent = [System.Net.Http.StreamContent]::new($fileStream)
$multipart = [System.Net.Http.MultipartFormDataContent]::new()
try {
    $fileName = [System.IO.Path]::GetFileName($ScriptPath)
    $libraryResponse = $client.GetAsync('https://api.security.microsoft.com/api/libraryfiles').GetAwaiter().GetResult()
    $libraryBody = $libraryResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if (-not $libraryResponse.IsSuccessStatusCode) {
        throw "Defender Live Response library query failed with $([int]$libraryResponse.StatusCode): $libraryBody"
    }
    try {
        $libraryFiles = @((ConvertFrom-Json -InputObject $libraryBody -ErrorAction Stop).value | Where-Object { $_.fileName -ieq $fileName })
    } catch {
        throw "Defender Live Response library query returned unreadable JSON: $($_.Exception.Message)"
    }
    if ($libraryFiles.Count -gt 1) { throw "More than one Live Response library file is named '$fileName'; resolve the collision before publishing." }
    if ($libraryFiles.Count -eq 1 -and -not $AdoptExisting -and [string]$libraryFiles[0].description -notmatch '(?i)managed by azd-sysmon') {
        throw "A Live Response library file named '$fileName' exists but is not marked as owned by azd-sysmon. Pass -AdoptExisting only after review."
    }
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('text/plain')
    $multipart.Add($fileContent, 'file', $fileName)
    $multipart.Add([System.Net.Http.StringContent]::new($Description), 'Description')
    $multipart.Add([System.Net.Http.StringContent]::new('true'), 'HasParameters')
    $multipart.Add([System.Net.Http.StringContent]::new('Configuration: one configuration key from config/generated-package-manifest.json.'), 'ParametersDescription')
    $multipart.Add([System.Net.Http.StringContent]::new([string]($libraryFiles.Count -eq 1)), 'OverrideIfExists')

    $response = $client.PostAsync('https://api.security.microsoft.com/api/libraryfiles', $multipart).GetAwaiter().GetResult()
    $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if (-not $response.IsSuccessStatusCode) {
        throw "Defender Live Response library upload failed with $([int]$response.StatusCode): $responseBody"
    }

    $responseFileId = $null
    if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
        try {
            $responseObject = $responseBody | ConvertFrom-Json -ErrorAction Stop
            $responseFileId = if ($responseObject.id) { [string]$responseObject.id } elseif ($responseObject.fileId) { [string]$responseObject.fileId } else { $null }
        } catch {
            # Some tenants return an empty or non-JSON success body. The
            # follow-up cleanup path can still identify the exact managed file
            # by filename and ownership description.
            $responseFileId = $null
        }
    }
    $fileId = if ($responseFileId) { $responseFileId } elseif ($libraryFiles.Count -eq 1) { [string]$libraryFiles[0].id } else { $null }
    $stateRoot = Join-Path (Split-Path -Parent $PSScriptRoot) (Join-Path '.azure' $EnvironmentName)
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    [ordered]@{
        template = 'azd-sysmon'
        objectType = 'defender-live-response-library-file'
        fileId = $fileId
        fileName = $fileName
        description = $Description
        tenantId = $ExpectedTenantId
        account = $ExpectedAccount
        environmentName = $EnvironmentName
        adoptedExisting = [bool]($libraryFiles.Count -eq 1 -and $AdoptExisting)
        status = 'published'
        recordedUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stateRoot 'azd-sysmon-live-response-state.json') -Encoding UTF8
    Write-Host "Published $fileName to the Defender Live Response library." -ForegroundColor Green
} finally {
    $multipart.Dispose()
    $fileContent.Dispose()
    $fileStream.Dispose()
    if ($ownsHttpClient) { $client.Dispose() }
}
