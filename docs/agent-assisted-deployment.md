# Agent-assisted deployment

Use the following checkpoints when an operator or agent runs the template.

## Before writes

- Confirm the exact Azure subscription, tenant, AZD environment, and workspace resource ID.
- Confirm the Sysmon configuration choice and the selected release hashes.
- Confirm whether the target is an Azure VM, an Intune group, a client-installed AMA tenant, or only a manual Live Response action.
- Preview the plan printed by `Pre-Provision.ps1`.

## Explicit write checkpoints

- A workspace resource ID creates the optional DCR.
- VM resource IDs run an elevated installation on those VMs and create resource-scoped associations.
- `AZD_SYSMON_DEPLOY_INTUNE=true` mutates Microsoft Graph and assigns to the specified group.
- `AZD_SYSMON_DEPLOY_AMA_APPLICATION=true` publishes the prepared, verified AMA MSI and requires it on the specified Intune group.
- `AZD_SYSMON_PUBLISH_LIVE_RESPONSE_LIBRARY=true` publishes a tenant-level MDE library file.
- `AZD_SYSMON_CLIENT_AMA_TENANT_SCOPE=true` changes the tenant-wide monitored-object association and requires the exact confirmation string.

Leave all optional values empty for a package-only run.

## After writes

Capture:

- DCR resource ID and association names;
- endpoint Sysmon state and event-channel evidence;
- heartbeat and raw Event-table query results;
- Intune script/assignment IDs if enabled;
- AMA application/content version, group assignment, and device installation status if enabled;
- MDE library response if published;
- the generated package manifest and release hashes.

Do not describe a deployment as successful based only on Bicep completion or an API response. The endpoint and workspace evidence are the acceptance criteria.
