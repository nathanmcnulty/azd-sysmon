# azd-sysmon

`azd-sysmon` packages Olaf Hartong’s Sysmon Modular configurations and optionally wires Sysmon Windows Event Log data into an existing Microsoft Sentinel Log Analytics workspace.

The default uses the checked-in deployment artifacts and skips Sentinel collection, Intune, Defender for Endpoint, and Azure VM targeting until their settings are explicitly populated. `azd up` still provisions an Azure resource group; use `scripts/Build-SysmonPackages.ps1` for a purely local package build.

## Quickstart

Prerequisites:

- Azure Developer CLI (`azd`) and Azure CLI (`az`) with normal browser/WAM authentication.
- PowerShell 7.2 or later for the AZD hooks and optional Graph/MDE publishing helpers.
- A Windows 11 test device or Windows Server 2025-and-later Azure VM with administrator/System execution and Sysmon built-in optional-feature support.
- For Sentinel ingestion, an existing Log Analytics workspace used by Microsoft Sentinel.

From this directory:

```powershell
azd auth login
azd init
azd up
```

That default run builds no tenant-wide association and no Log Analytics resource because `AZD_SYSMON_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID` is empty. The generated deployment scripts remain available under `deploy/`.

To enable an existing Sentinel workspace and Azure VM targets:

```powershell
azd env set AZD_SYSMON_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID /subscriptions/<subscription>/resourceGroups/<resource-group>/providers/Microsoft.OperationalInsights/workspaces/<workspace>
azd env set AZD_SYSMON_AZURE_VM_RESOURCE_IDS /subscriptions/<subscription>/resourceGroups/<resource-group>/providers/Microsoft.Compute/virtualMachines/<vm-name>
azd up
```

The optional DCR collects `Microsoft-Windows-Sysmon/Operational` through the `Microsoft-Event` stream into the workspace `Event` table. It does not use the Windows Security Events connector.

## Deployment choices

`AZD_SYSMON_CONFIG` defaults to `balanced`. Available packaged choices are:

- `balanced` — Olaf Hartong’s standard generated configuration.
- `filedelete` — balanced configuration with file-delete events enabled; review volume and privacy impact.
- `excludes-only` — high-volume configuration; use only for a deliberate research or lab workload.
- `mde-augmented` — Olaf’s MDE augmentation configuration, intended to add Sysmon visibility with as little overlap as possible with Defender for Endpoint. Use only where MDE is present and the resulting coverage has been validated.

The configuration XMLs are pinned by source URL and SHA-256 in `config/sysmon-modular-release.json`. The three standard configurations come from the pinned generated release; the MDE-augmented configuration is pinned to its exact upstream generated commit. `scripts/Build-SysmonPackages.ps1` reads those exact sources from `config/vendor/`, verifies their SHA-256, compresses them, and embeds the resulting Base64 bundle into the Intune, Live Response, and Azure VM scripts. Builds work offline. The endpoint scripts enable Windows' built-in Sysmon optional feature and call the built-in `sysmon` command; they do not download or ship a Sysmon executable.

To replace Olaf’s configuration catalog with your own complete Sysmon XML files, use `-CustomConfigurationFolder`. Each top-level XML filename becomes a configuration choice, and Olaf’s files are skipped entirely for that build:

```powershell
pwsh -File .\scripts\Build-SysmonPackages.ps1 `
    -CustomConfigurationFolder .\config\custom `
    -DefaultConfiguration workstation

azd env set AZD_SYSMON_CONFIG workstation
azd up
```

See [config/custom/README.md](config/custom/README.md) for the file naming and validation contract.

### Intune Remediation

The Intune path is opt-in and assigns only to the group you specify:

```powershell
azd env set AZD_SYSMON_DEPLOY_INTUNE true
azd env set AZD_SYSMON_INTUNE_GROUP_ID <entra-group-guid>
azd env set AZD_SYSMON_GRAPH_ACCOUNT <administrator-upn>
azd up
```

The hook uses Microsoft Graph beta `deviceHealthScripts`, runs as System/64-bit, and validates the selected tenant, administrator account, scopes, and a read-only token probe using the vendored azd-reference authentication component. Normal browser/WAM authentication is used when needed. Assignments run daily at 09:00 device-local time; an existing assignment to a different target blocks script updates. The required delegated permission is `DeviceManagementScripts.ReadWrite.All`. Review the target group before enabling this setting.

### Defender for Endpoint Live Response

The script `deploy/live-response/Install-Sysmon.ps1` can be uploaded manually to the Defender Live Response library. To publish it through the MDE API, explicitly enable:

```powershell
azd env set AZD_SYSMON_PUBLISH_LIVE_RESPONSE_LIBRARY true
azd env set AZD_SYSMON_MDE_ACCOUNT <administrator-upn>
azd up
```

