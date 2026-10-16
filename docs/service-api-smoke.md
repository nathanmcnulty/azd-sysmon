# Read-only service API smoke

`scripts/Test-ServiceApis.ps1` checks service access and small response contracts
separately from the pinned AMA/Sysmon input monitor. Without `-Run` it performs
no authentication or service requests. PowerShell 7.6+ and Azure CLI are required.
It uses the existing CLI session; it never logs in, requests consent or grants
permissions. Authenticate through the normal browser/broker flow when needed.

```powershell
./scripts/Test-ServiceApis.ps1 -Run -TenantId $tenantId -SubscriptionId $subscriptionId `
  -ExpectedPrincipalId $principalObjectId -ReportPath .artifacts/service-api-smoke.json
```

The three GUIDs must explicitly identify the commercial lab tenant, selected
subscription and operator/service-principal object ID, respectively. The client
application ID is not the principal object ID. Account tenant/subscription/cloud
are checked before token acquisition. Each CLI-minted token is checked for the
expected tenant, principal, audience and unexpired lifetime before it is sent.
This claim check binds the existing trusted CLI session; it is not a standalone
JWT signature verifier and accepts no externally supplied bearer token.

| Probe | Fixed GET route | Existing authority needed |
| --- | --- | --- |
| Intune mobile applications | Graph `/v1.0/deviceAppManagement/mobileApps?$top=1&$select=id` | `DeviceManagementApps.Read.All` or another documented accepted permission |
| Intune health scripts | Graph `/beta/deviceManagement/deviceHealthScripts?$top=1&$select=id` | `DeviceManagementScripts.Read.All` or its ReadWrite counterpart |
| Client AMA monitored object | ARM `/providers/Microsoft.Insights/monitoredObjects/{tenantId}` | Existing target-scope `Microsoft.Insights/monitoredObjects/read`; provider metadata read at the selected subscription |
| Defender library | `https://api.security.microsoft.com/api/libraryfiles` | `Library.Manage`, which also permits writes despite this checker using only GET |

The monitored-object probe first reads the selected subscription's
`Microsoft.Insights` provider metadata at API `2021-04-01`. It requires exactly
one `monitoredObjects` record and deterministically selects the newest advertised
date-shaped preview version. That is an additional metadata GET, not a fifth
service probe. No provider registration or monitored-object creation occurs.
Defender tokens use the documented legacy resource audience
`https://api.securitycenter.microsoft.com`. Read operations still require the
service's existing licensing, role and API-permission prerequisites. This feature
does not authorize acquiring the broader Defender capability.

Only fixed commercial HTTPS hosts/routes are used. Redirects and pagination are
not followed. Each response has a 30-second total deadline and 2 MiB body limit.
Successful collections must have an array of expected minimal item shapes;
empty collections pass. A successful monitored object must identify the exact
requested tenant object. These are small route/shape checks, not full service
schemas or evidence that a package, policy, assignment or endpoint works.

Reports contain source revision, source-dirty flag, checker SHA-256, UTC time,
method, fixed host, placeholder route, selected API version, HTTP status and
bounded outcome categories. Tokens, account/tenant/subscription/principal IDs,
resource names, response bodies, next links and raw exception messages are not
included. No service resources are changed; no service cleanup is required.
`authUnavailable`, denied access, throttling, transport/size failures, malformed
JSON, unexpected status/shape, and an absent monitored object all make the
aggregate check fail. A 404 on the tenant object is `targetAbsent`, not evidence
of a successful contract or a broken API. Discovery failures are separate from
the monitored-object HTTP result. No request is retried automatically.

## Optional scheduled workflow

`.github/workflows/service-api-smoke.yml` runs weekly or on manual dispatch only
on this repository's `main`, and only when repository variable
`SYSMON_API_SMOKE_ENABLED` equals `true`. It starts disabled. It selects the
existing checksum-pinned PowerShell 7.6.6 runtime and authenticates an existing
identity with immutable-pinned Azure/login OIDC. Configure these repository
secrets outside Git before enabling it:

- `SYSMON_API_SMOKE_CLIENT_ID`
- `SYSMON_API_SMOKE_TENANT_ID`
- `SYSMON_API_SMOKE_SUBSCRIPTION_ID`
- `SYSMON_API_SMOKE_PRINCIPAL_ID`

The existing identity needs a separately reviewed federated credential for
`repo:nathanmcnulty/azd-sysmon:ref:refs/heads/main` with the Azure/login default
audience, plus existing service access from the table above. Authentication does
not grant Graph/Defender/RBAC permissions. This change creates no identity,
credential, grant, secret, issue, notification or required status check, and does
not enable the repository variable. The workflow retains only the redacted JSON
for seven days, including on a failed probe. A preflight/authentication failure
before a report exists leaves no report artifact. Disabling the variable stops
future service checks without changing deployed resources.

## Recorded validation boundary

The 2026-10-16 cached commercial-lab check used checker SHA-256
`0cc02c893826463afe209be28390d41af822be90373d890983c30c7238645ec6`.
Provider discovery and the exact monitored-object GET returned 200 using
`2021-09-01-preview`; Defender library listing returned 200 with the expected
shape. Both Intune GETs returned 403. The report preserved those as
`permissionDenied` and the command exited nonzero. This proves neither an Intune
API failure nor a complete four-route pass. No new access was requested, and no
resources were created or changed. The private receipt binds the dirty source
tree's exact checker bytes and baseline revision; it contains no target GUIDs
or service response bodies. Scheduled OIDC execution has not been enabled or
validated. Its identity, access prerequisites and successful four-route run
remain acceptance gates for SYS-011.

Sources: [Graph mobileApps list](https://learn.microsoft.com/en-us/graph/api/intune-apps-mobileapp-list?view=graph-rest-1.0),
[Graph deviceHealthScripts list](https://learn.microsoft.com/en-us/graph/api/intune-devices-devicehealthscript-list?view=graph-rest-beta),
[Defender library list](https://learn.microsoft.com/en-us/defender-endpoint/api/list-library-files),
and the existing `scripts/Set-ClientAmaScope.ps1` provider-discovery/target contract.
