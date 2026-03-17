---
name: windows-background-process
description: Use when working on Windows without WSL and an agent needs to start, monitor, stop, or inspect long-running local programs in the background, or when the user wants multiple independent shell commands run concurrently. Covers `Start-Process`, `Start-Job`, PID tracking, stdout/stderr log files, port checks, and safe shutdown for native Windows development servers, watchers, test runners, and CLI tools.
---

# Windows Background Process

Use native Windows process management instead of `tmux`, `nohup`, or Unix job control.

## Core Rules

- Use `Start-Process` for long-running external programs such as `node`, `python`, `go`, `docker`, `java`, or compiled binaries.
- Use `Start-Job` only for PowerShell-native script blocks. Do not use it for general CLI tools unless there is a specific reason.
- Always redirect stdout and stderr to files for anything expected to keep running.
- Always capture either the PID or the job name so the process can be checked and stopped later.
- Reuse a process name only after cleaning its metadata. The helpers intentionally block name reuse to avoid losing track of older runs.
- Treat `-Name` as the stable identifier. `-Id` is useful for recovery and inspection, but names remain the most reliable way to manage a tracked process across commands.
- For multiple short independent commands, prefer parallel tool calls from your orchestration layer instead of backgrounding them.

## Bundled Scripts

This skill includes reusable helpers under `{baseDir}\scripts\`:

- `start-bg.ps1` starts a background process, redirects logs, and writes metadata.
- `list-bg.ps1` lists all registered background processes and marks whether each one is still running.
- `clean-bg.ps1` removes metadata for stopped processes, can optionally delete their log files, and can remove broken metadata files with `-RemoveInvalidMetadata`.
- `status-bg.ps1` checks whether a named process or PID is still running.
- `stop-bg.ps1` stops a named process or PID and updates metadata.
- `tail-log.ps1` reads the stdout or stderr log for a named process.
- `wait-bg.ps1` waits for a named process or PID to become running or stopped, with a timeout.

By default, these helpers store metadata under `$HOME\.codex\tmp\bg` and logs under `$HOME\.codex\tmp\logs`, so they can be queried from different working directories.
`start-bg.ps1` also defaults to `-WindowStyle Hidden` so background console programs do not pop open a new terminal window.

Preferred workflow:

```powershell
& "{baseDir}\scripts\start-bg.ps1" -Name app -FilePath npm -ArgumentList @('run','dev')
& "{baseDir}\scripts\wait-bg.ps1" -Name app -Until Running -TimeoutSeconds 10
& "{baseDir}\scripts\list-bg.ps1"
& "{baseDir}\scripts\status-bg.ps1" -Name app
& "{baseDir}\scripts\tail-log.ps1" -Name app -Stream out -Tail 50
& "{baseDir}\scripts\stop-bg.ps1" -Name app
& "{baseDir}\scripts\wait-bg.ps1" -Name app -Until Stopped -TimeoutSeconds 10
& "{baseDir}\scripts\clean-bg.ps1" -IncludeLogs
```

If you only have a PID, `status-bg.ps1 -Id <PID>`, `stop-bg.ps1 -Id <PID>`, and `wait-bg.ps1 -Id <PID>` will first try to reconnect to tracked metadata in the configured metadata directory. If the PID currently belongs to a different live process, stale metadata is ignored and the helpers fall back to raw PID state instead of letting stale metadata hijack the result.

## Long-Running Process Pattern

Create a stable log directory first:

```powershell
New-Item -ItemType Directory -Force "$HOME\.codex\tmp\logs" | Out-Null
```

Start a background process and keep the PID:

```powershell
$p = Start-Process -FilePath python `
  -ArgumentList '-m','http.server','8000' `
  -WorkingDirectory (Get-Location) `
  -RedirectStandardOutput "$HOME\.codex\tmp\logs\http.out.log" `
  -RedirectStandardError "$HOME\.codex\tmp\logs\http.err.log" `
  -PassThru

$p.Id
```

Use the same shape for `npm`, `node`, `go`, `cargo`, and other external tools.

## PowerShell Job Pattern

Use this only when the workload is naturally a PowerShell script block:

```powershell
Start-Job -Name sample-job -ScriptBlock {
  Set-Location 'C:\path\to\repo'
  pwsh -NoLogo -Command 'npm run build'
}
```

Inspect output:

```powershell
Receive-Job -Name sample-job -Keep
```

Stop and remove:

```powershell
Stop-Job -Name sample-job
Remove-Job -Name sample-job
```

