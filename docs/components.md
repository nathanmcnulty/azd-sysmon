# Component ownership and updates

The template is self-contained. Deployments never fetch source from the private
`azd-reference` repository.

| Component | Version | Source revision | Consumer |
| --- | --- | --- | --- |
| `graph-delegated-authentication` | `0.1.1` | `bc2cf2aad4ff5ebadabe8fd0f0efcf71d94d0e0f` | Intune publisher |

`azd-components.lock.json` records the canonical source repository, component
version, commit, source paths, destination paths, and SHA-256 hashes. The normal
repository checks verify the vendored bytes without access to the source repo.
The canonical portfolio registry tracks this incubating consumer at
`azd-work-in-progress/azd-sysmon`; update its repository and checkout paths when
the standalone repository is published.

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
