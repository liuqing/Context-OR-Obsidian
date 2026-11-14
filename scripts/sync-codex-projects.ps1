[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$stateDb = 'C:\Users\liuqi\.codex\state_5.sqlite'
$mapPath = 'E:\MAP.md'
$legacyClaudeBackup = 'E:\workspace\AI盘根管理\legacy-claude-backup'
$sqlite = (Get-Command sqlite3 -ErrorAction Stop).Source
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

if (-not (Test-Path -LiteralPath $stateDb -PathType Leaf)) {
  throw "Codex project state database not found: $stateDb"
}
if (-not (Test-Path -LiteralPath $mapPath -PathType Leaf)) {
  throw "E-drive project map not found: $mapPath"
}

$sql = @'
SELECT p.id, p.name, r.path
FROM projects p
JOIN project_roots r ON r.project_id = p.id AND r.position = 0
ORDER BY p.position, p.name;
'@
$lines = & $sqlite -separator "`t" $stateDb $sql
if ($LASTEXITCODE -ne 0) { throw 'Unable to read Codex project metadata.' }
$projects = @($lines | ForEach-Object {
  $parts = $_ -split "`t", 3
  if ($parts.Count -eq 3) {
    [pscustomobject]@{ id=$parts[0]; name=$parts[1]; path=$parts[2] }
  }
}) | Where-Object {
  $_.path -and $_.path -notlike 'C:\Users\liuqi\.codex\.chatgpt-projects\*'
}

function Ensure-ProjectFiles {
  param([Parameter(Mandatory = $true)]$Project)

  if (-not (Test-Path -LiteralPath $Project.path -PathType Container)) {
    return [pscustomobject]@{ Name=$Project.name; Path=$Project.path; Status='missing-root' }
  }

  $agentsPath = Join-Path $Project.path 'AGENTS.md'
  $sessionPath = Join-Path $Project.path '会话记录.md'

  if (-not (Test-Path -LiteralPath $agentsPath -PathType Leaf)) {
    $agents = @"
# $($Project.name) 项目规则

本目录是 Codex 项目“$($Project.name)”的绑定目录。

每次任务开始先读取 `E:\workspace\规矩文档.txt`、`E:\workspace\踩坑日志.txt` 和本文件。每轮结束前，把本轮用户消息、助手最终答复、关键执行结果和文件路径追加到本目录 `会话记录.md`。系统 transcript 与本地 Markdown 是两套记录；旧聊天正文无法取得时只登记待补录，不得臆造。禁止记录密码、令牌、Cookie、AppSecret 或私钥。
"@
    [IO.File]::WriteAllText($agentsPath, $agents.TrimEnd() + "`n", $utf8NoBom)
  } elseif (-not (Select-String -LiteralPath $agentsPath -Pattern '会话记录\.md' -Quiet)) {
    $append = @"

## 本地会话归档

属于 Codex 项目“$($Project.name)”的所有聊天，每轮结束前追加到本目录 `会话记录.md`。旧聊天正文无法取得时只登记待补录，不得臆造。
"@
    [IO.File]::AppendAllText($agentsPath, $append, $utf8NoBom)
  }

  $claudePath = Join-Path $Project.path 'CLAUDE.md'
  if (Test-Path -LiteralPath $claudePath -PathType Leaf) {
    $legacy = [IO.File]::ReadAllText($claudePath)
    $custom = [regex]::Replace($legacy, '^\s*@AGENTS\.md\s*', '').Trim()
    if ($custom) {
      $agentsNow = [IO.File]::ReadAllText($agentsPath)
      $migrationMarker = '## 从旧 CLAUDE.md 迁移的项目规则'
      if (-not $agentsNow.Contains($migrationMarker)) {
        $migrated = "`n`n$migrationMarker`n`n$custom`n"
        [IO.File]::AppendAllText($agentsPath, $migrated, $utf8NoBom)
      }
    }
    if (-not (Test-Path -LiteralPath $legacyClaudeBackup -PathType Container)) {
      [IO.Directory]::CreateDirectory($legacyClaudeBackup) | Out-Null
    }
    $safeName = ($Project.name -replace '[\\/:*?""<>|]', '_') + '-CLAUDE.md'
    $backupPath = Join-Path $legacyClaudeBackup $safeName
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
      [IO.File]::WriteAllText($backupPath, $legacy, $utf8NoBom)
    }
    Remove-Item -LiteralPath $claudePath -Force
  }

  $assistantEntries = @(
    @{ File='HARNESS.md'; Label='Harness' },
    @{ File='DEEPSEEK_HARNESS.md'; Label='DeepSeek Harness' },
    @{ File='MUSE.md'; Label='Muse' }
  )
  foreach ($entry in $assistantEntries) {
    $entryPath = Join-Path $Project.path $entry.File
    if (-not (Test-Path -LiteralPath $entryPath -PathType Leaf)) {
      $entryText = @"
# $($entry.Label) 项目入口

本项目的唯一公共规则源是同目录 `AGENTS.md`。开始任务前必须完整读取并遵守 `AGENTS.md`，不要在本文件复制项目规则，以免多份规则漂移。

本入口适用于 $($entry.Label)；会话归档仍统一写入同目录 `会话记录.md`。
"@
      [IO.File]::WriteAllText($entryPath, $entryText.TrimEnd() + "`n", $utf8NoBom)
    }
  }

  if (-not (Test-Path -LiteralPath $sessionPath -PathType Leaf)) {
    $session = "# $($Project.name) 会话记录`n`n> 从 $(Get-Date -Format 'yyyy-MM-dd') 起统一归档本项目聊天；此前聊天需按需从原聊天补录。`n"
    [IO.File]::WriteAllText($sessionPath, $session, $utf8NoBom)
  }

  return [pscustomobject]@{ Name=$Project.name; Path=$Project.path; Status='ready' }
}

