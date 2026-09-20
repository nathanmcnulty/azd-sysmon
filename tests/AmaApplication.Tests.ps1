BeforeAll {
    $sourceRoot = Split-Path -Parent $PSScriptRoot
    function Connect-AzdGraphSession { param($TenantId, $ExpectedAccount, $Scopes, $ProbeUri, [switch]$AllowInteractive, [switch]$AllowContextReplacement) }
    function Invoke-MgGraphRequest { param($Method, $Uri, $Headers, $Body) }
    function Invoke-WebRequest { param($Uri, $Method, $Headers, $Body, $OutFile, $ContentType) }
}

Describe 'Azure Monitor Agent Intune publisher' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path "$root/scripts/vendor/Azd.GraphAuthentication", "$root/config", "$root/.artifacts/ama" -Force | Out-Null
        Copy-Item "$sourceRoot/scripts/Deploy-IntuneAmaApplication.ps1" "$root/scripts/"
        Copy-Item "$sourceRoot/config/ama-client-release.json" "$root/config/"
        New-Item -ItemType File -Path "$root/.artifacts/ama/AzureMonitorAgentClientSetup-1.44.0.0.msi" | Out-Null
        $script:entry = "$root/scripts/Deploy-IntuneAmaApplication.ps1"
        $script:group = '11111111-1111-4111-8111-111111111111'
        $script:tenant = '22222222-2222-4222-8222-222222222222'
        $script:marker = 'Managed by azd-sysmon. The package is an SHA-256-pinned Microsoft Azure Monitor Agent Windows client MSI.'
        Mock Get-Module { [pscustomobject]@{ Name = 'Microsoft.Graph.Authentication' } }
        Mock Import-Module {}
        Mock Get-FileHash { [pscustomobject]@{ Hash = 'a93a6f55f8179be097184630e999d537eae2b8098da9c00101ba1bf9a9d55927' } }
        Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' } } }
        $script:msiProperties = @{ ProductCode = '{C4F6939C-A3A2-4556-AEB6-889F720A8AB8}'; ProductVersion = '1.44.0.0'; Manufacturer = 'Microsoft Corporation' }
        $global:azdSysmonAmaTestMsiProperties = $script:msiProperties
        Mock New-Object {
            $database = [pscustomobject]@{}
            $database | Add-Member -MemberType ScriptMethod -Name OpenView -Value {
                param($query)
                $value = if ($query -match 'ProductCode') { $global:azdSysmonAmaTestMsiProperties['ProductCode'] }
                elseif ($query -match 'ProductVersion') { $global:azdSysmonAmaTestMsiProperties['ProductVersion'] }
                elseif ($query -match 'Manufacturer') { $global:azdSysmonAmaTestMsiProperties['Manufacturer'] }
                elseif ($query -match 'UpgradeCode') { '{AB6064D5-3451-413C-9C54-535DF33F6512}' }
                else { $null }
                $view = [pscustomobject]@{ Value = $value }
                $view | Add-Member -MemberType ScriptMethod -Name Execute -Value { }
                $view | Add-Member -MemberType ScriptMethod -Name Fetch -Value {
                    $record = [pscustomobject]@{ Value = $this.Value }
                    $record | Add-Member -MemberType ScriptMethod -Name StringData -Value { param($index) return $this.Value }
                    return $record
                }
                return $view
            }
            $installer = [pscustomobject]@{ Database = $database }
            $installer | Add-Member -MemberType ScriptMethod -Name OpenDatabase -Value { param($path, $mode) return $this.Database }
            return $installer
        } -ParameterFilter { $ComObject -eq 'WindowsInstaller.Installer' }
        Mock Connect-AzdGraphSession {}
        Mock Invoke-WebRequest {}
        $script:contentCommitted = $false
        $script:publishPolls = 0
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'GET' -and $Uri -match '/files/file-id$') {
                if ($script:contentCommitted) { return @{ uploadState = 'commitFileSuccess' } }
                return @{ uploadState = 'azureStorageUriRequestSuccess'; azureStorageUri = 'https://storage.example/upload?sig=redacted' }
            }
            if ($Method -eq 'GET' -and $Uri -match '/created-app$') {
                $script:publishPolls++
                return @{ publishingState = if ($script:publishPolls -eq 1) { 'processing' } else { 'published' } }
            }
            if ($Method -eq 'GET') { return @{ value = @() } }
            if ($Method -eq 'POST' -and $Uri -match '/mobileApps$') { return @{ id = 'created-app'; productVersion = '1.44.0.0'; committedContentVersion = '1' } }
            if ($Method -eq 'POST' -and $Uri -match '/contentVersions$') { return @{ id = 'content-id' } }
            if ($Method -eq 'POST' -and $Uri -match '/files$') { return @{ id = 'file-id' } }
            if ($Method -eq 'POST' -and $Uri -match '/commit$') { $script:contentCommitted = $true; return }
        }
    }

    It 'uses the intended Graph session, creates a Windows MSI app, and assigns only the selected group' {
        & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' -PollSeconds 0
        Should -Invoke Connect-AzdGraphSession -Times 1 -Exactly -ParameterFilter { $TenantId -eq $script:tenant -and $ExpectedAccount -eq 'admin@example.com' -and $Scopes -eq 'DeviceManagementApps.ReadWrite.All' -and $ProbeUri -match '/v1.0/deviceAppManagement/mobileApps' }
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' -and $Uri -match '/mobileApps\?' -and $Uri -notmatch '(?i)\$select=.*(productCode|productVersion)' }
        Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/mobileApps$' -and ($Body | ConvertFrom-Json).'@odata.type' -eq '#microsoft.graph.windowsMobileMSI' -and ($Body | ConvertFrom-Json).productCode -eq '{C4F6939C-A3A2-4556-AEB6-889F720A8AB8}' }
        Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
            if ($Method -ne 'POST' -or $Uri -notmatch '/files$') { return $false }
            $request = $Body | ConvertFrom-Json
            [xml]$manifest = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($request.manifest))
            $manifest.MobileMsiData.MsiProductCode -eq '{C4F6939C-A3A2-4556-AEB6-889F720A8AB8}' -and
            $manifest.MobileMsiData.MsiProductVersion -eq '1.44.0.0' -and
            $manifest.MobileMsiData.MsiUpgradeCode -eq '{AB6064D5-3451-413C-9C54-535DF33F6512}' -and
            $manifest.MobileMsiData.MsiExecutionContext -eq 'System' -and
            $manifest.MobileMsiData.MsiIncludesServices -eq 'true'
        }
        Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/commit$' -and ($Body | ConvertFrom-Json).fileEncryptionInfo.profileIdentifier -eq 'ProfileVersion1' -and ($Body | ConvertFrom-Json).fileEncryptionInfo.fileDigestAlgorithm -eq 'SHA256' }
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Uri -match 'comp=blocklist' -and $ContentType -eq 'application/xml; charset=utf-8' -and
            ([Text.Encoding]::UTF8.GetString([byte[]]$Body) -match '^<\?xml version="1.0" encoding="utf-8"\?><BlockList><Latest>')
        }
        Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Method -eq 'PUT' }
        Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/assign$' -and ($Body | ConvertFrom-Json).mobileAppAssignments[0].target.groupId -eq $script:group -and ($Body | ConvertFrom-Json).mobileAppAssignments[0].intent -eq 'required' }
        (Get-Content "$root/.azure/default/azd-sysmon-ama-application-state.json" -Raw | ConvertFrom-Json).applicationId | Should -Be 'created-app'
        Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -ParameterFilter { $Method -eq 'GET' -and $Uri -match '/created-app$' }
    }

    It 'finds an owned app on a later page and does not upload unchanged content' {
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'GET' -and $Uri -match 'skiptoken=next') { return @{ value = @(@{ id = 'owned-app'; '@odata.type' = '#microsoft.graph.windowsMobileMSI'; displayName = 'Azure Monitor Agent (azd-sysmon)'; description = $script:marker; productCode = '{C4F6939C-A3A2-4556-AEB6-889F720A8AB8}'; productVersion = '1.44.0.0'; committedContentVersion = '1' }) } }
            if ($Method -eq 'GET' -and $Uri -match '/assignments') { return @{ value = @() } }
            if ($Method -eq 'GET' -and $Uri -match '/owned-app$') { return @{ publishingState = 'published' } }
            if ($Method -eq 'GET') { return @{ value = @(); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps?$skiptoken=next' } }
        }
        & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com'
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -match '/owned-app$' }
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/contentVersions$' }
    }

    It 'refuses an app that has an assignment outside the requested group before changing it' {
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'GET' -and $Uri -match '/assignments') { return @{ value = @(@{ target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } }) } }
            if ($Method -eq 'GET') { return @{ value = @(@{ id = 'owned-app'; '@odata.type' = '#microsoft.graph.windowsMobileMSI'; displayName = 'Azure Monitor Agent (azd-sysmon)'; description = $script:marker; productCode = '{C4F6939C-A3A2-4556-AEB6-889F720A8AB8}'; productVersion = '1.44.0.0'; committedContentVersion = '1' }) } }
        }
        { & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' } | Should -Throw '*different or filtered assignment*'
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -ne 'GET' }
    }

    It 'rejects a package whose pinned hash does not match before authentication' {
        Mock Get-FileHash { [pscustomobject]@{ Hash = '0000000000000000000000000000000000000000000000000000000000000000' } }
        { & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' } | Should -Throw '*hash does not match*'
        Should -Invoke Connect-AzdGraphSession -Times 0 -Exactly
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
    }

    It 'rejects an MSI whose ProductCode differs from the pinned release before authentication' {
        $script:msiProperties.ProductCode = '{00000000-0000-0000-0000-000000000000}'
        $global:azdSysmonAmaTestMsiProperties = $script:msiProperties
        { & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' } | Should -Throw '*ProductCode does not match*'
        Should -Invoke Connect-AzdGraphSession -Times 0 -Exactly
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
    }

    It 'times out publishing before it changes assignments' {
        Mock Invoke-MgGraphRequest { return @{ publishingState = 'processing' } } -ParameterFilter { $Method -eq 'GET' -and $Uri -match '/created-app$' }
        { & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' -MaxPollAttempts 2 -PollSeconds 0 } | Should -Throw '*publishing timed out*'
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/assign$' }
    }

    It 'does not advance version metadata after a failed upload and retries content on the next run' {
        $script:contentCommitted = $false
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'GET' -and $Uri -match '/assignments') { return @{ value = @() } }
            if ($Method -eq 'GET' -and $Uri -match '/files/file-id$') {
                if ($script:contentCommitted) { return @{ uploadState = 'commitFileSuccess' } }
                return @{ uploadState = 'azureStorageUriRequestSuccess'; azureStorageUri = 'https://storage.example/upload?sig=secret-value' }
            }
            if ($Method -eq 'GET' -and $Uri -match '/owned-app$') { return @{ publishingState = 'published' } }
            if ($Method -eq 'GET') { return @{ value = @(@{ id = 'owned-app'; '@odata.type' = '#microsoft.graph.windowsMobileMSI'; displayName = 'Azure Monitor Agent (azd-sysmon)'; description = $script:marker; productCode = '{C4F6939C-A3A2-4556-AEB6-889F720A8AB8}'; productVersion = '1.43.0.0'; committedContentVersion = 'old-content' }) } }
            if ($Method -eq 'POST' -and $Uri -match '/contentVersions$') { return @{ id = 'content-id' } }
            if ($Method -eq 'POST' -and $Uri -match '/files$') { return @{ id = 'file-id' } }
            if ($Method -eq 'POST' -and $Uri -match '/commit$') { $script:contentCommitted = $true; return }
        }
        Mock Invoke-WebRequest { throw 'provider response included https://storage.example/upload?sig=secret-value' }
        { & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' } | Should -Throw '*provider error details were withheld*'
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -match '/owned-app$' }

        Mock Invoke-WebRequest {}
        & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com'
        Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/contentVersions$' }
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -match '/owned-app$' -and ($Body | ConvertFrom-Json).committedContentVersion -eq 'content-id' }
    }

    It 'reuses the sole matching uncommitted initial file without creating or deleting content' {
        $manifestXml = '<MobileMsiData MsiExecutionContext="System" MsiRequiresReboot="false" MsiProductCode="{C4F6939C-A3A2-4556-AEB6-889F720A8AB8}" MsiProductVersion="1.44.0.0" MsiUpgradeCode="{AB6064D5-3451-413C-9C54-535DF33F6512}" MsiIsMachineInstall="true" MsiIsUserInstall="false" MsiIncludesServices="true" MsiContainsSystemRegistryKeys="true" MsiContainsSystemFolders="false" />'
        $manifest = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($manifestXml))
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'GET' -and $Uri -match '/assignments') { return @{ value = @() } }
            if ($Method -eq 'GET' -and $Uri -match '/owned-app/microsoft\.graph\.windowsMobileMSI/contentVersions\?') { return @{ value = @(@{ id = '1' }) } }
            if ($Method -eq 'GET' -and $Uri -match '/owned-app/microsoft\.graph\.windowsMobileMSI/contentVersions/1/files\?') { return @{ value = @(@{ id = 'stale-file'; isCommitted = $false; name = 'AzureMonitorAgentClientSetup.msi'; size = 0; sizeEncrypted = 64; manifest = $manifest }) } }
            if ($Method -eq 'GET' -and $Uri -match '/owned-app/microsoft\.graph\.windowsMobileMSI/contentVersions/1/files/stale-file$') {
                if ($script:contentCommitted) { return @{ uploadState = 'commitFileSuccess' } }
                return @{ uploadState = 'azureStorageUriRequestSuccess'; azureStorageUri = 'https://storage.example/upload?sig=redacted' }
            }
            if ($Method -eq 'GET' -and $Uri -match '/owned-app$') { return @{ publishingState = 'published' } }
            if ($Method -eq 'GET') { return @{ value = @(@{ id = 'owned-app'; '@odata.type' = '#microsoft.graph.windowsMobileMSI'; displayName = 'Azure Monitor Agent (azd-sysmon)'; description = $script:marker; productCode = '{C4F6939C-A3A2-4556-AEB6-889F720A8AB8}'; productVersion = '1.44.0.0'; committedContentVersion = $null }) } }
            if ($Method -eq 'POST' -and $Uri -match '/commit$') { $script:contentCommitted = $true; return }
        }
        & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' -PollSeconds 0
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/contentVersions$' }
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/owned-app/microsoft\.graph\.windowsMobileMSI/contentVersions/1/files$' }
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Uri -match '/owned-app/contentVersions' }
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -match '/owned-app$' -and ($Body | ConvertFrom-Json).committedContentVersion -eq '1' }
    }

    It 'refuses a mismatched file in an incomplete initial version' {
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'GET' -and $Uri -match '/assignments') { return @{ value = @() } }
            if ($Method -eq 'GET' -and $Uri -match '/owned-app/microsoft\.graph\.windowsMobileMSI/contentVersions\?') { return @{ value = @(@{ id = '1' }) } }
            if ($Method -eq 'GET' -and $Uri -match '/owned-app/microsoft\.graph\.windowsMobileMSI/contentVersions/1/files\?') { return @{ value = @(@{ id = 'protected-file'; isCommitted = $true }) } }
            if ($Method -eq 'GET') { return @{ value = @(@{ id = 'owned-app'; '@odata.type' = '#microsoft.graph.windowsMobileMSI'; displayName = 'Azure Monitor Agent (azd-sysmon)'; description = $script:marker; productCode = '{C4F6939C-A3A2-4556-AEB6-889F720A8AB8}'; productVersion = '1.44.0.0'; committedContentVersion = $null }) } }
        }
        { & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' } | Should -Throw '*does not exactly match*'
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/files$' }
    }

    It 'creates the first content version when an existing owned app has none' {
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'GET' -and $Uri -match '/assignments') { return @{ value = @() } }
            if ($Method -eq 'GET' -and $Uri -match '/owned-app/microsoft\.graph\.windowsMobileMSI/contentVersions\?') { return @{ value = @() } }
            if ($Method -eq 'GET' -and $Uri -match '/owned-app/microsoft\.graph\.windowsMobileMSI/contentVersions/first-version/files/file-id$') {
                if ($script:contentCommitted) { return @{ uploadState = 'commitFileSuccess' } }
                return @{ uploadState = 'azureStorageUriRequestSuccess'; azureStorageUri = 'https://storage.example/upload?sig=redacted' }
            }
            if ($Method -eq 'GET' -and $Uri -match '/owned-app$') { return @{ publishingState = 'published' } }
            if ($Method -eq 'GET') { return @{ value = @(@{ id = 'owned-app'; '@odata.type' = '#microsoft.graph.windowsMobileMSI'; displayName = 'Azure Monitor Agent (azd-sysmon)'; description = $script:marker; productCode = '{C4F6939C-A3A2-4556-AEB6-889F720A8AB8}'; productVersion = '1.44.0.0'; committedContentVersion = $null }) } }
            if ($Method -eq 'POST' -and $Uri -match '/owned-app/microsoft\.graph\.windowsMobileMSI/contentVersions$') { return @{ id = 'first-version' } }
            if ($Method -eq 'POST' -and $Uri -match '/owned-app/microsoft\.graph\.windowsMobileMSI/contentVersions/first-version/files$') { return @{ id = 'file-id' } }
            if ($Method -eq 'POST' -and $Uri -match '/commit$') { $script:contentCommitted = $true; return }
        }
        & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' -PollSeconds 0
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/owned-app/microsoft\.graph\.windowsMobileMSI/contentVersions$' }
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'reports only Azure block-list status and error code when the block list fails' {
        Mock Invoke-WebRequest {
            if ($Uri -match 'comp=blocklist') {
                $exception = [Exception]::new('secret provider response https://storage.example/upload?sig=secret-value')
                $exception | Add-Member -MemberType NoteProperty -Name ResponseStatusCode -Value 409
                $response = [pscustomobject]@{ Headers = @{}; Stream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes('<Error><Code>InvalidBlockList</Code><Message>secret-value</Message></Error>')) }
                $response | Add-Member -MemberType ScriptMethod -Name GetResponseStream -Value { return $this.Stream }
                $exception | Add-Member -MemberType NoteProperty -Name Response -Value $response
                throw $exception
            }
        }
        $failure = $null
        try { & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' -PollSeconds 0 } catch { $failure = $_ }
        $failure | Should -Not -BeNullOrEmpty
        $failure.Exception.Message | Should -Match 'HTTP status 409; Azure error code InvalidBlockList'
        $failure.Exception.Message | Should -Not -Match 'secret-value|provider response|storage\.example'
    }

    It 'reports only Azure block status and error code when a block upload fails' {
        Mock Invoke-WebRequest {
            if ($Uri -match 'comp=block&') {
                $exception = [Exception]::new('secret provider response https://storage.example/upload?sig=secret-value')
                $exception | Add-Member -MemberType NoteProperty -Name ResponseStatusCode -Value 403
                $response = [pscustomobject]@{ Headers = @{}; Stream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes('<Error><Code>AuthenticationFailed</Code><Message>secret-value</Message></Error>')) }
                $response | Add-Member -MemberType ScriptMethod -Name GetResponseStream -Value { return $this.Stream }
                $exception | Add-Member -MemberType NoteProperty -Name Response -Value $response
                throw $exception
            }
        }
        $failure = $null
        try { & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' -PollSeconds 0 } catch { $failure = $_ }
        $failure.Exception.Message | Should -Match 'HTTP status 403; Azure error code AuthenticationFailed'
        $failure.Exception.Message | Should -Not -Match 'secret-value|provider response|storage\.example'
    }

    It 'renews an expired Intune upload URI before uploading' {
        $script:renewed = $false
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'POST' -and $Uri -match '/files/file-id/renewUpload$') { $script:renewed = $true; return }
            if ($Method -eq 'GET' -and $Uri -match '/files/file-id$') {
                if ($script:contentCommitted) { return @{ uploadState = 'commitFileSuccess' } }
                if ($script:renewed) { return @{ uploadState = 'azureStorageUriRenewalSuccess'; azureStorageUri = 'https://storage.example/renewed?sig=redacted'; azureStorageUriExpirationDateTime = '2999-01-01T00:00:00Z' } }
                return @{ uploadState = 'azureStorageUriRequestSuccess'; azureStorageUri = 'https://storage.example/expired?sig=redacted'; azureStorageUriExpirationDateTime = '2000-01-01T00:00:00Z' }
            }
        } -ParameterFilter { ($Method -eq 'GET' -and $Uri -match '/files/file-id$') -or ($Method -eq 'POST' -and $Uri -match '/files/file-id/renewUpload$') }
        & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' -PollSeconds 0
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/files/file-id/renewUpload$' }
    }
}

AfterAll {
    Remove-Variable -Name azdSysmonAmaTestMsiProperties -Scope Global -ErrorAction SilentlyContinue
}