## Monitoring

Check process by PID:

```powershell
Get-Process -Id <PID>
```

Check whether a port is listening:

```powershell
Get-NetTCPConnection -LocalPort 3000 -State Listen
```

Wait for a process lifecycle change:

```powershell
& "{baseDir}\scripts\wait-bg.ps1" -Name app -Until Running -TimeoutSeconds 15
& "{baseDir}\scripts\wait-bg.ps1" -Name app -Until Stopped -TimeoutSeconds 15
```

Read recent logs:

```powershell
Get-Content "$HOME\.codex\tmp\logs\app.out.log" -Tail 50
Get-Content "$HOME\.codex\tmp\logs\app.err.log" -Tail 50
```

PowerShell-hosted child processes may emit CLIXML on stderr. If you want plain-text error logs, prefer the tool's native text output mode or redirect `2>&1` inside the child command when appropriate.

`wait-bg.ps1` only waits for process state. It does not prove that the app is healthy, has finished booting, or is already listening on its port. For servers, combine it with a port or health check when readiness matters.
When waiting with `-Name -Until Stopped`, a missing metadata file is treated as already stopped so `wait-bg.ps1` remains stable if cleanup happens before the wait finishes.

Follow logs:

```powershell
Get-Content "$HOME\.codex\tmp\logs\app.out.log" -Wait
```

## Shutdown

Graceful stop when possible:

```powershell
Stop-Process -Id <PID>
```

Force only if needed:

```powershell
Stop-Process -Id <PID> -Force
```

If the process is attached to a port and the PID is unknown:

```powershell
$conn = Get-NetTCPConnection -LocalPort 3000 -State Listen | Select-Object -First 1
if ($conn) { Stop-Process -Id $conn.OwningProcess }
```

## Common Recipes

Development server:

```powershell
& "{baseDir}\scripts\start-bg.ps1" `
  -Name dev-server `
  -FilePath npm `
  -ArgumentList @('run','dev') `
  -WorkingDirectory 'C:\path\to\repo'
```

Watch mode test runner:

```powershell
& "{baseDir}\scripts\start-bg.ps1" `
  -Name test-watch `
  -FilePath pnpm `
  -ArgumentList @('test','--watch') `
  -WorkingDirectory 'C:\path\to\repo'
```

One-shot independent commands should not be backgrounded unless the user explicitly wants that. Run them in parallel with your orchestration layer instead.

To clean stopped tasks after a session:

```powershell
& "{baseDir}\scripts\clean-bg.ps1"
```

To also delete their log files:

```powershell
& "{baseDir}\scripts\clean-bg.ps1" -IncludeLogs
```

To delete invalid or partially written metadata files that `list-bg.ps1` marks as `metadata_valid = $false`:

```powershell
& "{baseDir}\scripts\clean-bg.ps1" -RemoveInvalidMetadata
```

To remove both invalid metadata and logs for valid stopped tasks in one pass:

```powershell
& "{baseDir}\scripts\clean-bg.ps1" -IncludeLogs -RemoveInvalidMetadata
```

## Edge Cases

- If a custom log or metadata path already exists as a file instead of a directory, the helpers now stop immediately with a clear error instead of starting a process that cannot be tracked safely.
- `start-bg.ps1` writes metadata after process launch; if that write fails, it now stops the newly started process to avoid leaving an orphan behind.
- Same-name concurrent `start-bg.ps1` calls now serialize on a per-name lock so they fail with a stable, actionable message instead of surfacing random file-lock errors.
- `list-bg.ps1` surfaces broken metadata as `metadata_valid = $false` plus an error message, instead of emitting blank rows.
- `tail-log.ps1` now fails fast with a clearer message when the requested log file does not exist.
- `status-bg.ps1`, `stop-bg.ps1`, and `wait-bg.ps1` ignore stale metadata when a live PID no longer matches the recorded `started_at`, so PID reuse does not hijack raw PID operations.
- Sanitized names are still stored as the primary tracking key. Different input names that collapse to the same safe name will still collide, so pick distinct names made from letters, digits, `.`, `_`, or `-` when possible.

## When Not to Use

- Do not use this skill for Unix shells, WSL workflows, `tmux`, or Linux servers.
- Do not use `Start-Job` as a substitute for terminal multiplexing.
- Do not claim a process started successfully until you have checked PID, port, or log output.
- Do not leave orphaned processes behind when the task is finished unless the user asked to keep them running.
