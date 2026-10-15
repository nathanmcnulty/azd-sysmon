#requires -Version 7.6

BeforeAll {
    $sourceRoot = Split-Path -Parent $PSScriptRoot
    $helperPath = Join-Path $sourceRoot 'scripts/Azd.Receipt.ps1'
    . $helperPath
}

Describe 'Recoverable JSON receipt writes' {
    BeforeEach {
        $receiptRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $receiptPath = Join-Path $receiptRoot 'receipt.json'
    }

    It 'writes and reads a new receipt without leaving a candidate' {
        Write-AzdJsonReceipt -Path $receiptPath -InputObject ([ordered]@{ version = 1; status = 'created' })

        (Read-AzdJsonReceipt -Path $receiptPath).status | Should -Be 'created'
        Test-Path -LiteralPath "$receiptPath.previous" | Should -BeFalse
        @(Get-ChildItem -LiteralPath $receiptRoot -Filter '*.candidate' -Force) | Should -HaveCount 0
    }

    It 'keeps the immediately previous valid receipt across repeated replacements' {
        Write-AzdJsonReceipt -Path $receiptPath -InputObject ([ordered]@{ version = 1 })
        Write-AzdJsonReceipt -Path $receiptPath -InputObject ([ordered]@{ version = 2 })

        (Read-AzdJsonReceipt -Path $receiptPath).version | Should -Be 2
        (Read-AzdJsonReceipt -Path "$receiptPath.previous").version | Should -Be 1

        Write-AzdJsonReceipt -Path $receiptPath -InputObject ([ordered]@{ version = 3 })

        (Read-AzdJsonReceipt -Path $receiptPath).version | Should -Be 3
        (Read-AzdJsonReceipt -Path "$receiptPath.previous").version | Should -Be 2
        @(Get-ChildItem -LiteralPath $receiptRoot -Filter '*.candidate' -Force) | Should -HaveCount 0
    }

    It 'preserves the primary and a validated candidate when replacement cannot complete' {
        Write-AzdJsonReceipt -Path $receiptPath -InputObject ([ordered]@{ version = 1 })
        $before = [IO.File]::ReadAllBytes($receiptPath)
        $lock = $null
        if ($IsWindows) {
            $lock = [IO.File]::Open($receiptPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        } else {
            # Unix rename ignores Windows file-sharing locks. An unusable backup
            # destination forces the same real File.Replace failure after validation.
            $null = New-Item -ItemType Directory -Path "$receiptPath.previous"
        }
        try {
            { Write-AzdJsonReceipt -Path $receiptPath -InputObject ([ordered]@{ version = 2 }) } |
                Should -Throw '*validated recovery candidate was preserved*'
        } finally {
            if ($null -ne $lock) { $lock.Dispose() }
        }

        [Convert]::ToBase64String([IO.File]::ReadAllBytes($receiptPath)) | Should -BeExactly ([Convert]::ToBase64String($before))
        $candidates = @(Get-ChildItem -LiteralPath $receiptRoot -Filter '*.candidate' -Force)
        $candidates | Should -HaveCount 1
        (Read-AzdJsonReceipt -Path $candidates[0].FullName).version | Should -Be 2
    }

    It 'rejects <label> primary JSON without automatically loading a previous receipt' -ForEach @(
        @{ label = 'truncated'; content = '{"template":"azd-sysmon"' }
        @{ label = 'corrupt'; content = 'not-json' }
    ) {
        New-Item -ItemType Directory -Path $receiptRoot -Force | Out-Null
        [IO.File]::WriteAllText($receiptPath, $content)
        [IO.File]::WriteAllText("$receiptPath.previous", '{"template":"azd-sysmon","status":"created"}')
        $before = [IO.File]::ReadAllBytes($receiptPath)

        { Read-AzdJsonReceipt -Path $receiptPath } | Should -Throw '*invalid or truncated JSON*not loaded automatically*'

        [Convert]::ToBase64String([IO.File]::ReadAllBytes($receiptPath)) | Should -BeExactly ([Convert]::ToBase64String($before))
        (Read-AzdJsonReceipt -Path "$receiptPath.previous").status | Should -Be 'created'
    }

    It 'performs first write, read, and repeated replacement under PowerShell 7.6+' {
        $selectedPowerShell = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        $nativeRoot = Join-Path $receiptRoot 'powershell-7'
        New-Item -ItemType Directory -Path $nativeRoot -Force | Out-Null
        $nativeTest = Join-Path $nativeRoot 'Test-Receipt.ps1'
        @'
param([string]$HelperPath, [string]$Root)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion -lt [version]'7.6') { throw 'PowerShell 7.6+ required.' }
. $HelperPath
$path = Join-Path $Root 'receipt.json'
Write-AzdJsonReceipt -Path $path -InputObject ([ordered]@{ version = 1 })
if ((Read-AzdJsonReceipt -Path $path).version -ne 1) { throw 'First write/read failed.' }
Write-AzdJsonReceipt -Path $path -InputObject ([ordered]@{ version = 2 })
if ((Read-AzdJsonReceipt -Path $path).version -ne 2 -or (Read-AzdJsonReceipt -Path "$path.previous").version -ne 1) { throw 'First replacement failed.' }
Write-AzdJsonReceipt -Path $path -InputObject ([ordered]@{ version = 3 })
if ((Read-AzdJsonReceipt -Path $path).version -ne 3 -or (Read-AzdJsonReceipt -Path "$path.previous").version -ne 2) { throw 'Repeated replacement failed.' }
'PowerShell 7 receipt validation passed.'
'@ | Set-Content -LiteralPath $nativeTest -Encoding UTF8

        $output = & $selectedPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $nativeTest -HelperPath $helperPath -Root $nativeRoot 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
        $output | Should -Contain 'PowerShell 7 receipt validation passed.'
    }
}
