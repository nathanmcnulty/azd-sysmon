#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')][string]$GroupId,
    [string]$Configuration = 'balanced',
    [switch]$AdoptExisting,
    [string]$ExpectedAccount = $env:AZD_SYSMON_GRAPH_ACCOUNT,
    [string]$TenantId = $env:AZURE_TENANT_ID,
    [switch]$AllowContextReplacement,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')][string]$EnvironmentName = 'default'
)

$ErrorActionPreference = 'Stop'
$templateRoot = Split-Path -Parent $PSScriptRoot
$remediationPath = Join-Path $templateRoot 'deploy\intune\Remediate-Sysmon.ps1'
$detectionPath = Join-Path $templateRoot 'deploy\intune\Detect-Sysmon.ps1'
$packageManifestPath = Join-Path $templateRoot 'config\generated-package-manifest.json'
if (-not (Test-Path -LiteralPath $remediationPath -PathType Leaf) -or -not (Test-Path -LiteralPath $detectionPath -PathType Leaf)) { throw 'Generated Intune scripts are missing. Run scripts\Build-SysmonPackages.ps1 first.' }

$packageManifest = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json
foreach ($path in @($remediationPath, $detectionPath)) {
    $relative = '.\' + $path.Substring($templateRoot.Length).TrimStart('\', '/').Replace('/', '\')
    $expectedHash = [string]$packageManifest.generatedFiles.$relative
    if ($expectedHash -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $expectedHash) {
        throw "Generated package integrity check failed: $relative. Rebuild and review the package."
    }
}
$availableConfigurations = @($packageManifest.configurationKeys | ForEach-Object { ([string]$_).ToLowerInvariant() })
$Configuration = $Configuration.ToLowerInvariant()
if ($Configuration -notin $availableConfigurations) {
    throw "Configuration '$Configuration' is not in the generated package. Available configurations: $($availableConfigurations -join ', '). Rebuild the package or choose an available configuration."
}
$oldConfiguration = [string]$packageManifest.defaultConfiguration
$oldConfigurationHash = [string]$packageManifest.configurationFiles.PSObject.Properties[$oldConfiguration].Value.sha256
$configurationHash = [string]$packageManifest.configurationFiles.PSObject.Properties[$Configuration].Value.sha256
if ($configurationHash -notmatch '^[a-f0-9]{64}$') {
    throw "Configuration '$Configuration' is missing a valid SHA-256 hash in the generated package manifest."
}
$remediation = Get-Content -LiteralPath $remediationPath -Raw
$detection = Get-Content -LiteralPath $detectionPath -Raw
$remediation = $remediation.Replace("[string]`$Configuration = '$oldConfiguration'", "[string]`$Configuration = '$Configuration'")
$detection = $detection.Replace("`$desiredConfiguration = '$oldConfiguration'", "`$desiredConfiguration = '$Configuration'")
$detection = $detection.Replace("`$desiredConfigurationSha256 = '$oldConfigurationHash'", "`$desiredConfigurationSha256 = '$configurationHash'")
if (-not $remediation.Contains("[string]`$Configuration = '$Configuration'")) { throw 'Unable to select the requested configuration in the generated Intune remediation script.' }
if (-not $detection.Contains("`$desiredConfiguration = '$Configuration'")) { throw 'Unable to select the requested configuration in the generated Intune detection script.' }
if (-not $detection.Contains("`$desiredConfigurationSha256 = '$configurationHash'")) { throw 'Unable to select the requested configuration hash in the generated Intune detection script.' }

if ([Text.Encoding]::UTF8.GetByteCount($remediation) -ge 200KB -or [Text.Encoding]::UTF8.GetByteCount($detection) -ge 200KB) {
    throw 'The generated Intune script exceeds the documented 200 KB script limit.'
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw 'Microsoft.Graph.Authentication is required. Install it with Install-Module Microsoft.Graph.Authentication -Scope CurrentUser.'
}
Import-Module (Join-Path $PSScriptRoot 'vendor/Azd.GraphAuthentication/Azd.GraphAuthentication.psd1') -Force
$requiredScopes = @('DeviceManagementScripts.ReadWrite.All')
if ([string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($ExpectedAccount)) {
    throw 'Set AZURE_TENANT_ID and AZD_SYSMON_GRAPH_ACCOUNT to the intended tenant GUID and administrator UPN before Intune publishing.'
}
Connect-AzdGraphSession -TenantId $TenantId -ExpectedAccount $ExpectedAccount -Scopes $requiredScopes `
    -ProbeUri '/beta/deviceManagement/deviceHealthScripts?$top=1&$select=id' `
    -AllowInteractive -AllowContextReplacement:$AllowContextReplacement | Out-Null

function Get-GraphCollection {
    param([Parameter(Mandatory)][string]$Uri)
    $seen = [Collections.Generic.HashSet[string]]::new()
    while ($Uri) {
        if ($Uri -notmatch '^https://graph\.microsoft\.com/beta/deviceManagement/deviceHealthScripts(?:[/?]|$)' -or -not $seen.Add($Uri)) {
            throw 'Graph returned an unexpected or repeated pagination URL.'
        }
        $page = Invoke-MgGraphRequest -Method GET -Uri $Uri
        foreach ($item in $page.value) { $item }
        $Uri = [string]$page.'@odata.nextLink'
    }
}

function Write-IntuneState {
    param(
        [Parameter(Mandatory)][string]$ScriptId,
        [Parameter(Mandatory)][ValidateSet('created', 'assigned')][string]$Status,
        [Parameter(Mandatory)][bool]$AdoptedExisting
    )

    $stateRoot = Join-Path $templateRoot (Join-Path '.azure' $EnvironmentName)
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    [ordered]@{
        template = 'azd-sysmon'
        objectType = 'intune-device-health-script'
        scriptId = $ScriptId
        groupId = $GroupId
        tenantId = $TenantId
        account = $ExpectedAccount
        environmentName = $EnvironmentName
        configuration = $Configuration
        adoptedExisting = $AdoptedExisting
        status = $Status
        recordedUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stateRoot 'azd-sysmon-intune-state.json') -Encoding UTF8
}

$baseUri = 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'
$headers = @{ 'Content-Type' = 'application/json' }
$existing = @(Get-GraphCollection -Uri "$baseUri`?`$top=100" | Where-Object { $_.displayName -eq 'AZD Sysmon Remediation' })
if ($existing.Count -gt 1) { throw 'More than one AZD Sysmon Remediation object exists; resolve the duplicate before continuing.' }

$marker = 'Managed by azd-sysmon; changing this object outside the template can be overwritten.'
$scriptBody = @{
    '@odata.type' = '#microsoft.graph.deviceHealthScript'
    displayName = 'AZD Sysmon Remediation'
    description = $marker
    publisher = 'azd-sysmon'
    version = '0.1.0'
    detectionScriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($detection))
    remediationScriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remediation))
    runAsAccount = 'system'
    enforceSignatureCheck = $false
    runAs32Bit = $false
    deviceHealthScriptType = 'deviceHealthScript'
}
$scriptJson = $scriptBody | ConvertTo-Json -Depth 8
$adoptedExisting = $false

