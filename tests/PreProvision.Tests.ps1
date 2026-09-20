BeforeAll {
    $script:preProvision = Join-Path $PSScriptRoot '../scripts/Pre-Provision.ps1'
    function az { param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments) }
    function azd { param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments) }
}
Describe 'Pre-provision target validation' {
    BeforeEach {
        $script:saved = @{}
        Get-ChildItem Env: | Where-Object { $_.Name -match '^AZD_SYSMON_|^AZURE_' } | ForEach-Object {
            $saved[$_.Name] = $_.Value
            [Environment]::SetEnvironmentVariable($_.Name, $null, 'Process')
        }
        Mock azd { $global:LASTEXITCODE = 0 }
        Mock az {
            $global:LASTEXITCODE = 0
            '{"tenantId":"22222222-2222-4222-8222-222222222222","environmentName":"AzureCloud"}'
        }
    }
    AfterEach {
        Get-ChildItem Env: | Where-Object { $_.Name -match '^AZD_SYSMON_|^AZURE_' } | ForEach-Object {
            [Environment]::SetEnvironmentVariable($_.Name, $null, 'Process')
        }
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    }
    It 'does not call Azure when no external targets are selected' {
        & $preProvision
        Should -Invoke az -Times 0 -Exactly
    }
    It 'rejects tenant-wide AMA without the exact confirmation' {
        $env:AZD_SYSMON_CLIENT_AMA_TENANT_SCOPE = 'true'
        $env:AZD_SYSMON_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test'
        { & $preProvision } | Should -Throw '*Refusing tenant-wide*'
        Should -Invoke az -Times 0 -Exactly
    }
    It 'rejects an Intune run without the selected administrator account' {
        $env:AZD_SYSMON_DEPLOY_INTUNE = 'true'
        $env:AZD_SYSMON_INTUNE_GROUP_ID = '11111111-1111-4111-8111-111111111111'
        { & $preProvision } | Should -Throw '*AZD_SYSMON_GRAPH_ACCOUNT*'
    }
    It 'rejects a cached subscription in another tenant' {
        $env:AZURE_SUBSCRIPTION_ID = '11111111-1111-4111-8111-111111111111'
        $env:AZURE_TENANT_ID = '33333333-3333-4333-8333-333333333333'
        $env:AZD_SYSMON_PUBLISH_LIVE_RESPONSE_LIBRARY = 'true'
        $env:AZD_SYSMON_MDE_ACCOUNT = 'admin@example.com'
        { & $preProvision } | Should -Throw '*does not match*'
    }
    It 'rejects a VM outside the deployment subscription' {
        $env:AZURE_SUBSCRIPTION_ID = '11111111-1111-4111-8111-111111111111'
        $env:AZD_SYSMON_AZURE_VM_RESOURCE_IDS = '/subscriptions/33333333-3333-4333-8333-333333333333/resourceGroups/test/providers/Microsoft.Compute/virtualMachines/test'
        { & $preProvision } | Should -Throw '*Cross-subscription*'
    }
}
