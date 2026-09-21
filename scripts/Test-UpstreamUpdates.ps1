#requires -Version 7.2
[CmdletBinding()]
param(
    [switch]$Run,
    [string]$AmaManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\ama-client-release.json'),
    [string]$SysmonManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\sysmon-modular-release.json'),
    [string]$SysmonReleaseApiUri = 'https://api.github.com/repos/olafhartong/sysmon-modular/releases?per_page=100',
    [string]$ReportPath,
    [string]$SummaryPath
)

$ErrorActionPreference = 'Stop'

function Invoke-UpstreamDownload {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$Path)
    Invoke-WebRequest -Uri $Uri -OutFile $Path -Headers @{ 'User-Agent' = 'azd-sysmon-upstream-monitor' } -ErrorAction Stop | Out-Null
}

function Invoke-SysmonReleaseRequest {
    param([Parameter(Mandatory)][string]$Uri)
    return Invoke-RestMethod -Uri $Uri -Headers @{ 'User-Agent' = 'azd-sysmon-upstream-monitor'; Accept = 'application/vnd.github+json' } -ErrorAction Stop
}

function New-UpdateRecord {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Pinned,
        [Parameter(Mandatory)][string]$Observed,
        [Parameter(Mandatory)][string]$Source
    )
    return [ordered]@{
        kind = $Kind
        name = $Name
        pinned = $Pinned
        observed = $Observed
        source = $Source
    }
}

function Get-AzdSysmonUpstreamUpdateReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AmaManifestPath,
        [Parameter(Mandatory)][string]$SysmonManifestPath,
        [Parameter(Mandatory)][string]$SysmonReleaseApiUri,
        [scriptblock]$DownloadFile = ${function:Invoke-UpstreamDownload},
        [scriptblock]$ReleaseRequest = ${function:Invoke-SysmonReleaseRequest}
    )

    $ama = Get-Content -LiteralPath $AmaManifestPath -Raw | ConvertFrom-Json
    $sysmon = Get-Content -LiteralPath $SysmonManifestPath -Raw | ConvertFrom-Json
    foreach ($property in 'downloadUri', 'sha256', 'release') {
        if ([string]::IsNullOrWhiteSpace([string]$ama.$property)) { throw "AMA manifest is missing '$property'." }
    }
    foreach ($property in 'repository', 'releaseTag', 'configurationAssets') {
        if ($null -eq $sysmon.$property -or [string]::IsNullOrWhiteSpace([string]$sysmon.$property)) { throw "Sysmon manifest is missing '$property'." }
    }

    $updates = [Collections.Generic.List[object]]::new()
    $checks = [Collections.Generic.List[object]]::new()
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('azd-sysmon-upstream-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        $amaPath = Join-Path $tempRoot ([IO.Path]::GetFileName([Uri]$ama.downloadUri))
        & $DownloadFile ([string]$ama.downloadUri) $amaPath | Out-Null
        $observedAmaHash = (Get-FileHash -LiteralPath $amaPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $amaChanged = $observedAmaHash -ne ([string]$ama.sha256).ToLowerInvariant()
        $checks.Add([ordered]@{ kind = 'AMA MSI'; name = [string]$ama.release; pinned = [string]$ama.sha256; observed = $observedAmaHash; source = [string]$ama.downloadUri; changed = $amaChanged })
        if ($amaChanged) {
            $updates.Add((New-UpdateRecord -Kind 'AMA MSI' -Name ([string]$ama.release) -Pinned ([string]$ama.sha256) -Observed $observedAmaHash -Source ([string]$ama.downloadUri)))
        }

        $releaseResponse = @(& $ReleaseRequest $SysmonReleaseApiUri)
        $latestRelease = @($releaseResponse | Where-Object {
                [string]$_.tag_name -match '^configs-' -and
                -not [bool]$_.draft -and
                -not [bool]$_.prerelease -and
                -not [string]::IsNullOrWhiteSpace([string]$_.published_at)
            } | Sort-Object { try { [DateTimeOffset]::Parse([string]$_.published_at) } catch { [DateTimeOffset]::MinValue } } -Descending | Select-Object -First 1)
        if ($latestRelease.Count -ne 1) { throw 'The Sysmon Modular release API did not return exactly one latest configs-* release.' }
        $latestTag = [string]$latestRelease[0].tag_name
        $tagChanged = $latestTag -ne [string]$sysmon.releaseTag
        $checks.Add([ordered]@{ kind = 'Sysmon Modular release'; name = 'releaseTag'; pinned = [string]$sysmon.releaseTag; observed = $latestTag; source = $SysmonReleaseApiUri; changed = $tagChanged })
        if ($tagChanged) {
            $updates.Add((New-UpdateRecord -Kind 'Sysmon Modular release' -Name 'releaseTag' -Pinned ([string]$sysmon.releaseTag) -Observed $latestTag -Source $SysmonReleaseApiUri))
        }

        foreach ($property in $sysmon.configurationAssets.PSObject.Properties) {
            $asset = $property.Value
            if ([string]::IsNullOrWhiteSpace([string]$asset.sourceUrl) -or [string]::IsNullOrWhiteSpace([string]$asset.sha256)) {
                throw "Sysmon asset '$($property.Name)' is missing sourceUrl or sha256."
            }
            $assetPath = Join-Path $tempRoot ([IO.Path]::GetFileName(([Uri]$asset.sourceUrl).AbsolutePath))
            & $DownloadFile ([string]$asset.sourceUrl) $assetPath | Out-Null
            $observedHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $changed = $observedHash -ne ([string]$asset.sha256).ToLowerInvariant()
            $checks.Add([ordered]@{ kind = 'Sysmon configuration'; name = [string]$property.Name; pinned = [string]$asset.sha256; observed = $observedHash; source = [string]$asset.sourceUrl; changed = $changed })
            if ($changed) {
                $updates.Add((New-UpdateRecord -Kind 'Sysmon configuration' -Name ([string]$property.Name) -Pinned ([string]$asset.sha256) -Observed $observedHash -Source ([string]$asset.sourceUrl)))
            }
        }
    } finally {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    return [ordered]@{
        generatedUtc = [DateTime]::UtcNow.ToString('o')
        hasUpdates = $updates.Count -gt 0
        updates = @($updates)
        checks = @($checks)
    }
}

function ConvertTo-UpstreamMarkdown {
    param([Parameter(Mandatory)][object]$Report)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# azd-sysmon upstream update monitor')
    $lines.Add('')
    $lines.Add("Checked: $($Report.generatedUtc)")
    $lines.Add('')
    if ($Report.hasUpdates) {
        $lines.Add('Upstream changes require review before updating the pinned manifests:')
        $lines.Add('')
        $lines.Add('| Source | Name | Pinned | Observed |')
        $lines.Add('| --- | --- | --- | --- |')
        foreach ($update in $Report.updates) {
            $lines.Add("| $($update.kind) | $($update.name) | ``$($update.pinned)`` | ``$($update.observed)`` |")
        }
    } else {
        $lines.Add('All pinned AMA and Sysmon inputs match their current upstream content and release metadata.')
    }
    $lines.Add('')
    $lines.Add('This monitor reports drift; it never rewrites manifests or generated deployment scripts.')
    return ($lines -join [Environment]::NewLine)
}

if ($Run) {
    $report = Get-AzdSysmonUpstreamUpdateReport -AmaManifestPath $AmaManifestPath -SysmonManifestPath $SysmonManifestPath -SysmonReleaseApiUri $SysmonReleaseApiUri
    if ($ReportPath) { $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ReportPath -Encoding UTF8 }
    if ($SummaryPath) { ConvertTo-UpstreamMarkdown -Report $report | Set-Content -LiteralPath $SummaryPath -Encoding UTF8 }
    $report | ConvertTo-Json -Depth 10
}
