# Doyah Studio · Windows 侧闸门 ⑥ 一条命令跑全（windows/Tools/verify-all.ps1）
#
# 对应 §8.3.1 的六项必需项与 §8.3.2「跳过 ≠ 通过」。用法：
#
#     powershell.exe windows\Tools\verify-all.ps1
#     powershell.exe windows\Tools\verify-all.ps1 -RequireAll      # 跳过即红（自我证明 / CI 用）
#     powershell.exe windows\Tools\verify-all.ps1 -Base HEAD~1     # 越界判据换基线（默认 origin/master）
#
# 收尾行如实写「N 项中跑 X / 跳过 Y / 失败 Z」并**逐条列出跳过的项** ——
# 等价物可以缺席，但缺席必须可见（§8.3.2）。
#
# 退出码：0 = 全绿 / 1 = 有红（含 -RequireAll 下的跳过）/ 2 = 没有任何一项被判红但存在跳过
#
# 第 22 轮：11 项 → 12 项（新增第 11 项 = `P-*` 平台差异登记两侧对账，接契约侧 L-45 的 `Scripts/check-p-parity.py`）
# 第 24 轮：12 项 → 13 项（① ② 两项按 2026-09-28 开工令换栈：cargo/前端；新增第 12 项 = 结果网格压力基准可复跑）
# 第 27 轮：13 项 → 14 项（新增第 13 项 = 生成物一致性「发布产物版本号一个值三处一致」，接契约侧 L-70 的 §8.3 闸门行）
# Windows 侧（fatfish）2026-10-02：14 项 → 15 项（新增第 14 项 = 路径归属判据，派活单 T-20261002-033：--mine windows + 清单 Scripts/path-ownership.json）

