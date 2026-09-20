# Configuration

The template uses AZD environment values so the safe default is an empty optional setting rather than an implicit tenant mutation.

## Core settings

| Setting | Default | Effect |
| --- | --- | --- |
| `AZD_SYSMON_CONFIG` | `balanced` | Packaged configuration used by the Intune path and defaulted by the VM/Live Response paths. The standard choices are `balanced`, `filedelete`, `excludes-only`, and `mde-augmented`; a custom build uses the XML filename stems instead. |
| `AZD_SYSMON_DCR_NAME` | `dcr-sysmon-<environment>` | Name of the optional DCR in the AZD resource group. |
| `AZD_SYSMON_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID` | empty | Existing workspace resource ID. Empty means no DCR or Sentinel integration is provisioned. |
| `AZD_SYSMON_PROMPT_FOR_OPTIONAL_SETTINGS` | empty/false | If true, the pre-provision hook asks for a workspace ID when one is not already set. Pressing Enter keeps the integration disabled. |
| `AZD_SYSMON_AZURE_VM_RESOURCE_IDS` | empty | Comma-, semicolon-, or newline-separated full Azure VM resource IDs. Empty means no VM installation or DCR association. |

## Explicit feature gates

| Setting | Required companion | Effect |
| --- | --- | --- |
| `AZD_SYSMON_DEPLOY_INTUNE=true` | `AZD_SYSMON_INTUNE_GROUP_ID=<GUID>` and `AZD_SYSMON_GRAPH_ACCOUNT=<administrator UPN>` | Creates/updates the owned Graph beta Remediation and assigns it to exactly the specified group. |
| `AZD_SYSMON_DEPLOY_AMA_APPLICATION=true` | Prepared MSI from `Build-AmaPackage.ps1`, group GUID and Graph account above | Publishes the pinned AMA client MSI as a required Intune application for that group. |
| `AZD_SYSMON_PUBLISH_LIVE_RESPONSE_LIBRARY=true` | MDE `Library.Manage` and `AZD_SYSMON_MDE_ACCOUNT=<administrator UPN>` | Uploads the generated Live Response script to the tenant library. It does not run it. |
| `AZD_SYSMON_CLIENT_AMA_TENANT_SCOPE=true` | workspace ID plus `AZD_SYSMON_CONFIRM_TENANT_SCOPE=I_UNDERSTAND_TENANT_WIDE_SCOPE` | Creates/updates the named tenant monitored-object association. This is tenant-wide for client-installed AMA and is intentionally fail-closed. |
| `AZD_SYSMON_REMOVE_CLIENT_AMA_ASSOCIATION=true` | confirmation string above | During `azd down`, removes only the recorded client AMA association. The monitored object is retained. |

## Selecting another Intune default

The embedded Intune detection and remediation scripts must agree on the selected default. Rebuild them and review the generated diff before changing the environment value:

```powershell
pwsh -File .\scripts\Build-SysmonPackages.ps1 -DefaultConfiguration filedelete
azd env set AZD_SYSMON_CONFIG filedelete
```

Live Response and Azure VM scripts accept the configuration as a script argument even when the generated default remains `balanced`.

The MDE-augmented option is pinned to Olaf’s immutable generated source commit in `config/sysmon-modular-release.json`. It is a collection choice, not an MDE licensing or onboarding change; the endpoint still needs Defender for Endpoint if the goal is complementary MDE telemetry.

## Replacing the packaged configurations

The builder accepts a custom folder containing one or more complete Sysmon XML configurations:

```powershell
pwsh -File .\scripts\Build-SysmonPackages.ps1 `
    -CustomConfigurationFolder .\config\custom `
    -DefaultConfiguration workstation

azd env set AZD_SYSMON_CONFIG workstation
azd up
```

The folder is a replacement source, not an overlay: when it is supplied, Olaf’s configurations are not downloaded or included. Each top-level `.xml` file becomes a choice based on its filename stem, such as `workstation.xml` → `workstation`; keys are normalized to lowercase and must contain only letters, numbers, and hyphens. The builder validates the Sysmon XML shape, records SHA-256 hashes in `config/generated-package-manifest.json`, and rejects generated Intune scripts at or above 200 KB.

External deployment targets require an explicit `AZURE_SUBSCRIPTION_ID`. The pre-provision hook verifies its AzureCloud tenant and records `AZURE_TENANT_ID`. Workspace and VM targets must belong to that subscription. Intune assignments run daily at 09:00 device-local time. Existing assignments to other targets or filtered assignments block updates until reviewed in Intune.
