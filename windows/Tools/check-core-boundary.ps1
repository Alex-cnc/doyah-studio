# Doyah Studio · Windows 侧闸门 · 领域层边界（windows/Tools/check-core-boundary.ps1）
#
# 对应 §8.3「领域层单测」那一行的判据 —— **GUI / 平台依赖不得进入领域层**（§8.5.1 / §8.5.3），
# 也就是 mac 侧 Scripts/check-core-portability.py 的机械等价物。
#
# 沿革（别把旧形态当现状）：第 21 轮首建时按 C# 形态写（`.csproj` / `UseWPF` / `DllImport`）；
# 2026-09-28 开工令把本侧换成 Rust（Tauri 2 + Vue 3 + TS / Rust）后，该项一直**如实跳过**
# （判据形态对不上工程 ⇒ 跳过不是「已通过」）。第 25 轮按 **Rust 形态重建**，自此
# **本项没有「跳过」档**：工程在盘上就必须判，判据面找不到 = 判红（空跑不许通过）。
#
# 三条判据（缺一即判红）：
#   A 判据面非空：`windows/Core/Cargo.toml` 在盘上、能解析出 [package]、src 下至少 1 个 .rs
#   B 依赖面：Core 的 Cargo.toml 里 dependencies / dev-dependencies / build-dependencies /
#     target.*.dependencies 段中**每个依赖名**都不得命中 GUI / 平台面清单
#     （tauri / wry / tao / winit / egui / slint / iced / windows* / winapi / webview2 / gtk* /
#       gdk* / cocoa / objc* / core-graphics / webkit2gtk / muda / tray-icon / rfd / arboard /
#       clipboard-win / keyring / portable-pty / wgpu* / wmi / winreg / dxgi / d3d* 一类）
#     —— FFI 与平台能力只允许在 `Platform/Windows/`（§8.5.1 第 4 行那两条）
#   C 源码面：Core 下 .rs 不得 `use <GUI/平台 crate>`、不得出现 `<crate>::` 路径、
#     不得用平台专有 std（`std::os::windows` / `std::os::unix`）、不得出现 FFI 形状
#     （`extern "C"` / `extern "system"` / `#[link(` / `windows_targets` / `libc::`）；
#     判红一律点名 `文件:行号`
#
# 逃生门：`core-boundary-allow：理由` —— **只认结构化写法**：整行注释（`//` 或 `#` 起头），
#   写在**被判红那一行的上一行**（Cargo.toml 里同理）；**理由为空仍判红**；放行的行**逐条打印**
#   （放行必须看得见 —— 不许静默豁免）。
#
# 每轮真跑一遍自测（契约侧 L-72 ㈠：「判据写完不对已知改动报红，等于没有」）：固定夹具七例
#   （基线 / 依赖注入 / 源码 crate 名 / FFI 形状 / 空跑 / 逃生门 / 末例核对真仓库逐字节未变），
#   夹具一律在临时目录。`-SkipSelfTest` 只给手工快跑用（闸门里不带它）。
#
# 退出码：0 = 通过 / 1 = 判红（本项没有「跳过」这一档）

