[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$stateDb = 'C:\Users\liuqi\.codex\state_5.sqlite'
$vault = 'E:\obsidian\QingObs'
$noteDir = Join-Path $vault '05-Codex归档\项目'
$baseSyncScript = 'E:\workspace\AI盘根管理\run-codex-archive-base.ps1'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$begin = '<!-- CODEX-WEEKLY-PROJECT-SYNC:BEGIN -->'
$end = '<!-- CODEX-WEEKLY-PROJECT-SYNC:END -->'

if (-not (Test-Path -LiteralPath $vault -PathType Container)) { throw "Obsidian Vault not found: $vault" }
if (-not (Test-Path -LiteralPath $stateDb -PathType Leaf)) { throw "Codex state database not found: $stateDb" }
if (Test-Path -LiteralPath $baseSyncScript) { & $baseSyncScript | Out-Null }

$sqlite = (Get-Command sqlite3.exe -ErrorAction Stop).Source
$sql = @'
SELECT p.name, r.path
FROM projects p
JOIN project_roots r ON r.project_id = p.id AND r.position = 0
WHERE r.path NOT LIKE 'C:\Users\liuqi\.codex\.chatgpt-projects\%'
ORDER BY p.position, p.name;
'@
$rows = @(& $sqlite -separator "`t" $stateDb $sql)
$projects = foreach ($line in $rows) {
  $parts = $line -split "`t", 2
  if ($parts.Count -eq 2 -and $parts[0] -and $parts[1]) {
    [pscustomobject]@{ Name=$parts[0]; Root=$parts[1] }
  }
}

function Safe-FileName([string]$name) { return ($name -replace '[\\/:*?""<>|]', '_') }
function Read-RecentTitles([string]$path) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
  $lines = Get-Content -LiteralPath $path -Encoding UTF8
  return @($lines | Where-Object { $_ -match '^###\s+(.+)$' } | ForEach-Object { $matches[1].Trim() } | Select-Object -Last 5)
}

New-Item -ItemType Directory -Path $noteDir -Force | Out-Null
$now = Get-Date
$cutoff = $now.AddDays(-7)
$results = foreach ($project in $projects) {
  $session = Join-Path $project.Root '会话记录.md'
  $note = Join-Path $noteDir ("Codex项目 - " + (Safe-FileName $project.Name) + '.md')
  $sessionExists = Test-Path -LiteralPath $session -PathType Leaf
  $sessionItem = if ($sessionExists) { Get-Item -LiteralPath $session } else { $null }
  $changed = $sessionItem -and $sessionItem.LastWriteTime -ge $cutoff
  $titles = @(Read-RecentTitles $session)
  if (-not (Test-Path -LiteralPath $note -PathType Leaf)) {
    $initial = @("---", "title: Codex项目 - $($project.Name)", 'type: Codex项目', 'status: 自动同步', 'tags:', '  - Codex归档', '  - Codex项目', '---', "# Codex项目 - $($project.Name)", '', '本笔记由本机每周项目同步维护；人工正文不由脚本覆盖。', '') -join "`r`n"
    [IO.File]::WriteAllText($note, $initial + "`r`n", $utf8)
  }
  $existing = [IO.File]::ReadAllText($note, $utf8)
  $block = [Text.StringBuilder]::new()
  [void]$block.AppendLine($begin)
  [void]$block.AppendLine('## 每周项目同步（自动维护）')
  [void]$block.AppendLine()
  [void]$block.AppendLine("- 更新时间：$($now.ToString('yyyy-MM-dd HH:mm:ss zzz'))")
  [void]$block.AppendLine("- 项目根目录：``$($project.Root)``")
  [void]$block.AppendLine("- 本周会话归档是否更新：$([bool]$changed)")
  if ($sessionExists) {
    [void]$block.AppendLine("- 会话记录文件：``$session``")
    [void]$block.AppendLine("- 会话记录最后修改：$($sessionItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))")
    [void]$block.AppendLine("- 会话记录大小：$($sessionItem.Length) bytes")
  } else {
    [void]$block.AppendLine('- 会话记录文件：尚未生成')
  }
  [void]$block.AppendLine('- 最近会话标题：')
  if ($titles.Count -gt 0) { foreach ($title in $titles) { [void]$block.AppendLine("  - $title") } }
  else { [void]$block.AppendLine('  - 暂无可提取标题') }
  [void]$block.AppendLine('- 证据边界：本区块只反映本机项目目录与会话归档文件状态，不等同于功能完成、真机验收、Owner 验收或生产发布。')
  [void]$block.AppendLine($end)
  $managed = $block.ToString().TrimEnd()
  $pattern = '(?s)\r?\n?<!-- CODEX-WEEKLY-PROJECT-SYNC:BEGIN -->.*?<!-- CODEX-WEEKLY-PROJECT-SYNC:END -->\r?\n?'
  if ([regex]::IsMatch($existing, $pattern)) { $updated = [regex]::Replace($existing, $pattern, "`r`n$managed`r`n") }
  else { $updated = $existing.TrimEnd() + "`r`n`r`n$managed`r`n" }
  [IO.File]::WriteAllText($note, $updated, $utf8)
  [pscustomobject]@{ Project=$project.Name; Note=$note; SessionExists=$sessionExists; ChangedThisWeek=[bool]$changed }
}
$results | ConvertTo-Json -Depth 4
