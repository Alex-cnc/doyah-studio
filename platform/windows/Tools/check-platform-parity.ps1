# Doyah Studio · Windows 侧闸门 ⑤ 平台等价矩阵（platform/windows/Tools/check-platform-parity.ps1）
#
# 对应 §8.3 的「多平台等价矩阵」：判据复用共享脚本 `Scripts/gen-platform-parity.py --check`
# （列由台账 Docs/平台实现状态.json 决定，Windows 列已并入 SRS §10.10）。
#
# 第二道判据是**本侧自己的义务**（§8.5.6-2）：Windows 列必须如实 ——
# 本侧未开工（platform/windows/ 下没有工程文件）时，"全 ⬜ / 台账里没有 overrides"是唯一可接受状态；
# 未开工却登记了 overrides（哪怕是 🟡）= 为"看起来在推进"改状态，本脚本判红。
#
# 第三道判据（S-7a，2026-10-07 扩条）：**连接面的界面形态** ——
# 连接表单 / 连接列表只许在弹层件（`App/src/shell/ConnectionDialog.vue`）里，
# 数据库视图主区的模板区不得再内联铺开，且弹层由命令清单里的「新建连接 / 编辑连接」驱动。
# 由头 = 人类主人 2026-10-07 实测原话（详见判据本体的注释）。**本判据只扩条，未放宽既有两条。**
#
# 退出码：0 = 通过 / 1 = 判红 / 2 = 跳过

