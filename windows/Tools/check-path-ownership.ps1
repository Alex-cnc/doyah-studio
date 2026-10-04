# Doyah Studio · Windows 侧闸门（新增项）· 路径归属判据（windows/Tools/check-path-ownership.ps1）
#
# 派单 `T-20261002-033`（人类主人：「大河马与大肥鱼两侧各加一项路径归属判据」）的 **Windows 侧那一项**。
#
# 三条口径（**判据不重写**，与 §8.4 文档单一来源一致）：
#   ① **清单只有一份**：`Scripts/path-ownership.json`（macOS 侧落的，shared 面）—— 本脚本**只引用**，
#      不复制、不裁剪、不"本侧再维护一份"；
#   ② **判据本体也只有一份**：`Scripts/check-path-ownership.py`（同一份，三仓同源）——
#      本脚本只做"按本侧姿势传参"（`--mine windows` + 基线 `origin/master`）；
#   ③ **与既有越界判据同口径的基线**：默认 `origin/master`，与 `check-exclusive-sections.ps1` 一致
#      （这样两个判据看的是**同一批改动**）。
#
# 退出码：0 = 全绿 / 1 = 判红 / 2 = 跳过（清单或判据不在盘上 / 拿不到基线 —— 跳过要逐条说明）

param(
  [string]$RepoRoot = '',
  [string]$Base = 'origin/master',
  [switch]$RequireAll
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

Write-Host ("== 路径归属判据（本侧 = windows；清单 = Scripts/path-ownership.json）（{0}）" -f $RepoRoot)

$manifest = Join-Path $RepoRoot 'Scripts/path-ownership.json'
$checker = Join-Path $RepoRoot 'Scripts/check-path-ownership.py'
if (-not (Test-Path $manifest)) {
  Write-DoyahSkip -Text '路径归属判据' -Reason ("清单不在盘上：{0}（属共享面 Scripts/，由 macOS 侧落）" -f $manifest)
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}
if (-not (Test-Path $checker)) {
  Write-DoyahSkip -Text '路径归属判据' -Reason ("判据不在盘上：{0}（属共享面 Scripts/，由 macOS 侧落）" -f $checker)
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

$python = Find-DoyahPython
if (-not $python) {
  Write-DoyahSkip -Text '路径归属判据' -Reason '找不到可用的 Python 3（判据是 Scripts/check-path-ownership.py）'
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

# 基线能不能解析（解析不出就是环境问题：跳过并说明，不假装绿）
Push-Location $RepoRoot
try {
  $null = & git rev-parse --verify --quiet $Base 2>$null
  $baseOk = ($LASTEXITCODE -eq 0)
} finally { Pop-Location }
if (-not $baseOk) {
  Write-DoyahSkip -Text '路径归属判据' -Reason ("基线解析不出：{0}（先 git fetch；不猜基线）" -f $Base)
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

$rc = Invoke-DoyahSharedGate -RepoRoot $RepoRoot -Python $python `
  -RelativeScript 'Scripts/check-path-ownership.py' `
  -Arguments @('--mine', 'windows', '--base', $Base)

if ($rc -eq 0) {
  Write-DoyahPass ("路径归属通过（本侧 = windows；基线 = {0}）" -f $Base)
  Write-DoyahResult -Status PASS -Code 0
  exit 0
}
if ($rc -eq 2) {
  Write-DoyahSkip -Text '路径归属判据' -Reason ("判据自报跳过 / 清单过期（退出码 2，基线 {0}）" -f $Base)
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}
Write-DoyahFail ("路径归属判红（退出码 {0}）：一次改动不得落在对侧子树（macOS 族）上；共享面要登记理由" -f $rc)
Write-DoyahResult -Status FAIL -Code 1
exit 1
