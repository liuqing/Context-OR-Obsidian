[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspace = 'E:\workspace'
$repo = Join-Path $workspace 'context-infrastructure'
$logDir = Join-Path $workspace 'AI盘根管理\logs'
$logPath = Join-Path $logDir 'reflector-proposal.log'
$baseSync = Join-Path $workspace 'AI盘根管理\run-codex-archive-base.ps1'
$reflector = Join-Path $repo 'periodic_jobs\ai_heartbeat\src\v0\reflector.py'
$candidatesPath = Join-Path $repo 'contexts\memory\RULE_CANDIDATES.md'
$opencode = 'E:\OpenClaw\opencode.ps1'
$opencodeExe = 'E:\OpenClaw\node_modules\opencode-ai\bin\opencode.exe'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$startedByScript = $false
$serverProcess = $null

# Scheduled tasks do not always inherit a newly-added user environment variable;
# load the user-scoped DeepSeek key into this process without ever logging it.
$deepSeekUserKey = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'User')
if ($deepSeekUserKey) { $env:DEEPSEEK_API_KEY = $deepSeekUserKey }

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
function Log([string]$message) {
  $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')] $message`r`n"
  [IO.File]::AppendAllText($logPath, $line, $utf8)
}

try {
  if (Test-Path -LiteralPath $baseSync) { & $baseSync | ForEach-Object { Log ([string]$_) } }

  if (-not (Test-Path -LiteralPath $reflector -PathType Leaf)) { Log '跳过：Reflector 脚本不存在。'; exit 0 }
  if (-not (Test-NetConnection 127.0.0.1 -Port 4096 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    if (-not (Test-Path -LiteralPath $opencodeExe -PathType Leaf)) { Log '跳过：OpenCode CLI 不存在；未生成候选、未修改规则。'; exit 0 }
    Log 'OpenCode Server 未运行，尝试启动本机回环服务。'
    $serverProcess = Start-Process -FilePath $opencodeExe -ArgumentList 'serve','--hostname','127.0.0.1','--port','4096','--log-level','INFO' -WorkingDirectory $repo -WindowStyle Hidden -PassThru
    $startedByScript = $true
    $ready = $false
    for ($i = 0; $i -lt 20; $i++) {
      Start-Sleep -Seconds 1
      if (Test-NetConnection 127.0.0.1 -Port 4096 -InformationLevel Quiet -WarningAction SilentlyContinue) { $ready = $true; break }
    }
    if (-not $ready) { Log '跳过：OpenCode Server 启动失败；未生成候选、未修改规则。'; exit 0 }
  }

  $env:CONTEXT_WORKSPACE_ROOT = $repo
  $env:CONTEXT_RULES_ROOT = $repo
  $env:CONTEXT_KNOWLEDGE_BASE = Join-Path $repo 'periodic_jobs\ai_heartbeat\docs\KNOWLEDGE_BASE.md'
  $env:REFLECTOR_MODEL = if ($env:REFLECTOR_MODEL) { $env:REFLECTOR_MODEL } else { 'deepseek/deepseek-flash' }
  $venvPython = Join-Path $repo '.venv\Scripts\python.exe'
  $python = if (Test-Path -LiteralPath $venvPython -PathType Leaf) { $venvPython } else { (Get-Command python -ErrorAction Stop).Source }
  & $python $reflector 2>&1 | ForEach-Object { Log ([string]$_) }
  if ($LASTEXITCODE -ne 0) { throw "Reflector proposal exited with code $LASTEXITCODE" }
  $pending = if (Test-Path -LiteralPath $candidatesPath) { @(Select-String -LiteralPath $candidatesPath -Pattern '^\- \[ \] 批准' -Encoding UTF8).Count } else { 0 }
  if ($pending -gt 0) {
    Start-Process -FilePath 'notepad.exe' -ArgumentList $candidatesPath | Out-Null
    Log "完成：发现 $pending 条待批准候选，已自动打开 RULE_CANDIDATES.md 提醒人工审核；未合入 rules/。"
  } else {
    Log '完成：没有待批准候选；未弹窗、未合入 rules/。'
  }
} catch {
  Log "失败：$($_.Exception.Message)"
  exit 1
} finally {
  if ($startedByScript -and $serverProcess -and -not $serverProcess.HasExited) {
    Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
    Log '已关闭：本轮由脚本启动的 OpenCode Server。'
  }
}
