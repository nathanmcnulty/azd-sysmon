# azd-sysmon follow-up work

This list records work deferred after the September 2026 public-repository
validation. The current baseline has passed repository validation, live client
Intune/Sentinel validation, live client AMA-association cleanup, and a repeated
idempotent `azd down`. Do not put tenant identifiers, device identifiers,
credentials, tokens, or deployment receipts in this file.

## Live validation

- [ ] Validate the Azure VM path on a disposable Windows VM: Run Command
  installation, built-in Sysmon health, AMA extension provisioning with
  automatic upgrade, named DCR association, fresh `Event` and `Heartbeat`
  records, and the expected VM-preserving teardown boundary.
- [ ] Repeat AMA installation on a clean Windows client or VM that did not have
  AMA preinstalled. Record first install, reboot or pending behavior, repair or
  detection behavior, product code, version, and endpoint heartbeat.
- [ ] Exercise the real Defender Live Response publish/delete path. Use a
  temporary least-privilege application registration with `Library.Manage`,
  publish the marker-owned script, verify it in the library, delete it through
  the cleanup helper, and remove the temporary registration afterward. Execute
  a harmless Live Response command only with separate explicit authorization.
- [ ] Test an Intune AMA content update and rollback using a later pinned MSI:
  verify content-version progression, unchanged reruns, interrupted-upload
  recovery, assignment preservation, and removal of the superseded package.
- [ ] Run a controlled client AMA tenant-scope canary with explicit approval.
  Verify the association affects the intended client population, does not
  alter unrelated DCRs, and is removed cleanly before broad use.
- [ ] Exercise `AZD_SYSMON_PRESERVE_EXTERNAL_RESOURCES` and adopted-object
  behavior against disposable tenant objects. Confirm retained receipts can be
  cleaned deliberately later with the explicit removal setting.
- [ ] Rehearse a partial-failure recovery: interrupt or fail one external
  cleanup step, confirm the resource group is not removed when ownership cannot
  be proven, then rerun after the receipt and object state are reconciled.
- [ ] Measure the canary's event volume by event ID, review privacy and cost,
  and decide whether the broad Sysmon XPath should be narrowed for each
  supported configuration.

## Automated tests and CI

- [ ] Add a manual Windows integration workflow that runs only with explicitly
  supplied disposable Azure, Graph, Intune, and Sentinel targets. Keep tenant
  mutation disabled by default and publish only redacted evidence.
- [ ] Add scheduled, read-only API smoke checks for the Graph Intune routes,
  Microsoft.Insights monitored-object routes, and Defender library routes so
  service-contract drift is detected separately from pinned-input changes.
- [ ] Add tests for truncated or corrupt JSON receipts and make receipt writes
  use a recoverable temporary-file replacement where practical.
- [ ] Add a test matrix for the supported PowerShell versions and Windows
  environments, including the minimum documented PowerShell 7.2 runtime.
- [ ] Test upstream-monitor issue creation with a fixture or isolated test
  repository, including duplicate-issue suppression and failure recovery.
- [ ] Keep GitHub Actions SHAs, Dependabot updates, CodeQL, dependency review,
  and the vendored `azd-reference` lock synchronized after every release.

## Release and maintenance

- [ ] Create a short promotion checklist covering source review, license and
  third-party notice review, component-lock verification, reproducible package
  rebuilds, live evidence, public-repository metadata, and rollback ownership.
- [ ] Define the release evidence required for each optional path: client-only,
  Sentinel/DCR, Azure VM, Intune, tenant-wide client AMA, and MDE Live Response.
- [ ] Add repository ownership metadata such as `CODEOWNERS` and confirm branch
  protection requires validation, CodeQL, dependency review, and at least one
  maintainer review before public releases.
- [ ] Reconcile the public `azd-reference` consumer registry whenever the
  component version, source revision, or canonical repository metadata changes.
- [ ] When Sysmon Modular or AMA publishes a new release, update the exact
  manifests and vendored/generated artifacts together, rebuild twice offline,
  review the diff, and record live compatibility results.
- [ ] Review README, operations, identity, and validation documentation after
  each live test so known limits and endpoint behavior remain current.

## Completion evidence

For each completed item, record the date, code or workflow revision, target
class rather than personal identifiers, commands or queries used, observed
result, cleanup result, and any remaining limitation. Keep sensitive provider
responses and deployment receipts outside the public repository.
