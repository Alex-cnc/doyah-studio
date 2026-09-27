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
#   ③ Windows 表示层裸值棘轮：windows/App/**/*.xaml 按规则名统计，与
#      windows/Tools/design-token-baseline.json 比较，**只降不升**（工程未建 ⇒ 跳过，不是通过）。
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

# ── ③ Windows 表示层裸值棘轮 ─────────────────────────────────────────────────
$appDir = Join-Path $RepoRoot 'windows\App'
if (-not (Test-Path $appDir)) {
  Write-DoyahSkip -Text "Windows 表示层裸值棘轮（windows\App）" -Reason "表示层工程未建（§8.5.7 ⬜ 未开工）—— 工程建成后本项按 same-rules 棘轮跑，基线文件 windows\Tools\design-token-baseline.json"
  if ($failed) { Write-DoyahResult -Status FAIL -Code 1; exit 1 }
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

$windowsBaselinePath = Join-Path $RepoRoot 'windows\Tools\design-token-baseline.json'
if (-not (Test-Path $windowsBaselinePath)) {
  Write-DoyahFail "windows\App 已建，但棘轮基线不在盘上：windows\Tools\design-token-baseline.json（棘轮必须有基线，否则第一次就无参照）"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$windowsBaseline = ConvertFrom-Json (Read-DoyahTextFile -Path $windowsBaselinePath)
$windowsFiles = @(Get-ChildItem -Path $appDir -Filter '*.xaml' -Recurse -File -ErrorAction SilentlyContinue)
$ratchetViolations = New-Object System.Collections.Generic.List[string]

function Get-BareTokenCount {
  param([string]$Text, [string]$Rule)
  switch ($Rule) {
    'bare-color' { return ([regex]::Matches($Text, '#[0-9A-Fa-f]{6,8}')).Count }
    'bare-spacing' { return ([regex]::Matches($Text, '(Margin|Padding)="[^"]*\d')).Count }
    'bare-font' { return ([regex]::Matches($Text, 'FontSize="\d')).Count }
    'bare-radius' { return ([regex]::Matches($Text, 'CornerRadius="\d')).Count }
    'bare-textstyle' { return ([regex]::Matches($Text, 'TextBlock\s+Style="(?!\{StaticResource)')).Count }
    'bare-foreground' { return ([regex]::Matches($Text, 'Foreground="(?!\{StaticResource)')).Count }
    default { return 0 }
  }
}

foreach ($file in $windowsFiles) {
  $relative = $file.FullName.Substring($RepoRoot.Length).TrimStart('\').Replace('\', '/')
  $text = Read-DoyahTextFile -Path $file.FullName
  $baselineCounts = $null
  if ($windowsBaseline.files.PSObject.Properties.Name -contains $relative) {
    $baselineCounts = $windowsBaseline.files.$relative
  }
  foreach ($rule in $rules) {
    $count = Get-BareTokenCount -Text $text -Rule $rule
    $limit = 0
    if ($baselineCounts -and ($baselineCounts.PSObject.Properties.Name -contains $rule)) { $limit = [int]$baselineCounts.$rule }
    if ($count -gt $limit) {
      $ratchetViolations.Add(("{0}：{1} = {2} > 基线 {3}" -f $relative, $rule, $count, $limit))
    }
  }
}

if ($ratchetViolations.Count -gt 0) {
  foreach ($violation in $ratchetViolations) { Write-DoyahFail $violation }
  Write-DoyahFail "设计令牌棘轮只降不升；迁移到位后用 --update-baseline（mac 侧口径）下调基线"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

Write-DoyahPass ("Windows 表示层裸值棘轮未升高（扫 {0} 个 .xaml，规则 {1} 条）" -f $windowsFiles.Count, $rules.Count)

if ($failed) { Write-DoyahResult -Status FAIL -Code 1; exit 1 }
Write-DoyahResult -Status PASS -Code 0
exit 0
