#requires -Version 7.6
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../scripts/Sysmon.ApiSmoke.psm1') -Force
    if (-not ('SysmonSmokeTestHandler' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
public sealed class SysmonSmokeTestHandler : HttpMessageHandler {
    public Queue<HttpResponseMessage> Responses = new();
    public List<string> Requests = new();
    public List<string> Methods = new();
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
        Requests.Add(request.RequestUri.AbsoluteUri);
        Methods.Add(request.Method.Method);
        if (request.Content != null) throw new Exception("Unexpected write payload.");
        if (Responses.Count == 0) throw new Exception("Unexpected request.");
        return Task.FromResult(Responses.Dequeue());
    }
    public void Enqueue(int status, string body) {
        Responses.Enqueue(new HttpResponseMessage((HttpStatusCode)status) { Content = new StringContent(body) });
    }
}
'@
    }
    function New-SmokeTestJwt($Claims) {
        $json = $Claims | ConvertTo-Json -Compress
        'header.' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)).TrimEnd('=').Replace('+','-').Replace('/','_') + '.signature'
    }
}

Describe 'Read-only service API smoke' {
    BeforeEach {
        $script:tenant = '11111111-1111-4111-8111-111111111111'
        $script:subscription = '22222222-2222-4222-8222-222222222222'
        $script:principal = '33333333-3333-4333-8333-333333333333'
        $script:handler = [SysmonSmokeTestHandler]::new()
        Mock -ModuleName Sysmon.ApiSmoke New-SmokeHttpClient { [Net.Http.HttpClient]::new($script:handler) }
        Mock -ModuleName Sysmon.ApiSmoke Invoke-SmokeAzureCliJson {
            @{ id=$script:subscription;tenantId=$script:tenant;environmentName='AzureCloud' }
        }
        Mock -ModuleName Sysmon.ApiSmoke Get-SmokeToken { 'synthetic-token' }
    }

    It 'is disabled without Run and performs no authentication or requests' {
        $r = Invoke-SysmonApiSmoke
        $r.mode | Should -Be 'disabled'
        $r.passed | Should -BeFalse
        Should -Invoke -ModuleName Sysmon.ApiSmoke Invoke-SmokeAzureCliJson -Times 0
        Should -Invoke -ModuleName Sysmon.ApiSmoke Get-SmokeToken -Times 0
        Should -Invoke -ModuleName Sysmon.ApiSmoke New-SmokeHttpClient -Times 0
    }

    It 'rejects <kind> before tokens and service requests' -ForEach @(
        @{kind='tenant';changed=@{tenantId='44444444-4444-4444-8444-444444444444'}},
        @{kind='subscription';changed=@{id='44444444-4444-4444-8444-444444444444'}},
        @{kind='cloud';changed=@{environmentName='AzureUSGovernment'}}
    ) {
        $script:changed = $changed
        Mock -ModuleName Sysmon.ApiSmoke Invoke-SmokeAzureCliJson {
            $a=@{id=$script:subscription;tenantId=$script:tenant;environmentName='AzureCloud'}
            foreach($key in $script:changed.Keys){$a[$key]=$script:changed[$key]};$a
        }
        { Invoke-SysmonApiSmoke -Run -TenantId $tenant -SubscriptionId $subscription -ExpectedPrincipalId $principal } | Should -Throw '*could not be verified*'
        Should -Invoke -ModuleName Sysmon.ApiSmoke Get-SmokeToken -Times 0
        $handler.Requests.Count | Should -Be 0
    }

    It 'passes only four valid service shapes with exactly five GETs including discovery' {
        $handler.Enqueue(200,'{"value":[{"id":"private-device"}],"@odata.nextLink":"https://untrusted.invalid/private"}')
        $handler.Enqueue(200,'{"value":[]}')
        $handler.Enqueue(200,'{"resourceTypes":[{"resourceType":"monitoredObjects","apiVersions":["2021-09-01-preview","2025-01-01-preview","bad"]}]}')
        $handler.Enqueue(200,('{"id":"/providers/Microsoft.Insights/monitoredObjects/'+$tenant+'","type":"Microsoft.Insights/monitoredObjects","properties":{"secret":"private-value"}}'))
        $handler.Enqueue(200,('{"value":[{"fileName":"private-script.ps1","sha256":"'+('a'*64)+'"}]}'))
        $r=Invoke-SysmonApiSmoke -Run -TenantId $tenant -SubscriptionId $subscription -ExpectedPrincipalId $principal
        $r.passed | Should -BeTrue
        $r.probes.Count | Should -Be 4
        Should -Invoke -ModuleName Sysmon.ApiSmoke Invoke-SmokeAzureCliJson -Times 1 -Exactly -ParameterFilter {
            ($Arguments -join '|') -ceq "account|show|--subscription|$script:subscription"
        }
        foreach($resource in @('https://graph.microsoft.com/','https://management.azure.com/','https://api.securitycenter.microsoft.com')) {
            $script:expectedResource=$resource
            Should -Invoke -ModuleName Sysmon.ApiSmoke Get-SmokeToken -Times 1 -Exactly -ParameterFilter {
                $Resource -ceq $script:expectedResource -and $TenantId -ceq $script:tenant -and $SubscriptionId -ceq $script:subscription -and $PrincipalId -ceq $script:principal
            }
        }
        $handler.Requests.Count | Should -Be 5
        @($handler.Methods | Select-Object -Unique) | Should -Be @('GET')
        $handler.Requests[0] | Should -Be 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps?$top=1&$select=id'
        $handler.Requests[1] | Should -Be 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?$top=1&$select=id'
        $handler.Requests[3] | Should -Be "https://management.azure.com/providers/Microsoft.Insights/monitoredObjects/$tenant`?api-version=2025-01-01-preview"
        $handler.Requests[4] | Should -Be 'https://api.security.microsoft.com/api/libraryfiles'
        $json=$r|ConvertTo-Json -Depth 8
        foreach($private in @($tenant,$subscription,$principal,'synthetic-token','private-device','private-value','private-script','untrusted.invalid')){$json | Should -Not -Match ([regex]::Escape($private))}
        $r.sourceRevision | Should -Match '^[0-9a-f]{40}$'
        $r.sourceSha256 | Should -Be (Get-FileHash (Join-Path $PSScriptRoot '../scripts/Sysmon.ApiSmoke.psm1')).Hash.ToLowerInvariant()
    }

    It 'does not turn unavailable tokens into green checks or network calls' {
        Mock -ModuleName Sysmon.ApiSmoke Get-SmokeToken { throw 'private-token-error' }
        $r=Invoke-SysmonApiSmoke -Run -TenantId $tenant -SubscriptionId $subscription -ExpectedPrincipalId $principal
        $r.passed | Should -BeFalse
        @($r.probes.outcome | Select-Object -Unique) | Should -Be @('authUnavailable')
        $handler.Requests.Count | Should -Be 0
        ($r|ConvertTo-Json -Depth 8) | Should -Not -Match 'private-token-error'
    }

    It 'classifies <status> without persisting bodies or following next links' -ForEach @(
        @{status=302;expected='unexpectedStatus'},@{status=401;expected='authenticationDenied'},
        @{status=403;expected='permissionDenied'},@{status=404;expected='unexpectedStatus'},@{status=429;expected='throttled'},
        @{status=500;expected='unexpectedStatus'}
    ) {
        $handler.Enqueue($status,'{"private":"private-response-body"}')
        $client=[Net.Http.HttpClient]::new($handler)
        try {
            InModuleScope Sysmon.ApiSmoke -Parameters @{client=$client;expected=$expected;status=$status} {
                $response=Invoke-SmokeGet $client 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps?$top=1&$select=id' 'synthetic-token'
                $response.status | Should -Be $status
                Get-SmokeOutcome $response | Should -Be $expected
                ($response|ConvertTo-Json) | Should -Not -Match 'private-response-body'
            }
        } finally {$client.Dispose()}
        $handler.Requests.Count | Should -Be 1
    }

    It 'rejects <name> successful-response shapes' -ForEach @(
        @{name='malformed JSON';body='{broken'},@{name='missing collection';body='{}'},
        @{name='object collection';body='{"value":{}}'},@{name='null collection';body='{"value":null}'},
        @{name='scalar item';body='{"value":[1]}'},@{name='missing item id';body='{"value":[{}]}'},
        @{name='array root';body='[{"value":[]}]'}
    ) {
        $handler.Enqueue(200,$body);$handler.Enqueue(200,'{"value":[]}')
        $handler.Enqueue(200,'{"resourceTypes":[]}');$handler.Enqueue(200,'{"value":[]}')
        $r=Invoke-SysmonApiSmoke -Run -TenantId $tenant -SubscriptionId $subscription -ExpectedPrincipalId $principal
        $r.passed | Should -BeFalse
        $r.probes[0].outcome | Should -BeIn @('invalidJson','unexpectedShape')
        $r.probes[2].outcome | Should -Be 'providerDiscoveryFailed'
    }

    It 'does not count a missing monitored object as a passing contract' {
        $handler.Enqueue(200,'{"value":[]}');$handler.Enqueue(200,'{"value":[]}')
        $handler.Enqueue(200,'{"resourceTypes":[{"resourceType":"monitoredObjects","apiVersions":["2021-09-01-preview"]}]}')
        $handler.Enqueue(404,'{"error":{"message":"private-tenant-details"}}');$handler.Enqueue(200,'{"value":[]}')
        $r=Invoke-SysmonApiSmoke -Run -TenantId $tenant -SubscriptionId $subscription -ExpectedPrincipalId $principal
        $r.probes[2].outcome | Should -Be 'targetAbsent'
        $r.passed | Should -BeFalse
        ($r|ConvertTo-Json -Depth 8) | Should -Not -Match 'private-tenant-details'
    }

    It 'rejects ambiguous or malformed provider metadata without requesting a monitored object' -ForEach @(
        @{body='{"resourceTypes":[{"resourceType":"monitoredObjects","apiVersions":["2021-09-01-preview"]},{"resourceType":"monitoredObjects","apiVersions":["2021-09-01-preview"]}]}'},
        @{body='{"resourceTypes":[{"resourceType":"monitoredObjects","apiVersions":"2021-09-01-preview"}]}'},
        @{body='{"resourceTypes":[{"resourceType":"monitoredObjects","apiVersions":["../../private?secret=123"]}]}'},
        @{body='{"private":"unrelated-response"}'}
    ) {
        $handler.Enqueue(200,'{"value":[]}');$handler.Enqueue(200,'{"value":[]}');$handler.Enqueue(200,$body);$handler.Enqueue(200,'{"value":[]}')
        $r=Invoke-SysmonApiSmoke -Run -TenantId $tenant -SubscriptionId $subscription -ExpectedPrincipalId $principal
        $r.passed | Should -BeFalse
        $r.probes[2].outcome | Should -Be 'providerDiscoveryFailed'
        $handler.Requests.Count | Should -Be 4
    }

    It 'bounds response bytes and sanitizes transport errors' {
        $handler.Enqueue(200,('x'*(2MB+1)))
        $client=[Net.Http.HttpClient]::new($handler)
        try {
            InModuleScope Sysmon.ApiSmoke -Parameters @{client=$client} {
                $r=Invoke-SmokeGet $client 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps?$top=1&$select=id' 'synthetic-token'
                $r.failure | Should -Be 'transportOrLimit'
                $r.data | Should -BeNullOrEmpty
                $r=Invoke-SmokeGet $client 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps?$top=1&$select=id' 'synthetic-token'
                $r.failure | Should -Be 'transportOrLimit'
            }
        } finally {$client.Dispose()}
    }
}

