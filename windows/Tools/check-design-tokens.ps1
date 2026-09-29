# Doyah Studio · Windows 侧闸门 · 设计令牌棘轮（windows/Tools/check-design-tokens.ps1）
#
# 对应 §8.3 的「设计令牌棘轮」与 §8.5.3：另一平台的等价物 + **同一份基线取值**。
# mac 侧的 Scripts/check-design-tokens.py 是 Swift 专用（扫 App/ 下 .swift 统计裸值），
# 无法直接跑在 Windows 侧，故本脚本按同一套**规则名**在 Windows 侧重建棘轮。
#
# 三道判据：
#   ① 规则名对齐：mac 基线 Scripts/design-token-baseline.json 里出现过的规则名，
#      必须都在本脚本声明的清单里 —— 契约侧新增/改名规则时，本侧立刻知道要跟（现在就能跑）。
#   ② 令牌取值单一来源的前置：mac 侧令牌源 Core/DesignTokens.swift 仍在盘上
#      （§8.5.3：令牌取值属"一样"的五项之一，不得各写一套；本侧令牌源在建工程时按它生成）。
#   ③ Windows 表示层裸值棘轮（2026-09-28 本侧第 26 轮按 Tauri / Vue / TS 栈重建）：
#      旧版扫 windows/App/**/*.xaml（WPF 栈的形态）—— 换栈后一个 .xaml 都没有，**扫描集为空也 PASS**，
#      是假绿。新版把棘轮交给 windows/App 自己的 node 判据（判据跟着代码走、能单测），本脚本只编排：
#      `tools/gen-tokens.mjs --check`（令牌生成物 ⇄ mac 侧令牌源逐字一致）与
#      `tools/token-ratchet.mjs`（六条同名规则的裸值棘轮 + 引用面 ⊆ 定义面），
#      基线 windows/Tools/design-token-baseline.json，**只降不升**（工程未建 ⇒ 跳过，不是通过）。
#
# 退出码：0 = 通过 / 1 = 判红 / 2 = 跳过

param([string]$RepoRoot = '')

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

Write-Host ("== 设计令牌棘轮（{0}）" -f $RepoRoot)

# 与 Scripts/check-design-tokens.py docstring 里的规则名对齐（两侧同名，不各写一套）
$rules = @('bare-color', 'bare-font', 'bare-spacing', 'bare-radius', 'bare-textstyle', 'bare-foreground')

$failed = $false

