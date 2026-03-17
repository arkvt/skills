param(
    [string]$Name,
    [ValidateSet("out", "err")]
    [string]$Stream = "out",
    [string]$Path,
    [int]$Tail = 50,
    [switch]$Wait,
    [string]$MetadataDirectory
)

. (Join-Path $PSScriptRoot 'bg-common.ps1')

if (-not $Path -and -not $Name) {
    throw "Provide -Path or -Name."
}

if (-not $Path) {
    $resolvedMetadataDirectory = Resolve-BgDirectory -Path $MetadataDirectory -LeafName 'bg'
    $safeName = ConvertTo-BgSafeName -Name $Name
    $metadataPath = Get-BgMetadataPath -Name $safeName -MetadataDirectory $resolvedMetadataDirectory
    if (-not (Test-Path $metadataPath)) {
        throw "Metadata not found for '$safeName'."
    }
    $metadata = Read-BgMetadata -Path $metadataPath
    $Path = if ($Stream -eq "out") { $metadata.stdout_log } else { $metadata.stderr_log }
}

if (-not (Test-Path -Path $Path -PathType Leaf)) {
    throw "Log file '$Path' was not found. The process may not have written to that stream yet, or the log may have been cleaned."
}

Get-Content -Path $Path -Tail $Tail -Wait:$Wait -ErrorAction Stop