param(
  [string]$RepoRoot = '',
  [switch]$SkipSelfTest
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

Write-Host ("== 领域层边界（GUI / 平台依赖不得进入领域层）（{0}）" -f $RepoRoot)

# ── GUI / 平台面清单（依赖名一律按 Cargo 口径归一：小写 + `_` 视同 `-`）─────────────
$script:GuiDeps = @(
  'tauri', 'wry', 'tao', 'winit', 'egui', 'egui-extras', 'slint', 'iced',
  'windows', 'windows-sys', 'windows-targets', 'windows-registry', 'winapi', 'wmi', 'winreg',
  'webview2', 'webview2-com',
  'gtk', 'gtk-sys', 'gdk', 'gdk-sys', 'glib', 'glib-sys', 'gio', 'webkit2gtk',
  'cocoa', 'objc', 'objc2', 'objc2-foundation', 'core-graphics', 'core-foundation', 'core-text',
  'muda', 'tray-icon', 'rfd', 'arboard', 'clipboard-win', 'clipboard', 'keyring', 'portable-pty',
  'conpty', 'wgpu', 'wgpu-hal', 'softbuffer', 'raw-window-handle', 'skia-safe', 'femtovg',
  'glazier', 'dxgi', 'd3d12'
)
$script:GuiPrefixes = @('windows-', 'winapi-', 'gtk', 'gdk', 'objc', 'webkit', 'cocoa-', 'core-graphics', 'd3d', 'dxgi', 'wgpu-')

function Test-DoyahGuiDependencyName {
  param([Parameter(Mandatory = $true)][string]$Name)
  $n = ($Name.ToLower() -replace '_', '-')
  if ($script:GuiDeps -contains $n) { return $true }
  foreach ($prefix in $script:GuiPrefixes) {
    if ($n.StartsWith($prefix)) { return $true }
  }
  return $false
}

function Get-DoyahSourceRules {
  # crate 名写进正则：`-` 与 `_` 两种写法都算（Cargo 里两者等价）
  $alt = ($script:GuiDeps -join '|') -replace '-', '[-_]'
  return @(
    @{ Name = 'use GUI / 平台 crate'; Pattern = ('^\s*(?:pub\s+)?use\s+(?:' + $alt + ')(?:\b|::)') },
    @{ Name = 'GUI / 平台 crate 路径'; Pattern = ('(?:^|[^A-Za-z0-9_-])(' + $alt + ')::') },
    @{ Name = 'extern crate GUI / 平台 crate'; Pattern = ('^\s*extern\s+crate\s+(?:' + $alt + ')\b') },
    @{ Name = '平台专有 std（std::os::windows / std::os::unix）'; Pattern = 'std::os::(windows|unix)\b' },
    @{ Name = 'FFI：extern "C" / extern "system"'; Pattern = 'extern\s+"(C|system)"' },
    @{ Name = 'FFI：#[link(...)]'; Pattern = '#\s*\[\s*link\s*\(' },
    @{ Name = 'FFI：windows_targets'; Pattern = '\bwindows_targets\b' },
    @{ Name = 'FFI：libc::'; Pattern = '\blibc::' }
  )
}

function Get-DoyahEscapeReason {
  # 返回：$null = 这一行没有逃生门；'' = 有但理由为空（仍判红）；其它 = 理由
  param([string]$Line)
  $m = [regex]::Match($Line.Trim(), '^(?://+|#)\s*core-boundary-allow\s*[：:]\s*(.*)$')
  if (-not $m.Success) { return $null }
  return $m.Groups[1].Value.Trim()
}

function Test-DoyahCoreBoundary {
  # 纯判据：在任意 Root 上跑（自测夹具复用同一份逻辑，避免「夹具里另写一套」）
  param([Parameter(Mandatory = $true)][string]$Root)

  $result = @{
    Problems = (New-Object System.Collections.Generic.List[string])
    Allowed  = (New-Object System.Collections.Generic.List[string])
    Deps     = 0
    Files    = 0
  }

  $coreDir = Join-Path $Root 'windows\Core'
  $cargoPath = Join-Path $coreDir 'Cargo.toml'
  if (-not (Test-Path $cargoPath)) {
    [void]$result.Problems.Add('判据面不存在：windows\Core\Cargo.toml 不在盘上（工程已在盘上，判据无从下手 ⇒ 空跑判红，不跳过）')
    return $result
  }
  $cargoText = Read-DoyahTextFile -Path $cargoPath
  if ($cargoText -notmatch '(?m)^\s*\[package\]') {
    [void]$result.Problems.Add('windows\Core\Cargo.toml 里解析不到 [package] 段 ⇒ 判据面异常（空跑不许通过）')
    return $result
  }

  # ── B 依赖面 ────────────────────────────────────────────────────────────────
  $cargoLines = $cargoText -split "`r?`n"
  $section = ''
  $sawDepSection = $false
  for ($i = 0; $i -lt $cargoLines.Count; $i++) {
    $line = $cargoLines[$i].Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { continue }
    if ($line -match '^\[(.+)\]$') {
      $section = $Matches[1].Trim().ToLower()
      if ($section -eq 'dependencies' -or $section -eq 'dev-dependencies' -or $section -eq 'build-dependencies' -or $section.EndsWith('.dependencies')) { $sawDepSection = $true }
      continue
    }
    $isDepSection = ($section -eq 'dependencies' -or $section -eq 'dev-dependencies' -or $section -eq 'build-dependencies' -or $section.EndsWith('.dependencies'))
    if (-not $isDepSection) { continue }
    $m = [regex]::Match($line, '^"?([A-Za-z0-9_\-]+)"?\s*=')
    if (-not $m.Success) { continue }
    $depName = $m.Groups[1].Value
    $result.Deps = $result.Deps + 1
    if (Test-DoyahGuiDependencyName -Name $depName) {
      $text = ("Cargo.toml:{0} 依赖面命中 GUI / 平台 crate：{1}" -f ($i + 1), $depName)
      $reasonFound = $null
      foreach ($idx in @($i - 1)) {
        if ($idx -lt 0) { continue }
        $r = Get-DoyahEscapeReason -Line $cargoLines[$idx]
        if ($null -ne $r) { $reasonFound = $r; break }
      }
      if ($null -eq $reasonFound) { [void]$result.Problems.Add($text) }
      elseif ($reasonFound -eq '') { [void]$result.Problems.Add($text + '（逃生门理由为空 ⇒ 仍判红）') }
      else { [void]$result.Allowed.Add(('Cargo.toml:{0} {1}（core-boundary-allow：{2}）' -f ($i + 1), $depName, $reasonFound)) }
    }
  }
  if (-not $sawDepSection) {
    [void]$result.Problems.Add('Cargo.toml 里找不到任何依赖段（[dependencies] 一类）⇒ 判据读不到依赖面（空跑不许通过：领域层的依赖面必须显式可判）')
  }

  # ── C 源码面 ────────────────────────────────────────────────────────────────
  $rules = Get-DoyahSourceRules
  $srcFiles = @(Get-ChildItem -Path $coreDir -Filter '*.rs' -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)
  $result.Files = $srcFiles.Count
  if ($srcFiles.Count -eq 0) {
    [void]$result.Problems.Add('windows\Core 下找不到任何 .rs ⇒ 判据面为空（空跑不许通过）')
    return $result
  }
  foreach ($file in $srcFiles) {
    $rel = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
    $lines = (Read-DoyahTextFile -Path $file.FullName) -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $trimmed = $lines[$i].Trim()
      if ($trimmed -eq '') { continue }
      if ($trimmed.StartsWith('//')) { continue }   # 纯注释行不扫：文档注释里提 crate 名不算依赖
      foreach ($rule in $rules) {
        if ($lines[$i] -notmatch $rule.Pattern) { continue }
        $text = ("{0}:{1} 出现 {2} ⇒ GUI / 平台依赖不得进入领域层（FFI 与平台能力只允许在 Platform\Windows\）" -f $rel, ($i + 1), $rule.Name)
        $reasonFound = $null
        foreach ($idx in @($i - 1)) {
          if ($idx -lt 0) { continue }
          $r = Get-DoyahEscapeReason -Line $lines[$idx]
          if ($null -ne $r) { $reasonFound = $r; break }
        }
        if ($null -eq $reasonFound) { [void]$result.Problems.Add($text) }
        elseif ($reasonFound -eq '') { [void]$result.Problems.Add($text + '（逃生门理由为空 ⇒ 仍判红）') }
        else { [void]$result.Allowed.Add(('{0}:{1} {2}（core-boundary-allow：{3}）' -f $rel, ($i + 1), $rule.Name, $reasonFound)) }
      }
    }
  }

  return $result
}

