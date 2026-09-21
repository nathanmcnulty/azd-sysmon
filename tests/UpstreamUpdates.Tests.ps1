#requires -Version 7.2
BeforeAll {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $scriptRoot 'scripts/Test-UpstreamUpdates.ps1')
}

Describe 'Upstream input monitoring' {
    BeforeEach {
        $script:fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('azd-sysmon-monitor-test-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:fixtureRoot -Force | Out-Null
        $script:payloads = @{
            'https://example.test/ama.msi' = [Text.Encoding]::UTF8.GetBytes('ama-pinned')
            'https://example.test/balanced.xml' = [Text.Encoding]::UTF8.GetBytes('balanced-pinned')
        }
        $amaBytes = $script:payloads['https://example.test/ama.msi']
        $sysmonBytes = $script:payloads['https://example.test/balanced.xml']
        $amaHash = [Convert]::ToHexString(([Security.Cryptography.SHA256]::Create().ComputeHash($amaBytes))).ToLowerInvariant()
        $sysmonHash = [Convert]::ToHexString(([Security.Cryptography.SHA256]::Create().ComputeHash($sysmonBytes))).ToLowerInvariant()
        $script:amaManifest = Join-Path $script:fixtureRoot 'ama.json'
        $script:sysmonManifest = Join-Path $script:fixtureRoot 'sysmon.json'
        @{ release = 'test'; downloadUri = 'https://example.test/ama.msi'; sha256 = $amaHash } |
            ConvertTo-Json | Set-Content -LiteralPath $script:amaManifest -Encoding UTF8
        @{ repository = 'https://github.com/example/sysmon'; releaseTag = 'configs-test'; configurationAssets = [ordered]@{ balanced = @{ sourceUrl = 'https://example.test/balanced.xml'; sha256 = $sysmonHash } } } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:sysmonManifest -Encoding UTF8
        $script:download = {
            param($Uri, $Path)
            [IO.File]::WriteAllBytes($Path, $script:payloads[$Uri])
        }
        $script:releaseRequest = {
            param($Uri)
            @([pscustomobject]@{ tag_name = 'configs-test'; published_at = '2026-09-20T00:00:00Z' })
        }
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:fixtureRoot) { Remove-Item -LiteralPath $script:fixtureRoot -Recurse -Force }
    }

    It 'accepts pinned AMA and Sysmon inputs when upstream matches' {
        $report = Get-AzdSysmonUpstreamUpdateReport -AmaManifestPath $script:amaManifest -SysmonManifestPath $script:sysmonManifest -SysmonReleaseApiUri 'https://example.test/releases' -DownloadFile $script:download -ReleaseRequest $script:releaseRequest
        $report.hasUpdates | Should -BeFalse
        @($report.updates).Count | Should -Be 0
        @($report.checks).Count | Should -Be 3
    }

    It 'reports an AMA hash change without rewriting the manifest' {
        $script:payloads['https://example.test/ama.msi'] = [Text.Encoding]::UTF8.GetBytes('ama-new')
        $report = Get-AzdSysmonUpstreamUpdateReport -AmaManifestPath $script:amaManifest -SysmonManifestPath $script:sysmonManifest -SysmonReleaseApiUri 'https://example.test/releases' -DownloadFile $script:download -ReleaseRequest $script:releaseRequest
        $report.hasUpdates | Should -BeTrue
        @($report.updates | Where-Object { $_.kind -eq 'AMA MSI' }).Count | Should -Be 1
        ((Get-Content -LiteralPath $script:amaManifest -Raw | ConvertFrom-Json).sha256) | Should -Be (([Convert]::ToHexString(([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes('ama-pinned'))))).ToLowerInvariant())
    }

    It 'reports a Sysmon release tag and asset change' {
        $script:releaseRequest = { param($Uri) @([pscustomobject]@{ tag_name = 'configs-new'; published_at = '2026-09-21T00:00:00Z' }) }
        $script:payloads['https://example.test/balanced.xml'] = [Text.Encoding]::UTF8.GetBytes('balanced-new')
        $report = Get-AzdSysmonUpstreamUpdateReport -AmaManifestPath $script:amaManifest -SysmonManifestPath $script:sysmonManifest -SysmonReleaseApiUri 'https://example.test/releases' -DownloadFile $script:download -ReleaseRequest $script:releaseRequest
        @($report.updates | Where-Object { $_.kind -eq 'Sysmon Modular release' }).Count | Should -Be 1
        @($report.updates | Where-Object { $_.kind -eq 'Sysmon configuration' }).Count | Should -Be 1
    }
}
