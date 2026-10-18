#requires -Version 7.6

BeforeAll {
    $script:sourceRoot = Split-Path -Parent $PSScriptRoot
    $script:builderPath = Join-Path $script:sourceRoot 'scripts\Build-AmaPackage.ps1'
    . (Join-Path $script:sourceRoot 'scripts\Ama.ComCleanup.ps1')

    function Remove-TestComObject {
        param([AllowNull()][object]$InputObject, [switch]$Close)

        if ($null -eq $InputObject) { return }
        if ($Close) { try { $InputObject.Close() } catch { } }
        if ([Runtime.InteropServices.Marshal]::IsComObject($InputObject)) {
            try { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($InputObject) | Out-Null } catch { }
        }
    }

    function New-TestAmaMsi {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$ProductCode,
            [Parameter(Mandatory)][string]$ProductVersion,
            [Parameter(Mandatory)][string]$Manufacturer,
            [Parameter(Mandatory)][string]$UpgradeCode
        )

        $installer = $database = $null
        try {
            $installer = New-Object -ComObject WindowsInstaller.Installer
            $database = $installer.OpenDatabase($Path, 3)
            $statements = @(
                'CREATE TABLE `Property` (`Property` CHAR(72) NOT NULL, `Value` CHAR(0) LOCALIZABLE PRIMARY KEY `Property`)',
                "INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('ProductCode', '$ProductCode')",
                "INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('ProductVersion', '$ProductVersion')",
                "INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('Manufacturer', '$Manufacturer')",
                "INSERT INTO ``Property`` (``Property``, ``Value``) VALUES ('UpgradeCode', '$UpgradeCode')"
            )
            foreach ($statement in $statements) {
                $view = $null
                try {
                    $view = $database.OpenView($statement)
                    $view.Execute() | Out-Null
                }
                finally { Remove-TestComObject -InputObject $view -Close }
            }
            $database.Commit()
        }
        finally {
            Remove-TestComObject -InputObject $database
            Remove-TestComObject -InputObject $installer
        }
    }
}

Describe 'AMA COM cleanup error contract' {
    It 'preserves the primary error and attaches secondary release failures' {
        $primary = [Management.Automation.ErrorRecord]::new(
            [IO.InvalidDataException]::new('metadata-primary'),
            'AmaMetadata',
            [Management.Automation.ErrorCategory]::InvalidData,
            $null
        )
        $failures = [Collections.Generic.List[Exception]]::new()
        $failures.Add([InvalidOperationException]::new('release-secondary'))

        $caught = $null
        try { Complete-AmaComCleanup -PrimaryError $primary -Failures $failures }
        catch { $caught = $_ }

        $caught.Exception.Message | Should -BeExactly 'metadata-primary'
        $caught.Exception.Data['AmaComCleanupErrors'] | Should -BeExactly 'release-secondary'
    }

    It 'throws a cleanup failure when no primary error exists' {
        $failures = [Collections.Generic.List[Exception]]::new()
        $failures.Add([InvalidOperationException]::new('release-only'))

        { Complete-AmaComCleanup -PrimaryError $null -Failures $failures } |
            Should -Throw '*Failed to release one or more Windows Installer COM objects*'
    }
}

