#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Ensure', 'Remove')][string]$Action,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]{1,64}$')][string]$AssociationName,
    [string]$DcrId,
    [string]$DcrLocation,
    [string]$TenantId,
    [string]$SubscriptionId,
    [switch]$ConfirmTenantWideScope
)

$ErrorActionPreference = 'Stop'
if (-not $ConfirmTenantWideScope) {
    throw 'This operation changes a Microsoft Entra tenant-wide monitored-object association. Pass -ConfirmTenantWideScope only after reviewing the blast radius.'
}
if ($Action -eq 'Ensure' -and [string]::IsNullOrWhiteSpace($DcrId)) { throw 'DcrId is required for Ensure.' }
if ($Action -eq 'Ensure' -and [string]::IsNullOrWhiteSpace($DcrLocation)) { throw 'DcrLocation is required for Ensure.' }
if ($Action -eq 'Ensure' -and $DcrId -notmatch '^/subscriptions/([^/]+)/resourceGroups/[^/]+/providers/Microsoft\.Insights/dataCollectionRules/[^/]+$') { throw 'DcrId must be a full data collection rule resource ID.' }
if ($Action -eq 'Ensure') {
    $dcrSubscriptionId = $Matches[1]
    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { $SubscriptionId = $dcrSubscriptionId }
    if ($SubscriptionId -ine $dcrSubscriptionId) { throw "SubscriptionId '$SubscriptionId' does not match the DCR subscription '$dcrSubscriptionId'." }
}
if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or $SubscriptionId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    throw 'SubscriptionId must be the intended Azure subscription GUID.'
}
if ([string]::IsNullOrWhiteSpace($TenantId) -or $TenantId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    throw 'TenantId must be the intended Microsoft Entra tenant GUID.'
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required. Sign in through the standard Azure CLI browser/WAM flow before enabling client AMA tenant scope.'
}

function Invoke-AzureCliJson {
    param([Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$Operation)

    $raw = & az @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed while $Operation." }
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { throw "Azure CLI returned no JSON while $Operation." }
    try {
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        throw "Azure CLI returned invalid JSON while $Operation."
    }
}

$account = Invoke-AzureCliJson -Operation 'reading the selected subscription account' -Arguments @('account', 'show', '--subscription', $SubscriptionId, '--output', 'json', '--only-show-errors')
if ([string]$account.id -ine $SubscriptionId) { throw "Azure CLI did not bind to subscription '$SubscriptionId'." }
if ([string]$account.tenantId -ine $TenantId) { throw "Azure CLI subscription '$SubscriptionId' belongs to tenant '$($account.tenantId)', not '$TenantId'." }
if ([string]$account.environmentName -ne 'AzureCloud') { throw "Azure CLI subscription '$SubscriptionId' is in '$($account.environmentName)', not AzureCloud." }

# Get a token only after the selected CLI account has been verified. It stays in memory and is never written to output or state.
$tokenResult = Invoke-AzureCliJson -Operation 'acquiring an Azure Resource Manager token' -Arguments @('account', 'get-access-token', '--resource', 'https://management.azure.com/', '--subscription', $SubscriptionId, '--output', 'json', '--only-show-errors')
if ([string]$tokenResult.tenant -ine $TenantId) { throw 'The Azure CLI token tenant does not match the selected deployment tenant.' }
$accessToken = [string]$tokenResult.accessToken
if ([string]::IsNullOrWhiteSpace($accessToken)) { throw 'Azure CLI did not return an Azure Resource Manager access token.' }

# Resolve currently advertised preview API versions rather than pinning an obsolete client AMA API version.
$provider = Invoke-AzureCliJson -Operation 'reading Microsoft.Insights provider metadata' -Arguments @('provider', 'show', '--namespace', 'Microsoft.Insights', '--subscription', $SubscriptionId, '--output', 'json', '--only-show-errors')
$monitoredType = @($provider.resourceTypes | Where-Object { $_.resourceType -eq 'monitoredObjects' } | Select-Object -First 1)
$associationType = @($provider.resourceTypes | Where-Object { $_.resourceType -eq 'dataCollectionRuleAssociations' } | Select-Object -First 1)
if ($monitoredType.Count -eq 0) {
    throw 'Microsoft.Insights provider metadata did not advertise monitoredObjects. Register/refresh the provider and retry.'
}
$monitoredApiVersion = @($monitoredType.apiVersions | Where-Object { $_ -match 'preview' } | Select-Object -First 1)[0]
$associationApiVersion = if ($associationType.Count -gt 0) { @($associationType.apiVersions | Where-Object { $_ -match 'preview' } | Select-Object -First 1)[0] } else { $null }
if ([string]::IsNullOrWhiteSpace($associationApiVersion)) { $associationApiVersion = $monitoredApiVersion }
if ([string]::IsNullOrWhiteSpace($monitoredApiVersion) -or [string]::IsNullOrWhiteSpace($associationApiVersion)) {
    throw 'Microsoft.Insights provider metadata did not advertise a supported preview API version for the client AMA resources.'
}

function Invoke-ArmRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'PUT', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [string]$Payload,
        [switch]$AllowNotFound
    )

    $statusCode = $null
    $request = @{
        Uri = "https://management.azure.com$Path"
        Method = $Method
        Headers = @{ Authorization = "Bearer $accessToken" }
        SkipHttpErrorCheck = $true
        StatusCodeVariable = 'statusCode'
        ErrorAction = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Payload')) {
        $request.Body = $Payload
        $request.ContentType = 'application/json'
    }
    $response = Invoke-RestMethod @request
    $actualStatusCode = if ($null -ne $statusCode) { [int]$statusCode } elseif ($null -ne $response -and $null -ne $response.PSObject.Properties['StatusCode']) { [int]$response.StatusCode } else { $null }
    if ($null -eq $actualStatusCode) { throw "Azure Resource Manager returned no HTTP status for $Method $Path." }
    if ($AllowNotFound -and $actualStatusCode -eq 404) { return $null }
    if ($actualStatusCode -lt 200 -or $actualStatusCode -ge 300) { throw "Azure Resource Manager returned HTTP $actualStatusCode for $Method $Path." }
    $content = if ($response -is [string]) { $response } else { $response | ConvertTo-Json -Depth 100 -Compress }
    return [pscustomobject]@{ StatusCode = $actualStatusCode; Content = $content }
}

