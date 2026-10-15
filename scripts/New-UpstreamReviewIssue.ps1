#requires -Version 7.6

Set-StrictMode -Version Latest

function Invoke-AzdSysmonGhCommand {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = & gh @Arguments 2>$null
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = ($output -join [Environment]::NewLine)
    }
}

function New-AzdSysmonUpstreamReviewIssue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+\z')][string]$Repository,
        [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$SummaryPath,
        [scriptblock]$GhInvoker = ${function:Invoke-AzdSysmonGhCommand}
    )

    $title = 'Upstream update detected: azd-sysmon pinned inputs'
    $listArguments = @('api', '--paginate', '--slurp', "/repos/$Repository/issues?state=open&per_page=100")
    $listResult = & $GhInvoker $listArguments
    if ($null -eq $listResult -or $listResult -isnot [pscustomobject] -or
        $listResult.PSObject.Properties.Name -notcontains 'ExitCode' -or
        $listResult.ExitCode -isnot [int] -or
        $listResult.PSObject.Properties.Name -notcontains 'Output' -or
        $listResult.Output -isnot [string] -or $listResult.ExitCode -ne 0) {
        throw 'Could not inspect existing upstream monitor issues.'
    }

    try {
        $parsed = $listResult.Output | ConvertFrom-Json -Depth 20 -NoEnumerate -ErrorAction Stop
        if ($parsed -isnot [array]) {
            throw 'Issue response was not a paginated array.'
        }
        $pages = @($parsed)
        $issues = [Collections.Generic.List[object]]::new()
        foreach ($page in $pages) {
            if ($page -isnot [array]) {
                throw 'Issue response contained a malformed page.'
            }
            foreach ($issue in @($page)) {
                if ($null -eq $issue -or $issue -isnot [pscustomobject] -or
                    $issue.PSObject.Properties.Name -notcontains 'title' -or
                    $issue.title -isnot [string] -or [string]::IsNullOrWhiteSpace($issue.title) -or
                    $issue.PSObject.Properties.Name -notcontains 'number' -or
                    $issue.number -isnot [long] -or $issue.number -le 0) {
                    throw 'Issue response contained a malformed issue.'
                }
                $issues.Add($issue)
            }
        }
    }
    catch {
        throw 'Could not parse existing upstream monitor issues.'
    }

    $duplicate = @($issues | Where-Object {
            $isPullRequest = $null -ne $_ -and $null -ne $_.PSObject.Properties['pull_request'] -and $null -ne $_.pull_request
            $_ -and $_.title -eq $title -and -not $isPullRequest
        })
    if ($duplicate.Count -gt 0) {
        return [pscustomobject]@{ Created = $false; Duplicate = $true; Title = $title }
    }
    if (-not $PSCmdlet.ShouldProcess($Repository, 'Create upstream monitor review issue')) {
        return [pscustomobject]@{ Created = $false; Duplicate = $false; Title = $title }
    }

    $bodyFile = Join-Path ([IO.Path]::GetTempPath()) ('azd-sysmon-upstream-issue-' + [Guid]::NewGuid().ToString('N') + '.md')
    try {
        $summary = Get-Content -LiteralPath $SummaryPath -Raw -ErrorAction Stop
        $body = @"
The scheduled upstream monitor found a change in a pinned AMA or Sysmon input.

Review the report below, update the manifest and vendored/generated artifacts deliberately, run the full repository validation, and close this issue only after the new hashes and release metadata are reviewed.

$summary
"@
        [IO.File]::WriteAllText($bodyFile, $body, [Text.UTF8Encoding]::new($false))
        $createArguments = @('issue', 'create', '--repo', $Repository, '--title', $title, '--body-file', $bodyFile)
        $createResult = & $GhInvoker $createArguments
        if ($null -eq $createResult -or $createResult -isnot [pscustomobject] -or
            $createResult.PSObject.Properties.Name -notcontains 'ExitCode' -or
            $createResult.ExitCode -isnot [int] -or
            $createResult.PSObject.Properties.Name -notcontains 'Output' -or
            $createResult.Output -isnot [string] -or $createResult.ExitCode -ne 0) {
            throw 'Could not create the upstream monitor review issue.'
        }
        return [pscustomobject]@{ Created = $true; Duplicate = $false; Title = $title }
    }
    finally {
        if (Test-Path -LiteralPath $bodyFile) {
            Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
        }
    }
}
