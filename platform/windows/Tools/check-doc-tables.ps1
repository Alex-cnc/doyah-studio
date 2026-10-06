# Doyah Studio · Windows 侧闸门 ③ 文档计数 + 文档版本（platform/windows/Tools/check-doc-tables.ps1）
#
# 判据**不重写**：与 macOS 侧同一份脚本（Scripts/check-doc-tables.py / check-doc-versions.py）——
# 文档单一来源原则（§8.4）下，"另一平台再写一份表格解析器"等于造第二份判据，迟早两边不一致。
# 本脚本只负责：探测可用的 Python 3、按本侧姿势传参、如实报「跑了几项 / 跳过了什么」。
#
# 退出码：0 = 通过 / 1 = 判红 / 2 = 跳过（见 _common.ps1 顶部协议）

param(
  [string]$RepoRoot = '',
  [switch]$RequireAll
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

Write-Host ("== ③ 文档计数与版本校验（{0}）" -f $RepoRoot)

$python = Find-DoyahPython
if (-not $python) {
  Write-DoyahFail "找不到可用的 Python 3（判据在 Scripts/*.py；注意 Windows 上 python3 是应用商店占位符，本脚本已按 PYTHON → py -3 → python → python3 实跑探测）"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}
Write-Host ("    Python：{0}" -f $python.Label)

$tableArgs = @()
if ($RequireAll) { $tableArgs += '--require-all' }

$rcTables = Invoke-DoyahSharedGate -RepoRoot $RepoRoot -Python $python -RelativeScript 'Scripts/check-doc-tables.py' -Arguments $tableArgs
$rcVersions = Invoke-DoyahSharedGate -RepoRoot $RepoRoot -Python $python -RelativeScript 'Scripts/check-doc-versions.py'

# 取号工具：只读提示（不是判据）。本机已知缺口：--ids L 依赖不入库的本地文档，会在本机报错 ⇒ 不判红。
Write-Host "    （取号提示 —— 改本侧台账行/版本行时按工具给的号写，禁手抄）"
$null = Invoke-DoyahSharedGate -RepoRoot $RepoRoot -Python $python -RelativeScript 'Scripts/next-doc-version.py' -Arguments @('Docs/概要设计.md', 'Docs/需求规范书.md')

if ($rcTables -ne 0 -or $rcVersions -ne 0) {
  Write-DoyahFail ("文档判据报红（表格 {0} / 版本 {1}）" -f $rcTables, $rcVersions)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

Write-DoyahPass "文档表格与派生数字、变更记录版本号、头部版本、队列条目号均与判据一致"
Write-DoyahResult -Status PASS -Code 0
exit 0
