#requires -Version 7.6
Set-StrictMode -Version Latest
$script:sourcePath = $PSCommandPath

function Invoke-SmokeAzureCliJson {
    param([string[]]$Arguments)
    $output = & az @Arguments --output json --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI prerequisite failed.' }
    try { ($output -join "`n") | ConvertFrom-Json -AsHashtable -ErrorAction Stop }
    catch { throw 'Azure CLI prerequisite failed.' }
}

function Get-SmokeToken {
    param([string]$Resource, [string[]]$Audiences, [string]$TenantId, [string]$SubscriptionId, [string]$PrincipalId)
    $result = Invoke-SmokeAzureCliJson -Arguments @('account','get-access-token','--resource',$Resource,'--subscription',$SubscriptionId)
    try {
        if ($result.tenant -ine $TenantId -or [string]::IsNullOrWhiteSpace($result.accessToken)) { throw 'Invalid token.' }
        $parts = $result.accessToken.Split('.')
        if ($parts.Count -ne 3) { throw 'Invalid token.' }
        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        $payload = $payload.PadRight($payload.Length + ((4 - $payload.Length % 4) % 4), '=')
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json -AsHashtable
        if ($claims.tid -ine $TenantId -or $claims.oid -ine $PrincipalId -or $claims.aud -cnotin $Audiences -or
            [long]$claims.exp -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 60) { throw 'Invalid token.' }
        return [string]$result.accessToken
    } catch { throw 'Token binding failed.' }
}

function New-SmokeHttpClient {
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    return $client
}

function Invoke-SmokeGet {
    param([Net.Http.HttpClient]$Client, [uri]$Uri, [string]$Token)
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, $Uri)
    $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)
    $request.Headers.Accept.ParseAdd('application/json')
    $response = $null; $stream = $null; $buffer = $null
    $deadline = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(30))
    try {
        $response = $Client.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $deadline.Token).GetAwaiter().GetResult()
        $status = [int]$response.StatusCode
        if ($status -ne 200) { return @{ status=$status; data=$null; failure=$null } }
        if ($response.Content.Headers.ContentLength -gt 2MB) { throw 'Response exceeds limit.' }
        $stream = $response.Content.ReadAsStreamAsync($deadline.Token).GetAwaiter().GetResult()
        $buffer = [IO.MemoryStream]::new()
        $chunk = [byte[]]::new(8192)
        while (($read = $stream.ReadAsync($chunk, 0, $chunk.Length, $deadline.Token).GetAwaiter().GetResult()) -gt 0) {
            if ($buffer.Length + $read -gt 2MB) { throw 'Response exceeds limit.' }
            $buffer.Write($chunk, 0, $read)
        }
        try {
            $text = [Text.UTF8Encoding]::new($false, $true).GetString($buffer.ToArray())
            $data = ConvertFrom-Json -InputObject $text -AsHashtable -NoEnumerate -Depth 64 -ErrorAction Stop
        } catch { return @{status=$status;data=$null;failure='invalidJson'} }
        return @{status=$status;data=$data;failure=$null}
    } catch { return @{status=$null;data=$null;failure='transportOrLimit'} }
    finally {
        if ($buffer) { $buffer.Dispose() }; if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }; $request.Dispose(); $deadline.Dispose()
    }
}

function Get-SmokeOutcome {
    param($Response, [switch]$AllowAbsent)
    if ($Response.failure) { return [string]$Response.failure }
    switch ($Response.status) {
        200 { return 'passed' }
        401 { return 'authenticationDenied' }
        403 { return 'permissionDenied' }
        404 { if ($AllowAbsent) { return 'targetAbsent' }; return 'unexpectedStatus' }
        429 { return 'throttled' }
        default { return 'unexpectedStatus' }
    }
}

