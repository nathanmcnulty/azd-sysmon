# Component ownership and updates

The template is self-contained. Deployments never fetch source from the private
`azd-reference` repository.

| Component | Version | Source revision | Consumer |
| --- | --- | --- | --- |
| `graph-delegated-authentication` | `0.2.0` | `fbb521e468ed129f951e7e13ecf0134986fdbd75` | Intune publisher |
| `deployment-validation` | `2.0.0` | `fbb521e468ed129f951e7e13ecf0134986fdbd75` | Local artifact inspector |

`azd-components.lock.json` records the canonical source repository, component
version, commit, source paths, destination paths, and SHA-256 hashes. The normal
repository checks verify the vendored bytes without access to the source repo.
The canonical portfolio registry tracks the public consumer at
`nathanmcnulty/azd-sysmon`. Keep the registry entry aligned with this repository
when the component baseline or canonical checkout changes.

This migration consumes the exact reviewed candidate from [azd-reference PR #99](https://github.com/nathanmcnulty/azd-reference/pull/99). Merge that canonical baseline before this consumer update; the lock uses its immutable commit, without a moving-branch dependency. The baseline changes the component versions and runtime manifests; the implementation and schema bytes remain identical.

Maintainers with an `azd-reference` checkout can update explicitly:

```powershell
& ../azd-reference/tooling/Sync-AzdComponent.ps1 `
    -Component graph-delegated-authentication -Revision fbb521e468ed129f951e7e13ecf0134986fdbd75 `
    -TargetPath <azd-sysmon-directory>
& ../azd-reference/tooling/Sync-AzdComponent.ps1 `
    -Component deployment-validation -Revision fbb521e468ed129f951e7e13ecf0134986fdbd75 `
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
queries, permissions or a runtime dependency on Reference. Both consumed components require PowerShell 7.6 or later.

The candidate [deployment-receipt 0.3.0](https://github.com/nathanmcnulty/azd-reference/blob/fbb521e468ed129f951e7e13ecf0134986fdbd75/components/powershell/deployment-receipt/component.json)
is deferred. Its common report/management-binding schema does not replace the
solution's object-type, environment, tenant, subscription, object ID, account,
`adoptedExisting` and mutation flags consumed by cleanup. `Azd.Receipt.ps1`
also writes atomically with an explicit previous-file backup; readers do not
silently recover that backup. Migrating receipts requires an explicit producer,
reader, recovery and cleanup compatibility change. This inspector reads the
existing receipts and does not rewrite or authorize them.
