# Validation record

## Clean Server 2025 probe, 16 October 2026

A disposable commercial-lab VM used the exact Marketplace image
`MicrosoftWindowsServer:WindowsServer:2025-datacenter-azure-edition-smalldisk:26100.33650.261013`.
The read-only guest inventory confirmed built-in Sysmon was disabled and no
Sysmon or AMA services existed. The VM interface had no public IP; its NSG was
configured to deny inbound traffic and a NAT gateway supplied outbound access.

Running `scripts/Deploy-AzureVmSysmon.ps1 -Configuration balanced` from revision
`84d0f963d1ba53c90e257a8069006fe8871c7b49` failed during the first install.
`Enable-BuiltInSysmon` emitted its status message and executable path on the
success stream, so the caller attempted to invoke both as a command. The
wrapper rejected the guest stderr and did not report a successful installation.

The shared builder now writes status messages to the host stream. Regenerated
Azure VM, Intune remediation and Live Response installers all preserve the single
path return. Six offline tests execute their actual generated functions with
disabled/enabled feature fixtures: all three disabled cases failed before the
fix and all six cases pass afterward. The XML bundle and configuration hashes
are unchanged.

This trial did not prove the fixed install on a fresh native target, AMA
installation, DCR association, ingestion or VM-preserving solution teardown.
No reboot, tenant assignment, Graph grant, workspace or DCR was performed.
The disposable resource group and managed-identity principal were verified
absent after cleanup; the default CLI subscription remained unchanged.
Private fixture, account, guest-result, source-hash and cleanup receipts remain
outside Git. The fixed-source qualification follows below.

## Fixed Server 2025 VM qualification, 16 October 2026

A second disposable VM used the same exact image and network isolation above.
The initial inventory again showed Sysmon disabled and no Sysmon or AMA service.
The cold Run Command install from `bd943226397e220879148147b3e7080b6c479912`
succeeded without a reboot. Guest readback confirmed the enabled feature,
running Sysmon service, valid Microsoft executable signature, enabled event log,
and the bundled balanced XML hash.

The logging phase exposed two additional native failures: PowerShell consumed
`?api` as part of the association-name variable, and Windows `az.cmd` did not
preserve the inline JSON request body. The association helper now braces the
variable and passes UTF-8 JSON through a temporary file with an explicit JSON
content type. Tests exercise the actual create/remove helper and verify intact
request JSON and temporary-file removal after both successful and failed calls.

The actual `Post-Provision.ps1` hook completed at
`bde7a5fa6f4af54cf91422a929392e35095fc6e2`. Fresh readbacks confirmed AMA 1.45
with automatic upgrade enabled and the named association pointing to the owned
DCR/workspace. The authentic hook receipt recorded both steps. Guest diagnostics
confirmed AMA configuration pickup; a fresh health probe produced a harmless
process marker.
An exact-VM, trial-time-bounded counts query returned 410 Sysmon `Event` rows,
including one marker row, and nine `Heartbeat` rows at 08:53:55 UTC. The original
marker preceded AMA configuration pickup; a deliberate fresh probe supplied the
ingested marker.

The actual `Pre-Down.ps1` hook removed the named association and updated its
receipt while the CLI default subscription remained different from the selected
lab subscription. Association absence was read back. Deleting the DCR-only ARM
resource group then left the VM identity and succeeded AMA extension intact.
This proves the VM-preserving teardown boundary using the real pre-down hook
and ARM group deletion; no `azd down` command was executed in this trial.

The owned workspace was permanently deleted with no matching deleted-workspace
entry. Final fixture cleanup removed the VM group and its managed identity.
The lab security resource provider automatically added an `MDE.Windows` child
extension; its exact VM parent, publisher and creation caller were verified
before including it in fixture cleanup. No Defender plan, grant, tenant-wide
association, Intune assignment or recipient delivery was changed by this trial.
Both groups, the identity principal and ephemeral credential file were verified
absent; the CLI default subscription stayed unchanged. Private failed-attempt,
source, guest, query, ownership and cleanup receipts remain outside Git.

Source validation passed 159/159 tests on PowerShell 7.6.6/Pester 6.2 locally and
on hosted Windows Server 2022 and 2025. SYS-002 is complete for this image and
configuration; clean-client MSI, Defender Live Response and broader recovery
qualification remain separate backlog gates. This is not release authorization.

## Earlier client pilot

The September 20, 2026 validation used a Windows 11 pilot device managed by
Intune and an existing Microsoft Sentinel workspace. Tenant identifiers, device
identifiers, authentication material, and deployment receipts remain outside the
published source tree.

## Verified

- The default package rebuilds offline from vendored XML and produces identical
  bytes across two builds. Source and generated-file SHA-256 pins are checked.
- The canonical Graph authentication component matches its versioned
  `azd-reference` release and lock file.
- Repository checks compile Bicep, parse PowerShell, and exercise package,
  Intune, target selection, deployment receipts, and failure handling.
- Azure provisioning and a repeated provisioning run completed successfully.
- The complete AZD hook sequence completed with both Intune publishers and
  tenant-wide client AMA association enabled.
- AMA MSI content upload, encryption commit, application publication, and the
  required pilot-group assignment succeeded. Rerunning preserved content
  version 1 instead of uploading duplicate content.
- The current Intune installation report includes the pilot device with AMA
  version `1.44.0.0`, `InstallState=1` / `Installed`, and error code `0`.
  The same report also returns a second device-context row marked `Install
  Pending` with the same version and no error; the active AMA heartbeat and
  installed user row confirm the endpoint is running the pinned agent. Keep
  monitoring the duplicate device-context row as Intune reporting converges.
- The tenant monitored-object association points to the newly deployed DCR.
- An on-demand Intune remediation ran on the selected pilot. Sysmon Event 16
  reported the installed configuration hash
  `f115aac5770dae468e5cfb48c58a8b6e37588208a31f1b746812c534577a244b`,
  matching the bundled balanced configuration.
- Fresh Sysmon events arrived after the DCR association changed. Heartbeat and
  the workspace's `_Im_ProcessCreate` ASIM parser returned fresh pilot data.
- A separate run-once scheduled probe executed its remediation at 05:32:31 UTC.
  Sysmon Event 1 captured its unique harmless command marker under SYSTEM, with
  the Intune Management Extension's `HealthScripts/.../remediate.ps1` as parent.
  No on-demand request was sent to this probe.
- A live `azd down` removed the pilot DCR/resource group, receipt-bound Intune
  objects, and the named client AMA association while retaining the tenant
  monitored object, Sentinel workspace, and pilot group. A second `azd down`
  completed successfully with no Azure resources found.

## Limits

The pilot's Intune AMA application installation report and endpoint heartbeat
are now positive. The assignment API accepts `runRemediationScript=true` but
reads it back as `false`; the documented assignment PATCH route also returns an
unsupported-route error in the pilot tenant. The scheduled probe demonstrated
that remediation executes despite that readback. The publisher retains the
documented POST payload. Verify endpoint execution rather than interpreting
this beta response field alone.

The Azure VM extension/Run Command and final Defender Live Response publication
paths were not deployed in this pilot. A reversible live-response authentication
probe did list the tenant library with the legacy Defender resource audience;
the publisher's upload/delete behavior remains covered by local contract tests.
No Defender timeline behavior is inferred from successful Sentinel ingestion.
The client was already running AMA before the new Intune application was
prepared; this pilot alone cannot establish a clean-device AMA installation.

Repeat the relevant live checks when changing agent versions, supported Windows
builds, DCR streams, publisher APIs, or authentication dependencies. Keep actual
endpoint outcomes separate from successful API requests and mocked tests.
