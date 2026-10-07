# Backlog: nathanmcnulty/azd-sysmon

> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.
> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.

- **Schema version:** 1.0.0
- **Repository:** nathanmcnulty/azd-sysmon
- **Source revision:** `c20bbdb63e03279aec524ead39cdf1359ebc5701`
- **Captured:** 2026-10-07
- **Items:** 23

## SYS-001: Reconcile this backlog with current source and active work

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Plans and implementation evidence are spread across files; the captured source can change while other tasks work.

**Scope:**

- docs/backlog.json
- docs/backlog.md
- Existing roadmap, execution status, open issues and pull requests &lpar;read-only&rpar;

**Acceptance:**

- Classify each candidate as implemented, still open, superseded or awaiting evidence; retain source links and reasons.
- Inspect dirty state, remotes, worktrees and local environment presence without reading secrets; avoid duplicate work with active owners.
- Resolve the actual offline validation commands and record exact current default-branch/working-tree provenance; do not copy historical live passes to newer code.

**Validation:**

- git status --short
- git remote -v
- git worktree list --porcelain
- Read the applicable instructions and validation workflow; read gh issue list and gh pr list for the named repository using nathanmcnulty. Do not create or modify issues/PRs.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- README.md
- TODO.md

**Evidence:**

- 2026-10-04 read-only reconciliation against current main 5f3f185a72fce107e9b97373d922342a5f8e3afd&colon; inspected canonical dirty state, remotes, worktrees and environment-path presence without reading values; active/unowned branches remain untouched. Reviewed current issue/PR inventory, roadmap/TODO task sources and .github/workflows/validate.yml; kept live and optional-feature gates proposed.
- Invoke-Pester ./tests -CI&colon; 65/65 passed, including teardown receipts and explicit tenant-association decision guards. Validation used offline fixtures only; no cloud, tenant, recipient or endpoint action was performed.

**Review and authorization note:**

Review SYS-001 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-023: Require a teardown decision before leaving tenant AMA association to deleted DCR

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Open report captured 2026-10-03 during execution reconciliation. Another code-quality task may own an active fix; inspect its PR and current source before dispatch.

**Scope:**

- Linked issue and current source &lpar;read-only&rpar;
- Repository-local backlog evidence

**Acceptance:**

- Read the linked issue and current default branch; classify the exact defect, current owner and evidence gap.
- Record a current PR or verified resolution before selecting any implementation; preserve broader feature and live acceptance gates.

**Validation:**

- Read current issue and PR state using nathanmcnulty; do not modify or close issues during reconciliation.
- Inspect dirty state and worktrees; resolve the exact current revision and relevant offline commands before implementation.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-sysmon/issues/10

**Evidence:**

- Source implementation is present in current main 5f3f185a72fce107e9b97373d922342a5f8e3afd; resolved revision 5f3f185a72fce107e9b97373d922342a5f8e3afd. Current main adds the explicit teardown decision guard.
- Invoke-Pester ./tests -CI&colon; 65/65 passed, including teardown receipts and explicit tenant-association decision guards. This completes only the bounded source/fixture acceptance; live-service, recovery, release and endpoint gates remain separate.

**Review and authorization note:**

Review SYS-023 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-010: Add a manual Windows integration workflow that runs only with explicitly supplied disposable Azure, Graph, Intune, and Sentinel targets

- **Kind:** maintenance
- **Priority:** P2
- **Status:** proposed
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Add a manual Windows integration workflow that runs only with explicitly supplied disposable Azure, Graph, Intune, and Sentinel targets. Keep tenant mutation disabled by default and publish only redacted evidence.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Add a manual Windows integration workflow that runs only with explicitly supplied disposable Azure, Graph, Intune, and Sentinel targets. Keep tenant mutation disabled by default and publish only redacted evidence.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-010 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-011: Add scheduled, read-only API smoke checks for the Graph Intune routes, Microsoft.Insights monitored-object routes, and Defender library routes so service-contract drift is detected separately from pinned-input changes

