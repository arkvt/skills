function Get-BgDefaultDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LeafName
    )

    return [System.IO.Path]::GetFullPath((Join-Path $HOME ".codex\tmp\$LeafName"))
}

function Resolve-BgDirectory {
    param(
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$LeafName
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return Get-BgDefaultDirectory -LeafName $LeafName
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
}

function Ensure-BgDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -Path $Path -PathType Leaf) {
        throw "Path '$Path' exists as a file. Use a directory path instead."
    }

    New-Item -ItemType Directory -Force -Path $Path -ErrorAction Stop | Out-Null
    return [System.IO.Path]::GetFullPath($Path)
}

function ConvertTo-BgSafeName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return ($Name -replace '[^A-Za-z0-9._-]', '-')
}

function Get-BgMetadataPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$MetadataDirectory
    )

    $safeName = ConvertTo-BgSafeName -Name $Name
    return (Join-Path $MetadataDirectory "$safeName.json")
}

function Read-BgMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        return (Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        throw "Failed to read background metadata '$Path': $($_.Exception.Message)"
    }
}

function Read-BgMetadataSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        return [pscustomobject]@{
            valid = $true
            metadata = Read-BgMetadata -Path $Path
            error = $null
            path = $Path
        }
    } catch {
        return [pscustomobject]@{
            valid = $false
            metadata = $null
            error = $_.Exception.Message
            path = $Path
        }
    }
}

function Get-BgMetadataRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MetadataDirectory
    )

    if (-not (Test-Path $MetadataDirectory)) {
        return @()
    }

    $items = @(Get-ChildItem -Path $MetadataDirectory -Filter *.json -File -ErrorAction Stop | Sort-Object Name)
    $records = foreach ($item in $items) {
        $result = Read-BgMetadataSafe -Path $item.FullName
        [pscustomobject]@{
            path = $item.FullName
            file_name = $item.Name
            safe_name = $item.BaseName
            valid = [bool]$result.valid
            metadata = $result.metadata
            error = $result.error
        }
    }

    return @($records)
}

function Get-BgMutexName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MetadataDirectory,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $seed = "$MetadataDirectory|$Name"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($seed)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash($bytes)
    } finally {
        $sha256.Dispose()
    }

    $hash = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
    return "Local\codex-bg-$hash"
}

function Resolve-BgIdBinding {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Id,
        [Parameter(Mandatory = $true)]
        [string]$MetadataDirectory,
        [switch]$AllowStopped
    )

    $rawProcess = Get-Process -Id $Id -ErrorAction SilentlyContinue
    $records = @(Get-BgMetadataRecords -MetadataDirectory $MetadataDirectory | Where-Object {
        $_.valid -and ([int]$_.metadata.pid -eq $Id)
    })
    $runningMatches = @($records | Where-Object { Get-BgTrackedProcess -Metadata $_.metadata })
    $metadata = $null
    $metadataPath = $null
    $source = 'none'
    $warning = $null
    $metadataAmbiguous = $false
    $metadataStaleIgnored = $false
    $process = $rawProcess

    if ($runningMatches.Count -eq 1) {
        $metadata = $runningMatches[0].metadata
        $metadataPath = $runningMatches[0].path
        $process = Get-BgTrackedProcess -Metadata $metadata
        $source = 'tracked'
    } elseif ($runningMatches.Count -gt 1) {
        $metadataAmbiguous = $true
        $warning = "Multiple running metadata entries match PID $Id in '$MetadataDirectory'. Ignoring metadata and using raw PID state."
        if ($rawProcess) {
            $source = 'raw'
        }
    } elseif ($rawProcess) {
        if ($records.Count -gt 0) {
            $metadataStaleIgnored = $true
            $source = 'raw'
            if ($records.Count -eq 1) {
                $warning = "Ignoring stale metadata for PID $Id in '$MetadataDirectory' because the live process no longer matches the recorded start time."
            } else {
                $metadataAmbiguous = $true
                $warning = "Ignoring $($records.Count) stale metadata entries for PID $Id in '$MetadataDirectory' and using raw PID state."
            }
        } else {
            $source = 'raw'
        }
    } elseif ($AllowStopped) {
        if ($records.Count -eq 1) {
            $metadata = $records[0].metadata
            $metadataPath = $records[0].path
            $source = 'stopped_metadata'
        } elseif ($records.Count -gt 1) {
            $metadataAmbiguous = $true
            $warning = "Multiple stopped metadata entries match PID $Id in '$MetadataDirectory'. Metadata details are ambiguous."
        }
    }

    return [pscustomobject]@{
        process = $process
        metadata = $metadata
        metadata_path = $metadataPath
        metadata_source = $source
        metadata_warning = $warning
        metadata_ambiguous = $metadataAmbiguous
        metadata_stale_ignored = $metadataStaleIgnored
    }
}

function Get-BgTrackedProcess {
    param(
        [Parameter(Mandatory = $true)]
        $Metadata
    )

    $process = Get-Process -Id ([int]$Metadata.pid) -ErrorAction SilentlyContinue
    if (-not $process) {
        return $null
    }

    if (-not ($Metadata.PSObject.Properties.Name -contains 'started_at') -or [string]::IsNullOrWhiteSpace($Metadata.started_at)) {
        return $process
    }

    try {
        if ($Metadata.PSObject.Properties.Name -contains 'started_at_ticks') {
            $recordedStartTicks = [int64]$Metadata.started_at_ticks
        } elseif ($Metadata.started_at -is [DateTime]) {
            $recordedStartTicks = $Metadata.started_at.ToUniversalTime().Ticks
        } else {
            $recordedStartTicks = [DateTimeOffset]::Parse($Metadata.started_at).UtcDateTime.Ticks
        }
        $actualStartTicks = $process.StartTime.ToUniversalTime().Ticks
        if ([Math]::Abs($actualStartTicks - $recordedStartTicks) -lt [TimeSpan]::TicksPerSecond) {
            return $process
        }
    } catch {
        return $null
    }

    return $null
}
