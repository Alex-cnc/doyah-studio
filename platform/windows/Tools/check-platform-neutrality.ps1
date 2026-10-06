# Doyah Studio · Windows 侧闸门 · 平台中立性（platform/windows/Tools/check-platform-neutrality.ps1）
#
# 对应 §8.3 的「平台中立性校验」（另一平台要求 = 同样运行）。
# 判据复用 Scripts/check-platform-neutrality.py（三书里不得混入平台实现细节，棘轮只降不升），
# 棘轮基线 = Scripts/platform-neutrality-baseline.json（共享）。
#
# 退出码：0 = 通过 / 1 = 判红 / 2 = 跳过

param([string]$RepoRoot = '')

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

Write-Host ("== 平台中立性校验（{0}）" -f $RepoRoot)

$python = Find-DoyahPython
if (-not $python) {
  Write-DoyahFail "找不到可用的 Python 3（判据在 Scripts/check-platform-neutrality.py）"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

# 空跑不许通过（第 30 轮实测）：工作目录不对时，`Scripts/check-platform-neutrality.py` 会把三书
# **整批跳过**、照样退出 0 ⇒ 本侧闸门报「✅ 通过」，而它其实一本书都没读。受检输入是本侧能点名的
# 东西：三书必须在盘上（缺一份就判红，不许把「没读」读成「合规」）。
$missing = @()
foreach ($doc in @('Docs\需求规范书.md', 'Docs\产品能力规划说明书.md', 'Docs\概要设计.md')) {
  if (-not (Test-Path (Join-Path $RepoRoot $doc))) { $missing += $doc }
}
if ($missing.Count -gt 0) {
  Write-DoyahFail ("受检输入不在盘上：{0} ⇒ 判据会整批跳过（空跑不许读成通过）" -f ($missing -join '、'))
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$rc = Invoke-DoyahSharedGate -RepoRoot $RepoRoot -Python $python -RelativeScript 'Scripts/check-platform-neutrality.py'

if ($rc -ne 0) {
  Write-DoyahFail ("平台中立性判据报红（退出码 {0}）" -f $rc)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

Write-DoyahPass "三书未混入平台实现细节（严格档 0 处；报告档与棘轮基线一致）"
Write-DoyahResult -Status PASS -Code 0
exit 0