- **Kind:** maintenance
- **Priority:** P2
- **Status:** proposed
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Add scheduled, read-only API smoke checks for the Graph Intune routes, Microsoft.Insights monitored-object routes, and Defender library routes so service-contract drift is detected separately from pinned-input changes.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Add scheduled, read-only API smoke checks for the Graph Intune routes, Microsoft.Insights monitored-object routes, and Defender library routes so service-contract drift is detected separately from pinned-input changes.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-011 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-012: Add tests for truncated or corrupt JSON receipts and make receipt writes use a recoverable temporary-file replacement where practical

- **Kind:** maintenance
- **Priority:** P2
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Add tests for truncated or corrupt JSON receipts and make receipt writes use a recoverable temporary-file replacement where practical.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Add tests for truncated or corrupt JSON receipts and make receipt writes use a recoverable temporary-file replacement where practical.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- 2026-10-07 reviewed source implementation on base 719915e6adb36881085a0aad2275c45933490edb and exact source/test tree f749e178de63fdc10fa59730962b5c0e4c5fa690&colon; the four environment-scoped AZD ownership receipts now use a PowerShell 5.1-compatible helper that writes and flushes a unique same-directory candidate, validates its JSON, then uses filesystem replacement with a stable .previous version. First writes use a same-directory move. Corrupt or truncated primary receipts fail closed; .previous and candidate files require explicit operator review and are never loaded automatically. A failed replacement preserves the original receipt and its validated candidate.
- Focused Invoke-Pester coverage passed 41/41 for receipt, deployment and cleanup behavior. Receipt.Tests.ps1 passed 6/6 independently, including native Windows PowerShell 5.1 first-write/read/repeated-replacement coverage, immediate .previous rotation, locked-target failure preservation, corrupt and truncated JSON rejection, and no automatic recovery. The test fixtures cover the main deployment receipt plus Intune remediation, Intune AMA application and Defender Live Response child receipts.
- ./scripts/Test-Repository.ps1 passed static validation, deterministic package checks and 74/74 Pester tests. PSScriptAnalyzer reported zero error-severity findings across the changed PowerShell files, git diff --check passed, and azd-components.lock.json plus generated endpoint/package files remained byte-identical to origin/main. No cloud query, provider mutation, assignment, reboot, external cleanup or endpoint action was run; temporary test receipts were isolated to Pester TestDrive and removed by the test harness.

**Review and authorization note:**

Review SYS-012 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-013: Add a test matrix for the supported PowerShell versions and Windows environments, including the minimum documented PowerShell 7.2 runtime

- **Kind:** maintenance
- **Priority:** P2
- **Status:** proposed
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Add a test matrix for the supported PowerShell versions and Windows environments, including the minimum documented PowerShell 7.2 runtime.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Add a test matrix for the supported PowerShell versions and Windows environments, including the minimum documented PowerShell 7.2 runtime.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-013 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-014: Test upstream-monitor issue creation with a fixture or isolated test repository, including duplicate-issue suppression and failure recovery

- **Kind:** maintenance
- **Priority:** P2
- **Status:** proposed
- **Wave:** 1
- **Authorization:** publication
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Test upstream-monitor issue creation with a fixture or isolated test repository, including duplicate-issue suppression and failure recovery.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Test upstream-monitor issue creation with a fixture or isolated test repository, including duplicate-issue suppression and failure recovery.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-014 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-015: Keep GitHub Actions SHAs, Dependabot updates, CodeQL, dependency review, and the vendored &grave;azd-reference&grave; lock synchronized after every release

- **Kind:** maintenance
- **Priority:** P2
- **Status:** proposed
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Keep GitHub Actions SHAs, Dependabot updates, CodeQL, dependency review, and the vendored &grave;azd-reference&grave; lock synchronized after every release.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Keep GitHub Actions SHAs, Dependabot updates, CodeQL, dependency review, and the vendored &grave;azd-reference&grave; lock synchronized after every release.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-015 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-016: Create a short promotion checklist covering source review, license and third-party notice review, component-lock verification, reproducible package rebuilds, live evidence, public-repository metadata, and rollback ownership