function Get-DoyahTreeHash {
  param([Parameter(Mandatory = $true)][string]$Dir)
  $items = @(Get-ChildItem -Path $Dir -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)
  $sb = New-Object System.Text.StringBuilder
  foreach ($f in $items) {
    $h = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
    [void]$sb.Append($f.FullName.Substring($Dir.Length)).Append(':').Append($h).Append("`n")
  }
  return $sb.ToString()
}

function New-DoyahBoundaryFixture {
  param(
    [Parameter(Mandatory = $true)][string]$Dir,
    [string]$CargoDeps = '',
    [string]$LibRs = ''
  )
  $src = Join-Path (Join-Path $Dir 'windows\Core') 'src'
  New-Item -ItemType Directory -Force -Path $src | Out-Null
  if (-not $LibRs) { $LibRs = "pub fn add(a: i64, b: i64) -> i64 {`n    a + b`n}`n" }
  $cargo = "[package]`nname = `"fixture-core`"`nversion = `"0.1.0`"`nedition = `"2021`"`n`n[dependencies]`n" + $CargoDeps
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Join-Path (Join-Path $Dir 'windows\Core') 'Cargo.toml'), $cargo, $utf8)
  [System.IO.File]::WriteAllText((Join-Path $src 'lib.rs'), $LibRs, $utf8)
}