function Invoke-SysmonApiSmoke {
    [CmdletBinding()]
    param([switch]$Run, [string]$TenantId, [string]$SubscriptionId, [string]$ExpectedPrincipalId)
    if (-not $Run) { return [ordered]@{schemaVersion='1.0';mode='disabled';passed=$false;probes=@()} }
    foreach ($value in @($TenantId, $SubscriptionId, $ExpectedPrincipalId)) {
        $parsed = [guid]::Empty
        if (-not [guid]::TryParseExact($value, 'D', [ref]$parsed) -or $parsed -eq [guid]::Empty) { throw 'Explicit nonzero tenant, subscription and principal GUIDs are required.' }
    }
    try {
        $account = Invoke-SmokeAzureCliJson -Arguments @('account','show','--subscription',$SubscriptionId)
        if ($account.id -ine $SubscriptionId -or $account.tenantId -ine $TenantId -or $account.environmentName -cne 'AzureCloud') { throw 'Target mismatch.' }
    } catch { throw 'Selected commercial Azure account could not be verified. No service probe was sent.' }

    $root = Split-Path $PSScriptRoot -Parent
    $revision = (& git -C $root rev-parse HEAD 2>&1) -join ''
    if ($LASTEXITCODE -ne 0 -or $revision -cnotmatch '\A[0-9a-f]{40}\z') { throw 'Source revision could not be verified.' }
    $dirty = (& git -C $root status --porcelain 2>&1) -join ''
    if ($LASTEXITCODE -ne 0) { throw 'Source status could not be verified.' }
    $probes = @(
        @{ name='intuneMobileApps'; service='graph'; route='/v1.0/deviceAppManagement/mobileApps?$top=1&$select=id'; host='graph.microsoft.com' },
        @{ name='intuneHealthScripts'; service='graph'; route='/beta/deviceManagement/deviceHealthScripts?$top=1&$select=id'; host='graph.microsoft.com' },
        @{ name='monitoredObject'; service='arm'; route='/providers/Microsoft.Insights/monitoredObjects/{tenantId}'; host='management.azure.com' },
        @{ name='defenderLibrary'; service='defender'; route='/api/libraryfiles'; host='api.security.microsoft.com' }
    )
    $resources = @{
        graph=@{resource='https://graph.microsoft.com/';audiences=@('https://graph.microsoft.com','https://graph.microsoft.com/','00000003-0000-0000-c000-000000000000')}
        arm=@{resource='https://management.azure.com/';audiences=@('https://management.azure.com/','https://management.azure.com','https://management.core.windows.net/')}
        defender=@{resource='https://api.securitycenter.microsoft.com';audiences=@('https://api.securitycenter.microsoft.com','https://api.securitycenter.microsoft.com/','fc780465-2017-40d4-a0c5-307022471b92')}
    }
    $tokens = @{}; $results = [Collections.Generic.List[object]]::new()
    $client = New-SmokeHttpClient
    try {
        foreach ($service in 'graph','arm','defender') {
            try { $tokens[$service] = Get-SmokeToken -Resource $resources[$service].resource -Audiences $resources[$service].audiences -TenantId $TenantId -SubscriptionId $SubscriptionId -PrincipalId $ExpectedPrincipalId }
            catch { $tokens[$service] = $null }
        }
        foreach ($probe in $probes) {
            $row = [ordered]@{name=$probe.name;method='GET';host=$probe.host;route=$probe.route;apiVersion=$null;httpStatus=$null;discovery=$null;outcome='authUnavailable'}
            if (-not $tokens[$probe.service]) { $results.Add($row); continue }
            $route = $probe.route
            if ($probe.service -eq 'arm') {
                $provider = Invoke-SmokeGet $client "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Insights?api-version=2021-04-01" $tokens.arm
                $row.discovery = @{method='GET';route='/subscriptions/{subscriptionId}/providers/Microsoft.Insights?api-version=2021-04-01';httpStatus=$provider.status;outcome=(Get-SmokeOutcome $provider)}
                if ((Get-SmokeOutcome $provider) -ne 'passed') { $row.outcome='providerDiscoveryFailed'; $results.Add($row); continue }
                if ($provider.data -isnot [Collections.IDictionary] -or $provider.data['resourceTypes'] -isnot [array]) { $row.outcome='providerDiscoveryFailed'; $results.Add($row); continue }
                $types = @($provider.data['resourceTypes'] | Where-Object { $_ -is [Collections.IDictionary] -and $_['resourceType'] -ceq 'monitoredObjects' })
                if ($types.Count -ne 1) { $row.outcome='providerDiscoveryFailed'; $results.Add($row); continue }
                if ($types[0]['apiVersions'] -isnot [array]) { $row.outcome='providerDiscoveryFailed'; $results.Add($row); continue }
                $versions = @($types[0]['apiVersions'] | Where-Object { $_ -is [string] -and $_ -cmatch '\A\d{4}-\d{2}-\d{2}-preview\z' } | Sort-Object -Descending -Unique)
                if ($versions.Count -eq 0) { $row.outcome='providerDiscoveryFailed'; $results.Add($row); continue }
                $row.apiVersion = $versions[0]
                $route = $route.Replace('{tenantId}', $TenantId) + '?api-version=' + $versions[0]
            }
            $response = Invoke-SmokeGet $client ('https://' + $probe.host + $route) $tokens[$probe.service]
            $row.httpStatus = $response.status
            $row.outcome = Get-SmokeOutcome $response -AllowAbsent:($probe.service -eq 'arm')
            if ($row.outcome -eq 'passed') {
                $data = $response.data
                $shapeValid = $data -is [Collections.IDictionary]
                if ($probe.service -eq 'arm') {
                    $expectedId = "/providers/Microsoft.Insights/monitoredObjects/$TenantId"
                    $shapeValid = $shapeValid -and $data['id'] -ieq $expectedId -and $data['type'] -ieq 'Microsoft.Insights/monitoredObjects' -and $data['properties'] -is [Collections.IDictionary]
                } else {
                    $shapeValid = $shapeValid -and $data.Contains('value') -and $data.value -is [array]
                    if ($shapeValid) {
                        foreach ($item in $data.value) {
                            if ($item -isnot [Collections.IDictionary]) { $shapeValid=$false; break }
                            if ($probe.service -eq 'graph') {
                                if ($item['id'] -isnot [string] -or [string]::IsNullOrWhiteSpace($item['id'])) { $shapeValid=$false; break }
                            } elseif ($item['fileName'] -isnot [string] -or [string]::IsNullOrWhiteSpace($item['fileName']) -or $item['sha256'] -isnot [string] -or $item['sha256'] -notmatch '\A[0-9a-fA-F]{64}\z') { $shapeValid=$false; break }
                        }
                    }
                }
                if (-not $shapeValid) { $row.outcome='unexpectedShape' }
            }
            $results.Add($row)
        }
    } finally { $client.Dispose(); $tokens.Clear() }
    return [ordered]@{schemaVersion='1.0';mode='live-read-only';sourceRevision=$revision;sourceDirty=([bool]$dirty);sourceSha256=(Get-FileHash $script:sourcePath).Hash.ToLowerInvariant();observedAt=[DateTimeOffset]::UtcNow.ToString('o');passed=(@($results | Where-Object outcome -ne 'passed').Count -eq 0);probes=$results.ToArray();cleanup='No resources created or changed; no cleanup required.'}
}
Export-ModuleMember -Function Invoke-SysmonApiSmoke