- **Kind:** maintenance
- **Priority:** P2
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Create a short promotion checklist covering source review, license and third-party notice review, component-lock verification, reproducible package rebuilds, live evidence, public-repository metadata, and rollback ownership.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Create a short promotion checklist covering source review, license and third-party notice review, component-lock verification, reproducible package rebuilds, live evidence, public-repository metadata, and rollback ownership.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- 2026-10-07 on base c20bbdb63e03279aec524ead39cdf1359ebc5701, added docs/release-evidence.md with a bounded source, license/notice, immutable component-lock, reproducible-build, live-evidence, public-metadata, independent-review, and rollback-owner promotion checklist. It requires private evidence for tenant/device/provider material and keeps live acceptance, grants, assignment, reboot, cleanup, release, and enforcement claims pending.
- The checklist records exact existing commands and queries, input/output hash requirements, raw Git-index versus working-tree hash distinction, fresh retry directories, and receipt-bound rollback limits. README links the guide; no runtime, test, workflow, component pin, or historical validation record changed.
- Final documentation packet validated with pwsh -File ./scripts/Test-Repository.ps1&colon; 74 tests passed with no failures. Canonical backlog schema and generated-view checks passed; script parameters and literal evidence-query boundaries were checked against current source. This is offline source and mocked-contract evidence only; no live target, grant, assignment, cleanup or release operation ran.

**Review and authorization note:**

Review SYS-016 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-017: Define the release evidence required for each optional path

- **Kind:** maintenance
- **Priority:** P2
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Define the release evidence required for each optional path&colon; client-only, Sentinel/DCR, Azure VM, Intune, tenant-wide client AMA, and MDE Live Response.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Define the release evidence required for each optional path&colon; client-only, Sentinel/DCR, Azure VM, Intune, tenant-wide client AMA, and MDE Live Response.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- 2026-10-07 on base c20bbdb63e03279aec524ead39cdf1359ebc5701, defined docs/release-evidence.md path-specific evidence gates for client-only, Sentinel/DCR, Azure VM, Intune, tenant-wide client AMA, and MDE Live Response. Each row distinguishes control-plane/API/readback evidence from fresh endpoint, ingestion, execution, and human-visible proof.
- Recorded existing script parameter names and Event/Heartbeat Kusto queries, private/public redaction boundaries, target class and cleanup requirements, and historical limits from docs/validation.md. No live operation, tenant mutation, assignment, reboot, cleanup, publication, or enforcement action was performed.
- Final documentation packet validated with pwsh -File ./scripts/Test-Repository.ps1&colon; 74 tests passed with no failures. Canonical backlog schema and generated-view checks passed; script parameters and literal evidence-query boundaries were checked against current source. This is offline source and mocked-contract evidence only; no live target, grant, assignment, cleanup or release operation ran.

**Review and authorization note:**

Review SYS-017 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-018: Add repository ownership metadata such as &grave;CODEOWNERS&grave; and confirm branch protection requires validation, CodeQL, dependency review, and at least one maintainer review before public releases

- **Kind:** maintenance
- **Priority:** P2
- **Status:** proposed
- **Wave:** 1
- **Authorization:** publication
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Add repository ownership metadata such as &grave;CODEOWNERS&grave; and confirm branch protection requires validation, CodeQL, dependency review, and at least one maintainer review before public releases.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Add repository ownership metadata such as &grave;CODEOWNERS&grave; and confirm branch protection requires validation, CodeQL, dependency review, and at least one maintainer review before public releases.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-018 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-019: Reconcile the public &grave;azd-reference&grave; consumer registry whenever the component version, source revision, or canonical repository metadata changes

