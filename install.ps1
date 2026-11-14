[CmdletBinding()]
param(
  [string]$Workspace = 'E:\workspace',
  [switch]$RegisterTasks
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$manager = Join-Path $Workspace 'AI盘根管理'
$skillRoot = Join-Path $Workspace 'skills\obsidianto-codex-conversation-archive'
$contextRoot = Join-Path $Workspace 'context-infrastructure'

New-Item -ItemType Directory -Path $manager -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $skillRoot) -Force | Out-Null
Copy-Item (Join-Path $repoRoot 'scripts\*.ps1') $manager -Force
Copy-Item (Join-Path $repoRoot 'skills\obsidianto-codex-conversation-archive') $skillRoot -Recurse -Force

if (-not (Test-Path (Join-Path $repoRoot 'vendor\context-infrastructure\.git'))) {
  git -C $repoRoot submodule update --init --recursive
}
if (-not (Test-Path $contextRoot)) {
  Copy-Item (Join-Path $repoRoot 'vendor\context-infrastructure') $contextRoot -Recurse
  git -C $contextRoot apply (Join-Path $repoRoot 'patches\context-infrastructure-windows-deepseek.patch')
}

if ($RegisterTasks) {
  $observer = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$manager\run-observer.ps1`""
  $reflector = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$manager\run-reflector-proposal.ps1`""
  $obsidian = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$manager\sync-obsidian-project-notes.ps1`""
  Register-ScheduledTask -TaskName 'Context-Infrastructure-Daily-Observer' -Action $observer -Trigger (New-ScheduledTaskTrigger -Daily -At '08:00') -Force | Out-Null
  Register-ScheduledTask -TaskName 'Context-Infrastructure-Weekly-Reflector-Proposal' -Action $reflector -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '09:30') -Force | Out-Null
  Register-ScheduledTask -TaskName 'Codex-Obsidian-Weekly-Project-Sync' -Action $obsidian -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '20:00') -Force | Out-Null
}

Write-Output "Installed archive pipeline under $Workspace"
