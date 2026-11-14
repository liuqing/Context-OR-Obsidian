[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspace = 'E:\workspace'
$sync = Join-Path $workspace 'AI盘根管理\sync-codex-projects.ps1'
$export = Join-Path $workspace 'AI盘根管理\export-codex-history.ps1'
$mutexName = 'Global\CodexArchiveBaseSync'
$mutex = [Threading.Mutex]::new($false, $mutexName)
$locked = $false
try {
  $locked = $mutex.WaitOne(0)
  if (-not $locked) { Write-Output 'SKIPPED: another archive-base sync is running.'; exit 0 }
  if (-not (Test-Path -LiteralPath $sync -PathType Leaf)) { throw "Missing script: $sync" }
  if (-not (Test-Path -LiteralPath $export -PathType Leaf)) { throw "Missing script: $export" }
  & $sync | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "sync-codex-projects.ps1 exited with code $LASTEXITCODE" }
  & $export | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "export-codex-history.ps1 exited with code $LASTEXITCODE" }
  Write-Output 'OK: project discovery and Codex history export completed.'
} finally {
  if ($locked) { $mutex.ReleaseMutex() | Out-Null }
  $mutex.Dispose()
}