- **Kind:** maintenance
- **Priority:** P2
- **Status:** proposed
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Reconcile the public &grave;azd-reference&grave; consumer registry whenever the component version, source revision, or canonical repository metadata changes.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Reconcile the public &grave;azd-reference&grave; consumer registry whenever the component version, source revision, or canonical repository metadata changes.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-019 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-020: When Sysmon Modular or AMA publishes a new release, update the exact manifests and vendored/generated artifacts together, rebuild twice offline, review the diff, and record live compatibility results

- **Kind:** maintenance
- **Priority:** P2
- **Status:** proposed
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; When Sysmon Modular or AMA publishes a new release, update the exact manifests and vendored/generated artifacts together, rebuild twice offline, review the diff, and record live compatibility results.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- When Sysmon Modular or AMA publishes a new release, update the exact manifests and vendored/generated artifacts together, rebuild twice offline, review the diff, and record live compatibility results.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-020 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-021: Review README, operations, identity, and validation documentation after each live test so known limits and endpoint behavior remain current

- **Kind:** maintenance
- **Priority:** P2
- **Status:** proposed
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Review README, operations, identity, and validation documentation after each live test so known limits and endpoint behavior remain current.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Review README, operations, identity, and validation documentation after each live test so known limits and endpoint behavior remain current.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-021 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-002: Validate the Azure VM path on a disposable Windows VM

- **Kind:** verification
- **Priority:** P1
- **Status:** proposed
- **Wave:** 2
- **Authorization:** tenant-write
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Validate the Azure VM path on a disposable Windows VM&colon; Run Command installation, built-in Sysmon health, AMA extension provisioning with automatic upgrade, named DCR association, fresh &grave;Event&grave; and &grave;Heartbeat&grave; records, and the expected VM-preserving teardown boundary.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Validate the Azure VM path on a disposable Windows VM&colon; Run Command installation, built-in Sysmon health, AMA extension provisioning with automatic upgrade, named DCR association, fresh &grave;Event&grave; and &grave;Heartbeat&grave; records, and the expected VM-preserving teardown boundary.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-002 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-003: Repeat AMA installation on a clean Windows client or VM that did not have AMA preinstalled

- **Kind:** verification
- **Priority:** P1
- **Status:** proposed
- **Wave:** 2
- **Authorization:** tenant-write
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Repeat AMA installation on a clean Windows client or VM that did not have AMA preinstalled. Record first install, reboot or pending behavior, repair or detection behavior, product code, version, and endpoint heartbeat.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Repeat AMA installation on a clean Windows client or VM that did not have AMA preinstalled. Record first install, reboot or pending behavior, repair or detection behavior, product code, version, and endpoint heartbeat.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-003 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-004: Exercise the real Defender Live Response publish/delete path

- **Kind:** verification
- **Priority:** P1
- **Status:** proposed
- **Wave:** 2
- **Authorization:** publication
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Exercise the real Defender Live Response publish/delete path. Use a temporary least-privilege application registration with &grave;Library.Manage&grave;, publish the marker-owned script, verify it in the library, delete it through the cleanup helper, and remove the temporary registration afterward. Execute a harmless Live Response command only with separate explicit authorization.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Exercise the real Defender Live Response publish/delete path. Use a temporary least-privilege application registration with &grave;Library.Manage&grave;, publish the marker-owned script, verify it in the library, delete it through the cleanup helper, and remove the temporary registration afterward. Execute a harmless Live Response command only with separate explicit authorization.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-004 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-005: Test an Intune AMA content update and rollback using a later pinned MSI

- **Kind:** verification
- **Priority:** P1
- **Status:** proposed
- **Wave:** 2
- **Authorization:** tenant-write
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Test an Intune AMA content update and rollback using a later pinned MSI&colon; verify content-version progression, unchanged reruns, interrupted-upload recovery, assignment preservation, and removal of the superseded package.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Test an Intune AMA content update and rollback using a later pinned MSI&colon; verify content-version progression, unchanged reruns, interrupted-upload recovery, assignment preservation, and removal of the superseded package.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-005 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-006: Run a controlled client AMA tenant-scope canary with explicit approval

