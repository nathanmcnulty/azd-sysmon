BeforeAll {
    $sourceRoot = Split-Path -Parent $PSScriptRoot
    function az { param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments) }
    function azd { param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments) }
    function Get-AzResourceProvider {}
    function Get-AzRoleDefinition {}
    function Get-AzContext {}
    function Get-AzSubscription {}
    function Set-AzContext {}
    function Invoke-AzRestMethod {}
    if (-not ('AzdSysmonTest.FixedResponseHandler' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
namespace AzdSysmonTest {
    public sealed class FixedResponseHandler : HttpMessageHandler {
        public string Body;
        public int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) {
            Calls++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(Body) });
        }
    }
}
'@
    }
}

Describe 'Azure VM deployment result validation' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path "$root/scripts", "$root/config", "$root/deploy/azure-vm" -Force | Out-Null
        Copy-Item "$sourceRoot/scripts/Deploy-AzureVmSysmon.ps1" "$root/scripts/"
        Copy-Item "$sourceRoot/scripts/Install-AzureVmAma.ps1" "$root/scripts/"
        Copy-Item "$sourceRoot/config/generated-package-manifest.json" "$root/config/"
        Copy-Item "$sourceRoot/deploy/azure-vm/Install-Sysmon.ps1" "$root/deploy/azure-vm/"
        $script:deploy = "$root/scripts/Deploy-AzureVmSysmon.ps1"
        $script:installAma = "$root/scripts/Install-AzureVmAma.ps1"
        $script:vmId = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/test/providers/Microsoft.Compute/virtualMachines/test'
        Mock az { $global:LASTEXITCODE = 0; '{"value":[{"code":"ComponentStatus/StdOut/succeeded","level":"Info","displayStatus":"Provisioning succeeded","message":"[azd-sysmon] Sysmon is installed and Microsoft-Windows-Sysmon/Operational is available."}]}' }
    }

    It 'accepts an explicit successful guest Run Command result' {
        { & $deploy -VmResourceIds $vmId } | Should -Not -Throw
    }

    It 'rejects a guest result that reports an execution failure despite a successful CLI process' {
        Mock az {
            $global:LASTEXITCODE = 0
            '{"value":[{"code":"ComponentStatus/StdErr/failed","level":"Error","displayStatus":"Provisioning failed","message":"installer failed"}]}'
        }
        { & $deploy -VmResourceIds $vmId } | Should -Throw '*guest execution failed*'
    }

    It 'rejects a Run Command response without a guest success status' {
        Mock az { $global:LASTEXITCODE = 0; '{"value":[]}' }
        { & $deploy -VmResourceIds $vmId } | Should -Throw '*no guest status*'
    }

    It 'rejects nonempty guest stderr even when Run Command labels the stderr status as succeeded' {
        Mock az {
            $global:LASTEXITCODE = 0
            '{"value":[{"code":"ComponentStatus/StdOut/succeeded","level":"Info","displayStatus":"Provisioning succeeded","message":"[azd-sysmon] Sysmon is installed and Microsoft-Windows-Sysmon/Operational is available."},{"code":"ComponentStatus/StdErr/succeeded","level":"Info","displayStatus":"Provisioning succeeded","message":"Sysmon returned exit code 1."}]}'
        }
        { & $deploy -VmResourceIds $vmId } | Should -Throw '*stderr was not empty*'
    }

    It 'rejects a transport-success stdout result without the installer success marker' {
        Mock az {
            $global:LASTEXITCODE = 0
            '{"value":[{"code":"ComponentStatus/StdOut/succeeded","level":"Info","displayStatus":"Provisioning succeeded","message":"Command completed."}]}'
        }
        { & $deploy -VmResourceIds $vmId } | Should -Throw '*installer success marker*'
    }

    It 'rejects an AMA extension result without successful provisioning and automatic upgrade' {
        Mock az { $global:LASTEXITCODE = 0; '{"provisioningState":"Failed","enableAutomaticUpgrade":false}' }
        { & $installAma -VmResourceIds $vmId } | Should -Throw '*was not ready*'
    }
}

