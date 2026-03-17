param(
    [string]$Name,
    [int]$Id,
    [ValidateSet("Running", "Stopped")]
    [string]$Until = "Running",
    [ValidateRange(0, 86400)]
    [int]$TimeoutSeconds = 30,
    [ValidateRange(50, 60000)]
    [int]$PollIntervalMilliseconds = 500,
    [string]$MetadataDirectory
)

if (-not $Name -and -not $Id) {
    throw "Provide -Name or -Id."
}

$statusScript = Join-Path $PSScriptRoot 'status-bg.ps1'
$startedAt = [DateTimeOffset]::UtcNow
$deadline = $startedAt.AddSeconds($TimeoutSeconds)
$pollCount = 0

while ($true) {
    try {
        $status = if ($Name) {
            & $statusScript -Name $Name -MetadataDirectory $MetadataDirectory
        } else {
            & $statusScript -Id $Id -MetadataDirectory $MetadataDirectory
        }
    } catch {
        $message = $_.Exception.Message
        if ($Name -and $Until -eq 'Stopped' -and $message -like 'Metadata not found*') {
            [ordered]@{
                until = $Until
                timed_out = $false
                elapsed_seconds = [Math]::Round(([DateTimeOffset]::UtcNow - $startedAt).TotalSeconds, 3)
                polls = $pollCount + 1
                status = [ordered]@{
                    name = $Name
                    requested_name = $Name
                    pid = $null
                    running = $false
                    process_name = $null
                    started_at = $null
                    stopped_at = $null
                    stdout_log = $null
                    stderr_log = $null
                    metadata_valid = $null
                    metadata_source = 'missing_metadata'
                    metadata_warning = "Metadata for '$Name' was not found; treating the process as stopped."
                    metadata_ambiguous = $null
                    metadata_stale_ignored = $null
                }
            }
            return
        }

        throw
    }

    $conditionMet = if ($Until -eq 'Running') { [bool]$status.running } else { -not [bool]$status.running }
    if ($conditionMet) {
        [ordered]@{
            until = $Until
            timed_out = $false
            elapsed_seconds = [Math]::Round(([DateTimeOffset]::UtcNow - $startedAt).TotalSeconds, 3)
            polls = $pollCount + 1
            status = $status
        }
        return
    }

    if ([DateTimeOffset]::UtcNow -ge $deadline) {
        $lastStatus = $status | ConvertTo-Json -Depth 6 -Compress
        throw "Timed out after $TimeoutSeconds second(s) waiting for process state '$Until'. Last status: $lastStatus"
    }

    $pollCount++
    Start-Sleep -Milliseconds $PollIntervalMilliseconds
}
