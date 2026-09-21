# Identity and authentication

This template never uses device-code authentication. Use the normal cached account broker or browser flow:

```powershell
az login
azd auth login
```

If a helper needs a missing token, it invokes the standard interactive command without a device-code switch. If that flow cannot authenticate or obtain consent, stop and resolve the identity/consent issue rather than changing the authentication method.

## Azure RBAC

The signed-in Azure identity needs enough access to:

- deploy the AZD resource group and the optional DCR;
- install/update the `AzureMonitorWindowsAgent` extension on explicitly listed Azure VMs;
- associate a DCR to explicitly listed Azure VMs, normally through `Virtual Machine Contributor` or an equivalent custom permission;
- for client AMA tenant scope, already hold `Monitored Objects Contributor` at the Microsoft.Insights provider/root scope.

The template does not grant root-scope permissions. Pre-grant the required role through the organization’s normal approval path, then set the explicit tenant-scope confirmation string.

## Microsoft Graph and Intune

The optional Intune helper uses delegated Graph permissions:

- `DeviceManagementScripts.ReadWrite.All`


The optional AMA MSI application publisher additionally uses
`DeviceManagementApps.ReadWrite.All`. Client AMA association management reuses the
selected Azure CLI account and checks its tenant, subscription, and cloud before
acquiring an ARM token. It does not require a separate Azure PowerShell login.
The pre-down cleanup uses the same delegated Graph permissions to delete only
receipt-bound objects whose ownership markers and group assignments still match.

The user also needs the appropriate Intune RBAC role and licensing. The helper creates or updates only the object marked `Managed by azd-sysmon`; it refuses to adopt an unrelated object with the same display name unless `-AdoptExisting` is supplied deliberately.

## Defender for Endpoint

The optional Live Response library publisher uses the Defender API permission `Library.Manage`. It publishes the script only. Running the script against a device remains a separate Live Response action and requires the appropriate MDE device permissions and device-group remediation level.
The same `Library.Manage` permission is used by `azd down` to remove the exact
receipt-bound library file after verifying its filename and ownership marker.

The publisher calls `https://api.security.microsoft.com`, but requests the token
with the legacy Defender resource audience `https://api.securitycenter.microsoft.com`.
The API currently rejects the non-`api` resource name and may return `403` for a
token whose audience is the REST endpoint instead of the legacy resource.

## Authentication boundaries

Tokens are acquired at runtime and are not stored in this repository. Do not place client secrets, passwords, access tokens, SAS URLs, or personal data in AZD environment values or generated scripts.

The Intune publisher imports `graph-delegated-authentication@0.1.1` from local
vendored files. It requires PowerShell 7.2+ and Microsoft.Graph.Authentication
2.30.0+. Set `AZD_SYSMON_GRAPH_ACCOUNT` to the intended administrator UPN;
`AZURE_TENANT_ID` is verified against the AZD subscription before provisioning.
A mismatched inherited Graph session fails closed. To deliberately replace it,
run the Intune helper with `-AllowContextReplacement` after reviewing the tenant
and account. No authentication module is downloaded by the deployment hooks.
