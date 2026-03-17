param(
    [string]$MetadataDirectory
)

. (Join-Path $PSScriptRoot 'bg-common.ps1')

$resolvedMetadataDirectory = Resolve-BgDirectory -Path $MetadataDirectory -LeafName 'bg'

if (-not (Test-Path $resolvedMetadataDirectory)) {
    @()
    return
}

Get-BgMetadataRecords -MetadataDirectory $resolvedMetadataDirectory | ForEach-Object {
    if (-not $_.valid) {
        [pscustomobject]@{
            name = $_.safe_name
            requested_name = $null
            pid = $null
            running = $false
            process_name = $null
            working_directory = $null
            stdout_log = $null
            stderr_log = $null
            started_at = $null
            stopped_at = $null
            metadata_valid = $false
            error = $_.error
            metadata_path = $_.path
        }
        return
    }

    $metadata = $_.metadata
    $process = Get-BgTrackedProcess -Metadata $metadata

    [pscustomobject]@{
        name = $metadata.name
        requested_name = if ($metadata.PSObject.Properties.Name -contains 'requested_name') { $metadata.requested_name } else { $metadata.name }
        pid = [int]$metadata.pid
        running = [bool]$process
        process_name = if ($process) { $process.ProcessName } else { $null }
        working_directory = $metadata.working_directory
        stdout_log = $metadata.stdout_log
        stderr_log = $metadata.stderr_log
        started_at = $metadata.started_at
        stopped_at = if ($metadata.PSObject.Properties.Name -contains 'stopped_at') { $metadata.stopped_at } else { $null }
        metadata_valid = $true
        error = $null
        metadata_path = $_.path
    }
} | Sort-Object name
