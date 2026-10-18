#requires -Version 7.6
BeforeAll {
    $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
    $script:pwsh = (Get-Process -Id $PID).Path
}

Describe 'Repository validator real Pester outcomes' {
    It 'requires a passing suite: <Case>' -ForEach @(
        @{ Case = 'pass'; Accepted = $true },
        @{ Case = 'inconclusive'; Accepted = $false }
    ) {
        $fixtureRoot = Join-Path $TestDrive $Case
        $output = & $script:pwsh -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'helpers/Invoke-RepositoryOutcomeFixture.ps1') `
            -RepositoryRoot $script:repositoryRoot -FixtureRoot $fixtureRoot -Case $Case 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
        $receipt = Get-Content -LiteralPath (Join-Path $fixtureRoot 'receipt.json') -Raw | ConvertFrom-Json
        $receipt.fixtureRan | Should -BeTrue
        $receipt.pester | Should -Be '6.2.0'
        $receipt.succeeded | Should -Be $Accepted
        if (-not $Accepted) {
            $receipt.failure | Should -Be 'Behavioral validation failed: every registered test must pass without skipped, inconclusive or unexecuted cases.'
        }
    }
}
