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

param(
  [string]$RepoRoot = '',
  [switch]$SelfTest
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')

# ── 判据本体：Windows 列的如实性（主路径与 -SelfTest 读**同一份**）─────────────────────
#
# 返回一组「判红理由」（空数组 = 如实）。三条口径：
#   ① 台账必须在盘上、必须有 platforms.windows 与 label / role / owner；
#   ② **工程已建** = platform/windows 下有工程文件。**.csproj 不是唯一形态**：
#      2026-09-28 开工令换栈后本侧是 Rust/Tauri（`Cargo.toml`），只认 `.csproj` 会把
#      已经建起来的工程当成「未开工」—— 判据于是**陈述了假事实**（本项第 28 轮实测）。
#   ③ 未建工程时**全 ⬜（无 overrides）是唯一可接受状态**；已建工程时 overrides 由台账决定，
#      与表格是否一致交给上面的共享判据 `--check`。
function Get-DoyahWindowsColumnVerdict {
  param(
    [AllowNull()]$Ledger,
    [Parameter(Mandatory = $true)][int]$ProjectFileCount
  )
  $reasons = New-Object System.Collections.ArrayList
  if (-not $Ledger) {
    [void]$reasons.Add('台账不在盘上或解析不出（Docs/平台实现状态.json）')
    return $reasons
  }
  if (-not $Ledger.platforms -or -not $Ledger.platforms.windows) {
    [void]$reasons.Add('台账缺 platforms.windows 键（契约侧 L-26 的形状）')
    return $reasons
  }
  $windows = $Ledger.platforms.windows
  foreach ($field in @('label', 'role', 'owner')) {
    if (-not $windows.$field) { [void]$reasons.Add(('台账 platforms.windows 缺 {0}' -f $field)) }
  }
  $overrideCount = @($windows.overrides.PSObject.Properties).Count
  if ($ProjectFileCount -eq 0 -and $overrideCount -gt 0) {
    [void]$reasons.Add(('未开工却登记了 {0} 条 overrides ⇒ 不如实（§8.5.6-2：未开工时全 ⬜ 是唯一可接受状态）' -f $overrideCount))
  }
  return $reasons
}

# ── 判据自测（负例）──────────────────────────────────────────────────────────────
#
# 每一条负例都在证「判据真的抓得到它声称抓的东西」；两条正对照保证它**不误伤如实**。
# 全部在内存里造台账（`ConvertFrom-Json`），**盘上一个字节不动**。
function Invoke-DoyahParitySelfTest {
  $cases = @(
    @{ Name = '负例·未开工却登记 overrides'; Ledger = '{"platforms":{"windows":{"label":"Windows","role":"r","owner":"o","overrides":{"FR-X":"done"}}}}'; Files = 0; WantReasons = $true; MustMention = '未开工' },
    @{ Name = '负例·台账缺 platforms.windows'; Ledger = '{"platforms":{"macos":{"label":"macOS"}}}'; Files = 0; WantReasons = $true; MustMention = 'platforms.windows' },
    @{ Name = '负例·台账缺 owner'; Ledger = '{"platforms":{"windows":{"label":"Windows","role":"r"}}}'; Files = 0; WantReasons = $true; MustMention = 'owner' },
    @{ Name = '负例·台账是 null'; Ledger = $null; Files = 0; WantReasons = $true; MustMention = '台账' },
    @{ Name = '正对照·未开工且无 overrides'; Ledger = '{"platforms":{"windows":{"label":"Windows","role":"r","owner":"o","overrides":{}}}}'; Files = 0; WantReasons = $false; MustMention = '' },
    @{ Name = '正对照·工程已建（Cargo.toml）且登记 overrides'; Ledger = '{"platforms":{"windows":{"label":"Windows","role":"r","owner":"o","overrides":{"FR-X":"done"}}}}'; Files = 1; WantReasons = $false; MustMention = '' }
  )
  $failed = 0
  foreach ($case in $cases) {
    $ledger = $null
    if ($case.Ledger) { $ledger = ConvertFrom-Json $case.Ledger }
    $reasons = @(Get-DoyahWindowsColumnVerdict -Ledger $ledger -ProjectFileCount $case.Files)
    $has = ($reasons.Count -gt 0)
    if ($has -ne $case.WantReasons) {
      Write-DoyahFail (('{0}：期望「{1}」，实际判红数组 = [{2}]' -f $case.Name, $(if ($case.WantReasons) { '有理由' } else { '无理由' }), ($reasons -join ' / ')))
      $failed += 1
      continue
    }
    if ($case.WantReasons -and $case.MustMention) {
      $joined = ($reasons -join ' / ')
      if ($joined -notmatch [regex]::Escape($case.MustMention)) {
        Write-DoyahFail (('{0}：判红理由里没点名「{1}」（实际：{2}）' -f $case.Name, $case.MustMention, $joined))
        $failed += 1
        continue
      }
    }
    Write-Host ('    ✅ {0}' -f $case.Name)
  }
  $total = $cases.Count
  Write-Host ('    判据自测：{0}/{1}' -f ($total - $failed), $total)
  if ($failed -gt 0) { return 1 }
  return 0
}

if ($SelfTest) {
  Write-Host '== ⑤ 平台等价矩阵 · 判据自测（负例 4 / 正对照 2）'
  exit (Invoke-DoyahParitySelfTest)
}

if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

Write-Host ("== ⑤ 平台等价矩阵与 Windows 列如实性（{0}）" -f $RepoRoot)

$python = Find-DoyahPython
if (-not $python) {
  Write-DoyahFail "找不到可用的 Python 3（判据在 Scripts/gen-platform-parity.py）"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$failed = $false

# ── 判据自己的证据（每轮真跑）：负例 4 / 正对照 2 ─────────────────────────────────
Write-Host "  ── 判据自测（固定夹具，全部在内存里造台账）"
if ((Invoke-DoyahParitySelfTest) -ne 0) {
  Write-DoyahFail "判据自测未通过 ⇒ 本判据自己的证据不成立"
  $failed = $true
}

$rc = Invoke-DoyahSharedGate -RepoRoot $RepoRoot -Python $python -RelativeScript 'Scripts/gen-platform-parity.py' -Arguments @('--check')
if ($rc -ne 0) {
  Write-DoyahFail ("等价矩阵判据报红（退出码 {0}）：Windows 列与台账不一致 / 表格被手工改过" -f $rc)
  $failed = $true
}

# ── 第二道：本侧如实性（§8.5.6-2）─────────────────────────────────────────────
$ledgerPath = Join-Path $RepoRoot 'Docs\平台实现状态.json'
if (-not (Test-Path $ledgerPath)) {
  Write-DoyahFail ("台账不在盘上：Docs/平台实现状态.json（Windows 列的唯一真相来源）")
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$ledger = ConvertFrom-Json (Read-DoyahTextFile -Path $ledgerPath)

# 工程已建 = 有 `.csproj`（旧栈）**或** `Cargo.toml`（现栈：Rust/Tauri，2026-09-28 开工令）。
# 只认 `.csproj` 会把已经建起来的工程报成「未开工」—— 判据陈述假事实（第 28 轮实测）。
$windowsDir = Join-Path $RepoRoot 'platform/windows'
$csprojFiles = @()
if (Test-Path $windowsDir) {
  $csprojFiles = @(Get-ChildItem -Path $windowsDir -Filter '*.csproj' -Recurse -File -ErrorAction SilentlyContinue)
}
$hasCargo = Test-Path (Join-Path $windowsDir 'Cargo.toml')
$projectCount = $csprojFiles.Count
if ($hasCargo) { $projectCount += 1 }

if ($hasCargo) {
  Write-Host "    本侧形态：platform/windows/Cargo.toml 在盘上（Rust/Tauri 现栈）⇒ 工程已建，状态一律从台账改、改完重生成 §10.10"
}
elseif ($csprojFiles.Count -gt 0) {
  Write-Host ("    本侧形态：platform/windows/ 下有 {0} 个 .csproj ⇒ 工程已建，状态一律从台账改、改完重生成 §10.10" -f $csprojFiles.Count)
}
else {
  Write-Host "    本侧形态：platform/windows/ 下既没有 .csproj 也没有 Cargo.toml（工程未建，§8.5.7 ⬜ 未开工）"
}

$overrideCount = 0
if ($ledger.platforms -and $ledger.platforms.windows) {
  $overrideCount = @($ledger.platforms.windows.overrides.PSObject.Properties).Count
}
Write-Host ("    台账 overrides：{0} 条" -f $overrideCount)

foreach ($reason in @(Get-DoyahWindowsColumnVerdict -Ledger $ledger -ProjectFileCount $projectCount)) {
  Write-DoyahFail $reason
  $failed = $true
}
if (-not $failed) {
  Write-DoyahPass ("Windows 列如实：台账无缺项 · 工程已建={0} · overrides={1} 条（表格一致性由 --check 判据覆盖）" -f [bool]$projectCount, $overrideCount)
}

if ($failed) {
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

Write-DoyahResult -Status PASS -Code 0
exit 0
