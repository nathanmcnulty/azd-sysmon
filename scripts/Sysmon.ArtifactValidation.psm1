#requires -Version 7.6
Set-StrictMode -Version Latest

function Assert-SysmonLocalPath {
    param([string]$Path)
    if (-not [IO.Path]::IsPathFullyQualified($Path) -or $Path.StartsWith('\\') -or $Path.Contains('://')) {
        throw 'LocalArtifactPathRejected'
    }
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'LocalArtifactPathRejected'
        }
        $cursor = Split-Path -Parent $cursor
    }
}

function Read-SysmonArtifact {
    param([string]$Root, [string]$Name)
    $path = Join-Path $Root $Name
    Assert-SysmonLocalPath $path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $stream = $null
    $document = $null
    try {
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ($stream.Length -gt 65536) { throw 'Rejected' }
        $buffer = [byte[]]::new(65537)
        $used = 0
        while ($used -lt $buffer.Length) {
            $read = $stream.Read($buffer, $used, $buffer.Length - $used)
            if ($read -eq 0) { break }
            $used += $read
        }
        if ($used -gt 65536) { throw 'Rejected' }
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($buffer, 0, $used)
        # Reject ambiguous duplicate properties before converting to a hashtable.
        $options = [Text.Json.JsonDocumentOptions]::new()
        $options.MaxDepth = 16
        $document = [Text.Json.JsonDocument]::Parse($text, $options)
        function Assert-UniqueProperty($Node) {
            if ($Node.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
                $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                foreach ($property in $Node.EnumerateObject()) {
                    if (-not $names.Add($property.Name)) { throw 'Rejected' }
                    Assert-UniqueProperty $property.Value
                }
            } elseif ($Node.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
                foreach ($child in $Node.EnumerateArray()) { Assert-UniqueProperty $child }
            }
        }
        Assert-UniqueProperty $document.RootElement
        $value = ConvertFrom-Json -InputObject $text -AsHashtable -Depth 16 -DateKind String -ErrorAction Stop
        if ($value -isnot [Collections.IDictionary]) { throw 'Rejected' }
        return @{
            value = $value
            hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([byte[]]$buffer[0..($used - 1)])).ToLowerInvariant()
        }
    } catch {
        throw [InvalidOperationException]::new('LocalArtifactRejected')
    } finally {
        if ($document) { $document.Dispose() }
        if ($stream) { $stream.Dispose() }
        $text = $null
        $buffer = $null
    }
}

function Assert-SysmonReceipt {
    param($Artifact, [hashtable]$Target, [string]$Name, [string]$ObjectType, [string]$Account,
        [string[]]$Statuses, [int]$MaximumAgeHours)
    if ($null -eq $Artifact) { throw 'ReceiptMissing' }
    if (-not $Target.artifactHashes.ContainsKey($Name) -or $Target.artifactHashes[$Name] -cne $Artifact.hash) {
        throw 'ReceiptHashUnbound'
    }
    $value = $Artifact.value
    if ($value.template -cne 'azd-sysmon' -or $value.environmentName -cne $Target.environmentName) {
        throw 'ReceiptTargetMismatch'
    }
    if ($ObjectType) {
        if ($value.objectType -cne $ObjectType -or $value.tenantId -cne $Target.tenantId -or
            $value.account -cne $Account -or $value.status -cnotin $Statuses -or
            $value.adoptedExisting -isnot [bool]) { throw 'ReceiptTargetMismatch' }
    } elseif ($value.azureSubscriptionId -cne $Target.subscriptionId -or $value.azureTenantId -cne $Target.tenantId) {
        throw 'ReceiptTargetMismatch'
    }
    $recorded = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$value.recordedUtc, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$recorded) -or
        $recorded -lt [DateTimeOffset]::UtcNow.AddHours(-$MaximumAgeHours) -or
        $recorded -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) { throw 'ReceiptTimeUnusable' }
    return $value
}

