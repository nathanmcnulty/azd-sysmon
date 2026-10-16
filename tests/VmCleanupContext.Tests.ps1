#requires -Version 7.6
Describe 'VM cleanup selected context' {
    BeforeAll {
        $sourceRoot = Split-Path $PSScriptRoot -Parent
        function az { param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments) throw 'Unmocked Azure CLI call.' }
        function azd { param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments) throw 'Unmocked azd call.' }
    }
    BeforeEach {
        $saved = @{}
        Get-ChildItem Env: | Where-Object Name -Match '^AZURE_|^AZD_SYSMON_' | ForEach-Object {
            $saved[$_.Name] = $_.Value
            [Environment]::SetEnvironmentVariable($_.Name, $null, 'Process')
        }
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $scripts = Join-Path $root 'scripts'
        $receiptRoot = Join-Path $root '.azure/vm-context'
        New-Item -ItemType Directory -Path $scripts, $receiptRoot -Force | Out-Null
        Copy-Item (Join-Path $sourceRoot 'scripts/Pre-Down.ps1'), (Join-Path $sourceRoot 'scripts/Azd.Receipt.ps1') -Destination $scripts
        @'
param($VmResourceIds, $DcrId, $AssociationName, $Action)
if ($Action -cne 'Remove') { throw 'Unexpected fixture action.' }
Set-Content (Join-Path $PSScriptRoot 'delete-called') -Value yes
'@ | Set-Content (Join-Path $scripts 'Associate-AzureVmDcr.ps1')
        $env:AZURE_ENV_NAME = 'vm-context'
        $env:AZURE_SUBSCRIPTION_ID = '11111111-1111-4111-8111-111111111111'
        $env:AZURE_TENANT_ID = '22222222-2222-4222-8222-222222222222'
        foreach ($key in 'PRESERVE_EXTERNAL_RESOURCES','REMOVE_ADOPTED_EXTERNAL_RESOURCES','REMOVE_CLIENT_AMA_ASSOCIATION') {
            [Environment]::SetEnvironmentVariable("AZD_SYSMON_$key", 'false', 'Process')
        }
        Mock azd { $global:LASTEXITCODE = 1; $null }
        $env:AZD_SYSMON_FIXTURE_RETURNED_SUB = $env:AZURE_SUBSCRIPTION_ID
        $env:AZD_SYSMON_FIXTURE_RETURNED_TENANT = $env:AZURE_TENANT_ID
        $env:AZD_SYSMON_FIXTURE_RETURNED_CLOUD = 'AzureCloud'
        Mock az {
            if ($Arguments[0] -ne 'account' -or $Arguments[1] -ne 'show') { throw 'Unexpected CLI operation.' }
            $global:LASTEXITCODE = 0
            if ($Arguments -contains '--subscription') {
                return (@{ id = $env:AZD_SYSMON_FIXTURE_RETURNED_SUB; tenantId = $env:AZD_SYSMON_FIXTURE_RETURNED_TENANT; environmentName = $env:AZD_SYSMON_FIXTURE_RETURNED_CLOUD } | ConvertTo-Json)
            }
            # A different global default must never choose the cleanup target.
            return (@{ id = '33333333-3333-4333-8333-333333333333'; tenantId = $env:AZD_SYSMON_FIXTURE_RETURNED_TENANT } | ConvertTo-Json)
        }
        $state = @{
            template = 'azd-sysmon'; environmentName = 'vm-context'
            azureSubscriptionId = $env:AZURE_SUBSCRIPTION_ID; azureTenantId = $env:AZURE_TENANT_ID
            associationName = 'azd-sysmon-vm-context'
            dcrId = "/subscriptions/$($env:AZURE_SUBSCRIPTION_ID)/resourceGroups/fixture/providers/Microsoft.Insights/dataCollectionRules/fixture"
            vmResourceIds = @("/subscriptions/$($env:AZURE_SUBSCRIPTION_ID)/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/fixture")
            vmDcrAssociated = $true; clientAmaTenantScope = $false; clientAmaAssociationAttempted = $false
            intuneRemediation = $false; intuneAmaApplication = $false; liveResponseLibrary = $false
        }
        $receiptPath = Join-Path $receiptRoot 'azd-sysmon-state.json'
        $preDown = Join-Path $scripts 'Pre-Down.ps1'
        $marker = Join-Path $scripts 'delete-called'
    }
    AfterEach {
        Get-ChildItem Env: | Where-Object Name -Match '^AZURE_|^AZD_SYSMON_' | ForEach-Object { [Environment]::SetEnvironmentVariable($_.Name, $null, 'Process') }
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    }
    It 'removes the receipt-bound association when the global default is another subscription' {
        $state | ConvertTo-Json | Set-Content $receiptPath
        { & $preDown } | Should -Not -Throw
        Test-Path $marker | Should -BeTrue
        (Get-Content $receiptPath -Raw | ConvertFrom-Json).vmDcrAssociated | Should -BeFalse
        Should -Invoke az -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'account' -and $Arguments[1] -eq 'show' -and
            $Arguments -contains '--subscription' -and $Arguments -contains '11111111-1111-4111-8111-111111111111'
        }
    }
    It 'refuses <Case> before dispatching association deletion' -ForEach @(
        @{ Case = 'selected subscription mismatch'; Mode = 'selectedSub' }
        @{ Case = 'selected tenant mismatch'; Mode = 'selectedTenant' }
        @{ Case = 'missing selected subscription'; Mode = 'missingSub' }
        @{ Case = 'returned subscription mismatch'; Mode = 'returnedSub' }
        @{ Case = 'returned tenant mismatch'; Mode = 'returnedTenant' }
        @{ Case = 'returned cloud mismatch'; Mode = 'cloud' }
        @{ Case = 'foreign DCR subscription'; Mode = 'dcr' }
        @{ Case = 'foreign VM subscription'; Mode = 'vm' }
    ) {
        $other = '33333333-3333-4333-8333-333333333333'
        switch ($Mode) {
            selectedSub { $env:AZURE_SUBSCRIPTION_ID = $other }
            selectedTenant { $env:AZURE_TENANT_ID = $other }
            missingSub { $env:AZURE_SUBSCRIPTION_ID = '' }
            returnedSub { $env:AZD_SYSMON_FIXTURE_RETURNED_SUB = $other }
            returnedTenant { $env:AZD_SYSMON_FIXTURE_RETURNED_TENANT = $other }
            cloud { $env:AZD_SYSMON_FIXTURE_RETURNED_CLOUD = 'AzureUSGovernment' }
            dcr { $state.dcrId = $state.dcrId.Replace($state.azureSubscriptionId, $other) }
            vm { $state.vmResourceIds = @($state.vmResourceIds[0].Replace($state.azureSubscriptionId, $other)) }
        }
        $state | ConvertTo-Json | Set-Content $receiptPath
        { & $preDown } | Should -Throw
        Test-Path $marker | Should -BeFalse
        (Get-Content $receiptPath -Raw | ConvertFrom-Json).vmDcrAssociated | Should -BeTrue
    }
}
