# Doyah Studio · Windows 侧闸门 ⑤ 平台等价矩阵（platform/windows/Tools/check-platform-parity.ps1）
#
# 对应 §8.3 的「多平台等价矩阵」：判据复用共享脚本 `Scripts/gen-platform-parity.py --check`
# （列由台账 Docs/平台实现状态.json 决定，Windows 列已并入 SRS §10.10）。
#
# 第二道判据是**本侧自己的义务**（§8.5.6-2）：Windows 列必须如实 ——
# 本侧未开工（platform/windows/ 下没有工程文件）时，"全 ⬜ / 台账里没有 overrides"是唯一可接受状态；
# 未开工却登记了 overrides（哪怕是 🟡）= 为"看起来在推进"改状态，本脚本判红。
#
# 退出码：0 = 通过 / 1 = 判红 / 2 = 跳过

param([string]$RepoRoot = '')

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

Write-Host ("== ⑤ 平台等价矩阵与 Windows 列如实性（{0}）" -f $RepoRoot)

$python = Find-DoyahPython
if (-not $python) {
  Write-DoyahFail "找不到可用的 Python 3（判据在 Scripts/gen-platform-parity.py）"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$failed = $false

$rc = Invoke-DoyahSharedGate -RepoRoot $RepoRoot -Python $python -RelativeScript 'Scripts/gen-platform-parity.py' -Arguments @('--check')
if ($rc -ne 0) {
  Write-DoyahFail ("等价矩阵判据报红（退出码 {0}）：Windows 列与台账不一致 / 表格被手工改过" -f $rc)
  $failed = $true
}

# ── 第二道：本侧如实性（§8.5.6-2）─────────────────────────────────────────────
$ledgerPath = Join-Path $RepoRoot 'Docs\平台实现状态.json'
if (-not (Test-Path $ledgerPath)) {
  Write-DoyahFail ("台账不在盘上：Docs\平台实现状态.json（Windows 列的唯一真相来源）")
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$ledger = ConvertFrom-Json (Read-DoyahTextFile -Path $ledgerPath)
if (-not $ledger.platforms -or -not $ledger.platforms.windows) {
  Write-DoyahFail "台账缺 platforms.windows 键（契约侧 L-26 的形状）"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$windows = $ledger.platforms.windows
$overrideCount = @($windows.overrides.PSObject.Properties).Count
foreach ($field in @('label', 'role', 'owner')) {
  if (-not $windows.$field) { Write-DoyahFail ("台账 platforms.windows 缺 {0}" -f $field); $failed = $true }
}

$windowsDir = Join-Path $RepoRoot 'platform/windows'
$projectFiles = @()
if (Test-Path $windowsDir) {
  $projectFiles = @(Get-ChildItem -Path $windowsDir -Filter '*.csproj' -Recurse -File -ErrorAction SilentlyContinue)
}

if ($projectFiles.Count -eq 0) {
  Write-Host "    本侧形态：platform/windows/ 下没有 .csproj（工程未建，§8.5.7 ⬜ 未开工）"
  if ($overrideCount -gt 0) {
    Write-DoyahFail ("未开工却登记了 {0} 条 overrides ⇒ 不如实（§8.5.6-2：未开工时全 ⬜ 是唯一可接受状态）" -f $overrideCount)
    $failed = $true
  }
  else {
    Write-DoyahPass ("Windows 列如实：台账无 overrides（default = {0}，即全 ⬜）" -f $ledger.default)
  }
}
else {
  Write-Host ("    本侧形态：platform/windows/ 下有 {0} 个 .csproj ⇒ 工程已建，状态一律从台账改、改完重生成 §10.10" -f $projectFiles.Count)
  Write-Host ("    台账 overrides：{0} 条（一致性已由上面的 --check 判据覆盖）" -f $overrideCount)
}

if ($failed) {
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

Write-DoyahResult -Status PASS -Code 0
exit 0
