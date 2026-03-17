param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [string[]]$ArgumentList = @(),

    [string]$WorkingDirectory = (Get-Location).Path,

    [ValidateSet("Hidden", "Normal", "Minimized", "Maximized")]
    [string]$WindowStyle = "Hidden",

    [string]$LogDirectory,

    [string]$MetadataDirectory
)

. (Join-Path $PSScriptRoot 'bg-common.ps1')

$safeName = ConvertTo-BgSafeName -Name $Name
$resolvedLogDirectory = Resolve-BgDirectory -Path $LogDirectory -LeafName 'logs'
$resolvedMetadataDirectory = Resolve-BgDirectory -Path $MetadataDirectory -LeafName 'bg'
$resolvedWorkingDirectory = [System.IO.Path]::GetFullPath($WorkingDirectory)

$resolvedLogDirectory = Ensure-BgDirectory -Path $resolvedLogDirectory
$resolvedMetadataDirectory = Ensure-BgDirectory -Path $resolvedMetadataDirectory

$stdoutPath = Join-Path $resolvedLogDirectory "$safeName.out.log"
$stderrPath = Join-Path $resolvedLogDirectory "$safeName.err.log"
$metadataPath = Get-BgMetadataPath -Name $safeName -MetadataDirectory $resolvedMetadataDirectory
$mutexName = Get-BgMutexName -MetadataDirectory $resolvedMetadataDirectory -Name $safeName
$mutex = [System.Threading.Mutex]::new($false, $mutexName)
$lockTaken = $false

try {
    try {
        $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(5))
    } catch [System.Threading.AbandonedMutexException] {
        $lockTaken = $true
    }

    if (-not $lockTaken) {
        throw "Timed out waiting for the background-process lock for '$safeName'. Another start may already be in progress."
    }

    if (Test-Path $metadataPath) {
        $existingMetadata = Read-BgMetadata -Path $metadataPath
        $existingProcess = Get-BgTrackedProcess -Metadata $existingMetadata
        if ($existingProcess) {
            throw "Background process '$safeName' is already running with PID $($existingProcess.Id). Stop it first or use a different -Name."
        }
        throw "Metadata for '$safeName' already exists at '$metadataPath'. Run clean-bg.ps1 before reusing this name."
    }

    try {
        New-Item -ItemType File -Force -Path $stdoutPath, $stderrPath -ErrorAction Stop | Out-Null
    } catch {
        throw "Failed to prepare log files for '$safeName'. Another start may be in progress, or the log files may be locked: $($_.Exception.Message)"
    }

    try {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $ArgumentList `
            -WorkingDirectory $resolvedWorkingDirectory `
            -WindowStyle $WindowStyle `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -PassThru `
            -ErrorAction Stop
    } catch {
        throw "Failed to start background process '$safeName' using '$FilePath': $($_.Exception.Message)"
    }

    $metadata = [ordered]@{
        name = $safeName
        requested_name = $Name
        pid = $process.Id
        file_path = $FilePath
        arguments = $ArgumentList
        working_directory = $resolvedWorkingDirectory
        stdout_log = $stdoutPath
        stderr_log = $stderrPath
        metadata_path = $metadataPath
        started_at = $process.StartTime.ToUniversalTime().ToString("o")
        started_at_ticks = $process.StartTime.ToUniversalTime().Ticks
        window_style = $WindowStyle
    }

    try {
        $metadata | ConvertTo-Json -Depth 5 | Set-Content -Path $metadataPath -Encoding UTF8 -ErrorAction Stop
    } catch {
        $writeError = $_.Exception.Message
        $stopError = $null

        try {
            if (-not $process.HasExited) {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            }
        } catch {
            $stopError = $_.Exception.Message
        }

        if ($stopError) {
            throw "Started background process '$safeName' with PID $($process.Id), but failed to write metadata to '$metadataPath' and could not stop the process: $writeError. Stop error: $stopError"
        }

        throw "Started background process '$safeName' with PID $($process.Id), but failed to write metadata to '$metadataPath'. The process was stopped to avoid leaving an orphan: $writeError"
    }

    $metadata
} finally {
    if ($mutex) {
        if ($lockTaken) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}
