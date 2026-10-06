# Doyah Studio · Windows 侧闸门 ⑦ `P-*` 平台差异登记两侧对账（platform/windows/Tools/check-p-parity.ps1）
#
# 对应队列 **L-45**（契约侧 2026-09-27 第 36 轮落地：`Scripts/check-p-parity.py` 接进
# `Scripts/verify-all.sh` 第 7 项）。判据复用共享脚本，**本侧只编排、不重写**（§8.4 文档单一来源）。
#
# 为什么这一项与 Windows 侧直接相关：
#   §8.5.5（本节 `[独占:windows]`）是 `P-17`~`P-24` 的**原始落条目处**，判据第 3 类就是冲着它来的 ——
#   **本节已落的条目只要没有同时出现在 §4 与 SRS §10.9，就判红**（「已落条但未并入」不许静默）。
#   ⇒ 本侧此后新登记一条平台差异，会在契约侧并入前**保持判红**，这是设计意图、不是故障：
#     处置 = 在本节写明该条待契约侧并入（并可先提提案），**不要**因为判红就把条目删掉。
#
# 三类判据（以判据侧 docstring 为准）：A 双向覆盖（§10.9 ↔ §4 编号集合相等）/ B 同号同物 /
# C §8.5.5 已落条但未并入 §4 与 §10.9 即判红。**不判行序**，也**不判「同域不同号」**
# （后者是登记表要不要合并条目的设计问题，归提案与队列条目）。
#
# 本项没有「跳过」路径：判据只读入库的两份文档（`Docs/需求规范书.md` / `Docs/概要设计.md`），
# 不依赖被 `.gitignore` 排除的本地文档 ⇒ 干净克隆上同样能跑。
#
# 退出码：0 = 通过 / 1 = 判红 / 2 = 跳过（本项当前无跳过路径，保留给将来）

param(
  [string]$RepoRoot = '',
  [switch]$SelfTest
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

$python = Find-DoyahPython
if (-not $python) {
  Write-DoyahFail "找不到可用的 Python 3（判据在 Scripts/check-p-parity.py）"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

if ($SelfTest) {
  Write-Host "== ⑦ P-* 平台差异登记两侧对账 · 判据自测（--self-test，期望 8/8）"
  $rc = Invoke-DoyahSharedGate -RepoRoot $RepoRoot -Python $python -RelativeScript 'Scripts/check-p-parity.py' -Arguments @('--self-test')
  if ($rc -ne 0) {
    Write-DoyahFail ("判据自测未通过（退出码 {0}）—— 判据本身可疑，先别信它的绿" -f $rc)
    Write-DoyahResult -Status FAIL -Code 1
    exit 1
  }
  Write-DoyahPass "P-* 对账判据自测 8/8"
  Write-DoyahResult -Status PASS -Code 0
  exit 0
}

Write-Host ("== ⑦ P-* 平台差异登记两侧对账（SRS §10.9 ↔ 概要设计 §4，含 §8.5.5 已落条告警；{0}）" -f $RepoRoot)

$rc = Invoke-DoyahSharedGate -RepoRoot $RepoRoot -Python $python -RelativeScript 'Scripts/check-p-parity.py'

if ($rc -ne 0) {
  Write-DoyahFail ("P-* 对账报红（退出码 {0}）：双向覆盖缺口 / 同号不同物 / §8.5.5 已落条未并入 —— 逐条见上面的点名行" -f $rc)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

Write-DoyahPass "P-* 对账通过（双向覆盖 + 同号同物 + §8.5.5 无未并入条目）"
Write-DoyahResult -Status PASS -Code 0
exit 0