Describe 'Environment-specific deployment receipts' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path "$root/scripts" -Force | Out-Null
        Copy-Item "$sourceRoot/scripts/Post-Provision.ps1" "$root/scripts/"
        Copy-Item "$sourceRoot/scripts/Pre-Down.ps1" "$root/scripts/"
        $script:post = "$root/scripts/Post-Provision.ps1"
        $script:preDown = "$root/scripts/Pre-Down.ps1"
        $script:saved = @{}
        Get-ChildItem Env: | Where-Object { $_.Name -match '^AZD_SYSMON_|^AZURE_' } | ForEach-Object {
            $saved[$_.Name] = $_.Value
            [Environment]::SetEnvironmentVariable($_.Name, $null, 'Process')
        }
        $env:AZURE_ENV_NAME = 'isolated-review'
        Mock azd { $global:LASTEXITCODE = 0 }
    }

    AfterEach {
        Get-ChildItem Env: | Where-Object { $_.Name -match '^AZD_SYSMON_|^AZURE_' } | ForEach-Object {
            [Environment]::SetEnvironmentVariable($_.Name, $null, 'Process')
        }
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    }

    It 'writes a receipt under the selected AZD environment even when no optional target is selected' {
        & $post
        $receipt = Join-Path $root '.azure/isolated-review/azd-sysmon-state.json'
        Test-Path -LiteralPath $receipt -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json).environmentName | Should -Be 'isolated-review'
    }

    It 'preserves a prior client AMA cleanup receipt when a later run disables the setting' {
        $receiptDir = Join-Path $root '.azure/isolated-review'
        New-Item -ItemType Directory -Path $receiptDir -Force | Out-Null
        @{
            template = 'azd-sysmon'
            environmentName = 'isolated-review'
            azureSubscriptionId = '11111111-1111-4111-8111-111111111111'
            azureTenantId = '22222222-2222-4222-8222-222222222222'
            clientAmaTenantScope = $true
            clientAmaAssociationAttempted = $true
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $receiptDir 'azd-sysmon-state.json')
        & $post
        $state = Get-Content -LiteralPath (Join-Path $receiptDir 'azd-sysmon-state.json') -Raw | ConvertFrom-Json
        $state.clientAmaTenantScope | Should -BeTrue
        $state.clientAmaAssociationAttempted | Should -BeTrue
    }

    It 'invokes the tenant-wide helper with explicit bindings and records a successful association' {
        @'
param(
    [string]$Action,
    [string]$AssociationName,
    [string]$DcrId,
    [string]$DcrLocation,
    [string]$TenantId,
    [string]$SubscriptionId,
    [switch]$ConfirmTenantWideScope
)
@{
    action = $Action
    associationName = $AssociationName
    dcrId = $DcrId
    dcrLocation = $DcrLocation
    tenantId = $TenantId
    subscriptionId = $SubscriptionId
    confirmed = [bool]$ConfirmTenantWideScope
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'client-ama-call.json')
'@ | Set-Content -LiteralPath (Join-Path $root 'scripts/Set-ClientAmaScope.ps1')
        $env:AZURE_SUBSCRIPTION_ID = '11111111-1111-4111-8111-111111111111'
        $env:AZURE_TENANT_ID = '22222222-2222-4222-8222-222222222222'
        $env:AZURE_RESOURCE_GROUP = 'test-rg'
        $env:AZURE_LOCATION = 'westus'
        $env:AZD_SYSMON_DCR_NAME = 'test-dcr'
        $env:AZD_SYSMON_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/test-rg/providers/Microsoft.OperationalInsights/workspaces/test'
        $env:AZD_SYSMON_CLIENT_AMA_TENANT_SCOPE = 'true'
        $env:AZD_SYSMON_CONFIRM_TENANT_SCOPE = 'I_UNDERSTAND_TENANT_WIDE_SCOPE'
        Mock az {
            $global:LASTEXITCODE = 0
            if ($Arguments -contains 'resource') {
                return '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/test-rg/providers/Microsoft.Insights/dataCollectionRules/test-dcr'
            }
            throw "Unexpected Azure CLI call: $($Arguments -join ' ')"
        }

        & $post

        $call = Get-Content -LiteralPath (Join-Path $root 'scripts/client-ama-call.json') -Raw | ConvertFrom-Json
        $call.action | Should -Be 'Ensure'
        $call.tenantId | Should -Be $env:AZURE_TENANT_ID
        $call.subscriptionId | Should -Be $env:AZURE_SUBSCRIPTION_ID
        $call.dcrId | Should -Be '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/test-rg/providers/Microsoft.Insights/dataCollectionRules/test-dcr'
        $call.confirmed | Should -BeTrue
        $state = Get-Content -LiteralPath (Join-Path $root '.azure/isolated-review/azd-sysmon-state.json') -Raw | ConvertFrom-Json
        $state.clientAmaAssociationAttempted | Should -BeTrue
        $state.clientAmaTenantScope | Should -BeTrue
    }

    It 'rejects a receipt whose environment does not match the current azd environment before cleanup' {
        $receiptDir = Join-Path $root '.azure/isolated-review'
        New-Item -ItemType Directory -Path $receiptDir -Force | Out-Null
        @{ template = 'azd-sysmon'; environmentName = 'another-environment' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $receiptDir 'azd-sysmon-state.json')
        { & $preDown } | Should -Throw '*does not belong to the selected AZD environment*'
    }
}