function ConvertFrom-ArmContent {
    param([Parameter(Mandatory)]$Response, [Parameter(Mandatory)][string]$ResourceName)

    if ([string]::IsNullOrWhiteSpace([string]$Response.Content)) { throw "Azure Resource Manager returned no body for $ResourceName." }
    try {
        return $Response.Content | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Azure Resource Manager returned invalid JSON for ${ResourceName}: $($_.Exception.Message)"
    }
}

Write-Host "Using monitored-object API $monitoredApiVersion and association API $associationApiVersion."
Write-Host 'The signed-in principal must already have Monitored Objects Contributor at the Microsoft.Insights provider/root scope; this script does not grant root-scope permissions.'

$monitoredObjectId = "/providers/Microsoft.Insights/monitoredObjects/$TenantId"
$associationPath = "$monitoredObjectId/providers/Microsoft.Insights/dataCollectionRuleAssociations/$AssociationName"

if ($Action -eq 'Ensure') {
    $monitoredBody = @{ properties = @{ location = $DcrLocation } } | ConvertTo-Json -Depth 4
    $associationBody = @{ properties = @{ dataCollectionRuleId = $DcrId } } | ConvertTo-Json -Depth 4

    $monitoredObject = Invoke-ArmRequest -Method GET -Path "$monitoredObjectId`?api-version=$monitoredApiVersion" -AllowNotFound
    if ($null -eq $monitoredObject) {
        Write-Host "Creating tenant monitored object $monitoredObjectId"
        Invoke-ArmRequest -Method PUT -Path "$monitoredObjectId`?api-version=$monitoredApiVersion" -Payload $monitoredBody | Out-Null
    } else {
        $existingMonitoredObject = ConvertFrom-ArmContent -Response $monitoredObject -ResourceName 'the tenant monitored object'
        if ([string]$existingMonitoredObject.properties.location -ine $DcrLocation) {
            throw "The existing tenant monitored object location '$($existingMonitoredObject.properties.location)' does not match DCR location '$DcrLocation'."
        }
        Write-Host "Retaining existing tenant monitored object $monitoredObjectId"
    }

    $association = Invoke-ArmRequest -Method GET -Path "$associationPath`?api-version=$associationApiVersion" -AllowNotFound
    if ($null -ne $association) {
        $existingAssociation = ConvertFrom-ArmContent -Response $association -ResourceName "association '$AssociationName'"
        if ([string]$existingAssociation.properties.dataCollectionRuleId -ine $DcrId) {
            throw "Association '$AssociationName' already exists but points to another DCR. Resolve the ownership collision before continuing."
        }
        Write-Host "Retaining existing Sysmon DCR association '$AssociationName'"
    } else {
        Write-Host "Associating Sysmon DCR $DcrId to the tenant monitored object"
        Invoke-ArmRequest -Method PUT -Path "$associationPath`?api-version=$associationApiVersion" -Payload $associationBody | Out-Null
    }
    Write-Host "Client AMA tenant-wide association '$AssociationName' is configured." -ForegroundColor Green
} else {
    Write-Host "Removing only association '$AssociationName' from $monitoredObjectId"
    $deleted = Invoke-ArmRequest -Method DELETE -Path "$associationPath`?api-version=$associationApiVersion" -AllowNotFound
    if ($null -eq $deleted) { Write-Host 'The association was already absent.' }
    Write-Host 'The monitored object itself was retained.' -ForegroundColor Green
}
