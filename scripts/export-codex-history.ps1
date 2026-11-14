[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$stateDb = 'C:\Users\liuqi\.codex\state_5.sqlite'
$historyDb = 'C:\Users\liuqi\.codex\thread_history_1.sqlite'
$reportPath = 'E:\workspace\AI盘根管理\会话归档报告.md'
$temporaryArchivePath = 'E:\临时会话记录.md'
$temporaryBeginMarker = '<!-- CODEX-UNMAPPED-HISTORY:BEGIN -->'
$temporaryEndMarker = '<!-- CODEX-UNMAPPED-HISTORY:END -->'
$beginMarker = '<!-- CODEX-HISTORY:BEGIN -->'
$endMarker = '<!-- CODEX-HISTORY:END -->'

function Invoke-SqliteJson {
    param([string]$Database, [string]$Sql)
    $lines = & sqlite3.exe -json $Database $Sql
    if ($LASTEXITCODE -ne 0) { throw "sqlite3 查询失败：$Database" }
    $text = ($lines -join "`n").Trim()
    if (-not $text) { return @() }
    return @($text | ConvertFrom-Json)
}

function Normalize-PathText {
    param([AllowNull()][string]$Path)
    if (-not $Path) { return '' }
    $value = $Path -replace '^\\\\\?\\', ''
    return $value.TrimEnd('\').ToLowerInvariant()
}

function Protect-Secrets {
    param([AllowNull()][string]$Text)
    if (-not $Text) { return '' }
    $safe = $Text
    $safe = [regex]::Replace($safe, '(?im)(authorization\s*:\s*(?:bearer|basic)\s+)[^\s`"'']+', '$1[已隐藏]')
    $safe = [regex]::Replace($safe, '(?im)\b(api[_-]?key|app[_-]?secret|client[_-]?secret|access[_-]?token|refresh[_-]?token|password|passwd|cookie)\b\s*[:=]\s*([^\s,;]+)', '$1=[已隐藏]')
    $safe = [regex]::Replace($safe, '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', '[私钥已隐藏]')
    $safe = [regex]::Replace($safe, '\bsk-[A-Za-z0-9_-]{16,}\b', '[密钥已隐藏]')
    return $safe
}

function Sql-Literal {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

$projectRows = Invoke-SqliteJson $stateDb @'
SELECT p.id, p.name, r.path, r.position
FROM projects p
JOIN project_roots r ON r.project_id = p.id
WHERE r.path NOT LIKE '%\.codex\.chatgpt-projects\%'
ORDER BY p.position, r.position;
'@

$projects = @{}
foreach ($row in $projectRows) {
    if (-not $projects.ContainsKey($row.id)) {
        $projects[$row.id] = [ordered]@{
            Id = [string]$row.id
            Name = [string]$row.name
            PrimaryRoot = $null
            Roots = @()
            Threads = [System.Collections.Generic.List[object]]::new()
        }
    }
    $root = [pscustomobject]@{
        Path = [string]$row.path
        Normalized = Normalize-PathText ([string]$row.path)
        Position = [int]$row.position
    }
    $projects[$row.id].Roots += $root
    if ($root.Position -eq 0) { $projects[$row.id].PrimaryRoot = $root.Path }
}

$threadRows = Invoke-SqliteJson $stateDb @'
SELECT id, title, first_user_message, cwd, created_at, updated_at, archived
FROM threads
ORDER BY created_at, id;
'@

$unmapped = [System.Collections.Generic.List[object]]::new()
$methodCounts = @{}

$keywordRules = @(
    @{ Name = 'MiBiz手机APP'; Pattern = '(?i)MiBiz手机|AI开单助手|AI工程助手' },
    @{ Name = '锦鸿机电工单系统'; Pattern = '锦鸿机电|工单系统|设备保养与维修' },
    @{ Name = '零星工程报价程序'; Pattern = '零星工程报价|报价小程序' },
    @{ Name = 'YouTube学习插件Skill'; Pattern = '(?i)YouTube\s*Digest|YouTube学习插件' },
    @{ Name = 'MyObsidian'; Pattern = '(?i)MyObsidian|Obsidian' },
    @{ Name = 'HardwareFast'; Pattern = '(?i)HardwareFast' },
    @{ Name = 'MiBiz'; Pattern = '(?i)\bMiBiz\b|快速开单' },
    @{ Name = '源林'; Pattern = '源林' },
    @{ Name = '华为电脑中转站修改'; Pattern = '(?i)华为电脑中转站|Huawei Share' },
    @{ Name = '硬件开发'; Pattern = '(?i)ESP32|硬件开发' },
    @{ Name = '视频制作'; Pattern = '视频制作|锦鸿机电工程工艺|桥架线槽安装' }
)

foreach ($thread in $threadRows) {
    $cwd = Normalize-PathText ([string]$thread.cwd)
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($project in $projects.Values) {
        foreach ($root in $project.Roots) {
            if ($cwd -eq $root.Normalized -or $cwd.StartsWith($root.Normalized + '\')) {
                $candidates.Add([pscustomobject]@{ Project = $project; Length = $root.Normalized.Length; Position = $root.Position })
            }
        }
    }

    $selected = $null
    $method = $null
    if ($candidates.Count -gt 0) {
        $best = $candidates | Sort-Object @{Expression='Length';Descending=$true}, @{Expression='Position';Ascending=$true} | Select-Object -First 1
        $selected = $best.Project
        $method = if ($best.Position -eq 0) { '目录主绑定' } else { '目录次绑定' }
    }

    if (-not $selected) {
        $leaf = if ($cwd) { [System.IO.Path]::GetFileName($cwd.TrimEnd('\')) } else { '' }
        $byName = @($projects.Values | Where-Object { $_.Name.ToLowerInvariant() -eq $leaf })
        if ($byName.Count -eq 1) {
            $selected = $byName[0]
            $method = '旧目录同名'
        }
    }

    if (-not $selected -and $cwd -match '(?i)\\快速开单(?:\\|$)') {
        $selected = $projects.Values | Where-Object Name -eq 'MiBiz' | Select-Object -First 1
        $method = '已知旧项目目录'
    }

    if (-not $selected) {
        $haystack = ([string]$thread.title) + "`n" + ([string]$thread.first_user_message)
        $hits = @()
        foreach ($rule in $keywordRules) {
            if ($haystack -match $rule.Pattern) { $hits += $rule.Name }
        }
        $hits = @($hits | Select-Object -Unique)
        if ($hits.Count -eq 1) {
            $selected = $projects.Values | Where-Object Name -eq $hits[0] | Select-Object -First 1
            $method = '明确项目关键词'
        }
    }

    if ($selected) {
        $selected.Threads.Add([pscustomobject]@{
            Id = [string]$thread.id
            Title = [string]$thread.title
            Cwd = [string]$thread.cwd
            CreatedAt = [long]$thread.created_at
            UpdatedAt = [long]$thread.updated_at
            Archived = [bool]$thread.archived
            MatchMethod = $method
        })
        if (-not $methodCounts.ContainsKey($method)) { $methodCounts[$method] = 0 }
        $methodCounts[$method]++
    } else {
        $unmapped.Add($thread)
    }
}

$utf8 = [System.Text.UTF8Encoding]::new($false)
$totalMessages = 0
$writtenProjects = 0

foreach ($project in ($projects.Values | Sort-Object Name)) {
    $archivePath = Join-Path $project.PrimaryRoot '会话记录.md'
    if (-not (Test-Path -LiteralPath $archivePath)) {
        [System.IO.File]::WriteAllText($archivePath, "# 会话记录`r`n", $utf8)
    }
    $existing = [System.IO.File]::ReadAllText($archivePath)
    $escapedBegin = [regex]::Escape($beginMarker)
    $escapedEnd = [regex]::Escape($endMarker)
    $manual = [regex]::Replace($existing, "(?s)\r?\n?$escapedBegin.*?$escapedEnd\r?\n?", "`r`n")
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine($beginMarker)
    [void]$builder.AppendLine('## Codex 历史会话自动归档')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("- 项目：$($project.Name)")
    [void]$builder.AppendLine("- 项目主目录：``$($project.PrimaryRoot)``")
    [void]$builder.AppendLine("- 会话数：$($project.Threads.Count)")
    [void]$builder.AppendLine('- 范围：用户消息、助手过程说明和最终答复；不含系统提示、内部推理、命令及工具输出。')
    [void]$builder.AppendLine('- 安全：疑似密码、令牌、Cookie、密钥和私钥已自动隐藏。')

    foreach ($thread in ($project.Threads | Sort-Object CreatedAt, Id)) {
        $created = [DateTimeOffset]::FromUnixTimeSeconds($thread.CreatedAt).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss zzz')
        [void]$builder.AppendLine()
        [void]$builder.AppendLine('---')
        [void]$builder.AppendLine()
        [void]$builder.AppendLine("### $(Protect-Secrets $thread.Title)")
        [void]$builder.AppendLine()
        [void]$builder.AppendLine("- 会话 ID：``$($thread.Id)``")
        [void]$builder.AppendLine("- 创建时间：$created")
        [void]$builder.AppendLine("- 当时工作目录：``$(Protect-Secrets $thread.Cwd)``")
        [void]$builder.AppendLine("- 归类依据：$($thread.MatchMethod)")

        $idSql = Sql-Literal $thread.Id
        $items = Invoke-SqliteJson $historyDb "SELECT item_type, item_json, created_at_ms, rollout_ordinal FROM thread_items WHERE thread_id=$idSql AND item_type IN ('userMessage','agentMessage') ORDER BY rollout_ordinal, created_at_ms, item_id;"
        foreach ($item in $items) {
            $obj = ([string]$item.item_json) | ConvertFrom-Json
            if ($item.item_type -eq 'userMessage') {
                $parts = [System.Collections.Generic.List[string]]::new()
                foreach ($content in @($obj.content)) {
                    if ($content.type -eq 'text' -and $content.text) { $parts.Add([string]$content.text) }
                    elseif ($content.type -eq 'localImage') {
                        $imagePath = if ($content.path) { [string]$content.path } elseif ($content.imagePath) { [string]$content.imagePath } else { '[路径未记录]' }
                        $parts.Add("[图片附件：$imagePath]")
                    }
                }
                $message = ($parts -join "`r`n").Trim()
                $role = '用户'
            } else {
                $message = ([string]$obj.text).Trim()
                $role = if ($obj.phase -eq 'final_answer') { '助手（最终答复）' } else { '助手（过程说明）' }
            }
            if ($message) {
                $totalMessages++
                [void]$builder.AppendLine()
                [void]$builder.AppendLine("#### $role")
                [void]$builder.AppendLine()
                [void]$builder.AppendLine((Protect-Secrets $message))
            }
        }
    }
    [void]$builder.AppendLine()
    [void]$builder.AppendLine($endMarker)
    $combined = $manual.TrimEnd() + "`r`n`r`n" + $builder.ToString().TrimEnd() + "`r`n"
    [System.IO.File]::WriteAllText($archivePath, $combined, $utf8)
    $writtenProjects++
}

# 无法可靠匹配到项目的历史会话集中写入 E 盘根临时总表，保留完整可检索正文。
$temporaryExisting = if (Test-Path -LiteralPath $temporaryArchivePath -PathType Leaf) { [IO.File]::ReadAllText($temporaryArchivePath) } else { '# 临时会话记录`r`n' }
$temporaryManual = [regex]::Replace($temporaryExisting, "(?s)\r?\n?$( [regex]::Escape($temporaryBeginMarker) ).*?$( [regex]::Escape($temporaryEndMarker) )\r?\n?", "`r`n")
$temporaryBuilder = [System.Text.StringBuilder]::new()
[void]$temporaryBuilder.AppendLine($temporaryBeginMarker)
[void]$temporaryBuilder.AppendLine('## 未归入项目的 Codex/ChatGPT 历史会话')
[void]$temporaryBuilder.AppendLine()
[void]$temporaryBuilder.AppendLine("- 会话数：$($unmapped.Count)")
[void]$temporaryBuilder.AppendLine('- 说明：这些会话没有可靠的项目绑定目录或唯一项目关键词，因此集中保存于此；后续若确认归属，应迁移到对应项目的 `会话记录.md`。')
[void]$temporaryBuilder.AppendLine('- 检索：优先按会话 ID、日期、标题或当时工作目录搜索；每个会话下保留用户消息和助手过程/最终答复。')
[void]$temporaryBuilder.AppendLine('- 安全：不保存系统提示、内部推理、命令/工具输出；疑似密码、令牌、Cookie、密钥和私钥已隐藏。')
[void]$temporaryBuilder.AppendLine()
[void]$temporaryBuilder.AppendLine('## 快速索引')
[void]$temporaryBuilder.AppendLine()
[void]$temporaryBuilder.AppendLine('| 日期 | 会话 ID | 标题 | 当时工作目录 |')
[void]$temporaryBuilder.AppendLine('|---|---|---|---|')
foreach ($thread in ($unmapped | Sort-Object created_at, id)) {
    $created = [DateTimeOffset]::FromUnixTimeSeconds([long]$thread.created_at).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
    [void]$temporaryBuilder.AppendLine("| $created | ``$($thread.id)`` | $(Protect-Secrets ([string]$thread.title)) | ``$(Protect-Secrets ([string]$thread.cwd))`` |")
}
foreach ($thread in ($unmapped | Sort-Object created_at, id)) {
    $created = [DateTimeOffset]::FromUnixTimeSeconds([long]$thread.created_at).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss zzz')
    [void]$temporaryBuilder.AppendLine()
    [void]$temporaryBuilder.AppendLine('---')
    [void]$temporaryBuilder.AppendLine()
    [void]$temporaryBuilder.AppendLine("### $(Protect-Secrets ([string]$thread.title))")
    [void]$temporaryBuilder.AppendLine()
    [void]$temporaryBuilder.AppendLine("- 会话 ID：``$($thread.id)``")
    [void]$temporaryBuilder.AppendLine("- 创建时间：$created")
    [void]$temporaryBuilder.AppendLine("- 当时工作目录：``$(Protect-Secrets ([string]$thread.cwd))``")
    [void]$temporaryBuilder.AppendLine('- 归属状态：待确认；当前未写入任何具体项目。')
    $idSql = Sql-Literal ([string]$thread.id)
    $items = Invoke-SqliteJson $historyDb "SELECT item_type, item_json, created_at_ms, rollout_ordinal FROM thread_items WHERE thread_id=$idSql AND item_type IN ('userMessage','agentMessage') ORDER BY rollout_ordinal, created_at_ms, item_id;"
    foreach ($item in $items) {
        $obj = ([string]$item.item_json) | ConvertFrom-Json
        if ($item.item_type -eq 'userMessage') {
            $parts = [System.Collections.Generic.List[string]]::new()
            foreach ($content in @($obj.content)) {
                if ($content.type -eq 'text' -and $content.text) { $parts.Add([string]$content.text) }
                elseif ($content.type -eq 'localImage') {
                    $imagePath = if ($content.path) { [string]$content.path } elseif ($content.imagePath) { [string]$content.imagePath } else { '[路径未记录]' }
                    $parts.Add("[图片附件：$imagePath]")
                }
            }
            $message = ($parts -join "`r`n").Trim()
            $role = '用户'
        } else {
            $message = ([string]$obj.text).Trim()
            $role = if ($obj.phase -eq 'final_answer') { '助手（最终答复）' } else { '助手（过程说明）' }
        }
        if ($message) {
            $totalMessages++
            [void]$temporaryBuilder.AppendLine()
            [void]$temporaryBuilder.AppendLine("#### $role")
            [void]$temporaryBuilder.AppendLine()
            [void]$temporaryBuilder.AppendLine((Protect-Secrets $message))
        }
    }
}
[void]$temporaryBuilder.AppendLine()
[void]$temporaryBuilder.AppendLine($temporaryEndMarker)
$temporaryCombined = $temporaryManual.TrimEnd() + "`r`n`r`n" + $temporaryBuilder.ToString().TrimEnd() + "`r`n"
[IO.File]::WriteAllText($temporaryArchivePath, $temporaryCombined, $utf8)

$report = [System.Text.StringBuilder]::new()
[void]$report.AppendLine('# Codex 会话归档报告')
[void]$report.AppendLine()
[void]$report.AppendLine("- 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
[void]$report.AppendLine("- 数据库会话总数：$($threadRows.Count)")
[void]$report.AppendLine("- 已归档会话数：$(($projects.Values | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum)")
[void]$report.AppendLine("- 待确认会话数：$($unmapped.Count)")
[void]$report.AppendLine("- 待确认会话完整内容：``$temporaryArchivePath``")
[void]$report.AppendLine("- 已归档消息数：$totalMessages")
[void]$report.AppendLine()
[void]$report.AppendLine('## 各项目结果')
[void]$report.AppendLine()
[void]$report.AppendLine('| 项目 | 主目录 | 会话数 |')
[void]$report.AppendLine('|---|---|---:|')
foreach ($project in ($projects.Values | Sort-Object Name)) {
    [void]$report.AppendLine("| $($project.Name) | ``$($project.PrimaryRoot)`` | $($project.Threads.Count) |")
}
[void]$report.AppendLine()
[void]$report.AppendLine('## 待确认归属')
[void]$report.AppendLine()
[void]$report.AppendLine('这些会话没有可靠的项目目录或唯一项目关键词，因此没有擅自写入任何项目。')
[void]$report.AppendLine()
foreach ($thread in $unmapped) {
    $created = [DateTimeOffset]::FromUnixTimeSeconds([long]$thread.created_at).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
    [void]$report.AppendLine("- $created｜``$($thread.id)``｜$(Protect-Secrets ([string]$thread.title))｜``$(Protect-Secrets ([string]$thread.cwd))``")
}
[System.IO.File]::WriteAllText($reportPath, $report.ToString(), $utf8)

[pscustomobject]@{
    Projects = $writtenProjects
    TotalThreads = $threadRows.Count
    ArchivedThreads = (($projects.Values | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum)
    UnmappedThreads = $unmapped.Count
    ArchivedMessages = $totalMessages
    Report = $reportPath
} | ConvertTo-Json