param(
  [string]$RepoRoot = '',
  [switch]$SelfTest
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')

# ── 判据本体：Windows 列的如实性（主路径与 -SelfTest 读**同一份**）─────────────────────
#
# 返回一组「判红理由」（空数组 = 如实）。三条口径：
#   ① 台账必须在盘上、必须有 platforms.windows 与 label / role / owner；
#   ② **工程已建** = platform/windows 下有工程文件。**.csproj 不是唯一形态**：
#      2026-09-28 开工令换栈后本侧是 Rust/Tauri（`Cargo.toml`），只认 `.csproj` 会把
#      已经建起来的工程当成「未开工」—— 判据于是**陈述了假事实**（本项第 28 轮实测）。
#   ③ 未建工程时**全 ⬜（无 overrides）是唯一可接受状态**；已建工程时 overrides 由台账决定，
#      与表格是否一致交给上面的共享判据 `--check`。
function Get-DoyahWindowsColumnVerdict {
  param(
    [AllowNull()]$Ledger,
    [Parameter(Mandatory = $true)][int]$ProjectFileCount
  )
  $reasons = New-Object System.Collections.ArrayList
  if (-not $Ledger) {
    [void]$reasons.Add('台账不在盘上或解析不出（Docs/平台实现状态.json）')
    return $reasons
  }
  if (-not $Ledger.platforms -or -not $Ledger.platforms.windows) {
    [void]$reasons.Add('台账缺 platforms.windows 键（契约侧 L-26 的形状）')
    return $reasons
  }
  $windows = $Ledger.platforms.windows
  foreach ($field in @('label', 'role', 'owner')) {
    if (-not $windows.$field) { [void]$reasons.Add(('台账 platforms.windows 缺 {0}' -f $field)) }
  }
  $overrideCount = @($windows.overrides.PSObject.Properties).Count
  if ($ProjectFileCount -eq 0 -and $overrideCount -gt 0) {
    [void]$reasons.Add(('未开工却登记了 {0} 条 overrides ⇒ 不如实（§8.5.6-2：未开工时全 ⬜ 是唯一可接受状态）' -f $overrideCount))
  }
  return $reasons
}

# ── 判据自测（负例）──────────────────────────────────────────────────────────────
#
# 每一条负例都在证「判据真的抓得到它声称抓的东西」；两条正对照保证它**不误伤如实**。
# 全部在内存里造台账（`ConvertFrom-Json`），**盘上一个字节不动**。
function Invoke-DoyahParitySelfTest {
  $cases = @(
    @{ Name = '负例·未开工却登记 overrides'; Ledger = '{"platforms":{"windows":{"label":"Windows","role":"r","owner":"o","overrides":{"FR-X":"done"}}}}'; Files = 0; WantReasons = $true; MustMention = '未开工' },
    @{ Name = '负例·台账缺 platforms.windows'; Ledger = '{"platforms":{"macos":{"label":"macOS"}}}'; Files = 0; WantReasons = $true; MustMention = 'platforms.windows' },
    @{ Name = '负例·台账缺 owner'; Ledger = '{"platforms":{"windows":{"label":"Windows","role":"r"}}}'; Files = 0; WantReasons = $true; MustMention = 'owner' },
    @{ Name = '负例·台账是 null'; Ledger = $null; Files = 0; WantReasons = $true; MustMention = '台账' },
    @{ Name = '正对照·未开工且无 overrides'; Ledger = '{"platforms":{"windows":{"label":"Windows","role":"r","owner":"o","overrides":{}}}}'; Files = 0; WantReasons = $false; MustMention = '' },
    @{ Name = '正对照·工程已建（Cargo.toml）且登记 overrides'; Ledger = '{"platforms":{"windows":{"label":"Windows","role":"r","owner":"o","overrides":{"FR-X":"done"}}}}'; Files = 1; WantReasons = $false; MustMention = '' }
  )
  $failed = 0
  foreach ($case in $cases) {
    $ledger = $null
    if ($case.Ledger) { $ledger = ConvertFrom-Json $case.Ledger }
    $reasons = @(Get-DoyahWindowsColumnVerdict -Ledger $ledger -ProjectFileCount $case.Files)
    $has = ($reasons.Count -gt 0)
    if ($has -ne $case.WantReasons) {
      Write-DoyahFail (('{0}：期望「{1}」，实际判红数组 = [{2}]' -f $case.Name, $(if ($case.WantReasons) { '有理由' } else { '无理由' }), ($reasons -join ' / ')))
      $failed += 1
      continue
    }
    if ($case.WantReasons -and $case.MustMention) {
      $joined = ($reasons -join ' / ')
      if ($joined -notmatch [regex]::Escape($case.MustMention)) {
        Write-DoyahFail (('{0}：判红理由里没点名「{1}」（实际：{2}）' -f $case.Name, $case.MustMention, $joined))
        $failed += 1
        continue
      }
    }
    Write-Host ('    ✅ {0}' -f $case.Name)
  }
  $total = $cases.Count
  Write-Host ('    判据自测：{0}/{1}' -f ($total - $failed), $total)
  if ($failed -gt 0) { return 1 }
  return 0
}

# ── 判据本体（第二条）：连接面的**界面形态**（S-7a，2026-10-07）─────────────────────
#
# 由头（人类主人 2026-10-07 实测原话）：**「数据库客户端的连接信息怎么直接在界面呈现而不是
# 通过菜单弹出对话框呢？」** —— 连接表单与连接列表内联铺在数据库视图的主区里，而对侧
# （macOS）是 `App/Views/ConnectionSettingsSheet.swift` 那种**弹层**形态
# （呈现点 `App/Views/MainWindow.swift:256` 的 `ConnectionSettingsSheet()`）。
#
# 三条口径（缺一即判红）：
#   ① `views/DatabaseView.vue` 的**主内容模板区**不得出现连接表单节点 / 连接列表节点
#      （判红一律点名 `views/DatabaseView.vue:行号`）；
#   ② `shell/ConnectionDialog.vue` 必须在盘上，且**承载**这些节点 —— 少了就是"把连接面
#      **删掉**了，不是搬走（删掉也能让 ① 变绿，那是假绿）；
#   ③ `shell/commands.ts` 里「新建连接」「编辑连接」两条命令都在（弹层由**命令清单**驱动）。
#      这两条命令自身的三者对账（id 唯一 / scope 说得清 / 视图名认识）由
#      `App/src/shell/commands.test.ts` 判，这里只判"在不在"（不重造一份对账）。
#
# 连接面节点 = 模板里的类名（`<style>` 区与脚本区**不算**：搬走时 CSS 可能留在原处）。
$ConnectionSurfaceMarkers = @(
  'class="db__bar"',   # 连接表单根（<form>）
  'db__field--check',  # 连接表单的「记住口令」勾选
  'db__conn-fold',     # 连接列表（可折叠段）
  'db__conn-group',    # 连接列表分组
  'db__conn-main',     # 连接列表行
  'db__conn-del'       # 连接列表行的删除按钮
)

# 弹层由命令清单驱动：这两条 id 必须在命令清单里（清单 = 唯一出处）
$ConnectionSurfaceCommandIds = @('database.newConnection', 'database.editConnection')

# 顶层 `<template>` 区 = 从行首 `<template` 到行首 `</template>`（内层模板都带缩进，不误伤）。
function Get-DoyahTemplateLineRange {
  param([Parameter(Mandatory = $true)][string]$Text)
  $lines = $Text -split "`n"
  $start = -1
  $end = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^<template(\s|>)') { $start = $i; break }
  }
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match '^</template>') { $end = $i; break }
  }
  if ($start -lt 0 -or $end -lt $start) { return $null }
  return @{ Start = $start; End = $end; Lines = $lines }
}

