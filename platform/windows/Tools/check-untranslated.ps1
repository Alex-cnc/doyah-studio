# Doyah Studio · Windows 侧闸门 · 双语漏译棘轮（platform/windows/Tools/check-untranslated.ps1）
#
# 对应 1.8 段的出口「**全部文案中英双语**」。为什么光有语言表证明不了：
# 语言表只是"**能**翻译"，而"**有没有漏**"要靠扫描 —— 界面上直接写死的中文，
# 切成英文之后仍然是中文（用户可见的不一致）。
#
# 判据 = 棘轮（**只减不增**），与设计令牌那边同一套做法：
#   `App/tools/untranslated-ratchet.py` 数出"没走语言表的中文用户可见文案"，
#   基线 `App/tools/untranslated-baseline.txt`，**只许往下调**。
#
# 口径（为什么这么切）：
#   · 注释里的中文不算（给读代码的人看，不是给用户看）；
#   · 模板里的中文基本就是用户可见文案；
#   · 脚本里只算会进界面的位置（`title` / `placeholder` / 确认框）；
#   · **语言表自己**与**测试文件**跳过。
#
# 退出码：0 = 通过 / 1 = 判红 / 2 = 跳过

param([string]$RepoRoot = '')

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

Write-Host ("== 双语漏译棘轮（{0}）" -f $RepoRoot)

$ratchet = Join-Path $RepoRoot 'platform/windows\App\tools\untranslated-ratchet.py'
$baseline = Join-Path $RepoRoot 'platform/windows\App\tools\untranslated-baseline.txt'

if (-not (Test-Path $ratchet)) {
    Write-DoyahFail "棘轮脚本不在盘上：platform/windows\App\tools\untranslated-ratchet.py"
    Write-DoyahResult -Status FAIL -Code 1
    exit 1
}
if (-not (Test-Path $baseline)) {
    Write-DoyahFail "基线不在盘上：platform/windows\App\tools\untranslated-baseline.txt"
    Write-DoyahResult -Status FAIL -Code 1
    exit 1
}

# python 不在就跳过（与其它 python 子判据同一姿势：**跳过要可见**）
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
if (-not $python) {
    Write-DoyahResult -Status SKIP -Code 2
    exit 2
}

$output = & $python.Source $ratchet 2>&1
$code = $LASTEXITCODE
$output | ForEach-Object { Write-Host ("  " + $_) }

if ($code -ne 0) {
    Write-DoyahFail "漏译比基线多了（新写的界面文案要走语言表 t(...)）"
    Write-DoyahResult -Status FAIL -Code 1
    exit 1
}

Write-DoyahPass "双语漏译棘轮未升高（基线只减不增）"
Write-DoyahResult -Status PASS -Code 0
exit 0