# ── ① 规则名对齐 ─────────────────────────────────────────────────────────────
$macBaselinePath = Join-Path $RepoRoot 'Scripts\design-token-baseline.json'
if (-not (Test-Path $macBaselinePath)) {
  Write-DoyahFail "mac 侧棘轮基线不在盘上：Scripts\design-token-baseline.json"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$macBaseline = ConvertFrom-Json (Read-DoyahTextFile -Path $macBaselinePath)
$seenRules = New-Object System.Collections.Generic.HashSet[string]
foreach ($fileProp in $macBaseline.files.PSObject.Properties) {
  foreach ($ruleProp in $fileProp.Value.PSObject.Properties) { [void]$seenRules.Add($ruleProp.Name) }
}
$unknownRules = @($seenRules | Where-Object { $rules -notcontains $_ } | Sort-Object)
if ($unknownRules.Count -gt 0) {
  Write-DoyahFail ("mac 基线里出现本脚本没声明的规则名：{0} ⇒ 契约侧改过规则，本侧棘轮要跟" -f ($unknownRules -join '、'))
  $failed = $true
}
else {
  Write-DoyahPass ("规则名对齐（基线里出现的规则：{0}；本侧声明 {1} 条）" -f (($seenRules | Sort-Object) -join '、'), $rules.Count)
}

# ── ② 令牌取值单一来源的前置 ─────────────────────────────────────────────────
$macTokenSource = Join-Path $RepoRoot 'Core\DesignTokens.swift'
if (Test-Path $macTokenSource) {
  Write-DoyahPass "mac 侧令牌源在盘上：Core\DesignTokens.swift（本侧令牌取值按它生成，不另立一套）"
}
else {
  Write-DoyahFail "mac 侧令牌源 Core\DesignTokens.swift 不在盘上（被移走 / 改名）⇒ 本侧令牌取值没有基准"
  $failed = $true
}

# ── ③ Windows 表示层裸值棘轮（2026-09-28 本侧第 26 轮按 Tauri / Vue / TS 栈重建）─────
#
# 旧版扫 `windows\App\**\*.xaml`（那是 WPF 栈的形态）—— 换栈后**一个 .xaml 都没有，
# 扫描集为空也照样 PASS**（假绿：棘轮看着在守、其实没守）。新版把棘轮交给**前端目录自己的
# node 判据**（判据跟着代码走、能单测），本脚本只做编排与空跑判定：
#   ① tools/gen-tokens.mjs --check —— 令牌生成物 ⇄ mac 侧令牌源 Core/DesignTokens.swift 逐字一致
#      （令牌取值属「一样」的五项之一 ⇒ 只能有一处源；改了源不重新生成即判红）；
#   ② tools/token-ratchet.mjs —— 六条**与 mac 基线同名**的规则统计裸值（只降不升）
#      + 引用面 ⊆ 定义面（拼错变量名在 Vue / CSS 里不报错、只是不生效）。
# 规则名对齐仍由本脚本 ① 项判；棘轮的**空跑保护**在脚本内（扫描集为空即非零退出）。
$appDir = Join-Path $RepoRoot 'windows\App'
if (-not (Test-Path $appDir)) {
  Write-DoyahSkip -Text "Windows 表示层裸值棘轮（windows\App）" -Reason "表示层工程未建（§8.5.7 ⬜ 未开工）—— 工程建成后本项按 same-rules 棘轮跑，基线 windows\Tools\design-token-baseline.json"
  if ($failed) { Write-DoyahResult -Status FAIL -Code 1; exit 1 }
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

$windowsBaselinePath = Join-Path $RepoRoot 'windows\Tools\design-token-baseline.json'
if (-not (Test-Path $windowsBaselinePath)) {
  Write-DoyahFail "windows\App 已建，但棘轮基线不在盘上：windows\Tools\design-token-baseline.json（棘轮必须有基线，否则第一次就无参照）"
  $failed = $true
}

$nodeExe = ''
foreach ($candidate in @('C:\Program Files\nodejs\node.exe', 'C:\Program Files (x86)\nodejs\node.exe')) {
  if (Test-Path $candidate) { $nodeExe = $candidate; break }
}
if (-not $nodeExe) {
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  if ($nodeCmd) { $nodeExe = $nodeCmd.Source }
}
if (-not $nodeExe) {
  Write-DoyahFail "本机找不到 node：表示层的令牌判据与构建都要它（§8.5.1 栈要求 Node 工具链）—— 这不是「跳过」"
  $failed = $true
}
else {
  Write-Host ("    node：{0}" -f $nodeExe)
  $tokenChecks = @(
    @{ Label = '令牌生成物 ⇄ 令牌源（gen-tokens --check）'; Args = @('tools/gen-tokens.mjs', '--check') },
    @{ Label = '裸值棘轮 + 引用面（token-ratchet）'; Args = @('tools/token-ratchet.mjs') }
  )
  foreach ($check in $tokenChecks) {
    # 判红与否**只由退出码决定**：node 往 stderr 写的那行判红原因照原样打印，不许被 PS 5.1 的
    # `$ErrorActionPreference = 'Stop'` 变成终止错误（同 `_common.ps1` 里记的那处坑 —— 第 30 轮实测：
    # 判据明明「打印一条原因、退出码 1」，本侧闸门却整项报成「抛异常」，还因为半路抛出而漏掉 Pop-Location，
    # 把后面的项全带跑在 windows/App 下）。
    Push-Location $appDir
    try {
      $prevEap = $ErrorActionPreference
      $ErrorActionPreference = 'Continue'
      try {
        $out = & $nodeExe @($check.Args) 2>&1
        $rc = $LASTEXITCODE
      }
      finally { $ErrorActionPreference = $prevEap }
    }
    finally { Pop-Location }
    foreach ($line in $out) { Write-Host ("    {0}" -f $line) }
    if ($rc -ne 0) {
      Write-DoyahFail ("{0} 判红（退出码 {1}）" -f $check.Label, $rc)
      $failed = $true
    }
    else {
      Write-DoyahPass $check.Label
    }
  }
}

if ($failed) { Write-DoyahResult -Status FAIL -Code 1; exit 1 }
Write-DoyahResult -Status PASS -Code 0
exit 0