Describe 'Minted token binding' {
    It 'accepts the expected minted token and rejects a wrong <name>' -ForEach @(
        @{name='tenant';key='tid';bad='44444444-4444-4444-8444-444444444444'},
        @{name='principal';key='oid';bad='44444444-4444-4444-8444-444444444444'},
        @{name='audience';key='aud';bad='https://untrusted.invalid/'},@{name='expiry';key='exp';bad=0}
    ) {
        $claims=@{tid='11111111-1111-4111-8111-111111111111';oid='33333333-3333-4333-8333-333333333333';aud='https://graph.microsoft.com/';exp=[DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds()}
        $token=New-SmokeTestJwt $claims
        InModuleScope Sysmon.ApiSmoke -Parameters @{token=$token;claims=$claims;key=$key;bad=$bad} {
            Mock Invoke-SmokeAzureCliJson { @{tenant=$claims.tid;accessToken=$token} }
            $p=@{Resource='https://graph.microsoft.com/';Audiences=@('https://graph.microsoft.com/');TenantId=$claims.tid;SubscriptionId='22222222-2222-4222-8222-222222222222';PrincipalId=$claims.oid}
            Get-SmokeToken @p | Should -Be $token
            Should -Invoke Invoke-SmokeAzureCliJson -Times 1 -Exactly -ParameterFilter {
                ($Arguments -join '|') -ceq 'account|get-access-token|--resource|https://graph.microsoft.com/|--subscription|22222222-2222-4222-8222-222222222222'
            }
            $claims[$key]=$bad
            $json=$claims|ConvertTo-Json -Compress
            $token='header.'+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)).TrimEnd('=').Replace('+','-').Replace('/','_')+'.signature'
            {Get-SmokeToken @p} | Should -Throw '*binding failed*'
        }
    }
}

