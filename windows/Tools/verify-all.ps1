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
$total = 12

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
  try {
    & $child @splat
    $rc = $LASTEXITCODE
  }
  catch {
    Write-DoyahFail ("子闸门抛异常：{0}" -f $_.Exception.Message)
    [void]$failed.Add(("{0} —— 抛异常：{1}" -f $Name, $_.Exception.Message))
    return
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

# ── 1/12 闸门脚本自身编码（本机实测坑：无 BOM 的 UTF-8 中文脚本在 PS 5.1 下一行都不执行） ──
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

# ── 2/12 判据运行器（Python 3）──────────────────────────────────────────────
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

# ── 3/12 ① 构建入口 ─────────────────────────────────────────────────────────
Invoke-ChildGate "3/$total" "① 构建入口（dotnet publish + 便携 zip）" 'build.ps1'
# ── 4/12 ② 单测 ────────────────────────────────────────────────────────────
Invoke-ChildGate "4/$total" "② 单测（dotnet test / xUnit）" 'test.ps1'
# ── 5/12 领域层边界 ─────────────────────────────────────────────────────────
Invoke-ChildGate "5/$total" "领域层边界（GUI 不得进入领域层）" 'check-core-boundary.ps1'
# ── 6/12 ③ 文档计数与版本 ───────────────────────────────────────────────────
Invoke-ChildGate "6/$total" "③ 文档计数与版本（表格 / 派生数字 / 版本号）" 'check-doc-tables.ps1' -SkipReason $pythonSkipReason
# ── 7/12 设计令牌棘轮 ───────────────────────────────────────────────────────
Invoke-ChildGate "7/$total" "设计令牌棘轮（规则名对齐 + 取值单一来源 + Windows 侧棘轮）" 'check-design-tokens.ps1'
# ── 8/12 平台中立性 ─────────────────────────────────────────────────────────
Invoke-ChildGate "8/$total" "平台中立性（三书不得混入平台实现细节）" 'check-platform-neutrality.ps1' -SkipReason $pythonSkipReason
# ── 9/12 ④ 独占节越界 ───────────────────────────────────────────────────────
Invoke-ChildGate "9/$total" "④ 独占节越界（本侧 = windows）" 'check-exclusive-sections.ps1' -SkipReason $pythonSkipReason -ChildArgs @{ Base = $Base }
# ── 10/12 ⑤ 平台等价矩阵 ────────────────────────────────────────────────────
Invoke-ChildGate "10/$total" "⑤ 平台等价矩阵 + Windows 列如实性" 'check-platform-parity.ps1' -SkipReason $pythonSkipReason
# ── 11/12 ⑦ `P-*` 平台差异登记两侧对账（队列 L-45）──────────────────────────
Invoke-ChildGate "11/$total" "⑦ `P-*` 平台差异登记两侧对账（SRS §10.9 ↔ 概要设计 §4 + §8.5.5 已落条）" 'check-p-parity.ps1'
# ── 12/12 ⑥ 一条命令跑全（本脚本自身）────────────────────────────────────────
Write-DoyahStep "12/$total" "⑥ 一条命令跑全（本脚本 = 该入口本身）"
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
