# Operations

## Verify the endpoint

On a supported Windows 11/Windows Server 2025-and-later target, run as administrator:

```powershell
Get-Service Sysmon64,Sysmon -ErrorAction SilentlyContinue
Get-WindowsOptionalFeature -Online -FeatureName Sysmon
Get-WinEvent -ListLog 'Microsoft-Windows-Sysmon/Operational'
Get-WinEvent -LogName 'Microsoft-Windows-Sysmon/Operational' -MaxEvents 5 |
    Select-Object TimeCreated, Id, ProviderName, Message
```

Generate a benign process event by launching a known executable, then verify the newest event.

## Verify Sentinel ingestion

Use the Log Analytics workspace that backs Sentinel:

```kusto
Event
| where EventLog =~ 'Microsoft-Windows-Sysmon/Operational'
| where Source =~ 'Microsoft-Windows-Sysmon'
| where TimeGenerated > ago(1h)
| project TimeGenerated, Computer, ComputerIP, EventID, SourceComputerId, EventData, RenderedDescription
| order by TimeGenerated desc
```

For one test workstation:

```kusto
Event
| where Computer =~ '<test-device-name>'
| where EventLog =~ 'Microsoft-Windows-Sysmon/Operational'
| summarize Events=count(), FirstSeen=min(TimeGenerated), LastSeen=max(TimeGenerated) by EventID
| order by EventID asc
```

The AMA heartbeat is separate from the Sysmon records. Use the workspace heartbeat query to confirm the agent before investigating XPath or Sysmon configuration:

```kusto
Heartbeat
| where TimeGenerated > ago(2h)
| summarize LastHeartbeat=max(TimeGenerated) by Computer, Category, ComputerIP, SourceComputerId
| order by LastHeartbeat desc
```

## Parse and normalize

First prove the raw `Event` record. Then try the built-in ASIM parsers that match the Sysmon configuration’s event coverage, for example the process, network session, file, registry, or DNS parsers documented in the Microsoft Sentinel ASIM parser catalog. A parser returning no rows can mean either that the configuration does not emit that event type or that the raw XML fields do not meet that parser’s contract.

Do not change Sentinel analytics rules while proving ingestion. Capture the raw record, event ID, host identity, and parser result separately.

## Measure the canary

```kusto
Event
| where EventLog =~ 'Microsoft-Windows-Sysmon/Operational'
| where TimeGenerated > ago(24h)
| summarize Events=count(), Bytes=sum(estimate_data_size(*)) by EventID
| order by Bytes desc
```

Use the result to propose a narrowed XPath. Keep the canary configuration until the proposed event-ID filter has been reviewed, because a client AMA tenant association can affect every client-installed AMA device in the tenant.

## MDE unified timeline boundary

Getting rows into the `Event` table is necessary for Sentinel analysis but does not by itself guarantee that each raw Sysmon record appears in the Defender XDR device timeline. That view depends on the Microsoft Sentinel/Defender integration, entity mapping, parser support, and product-side timeline behavior. Record both outcomes when diagnosing an exporter: raw workspace evidence and the device-timeline/API evidence.

## Rollback

The narrow rollback sequence is:

1. Stop assigning new endpoint scripts.
2. Remove only the named DCR association from Azure VMs or the client AMA monitored object, using the explicit helper for the latter.
3. Run `azd down` to remove the AZD-owned DCR/resource group if it is no longer needed.
4. Remove Intune and MDE library objects separately through their normal consoles/API only after confirming ownership.

The monitored object is not deleted by this template. Existing unrelated DCRs and associations are not modified.

Deployment receipts are stored under `.azure/<environment>/`. Cleanup reads only
that environment's receipt and uses its recorded tenant and subscription. Before
client AMA cleanup, set both `AZD_SYSMON_REMOVE_CLIENT_AMA_ASSOCIATION=true` and
`AZD_SYSMON_CONFIRM_TENANT_SCOPE=I_UNDERSTAND_TENANT_WIDE_SCOPE`. Verify the recorded
association name before running `azd down`.