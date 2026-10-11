# Component ownership and updates

The template is self-contained. Deployments never fetch source from the private
`azd-reference` repository.

| Component | Version | Source revision | Consumer |
| --- | --- | --- | --- |
| `graph-delegated-authentication` | `0.1.1` | `bc2cf2aad4ff5ebadabe8fd0f0efcf71d94d0e0f` | Intune publisher |
| `deployment-validation` | `1.1.1` | `49b21df0b222a35537b9b75e46f851cc7e514c73` | Local artifact inspector |

`azd-components.lock.json` records the canonical source repository, component
version, commit, source paths, destination paths, and SHA-256 hashes. The normal
repository checks verify the vendored bytes without access to the source repo.
The canonical portfolio registry tracks the public consumer at
`nathanmcnulty/azd-sysmon`. Keep the registry entry aligned with this repository
when the component baseline or canonical checkout changes.

Maintainers with an `azd-reference` checkout can update explicitly:

```powershell
& ../azd-reference/tooling/Sync-AzdComponent.ps1 `
    -Component graph-delegated-authentication -Version <reviewed-version> `
    -TargetPath <azd-sysmon-directory>
& ../azd-reference/tooling/Test-AzdComponentDrift.ps1 -TargetPath <azd-sysmon-directory>
```

Review the source release, resulting diff, lock, and repository test results
together. Do not edit managed files directly or fetch a moving branch during
deployment. Roll back a component update by reverting its consumer change.

Sysmon configuration packaging, endpoint installation, DCR configuration, and
target-selection policy remain solution-owned. They do not yet have a second
proven consumer that warrants a shared runtime abstraction. Their configuration
sources have a separate upstream release/hash manifest and third-party notices.

Deployment-validation is adopted only for check definitions, planned checks and
the schema-valid local report described in [deployment artifacts](deployment-artifacts.md).
The CLI verifies all three vendored hashes before import. It does not add service
queries, permissions or a runtime dependency on Reference. The existing Graph
authentication component remains at 0.1.1.

The candidate [deployment-receipt 0.2.1](https://github.com/nathanmcnulty/azd-reference/blob/49b21df0b222a35537b9b75e46f851cc7e514c73/components/powershell/deployment-receipt/component.json)
is deferred. Its common report/management-binding schema does not replace the
solution's object-type, environment, tenant, subscription, object ID, account,
`adoptedExisting` and mutation flags consumed by cleanup. `Azd.Receipt.ps1`
also writes atomically with an explicit previous-file backup; readers do not
silently recover that backup. Migrating receipts requires an explicit producer,
reader, recovery and cleanup compatibility change. This inspector reads the
existing receipts and does not rewrite or authorize them.