function New-SysmonArtifactReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArtifactRoot,
        [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
        [ValidateRange(1, 168)][int]$MaximumReceiptAgeHours = 24,
        [switch]$Plan
    )
    Assert-SysmonLocalPath $ArtifactRoot
    Assert-SysmonLocalPath $RepositoryRoot
    $targetArtifact = Read-SysmonArtifact $ArtifactRoot 'target.json'
    if ($null -eq $targetArtifact) { throw 'TargetContractMissing' }
    $target = $targetArtifact.value
    $schemaPath = Join-Path $PSScriptRoot 'sysmon-artifact-target.schema.json'
    if (-not (($target | ConvertTo-Json -Depth 16) | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) {
        throw 'TargetContractRejected'
    }
    if (('intune' -cin $target.paths -and -not $target.graphAccount) -or
        ('liveResponse' -cin $target.paths -and -not $target.mdeAccount)) { throw 'TargetContractRejected' }
    foreach ($field in @('environmentName','tenantId','subscriptionId','graphAccount','mdeAccount')) {
        if ($target[$field] -match '[\u0000-\u0020]') { throw 'TargetContractRejected' }
    }
    $started = [DateTimeOffset]::UtcNow
    $checks = foreach ($path in @('package', 'intune', 'azureVm', 'sentinel', 'liveResponse')) {
        $enabled = $path -cin $target.paths
        $status = if ($enabled) { 'info' } else { 'skipped' }
        $reason = if ($enabled) { 'LocalArtifactsOnly' } else { 'PathNotSelected' }
        $facts = @{}
        if ($enabled -and -not $Plan) {
            try {
                if ($path -ceq 'package') {
                    $manifest = (Read-SysmonArtifact (Join-Path $RepositoryRoot 'config') 'generated-package-manifest.json').value
                    $count = 0
                    foreach ($entry in $manifest.generatedFiles.GetEnumerator()) {
                        $relative = $entry.Key -replace '^\.[\\/]', ''
                        if ($relative -notmatch '^(deploy/(azure-vm|intune|live-response)/[A-Za-z0-9.-]+\.ps1)$') {
                            $relative = $relative.Replace('\', '/')
                        }
                        if ($relative -notmatch '^deploy/(azure-vm|intune|live-response)/[A-Za-z0-9.-]+\.ps1$' -or
                            $entry.Value -cnotmatch '^[a-f0-9]{64}$') { throw 'PackageManifestRejected' }
                        $file = Join-Path $RepositoryRoot $relative
                        Assert-SysmonLocalPath $file
                        if ((Get-Item -LiteralPath $file).Length -gt 2097152 -or
                            (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $entry.Value) { throw 'PackageDrift' }
                        $count++
                    }
                    if ($count -lt 1) { throw 'PackageManifestRejected' }
                    $status = 'pass'
                    $reason = 'GeneratedPackageHashesMatch'
                    $facts = @{ generatedFileCount = $count }
                } else {
                    $stateArtifact = Read-SysmonArtifact $ArtifactRoot 'azd-sysmon-state.json'
                    $state = Assert-SysmonReceipt $stateArtifact $target 'azd-sysmon-state.json' '' '' @() $MaximumReceiptAgeHours
                    switch -CaseSensitive ($path) {
                        intune {
                            $flags = @('intuneRemediation', 'intuneAmaApplication')
                            foreach ($flag in $flags) {
                                if ($state[$flag] -isnot [bool]) { throw 'ReceiptShapeRejected' }
                            }
                            if (-not ($state.intuneRemediation -or $state.intuneAmaApplication)) { throw 'PathNotRecorded' }
                            foreach ($spec in @(
                                @{ flag='intuneRemediation'; file='azd-sysmon-intune-state.json'; type='intune-device-health-script'; id='scriptId' },
                                @{ flag='intuneAmaApplication'; file='azd-sysmon-ama-application-state.json'; type='intune-windows-msi-application'; id='applicationId' }
                            )) {
                                if ($state[$spec.flag]) {
                                    $object = Assert-SysmonReceipt (Read-SysmonArtifact $ArtifactRoot $spec.file) $target $spec.file $spec.type $target.graphAccount @('created','assigned') $MaximumReceiptAgeHours
                                    foreach ($field in @($spec.id, 'groupId')) {
                                        if ($object[$field] -isnot [string] -or $object[$field] -cnotmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(?![\s\S])') { throw 'ReceiptShapeRejected' }
                                    }
                                }
                            }
                            $facts = @{ remediationRecorded=$state.intuneRemediation; amaApplicationRecorded=$state.intuneAmaApplication }
                        }
                        azureVm {
                            if ($state.vmSysmonAttempted -isnot [bool] -or -not $state.vmSysmonAttempted -or
                                $state.vmAmaInstalled -isnot [bool] -or $state.vmDcrAssociated -isnot [bool] -or
                                $state.vmResourceIds -isnot [array] -or $state.vmResourceIds.Count -eq 0) { throw 'ReceiptShapeRejected' }
                            foreach ($id in $state.vmResourceIds) {
                                if ($id -isnot [string] -or $id -match '[\u0000-\u0020]' -or $id -notmatch ('^/subscriptions/'+[regex]::Escape($target.subscriptionId)+'/resourceGroups/[^/]+/providers/Microsoft\.Compute/virtualMachines/[^/]+(?![\s\S])')) { throw 'ReceiptTargetMismatch' }
                            }
                            $facts = @{ vmAttemptCount=$state.vmResourceIds.Count; amaInstallRecorded=$state.vmAmaInstalled; dcrAssociationRecorded=$state.vmDcrAssociated }
                        }
                        sentinel {
                            if ($state.dcrId -isnot [string] -or $state.dcrId -match '[\u0000-\u0020]' -or $state.dcrId -notmatch ('^/subscriptions/'+[regex]::Escape($target.subscriptionId)+'/resourceGroups/[^/]+/providers/Microsoft\.Insights/dataCollectionRules/[^/]+(?![\s\S])')) { throw 'ReceiptTargetMismatch' }
                            $facts = @{ dcrRecorded=$true }
                        }
                        liveResponse {
                            if ($state.liveResponseLibrary -isnot [bool] -or -not $state.liveResponseLibrary) { throw 'PathNotRecorded' }
                            $object = Assert-SysmonReceipt (Read-SysmonArtifact $ArtifactRoot 'azd-sysmon-live-response-state.json') $target 'azd-sysmon-live-response-state.json' 'defender-live-response-library-file' $target.mdeAccount @('published') $MaximumReceiptAgeHours
                            if ($object.fileName -isnot [string] -or $object.fileName -cnotmatch '^[A-Za-z0-9._-]+\.ps1(?![\s\S])') { throw 'ReceiptShapeRejected' }
                            $facts = @{ libraryPublicationRecorded=$true }
                        }
                    }
                    $reason = 'HashBoundLocalRecordNotServiceProof'
                }
            } catch {
                $status = 'warning'
                $allowed = @('ReceiptMissing','ReceiptHashUnbound','ReceiptTargetMismatch','ReceiptTimeUnusable','ReceiptShapeRejected','PathNotRecorded','PackageManifestRejected','PackageDrift','LocalArtifactRejected','LocalArtifactPathRejected')
                $reason = if ($_.Exception.Message -cin $allowed) { $_.Exception.Message } else { 'ArtifactEvidenceUnusable' }
                $facts = @{}
            }
        }
        $outcome = New-AzdCheckOutcome -Status $status -Summary $reason -Evidence $facts -Metadata @{ evidenceClass='localArtifact'; selected=$enabled }
        $action = { $outcome }.GetNewClosure()
        $definition = New-AzdValidationCheckDefinition -Id ($path.ToLowerInvariant()+'.artifact') -Phase configuration -Title ($path+' local artifacts') -Summary 'Local artifact inspection only' -Action $action -SideEffect none
        Invoke-AzdValidationSet -Definitions @($definition) -Plan:$Plan
        $endpoint = New-AzdCheckOutcome -Status $(if ($enabled) {'warning'} else {'skipped'}) -Summary $(if ($enabled) {'FreshEndpointAndServiceEvidenceRequired'} else {'PathNotSelected'}) -Metadata @{ evidenceClass='unverifiedEndpoint' }
        $endpointAction = { $endpoint }.GetNewClosure()
        $endpointDefinition = New-AzdValidationCheckDefinition -Id ($path.ToLowerInvariant()+'.endpoint') -Phase runtime -Title ($path+' live qualification') -Summary 'Local files cannot prove current service or endpoint state' -Action $endpointAction -SideEffect none
        Invoke-AzdValidationSet -Definitions @($endpointDefinition) -Plan:$Plan
    }
    New-AzdValidationReport -TemplateName 'azd-sysmon-local-artifacts' -TemplateVersion '1.0' -Mode $(if ($Plan) {'plan'} else {'verify'}) -StartedAt $started -Checks @($checks) -Environment @{
        name=$target.environmentName
        metadata=@{ evidenceClass='localArtifactOnly'; targetContractHash=$targetArtifact.hash; maximumReceiptAgeHours=$MaximumReceiptAgeHours; notCleanupAuthority=$true }
    } -NextSteps @('Use separately authorized fresh service and endpoint checks for selected paths. Local records are not deployment readiness, delivery, installation or cleanup proof.')
}

Export-ModuleMember -Function New-SysmonArtifactReport
