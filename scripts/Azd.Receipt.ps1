#requires -Version 5.1

function Read-AzdJsonReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    try {
        $json = [IO.File]::ReadAllText($fullPath)
        return ConvertFrom-Json -InputObject $json -ErrorAction Stop
    } catch {
        $previousPath = "$fullPath.previous"
        $recoveryHint = if ([IO.File]::Exists($previousPath)) {
            " A previous version exists at '$previousPath'; review it explicitly before recovery. It was not loaded automatically."
        } else {
            ''
        }
        throw "The receipt at '$fullPath' contains invalid or truncated JSON and was not used.$recoveryHint $($_.Exception.Message)"
    }
}

function Write-AzdJsonReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory, ValueFromPipeline)][AllowNull()]$InputObject,
        [ValidateRange(2, 100)][int]$Depth = 8
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($fullPath)
    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw "The receipt path '$Path' does not have a parent directory."
    }
    [IO.Directory]::CreateDirectory($directory) | Out-Null

    $leafName = [IO.Path]::GetFileName($fullPath)
    $candidatePath = Join-Path $directory ('.{0}.{1}.candidate' -f $leafName, [guid]::NewGuid().ToString('N'))
    $candidateValidated = $false

    try {
        $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth -ErrorAction Stop
        $encoding = New-Object Text.UTF8Encoding($false)
        $bytes = $encoding.GetBytes($json + [Environment]::NewLine)
        $stream = New-Object IO.FileStream($candidatePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally {
            $stream.Dispose()
        }

        $null = Read-AzdJsonReceipt -Path $candidatePath
        $candidateValidated = $true

        if ([IO.File]::Exists($fullPath)) {
            [IO.File]::Replace($candidatePath, $fullPath, "$fullPath.previous", $true)
        } else {
            [IO.File]::Move($candidatePath, $fullPath)
        }
    } catch {
        if ([IO.File]::Exists($candidatePath)) {
            $kind = if ($candidateValidated) { 'validated recovery candidate' } else { 'temporary candidate' }
            throw "Could not safely replace receipt '$fullPath'. The $kind was preserved at '$candidatePath'. $($_.Exception.Message)"
        }
        throw
    }
}