Describe 'Client AMA tenant binding' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path "$root/scripts" -Force | Out-Null
        Copy-Item "$sourceRoot/scripts/Set-ClientAmaScope.ps1" "$root/scripts/"
        $script:clientEntry = "$root/scripts/Set-ClientAmaScope.ps1"
        $script:tenant = '22222222-2222-4222-8222-222222222222'
        $script:subscription = '11111111-1111-4111-8111-111111111111'
        $script:dcr = "/subscriptions/$subscription/resourceGroups/test/providers/Microsoft.Insights/dataCollectionRules/test"
        Mock az {
            $global:LASTEXITCODE = 0
            if ($Arguments[0] -eq 'account' -and $Arguments[1] -eq 'show') {
                return '{"id":"11111111-1111-4111-8111-111111111111","tenantId":"22222222-2222-4222-8222-222222222222","environmentName":"AzureCloud"}'
            }
            if ($Arguments[0] -eq 'account' -and $Arguments[1] -eq 'get-access-token') {
                if ($Arguments -contains '--tenant') { throw 'Azure CLI must not combine --tenant and --subscription for token acquisition.' }
                return '{"accessToken":"test-token","tenant":"22222222-2222-4222-8222-222222222222"}'
            }
            if ($Arguments[0] -eq 'provider' -and $Arguments[1] -eq 'show') {
                return '{"resourceTypes":[{"resourceType":"monitoredObjects","apiVersions":["2024-01-01-preview"]},{"resourceType":"dataCollectionRuleAssociations","apiVersions":["2024-01-01-preview"]}]}'
            }
            throw "Unexpected Azure CLI call: $($Arguments -join ' ')"
        }
    }

    It 'rejects a DCR subscription that differs from the selected context before loading Azure modules' {
        { & $clientEntry -Action Ensure -AssociationName test -DcrId $dcr -DcrLocation westus -TenantId $tenant -SubscriptionId '33333333-3333-4333-8333-333333333333' -ConfirmTenantWideScope } | Should -Throw '*does not match the DCR subscription*'
    }

    It 'rejects removal without an explicit tenant and subscription receipt binding' {
        { & $clientEntry -Action Remove -AssociationName test -ConfirmTenantWideScope } | Should -Throw '*SubscriptionId must be the intended*'
    }

    It 'fails closed when Azure Resource Manager returns an error status without throwing' {
        Mock Invoke-RestMethod { [pscustomobject]@{ StatusCode = 500; Content = '{"error":"server"}' } }
        { & $clientEntry -Action Ensure -AssociationName test -DcrId $dcr -DcrLocation westus -TenantId $tenant -SubscriptionId $subscription -ConfirmTenantWideScope } | Should -Throw '*HTTP 500*'
    }

    It 'binds the Azure CLI account to the requested tenant before acquiring a token' {
        Mock Invoke-RestMethod { throw 'The ARM request must not be reached.' }
        Mock az {
            $global:LASTEXITCODE = 0
            if ($Arguments[0] -eq 'account' -and $Arguments[1] -eq 'show') {
                return '{"id":"11111111-1111-4111-8111-111111111111","tenantId":"33333333-3333-4333-8333-333333333333","environmentName":"AzureCloud"}'
            }
            throw 'The token request must not be reached.'
        }
        { & $clientEntry -Action Ensure -AssociationName test -DcrId $dcr -DcrLocation westus -TenantId $tenant -SubscriptionId $subscription -ConfirmTenantWideScope } | Should -Throw '*belongs to tenant*'
        Should -Invoke az -Times 1 -Exactly
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'refuses an existing same-name association that points to another DCR' {
        Mock Invoke-RestMethod {
            if ($Uri -match 'monitoredObjects/.+\?') {
                return [pscustomobject]@{ StatusCode = 200; properties = @{ location = 'westus' } }
            }
            [pscustomobject]@{ StatusCode = 200; properties = @{ dataCollectionRuleId = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/test/providers/Microsoft.Insights/dataCollectionRules/other' } }
        }
        { & $clientEntry -Action Ensure -AssociationName test -DcrId $dcr -DcrLocation westus -TenantId $tenant -SubscriptionId $subscription -ConfirmTenantWideScope } | Should -Throw '*ownership collision*'
        Should -Invoke Invoke-RestMethod -Times 0 -ParameterFilter { $Method -eq 'PUT' }
    }
}

Describe 'MDE library publishing boundaries' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path "$root/scripts", "$root/deploy/live-response" -Force | Out-Null
        Copy-Item "$sourceRoot/scripts/Publish-LiveResponseScript.ps1" "$root/scripts/"
        Set-Content -LiteralPath "$root/deploy/live-response/Install-Sysmon.ps1" -Value 'Write-Output test'
        $script:entry = "$root/scripts/Publish-LiveResponseScript.ps1"
        $script:scriptPath = "$root/deploy/live-response/Install-Sysmon.ps1"
    }

    It 'rejects an MDE publication without an explicitly selected administrator account before acquiring a token' {
        Mock az { throw 'Azure CLI should not be called' }
        { & $entry -ScriptPath $scriptPath -ExpectedTenantId '22222222-2222-4222-8222-222222222222' } | Should -Throw '*AZD_SYSMON_MDE_ACCOUNT*'
        Should -Invoke az -Times 0 -Exactly
    }

    It 'rejects a mismatched cached Azure CLI account before acquiring a Defender token' {
        Mock az { $global:LASTEXITCODE = 0; '{"tenantId":"22222222-2222-4222-8222-222222222222","user":"other@example.com"}' }
        { & $entry -ScriptPath $scriptPath -ExpectedTenantId '22222222-2222-4222-8222-222222222222' -ExpectedAccount 'admin@example.com' } | Should -Throw '*not the explicitly selected MDE account*'
        Should -Invoke az -Times 1 -Exactly
    }

    It 'refuses to overwrite a library filename that is not marked as template-owned' {
        Mock az {
            $global:LASTEXITCODE = 0
            if ($Arguments -contains 'show') { return '{"tenantId":"22222222-2222-4222-8222-222222222222","user":"admin@example.com"}' }
            return 'token'
        }
        $handler = [AzdSysmonTest.FixedResponseHandler]::new()
        $handler.Body = '{"value":[{"fileName":"Install-Sysmon.ps1","description":"another deployment"}]}'
        $client = [System.Net.Http.HttpClient]::new($handler)
        try {
            { & $entry -ScriptPath $scriptPath -ExpectedTenantId '22222222-2222-4222-8222-222222222222' -ExpectedAccount 'admin@example.com' -HttpClient $client } | Should -Throw '*not marked as owned*'
            $handler.Calls | Should -Be 1
        } finally {
            $client.Dispose()
            $handler.Dispose()
        }
    }
}
