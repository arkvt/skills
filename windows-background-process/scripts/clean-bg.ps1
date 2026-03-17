param(
    [string]$MetadataDirectory,
    [switch]$IncludeLogs,
    [switch]$RemoveInvalidMetadata
)

. (Join-Path $PSScriptRoot 'bg-common.ps1')

$resolvedMetadataDirectory = Resolve-BgDirectory -Path $MetadataDirectory -LeafName 'bg'

if (-not (Test-Path $resolvedMetadataDirectory)) {
    @()
    return
}

Get-BgMetadataRecords -MetadataDirectory $resolvedMetadataDirectory | ForEach-Object {
    $metadataPath = $_.path
    if (-not $_.valid) {
        if (-not $RemoveInvalidMetadata) {
            [pscustomobject]@{
                name = $_.safe_name
                pid = $null
                invalid_metadata = $true
                metadata_removed = $false
                stdout_log_removed = $false
                stderr_log_removed = $false
                error = "$($_.error) Re-run clean-bg.ps1 with -RemoveInvalidMetadata to delete this broken metadata file."
            }
            return
        }

        try {
            Remove-Item -Force $metadataPath -ErrorAction Stop
        } catch {
            [pscustomobject]@{
                name = $_.safe_name
                pid = $null
                invalid_metadata = $true
                metadata_removed = $false
                stdout_log_removed = $false
                stderr_log_removed = $false
                error = "Failed to remove invalid metadata '$metadataPath': $($_.Exception.Message)"
            }
            return
        }

        [pscustomobject]@{
            name = $_.safe_name
            pid = $null
            invalid_metadata = $true
            metadata_removed = $true
            stdout_log_removed = $false
            stderr_log_removed = $false
            error = $null
        }
        return
    }

    $metadata = $_.metadata
    $processId = [int]$metadata.pid
    $process = Get-BgTrackedProcess -Metadata $metadata

    if ($process) {
        return
    }

    $stdoutRemoved = $false
    $stderrRemoved = $false

    if ($IncludeLogs) {
        if ($metadata.stdout_log -and (Test-Path $metadata.stdout_log)) {
            try {
                Remove-Item -Force $metadata.stdout_log -ErrorAction Stop
                $stdoutRemoved = $true
            } catch {
                [pscustomobject]@{
                    name = $metadata.name
                    pid = $processId
                    invalid_metadata = $false
                    metadata_removed = $false
                    stdout_log_removed = $false
                    stderr_log_removed = $false
                    error = "Failed to remove stdout log '$($metadata.stdout_log)': $($_.Exception.Message)"
                }
                return
            }
        }
        if ($metadata.stderr_log -and (Test-Path $metadata.stderr_log)) {
            try {
                Remove-Item -Force $metadata.stderr_log -ErrorAction Stop
                $stderrRemoved = $true
            } catch {
                [pscustomobject]@{
                    name = $metadata.name
                    pid = $processId
                    invalid_metadata = $false
                    metadata_removed = $false
                    stdout_log_removed = $stdoutRemoved
                    stderr_log_removed = $false
                    error = "Failed to remove stderr log '$($metadata.stderr_log)': $($_.Exception.Message)"
                }
                return
            }
        }
    }

    try {
        Remove-Item -Force $metadataPath -ErrorAction Stop
    } catch {
        [pscustomobject]@{
            name = $metadata.name
            pid = $processId
            invalid_metadata = $false
            metadata_removed = $false
            stdout_log_removed = $stdoutRemoved
            stderr_log_removed = $stderrRemoved
            error = "Failed to remove metadata '$metadataPath': $($_.Exception.Message)"
        }
        return
    }

    [pscustomobject]@{
        name = $metadata.name
        pid = $processId
        invalid_metadata = $false
        metadata_removed = $true
        stdout_log_removed = $stdoutRemoved
        stderr_log_removed = $stderrRemoved
        error = $null
    }
} | Sort-Object name
