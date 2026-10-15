#requires -Version 7.6
BeforeAll {
    $sourceRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $sourceRoot 'scripts/vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psd1') -Force
    Import-Module (Join-Path $sourceRoot 'scripts/Sysmon.ArtifactValidation.psm1') -Force
    . (Join-Path $sourceRoot 'scripts/Azd.Receipt.ps1')
    # Only the actual local receipt constructor, never the mutating publisher.
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $sourceRoot 'scripts/Deploy-IntuneRemediation.ps1'), [ref]$null, [ref]$null)
    $constructor = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Write-IntuneState' }, $true)
    . ([scriptblock]::Create($constructor.Extent.Text))
    function Write-FixtureTarget {
        $target.artifactHashes = @{}
        foreach ($name in @('azd-sysmon-state.json','azd-sysmon-intune-state.json','azd-sysmon-ama-application-state.json','azd-sysmon-live-response-state.json')) {
            $path = Join-Path $artifactRoot $name
            if (Test-Path -LiteralPath $path) { $target.artifactHashes[$name] = (Get-FileHash $path).Hash.ToLowerInvariant() }
        }
        $target | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $artifactRoot 'target.json') -Encoding utf8NoBOM
    }
    function Read-Report { & (Join-Path $sourceRoot 'scripts/Test-DeploymentArtifacts.ps1') -ArtifactRoot $artifactRoot }
}
Describe 'Actual artifact CLI and canonical report integration' {
    BeforeEach {
        $templateRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $EnvironmentName = 'fixture'
        $artifactRoot = Join-Path $templateRoot '.azure/fixture'
        $null = New-Item -ItemType Directory -Path $artifactRoot -Force
        $TenantId = '11111111-1111-4111-8111-111111111111'
        $subscription = '22222222-2222-4222-8222-222222222222'
        $ExpectedAccount = 'operator@example.invalid'
        $GroupId = '33333333-3333-4333-8333-333333333333'
        $Configuration = 'balanced'
        $target = @{schemaVersion='1.0';environmentName=$EnvironmentName;tenantId=$TenantId;subscriptionId=$subscription;graphAccount=$ExpectedAccount;mdeAccount=$ExpectedAccount;paths=@('package','intune','azureVm','sentinel','liveResponse');artifactHashes=@{}}
        $state = @{
            template='azd-sysmon';environmentName=$EnvironmentName;azureSubscriptionId=$subscription;azureTenantId=$TenantId
            intuneRemediation=$true;intuneAmaApplication=$true;liveResponseLibrary=$true
            vmSysmonAttempted=$true;vmAmaInstalled=$true;vmDcrAssociated=$true
            vmResourceIds=@("/subscriptions/$subscription/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/fixture")
            dcrId="/subscriptions/$subscription/resourceGroups/fixture/providers/Microsoft.Insights/dataCollectionRules/fixture"
            recordedUtc=[DateTimeOffset]::UtcNow.ToString('o')
        }
        Write-AzdJsonReceipt -Path (Join-Path $artifactRoot 'azd-sysmon-state.json') -InputObject $state
        Write-IntuneState -ScriptId '44444444-4444-4444-8444-444444444444' -Status assigned -AdoptedExisting $false
        $ama = @{template='azd-sysmon';objectType='intune-windows-msi-application';environmentName=$EnvironmentName;tenantId=$TenantId;account=$ExpectedAccount;applicationId='55555555-5555-4555-8555-555555555555';groupId=$GroupId;adoptedExisting=$false;status='assigned';recordedUtc=[DateTimeOffset]::UtcNow.ToString('o')}
        Write-AzdJsonReceipt -Path (Join-Path $artifactRoot 'azd-sysmon-ama-application-state.json') -InputObject $ama
        $library = @{template='azd-sysmon';objectType='defender-live-response-library-file';environmentName=$EnvironmentName;tenantId=$TenantId;account=$ExpectedAccount;fileId=$null;fileName='Install-Sysmon.ps1';adoptedExisting=$false;status='published';recordedUtc=[DateTimeOffset]::UtcNow.ToString('o')}
        Write-AzdJsonReceipt -Path (Join-Path $artifactRoot 'azd-sysmon-live-response-state.json') -InputObject $library
        Write-FixtureTarget
    }
    It 'reads the actual producer receipt and emits ten schema-valid independent checks' {
        $report = Read-Report
        $report.checks.Count | Should -Be 10
        ($report | ConvertTo-Json -Depth 30 | Test-Json -SchemaFile (Join-Path $sourceRoot 'scripts/vendor/Azd.DeploymentValidation/deployment-validation.schema.json')) | Should -BeTrue
        ($report.checks | Where-Object id -ceq 'package.artifact').status | Should -BeExactly 'pass'
        foreach ($path in @('intune','azurevm','sentinel','liveresponse')) { ($report.checks | Where-Object id -ceq "$path.artifact").status | Should -BeExactly 'info' }
        @($report.checks | Where-Object { $_.id.EndsWith('.endpoint') -and $_.status -ceq 'warning' }).Count | Should -Be 5
        $report.outcome | Should -BeExactly 'passedWithWarnings'
        $report.environment.metadata.notCleanupAuthority | Should -BeTrue
    }
    It 'does not write legacy receipts or recover a previous receipt' {
        $before=(Get-FileHash (Join-Path $artifactRoot 'azd-sysmon-intune-state.json')).Hash
        $null=Read-Report
        (Get-FileHash (Join-Path $artifactRoot 'azd-sysmon-intune-state.json')).Hash|Should -BeExactly $before
        Test-Path (Join-Path $artifactRoot 'azd-sysmon-intune-state.json.previous')|Should -BeFalse
    }
    It 'plans without reading receipts or packages' {
        Mock Read-SysmonArtifact -ModuleName Sysmon.ArtifactValidation {
            param($Root,$Name)
            if($Name -ceq 'target.json'){return @{value=$target;hash='0'*64}}
            throw 'ARTIFACT_READ_FORBIDDEN'
        }
        $report=New-SysmonArtifactReport -ArtifactRoot $artifactRoot -Plan
        @($report.checks|Where-Object status -ceq 'planned').Count|Should -Be 10
        Should -Invoke Read-SysmonArtifact -ModuleName Sysmon.ArtifactValidation -Times 0 -ParameterFilter {$Name -ne 'target.json'}
    }
    It 'performs both modes with zero external dispatch' {
        Mock az -ModuleName Sysmon.ArtifactValidation {throw 'EXTERNAL_DISPATCH_FORBIDDEN'}
        Mock Invoke-RestMethod -ModuleName Sysmon.ArtifactValidation {throw 'EXTERNAL_DISPATCH_FORBIDDEN'}
        Mock Invoke-WebRequest -ModuleName Sysmon.ArtifactValidation {throw 'EXTERNAL_DISPATCH_FORBIDDEN'}
        Mock Start-Process -ModuleName Sysmon.ArtifactValidation {throw 'EXTERNAL_DISPATCH_FORBIDDEN'}
        $verified=New-SysmonArtifactReport -ArtifactRoot $artifactRoot
        $planned=New-SysmonArtifactReport -ArtifactRoot $artifactRoot -Plan
        $verified.checks.Count|Should -Be 10
        $planned.checks.Count|Should -Be 10
        Should -Invoke az -ModuleName Sysmon.ArtifactValidation -Times 0
        Should -Invoke Invoke-RestMethod -ModuleName Sysmon.ArtifactValidation -Times 0
        Should -Invoke Invoke-WebRequest -ModuleName Sysmon.ArtifactValidation -Times 0
        Should -Invoke Start-Process -ModuleName Sysmon.ArtifactValidation -Times 0
    }
    It 'keeps disabled paths independent from missing artifacts' {
        $target.paths=@('package')
        Write-FixtureTarget
        Remove-Item -LiteralPath (Join-Path $artifactRoot 'azd-sysmon-state.json')
        $report=Read-Report
        @($report.checks|Where-Object status -ceq 'skipped').Count|Should -Be 8
        ($report.checks|Where-Object id -ceq 'package.artifact').status|Should -BeExactly 'pass'
    }
    It 'refuses foreign, stale, future, missing or unbound state without granting endpoint freshness' -ForEach @('tenant','subscription','environment','template','stale','future','missing','hash','malformed','boolean') {
        $case = $PSItem
        $path=Join-Path $artifactRoot 'azd-sysmon-state.json'
        switch($case){
            tenant {$state.azureTenantId='foreign'} subscription {$state.azureSubscriptionId='foreign'}
            environment {$state.environmentName='foreign'} template {$state.template='foreign'}
            stale {$state.recordedUtc=[DateTimeOffset]::UtcNow.AddDays(-2).ToString('o')}
            future {$state.recordedUtc=[DateTimeOffset]::UtcNow.AddHours(1).ToString('o')}
            boolean {$state.intuneRemediation='false'}
        }
        Write-AzdJsonReceipt -Path $path -InputObject $state
        Write-FixtureTarget
        switch($case){missing {Remove-Item -LiteralPath $path} hash {Add-Content $path ' '} malformed {Set-Content $path '{"broken":'}}
        $report=Read-Report
        ($report.checks|Where-Object id -ceq 'intune.artifact').status|Should -BeExactly 'warning'
        @($report.checks|Where-Object {$_.id.EndsWith('.endpoint') -and $_.status -ceq 'pass'}).Count|Should -Be 0
        ($report.checks|Where-Object id -ceq 'package.artifact').status|Should -BeExactly 'pass'
    }
    It 'isolates foreign object evidence from unrelated paths' -ForEach @('tenant','account','environment','type','status','id','removed') {
        $path=Join-Path $artifactRoot 'azd-sysmon-intune-state.json'
        $value=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable -DateKind String
        switch($PSItem){tenant {$value.tenantId='foreign'} account {$value.account='foreign@example.invalid'} environment {$value.environmentName='foreign'} type {$value.objectType='foreign'} status {$value.status='installed'} id {$value.scriptId='bad'} removed {$value.status='removed'}}
        Write-AzdJsonReceipt -Path $path -InputObject $value
        Write-FixtureTarget
        $report=Read-Report
        ($report.checks|Where-Object id -ceq 'intune.artifact').status|Should -BeExactly 'warning'
        ($report.checks|Where-Object id -ceq 'liveresponse.artifact').status|Should -BeExactly 'info'
    }
    It 'rejects duplicate, oversized, malformed or open target contracts' -ForEach @('duplicate','oversized','malformed','extra','URL','hash-path','finalLF') {
        $path=Join-Path $artifactRoot 'target.json'
        switch($PSItem){
            duplicate {Set-Content $path '{"schemaVersion":"1.0","schemaVersion":"1.0"}'}
            oversized {Set-Content $path ('x'*65537)} malformed {Set-Content $path '{'}
            extra {$target.callback='https://secret.invalid/?sig=SECRET';Write-FixtureTarget}
            URL {$target.paths=@('https://secret.invalid');Write-FixtureTarget}
            hash-path {Write-FixtureTarget;$target.artifactHashes['../foreign.json']='0'*64;$target|ConvertTo-Json -Depth 16|Set-Content $path}
            finalLF {$target.environmentName='fixture'+[char]10;Write-FixtureTarget}
        }
        {Read-Report}|Should -Throw
    }
    It 'never echoes extra receipt canaries, object IDs or accounts' {
        $state.secret='SECRET_STATE_CANARY'
        $state.callbackUrl='https://secret.invalid/?sig=SECRET_SIGNATURE'
        Write-AzdJsonReceipt -Path (Join-Path $artifactRoot 'azd-sysmon-state.json') -InputObject $state
        Write-FixtureTarget
        (Read-Report|ConvertTo-Json -Depth 30)|Should -Not -Match 'SECRET_STATE_CANARY|SECRET_SIGNATURE|secret.invalid|operator@example|44444444|55555555'
    }
    It 'rejects ambiguous or oversized receipt bytes after a matching caller hash' -ForEach @('duplicate','oversized','deep') {
        $case=$PSItem
        $path=Join-Path $artifactRoot 'azd-sysmon-state.json'
        switch($case){
            duplicate {Set-Content -LiteralPath $path '{"template":"azd-sysmon","template":"azd-sysmon"}'}
            oversized {Set-Content -LiteralPath $path ('x'*65537)}
            deep {Set-Content -LiteralPath $path (('{"child":'*18)+'{}'+('}'*18))}
        }
        Write-FixtureTarget
        ($target.artifactHashes['azd-sysmon-state.json'])|Should -BeExactly (Get-FileHash $path).Hash.ToLowerInvariant()
        (Read-Report).checks|Where-Object id -ceq 'intune.artifact'|Select-Object -ExpandProperty status|Should -BeExactly 'warning'
    }
    It 'keeps foreign resource and incomplete object evidence on its own path' -ForEach @('vmSubscription','vmFinalLF','dcrSubscription','dcrFinalLF','amaMissing','unboundObject','objectFinalLF') {
        $case=$PSItem
        switch($case){
            vmSubscription {$state.vmResourceIds=@('/subscriptions/99999999-9999-4999-8999-999999999999/resourceGroups/fixture/providers/Microsoft.Compute/virtualMachines/fixture')}
            vmFinalLF {$state.vmResourceIds=@($state.vmResourceIds[0]+[char]10)}
            dcrSubscription {$state.dcrId='/subscriptions/99999999-9999-4999-8999-999999999999/resourceGroups/fixture/providers/Microsoft.Insights/dataCollectionRules/fixture'}
            dcrFinalLF {$state.dcrId+=[char]10}
            amaMissing {Remove-Item -LiteralPath (Join-Path $artifactRoot 'azd-sysmon-ama-application-state.json')}
            objectFinalLF {
                $path=Join-Path $artifactRoot 'azd-sysmon-intune-state.json'
                $value=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable -DateKind String
                $value.scriptId+=[char]10
                Write-AzdJsonReceipt -Path $path -InputObject $value
            }
        }
        Write-AzdJsonReceipt -Path (Join-Path $artifactRoot 'azd-sysmon-state.json') -InputObject $state
        Write-FixtureTarget
        if($case -ceq 'unboundObject'){
            $target.artifactHashes.Remove('azd-sysmon-intune-state.json')
            $target|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $artifactRoot 'target.json')
        }
        $pathId=if($case.StartsWith('vm')){'azurevm.artifact'}elseif($case.StartsWith('dcr')){'sentinel.artifact'}else{'intune.artifact'}
        $report=Read-Report
        ($report.checks|Where-Object id -ceq $pathId).status|Should -BeExactly 'warning'
        ($report.checks|Where-Object id -ceq 'liveresponse.artifact').status|Should -BeExactly 'info'
    }
    It 'verifies component bytes before loading a tampered module' {
        $copyRoot=Join-Path $templateRoot 'component-copy'
        $null=New-Item -ItemType Directory -Path $copyRoot
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'scripts') -Destination $copyRoot -Recurse
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'azd-components.lock.json') -Destination $copyRoot
        $marker=Join-Path $templateRoot 'tampered-module-ran'
        Set-Content -LiteralPath (Join-Path $copyRoot 'scripts/vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psm1') -Value "Set-Content -LiteralPath '$marker' -Value 'BAD'"
        { & (Join-Path $copyRoot 'scripts/Test-DeploymentArtifacts.ps1') -ArtifactRoot $artifactRoot }|Should -Throw '*ValidationComponentBindingRejected*'
        Test-Path -LiteralPath $marker|Should -BeFalse
    }
    It 'refuses an actual reparse-point artifact root' {
        $junction=Join-Path $templateRoot 'linked-artifacts'
        $null=New-Item -ItemType $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }) -Path $junction -Target $artifactRoot -ErrorAction Stop
        ((Get-Item -LiteralPath $junction -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)|Should -Not -Be 0
        { & (Join-Path $sourceRoot 'scripts/Test-DeploymentArtifacts.ps1') -ArtifactRoot $junction }|Should -Throw '*LocalArtifactPathRejected*'
    }
}
Describe 'PowerShell validation contract' {
    It 'uses only pinned 7.6+ matrix cells and retains the terminal gate' {
        $workflow=Get-Content (Join-Path $sourceRoot '.github/workflows/validate.yml') -Raw
        $workflow|Should -Not -Match '7\.2\.24|runtime: runner'
        ([regex]::Matches($workflow,'runtime: 7\.6\.6')).Count|Should -Be 2
        $workflow|Should -Match 'needs: runtime_matrix'
        $workflow|Should -Match 'Install-PowerShellRuntime.ps1'
        $workflow|Should -Match 'scripts/Test-Repository.ps1'
        $workflow|Should -Match "(?s)Package tests failed after the selected runtime rebuild.*git diff --exit-code.*Offline rebuild changed checked-in artifacts"
        (Get-Content (Join-Path $sourceRoot 'scripts/Install-PowerShellRuntime.ps1') -Raw)|Should -Match '02FE458BE20493FBDF43F61EA20610B811EE6C738AB1676C61B9CFCD1A33C860'
    }
    It 'executes the CI Git baseline gate and rejects deterministic package drift' {
        $fixture=Join-Path $TestDrive 'git-baseline'
        $null=New-Item -ItemType Directory -Path $fixture
        foreach($path in @('config','deploy','scripts','.gitattributes')){Copy-Item -LiteralPath (Join-Path $sourceRoot $path) -Destination $fixture -Recurse}
        $null=New-Item -ItemType Directory -Path (Join-Path $fixture 'tests')
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'tests/Test-Package.ps1') -Destination (Join-Path $fixture 'tests')
        $workflow=Get-Content (Join-Path $sourceRoot '.github/workflows/validate.yml') -Raw
        $match=[regex]::Match($workflow,"(?m)^          git diff --exit-code\r?\n          if \(\`$LASTEXITCODE -ne 0\) \{ throw 'Offline rebuild changed checked-in artifacts\.' \}")
        $match.Success|Should -BeTrue
        $gate=[scriptblock]::Create($match.Value)
        Push-Location $fixture
        try {
            $null=git -c core.autocrlf=false -c core.safecrlf=false init --quiet
            $LASTEXITCODE|Should -Be 0
            $null=git -c core.autocrlf=false -c core.safecrlf=false add -- .
            $LASTEXITCODE|Should -Be 0
            { & $gate }|Should -Not -Throw
            & ./scripts/Build-SysmonPackages.ps1 -DefaultConfiguration filedelete
            $first=(Get-FileHash ./config/generated-package-manifest.json).Hash
            & ./scripts/Build-SysmonPackages.ps1 -DefaultConfiguration filedelete
            (Get-FileHash ./config/generated-package-manifest.json).Hash|Should -BeExactly $first
            & ./tests/Test-Package.ps1
            { & $gate }|Should -Throw '*Offline rebuild changed checked-in artifacts*'
        } finally { Pop-Location }
    }
}
