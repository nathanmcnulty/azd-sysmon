# Local deployment artifact inspection

Run this inspector in PowerShell 7.6 or later to check a selected local artifact
set. It performs no authentication, Azure CLI, Graph, Defender, endpoint or
workspace queries. It never installs, assigns, sends, repairs, deletes or writes
receipts. Its output is not cleanup authority.

```powershell
./scripts/Test-DeploymentArtifacts.ps1 -ArtifactRoot C:\private\sysmon-artifacts -Plan
./scripts/Test-DeploymentArtifacts.ps1 -ArtifactRoot C:\private\sysmon-artifacts
```

Create an ordinary local directory containing `target.json` and copies of the
current environment receipts you intend to inspect. Keep these files private.
Use full local paths; network paths, URLs and reparse-point paths are rejected.
Only these four receipt filenames are read: `azd-sysmon-state.json`,
`azd-sysmon-intune-state.json`, `azd-sysmon-ama-application-state.json` and
`azd-sysmon-live-response-state.json`. No `.previous` recovery occurs.

The closed target contract below uses illustrative IDs. Select only the paths
you intend to inspect. `graphAccount` is required for Intune and `mdeAccount`
for Live Response; they must match the local object receipts. Supply the actual
lowercase SHA-256 of each copied receipt in `artifactHashes`, with the exact
filename as its key. A caller-supplied hash binds the inspected bytes; it does
not authenticate a publisher or prove the object still exists.

```json
{
  "schemaVersion": "1.0",
  "environmentName": "pilot",
  "tenantId": "11111111-1111-4111-8111-111111111111",
  "subscriptionId": "22222222-2222-4222-8222-222222222222",
  "graphAccount": "operator@example.invalid",
  "mdeAccount": null,
  "paths": ["package", "intune"],
  "artifactHashes": {}
}
```

For example, obtain a receipt hash with `(Get-FileHash -LiteralPath
C:\private\sysmon-artifacts\azd-sysmon-state.json).Hash.ToLowerInvariant()`.
The empty hash map above cannot qualify a receipt. Unknown properties,
duplicate JSON keys, more than 64 KiB of JSON and JSON nesting beyond 16 levels
are rejected. Package files come only from the checked-in generated manifest
and are bounded to 2 MiB each. The inspector does not execute generated scripts.

| Path | Local result | Remaining live evidence |
| --- | --- | --- |
| `package` | Checked-in manifest and generated script hashes agree | No installation or deployment is inferred from package bytes |
| `intune` | Hash-bound, target-matched remediation/MSI receipts and publication flags | Current assignment, effective installation and endpoint state |
| `azureVm` | Target-matched VM attempt, AMA and association records | Actual Sysmon service/channel and fresh events on each selected VM |
| `sentinel` | Target-matched DCR record | Fresh `Event`/`Heartbeat` ingestion, ASIM and intended workspace behavior |
| `liveResponse` | Target-matched library publication record | Current library object, authorized invocation and endpoint result |

Every path has separate artifact and live-qualification checks. Disabled paths
are skipped. Matching service-related records yield informational results;
missing, mismatched, unbound, malformed or stale records yield warnings. No
selected live-qualification check passes from local files. A package hash check
can pass without proving deployment. `-Plan` validates only the target contract
and returns planned checks without reading receipts or package files.

Receipt age defaults to 24 hours and can be set with
`-MaximumReceiptAgeHours` from 1 to 168. Records more than five minutes in the
future are unusable. This is local recording recency, never event freshness or
service health. The report includes fixed reasons, counts, booleans and the
target-contract hash, omitting receipt contents, accounts and object IDs.
Its environment name is the non-secret label supplied in the target contract;
do not place sensitive values in that label.

The common report is vendored at an immutable revision. See
[component ownership](components.md) for the receipt migration deferral.
`azd-permissions.json` records partial coverage and known gaps; metadata grants
no scopes or roles. Native service and endpoint qualification remain separately
authorized work.
