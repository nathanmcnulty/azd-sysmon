#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')][string]$GroupId,
    [string]$MsiPath,
    [string]$ManifestPath,
    [switch]$AdoptExisting,
    [string]$ExpectedAccount = $env:AZD_SYSMON_GRAPH_ACCOUNT,
    [string]$TenantId = $env:AZURE_TENANT_ID,
    [switch]$AllowContextReplacement,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')][string]$EnvironmentName = 'default',
    [ValidateRange(1, 30)][int]$MaxPollAttempts = 16,
    [ValidateRange(0, 30)][int]$PollSeconds = 10
)

$ErrorActionPreference = 'Stop'
$templateRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ManifestPath)) { $ManifestPath = Join-Path $templateRoot 'config\ama-client-release.json' }
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "AMA release manifest was not found: $ManifestPath" }
$release = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
foreach ($property in 'release', 'fileName', 'sha256', 'productCode', 'publisher', 'signerSubjectPattern') {
    if ([string]::IsNullOrWhiteSpace([string]$release.$property)) { throw "AMA release manifest is missing '$property'." }
}
if ([string]::IsNullOrWhiteSpace($MsiPath)) { $MsiPath = Join-Path $templateRoot ".artifacts\ama\AzureMonitorAgentClientSetup-$($release.release).msi" }
if (-not (Test-Path -LiteralPath $MsiPath -PathType Leaf)) { throw "Azure Monitor Agent package is missing: $MsiPath. Run scripts\Build-AmaPackage.ps1 first." }
$actualHash = (Get-FileHash -LiteralPath $MsiPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne ([string]$release.sha256).ToLowerInvariant()) { throw 'Azure Monitor Agent package hash does not match the pinned release manifest.' }
$signature = Get-AuthenticodeSignature -FilePath $MsiPath
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch ([string]$release.signerSubjectPattern)) { throw 'Azure Monitor Agent package does not have the expected valid Microsoft Authenticode signature.' }
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.OpenDatabase($MsiPath, 0)
foreach ($expected in @(
    @{ Name = 'ProductCode'; Value = [string]$release.productCode },
    @{ Name = 'ProductVersion'; Value = [string]$release.release },
    @{ Name = 'Manufacturer'; Value = [string]$release.publisher }
)) {
    $view = $database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = '$($expected.Name)'")
    $view.Execute() | Out-Null
    $record = $view.Fetch()
    $actual = if ($null -eq $record) { $null } else { [string]$record.StringData(1) }
    if ($actual -ne $expected.Value) { throw "Azure Monitor Agent MSI $($expected.Name) does not match the pinned release manifest." }
}
$upgradeView = $database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = 'UpgradeCode'")
$upgradeView.Execute() | Out-Null
$upgradeRecord = $upgradeView.Fetch()
$msiUpgradeCode = if ($null -eq $upgradeRecord) { $null } else { [string]$upgradeRecord.StringData(1) }
if ($msiUpgradeCode -notmatch '^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$') { throw 'Azure Monitor Agent MSI UpgradeCode is missing or invalid.' }

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) { throw 'Microsoft.Graph.Authentication is required. Install it with Install-Module Microsoft.Graph.Authentication -Scope CurrentUser.' }
if ([string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($ExpectedAccount)) { throw 'Set AZURE_TENANT_ID and AZD_SYSMON_GRAPH_ACCOUNT to the intended tenant GUID and administrator UPN before Intune publishing.' }
Import-Module (Join-Path $PSScriptRoot 'vendor/Azd.GraphAuthentication/Azd.GraphAuthentication.psd1') -Force
$requiredScopes = @('DeviceManagementApps.ReadWrite.All')
Connect-AzdGraphSession -TenantId $TenantId -ExpectedAccount $ExpectedAccount -Scopes $requiredScopes -ProbeUri '/v1.0/deviceAppManagement/mobileApps?$top=1&$select=id' -AllowInteractive -AllowContextReplacement:$AllowContextReplacement | Out-Null

$graphRoot = 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps'
$headers = @{ 'Content-Type' = 'application/json' }
$displayName = 'Azure Monitor Agent (azd-sysmon)'
$marker = 'Managed by azd-sysmon. The package is an SHA-256-pinned Microsoft Azure Monitor Agent Windows client MSI.'

function Get-GraphCollection {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$ExpectedPath)
    $seen = [Collections.Generic.HashSet[string]]::new()
    while ($Uri) {
        $parsed = [Uri]$Uri
        if ($parsed.Scheme -ne 'https' -or $parsed.Host -ne 'graph.microsoft.com' -or -not $parsed.AbsolutePath.StartsWith($ExpectedPath, [StringComparison]::Ordinal) -or -not $seen.Add($Uri)) {
            throw 'Graph returned an unexpected or repeated pagination URL.'
        }
        $page = Invoke-MgGraphRequest -Method GET -Uri $Uri
        foreach ($item in @($page.value)) { $item }
        $Uri = [string]$page.'@odata.nextLink'
    }
}

