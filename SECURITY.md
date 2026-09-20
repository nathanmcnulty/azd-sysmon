# Security policy

## Scope

This template can install a kernel-backed Windows monitoring service, publish an Intune Remediation, publish a Defender for Endpoint Live Response library script, associate a DCR to Azure VMs, or create a tenant-wide client AMA association. Review every optional setting before use.

## Safe use

- Use a disposable test device or a controlled pilot group first.
- Keep `AZD_SYSMON_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID` empty until the destination and retention/cost expectations are confirmed.
- Keep `AZD_SYSMON_CLIENT_AMA_TENANT_SCOPE` empty unless tenant-wide client targeting is intended and the required role approval is complete.
- Do not put secrets, tokens, passwords, personal data, or SAS URLs in this repository or generated scripts.
- Review event volume and privacy impact before enabling `filedelete` or `excludes-only`.
- Review the MDE-augmented configuration in a pilot before broad use; it is intended to complement Defender for Endpoint, not replace it.
- Keep the configuration source URLs and hashes pinned and review upstream changes before rebuilding. The template relies on Windows’ built-in Sysmon optional feature and does not redistribute an executable.

## Reporting

Report template defects or unsafe behavior through the repository’s normal private security-reporting process. Do not include credentials, access tokens, private endpoint data, or sensitive event payloads in an issue.
