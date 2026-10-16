#requires -Version 7.6
Describe 'VM DCR association request binding' {
    BeforeAll {
        $helper = Join-Path $PSScriptRoot '../scripts/Associate-AzureVmDcr.ps1'
        function az { param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments) throw 'Unmocked CLI call.' }
    }
    It 'preserves the exact association name and API query for <Action>' -ForEach @(
        @{ Action = 'Ensure'; Method = 'put' }
        @{ Action = 'Remove'; Method = 'delete' }
    ) {
        Mock az { $global:LASTEXITCODE = 0; '{}' }
        $vm = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/fixture'
        $dcr = '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/fixture/providers/Microsoft.Insights/dataCollectionRules/fixture'
        $expectedUri = "https://management.azure.com$vm/providers/Microsoft.Insights/dataCollectionRuleAssociations/azd-sysmon-fixture?api-version=2022-06-01"

        & $helper -VmResourceIds $vm -DcrId $dcr -AssociationName azd-sysmon-fixture -Action $Action

        Should -Invoke az -Exactly -Times 1 -ParameterFilter {
            $Arguments[0] -eq 'rest' -and $Arguments -contains '--url' -and
            $Arguments -contains $expectedUri -and $Arguments -contains '--method' -and $Arguments -contains $Method
        }
    }
}
