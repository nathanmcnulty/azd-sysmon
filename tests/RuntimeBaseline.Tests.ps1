#requires -Version 7.6
BeforeAll {
    $sourceRoot = Split-Path -Parent $PSScriptRoot
}
Describe 'Maintained management and test baseline' {
    It 'requires PowerShell 7.6 for every owned management and test entry point' {
        $paths = @(Get-ChildItem (Join-Path $sourceRoot 'scripts') -File -Filter '*.ps1' | Where-Object Name -ne 'Install-PowerShellRuntime.ps1')
        $paths += @(Get-ChildItem (Join-Path $sourceRoot 'tests') -File -Filter '*.ps1')
        foreach ($path in $paths) {
            (Get-Content -LiteralPath $path.FullName -First 1) | Should -BeExactly '#requires -Version 7.6' -Because $path.Name
        }
    }
    It 'installs and imports exact Pester 6.2.0 in CI and logs the local selected versions' {
        $workflow = Get-Content (Join-Path $sourceRoot '.github/workflows/validate.yml') -Raw
        $workflow | Should -Match 'Install-Module Pester -RequiredVersion 6\.2\.0'
        $workflow | Should -Match 'Import-Module Pester -RequiredVersion 6\.2\.0'
        $workflow | Should -Match 'Test-Repository.ps1 -PesterVersion 6\.2\.0'
        $runner = Get-Content (Join-Path $sourceRoot 'scripts/Test-Repository.ps1') -Raw
        $runner | Should -Match 'Import-Module Pester -MinimumVersion 6\.2\.0'
        $runner | Should -Match 'Import-Module Pester -RequiredVersion \$PesterVersion'
        $runner | Should -Match 'Selected PowerShell.*PSVersionTable.PSVersion.*Pester.*Get-Module Pester'
        $runner | Should -Not -Match '5\.7\.1|Assert-MockCalled'
        $runner | Should -Match '\$result.FailedContainersCount -gt 0'
    }
    It 'rejects an explicitly requested Pester version below the supported floor before validation' {
        { & (Join-Path $sourceRoot 'scripts/Test-Repository.ps1') -PesterVersion 5.7.1 } |
            Should -Throw '*PesterVersion*6.2.0 or later*'
    }
    It 'selects exact Pester in a fresh test process even when a newer module is installed' {
        # Isolate version selection only; the full suite above uses real Pester.
        $fixture = Join-Path $TestDrive 'pester-selection'
        $moduleRoot = Join-Path $fixture 'modules'
        $null = New-Item -ItemType Directory -Path (Join-Path $fixture 'scripts'), (Join-Path $fixture 'tests') -Force
        Copy-Item (Join-Path $sourceRoot 'scripts/Test-Repository.ps1') (Join-Path $fixture 'scripts')
        foreach ($name in @('Test-Static.ps1', 'Test-Package.ps1')) {
            Set-Content (Join-Path $fixture "tests/$name") '$global:LASTEXITCODE = 0'
        }
        foreach ($version in @('6.2.0', '6.3.0')) {
            $moduleDirectory = Join-Path $moduleRoot "Pester/$version"
            $null = New-Item -ItemType Directory -Path $moduleDirectory -Force
            Set-Content (Join-Path $moduleDirectory 'Pester.psd1') "@{ RootModule='Pester.psm1'; ModuleVersion='$version'; FunctionsToExport=@('Invoke-Pester') }"
            Set-Content (Join-Path $moduleDirectory 'Pester.psm1') @'
function Invoke-Pester {
    param($Path, [switch]$PassThru, $Output)
    [pscustomobject]@{ FailedCount=0; FailedContainersCount=0; TotalCount=1; SkippedCount=0; NotRunCount=0 }
}
Export-ModuleMember -Function Invoke-Pester
'@
        }
        $selectedPowerShell = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        $originalModulePath = $env:PSModulePath
        try {
            $env:PSModulePath = $moduleRoot + [IO.Path]::PathSeparator + (Join-Path $PSHOME 'Modules')
            $output = & $selectedPowerShell -NoLogo -NoProfile -NonInteractive -File (Join-Path $fixture 'scripts/Test-Repository.ps1') -PesterVersion 6.2.0 2>&1
            $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
            ($output -join [Environment]::NewLine) | Should -Match 'Pester 6\.2\.0'
            $output = & $selectedPowerShell -NoLogo -NoProfile -NonInteractive -File (Join-Path $fixture 'scripts/Test-Repository.ps1') 2>&1
            $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
            ($output -join [Environment]::NewLine) | Should -Match 'Pester 6\.3\.0'
        } finally {
            $env:PSModulePath = $originalModulePath
        }
    }
    It 'keeps the runtime installer narrow and selects its verified runtime in both workflows' {
        $bootstrap = Get-Content (Join-Path $sourceRoot 'scripts/Install-PowerShellRuntime.ps1') -Raw
        $bootstrap | Should -Match '(?m)^#requires -Version 7\.2$'
        $bootstrap | Should -Match '\$version = ''7\.6\.6'''
        $bootstrap | Should -Match 'Get-FileHash.*SHA256'
        $bootstrap | Should -Match '\$LASTEXITCODE -ne 0 -or \$actualVersion -ne \$version'
        $bootstrap | Should -Not -Match 'Pre-Provision|Post-Provision|Deploy-|Connect-|Invoke-RestMethod'
        foreach ($name in @('validate.yml', 'monitor-upstream.yml')) {
            $workflow = Get-Content (Join-Path $sourceRoot ".github/workflows/$name") -Raw
            $workflow | Should -Match 'Install-PowerShellRuntime\.ps1'
            $workflow | Should -Match '\$env:POWERSHELL_PATH -NoLogo -NoProfile -NonInteractive'
        }
    }
    It 'records the unresolved Windows endpoint contract without changing endpoint guards' {
        $guide = Get-Content (Join-Path $sourceRoot 'docs/development.md') -Raw
        $guide | Should -Match 'Issue #18'
        $guide | Should -Match 'not runtime-selection bootstraps'
        foreach ($path in @('deploy/intune/Detect-Sysmon.ps1', 'deploy/intune/Remediate-Sysmon.ps1', 'deploy/azure-vm/Install-Sysmon.ps1', 'deploy/live-response/Install-Sysmon.ps1')) {
            (Get-Content (Join-Path $sourceRoot $path) -First 1) | Should -BeExactly '#requires -Version 5.1'
        }
    }
}