The publisher obtains a normal cached Azure CLI token for the Defender API and requires `Library.Manage`. The REST endpoint is `https://api.security.microsoft.com`; token acquisition uses the Defender API's legacy resource audience `https://api.securitycenter.microsoft.com`. Publishing does not automatically run the script on a device; run it from a Live Response session with a configuration key from `config/generated-package-manifest.json`.

### Azure VMs

When `AZD_SYSMON_AZURE_VM_RESOURCE_IDS` is populated, the post-provision hook uses Azure VM Run Command to execute `deploy/azure-vm/Install-Sysmon.ps1` as System. The VM needs the VM agent, permission to run commands, a Windows version exposing the built-in Sysmon optional feature, and normal Windows Event Log operation. If a workspace is also configured, the hook installs/updates `AzureMonitorWindowsAgent` with automatic upgrade enabled and creates a named DCR association on each listed VM. AMA authentication prerequisites, including managed identity, remain the operator’s responsibility.

### Windows client AMA

To package AMA as an Intune application, build the pinned Microsoft MSI once,
then enable its group assignment:

```powershell
pwsh -File ./scripts/Build-AmaPackage.ps1
azd env set AZD_SYSMON_DEPLOY_AMA_APPLICATION true
azd env set AZD_SYSMON_INTUNE_GROUP_ID <entra-group-guid>
azd env set AZD_SYSMON_GRAPH_ACCOUNT <administrator-upn>
```

The MSI is checked for its pinned hash and Microsoft signature and kept outside
Git. The deployment uses the prepared file; it does not download the MSI. See
[AMA application packaging](docs/ama-client-application.md) for permissions and
verification. This group controls where AMA is installed.

For workstations using the Azure Monitor Agent client installer, set all of the following only after reviewing the tenant-wide scope:

```powershell
azd env set AZD_SYSMON_CLIENT_AMA_TENANT_SCOPE true
azd env set AZD_SYSMON_CONFIRM_TENANT_SCOPE I_UNDERSTAND_TENANT_WIDE_SCOPE
azd up
```

The script creates or updates only the named Sysmon association on the tenant monitored object. The DCR applies to every Windows client in the Entra tenant that uses the client-installed AMA; the client AMA API does not provide per-device targeting. The signed-in principal must already have `Monitored Objects Contributor` at the required provider/root scope. The template never grants that role automatically.

## Data flow

```text
Sysmon service
  -> Microsoft-Windows-Sysmon/Operational
  -> AMA client installer or AMA VM extension
  -> Sysmon Windows Events DCR
  -> Microsoft-Event stream
  -> Sentinel Log Analytics workspace
  -> Event table
```

Sentinel’s Windows Security Events solution is not required for this Sysmon path. The DCR is the source of truth for the channel and XPath filter. The template does not promise that every raw Event record will appear in the Defender device timeline; that product view also depends on the Sentinel/Defender integration and entity mapping. Use the verification queries in `docs/operations.md` to establish ingestion first.

## Verification and rollback

See [docs/operations.md](docs/operations.md) for the Event-table queries, heartbeat checks, ASIM checks, and volume measurement.

`azd down` removes resources owned by the AZD environment, including the optional DCR. It does not remove Intune Remediation objects, Intune AMA applications, MDE Live Response library files, or the tenant monitored object. Removing the client AMA association requires the explicit pre-down settings documented in [docs/operations.md](docs/operations.md).

## Documentation

| Topic | Document |
| --- | --- |
| Identity, RBAC, Graph, and MDE permissions | [docs/identity-and-authentication.md](docs/identity-and-authentication.md) |
| Environment variables and configuration | [docs/configuration.md](docs/configuration.md) |
| Resource and data-flow design | [docs/architecture.md](docs/architecture.md) |
| Operations, validation, tuning, and rollback | [docs/operations.md](docs/operations.md) |
| Component ownership and versioned updates | [docs/components.md](docs/components.md) |
| AMA MSI application packaging | [docs/ama-client-application.md](docs/ama-client-application.md) |
| Rebuilding packages and validation | [docs/development.md](docs/development.md) |
| Live validation record and limits | [docs/validation.md](docs/validation.md) |
| Safe agent-assisted deployment checkpoints | [docs/agent-assisted-deployment.md](docs/agent-assisted-deployment.md) |

## Security and license

Original project code and the vendored azd-reference component are released under the [Unlicense](LICENSE). Bundled third-party configurations retain their own license; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). See [SECURITY.md](SECURITY.md). Review the upstream licenses and release notes for [Sysmon Modular](https://github.com/olafhartong/sysmon-modular) and [Microsoft Sysmon](https://learn.microsoft.com/en-us/sysinternals/downloads/sysmon) before distributing a derived package.
