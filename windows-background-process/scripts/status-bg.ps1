param(
    [string]$Name,
    [int]$Id,
    [string]$MetadataDirectory
)

. (Join-Path $PSScriptRoot 'bg-common.ps1')

if (-not $Name -and -not $Id) {
    throw "Provide -Name or -Id."
}

$metadata = $null
$process = $null
$metadataSource = $null
$metadataWarning = $null
$metadataAmbiguous = $null
$metadataStaleIgnored = $null
$resolvedMetadataDirectory = Resolve-BgDirectory -Path $MetadataDirectory -LeafName 'bg'
if ($Name) {
    $safeName = ConvertTo-BgSafeName -Name $Name
    $metadataPath = Get-BgMetadataPath -Name $safeName -MetadataDirectory $resolvedMetadataDirectory
    if (-not (Test-Path $metadataPath)) {
        throw "Metadata not found for '$safeName'."
    }
    $metadata = Read-BgMetadata -Path $metadataPath
    $Id = [int]$metadata.pid
} elseif (Test-Path $resolvedMetadataDirectory) {
    $binding = Resolve-BgIdBinding -Id $Id -MetadataDirectory $resolvedMetadataDirectory -AllowStopped
    $metadata = $binding.metadata
    $process = $binding.process
    $metadataSource = $binding.metadata_source
    $metadataWarning = $binding.metadata_warning
    $metadataAmbiguous = $binding.metadata_ambiguous
    $metadataStaleIgnored = $binding.metadata_stale_ignored
    if ($metadata) {
        $Id = [int]$metadata.pid
    }
}

if (-not $process) {
    $process = if ($metadata) { Get-BgTrackedProcess -Metadata $metadata } else { Get-Process -Id $Id -ErrorAction SilentlyContinue }
}

[ordered]@{
    name = if ($metadata) { $metadata.name } else { $null }
    requested_name = if ($metadata -and ($metadata.PSObject.Properties.Name -contains 'requested_name')) { $metadata.requested_name } elseif ($metadata) { $metadata.name } else { $null }
    pid = $Id
    running = [bool]$process
    process_name = if ($process) { $process.ProcessName } else { $null }
    started_at = if ($metadata) { $metadata.started_at } elseif ($process) { $process.StartTime.ToUniversalTime().ToString("o") } else { $null }
    stopped_at = if ($metadata -and ($metadata.PSObject.Properties.Name -contains 'stopped_at')) { $metadata.stopped_at } else { $null }
    stdout_log = if ($metadata) { $metadata.stdout_log } else { $null }
    stderr_log = if ($metadata) { $metadata.stderr_log } else { $null }
    metadata_valid = if ($metadata) { $true } else { $null }
    metadata_source = $metadataSource
    metadata_warning = $metadataWarning
    metadata_ambiguous = $metadataAmbiguous
    metadata_stale_ignored = $metadataStaleIgnored
}