function Wait-ForFileState {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][ValidateSet('azureStorageUriRequest', 'azureStorageUriRenewal', 'commitFile')][string]$Stage)
    $success = "$Stage`Success"
    $pending = "$Stage`Pending"
    for ($attempt = 1; $attempt -le $MaxPollAttempts; $attempt++) {
        $file = Invoke-MgGraphRequest -Method GET -Uri $Uri
        if ([string]$file.uploadState -eq $success) { return $file }
        if ([string]$file.uploadState -ne $pending) { throw "Intune file processing failed during ${Stage}: $($file.uploadState)." }
        if ($attempt -lt $MaxPollAttempts) { Start-Sleep -Seconds $PollSeconds }
    }
    throw "Intune file processing timed out during $Stage after $MaxPollAttempts attempts."
}

function Get-IntuneUploadUri {
    param([Parameter(Mandatory)][string]$FileUri)
    $file = Invoke-MgGraphRequest -Method GET -Uri $FileUri
    $expiresAt = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$file.azureStorageUriExpirationDateTime)) {
        try { $expiresAt = [DateTimeOffset]::Parse([string]$file.azureStorageUriExpirationDateTime) } catch { $expiresAt = $null }
    }
    if ($expiresAt -and $expiresAt -le [DateTimeOffset]::UtcNow.AddMinutes(2)) {
        Invoke-MgGraphRequest -Method POST -Uri "$FileUri/renewUpload" -Headers $headers -Body '{}' | Out-Null
        $file = Wait-ForFileState -Uri $FileUri -Stage azureStorageUriRenewal
    } elseif ([string]$file.uploadState -eq 'azureStorageUriRenewalSuccess') {
        # A prior renewal completed; the individual file response carries its replacement URI.
    } else {
        $file = Wait-ForFileState -Uri $FileUri -Stage azureStorageUriRequest
    }
    if ([string]::IsNullOrWhiteSpace([string]$file.azureStorageUri)) { throw 'Intune did not return an active upload URI for the content file.' }
    return $file
}

function Wait-ForAppPublished {
    param([Parameter(Mandatory)][string]$ApplicationId)
    for ($attempt = 1; $attempt -le $MaxPollAttempts; $attempt++) {
        $application = Invoke-MgGraphRequest -Method GET -Uri "$graphRoot/$ApplicationId"
        if ([string]$application.publishingState -eq 'published') { return }
        if ([string]$application.publishingState -notin @('processing', 'notPublished')) {
            throw "Intune application publishing failed: $($application.publishingState)."
        }
        if ($attempt -lt $MaxPollAttempts) { Start-Sleep -Seconds $PollSeconds }
    }
    throw "Intune application publishing timed out after $MaxPollAttempts attempts."
}

