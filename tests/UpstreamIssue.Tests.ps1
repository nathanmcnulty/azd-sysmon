#requires -Version 7.6

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'scripts' 'New-UpstreamReviewIssue.ps1')
    $script:Title = 'Upstream update detected: azd-sysmon pinned inputs'
}

Describe 'New-AzdSysmonUpstreamReviewIssue' {
    BeforeEach {
        $script:Root = Join-Path ([IO.Path]::GetTempPath()) ('azd-sysmon-fixture-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
        $script:Summary = Join-Path $script:Root 'summary.md'
        $script:SummaryText = "Changed pin: café / 東京`r`nSecond line & symbols"
        [IO.File]::WriteAllText($script:Summary, $script:SummaryText, [Text.UTF8Encoding]::new($false))
    }

    AfterEach {
        Remove-Item -LiteralPath $script:Root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates one issue with exact UTF8 body and cleans the temporary body file' {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $fake = {
            param([string[]]$Arguments)
            $script:Calls.Add($Arguments)
            if ($Arguments[0] -eq 'api') {
                return [pscustomobject]@{ ExitCode = 0; Output = '[[{"number":1,"title":"unrelated"}]]' }
            }
            $bodyPath = $Arguments[$Arguments.IndexOf('--body-file') + 1]
            $script:ObservedBody = [IO.File]::ReadAllText($bodyPath)
            $script:BodyExistedDuringCreate = Test-Path -LiteralPath $bodyPath
            return [pscustomobject]@{ ExitCode = 0; Output = 'https://github.example/issues/1' }
        }

        $result = New-AzdSysmonUpstreamReviewIssue -Repository 'owner/repo' -SummaryPath $script:Summary -GhInvoker $fake

        $result.Created | Should -BeTrue
        $result.Duplicate | Should -BeFalse
        $script:Calls.Count | Should -Be 2
        $script:Calls[0] | Should -Be @('api', '--paginate', '--slurp', '/repos/owner/repo/issues?state=open&per_page=100')
        $script:Calls[1][0..5] | Should -Be @('issue', 'create', '--repo', 'owner/repo', '--title', $script:Title)
        $normalizedBody = $script:ObservedBody -replace "`r`n", "`n"
        $normalizedSummary = $script:SummaryText -replace "`r`n", "`n"
        $normalizedBody | Should -Be "The scheduled upstream monitor found a change in a pinned AMA or Sysmon input.`n`nReview the report below, update the manifest and vendored/generated artifacts deliberately, run the full repository validation, and close this issue only after the new hashes and release metadata are reviewed.`n`n$normalizedSummary"
        $script:ObservedBody | Should -Match 'café / 東京'
        $script:BodyExistedDuringCreate | Should -BeTrue
        Test-Path -LiteralPath $script:Calls[1][$script:Calls[1].IndexOf('--body-file') + 1] | Should -BeFalse
    }

    It 'suppresses a duplicate found on a later paginated page and ignores pull requests' {
        $script:CreateCalls = 0
        $fake = {
            param([string[]]$Arguments)
            if ($Arguments[0] -eq 'api') {
                $pages = @(
                    @(@{ number = 1; title = 'unrelated' }),
                    @(@{ number = 2; title = $script:Title; pull_request = @{ url = 'https://github.example/pulls/2' } }),
                    @(@{ number = 3; title = $script:Title; html_url = 'https://github.example/issues/3' })
                )
                return [pscustomobject]@{ ExitCode = 0; Output = ($pages | ConvertTo-Json -Depth 8 -Compress) }
            }
            $script:CreateCalls++
            return [pscustomobject]@{ ExitCode = 0; Output = 'unexpected' }
        }

        $result = New-AzdSysmonUpstreamReviewIssue -Repository 'owner/repo' -SummaryPath $script:Summary -GhInvoker $fake

        $result.Duplicate | Should -BeTrue
        $result.Created | Should -BeFalse
        $script:CreateCalls | Should -Be 0
    }

    It 'fails closed on list failure or malformed list output without writing' -TestCases @(
        @{ Output = 'provider failure'; ExitCode = 1 }
        @{ Output = 'not json'; ExitCode = 0 }
        @{ Output = '{"number":1,"title":"wrong outer shape"}'; ExitCode = 0 }
        @{ Output = '[{"number":1,"title":"wrong page shape"}]'; ExitCode = 0 }
        @{ Output = '[[{"title":"missing number"}]]'; ExitCode = 0 }
        @{ Output = '[[null]]'; ExitCode = 0 }
    ) {
        param($Output, $ExitCode)
        $script:CreateCalls = 0
        $fake = {
            param([string[]]$Arguments)
            if ($Arguments[0] -eq 'api') {
                return [pscustomobject]@{ ExitCode = $ExitCode; Output = $Output }
            }
            $script:CreateCalls++
            return [pscustomobject]@{ ExitCode = 0; Output = 'unexpected' }
        }

        { New-AzdSysmonUpstreamReviewIssue -Repository 'owner/repo' -SummaryPath $script:Summary -GhInvoker $fake } | Should -Throw
        $script:CreateCalls | Should -Be 0
    }

    It 'uses the native gh wrapper with an argument array and checks its exit code without network access' {
        function global:gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
            $script:NativeGhArguments = $Arguments
            if ($Arguments[0] -eq 'api') {
                $global:LASTEXITCODE = 0
                return '[[{"number":1,"title":"shim unrelated"}]]'
            }
            $global:LASTEXITCODE = 7
        }
        try {
            $result = Invoke-AzdSysmonGhCommand -Arguments @('api', '/repos/owner/repo/issues?state=open&per_page=100')
            $failure = Invoke-AzdSysmonGhCommand -Arguments @('issue', 'create', '--repo', 'owner/repo')
        }
        finally {
            Remove-Item Function:\gh -Force -ErrorAction SilentlyContinue
        }

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Be '[[{"number":1,"title":"shim unrelated"}]]'
        $failure.ExitCode | Should -Be 7
        $script:NativeGhArguments | Should -Be @('issue', 'create', '--repo', 'owner/repo')
    }

    It 'keeps the workflow wiring bound to the helper and update failure' {
        $workflow = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' '.github/workflows/monitor-upstream.yml') -Raw
        $workflow | Should -Match '\. ./scripts/New-UpstreamReviewIssue\.ps1'
        $workflow | Should -Match 'New-AzdSysmonUpstreamReviewIssue -Repository \$env:GITHUB_REPOSITORY -SummaryPath \$env:SUMMARY_PATH'
        $workflow | Should -Match 'Pinned upstream inputs changed\.'
        $workflow | Should -Match "if: steps.check.outputs.hasUpdates == 'true'"
        $runMatch = [regex]::Match($workflow, '(?s)      - name: Open a review issue for upstream changes.*?        run: \|\r?\n(?<body>.*)\z')
        $runMatch.Success | Should -BeTrue
        $runBlock = [scriptblock]::Create(($runMatch.Groups['body'].Value -replace '(?m)^          ', ''))
        $previousRepo = $env:GITHUB_REPOSITORY
        $previousSummary = $env:SUMMARY_PATH
        $script:WorkflowCreates = 0
        $script:WorkflowBodyPath = $null
        function global:gh {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
            $global:LASTEXITCODE = 0
            if ($Arguments[0] -eq 'api') { return '[[]]' }
            if ($Arguments[0] -ne 'issue' -or $Arguments[1] -ne 'create') { throw 'Unexpected fixture command.' }
            $script:WorkflowCreates++
            $script:WorkflowBodyPath = $Arguments[$Arguments.IndexOf('--body-file') + 1]
            (Get-Content -LiteralPath $script:WorkflowBodyPath -Raw) | Should -Match 'café / 東京'
            return 'https://github.example/issues/5'
        }
        Push-Location (Split-Path -Parent $PSScriptRoot)
        try {
            $env:GITHUB_REPOSITORY = 'owner/repo'
            $env:SUMMARY_PATH = $script:Summary
            { & $runBlock } | Should -Throw '*Pinned upstream inputs changed.*'
            $script:WorkflowCreates | Should -Be 1
            Test-Path -LiteralPath $script:WorkflowBodyPath | Should -BeFalse
        }
        finally {
            Pop-Location
            $env:GITHUB_REPOSITORY = $previousRepo
            $env:SUMMARY_PATH = $previousSummary
            Remove-Item Function:\gh -Force -ErrorAction SilentlyContinue
        }
    }

    It 'creates an issue when the matching title belongs only to a pull request' {
        $script:CreateCalls = 0
        $fake = {
            param([string[]]$Arguments)
            if ($Arguments[0] -eq 'api') {
                return [pscustomobject]@{ ExitCode = 0; Output = '[[{"number":2,"title":"Upstream update detected: azd-sysmon pinned inputs","pull_request":{"url":"https://github.example/pulls/2"}}]]' }
            }
            $script:CreateCalls++
            return [pscustomobject]@{ ExitCode = 0; Output = 'https://github.example/issues/3' }
        }
        (New-AzdSysmonUpstreamReviewIssue -Repository 'owner/repo' -SummaryPath $script:Summary -GhInvoker $fake).Created | Should -BeTrue
        $script:CreateCalls | Should -Be 1
    }

    It 'rejects a CLI result without a typed exit code before creating an issue' {
        $script:CreateCalls = 0
        $fake = {
            param([string[]]$Arguments)
            if ($Arguments[0] -eq 'api') { return [pscustomobject]@{ Output = '[[]]' } }
            $script:CreateCalls++
        }
        { New-AzdSysmonUpstreamReviewIssue -Repository 'owner/repo' -SummaryPath $script:Summary -GhInvoker $fake } | Should -Throw
        $script:CreateCalls | Should -Be 0
    }

    It 'performs no create in an explicitly requested WhatIf run' {
        $script:CreateCalls = 0
        $fake = {
            param([string[]]$Arguments)
            if ($Arguments[0] -eq 'api') { return [pscustomobject]@{ ExitCode = 0; Output = '[[]]' } }
            $script:CreateCalls++
        }
        $result = New-AzdSysmonUpstreamReviewIssue -Repository 'owner/repo' -SummaryPath $script:Summary -GhInvoker $fake -WhatIf
        $result.Created | Should -BeFalse
        $script:CreateCalls | Should -Be 0
    }

    It 'rejects a repository value that is not an owner/name pair' {
        { New-AzdSysmonUpstreamReviewIssue -Repository 'owner/repo/extra' -SummaryPath $script:Summary -GhInvoker { param([string[]]$Arguments) throw 'must not invoke gh' } } | Should -Throw
    }

    It 'cleans the body file when create fails' {
        $script:BodyPath = $null
        $fake = {
            param([string[]]$Arguments)
            if ($Arguments[0] -eq 'api') { return [pscustomobject]@{ ExitCode = 0; Output = '[[{"number":1,"title":"unrelated"}]]' } }
            $script:BodyPath = $Arguments[$Arguments.IndexOf('--body-file') + 1]
            return [pscustomobject]@{ ExitCode = 1; Output = 'provider failure must not be surfaced' }
        }

        { New-AzdSysmonUpstreamReviewIssue -Repository 'owner/repo' -SummaryPath $script:Summary -GhInvoker $fake } | Should -Throw
        $script:BodyPath | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:BodyPath | Should -BeFalse
    }

    It 'relists after an uncertain create result and suppresses a later duplicate' {
        $script:ListCount = 0
        $script:CreateCount = 0
        $fake = {
            param([string[]]$Arguments)
            if ($Arguments[0] -eq 'api') {
                $script:ListCount++
                if ($script:ListCount -eq 1) { return [pscustomobject]@{ ExitCode = 0; Output = '[[{"number":1,"title":"unrelated"}]]' } }
                $page = @(@{ number = 4; title = $script:Title; html_url = 'https://github.example/issues/4' })
                return [pscustomobject]@{ ExitCode = 0; Output = (ConvertTo-Json -InputObject (,@($page)) -Depth 8 -Compress) }
            }
            $script:CreateCount++
            return [pscustomobject]@{ ExitCode = 1; Output = 'timeout after provider accepted request' }
        }

        { New-AzdSysmonUpstreamReviewIssue -Repository 'owner/repo' -SummaryPath $script:Summary -GhInvoker $fake } | Should -Throw
        $retry = New-AzdSysmonUpstreamReviewIssue -Repository 'owner/repo' -SummaryPath $script:Summary -GhInvoker $fake

        $retry.Duplicate | Should -BeTrue
        $script:ListCount | Should -Be 2
        $script:CreateCount | Should -Be 1
    }
}
