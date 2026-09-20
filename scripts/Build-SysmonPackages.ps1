#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$DefaultConfiguration = 'balanced',

    [string]$ManifestPath,

    [string]$CustomConfigurationFolder,

    [switch]$KeepSourceFiles
)

$ErrorActionPreference = 'Stop'
$templateRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $templateRoot 'config\sysmon-modular-release.json'
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$releaseTag = [string]$manifest.releaseTag
$DefaultConfiguration = $DefaultConfiguration.ToLowerInvariant()
$usingCustomConfigurations = -not [string]::IsNullOrWhiteSpace($CustomConfigurationFolder)
$configurationSource = if ($usingCustomConfigurations) { 'custom-folder' } else { 'olaf-sysmon-modular-release' }
$vendorRoot = Join-Path $templateRoot 'config\vendor'
$sourceRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('azd-sysmon-build-' + [Guid]::NewGuid().ToString('N'))
$downloadRoot = Join-Path $sourceRoot 'configs'
$outputRoot = Join-Path $templateRoot 'deploy'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBomLf {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Text)

    [System.IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`n"), $utf8NoBom)
}

New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $outputRoot 'intune') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $outputRoot 'live-response') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $outputRoot 'azure-vm') -Force | Out-Null

$configurationKeys = @()
$configurationFiles = [ordered]@{}
$configurationManifest = [ordered]@{}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if ($usingCustomConfigurations) {
        if (-not (Test-Path -LiteralPath $CustomConfigurationFolder -PathType Container)) {
            throw "Custom configuration folder was not found: $CustomConfigurationFolder"
        }

        $customFolder = (Get-Item -LiteralPath $CustomConfigurationFolder -ErrorAction Stop).FullName
        $customFiles = @(Get-ChildItem -LiteralPath $customFolder -File | Where-Object { $_.Extension -ieq '.xml' } | Sort-Object Name)
        if ($customFiles.Count -eq 0) {
            throw "Custom configuration folder contains no XML files: $customFolder"
        }

        foreach ($customFile in $customFiles) {
            $configurationKey = [System.IO.Path]::GetFileNameWithoutExtension($customFile.Name).ToLowerInvariant()
            if ($configurationKey -notmatch '^[a-z0-9][a-z0-9-]{0,63}$') {
                throw "Custom configuration file '$($customFile.Name)' must use a filename stem containing only lowercase letters, numbers, and hyphens, beginning with a letter or number."
            }
            if ($configurationFiles.Contains($configurationKey)) {
                throw "Custom configuration key '$configurationKey' is duplicated. File names must have unique stems."
            }

            $assetPath = Join-Path $downloadRoot $customFile.Name
            Copy-Item -LiteralPath $customFile.FullName -Destination $assetPath -Force
            try {
                $xml = [xml](Get-Content -LiteralPath $assetPath -Raw)
            } catch {
                throw "Custom configuration '$($customFile.Name)' is not valid XML: $($_.Exception.Message)"
            }
            if ($null -eq $xml.Sysmon -or $null -eq $xml.Sysmon.EventFiltering) {
                throw "Custom configuration '$($customFile.Name)' must contain a Sysmon root with an EventFiltering element."
            }

            $actualHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $configurationKeys += $configurationKey
            $configurationFiles[$configurationKey] = $customFile.Name
            $configurationManifest[$configurationKey] = [ordered]@{
                fileName = $customFile.Name
                sha256 = $actualHash
            }
        }
    } else {
        $configurationKeys = @('balanced', 'filedelete', 'excludes-only', 'mde-augmented')
        foreach ($configurationKey in $configurationKeys) {
            $asset = $manifest.configurationAssets.$configurationKey
            if ($null -eq $asset) {
                throw "Manifest does not contain configuration asset '$configurationKey'."
            }

            $vendorPath = Join-Path $vendorRoot ([string]$asset.fileName)
            if (-not (Test-Path -LiteralPath $vendorPath -PathType Leaf)) {
                throw "Vendored configuration asset is missing: $vendorPath"
            }
            $assetPath = Join-Path $downloadRoot $asset.fileName
            Copy-Item -LiteralPath $vendorPath -Destination $assetPath -Force

            $actualHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne ([string]$asset.sha256).ToLowerInvariant()) {
                throw "SHA-256 mismatch for $($asset.fileName). Expected $($asset.sha256), got $actualHash."
            }
            $configurationFiles[$configurationKey] = [string]$asset.fileName
            $configurationManifest[$configurationKey] = [ordered]@{
                fileName = [string]$asset.fileName
                sha256 = $actualHash
            }
        }
    }

    if ($configurationKeys -notcontains $DefaultConfiguration) {
        throw "Default configuration '$DefaultConfiguration' is not available. Choose one of: $($configurationKeys -join ', ')."
    }

    # Compress-Archive records file timestamps. Normalize them so rebuilding the
    # same pinned release produces the same bundle and embedded script bytes.
    $archiveTimestamp = [DateTime]::SpecifyKind([DateTime]'2000-01-01T00:00:00', [DateTimeKind]::Unspecified)
    Get-ChildItem -LiteralPath $downloadRoot -File | ForEach-Object { $_.LastWriteTime = $archiveTimestamp }
    $bundlePath = Join-Path $sourceRoot 'sysmon-configs.zip'
    Compress-Archive -Path (Join-Path $downloadRoot '*') -DestinationPath $bundlePath -CompressionLevel Optimal -Force
    $bundleBytes = [System.IO.File]::ReadAllBytes($bundlePath)
    $bundleBase64 = [Convert]::ToBase64String($bundleBytes)
    $bundleHash = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()

$installerTemplate = @'
#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet(__CONFIGURATION_VALIDATE_SET__)]
    [string]$Configuration = '__DEFAULT_CONFIGURATION__',

    [string]$InstallRoot = 'C:\ProgramData\AzdSysmon'
)

$ErrorActionPreference = 'Stop'
$configBundleBase64 = '__CONFIG_BUNDLE_BASE64__'
$configBundleBase64 = ($configBundleBase64 -replace '\s', '')
$configFiles = @{
__CONFIGURATION_FILE_MAP__
}
$configFileHashes = @{
__CONFIGURATION_HASH_MAP__
}

function Write-Status {
    param([string]$Message)
    Write-Output "[azd-sysmon] $Message"
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Sysmon installation requires an elevated administrator or Local System context.'
    }
}

function Expand-EmbeddedConfiguration {
    param([string]$DestinationRoot)

    if (-not $configFiles.ContainsKey($Configuration)) {
        throw "Unsupported Sysmon configuration '$Configuration'."
    }

    $configRoot = Join-Path $DestinationRoot 'configs'
    $bundlePath = Join-Path $DestinationRoot 'sysmon-configs.zip'
    New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
    [System.IO.File]::WriteAllBytes($bundlePath, [Convert]::FromBase64String($configBundleBase64))
    Expand-Archive -LiteralPath $bundlePath -DestinationPath $configRoot -Force

    $configPath = Join-Path $configRoot $configFiles[$Configuration]
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Embedded configuration was not found after expansion: $configPath"
    }
    $actualHash = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $configFileHashes[$Configuration]) {
        throw "Embedded configuration hash verification failed for '$Configuration'."
    }

    return $configPath
}

function Enable-BuiltInSysmon {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName 'Sysmon' -ErrorAction SilentlyContinue
    if ($null -eq $feature) {
        throw 'This Windows image does not expose the built-in Sysmon optional feature. The package is intended for Windows 11 or Windows Server 2025 and later.'
    }
    $existingServices = @(Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue)
    if ($existingServices.Count -gt 0 -and $feature.State -ne 'Enabled') {
        throw 'A standalone Sysmon service is present while the built-in Sysmon feature is disabled. Built-in and standalone Sysmon must not coexist.'
    }
    if ($feature.State -ne 'Enabled') {
        Write-Status 'Enabling the built-in Windows Sysmon optional feature.'
        Enable-WindowsOptionalFeature -Online -FeatureName 'Sysmon' -NoRestart | Out-Null
    }
    $sysmonPath = Join-Path $env:WINDIR 'System32\sysmon.exe'
    if (-not (Test-Path -LiteralPath $sysmonPath -PathType Leaf)) {
        throw "The Sysmon optional feature was enabled, but the built-in executable was not found at $sysmonPath."
    }
    $signature = Get-AuthenticodeSignature -FilePath $sysmonPath
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw "The built-in Sysmon executable at $sysmonPath does not have a valid Microsoft signature."
    }
    return $sysmonPath
}

function Get-SysmonService {
    $service = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        $service = Get-Service -Name 'Sysmon' -ErrorAction SilentlyContinue
    }
    return $service
}

Assert-Administrator
$sysmonPath = Enable-BuiltInSysmon
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
$configPath = Expand-EmbeddedConfiguration -DestinationRoot $InstallRoot
$service = Get-SysmonService

if ($null -eq $service) {
    Write-Status "Installing Sysmon with the '$Configuration' configuration."
    & $sysmonPath -accepteula -i $configPath
} else {
    Write-Status "Updating Sysmon with the '$Configuration' configuration."
    & $sysmonPath -c $configPath
}
if ($LASTEXITCODE -ne 0) {
    throw "Sysmon returned exit code $LASTEXITCODE."
}

$eventLog = Get-WinEvent -ListLog 'Microsoft-Windows-Sysmon/Operational' -ErrorAction Stop
$configHash = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
$state = [ordered]@{
    template = 'azd-sysmon'
    configuration = $Configuration
    configurationFile = Split-Path -Leaf $configPath
    configurationSha256 = $configHash
    sysmonSource = 'Windows built-in optional feature'
    sysmonBinary = $sysmonPath
    eventLog = $eventLog.LogName
    installedUtc = [DateTime]::UtcNow.ToString('o')
}
$statePath = Join-Path $InstallRoot 'state.json'
$state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8
Write-Status "Sysmon is installed and '$($eventLog.LogName)' is available."
exit 0
'@

$installer = $installerTemplate
$configurationValidateSet = ($configurationKeys | ForEach-Object { "'$($_)'" }) -join ', '
$configurationFileMap = ($configurationFiles.GetEnumerator() | ForEach-Object { "    '$($_.Key)' = '$($_.Value)'" }) -join [Environment]::NewLine
$configurationHashMap = ($configurationManifest.GetEnumerator() | ForEach-Object { "    '$($_.Key)' = '$($_.Value.sha256)'" }) -join [Environment]::NewLine
$installer = $installer.Replace('__DEFAULT_CONFIGURATION__', $DefaultConfiguration)
$installer = $installer.Replace('__CONFIG_BUNDLE_BASE64__', $bundleBase64)
$installer = $installer.Replace('__CONFIGURATION_VALIDATE_SET__', $configurationValidateSet)
$installer = $installer.Replace('__CONFIGURATION_FILE_MAP__', $configurationFileMap)
$installer = $installer.Replace('__CONFIGURATION_HASH_MAP__', $configurationHashMap)

$detection = @'
#requires -Version 5.1
$ErrorActionPreference = 'SilentlyContinue'
$desiredConfiguration = '__DEFAULT_CONFIGURATION__'
$desiredConfigurationSha256 = '__DEFAULT_CONFIGURATION_SHA256__'
$desiredConfigurationFile = '__DEFAULT_CONFIGURATION_FILE__'
$installRoot = 'C:\ProgramData\AzdSysmon'
$statePath = Join-Path $installRoot 'state.json'
$service = Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue
if ($null -eq $service) {
    $service = Get-Service -Name 'Sysmon' -ErrorAction SilentlyContinue
}
$state = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $state = $null }
}
$eventLog = Get-WinEvent -ListLog 'Microsoft-Windows-Sysmon/Operational' -ErrorAction SilentlyContinue
$configurationPath = Join-Path (Join-Path $installRoot 'configs') $desiredConfigurationFile
$configurationHash = if (Test-Path -LiteralPath $configurationPath -PathType Leaf) { (Get-FileHash -LiteralPath $configurationPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
if ($null -ne $service -and $service.Status -eq 'Running' -and $null -ne $eventLog -and $null -ne $state -and $state.configuration -eq $desiredConfiguration -and $state.configurationFile -eq $desiredConfigurationFile -and $state.configurationSha256 -eq $desiredConfigurationSha256 -and $configurationHash -eq $desiredConfigurationSha256) {
    Write-Output "Sysmon is healthy with the '$desiredConfiguration' configuration."
    exit 0
}
Write-Output "Sysmon remediation is required for the '$desiredConfiguration' configuration."
exit 1
'@
$detection = $detection.Replace('__DEFAULT_CONFIGURATION__', $DefaultConfiguration)
$detection = $detection.Replace('__DEFAULT_CONFIGURATION_SHA256__', [string]$configurationManifest[$DefaultConfiguration].sha256)
$detection = $detection.Replace('__DEFAULT_CONFIGURATION_FILE__', [string]$configurationManifest[$DefaultConfiguration].fileName)

$intuneRemediation = $installer
$liveResponse = $installer
$azureVm = $installer

if ([Text.Encoding]::UTF8.GetByteCount($intuneRemediation) -ge 200KB -or [Text.Encoding]::UTF8.GetByteCount($detection) -ge 200KB) {
    throw 'The generated Intune scripts must remain below 200 KB. Reduce the number or size of XML files in the selected configuration source.'
}

Write-Utf8NoBomLf -Path (Join-Path $outputRoot 'intune\Detect-Sysmon.ps1') -Text $detection
Write-Utf8NoBomLf -Path (Join-Path $outputRoot 'intune\Remediate-Sysmon.ps1') -Text $intuneRemediation
Write-Utf8NoBomLf -Path (Join-Path $outputRoot 'live-response\Install-Sysmon.ps1') -Text $liveResponse
Write-Utf8NoBomLf -Path (Join-Path $outputRoot 'azure-vm\Install-Sysmon.ps1') -Text $azureVm

$generatedManifest = [ordered]@{
    template = 'azd-sysmon'
    configurationSource = $configurationSource
    defaultConfiguration = $DefaultConfiguration
    configurationKeys = $configurationKeys
    configRelease = if ($usingCustomConfigurations) { $null } else { $releaseTag }
    configurationFiles = $configurationManifest
    configBundleSha256 = $bundleHash
    generatedFiles = [ordered]@{}
}
foreach ($generatedPath in @(
    (Join-Path $outputRoot 'intune\Detect-Sysmon.ps1'),
    (Join-Path $outputRoot 'intune\Remediate-Sysmon.ps1'),
    (Join-Path $outputRoot 'live-response\Install-Sysmon.ps1'),
    (Join-Path $outputRoot 'azure-vm\Install-Sysmon.ps1')
)) {
    $generatedFullPath = (Resolve-Path -LiteralPath $generatedPath).Path
    $generatedRelativePath = $generatedFullPath.Substring($templateRoot.Length) -replace '^[\\/]+', ''
    $generatedManifest.generatedFiles[('.\' + $generatedRelativePath -replace '/', '\')] = (Get-FileHash -LiteralPath $generatedPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
Write-Utf8NoBomLf -Path (Join-Path $templateRoot 'config\generated-package-manifest.json') -Text ($generatedManifest | ConvertTo-Json -Depth 8)

Write-Output "Generated Sysmon deployment scripts using $(if ($usingCustomConfigurations) { 'the custom configuration folder' } else { $releaseTag })."
Write-Output "Configuration bundle SHA-256: $bundleHash"
Write-Output "Default configuration: $DefaultConfiguration"
Write-Output "Intune remediation size: $([Math]::Round((Get-Item -LiteralPath (Join-Path $outputRoot 'intune\Remediate-Sysmon.ps1')).Length / 1KB, 1)) KB"

}
finally {
    if (-not $KeepSourceFiles) {
        Remove-Item -LiteralPath $sourceRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
