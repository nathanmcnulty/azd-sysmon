# Azure Monitor Agent Intune application

`Build-AmaPackage.ps1` obtains the Microsoft Azure Monitor Agent Windows client MSI from the exact `download.microsoft.com` URL in `config/ama-client-release.json`. It checks the pinned SHA-256 and a valid Microsoft Authenticode signature, then stores the MSI in `.artifacts/ama/`. The MSI is intentionally not committed.

`Deploy-IntuneAmaApplication.ps1` publishes that MSI as an Intune `windowsMobileMSI` line-of-business application. It encrypts the content with the `ProfileVersion1` layout, waits for the Intune upload URI and commit states with bounded polling, commits the content version, and makes a required group assignment.

The publisher needs the **object ID**, not the display name, of the intended group. Resolve and review the object ID for your pilot device group before publishing:

```powershell
pwsh -File .\scripts\Build-AmaPackage.ps1
pwsh -File .\scripts\Deploy-IntuneAmaApplication.ps1 `
  -GroupId <pilot-group-object-id> `
  -TenantId <tenant-guid> `
  -ExpectedAccount <administrator-upn> `
  -EnvironmentName default
```

The delegated scope is `DeviceManagementApps.ReadWrite.All`, together with an Intune role that can manage mobile applications and assignments. Authentication uses the checked-in `Azd.GraphAuthentication` 0.1.1 component and its normal cached broker/browser flow; it never uses device-code authentication.

The app is named `Azure Monitor Agent (azd-sysmon)` and is marked in its description. The publisher refuses duplicate names, an unmarked same-name app unless `-AdoptExisting` is explicit, and any existing assignment that is not the requested unfiltered group. Re-running for the same committed release refreshes only the app metadata and required group assignment; it does not upload another content version. SAS URLs and Graph tokens are never written to output.

If a first upload was interrupted before its initial content version committed, Intune rejects creating another version. The publisher reuses one initial uncommitted file only when its name, sizes, and manifest exactly match the package, then uploads the encrypted blocks again and commits it. It stops for review when the version or file is ambiguous or mismatched.

After a successful mutation it records only the app ID, group ID, tenant ID, release, package hash, and timestamp in `.azure/<environment>/azd-sysmon-ama-application-state.json`.

This app scopes installation to the Intune group. After installation, AMA data collection rules for Windows client MSI installations still apply at the Microsoft Entra tenant scope; see [Microsoft's client AMA guidance](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-windows-client).

The client must be Microsoft Entra joined or hybrid joined, have the supported
Visual C++ redistributable installed, and reach the documented AMA endpoints.
The application uses the default silent MSI settings. It does not provision
these prerequisites or configure a network proxy. Check the Intune device
installation status, the local Azure Monitor Agent service, and fresh workspace
heartbeat after deployment; a published application alone does not prove an
endpoint installation.

The content-encryption layout and upload sequence were independently implemented with the [Microsoft Intune PowerShell SDK `UploadLobApp` sample](https://github.com/microsoft/Intune-PowerShell-SDK/blob/master/Samples/Apps/UploadLobApp.psm1) as a behavioral reference. That sample is MIT licensed, Copyright (c) Microsoft Corporation.
