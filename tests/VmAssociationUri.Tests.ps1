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
    BeforeEach {
        $savedBodyPath = $env:AZD_TEST_VM_DCR_BODY_PATH
    }
    AfterEach {
        $env:AZD_TEST_VM_DCR_BODY_PATH = $savedBodyPath
    }
    It 'passes intact JSON through a temporary file and removes it after CLI exit <Code>' -ForEach @(
        @{ Code = 0 }; @{ Code = 1 }
    ) {
        $env:AZD_TEST_VM_DCR_EXIT_CODE = [string]$Code
        try {
            Mock az {
                $bodyArgument = $Arguments[[Array]::IndexOf($Arguments, '--body') + 1]
                $bodyArgument | Should -Match '^@'
                $env:AZD_TEST_VM_DCR_BODY_PATH = $bodyArgument.Substring(1)
                $payload = Get-Content -LiteralPath $env:AZD_TEST_VM_DCR_BODY_PATH -Raw | ConvertFrom-Json
                $payload.properties.dataCollectionRuleId | Should -Be '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/fixture/providers/Microsoft.Insights/dataCollectionRules/fixture'
                $Arguments | Should -Contain 'Content-Type=application/json'
                $global:LASTEXITCODE = [int]$env:AZD_TEST_VM_DCR_EXIT_CODE
                '{}'
            }
            $invoke = {
                & $helper -VmResourceIds '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/fixture' -DcrId '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/fixture/providers/Microsoft.Insights/dataCollectionRules/fixture' -AssociationName azd-sysmon-fixture
            }
            if ($Code -eq 0) { & $invoke } else { $invoke | Should -Throw '*DCR association failed*' }
            $env:AZD_TEST_VM_DCR_BODY_PATH | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $env:AZD_TEST_VM_DCR_BODY_PATH | Should -BeFalse
            Should -Invoke az -Exactly -Times 1
        } finally {
            Remove-Item Env:AZD_TEST_VM_DCR_EXIT_CODE
        }
    }
}
