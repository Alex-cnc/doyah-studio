# Doyah Studio · Windows 侧闸门：结果网格压力基准可复跑（platform/windows/Tools/check-grid-bench.ps1）
#
# 由头（§8.5.6-3 的开工令口径）：**Studio 开工后第一件事（不是写功能）= 结果集网格压力基准**
# —— 40 万行 × 20 列的滚动帧率 / 内存 / 排序筛选延迟，三选一实现，「过了再铺功能」。
# 本脚本 = 那份口径的**机械形式**（本侧自有判据；不重写对侧 `Scripts/`）：
#   ① 用 cargo 跑 `grid-bench`（闸门用缩小规模 4 万行 × 20 列，保证快；全量 40 万行读数落在 §8.5.7）；
#   ② 断言读数齐全、可解析（**空跑不许通过** —— 没有 GRID_BENCH 行即判红）；
#   ③ 断言「排序置换长度 == 行数」与 `RESULT: PASS`（排序不是半截的、基准是跑完的）。
# 说明：本项只判**数据侧**（Rust）可复跑；前端滚动帧率是无头浏览器读数（见 Bench/grid/README.md），
# 不接进闸门（依赖浏览器，脆）—— 这条边界如实写在这里。
#
# 退出码：0 = 通过 / 1 = 判红 / 2 = 跳过（缺 cargo / 缺工程）

param(
  [string]$RepoRoot = '',
  [int]$Rows = 40000,
  [int]$Cols = 20
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

# 判红与否只由退出码决定（cargo 的进度行走 stderr；PS 5.1 在 Stop 下会把它当终止错误 ⇒ 假红）
$ErrorActionPreference = 'Continue'

Write-Host ("== 结果网格压力基准（数据侧可复跑；{0} 行 × {1} 列）" -f $Rows, $Cols)

function Find-DoyahCargo {
  $cands = @()
  if ($env:CARGO_HOME) { $cands += (Join-Path $env:CARGO_HOME 'bin\cargo.exe') }
  if ($env:USERPROFILE) { $cands += (Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe') }
  $cands += 'C:\Users\Alex\.cargo\bin\cargo.exe'
  foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  $cmd = Get-Command cargo -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return ''
}

$windowsDir = Join-Path $RepoRoot 'platform/windows'
if (-not (Test-Path (Join-Path $windowsDir 'Cargo.toml'))) {
  Write-DoyahSkip -Text "结果网格压力基准" -Reason "Windows 侧 Rust 工程未建（platform/windows\Cargo.toml 不存在）"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}
$cargo = Find-DoyahCargo
if (-not $cargo) {
  Write-DoyahSkip -Text "结果网格压力基准" -Reason "本机找不到 cargo（§8.5.1 栈 = Rust）"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

Push-Location $windowsDir
$env:RUSTUP_AUTO_INSTALL = '0'
$out = & $cargo run --release --quiet --bin grid-bench -- --rows $Rows --cols $Cols --stdout-only 2>&1
$rc = $LASTEXITCODE
Pop-Location
$out | ForEach-Object { Write-Host ("    {0}" -f $_) }

if ($rc -ne 0) {
  Write-DoyahFail ("grid-bench 退出码 {0}" -f $rc)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$line = @($out | Where-Object { $_ -match '^GRID_BENCH ' })
if ($line.Count -ne 1) {
  Write-DoyahFail ("没有唯一的 GRID_BENCH 读出行（实际 {0} 行）—— 空跑不许通过" -f $line.Count)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}
$L = [string]$line[0]
$expect = @("rows=$Rows", "cols=$Cols", 'gen_ms=', 'sort_ms=', 'filter_ms=', 'range_ms=', 'window_ms=', 'cell200k_ms=', 'bytes=')
$missing = @($expect | Where-Object { $L -notmatch [regex]::Escape($_) })
if ($missing.Count -gt 0) {
  Write-DoyahFail ("读出行缺字段：{0}" -f ($missing -join '、'))
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}
$flat = ($out | Out-String)
if ($flat -notmatch ("置换长度核对 {0}" -f $Rows)) {
  Write-DoyahFail ("排序置换长度不等于行数 {0}（排序可能是半截的）" -f $Rows)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}
if ($flat -notmatch 'RESULT: PASS') {
  Write-DoyahFail "grid-bench 没有打印 RESULT: PASS"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

Write-DoyahPass ("数据侧基线可复跑：{0}" -f $L)
Write-DoyahResult -Status PASS -Code 0
exit 0