# ── 主判据 ──────────────────────────────────────────────────────────────────
$main = Test-DoyahCoreBoundary -Root $RepoRoot
if ($main.Allowed.Count -gt 0) {
  Write-Host '   放行的行（逃生门 core-boundary-allow，逐条列出）：'
  foreach ($a in $main.Allowed) { Write-Host ('     · ' + $a) }
}
if ($main.Problems.Count -gt 0) {
  foreach ($p in $main.Problems) { Write-DoyahFail $p }
}
else {
  Write-DoyahPass ("领域层边界干净（Core 依赖 {0} 条 / 源文件 {1} 个；GUI 与平台能力只在 Platform\Windows\）" -f $main.Deps, $main.Files)
}

# ── 自测（固定夹具七例；夹具一律在临时目录，真仓库只被读、只被核对）──────────────────
$selfFailed = 0
if (-not $SkipSelfTest) {
  Write-Host '  ── 自测（固定夹具，临时目录）'
  $realCore = Join-Path $RepoRoot 'windows\Core'
  $before = ''
  if (Test-Path $realCore) { $before = Get-DoyahTreeHash -Dir $realCore }
  $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('doyah-boundary-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
  $caseCount = 0
  $caseOk = 0
  try {
    # 例 1：基线（干净夹具）⇒ 期望 0 判红
    $caseCount++
    $f = Join-Path $tmpRoot 'case1'
    New-DoyahBoundaryFixture -Dir $f
    $r = Test-DoyahCoreBoundary -Root $f
    if ($r.Problems.Count -eq 0 -and $r.Files -ge 1) { $caseOk++; Write-DoyahPass ('自测 1/{0} 基线：干净夹具通过（依赖 {1} 条 / 源文件 {2} 个）' -f 7, $r.Deps, $r.Files) }
    else { $selfFailed++; Write-DoyahFail ('自测 1/7 基线：期望 0 判红，实得 {0} 条：{1}' -f $r.Problems.Count, ($r.Problems -join ' | ')) }

    # 例 2：依赖面注入 tauri ⇒ 期望判红并点名
    $caseCount++
    $f = Join-Path $tmpRoot 'case2'
    New-DoyahBoundaryFixture -Dir $f -CargoDeps ("tauri = `"2`"`n")
    $r = Test-DoyahCoreBoundary -Root $f
    $hit = @($r.Problems | Where-Object { $_ -like '*tauri*' }).Count
    if ($hit -ge 1) { $caseOk++; Write-DoyahPass '自测 2/7 依赖注入：Cargo.toml 加 tauri ⇒ 判红并点名' }
    else { $selfFailed++; Write-DoyahFail ('自测 2/7 依赖注入：期望点名 tauri，实得 {0} 条判红' -f $r.Problems.Count) }

    # 例 3：源码里 use GUI crate ⇒ 期望判红并点名 文件:行号
    $caseCount++
    $f = Join-Path $tmpRoot 'case3'
    New-DoyahBoundaryFixture -Dir $f -LibRs ("use windows::core::*;`n`npub fn add(a: i64, b: i64) -> i64 {`n    a + b`n}`n")
    $r = Test-DoyahCoreBoundary -Root $f
    $hit = @($r.Problems | Where-Object { $_ -like '*lib.rs:1*' }).Count
    if ($hit -ge 1) { $caseOk++; Write-DoyahPass '自测 3/7 源码 crate 名：use windows::… ⇒ 判红并点名 lib.rs:1' }
    else { $selfFailed++; Write-DoyahFail ('自测 3/7 源码 crate 名：期望点名 lib.rs:1，实得：{0}' -f ($r.Problems -join ' | ')) }

    # 例 4：FFI 形状 ⇒ 期望判红
    $caseCount++
    $f = Join-Path $tmpRoot 'case4'
    New-DoyahBoundaryFixture -Dir $f -LibRs ("extern `"C`" {`n    fn probe();`n}`n")
    $r = Test-DoyahCoreBoundary -Root $f
    $hit = @($r.Problems | Where-Object { $_ -like '*FFI*' }).Count
    if ($hit -ge 1) { $caseOk++; Write-DoyahPass '自测 4/7 FFI 形状：extern "C" ⇒ 判红并点名' }
    else { $selfFailed++; Write-DoyahFail '自测 4/7 FFI 形状：期望判红，实得 0 条' }

    # 例 5：空跑（夹具里没有 windows/Core）⇒ 期望判红（不是跳过、不是通过）
    $caseCount++
    $f = Join-Path $tmpRoot 'case5'
    New-Item -ItemType Directory -Force -Path $f | Out-Null
    $r = Test-DoyahCoreBoundary -Root $f
    if ($r.Problems.Count -ge 1 -and @($r.Problems | Where-Object { $_ -like '*判据面不存在*' }).Count -ge 1) { $caseOk++; Write-DoyahPass '自测 5/7 空跑：判据面不存在 ⇒ 判红（空跑不许通过）' }
    else { $selfFailed++; Write-DoyahFail '自测 5/7 空跑：期望判红并点明判据面不存在，实得 0 条' }

    # 例 6：逃生门（上一行整行注释 + 理由非空）⇒ 期望通过 + 1 条放行记录
    $caseCount++
    $f = Join-Path $tmpRoot 'case6'
    New-DoyahBoundaryFixture -Dir $f -LibRs ("// core-boundary-allow：自测夹具，验证逃生门本身`nuse tauri::App;`n`npub fn add(a: i64, b: i64) -> i64 {`n    a + b`n}`n")
    $r = Test-DoyahCoreBoundary -Root $f
    if ($r.Problems.Count -eq 0 -and $r.Allowed.Count -ge 1) { $caseOk++; Write-DoyahPass ('自测 6/7 逃生门：整行注释 + 理由非空 ⇒ 放行并逐条打印（{0} 条）' -f $r.Allowed.Count) }
    else { $selfFailed++; Write-DoyahFail ('自测 6/7 逃生门：期望放行 1 条，实得判红 {0} 条 / 放行 {1} 条' -f $r.Problems.Count, $r.Allowed.Count) }

    # 例 7（末例）：真仓库 windows/Core 逐字节未变
    $caseCount++
    $after = ''
    if (Test-Path $realCore) { $after = Get-DoyahTreeHash -Dir $realCore }
    if ($before -ne '' -and $before -eq $after) { $caseOk++; Write-DoyahPass '自测 7/7 末例：自测前后真仓库 windows\Core 下文件 sha256 逐字节一致' }
    else { $selfFailed++; Write-DoyahFail '自测 7/7 末例：真仓库 windows\Core 发生变化（或不存在）—— 夹具不该碰真仓库' }
  }
  finally {
    Remove-Item -Path $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Host ("   自测：{0}/{1} 例通过" -f $caseOk, $caseCount)
}

if ($main.Problems.Count -gt 0 -or $selfFailed -gt 0) {
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}
Write-DoyahResult -Status PASS -Code 0
exit 0
