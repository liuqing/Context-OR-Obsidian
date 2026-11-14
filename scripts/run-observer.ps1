[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspace = 'E:\workspace'
$repo = Join-Path $workspace 'context-infrastructure'
$logDir = Join-Path $workspace 'AI盘根管理\logs'
$logPath = Join-Path $logDir 'observer.log'
$baseSync = Join-Path $workspace 'AI盘根管理\run-codex-archive-base.ps1'
$observer = Join-Path $repo 'periodic_jobs\ai_heartbeat\src\v0\observer.py'
$opencodeExe = 'E:\OpenClaw\node_modules\opencode-ai\bin\opencode.exe'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedByScript = $false
$serverProcess = $null
$deepSeekUserKey = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'User')
if ($deepSeekUserKey) { $env:DEEPSEEK_API_KEY = $deepSeekUserKey }
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
function Log([string]$message) { [IO.File]::AppendAllText($logPath, "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')] $message`r`n", $utf8) }

try {
  if (Test-Path $baseSync) { & $baseSync | ForEach-Object { Log ([string]$_) } }
  if (-not (Test-Path $observer -PathType Leaf)) { Log '跳过：Observer 脚本不存在。'; exit 0 }
  $date = Get-Date -Format 'yyyy-MM-dd'
  if (Test-Path (Join-Path $workspace 'contexts\memory\OBSERVATIONS.md')) {
    if (Select-String -LiteralPath (Join-Path $workspace 'contexts\memory\OBSERVATIONS.md') -Pattern "Date: $date" -Quiet) { Log "跳过：$date 已有观察记录。"; exit 0 }
  }
  if (-not (Test-NetConnection 127.0.0.1 -Port 4096 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    if (-not (Test-Path $opencodeExe -PathType Leaf)) { Log '跳过：OpenCode CLI 不存在。'; exit 0 }
    Log 'OpenCode Server 未运行，尝试启动本机回环服务。'
    $serverProcess = Start-Process -FilePath $opencodeExe -ArgumentList 'serve','--hostname','127.0.0.1','--port','4096','--log-level','INFO' -WorkingDirectory $repo -WindowStyle Hidden -PassThru
    $startedByScript = $true
    $ready = $false
    for ($i=0; $i -lt 20; $i++) { Start-Sleep 1; if (Test-NetConnection 127.0.0.1 -Port 4096 -InformationLevel Quiet -WarningAction SilentlyContinue) { $ready=$true; break } }
    if (-not $ready) { Log '跳过：OpenCode Server 启动失败。'; exit 0 }
  }
  $venvPython = Join-Path $repo '.venv\Scripts\python.exe'
  $python = if (Test-Path $venvPython) { $venvPython } else { (Get-Command python -ErrorAction Stop).Source }
  $env:CONTEXT_WORKSPACE_ROOT = $workspace
  $env:CONTEXT_KNOWLEDGE_BASE = Join-Path $repo 'periodic_jobs\ai_heartbeat\docs\KNOWLEDGE_BASE.md'
  $env:OBSERVER_MODEL = if ($env:OBSERVER_MODEL) { $env:OBSERVER_MODEL } else { 'deepseek/deepseek-flash' }
  & $python $observer $date 2>&1 | ForEach-Object { Log ([string]$_) }
  if ($LASTEXITCODE -ne 0) { throw "Observer exited with code $LASTEXITCODE" }
  Log '完成：Observer 仅更新 OBSERVATIONS.md，未修改 rules/。'
} catch { Log "失败：$($_.Exception.Message)"; exit 1 }
finally {
  if ($startedByScript -and $serverProcess -and -not $serverProcess.HasExited) { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue; Log '已关闭：本轮由脚本启动的 OpenCode Server。' }
}