function New-EncryptedAmaContent {
    param([Parameter(Mandatory)][string]$Path)
    $encryptedPath = Join-Path ([IO.Path]::GetTempPath()) ("azd-sysmon-ama-" + [Guid]::NewGuid().ToString('N') + '.bin')
    $aes = [Security.Cryptography.Aes]::Create()
    $hmac = [Security.Cryptography.HMACSHA256]::new()
    $source = $target = $crypto = $null
    try {
        $iv = $aes.IV
        $hmac.Key = [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
        $encryptionKey = [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
        $target = [IO.File]::Open($encryptedPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $target.Write([byte[]]::new(48), 0, 48)
        $source = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $crypto = [Security.Cryptography.CryptoStream]::new($target, $aes.CreateEncryptor($encryptionKey, $iv), [Security.Cryptography.CryptoStreamMode]::Write)
        $source.CopyTo($crypto)
        $crypto.FlushFinalBlock()
        $target.Position = 32
        $target.Write($iv, 0, $iv.Length)
        $target.Position = 32
        $mac = $hmac.ComputeHash($target)
        $target.Position = 0
        $target.Write($mac, 0, $mac.Length)
        $target.Flush()
        $digestStream = [IO.File]::OpenRead($Path)
        try { $digest = [Security.Cryptography.SHA256]::Create().ComputeHash($digestStream) }
        finally { $digestStream.Dispose() }
        return [pscustomobject]@{
            Path = $encryptedPath
            Size = $target.Length
            FileEncryptionInfo = [ordered]@{
                '@odata.type' = '#microsoft.graph.fileEncryptionInfo'
                encryptionKey = [Convert]::ToBase64String($encryptionKey)
                macKey = [Convert]::ToBase64String($hmac.Key)
                initializationVector = [Convert]::ToBase64String($iv)
                mac = [Convert]::ToBase64String($mac)
                profileIdentifier = 'ProfileVersion1'
                fileDigest = [Convert]::ToBase64String($digest)
                fileDigestAlgorithm = 'SHA256'
            }
        }
    } catch {
        if (Test-Path -LiteralPath $encryptedPath) { Remove-Item -LiteralPath $encryptedPath -Force -ErrorAction SilentlyContinue }
        throw
    } finally {
        if ($crypto) { $crypto.Dispose() }
        if ($source) { $source.Dispose() }
        if ($target) { $target.Dispose() }
        $hmac.Dispose(); $aes.Dispose()
    }
}

function New-WindowsMobileMsiManifest {
    param(
        [Parameter(Mandatory)][string]$ProductCode,
        [Parameter(Mandatory)][string]$ProductVersion,
        [Parameter(Mandatory)][string]$UpgradeCode
    )
    $document = [xml]'<MobileMsiData />'
    $attributes = [ordered]@{
        MsiExecutionContext = 'System'
        MsiRequiresReboot = 'false'
        MsiProductCode = $ProductCode
        MsiProductVersion = $ProductVersion
        MsiUpgradeCode = $UpgradeCode
        MsiIsMachineInstall = 'true'
        MsiIsUserInstall = 'false'
        MsiIncludesServices = 'true'
        MsiContainsSystemRegistryKeys = 'true'
        MsiContainsSystemFolders = 'false'
    }
    foreach ($attribute in $attributes.GetEnumerator()) {
        $node = $document.CreateAttribute([string]$attribute.Key)
        $node.Value = [string]$attribute.Value
        [void]$document.DocumentElement.Attributes.Append($node)
    }
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($document.OuterXml))
}

function Get-SafeAzureStorageFailureDiagnostic {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    $exception = $ErrorRecord.Exception
    $response = if ($exception.PSObject.Properties.Name -contains 'Response') { $exception.Response } else { $null }
    $status = $null
    $statusCandidates = [Collections.Generic.List[object]]::new()
    if ($exception.PSObject.Properties.Name -contains 'ResponseStatusCode') { $statusCandidates.Add($exception.ResponseStatusCode) }
    if ($exception.PSObject.Properties.Name -contains 'StatusCode') { $statusCandidates.Add($exception.StatusCode) }
    if ($response -and $response.PSObject.Properties.Name -contains 'StatusCode') { $statusCandidates.Add($response.StatusCode) }
    foreach ($candidate in $statusCandidates) {
        try { $status = [int]$candidate } catch { $status = $null }
        if ($null -ne $status) { break }
    }
    $azureCode = $null
    if ($response -and $response.PSObject.Properties.Name -contains 'Headers' -and $response.Headers) {
        try { $azureCode = [string]$response.Headers['x-ms-error-code'] } catch { $azureCode = $null }
        if ([string]::IsNullOrWhiteSpace($azureCode) -and $response.Headers.PSObject.Methods.Name -contains 'GetValues') {
            try { $azureCode = [string](@($response.Headers.GetValues('x-ms-error-code'))[0]) } catch { $azureCode = $null }
        }
    }
    if ([string]::IsNullOrWhiteSpace($azureCode) -and $response) {
        $errorXml = $null
        try {
            if ($response.PSObject.Properties.Name -contains 'Content' -and $response.Content) {
                $errorXml = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            } elseif ($response.PSObject.Methods.Name -contains 'GetResponseStream') {
                $reader = [IO.StreamReader]::new($response.GetResponseStream())
                try { $errorXml = $reader.ReadToEnd() } finally { $reader.Dispose() }
            }
            if ($errorXml) {
                [xml]$document = $errorXml
                $azureCode = [string]$document.SelectSingleNode('/Error/Code').InnerText
            }
        } catch { $azureCode = $null }
    }
    if ($null -eq $status) { $status = 'unavailable' }
    if ($azureCode -notmatch '^[A-Za-z0-9]{1,128}$') { $azureCode = 'unavailable' }
    return "HTTP status $status; Azure error code $azureCode."
}

function Upload-EncryptedBlob {
    param([Parameter(Mandatory)][string]$SasUri, [Parameter(Mandatory)][string]$Path)
    $blocks = [Collections.Generic.List[string]]::new()
    $stream = [IO.File]::OpenRead($Path)
    try {
        $buffer = [byte[]]::new(4MB)
        $index = 0
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $blockId = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($index.ToString('D8')))
            $separator = if ($SasUri.Contains('?')) { '&' } else { '?' }
            $blockUri = "$SasUri$separator`comp=block&blockid=$([Uri]::EscapeDataString($blockId))"
            [byte[]]$body = [byte[]]::new($read)
            [Array]::Copy($buffer, 0, $body, 0, $read)
            try {
                Invoke-WebRequest -Uri $blockUri -Method PUT -Headers @{ 'x-ms-blob-type' = 'BlockBlob' } -Body $body -ErrorAction Stop | Out-Null
            } catch {
                $diagnostic = Get-SafeAzureStorageFailureDiagnostic -ErrorRecord $_
                throw "Azure Storage upload failed while sending encrypted block $index. $diagnostic SAS URI and provider error details were withheld."
            }
            $blocks.Add($blockId)
            $index++
        }
        if ($blocks.Count -eq 0) { throw 'Encrypted AMA package is empty.' }
        $entries = ($blocks | ForEach-Object { '<Latest>' + [Security.SecurityElement]::Escape($_) + '</Latest>' }) -join ''
        $separator = if ($SasUri.Contains('?')) { '&' } else { '?' }
        $blockListXml = "<?xml version=`"1.0`" encoding=`"utf-8`"?><BlockList>$entries</BlockList>"
        [byte[]]$blockListBytes = [Text.Encoding]::UTF8.GetBytes($blockListXml)
        try {
            Invoke-WebRequest -Uri "$SasUri$separator`comp=blocklist" -Method PUT -ContentType 'application/xml; charset=utf-8' -Body $blockListBytes -ErrorAction Stop | Out-Null
        } catch {
            $diagnostic = Get-SafeAzureStorageFailureDiagnostic -ErrorRecord $_
            throw "Azure Storage upload failed while committing the encrypted block list. $diagnostic SAS URI and provider error details were withheld."
        }
    } finally { $stream.Dispose() }
}

