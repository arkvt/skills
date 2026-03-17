param(
    [string]$Name,
    [int]$Id,
    [switch]$Force,
    [string]$MetadataDirectory
)

. (Join-Path $PSScriptRoot 'bg-common.ps1')

if (-not $Name -and -not $Id) {
    throw "Provide -Name or -Id."
}

$metadata = $null
$metadataPath = $null
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
    $metadataPath = $binding.metadata_path
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
if ($process) {
    try {
        Stop-Process -Id $Id -Force:$Force -ErrorAction Stop
    } catch {
        throw "Failed to stop process with PID ${Id}: $($_.Exception.Message)"
    }
}

if ($metadataPath -and (Test-Path $metadataPath)) {
    $updated = Read-BgMetadata -Path $metadataPath
    $updated | Add-Member -NotePropertyName stopped_at -NotePropertyValue (Get-Date).ToUniversalTime().ToString("o") -Force
    $updated | Add-Member -NotePropertyName stopped_forcefully -NotePropertyValue ([bool]$Force) -Force
    $updated | ConvertTo-Json -Depth 5 | Set-Content -Path $metadataPath -Encoding UTF8 -ErrorAction Stop
}

[ordered]@{
    name = if ($metadata) { $metadata.name } else { $null }
    requested_name = if ($metadata -and ($metadata.PSObject.Properties.Name -contains 'requested_name')) { $metadata.requested_name } elseif ($metadata) { $metadata.name } else { $null }
    pid = $Id
    was_running = [bool]$process
    force = [bool]$Force
    metadata_updated = [bool]$metadataPath
    metadata_source = $metadataSource
    metadata_warning = $metadataWarning
    metadata_ambiguous = $metadataAmbiguous
    metadata_stale_ignored = $metadataStaleIgnored
}
