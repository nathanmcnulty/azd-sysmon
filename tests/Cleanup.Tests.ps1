#requires -Version 7.2
BeforeAll {
    $sourceRoot = Split-Path -Parent $PSScriptRoot
    function Connect-AzdGraphSession { param($TenantId, $ExpectedAccount, $Scopes, $ProbeUri, [switch]$AllowInteractive, [switch]$AllowContextReplacement) }
    function Invoke-MgGraphRequest { param($Method, $Uri, $Headers, $Body) }
    function New-GraphNotFoundException {
        $exception = [System.Exception]::new('Response status code does not indicate success: NotFound (Not Found).')
        $exception | Add-Member -MemberType NoteProperty -Name Response -Value ([pscustomobject]@{ StatusCode = 404 }) -Force
        return $exception
    }
}

Describe 'azd down receipt cleanup' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $scriptRoot = Join-Path $root 'scripts'
        $receiptRoot = Join-Path $root '.azure/cleanup-test'
        New-Item -ItemType Directory -Path $scriptRoot, $receiptRoot -Force | Out-Null
        Copy-Item (Join-Path $sourceRoot 'scripts/Pre-Down.ps1') (Join-Path $scriptRoot 'Pre-Down.ps1')
        $script:preDown = Join-Path $scriptRoot 'Pre-Down.ps1'
        $script:savedEnvironment = @{}
        Get-ChildItem Env: | Where-Object { $_.Name -match '^AZD_SYSMON_|^AZURE_' } | ForEach-Object {
            $script:savedEnvironment[$_.Name] = $_.Value
            [Environment]::SetEnvironmentVariable($_.Name, $null, 'Process')
        }
        $env:AZURE_ENV_NAME = 'cleanup-test'
        $env:AZD_SYSMON_PRESERVE_EXTERNAL_RESOURCES = 'false'
        $env:AZD_SYSMON_REMOVE_ADOPTED_EXTERNAL_RESOURCES = 'false'
        $env:AZD_SYSMON_REMOVE_CLIENT_AMA_ASSOCIATION = 'false'
        $env:AZD_SYSMON_CONFIRM_TENANT_SCOPE = 'not-confirmed'
    }

    AfterEach {
        Get-ChildItem Env: | Where-Object { $_.Name -match '^AZD_SYSMON_|^AZURE_' } | ForEach-Object {
            [Environment]::SetEnvironmentVariable($_.Name, $null, 'Process')
        }
        foreach ($key in $script:savedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $script:savedEnvironment[$key], 'Process')
        }
    }

    It 'dispatches cleanup through each receipt-bound helper and records removed state' {
        foreach ($helper in 'Remove-IntuneRemediation.ps1', 'Remove-IntuneAmaApplication.ps1', 'Remove-LiveResponseScript.ps1') {
            @'
param([string]$StatePath, [switch]$RemoveAdopted)
$receipt = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
$receipt.status = 'removed'
$receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatePath -Encoding UTF8
Add-Content -LiteralPath (Join-Path (Split-Path -Parent $StatePath) 'cleanup.log') -Value (Split-Path -Leaf $PSCommandPath)
'@ | Set-Content -LiteralPath (Join-Path $scriptRoot $helper) -Encoding UTF8
        }

        $common = @{
            template = 'azd-sysmon'
            tenantId = '22222222-2222-4222-8222-222222222222'
            environmentName = 'cleanup-test'
            account = 'operator@example.test'
            adoptedExisting = $false
        }
        ($common + @{ objectType = 'intune-device-health-script'; scriptId = '11111111-1111-4111-8111-111111111111'; groupId = '33333333-3333-4333-8333-333333333333'; status = 'assigned' } | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-intune-state.json')
        ($common + @{ objectType = 'intune-windows-msi-application'; applicationId = '44444444-4444-4444-8444-444444444444'; groupId = '33333333-3333-4333-8333-333333333333'; status = 'assigned' } | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-ama-application-state.json')
        ($common + @{ objectType = 'defender-live-response-library-file'; fileName = 'Install-Sysmon.ps1'; fileId = 'file-1'; status = 'published' } | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-live-response-state.json')
        @{
            template = 'azd-sysmon'
            environmentName = 'cleanup-test'
            azureSubscriptionId = '11111111-1111-4111-8111-111111111111'
            azureTenantId = '22222222-2222-4222-8222-222222222222'
            intuneRemediation = $true
            intuneAmaApplication = $true
            liveResponseLibrary = $true
            vmDcrAssociated = $false
            clientAmaTenantScope = $false
            clientAmaAssociationAttempted = $false
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-state.json')

        & $preDown

        $log = Get-Content -LiteralPath (Join-Path $receiptRoot 'cleanup.log')
        $log | Should -Contain 'Remove-IntuneRemediation.ps1'
        $log | Should -Contain 'Remove-IntuneAmaApplication.ps1'
        $log | Should -Contain 'Remove-LiveResponseScript.ps1'
        $state = Get-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-state.json') -Raw | ConvertFrom-Json
        $state.intuneRemediation | Should -BeFalse
        $state.intuneAmaApplication | Should -BeFalse
        $state.liveResponseLibrary | Should -BeFalse
    }

    It 'refuses a VM association receipt that has no VM resource IDs' {
        @{
            template = 'azd-sysmon'
            environmentName = 'cleanup-test'
            azureSubscriptionId = '11111111-1111-4111-8111-111111111111'
            azureTenantId = '22222222-2222-4222-8222-222222222222'
            associationName = 'azd-sysmon-cleanup-test'
            dcrId = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/test/providers/Microsoft.Insights/dataCollectionRules/test'
            vmResourceIds = @()
            vmDcrAssociated = $true
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-state.json')

        { & $preDown } | Should -Throw '*records no VM resource IDs*'
    }

    It 'continues when receipt-bound helpers already recorded removal' {
        foreach ($helper in 'Remove-IntuneRemediation.ps1', 'Remove-IntuneAmaApplication.ps1', 'Remove-LiveResponseScript.ps1') {
            Copy-Item (Join-Path $sourceRoot "scripts/$helper") (Join-Path $scriptRoot $helper)
        }
        @{ template = 'azd-sysmon'; objectType = 'intune-device-health-script'; environmentName = 'cleanup-test'; status = 'removed'; scriptId = '11111111-1111-4111-8111-111111111111' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-intune-state.json')
        @{ template = 'azd-sysmon'; objectType = 'intune-windows-msi-application'; environmentName = 'cleanup-test'; status = 'removed'; applicationId = '44444444-4444-4444-8444-444444444444' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-ama-application-state.json')
        @{ template = 'azd-sysmon'; objectType = 'defender-live-response-library-file'; environmentName = 'cleanup-test'; status = 'removed'; fileName = 'Install-Sysmon.ps1' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-live-response-state.json')
        @{
            template = 'azd-sysmon'
            environmentName = 'cleanup-test'
            intuneRemediation = $false
            intuneAmaApplication = $false
            liveResponseLibrary = $false
            vmDcrAssociated = $false
            clientAmaTenantScope = $false
            clientAmaAssociationAttempted = $false
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-state.json')

        { & $preDown } | Should -Not -Throw
        (Get-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-state.json') -Raw | ConvertFrom-Json).recordedUtc | Should -Not -BeNullOrEmpty
    }

    It 'removes the AZD-owned VM association even when tenant resources are preserved' {
        @'
param(
    [string[]]$VmResourceIds,
    [string]$DcrId,
    [string]$AssociationName,
    [string]$Action
)
@{ vmResourceIds = $VmResourceIds; dcrId = $DcrId; associationName = $AssociationName; action = $Action } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'association-call.json')
'@ | Set-Content -LiteralPath (Join-Path $scriptRoot 'Associate-AzureVmDcr.ps1') -Encoding UTF8
        function az {
            param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
            $global:LASTEXITCODE = 0
            if ($Arguments[0] -eq 'account' -and $Arguments[1] -eq 'show') {
                return '{"id":"11111111-1111-4111-8111-111111111111","tenantId":"22222222-2222-4222-8222-222222222222"}'
            }
            throw "Unexpected Azure CLI call: $($Arguments -join ' ')"
        }
        $env:AZD_SYSMON_PRESERVE_EXTERNAL_RESOURCES = 'true'
        @{
            template = 'azd-sysmon'
            environmentName = 'cleanup-test'
            azureSubscriptionId = '11111111-1111-4111-8111-111111111111'
            azureTenantId = '22222222-2222-4222-8222-222222222222'
            associationName = 'azd-sysmon-cleanup-test'
            dcrId = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/test/providers/Microsoft.Insights/dataCollectionRules/test'
            vmResourceIds = @('/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/test/providers/Microsoft.Compute/virtualMachines/test')
            vmDcrAssociated = $true
            intuneRemediation = $false
            intuneAmaApplication = $false
            liveResponseLibrary = $false
            clientAmaTenantScope = $false
            clientAmaAssociationAttempted = $false
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-state.json')

        try {
            & $preDown

            $call = Get-Content -LiteralPath (Join-Path $root 'association-call.json') -Raw | ConvertFrom-Json
            $call.action | Should -Be 'Remove'
            $state = Get-Content -LiteralPath (Join-Path $receiptRoot 'azd-sysmon-state.json') -Raw | ConvertFrom-Json
            $state.vmDcrAssociated | Should -BeFalse
        } finally {
            Remove-Item -LiteralPath Function:\az -ErrorAction SilentlyContinue
        }
    }

    It 'adds a removed timestamp when an Intune Remediation is already absent' {
        $statePath = Join-Path $receiptRoot 'remediation.json'
        @{
            template = 'azd-sysmon'
            objectType = 'intune-device-health-script'
            scriptId = '11111111-1111-4111-8111-111111111111'
            groupId = '33333333-3333-4333-8333-333333333333'
            tenantId = '22222222-2222-4222-8222-222222222222'
            account = 'operator@example.test'
            environmentName = 'cleanup-test'
            status = 'assigned'
            adoptedExisting = $false
        } | ConvertTo-Json | Set-Content -LiteralPath $statePath
        Mock Import-Module {}
        Mock Connect-AzdGraphSession {}
        Mock Invoke-MgGraphRequest { throw (New-GraphNotFoundException) }

        & (Join-Path $sourceRoot 'scripts/Remove-IntuneRemediation.ps1') -StatePath $statePath

        $receipt = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $receipt.status | Should -Be 'removed'
        $receipt.removedUtc | Should -Not -BeNullOrEmpty
    }

    It 'adds a removed timestamp when an Intune AMA application is already absent' {
        $statePath = Join-Path $receiptRoot 'ama.json'
        @{
            template = 'azd-sysmon'
            objectType = 'intune-windows-msi-application'
            applicationId = '44444444-4444-4444-8444-444444444444'
            groupId = '33333333-3333-4333-8333-333333333333'
            tenantId = '22222222-2222-4222-8222-222222222222'
            account = 'operator@example.test'
            environmentName = 'cleanup-test'
            status = 'assigned'
            adoptedExisting = $false
        } | ConvertTo-Json | Set-Content -LiteralPath $statePath
        Mock Import-Module {}
        Mock Connect-AzdGraphSession {}
        Mock Invoke-MgGraphRequest { throw (New-GraphNotFoundException) }

        & (Join-Path $sourceRoot 'scripts/Remove-IntuneAmaApplication.ps1') -StatePath $statePath

        $receipt = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $receipt.status | Should -Be 'removed'
        $receipt.removedUtc | Should -Not -BeNullOrEmpty
    }

    It 'deletes an owned Intune AMA application through the device app management endpoint' {
        $statePath = Join-Path $receiptRoot 'ama.json'
        $applicationId = '44444444-4444-4444-8444-444444444444'
        $groupId = '33333333-3333-4333-8333-333333333333'
        @{
            template = 'azd-sysmon'
            objectType = 'intune-windows-msi-application'
            applicationId = $applicationId
            groupId = $groupId
            tenantId = '22222222-2222-4222-8222-222222222222'
            account = 'operator@example.test'
            environmentName = 'cleanup-test'
            status = 'assigned'
            adoptedExisting = $false
        } | ConvertTo-Json | Set-Content -LiteralPath $statePath
        Mock Import-Module {}
        Mock Connect-AzdGraphSession {}
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'GET' -and $Uri -match '/deviceAppManagement/mobileApps/[^/]+$') {
                return @{ '@odata.type' = '#microsoft.graph.windowsMobileMSI'; displayName = 'Azure Monitor Agent (azd-sysmon)'; description = 'Managed by azd-sysmon. The package is an SHA-256-pinned Microsoft Azure Monitor Agent Windows client MSI.' }
            }
            if ($Method -eq 'GET' -and $Uri -match '/assignments\?\$top=100$') {
                return @{ value = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $groupId } }) }
            }
            if ($Method -eq 'DELETE') { return @{} }
            throw "Unexpected Graph request: $Method $Uri"
        }

        & (Join-Path $sourceRoot 'scripts/Remove-IntuneAmaApplication.ps1') -StatePath $statePath

        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' -and $Uri -eq "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/$applicationId" }
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' -and $Uri -eq "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/$applicationId/assignments?`$top=100" }
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Uri -eq "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/$applicationId" }
        (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).status | Should -Be 'removed'
    }
}