$existing = @(Get-GraphCollection -Uri "${graphRoot}?`$top=100" -ExpectedPath '/v1.0/deviceAppManagement/mobileApps' | Where-Object { $_.displayName -eq $displayName })
if ($existing.Count -gt 1) { throw "More than one Intune application is named '$displayName'; resolve duplicates before continuing." }
$app = if ($existing.Count -eq 1) { $existing[0] } else { $null }
$appExisted = $null -ne $app
if ($app -and -not $AdoptExisting -and [string]$app.description -ne $marker) { throw "An application named '$displayName' exists but is not marked as owned by azd-sysmon. Pass -AdoptExisting only after review." }
if ($app -and [string]$app.'@odata.type' -ne '#microsoft.graph.windowsMobileMSI') { throw "An application named '$displayName' is not a windowsMobileMSI application." }
$needsContent = -not $app -or
    [string]$app.productCode -ne [string]$release.productCode -or
    [string]$app.productVersion -ne [string]$release.release -or
    [string]::IsNullOrWhiteSpace([string]$app.committedContentVersion)

$createAppBody = [ordered]@{
    '@odata.type' = '#microsoft.graph.windowsMobileMSI'
    displayName = $displayName
    description = $marker
    publisher = [string]$release.publisher
    fileName = [string]$release.fileName
    commandLine = '/qn'
    productCode = [string]$release.productCode
    productVersion = [string]$release.release
    ignoreVersionDetection = $false
}
$updateAppBody = [ordered]@{
    '@odata.type' = '#microsoft.graph.windowsMobileMSI'
    displayName = $displayName
    description = $marker
    publisher = [string]$release.publisher
    fileName = [string]$release.fileName
    commandLine = '/qn'
    productCode = [string]$release.productCode
    productVersion = [string]$release.release
    ignoreVersionDetection = $false
}
if ($app) {
    $appId = [string]$app.id
    $assignments = @(Get-GraphCollection -Uri "$graphRoot/$appId/assignments?`$top=100" -ExpectedPath "/v1.0/deviceAppManagement/mobileApps/$appId/assignments")
    foreach ($assignment in $assignments) {
        if ($assignment.target.'@odata.type' -ne '#microsoft.graph.groupAssignmentTarget' -or [string]$assignment.target.groupId -ne $GroupId -or $assignment.target.deviceAndAppManagementAssignmentFilterId) {
            throw 'The existing application has a different or filtered assignment. Refusing to change an application that could affect other targets.'
        }
    }
    if ($assignments.Count -gt 1) { throw 'Duplicate Intune application assignments require manual review before updating.' }
} else {
    $app = Invoke-MgGraphRequest -Method POST -Uri $graphRoot -Headers $headers -Body ($createAppBody | ConvertTo-Json -Depth 8)
    $appId = [string]$app.id
    if ([string]::IsNullOrWhiteSpace($appId)) { throw 'Graph did not return the new Intune application ID.' }
}