$results = foreach ($project in $projects) { Ensure-ProjectFiles -Project $project }

# E 盘盘根也使用同一套多助手入口，避免项目已替换但总入口仍残留 Claude 专属文件。
$rootClaudePath = 'E:\CLAUDE.md'
if (Test-Path -LiteralPath $rootClaudePath -PathType Leaf) {
  if (-not (Test-Path -LiteralPath $legacyClaudeBackup -PathType Container)) {
    [IO.Directory]::CreateDirectory($legacyClaudeBackup) | Out-Null
  }
  $rootClaudeBackup = Join-Path $legacyClaudeBackup 'E-drive-root-CLAUDE.md'
  if (-not (Test-Path -LiteralPath $rootClaudeBackup -PathType Leaf)) {
    [IO.File]::WriteAllText($rootClaudeBackup, [IO.File]::ReadAllText($rootClaudePath), $utf8NoBom)
  }
  Remove-Item -LiteralPath $rootClaudePath -Force
}
$rootAssistantEntries = @(
  @{ Path='E:\HARNESS.md'; Label='Harness' },
  @{ Path='E:\DEEPSEEK_HARNESS.md'; Label='DeepSeek Harness' },
  @{ Path='E:\MUSE.md'; Label='Muse' }
)
foreach ($entry in $rootAssistantEntries) {
  if (-not (Test-Path -LiteralPath $entry.Path -PathType Leaf)) {
    $text = "# $($entry.Label) E 盘盘根入口`n`n开始工作前必须完整读取并遵守 ``E:\AGENTS.md``；项目任务随后继续读取目标项目目录的 ``AGENTS.md``。``E:\MAP.md`` 是项目导航，``E:\MEMORY.md`` 是可复用经验索引。`n"
    [IO.File]::WriteAllText($entry.Path, $text, $utf8NoBom)
  }
}

function Map-Link {
  param([string]$Path, [string]$Child = '')
  $target = if ($Child) { Join-Path $Path $Child } else { $Path }
  return ($target -replace '\\','/' -replace ' ','%20')
}

$rows = foreach ($project in $projects) {
  $rootLink = Map-Link -Path $project.path
  $agentsLink = Map-Link -Path $project.path -Child 'AGENTS.md'
  $sessionLink = Map-Link -Path $project.path -Child '会话记录.md'
  '| {0} | [{1}]({2}) | [AGENTS.md]({3}) | [会话记录.md]({4}) |' -f $project.name,$project.path,$rootLink,$agentsLink,$sessionLink
}

$managedLines = @(
  '<!-- CODEX-PROJECTS:BEGIN -->',
  "## Codex 用户项目（$($projects.Count) 个）",
  '',
  '本节由 `E:\workspace\AI盘根管理\sync-codex-projects.ps1` 根据 Codex 本机项目清单维护。每个项目第一次开聊时应先运行同步脚本。',
  '',
  '| Codex 项目 | 首个绑定目录 | 规则入口 | 会话归档 |',
  '| --- | --- | --- | --- |'
)
$managedLines += $rows
$managedLines += @(
  '',
  'ChatGPT 自动管理的内部项目目录不写入本表，也不向其写人工归档。',
  '<!-- CODEX-PROJECTS:END -->'
)
$managed = $managedLines -join "`n"

$map = [IO.File]::ReadAllText($mapPath)
$pattern = '(?s)<!-- CODEX-PROJECTS:BEGIN -->.*?<!-- CODEX-PROJECTS:END -->'
if ([regex]::IsMatch($map, $pattern)) {
  $map = [regex]::Replace($map, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $managed })
} else {
  $firstBreak = $map.IndexOf("`n`n")
  if ($firstBreak -lt 0) { $map = $map.TrimEnd() + "`n`n" + $managed + "`n" }
  else { $map = $map.Insert($firstBreak + 2, $managed + "`n`n") }
}
[IO.File]::WriteAllText($mapPath, $map, $utf8NoBom)

$results | Format-Table -AutoSize
Write-Output "Synchronized $($projects.Count) Codex user projects."