- **Kind:** verification
- **Priority:** P1
- **Status:** proposed
- **Wave:** 2
- **Authorization:** tenant-write
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Run a controlled client AMA tenant-scope canary with explicit approval. Verify the association affects the intended client population, does not alter unrelated DCRs, and is removed cleanly before broad use.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Run a controlled client AMA tenant-scope canary with explicit approval. Verify the association affects the intended client population, does not alter unrelated DCRs, and is removed cleanly before broad use.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-006 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-007: Exercise &grave;AZD&lowbar;SYSMON&lowbar;PRESERVE&lowbar;EXTERNAL&lowbar;RESOURCES&grave; and adopted-object behavior against disposable tenant objects

- **Kind:** verification
- **Priority:** P1
- **Status:** proposed
- **Wave:** 2
- **Authorization:** tenant-write
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Exercise &grave;AZD&lowbar;SYSMON&lowbar;PRESERVE&lowbar;EXTERNAL&lowbar;RESOURCES&grave; and adopted-object behavior against disposable tenant objects. Confirm retained receipts can be cleaned deliberately later with the explicit removal setting.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Exercise &grave;AZD&lowbar;SYSMON&lowbar;PRESERVE&lowbar;EXTERNAL&lowbar;RESOURCES&grave; and adopted-object behavior against disposable tenant objects. Confirm retained receipts can be cleaned deliberately later with the explicit removal setting.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-007 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-008: Rehearse a partial-failure recovery

- **Kind:** verification
- **Priority:** P1
- **Status:** proposed
- **Wave:** 2
- **Authorization:** tenant-write
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Rehearse a partial-failure recovery&colon; interrupt or fail one external cleanup step, confirm the resource group is not removed when ownership cannot be proven, then rerun after the receipt and object state are reconciled.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Rehearse a partial-failure recovery&colon; interrupt or fail one external cleanup step, confirm the resource group is not removed when ownership cannot be proven, then rerun after the receipt and object state are reconciled.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-008 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-009: Measure the canary&#39;s event volume by event ID, review privacy and cost, and decide whether the broad Sysmon XPath should be narrowed for each supported configuration

- **Kind:** verification
- **Priority:** P1
- **Status:** proposed
- **Wave:** 2
- **Authorization:** tenant-write
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Deferred existing follow-up&colon; Measure the canary&#39;s event volume by event ID, review privacy and cost, and decide whether the broad Sysmon XPath should be narrowed for each supported configuration.

**Scope:**

- scripts/
- tests/
- docs/
- .github/workflows/

**Acceptance:**

- Measure the canary&#39;s event volume by event ID, review privacy and cost, and decide whether the broad Sysmon XPath should be narrowed for each supported configuration.
- Record exact revision, target class, commands/queries, observed result and cleanup; keep tenant/device identifiers and credentials outside Git.
- Do not expand assignment, reboot, cleanup, issue creation or required-check scope without explicit authorization.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-009 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## SYS-022: Evaluate common deployment-validation evidence for optional paths

- **Kind:** discovery
- **Priority:** P2
- **Status:** proposed
- **Wave:** 2
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Existing Graph authentication reuse does not yet standardize each optional-path readiness and endpoint gate.

**Scope:**

- scripts/
- docs/
- azd-components.lock.json

**Acceptance:**

- Represent package-only, Intune, Azure VM, Sentinel and Live Response paths independently.
- Compare deployment-validation and candidate receipts with existing owned-object cleanup before adopting.
- Never present DCR association or an Intune success row as fresh Event/Heartbeat or effective endpoint installation.

**Validation:**

- From the solution root run ./scripts/Test-Repository.ps1
- Run focused tests for changed behavior from tests/; fixtures do not prove live-service or endpoint behavior.

**Dependencies:**

- _none_

**Components:**

- deployment-validation
- deployment-receipt

**Sources:**

- README.md
- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review SYS-022 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.