if ($needsContent) {
    # Intune exposes the content route for this concrete app type through its cast.
    # The uncast mobileApp route is rejected by the service for windowsMobileMSI.
    $contentVersionRoot = "$graphRoot/$appId/microsoft.graph.windowsMobileMSI/contentVersions"
    $encrypted = New-EncryptedAmaContent -Path $MsiPath
    try {
    $fileManifest = New-WindowsMobileMsiManifest -ProductCode ([string]$release.productCode) -ProductVersion ([string]$release.release) -UpgradeCode $msiUpgradeCode
    $fileSize = (Get-Item -LiteralPath $MsiPath).Length
    $file = $null
    if ($appExisted -and [string]::IsNullOrWhiteSpace([string]$app.committedContentVersion)) {
        # Intune does not allow a second content version before the first one commits. Reuse
        # that initial version, removing only its uncommitted files from a prior failed upload.
        $versions = @(Get-GraphCollection -Uri "${contentVersionRoot}?`$top=100" -ExpectedPath "/v1.0/deviceAppManagement/mobileApps/$appId/microsoft.graph.windowsMobileMSI/contentVersions")
        if ($versions.Count -eq 0) {
            # The application may have been created before an interruption prevented its
            # first version from being created. This is the only safe case to create one.
            $content = Invoke-MgGraphRequest -Method POST -Uri $contentVersionRoot -Headers $headers -Body '{}'
            $contentId = [string]$content.id
            if ([string]::IsNullOrWhiteSpace($contentId)) { throw 'Graph did not return the Intune application content version ID.' }
        } elseif ($versions.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$versions[0].id)) {
            $contentId = [string]$versions[0].id
            $staleFileRoot = "$contentVersionRoot/$contentId/files"
            $staleFiles = @(Get-GraphCollection -Uri "${staleFileRoot}?`$top=100" -ExpectedPath "/v1.0/deviceAppManagement/mobileApps/$appId/microsoft.graph.windowsMobileMSI/contentVersions/$contentId/files")
            if ($staleFiles.Count -gt 1) {
                throw 'The initial content version has multiple files. Recreate the unassigned application after review before retrying.'
            }
            if ($staleFiles.Count -eq 1) {
                $candidate = $staleFiles[0]
                if ([string]::IsNullOrWhiteSpace([string]$candidate.id) -or [string]$candidate.isCommitted -ine 'False' -or
                    [string]$candidate.name -ne [string]$release.fileName -or [int64]$candidate.size -ne [int64]$fileSize -or
                    [int64]$candidate.sizeEncrypted -ne [int64]$encrypted.Size -or [string]$candidate.manifest -cne $fileManifest) {
                    throw 'The initial content file does not exactly match this package. Recreate the unassigned application after review before retrying.'
                }
                $file = $candidate
            }
        } else {
            throw 'The existing application has no single reusable initial content version. Review its Intune content before retrying.'
        }
    } else {
        $contentUri = "$graphRoot/$appId/microsoft.graph.windowsMobileMSI/contentVersions"
        $content = Invoke-MgGraphRequest -Method POST -Uri $contentUri -Headers $headers -Body '{}'
        $contentId = [string]$content.id
        if ([string]::IsNullOrWhiteSpace($contentId)) { throw 'Graph did not return the Intune application content version ID.' }
    }
        $fileUri = "$contentVersionRoot/$contentId/files"
        if (-not $file) {
            $file = Invoke-MgGraphRequest -Method POST -Uri $fileUri -Headers $headers -Body (@{ name = [string]$release.fileName; size = $fileSize; sizeEncrypted = $encrypted.Size; manifest = $fileManifest } | ConvertTo-Json)
        }
        $fileId = [string]$file.id
        if ([string]::IsNullOrWhiteSpace($fileId)) { throw 'Graph did not return the Intune application content file ID.' }
        $fileUri = "$fileUri/$fileId"
        $file = Get-IntuneUploadUri -FileUri $fileUri
        Upload-EncryptedBlob -SasUri ([string]$file.azureStorageUri) -Path $encrypted.Path
        Invoke-MgGraphRequest -Method POST -Uri "$fileUri/commit" -Headers $headers -Body (@{ fileEncryptionInfo = $encrypted.FileEncryptionInfo } | ConvertTo-Json -Depth 8) | Out-Null
        Wait-ForFileState -Uri $fileUri -Stage commitFile | Out-Null
        $updateAppBody.committedContentVersion = $contentId
    } finally {
        if ($encrypted -and (Test-Path -LiteralPath $encrypted.Path)) { Remove-Item -LiteralPath $encrypted.Path -Force -ErrorAction SilentlyContinue }
    }
}

Invoke-MgGraphRequest -Method PATCH -Uri "$graphRoot/$appId" -Headers $headers -Body ($updateAppBody | ConvertTo-Json -Depth 8) | Out-Null
Wait-ForAppPublished -ApplicationId $appId

$assignmentBody = @{ mobileAppAssignments = @(@{ '@odata.type' = '#microsoft.graph.mobileAppAssignment'; intent = 'required'; target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $GroupId } }) }
Invoke-MgGraphRequest -Method POST -Uri "$graphRoot/$appId/assign" -Headers $headers -Body ($assignmentBody | ConvertTo-Json -Depth 8) | Out-Null
$stateRoot = Join-Path $templateRoot (Join-Path '.azure' $EnvironmentName)
New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
[ordered]@{
    applicationId = $appId
    groupId = $GroupId
    tenantId = $TenantId
    release = [string]$release.release
    packageSha256 = [string]$release.sha256
    recordedUtc = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stateRoot 'azd-sysmon-ama-application-state.json') -Encoding UTF8
Write-Output "Published Azure Monitor Agent $($release.release) to Intune application $appId and assigned it to group $GroupId."
