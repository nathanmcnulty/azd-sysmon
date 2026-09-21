# Development and validation

## Rebuild the embedded package

The generated scripts are checked in so Intune and MDE can consume them without a build-time network dependency. Rebuild only when changing the pinned release or default configuration:

```powershell
pwsh -File .\scripts\Build-SysmonPackages.ps1 -DefaultConfiguration balanced
```

The builder reads the vendored XMLs from `config/vendor/` pinned by `config/sysmon-modular-release.json`, or uses the complete XML files supplied with `-CustomConfigurationFolder`, verifies their hashes, normalizes archive timestamps, uses `Compress-Archive`, and writes the generated files under `deploy/`. Review the generated diff and `config/generated-package-manifest.json`. No Sysmon executable is downloaded or embedded. A custom folder replaces the upstream catalog for that build.

## Repository validation

```powershell
pwsh -File .\scripts\Test-Repository.ps1
```

Install Pester 5.7.1 and Azure CLI with Bicep before running validation. It checks PowerShell parsing, the DCR contract, Bicep compilation, generated script integrity and size, vendored component hashes, and behavioral tests using mocked service boundaries. These checks do not authenticate or deploy.

## Test order

1. Inspect the generated diff and release hashes.
2. Run static validation.
3. In a disposable Windows test device or VM, run the installer as administrator/System.
4. Verify the Sysmon service and event channel.
5. Enable the optional DCR and association for only the explicitly selected scope.
6. Generate a benign event and verify `Event` and `Heartbeat` in the workspace.
7. Test the intended ASIM parser and timeline/exporter behavior separately.

The repository validation does not claim that a live endpoint, Sentinel workspace, or Defender timeline is currently connected.

## Update configuration sources

Fetch new upstream XMLs only during an explicit maintainer update. Review the
upstream revision and license, replace the exact bytes in `config/vendor/`, and
update their release URLs and SHA-256 values in `config/sysmon-modular-release.json`.
Then rebuild twice and compare hashes. The normal Sysmon build is offline;
deployment never fetches configuration files or private component sources.

The scheduled `Monitor upstream inputs` workflow runs
`scripts/Test-UpstreamUpdates.ps1` weekly and on manual dispatch. It downloads
the pinned AMA MSI and Sysmon configuration URLs into a temporary runner
directory, compares their SHA-256 values, and checks the latest
`configs-*` Sysmon Modular release tag. It never rewrites the repository. A
detected change opens one review issue and fails the monitor until the maintainer
reviews the upstream release, updates the manifests and generated scripts, and
reruns repository validation. Run the same check locally with:

```powershell
pwsh -File .\scripts\Test-UpstreamUpdates.ps1 -Run
```

## Public repository maintenance

The standalone validation workflow is included under
`.github/workflows/validate.yml`. For changes that affect a live endpoint,
validate install/update/detection and fresh events, then the selected AMA/DCR
ingestion route and Intune assignment. Capture actual results separately from
mocked tests. Publish only project files; exclude `.azure`, downloaded MSI
artifacts, local reports, and credentials. Keep third-party notices alongside
the Unlicense, and keep the canonical consumer registry aligned with this
public repository.