param(
  [switch]$RequireAll,
  [string]$Base = 'origin/master'
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
$RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir

$ran = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList
$failed = New-Object System.Collections.ArrayList
$total = 17

Write-Host "== Doyah Studio · Windows 侧闸门（§8.3.1 六项必需项 + §8.5.3 等价物）"
Write-Host ("   仓库：{0}" -f $RepoRoot)
$commit = ''
try { $commit = (& git -C $RepoRoot rev-parse --short HEAD 2>$null | Out-String).Trim() } catch { $commit = '' }
Write-Host ("   HEAD：{0}   平台：Windows / Windows PowerShell {1}" -f $commit, $PSVersionTable.PSVersion)
Write-Host ("   基线（越界判据）：{0}   RequireAll：{1}" -f $Base, [bool]$RequireAll)
Write-Host ""

function Invoke-ChildGate {
  param(
    [string]$Number,
    [string]$Name,
    [string]$File,
    [string]$SkipReason = '',
    [hashtable]$ChildArgs = $null
  )
  if (-not $ChildArgs) { $ChildArgs = @{} }
  Write-DoyahStep $Number $Name
  if ($SkipReason) {
    Write-DoyahSkip -Text $Name -Reason $SkipReason
    [void]$skipped.Add(("{0} —— {1}" -f $Name, $SkipReason))
    return
  }
  $child = Join-Path $ToolsDir $File
  if (-not (Test-Path $child)) {
    Write-DoyahFail ("子闸门不在盘上：{0}" -f $File)
    [void]$failed.Add(("{0} —— 子闸门缺失 {1}" -f $Name, $File))
    return
  }
  $splat = @{ RepoRoot = $RepoRoot }
  foreach ($key in $ChildArgs.Keys) { $splat[$key] = $ChildArgs[$key] }
  # 工作目录隔离（第 30 轮实测）：子闸门是**同进程**调用的（`& $child`），它 Push-Location 之后
  # 若在半路抛异常 / 提前 return，Pop-Location 就轮不到 ⇒ 后面所有项都在别人的目录里跑：
  # `Scripts/gen-platform-parity.py` 这类按仓根相对路径读三书的判据当场 FileNotFoundError
  # （报成「判据判红」），而 `check-platform-neutrality.py` 会**静默跳过三书、照样退出 0**（假绿）。
  $cwdBefore = (Get-Location).Path
  try {
    & $child @splat
    $rc = $LASTEXITCODE
  }
  catch {
    Write-DoyahFail ("子闸门抛异常：{0}" -f $_.Exception.Message)
    [void]$failed.Add(("{0} —— 抛异常：{1}" -f $Name, $_.Exception.Message))
    return
  }
  finally {
    if ((Get-Location).Path -ne $cwdBefore) {
      $leaked = (Get-Location).Path
      Set-Location -LiteralPath $cwdBefore
      Write-Host ("    ℹ️ 子闸门没有还原工作目录（跑在 {0}），本项已代为还原" -f $leaked)
    }
  }
  switch ($rc) {
    0 { Write-DoyahPass $Name; [void]$ran.Add($Name) }
    2 { [void]$skipped.Add($Name); }
    default {
      Write-DoyahFail ("子闸门退出码 {0}" -f $rc)
      [void]$failed.Add(("{0} —— 退出码 {1}" -f $Name, $rc))
    }
  }
}

# ── 1/14 闸门脚本自身编码（本机实测坑：无 BOM 的 UTF-8 中文脚本在 PS 5.1 下一行都不执行） ──
Write-DoyahStep "1/$total" "闸门脚本自身编码（UTF-8 带 BOM）"
$badEncoding = New-Object System.Collections.ArrayList
foreach ($file in @(Get-ChildItem -Path $ToolsDir -Filter '*.ps1' -File)) {
  if (-not (Test-DoyahUtf8Bom -Path $file.FullName)) { [void]$badEncoding.Add($file.Name) }
}
if ($badEncoding.Count -gt 0) {
  Write-DoyahFail ("以下脚本缺 UTF-8 BOM：{0} ⇒ PowerShell 5.1 会按 ANSI 解码中文、整脚本不执行（改法：另存为「UTF-8 带 BOM」）" -f ($badEncoding -join '、'))
  [void]$failed.Add("闸门脚本编码")
}
else {
  Write-DoyahPass "本目录 .ps1 全部 UTF-8 带 BOM"
  [void]$ran.Add("闸门脚本编码")
}

# ── 2/14 判据运行器（Python 3）──────────────────────────────────────────────
Write-DoyahStep "2/$total" "判据运行器：可用的 Python 3"
$python = Find-DoyahPython
$pythonSkipReason = ''
if ($python) {
  Write-DoyahPass ("Python：{0}" -f $python.Label)
  [void]$ran.Add("判据运行器（Python 3）")
}
else {
  $pythonSkipReason = "找不到可用 Python 3（Windows 上 python3 是应用商店占位符；判据 Scripts/*.py 需要真 Python）"
  Write-DoyahSkip -Text "判据运行器：Python 3" -Reason $pythonSkipReason
  [void]$skipped.Add(("判据运行器：Python 3 —— {0}" -f $pythonSkipReason))
}

# ── 3/14 ① 构建入口 ─────────────────────────────────────────────────────────
Invoke-ChildGate "3/$total" "① 构建入口（cargo build + 前端 vite build）" 'build.ps1'
# ── 4/14 ② 单测 ────────────────────────────────────────────────────────────
Invoke-ChildGate "4/$total" "② 单测（cargo test + vitest）" 'test.ps1'
# ── 5/14 领域层边界 ─────────────────────────────────────────────────────────
Invoke-ChildGate "5/$total" "领域层边界（GUI 不得进入领域层）" 'check-core-boundary.ps1'
# ── 6/14 ③ 文档计数与版本 ───────────────────────────────────────────────────
Invoke-ChildGate "6/$total" "③ 文档计数与版本（表格 / 派生数字 / 版本号）" 'check-doc-tables.ps1' -SkipReason $pythonSkipReason
# ── 7/14 设计令牌棘轮 ───────────────────────────────────────────────────────
Invoke-ChildGate "7/$total" "设计令牌棘轮（规则名对齐 + 取值单一来源 + Windows 侧棘轮）" 'check-design-tokens.ps1'
# ── 8/14 平台中立性 ─────────────────────────────────────────────────────────
Invoke-ChildGate "8/$total" "平台中立性（三书不得混入平台实现细节）" 'check-platform-neutrality.ps1' -SkipReason $pythonSkipReason
# ── 9/14 ④ 独占节越界 ───────────────────────────────────────────────────────
Invoke-ChildGate "9/$total" "④ 独占节越界（本侧 = windows）" 'check-exclusive-sections.ps1' -SkipReason $pythonSkipReason -ChildArgs @{ Base = $Base }
# ── 10/14 ⑤ 平台等价矩阵 ────────────────────────────────────────────────────
Invoke-ChildGate "10/$total" "⑤ 平台等价矩阵 + Windows 列如实性" 'check-platform-parity.ps1' -SkipReason $pythonSkipReason
# ── 11/14 ⑦ `P-*` 平台差异登记两侧对账（队列 L-45）──────────────────────────
Invoke-ChildGate "11/$total" "⑦ `P-*` 平台差异登记两侧对账（SRS §10.9 ↔ 概要设计 §4 + §8.5.5 已落条）" 'check-p-parity.ps1'
# ── 12/14 结果网格压力基准（§8.5.6-3 开工令的第一件事；数据侧可复跑）────────
Invoke-ChildGate "12/$total" "结果网格压力基准（数据侧可复跑：grid-bench）" 'check-grid-bench.ps1'
# ── 13/14 生成物一致性：发布产物版本号「一个值、三处逐字一致」（契约侧 L-70）────
Invoke-ChildGate "13/$total" "生成物一致性：发布产物版本号一个值三处一致（+ 与 mac 侧发布台账同源）" 'check-release-version.ps1'
# ── 14/15 路径归属（派单 T-20261002-033 的 Windows 侧那一项）──────────────────
# 清单 = 共享面 `Scripts/path-ownership.json`（**只有一份**，本侧只引用）；判据本体 =
# 共享面 `Scripts/check-path-ownership.py`（同一份，三仓同源）⇒ 本侧只做按本侧姿势传参。
Invoke-ChildGate "14/$total" "路径归属（一次改动不得落在对侧子树；共享面要登记理由）" 'check-path-ownership.ps1' -SkipReason $pythonSkipReason -ChildArgs @{ Base = $Base }
# ── 15/16 双语漏译棘轮（1.8 段出口「全部文案中英双语」的**可判形式**）──────────────
# 语言表只证明"**能**翻译"；"**有没有漏**"要靠扫描界面里直接写死的中文。
# 棘轮**只减不增**：新写的界面文案必须走语言表 `t(...)`。
Invoke-ChildGate "15/$total" "双语漏译棘轮（界面文案不得绕过语言表；基线只减不增）" 'check-untranslated.ps1' -SkipReason $pythonSkipReason

# ── 16/17 Vue 组合式 API 导入对账（防"空白页"复发）──────────────────────────────
# 2026-10-04 实测事故：App.vue 用了 computed 但没从 vue 导入 ⇒ **整个应用白屏**
# （Vue 挂载成功、根组件 setup 抛 ReferenceError、渲染成空注释）。
# tsc 不校验模板与 setup 里的未声明引用、vitest 不挂载组件 ⇒ 两道网都漏，只能文本对账。
Invoke-ChildGate "16/$total" "Vue 组合式 API 导入对账（用了 computed/ref/... 就必须从 vue 导入）" 'check-vue-imports.ps1'
# ── 17/17 ⑥ 一条命令跑全（本脚本自身）────────────────────────────────────────
Write-DoyahStep "17/$total" "⑥ 一条命令跑全（本脚本 = 该入口本身）"
Write-DoyahPass "本脚本即闭环入口；跳过的项已逐条列出（等价物可以缺席，缺席必须可见）"
[void]$ran.Add("⑥ 一条命令跑全")

# ── 收尾：如实报数 ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("== 收尾：{0} 项中跑 {1} / 跳过 {2} / 失败 {3}" -f $total, $ran.Count, $skipped.Count, $failed.Count)
if ($skipped.Count -gt 0) {
  Write-Host "   跳过的项（跳过不是「已通过」）："
  foreach ($item in $skipped) { Write-Host ("     · {0}" -f $item) }
}
if ($failed.Count -gt 0) {
  Write-Host "   失败的项："
  foreach ($item in $failed) { Write-Host ("     · {0}" -f $item) }
}
Write-Host "   平台不适用项的处置口径见 Docs/概要设计.md §8.3.2；本侧必需项清单见 §8.3.1；等价物登记见 §8.5.3"

if ($failed.Count -gt 0) {
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}
if ($RequireAll -and $skipped.Count -gt 0) {
  Write-DoyahFail ("-RequireAll：存在 {0} 项跳过 ⇒ 判红（跳过即红）" -f $skipped.Count)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}
if ($skipped.Count -gt 0) {
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}
Write-DoyahResult -Status PASS -Code 0
exit 0
