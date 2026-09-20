# Architecture

## Components

The template separates local package generation from optional control-plane and tenant-level actions.

| Component | Ownership | Default |
| --- | --- | --- |
| Sysmon Modular XML bundle | Checked-in generated deployment scripts | Enabled; balanced is the default; MDE-augmented is optional; custom folders can replace the catalog |
| Windows built-in Sysmon optional feature | Enabled by the endpoint script | Used only when a deployment script runs |
| Log Analytics/Sentinel DCR | AZD resource group | Skipped until a workspace resource ID is set |
| Azure VM Run Command and AMA extension | Existing VM resource IDs supplied by the operator | Skipped |
| Intune Remediation | Microsoft Graph beta tenant object | Skipped |
| MDE Live Response library file | Defender for Endpoint tenant object | Skipped |
| Client AMA monitored object and association | Microsoft.Insights tenant-level preview resource | Skipped |

## Sentinel path

The Bicep DCR uses a `windowsEventLogs` data source for `Microsoft-Windows-Sysmon/Operational`, the built-in `Microsoft-Event` stream, and an existing Log Analytics workspace destination. Windows events are stored in the `Event` table. The initial XPath is intentionally broad for a canary:

```text
Microsoft-Windows-Sysmon/Operational!*
```

After measuring volume, narrow the XPath to the event IDs that the selected Sysmon configuration emits and the hunting use case requires. The change remains broad for all resources associated with the DCR; the client AMA association is broader still because it maps to the Entra tenant.

## Association paths

- Azure VMs use `Deploy-AzureVmSysmon.ps1` for Sysmon, `Install-AzureVmAma.ps1` for the `AzureMonitorWindowsAgent` extension when a workspace is enabled, and resource-scoped DCR associations created by `Associate-AzureVmDcr.ps1`.
- Windows clients that use the client installer use the Entra tenant monitored object. `Set-ClientAmaScope.ps1` resolves currently advertised Microsoft.Insights preview API versions from provider metadata and uses `Invoke-AzRestMethod`.
- The template does not attach the Sysmon DCR to unrelated VMs, servers, Arc machines, or existing DCRs unless their resource IDs are explicitly supplied.

## Endpoint installer behavior

Each generated installer:

1. Decodes the embedded Base64 configuration ZIP.
2. Expands it under `C:\ProgramData\AzdSysmon\configs`.
3. Calls the Windows-provided `sysmon` command with `-i` or `-c` and the selected XML.
4. Writes `C:\ProgramData\AzdSysmon\state.json` and verifies the Sysmon event channel.

The scripts do not silently reboot a device. They must run as Local System or an elevated administrator. Built-in Sysmon is supported on Windows 11 and Windows Server 2025 and later; a machine with standalone Sysmon already installed must be remediated separately because the two forms do not coexist.

The package builder can replace the upstream catalog with complete XML files from a custom folder. This keeps the default Olaf bundle unchanged while allowing a deployment to ship only the operator’s selected policy set. Custom choices are derived from top-level XML filename stems and are recorded in the generated package manifest.