Describe 'Azure CLI JSON wrapper boundary' {
    It 'preserves exact argv and fails closed for <name>' -ForEach @(
        @{name='nonzero CLI';code=1;text='private-tenant-details'},
        @{name='malformed JSON';code=0;text='private-token-details'}
    ) {
        InModuleScope Sysmon.ApiSmoke -Parameters @{code=$code;text=$text} {
            $script:fixtureCode=$code; $script:fixtureText=$text
            function script:az {
                param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
                $script:fixtureArguments=$Arguments
                $global:LASTEXITCODE=$script:fixtureCode
                $script:fixtureText
            }
            try {
                { Invoke-SmokeAzureCliJson -Arguments @('account','show','--subscription','22222222-2222-4222-8222-222222222222') } | Should -Throw -ExpectedMessage 'Azure CLI prerequisite failed.'
                $script:fixtureArguments | Should -Be @('account','show','--subscription','22222222-2222-4222-8222-222222222222','--output','json','--only-show-errors')
                $script:fixtureCode=0; $script:fixtureText='{"tenant":"expected","accessToken":"synthetic-token"}'
                $r=Invoke-SmokeAzureCliJson -Arguments @('account','get-access-token','--resource','https://graph.microsoft.com/','--subscription','22222222-2222-4222-8222-222222222222')
                $r.tenant | Should -Be 'expected'
                $script:fixtureArguments | Should -Be @('account','get-access-token','--resource','https://graph.microsoft.com/','--subscription','22222222-2222-4222-8222-222222222222','--output','json','--only-show-errors')
            } finally { Remove-Item Function:script:az; $global:LASTEXITCODE=0 }
        }
    }
}
