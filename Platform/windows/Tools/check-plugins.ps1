# 判据：Windows 侧插件架构（契约依据 = 概要设计 §3.52；本侧落法 = §8.5.8）
#
# 为什么需要它（人类主人 2026-10-13 令「把 Studio 通过插件形式加载 Notes 和 Retro」）：
#   插件化的三条承诺，**没有一条能靠"看一眼代码"确认**：
#     ① 清单是**唯一出处**（界面不许再写一份"有哪几个插件"）；
#     ② 插件的**挂点只能走白名单**、且**不许碰宿主内部模型**；
#     ③ **拔掉插件 ⇒ 挂点整体消失且不报错**（契约§3.52-④）。
#   ⇒ 前两条用**静态对账**守（`App/tools/check-plugins.mjs`），
#     第三条用**行为判据**守（`App/src/shell/pluginRegistry.test.ts` 真调注册表/派生器）。
#
# 为什么静态与行为**两道都要**：
#   只静态 ⇒ "文本对得上但运行时炸"（本侧栽过：`queryTabs` 未定义整段不渲染）；
#   只行为 ⇒ "注册表能跑但清单与界面早就各写一份"。
#
# 退出码：0 = 通过 · 1 = 判红（逐条点名）· 2 = 跳过（node/npm 不在）

$ErrorActionPreference = 'Stop'

$appDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'App'
$checker = Join-Path $appDir 'tools\check-plugins.mjs'

if (-not (Test-Path $checker)) {
    Write-Host "判红：判据脚本不在盘上 $checker"
    exit 1
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Host '跳过：本机没有 node（要人管：插件判据跑不了）'
    exit 2
}

# ── 第一道：静态三处对账（清单 ⇄ 装配 ⇄ 插件目录）────────────────────────────
Write-Host '· 第一道：静态对账（清单 ⇄ 装配 ⇄ 插件目录 + 挂点白名单 + import 面）'
$out = & node $checker 2>&1 | Out-String
$code = $LASTEXITCODE
foreach ($line in ($out.Trim() -split "`n")) { Write-Host "    $line" }
if ($code -ne 0) {
    Write-Host '判红：插件清单静态对账不过（逐条见上）'
    exit 1
}

# ── 第二道：行为判据（拔掉不报错 / 装回恢复 / 活动栏由清单派生）──────────────
Write-Host '· 第二道：行为判据（注册表 + 活动栏派生；`vitest` 真跑）'
if (-not (Test-Path (Join-Path $appDir 'node_modules'))) {
    Write-Host '跳过：App 依赖未安装（先 `npm ci`；跳过不是通过）'
    exit 2
}

Push-Location $appDir
try {
    $testOut = & npx vitest run src/shell/pluginRegistry.test.ts 2>&1 | Out-String
    $testCode = $LASTEXITCODE
} finally {
    Pop-Location
}

$summary = ($testOut -split "`n") | Where-Object { $_ -match 'Test Files|Tests ' } | ForEach-Object { $_.Trim() }
foreach ($line in $summary) { Write-Host "    $line" }
if ($testCode -ne 0) {
    Write-Host '判红：插件行为判据不过（拔掉不报错 / 装回恢复 / 清单派生 这三件事有一件没做到）'
    ($testOut -split "`n") | Where-Object { $_ -match 'FAIL|×' } | Select-Object -First 8 | ForEach-Object { Write-Host "    $($_.Trim())" }
    exit 1
}

Write-Host '通过：插件清单唯一出处 + 挂点白名单 + 拔掉不报错（两道判据都绿）'
exit 0