if ($existing.Count -eq 1) {
    if (-not $AdoptExisting -and ($existing[0].publisher -ne 'azd-sysmon' -or $existing[0].description -ne $marker)) {
        throw 'An object named AZD Sysmon Remediation exists but is not marked as owned by azd-sysmon. Pass -AdoptExisting only after review.'
    }
    $adoptedExisting = [bool]$AdoptExisting
    $scriptId = [string]$existing[0].id
    $currentAssignments = @(Get-GraphCollection -Uri "$baseUri/$scriptId/assignments")
    foreach ($assignment in $currentAssignments) {
        if ($assignment.target.'@odata.type' -ne '#microsoft.graph.groupAssignmentTarget' -or $assignment.target.groupId -ne $GroupId -or
            ($assignment.target.deviceAndAppManagementAssignmentFilterId -and $assignment.target.deviceAndAppManagementAssignmentFilterId -ne [guid]::Empty.ToString()) -or
            ($assignment.target.deviceAndAppManagementAssignmentFilterType -and $assignment.target.deviceAndAppManagementAssignmentFilterType -ne 'none')) {
            throw 'The existing remediation has a different or filtered assignment. Refusing to update scripts that could affect other targets; review assignments in Intune first.'
        }
    }
    if ($currentAssignments.Count -gt 1) { throw 'Duplicate remediation assignments require manual review before updating scripts.' }
    # Intune owns the version and script type after creation; its live PATCH
    # endpoint rejects these properties even though create examples include them.
    $updateBody = $scriptBody.Clone()
    $updateBody.Remove('version')
    $updateBody.Remove('deviceHealthScriptType')
    Invoke-MgGraphRequest -Method PATCH -Uri "$baseUri/$scriptId" -Headers $headers -Body ($updateBody | ConvertTo-Json -Depth 8) | Out-Null
    Write-Host "Updated Intune Remediation $scriptId"
} else {
    $created = Invoke-MgGraphRequest -Method POST -Uri $baseUri -Headers $headers -Body $scriptJson
    $scriptId = [string]$created.id
    if ([string]::IsNullOrWhiteSpace($scriptId)) { throw 'Graph did not return the new deviceHealthScript ID.' }
    Write-Host "Created Intune Remediation $scriptId"
}

# Persist the object identity before assignment so azd down can clean up a
# partially completed deployment without guessing by display name.
Write-IntuneState -ScriptId $scriptId -Status created -AdoptedExisting $adoptedExisting

$assignmentUri = "$baseUri/$scriptId/assignments"
$existingAssignment = @(Get-GraphCollection -Uri $assignmentUri)
foreach ($assignment in $existingAssignment) {
    if ($assignment.target.'@odata.type' -ne '#microsoft.graph.groupAssignmentTarget' -or $assignment.target.groupId -ne $GroupId -or
        ($assignment.target.deviceAndAppManagementAssignmentFilterId -and $assignment.target.deviceAndAppManagementAssignmentFilterId -ne [guid]::Empty.ToString()) -or
        ($assignment.target.deviceAndAppManagementAssignmentFilterType -and $assignment.target.deviceAndAppManagementAssignmentFilterType -ne 'none')) {
        throw 'The remediation assignments changed or include another target. Refusing to replace them.'
    }
}
$assignmentBody = @{
    '@odata.type' = '#microsoft.graph.deviceHealthScriptAssignment'
    target = @{
        '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
        groupId = $GroupId
    }
    runRemediationScript = $true
    runSchedule = @{
        '@odata.type' = '#microsoft.graph.deviceHealthScriptDailySchedule'
        interval = 1
        useUtc = $false
        time = '09:00:00'
    }
}
if ($existingAssignment.Count -gt 1) {
    throw "More than one assignment exists for group $GroupId."
}
$assignmentJson = @{ deviceHealthScriptAssignments = @($assignmentBody) } | ConvertTo-Json -Depth 8
Invoke-MgGraphRequest -Method POST -Uri "$baseUri/$scriptId/assign" -Headers $headers -Body $assignmentJson | Out-Null
Write-Host "Assigned the remediation to group $GroupId" -ForegroundColor Green
Write-IntuneState -ScriptId $scriptId -Status assigned -AdoptedExisting $adoptedExisting
