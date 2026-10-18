#requires -Version 7.6

function Add-AmaComReleaseFailure {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[Exception]]$Failures,
        [switch]$Close
    )

    if ($null -eq $InputObject) { return }
    if ($Close) { try { $InputObject.Close() } catch { } }
    if (-not [Runtime.InteropServices.Marshal]::IsComObject($InputObject)) { return }
    try { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($InputObject) | Out-Null }
    catch { $Failures.Add($_.Exception) }
}

function Complete-AmaComCleanup {
    param(
        [AllowNull()][Management.Automation.ErrorRecord]$PrimaryError,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[Exception]]$Failures
    )

    if ($null -ne $PrimaryError) {
        if ($Failures.Count -gt 0) {
            $PrimaryError.Exception.Data['AmaComCleanupErrors'] = @($Failures | ForEach-Object Message) -join ' | '
        }
        throw $PrimaryError
    }
    if ($Failures.Count -gt 0) {
        throw [AggregateException]::new('Failed to release one or more Windows Installer COM objects.', $Failures)
    }
}