# 返回一组「判红理由」（空数组 = 连接面只在弹层里、且由命令清单驱动）。主路径与自测**读同一份**。
function Get-DoyahConnectionSurfaceVerdict {
  param([Parameter(Mandatory = $true)][string]$AppSrcDir)

  $reasons = New-Object System.Collections.ArrayList
  $viewPath = Join-Path $AppSrcDir 'views/DatabaseView.vue'
  $dialogPath = Join-Path $AppSrcDir 'shell/ConnectionDialog.vue'
  $commandsPath = Join-Path $AppSrcDir 'shell/commands.ts'

  if (-not (Test-Path $viewPath)) {
    [void]$reasons.Add('数据库视图不在盘上：views/DatabaseView.vue')
    return $reasons
  }
  if (-not (Test-Path $commandsPath)) {
    [void]$reasons.Add('命令清单不在盘上：shell/commands.ts（唯一出处）')
    return $reasons
  }

  # ① 主内容模板区不得出现连接表单 / 连接列表节点（逐条点名 文件:行号）
  $viewText = Read-DoyahTextFile -Path $viewPath
  $range = Get-DoyahTemplateLineRange -Text $viewText
  if (-not $range) {
    [void]$reasons.Add('views/DatabaseView.vue 找不到顶层 <template> 区（判据面为空 ≠ 通过）')
  }
  else {
    for ($i = $range.Start; $i -le $range.End; $i++) {
      foreach ($marker in $ConnectionSurfaceMarkers) {
        if ($range.Lines[$i].Contains($marker)) {
          [void]$reasons.Add(('主区里仍有连接面节点「{0}」：views/DatabaseView.vue:{1} —— 连接表单 / 连接列表只许在弹层里' -f $marker, ($i + 1)))
        }
      }
    }
  }

  # ② 弹层件必须在盘上，且承载这些节点（删掉 ≠ 搬走）
  if (-not (Test-Path $dialogPath)) {
    [void]$reasons.Add('连接弹层件不在盘上：shell/ConnectionDialog.vue（连接面的落点；没有它就没搬走）')
  }
  else {
    $dialogText = Read-DoyahTextFile -Path $dialogPath
    if (-not $dialogText.Contains('defineModel')) {
      [void]$reasons.Add('弹层件不是"承载原表单"的形态：shell/ConnectionDialog.vue 里没有 defineModel（表单状态仍是持有方两向绑定的）')
    }
    foreach ($marker in $ConnectionSurfaceMarkers) {
      if (-not $dialogText.Contains($marker)) {
        [void]$reasons.Add(('弹层件里缺连接面节点「{0}」：shell/ConnectionDialog.vue —— 那是把连接面**删掉**了，不是搬走' -f $marker))
      }
    }
  }

  # ③ 弹层由命令清单驱动：两条菜单入口都在
  $commandsText = Read-DoyahTextFile -Path $commandsPath
  foreach ($id in $ConnectionSurfaceCommandIds) {
    if ($commandsText -notmatch ("id:\s*'" + [regex]::Escape($id) + "'")) {
      [void]$reasons.Add(('命令清单里没有「{0}」（shell/commands.ts）—— 弹层没有菜单入口（清单 = 唯一出处）' -f $id))
    }
  }
  return $reasons
}

