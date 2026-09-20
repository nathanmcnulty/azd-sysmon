BeforeAll {
    $sourceRoot = Split-Path -Parent $PSScriptRoot
    function Connect-AzdGraphSession { param($TenantId, $ExpectedAccount, $Scopes, $ProbeUri, [switch]$AllowInteractive, [switch]$AllowContextReplacement) }
    function Invoke-MgGraphRequest { param($Method, $Uri, $Headers, $Body) }
}

Describe 'Intune publishing boundaries' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path "$root/scripts", "$root/config", "$root/deploy/intune" -Force | Out-Null
        Copy-Item "$sourceRoot/scripts/Deploy-IntuneRemediation.ps1" "$root/scripts/"
        Copy-Item "$sourceRoot/config/generated-package-manifest.json" "$root/config/"
        Copy-Item "$sourceRoot/deploy/intune/*.ps1" "$root/deploy/intune/"
        $script:entry = "$root/scripts/Deploy-IntuneRemediation.ps1"
        $script:group = '11111111-1111-4111-8111-111111111111'
        $script:tenant = '22222222-2222-4222-8222-222222222222'
        $script:marker = 'Managed by azd-sysmon; changing this object outside the template can be overwritten.'
        Mock Get-Module { [pscustomobject]@{ Name = 'Microsoft.Graph.Authentication' } }
        Mock Import-Module {}
        Mock Connect-AzdGraphSession {}
        Mock Invoke-MgGraphRequest {
            if ($Method -eq 'GET') { return @{ value = @() } }
            if ($Method -eq 'POST' -and $Uri -notmatch '/assign$') { return @{ id = 'created-id' } }
        }
    }

    It 'authenticates against the explicitly selected account and tenant and adds a daily schedule' {
        & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com'
        Should -Invoke Connect-AzdGraphSession -Times 1 -Exactly -ParameterFilter {
            $TenantId -eq $script:tenant -and $ExpectedAccount -eq 'admin@example.com' -and $AllowInteractive -and -not $AllowContextReplacement
        }
        Should -Invoke Invoke-MgGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -match '/assign$' -and
            ($Body | ConvertFrom-Json).deviceHealthScriptAssignments[0].runSchedule.interval -eq 1 -and
            ($Body | ConvertFrom-Json).deviceHealthScriptAssignments[0].runRemediationScript -eq $true -and
            ($Body | ConvertFrom-Json).deviceHealthScriptAssignments[0].target.groupId -eq $script:group
        }
    }

    It 'finds an owned object on a later page instead of creating a duplicate' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/assignments$') { return @{ value = @() } }
            if ($Uri -match 'skiptoken=next') {
                return @{ value = @(@{ id = 'existing-id'; displayName = 'AZD Sysmon Remediation'; publisher = 'azd-sysmon'; description = 'Managed by azd-sysmon; changing this object outside the template can be overwritten.' }) }
            }
            return @{ value = @(); '@odata.nextLink' = 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts?$skiptoken=next' }
        } -ParameterFilter { $Method -eq 'GET' }
        & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com'
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and $Uri -match '/existing-id$' }
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and ($Body | ConvertFrom-Json).PSObject.Properties.Name -contains 'isGlobalScript' }
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' -and ($Body | ConvertFrom-Json).PSObject.Properties.Name -contains 'version' }
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -notmatch '/assign$' }
    }

    It 'selects the matching configuration hash when publishing a non-default choice' {
        & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' -Configuration filedelete
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Uri -notmatch '/assign$' -and
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($Body | ConvertFrom-Json).detectionScriptContent)).Contains("`$desiredConfiguration = 'filedelete'") -and
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($Body | ConvertFrom-Json).detectionScriptContent)).Contains('92b1239486c0ea8ab4b71ec0298ae89d5e814751337cef0b25b3e3eccf96c050')
        }
    }

    It 'accepts the live unfiltered assignment representation' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/assignments$') {
                return @{ value = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = '11111111-1111-4111-8111-111111111111'; deviceAndAppManagementAssignmentFilterType = 'none'; deviceAndAppManagementAssignmentFilterId = '00000000-0000-0000-0000-000000000000' } }) }
            }
            return @{ value = @(@{ id = 'existing-id'; displayName = 'AZD Sysmon Remediation'; publisher = 'azd-sysmon'; description = 'Managed by azd-sysmon; changing this object outside the template can be overwritten.' }) }
        } -ParameterFilter { $Method -eq 'GET' }
        & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com'
        Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/assign$' }
    }

    It 'refuses to update a script assigned outside the requested group' {
        Mock Invoke-MgGraphRequest {
            if ($Uri -match '/assignments$') {
                return @{ value = @(@{ target = @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } }) }
            }
            return @{ value = @(@{ id = 'existing-id'; displayName = 'AZD Sysmon Remediation'; publisher = 'azd-sysmon'; description = 'Managed by azd-sysmon; changing this object outside the template can be overwritten.' }) }
        } -ParameterFilter { $Method -eq 'GET' }
        { & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' } | Should -Throw '*different or filtered assignment*'
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -ne 'GET' }
    }

    It 'rejects a tampered generated script before authentication or publishing' {
        Add-Content "$root/deploy/intune/Detect-Sysmon.ps1" '# changed'
        { & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' } | Should -Throw '*integrity check failed*'
        Should -Invoke Connect-AzdGraphSession -Times 0 -Exactly
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
    }

    It 'refuses publishing when the canonical authentication check fails' {
        Mock Connect-AzdGraphSession { throw 'Tenant or account mismatch' }
        { & $entry -GroupId $group -TenantId $tenant -ExpectedAccount 'admin@example.com' } | Should -Throw '*mismatch*'
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
    }
}
