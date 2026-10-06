# Doyah Studio · Windows 侧闸门 ④ 独占节越界（platform/windows/Tools/check-exclusive-sections.ps1）
#
# 对应 §8.3 的「独占节越界校验」（另一平台要求 = `Scripts/check-exclusive-sections.py --mine windows`）。
# 判据复用共享脚本，**不重写**。
#
# 两条实测坑（写死成默认值）：
#   ① 默认基线必须是 **origin/master**：合并对侧提交后、merge 还没提交时 `--base HEAD` 会
#      把对侧刚合进来的契约层改动整批算成"本侧越界"（实测 76 处假红）。
#   ② `--mine` 在本脚本里**显式传** windows，不依赖脚本的按平台推断（Windows 上推断也是 windows，
#      但显式写清楚，读日志的人不用去猜）。
#
# 退出码：0 = 通过 / 1 = 判红 / 2 = 跳过

param(
  [string]$RepoRoot = '',
  [string]$Base = 'origin/master',
  [switch]$SelfTest
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

$python = Find-DoyahPython
if (-not $python) {
  Write-DoyahFail "找不到可用的 Python 3（判据在 Scripts/check-exclusive-sections.py）"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

if ($SelfTest) {
  Write-Host "== ④ 独占节越界 · 判据自测（--self-test，期望 7/7）"
  $rc = Invoke-DoyahSharedGate -RepoRoot $RepoRoot -Python $python -RelativeScript 'Scripts/check-exclusive-sections.py' -Arguments @('--self-test')
  if ($rc -ne 0) {
    Write-DoyahFail ("判据自测未通过（退出码 {0}）—— 判据本身可疑，先别信它的绿" -f $rc)
    Write-DoyahResult -Status FAIL -Code 1
    exit 1
  }
  Write-DoyahPass "越界判据自测 7/7"
  Write-DoyahResult -Status PASS -Code 0
  exit 0
}

Write-Host ("== ④ 独占节越界（本侧 = windows；基线 = {0}）" -f $Base)
if ($Base -match '^HEAD') {
  Write-Host "    ⚠ 提醒：基线是 HEAD —— 刚 merge 完对侧提交但还没提交 merge 时，此法会假红（实测 76 处）；推前姿势请用 origin/master"
}

$rc = Invoke-DoyahSharedGate -RepoRoot $RepoRoot -Python $python -RelativeScript 'Scripts/check-exclusive-sections.py' -Arguments @('--mine', 'windows', '--base', $Base)

if ($rc -ne 0) {
  Write-DoyahFail ("越界判据报红（退出码 {0}）：一次改动不得落在对侧独占节 / 契约层内" -f $rc)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

Write-DoyahPass ("越界检查通过（本侧 = windows，基线 = {0}）" -f $Base)
Write-DoyahResult -Status PASS -Code 0
exit 0