# ── 判据自测（固定夹具，**全在临时目录里**，盘上一个字节不动）───────────────────────
#
# 负例 4 / 正对照 1：每条负例都在证「判据真的抓得到它声称抓的东西」，正对照证它**不误伤**。
function Invoke-DoyahConnectionSurfaceSelfTest {
  $allMarkers = $ConnectionSurfaceMarkers
  $surfaceLines = ($allMarkers | ForEach-Object { '    <div class="' + ($_.TrimStart('class="').TrimEnd('"')) + '"></div>' }) -join "`n"

  $cases = @(
    @{ Name = '正对照·连接面已在弹层里'; View = '    <p>对象树</p>'; Dialog = ('  <script setup>' + "`n" + '    const form = defineModel()' + "`n" + '  </script>' + "`n" + '  <template>' + "`n" + $surfaceLines + "`n" + '  </template>'); Commands = "  { id: 'database.newConnection' }," + "`n" + "  { id: 'database.editConnection' },"; WantReasons = $false; MustMention = '' },
    @{ Name = '负例·连接表单节点被搬回主区'; View = ('    <form class="db__bar"></form>' + "`n" + '    <p>对象树</p>'); Dialog = (($ConnectionSurfaceMarkers | ForEach-Object { '    <div class="' + ($_.TrimStart('class="').TrimEnd('"')) + '"></div>' }) -join "`n" + "`n" + '    const form = defineModel()'); Commands = "  { id: 'database.newConnection' }," + "`n" + "  { id: 'database.editConnection' },"; WantReasons = $true; MustMention = 'views/DatabaseView.vue:' },
    @{ Name = '负例·弹层件不在盘上'; View = '    <p>对象树</p>'; Dialog = $null; Commands = "  { id: 'database.newConnection' }," + "`n" + "  { id: 'database.editConnection' },"; WantReasons = $true; MustMention = 'ConnectionDialog.vue' },
    @{ Name = '负例·弹层里少了连接列表行（删掉 ≠ 搬走）'; View = '    <p>对象树</p>'; Dialog = (($allMarkers | Where-Object { $_ -ne 'db__conn-main' } | ForEach-Object { '    <div class="' + ($_.TrimStart('class="').TrimEnd('"')) + '"></div>' }) -join "`n" + "`n" + '    const form = defineModel()'); Commands = "  { id: 'database.newConnection' }," + "`n" + "  { id: 'database.editConnection' },"; WantReasons = $true; MustMention = 'db__conn-main' },
    @{ Name = '负例·命令清单缺「编辑连接」'; View = '    <p>对象树</p>'; Dialog = (($allMarkers | ForEach-Object { '    <div class="' + ($_.TrimStart('class="').TrimEnd('"')) + '"></div>' }) -join "`n" + "`n" + '    const form = defineModel()'); Commands = "  { id: 'database.newConnection' },"; WantReasons = $true; MustMention = 'database.editConnection' }
  )

  $failed = 0
  $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('doyah-conn-surface-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  try {
    foreach ($case in $cases) {
      $src = Join-Path $tmpRoot ([guid]::NewGuid().ToString('N').Substring(0, 8))
      $views = Join-Path $src 'views'
      $shell = Join-Path $src 'shell'
      New-Item -ItemType Directory -Path $views -Force | Out-Null
      New-Item -ItemType Directory -Path $shell -Force | Out-Null
      [System.IO.File]::WriteAllText((Join-Path $views 'DatabaseView.vue'), ("<script setup lang=`"ts`">`n</script>`n`n<template>`n" + $case.View + "`n</template>`n"), [System.Text.UTF8Encoding]::new($false))
      [System.IO.File]::WriteAllText((Join-Path $shell 'commands.ts'), $case.Commands, [System.Text.UTF8Encoding]::new($false))
      if ($case.Dialog) {
        [System.IO.File]::WriteAllText((Join-Path $shell 'ConnectionDialog.vue'), ("<script setup lang=`"ts`">`n" + $case.Dialog + "`n"), [System.Text.UTF8Encoding]::new($false))
      }
      $reasons = @(Get-DoyahConnectionSurfaceVerdict -AppSrcDir $src)
      $has = ($reasons.Count -gt 0)
      if ($has -ne $case.WantReasons) {
        Write-DoyahFail (('{0}：期望「{1}」，实际判红数组 = [{2}]' -f $case.Name, $(if ($case.WantReasons) { '有理由' } else { '无理由' }), ($reasons -join ' / ')))
        $failed += 1
        continue
      }
      if ($case.WantReasons -and $case.MustMention) {
        $joined = ($reasons -join ' / ')
        if ($joined -notmatch [regex]::Escape($case.MustMention)) {
          Write-DoyahFail (('{0}：判红理由里没点名「{1}」（实际：{2}）' -f $case.Name, $case.MustMention, $joined))
          $failed += 1
          continue
        }
      }
      Write-Host ('    ✅ {0}' -f $case.Name)
    }
  }
  finally {
    if (Test-Path $tmpRoot) { Remove-Item -Path $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue }
  }
  $total = $cases.Count
  Write-Host ('    判据自测：{0}/{1}' -f ($total - $failed), $total)
  if ($failed -gt 0) { return 1 }
  return 0
}

if ($SelfTest) {
  Write-Host '== ⑤ 平台等价矩阵 · 判据自测（负例 4 / 正对照 2 + 连接面形态 负例 4 / 正对照 1）'
  $rc = 0
  if ((Invoke-DoyahParitySelfTest) -ne 0) { $rc = 1 }
  if ((Invoke-DoyahConnectionSurfaceSelfTest) -ne 0) { $rc = 1 }
  exit $rc
}

if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

Write-Host ("== ⑤ 平台等价矩阵与 Windows 列如实性（{0}）" -f $RepoRoot)

$python = Find-DoyahPython
if (-not $python) {
  Write-DoyahFail "找不到可用的 Python 3（判据在 Scripts/gen-platform-parity.py）"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$failed = $false

# ── 判据自己的证据（每轮真跑）：负例 4 / 正对照 2 ─────────────────────────────────
Write-Host "  ── 判据自测（固定夹具，全部在内存里造台账）"
if ((Invoke-DoyahParitySelfTest) -ne 0) {
  Write-DoyahFail "判据自测未通过 ⇒ 本判据自己的证据不成立"
  $failed = $true
}

$rc = Invoke-DoyahSharedGate -RepoRoot $RepoRoot -Python $python -RelativeScript 'Scripts/gen-platform-parity.py' -Arguments @('--check')
if ($rc -ne 0) {
  Write-DoyahFail ("等价矩阵判据报红（退出码 {0}）：Windows 列与台账不一致 / 表格被手工改过" -f $rc)
  $failed = $true
}

# ── 第二道：本侧如实性（§8.5.6-2）─────────────────────────────────────────────
$ledgerPath = Join-Path $RepoRoot 'Docs\平台实现状态.json'
if (-not (Test-Path $ledgerPath)) {
  Write-DoyahFail ("台账不在盘上：Docs/平台实现状态.json（Windows 列的唯一真相来源）")
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$ledger = ConvertFrom-Json (Read-DoyahTextFile -Path $ledgerPath)

# 工程已建 = 有 `.csproj`（旧栈）**或** `Cargo.toml`（现栈：Rust/Tauri，2026-09-28 开工令）。
# 只认 `.csproj` 会把已经建起来的工程报成「未开工」—— 判据陈述假事实（第 28 轮实测）。
$windowsDir = Join-Path $RepoRoot 'platform/windows'
$csprojFiles = @()
if (Test-Path $windowsDir) {
  $csprojFiles = @(Get-ChildItem -Path $windowsDir -Filter '*.csproj' -Recurse -File -ErrorAction SilentlyContinue)
}
$hasCargo = Test-Path (Join-Path $windowsDir 'Cargo.toml')
$projectCount = $csprojFiles.Count
if ($hasCargo) { $projectCount += 1 }

if ($hasCargo) {
  Write-Host "    本侧形态：platform/windows/Cargo.toml 在盘上（Rust/Tauri 现栈）⇒ 工程已建，状态一律从台账改、改完重生成 §10.10"
}
elseif ($csprojFiles.Count -gt 0) {
  Write-Host ("    本侧形态：platform/windows/ 下有 {0} 个 .csproj ⇒ 工程已建，状态一律从台账改、改完重生成 §10.10" -f $csprojFiles.Count)
}
else {
  Write-Host "    本侧形态：platform/windows/ 下既没有 .csproj 也没有 Cargo.toml（工程未建，§8.5.7 ⬜ 未开工）"
}

$overrideCount = 0
if ($ledger.platforms -and $ledger.platforms.windows) {
  $overrideCount = @($ledger.platforms.windows.overrides.PSObject.Properties).Count
}
Write-Host ("    台账 overrides：{0} 条" -f $overrideCount)

foreach ($reason in @(Get-DoyahWindowsColumnVerdict -Ledger $ledger -ProjectFileCount $projectCount)) {
  Write-DoyahFail $reason
  $failed = $true
}
if (-not $failed) {
  Write-DoyahPass ("Windows 列如实：台账无缺项 · 工程已建={0} · overrides={1} 条（表格一致性由 --check 判据覆盖）" -f [bool]$projectCount, $overrideCount)
}

# ── 第三道：连接面的界面形态（S-7a：内联 ⇒ 弹层 + 菜单入口）─────────────────────────
Write-Host "  ── 连接面形态自测（固定夹具，全部在临时目录里；负例 4 / 正对照 1）"
if ((Invoke-DoyahConnectionSurfaceSelfTest) -ne 0) {
  Write-DoyahFail "连接面形态判据自测未通过 ⇒ 本判据自己的证据不成立"
  $failed = $true
}

$appSrcDir = Join-Path $RepoRoot 'platform\windows\App\src'
$surfaceReasons = @(Get-DoyahConnectionSurfaceVerdict -AppSrcDir $appSrcDir)
foreach ($reason in $surfaceReasons) {
  Write-DoyahFail $reason
  $failed = $true
}
if ($surfaceReasons.Count -eq 0) {
  Write-DoyahPass "连接面形态如实：主内容模板区无连接表单 / 连接列表节点 · 弹层件 shell/ConnectionDialog.vue 承载它们 · 命令清单有「新建连接 / 编辑连接」两条菜单入口"
}

if ($failed) {
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

Write-DoyahResult -Status PASS -Code 0
exit 0