Describe 'Azure Monitor Agent package builder COM cleanup' -Skip:(-not $IsWindows) {
    BeforeEach {
        $script:testRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:outputRoot = Join-Path $script:testRoot 'output'
        $script:fixturePath = Join-Path $script:testRoot 'fixture.msi'
        $script:manifestPath = Join-Path $script:testRoot 'release.json'
        $script:productCode = '{11111111-2222-4333-8444-555555555555}'
        $script:productVersion = '9.8.7.6'
        $script:manufacturer = 'Microsoft Corporation'
        $script:upgradeCode = '{AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE}'
        New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null
        New-TestAmaMsi -Path $script:fixturePath -ProductCode $script:productCode -ProductVersion $script:productVersion -Manufacturer $script:manufacturer -UpgradeCode $script:upgradeCode
        $global:AzdSysmonAmaFixturePath = $script:fixturePath
        $script:release = [ordered]@{
            release = $script:productVersion
            fileName = 'fixture.msi'
            downloadUri = 'https://download.microsoft.com/test/fixture.msi'
            sha256 = (Get-FileHash -LiteralPath $script:fixturePath -Algorithm SHA256).Hash.ToLowerInvariant()
            productCode = $script:productCode
            publisher = $script:manufacturer
            signerSubjectPattern = '^CN=Microsoft Corporation'
        }
        $script:release | ConvertTo-Json | Set-Content -LiteralPath $script:manifestPath
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status = 'Valid'
                SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation' }
            }
        }
    }

    AfterEach { Remove-Variable -Name AzdSysmonAmaFixturePath -Scope Global -ErrorAction SilentlyContinue }

    It 'promotes controlled download staging and releases the validated destination' {
        Mock Invoke-WebRequest {
            param($Uri, $OutFile, $ErrorAction)
            Copy-Item -LiteralPath $global:AzdSysmonAmaFixturePath -Destination $OutFile
        }

        & $script:builderPath -ManifestPath $script:manifestPath -OutputDirectory $script:outputRoot

        $destination = Join-Path $script:outputRoot "AzureMonitorAgentClientSetup-$($script:productVersion).msi"
        $destination | Should -Exist
        "$destination.download" | Should -Not -Exist
        $moved = "$destination.moved"
        Move-Item -LiteralPath $destination -Destination $moved
        $moved | Should -Exist
    }

    It 'releases local input and cached destination files after validation' {
        & $script:builderPath -ManifestPath $script:manifestPath -OutputDirectory $script:outputRoot -MsiPath $script:fixturePath
        $destination = Join-Path $script:outputRoot "AzureMonitorAgentClientSetup-$($script:productVersion).msi"
        Move-Item -LiteralPath $script:fixturePath -Destination "$($script:fixturePath).moved"
        Move-Item -LiteralPath $destination -Destination "$destination.moved"

        New-Item -ItemType Directory -Path $script:outputRoot -Force | Out-Null
        Copy-Item -LiteralPath "$($script:fixturePath).moved" -Destination $destination
        & $script:builderPath -ManifestPath $script:manifestPath -OutputDirectory $script:outputRoot
        Move-Item -LiteralPath $destination -Destination "$destination.cached-moved"
        "$destination.cached-moved" | Should -Exist
    }

    It 'releases publisher metadata handles before the existing pre-auth target guard fails' {
        Mock Get-Module { [pscustomobject]@{ Name = 'Microsoft.Graph.Authentication' } }
        $publisher = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Deploy-IntuneAmaApplication.ps1'

        { & $publisher -GroupId '99999999-8888-4777-8666-555555555555' -MsiPath $script:fixturePath -ManifestPath $script:manifestPath -TenantId '' -ExpectedAccount '' } |
            Should -Throw '*Set AZURE_TENANT_ID and AZD_SYSMON_GRAPH_ACCOUNT*'

        $moved = "$($script:fixturePath).publisher-moved"
        Move-Item -LiteralPath $script:fixturePath -Destination $moved
        $moved | Should -Exist
    }

    It 'preserves metadata rejection while releasing the invalid MSI' {
        $script:release.publisher = 'Unexpected Publisher'
        $script:release | ConvertTo-Json | Set-Content -LiteralPath $script:manifestPath

        { & $script:builderPath -ManifestPath $script:manifestPath -OutputDirectory $script:outputRoot -MsiPath $script:fixturePath } |
            Should -Throw '*Manufacturer does not match the pinned release manifest*'

        $moved = "$($script:fixturePath).rejected-moved"
        Move-Item -LiteralPath $script:fixturePath -Destination $moved
        $moved | Should -Exist
    }
}
