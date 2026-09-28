# Doyah Studio · Windows 侧闸门 · 发布产物版本号「一个值、三处逐字一致」（windows/Tools/check-release-version.ps1）
#
# 对应 §8.3 闸门表那一行「**生成物一致性：发布产物版本号一个值三处一致**」（契约侧第 68 轮 · 队列 L-70 新增）
# —— 也就是 mac 侧 `Scripts/check-release-version.py` 的 **Windows 等价物**。那条判的是
# `build-app.sh` 的 Info.plist 模板 / `project.yml` / 生成物 `project.pbxproj`；
# 本侧一处都不同名 ⇒ 按**同规则名**重建（判据形态跟着文件走，见 `Tools/README.md` 的归属表）。
#
# 由头（本侧第 27 轮，`windows/App/` 表示层落地后）：`0.2.0` 这个值同时写在三处
# （`App/package.json` / `App/src-tauri/tauri.conf.json` / `App/src-tauri/Cargo.toml`），
# **改一处不改另两处没有任何东西会红** —— `vite build` 照过、`cargo build` 照过、单测照绿。
# 与 mac 侧第 57 轮同族的现象：写在同一个产品三处的同一个值，靠人记得同步 = **纸面纪律**。
# mac 侧那条判据第一次上真仓库就抓到「应用目标一个版本键都没有」；本侧第一次上真仓库
# 三处已经同值（绿），所以**判据的发现力必须由注入自证给出**（见下「每个值都注入一次」）。
#
# 四条判据（缺一即判红；本项**没有「跳过」档** —— 工程在盘上就必须判）：
#   A 台账自洽：`windows/Tools/release-version.json` 结构完整（值 / 形状 / 权威处 / 镜像处 /
#     跨端口径 / 锚点 / 范围外 / 生成物登记或空的原因），值形如 `主.次.修订`。
#   B 三处逐字一致：B1 权威处 = `App/src-tauri/tauri.conf.json` 的 `version`（Tauri bundler 把
#     productName + version 写进 MSI / NSIS 元数据 ⇒ 发布产物实际携带的就是它）；B2 `App/package.json`；
#     B3 `App/src-tauri/Cargo.toml` 的 `[package] version`（**必须在 `[package]` 段内**
#     —— 依赖段里的 `version =` 不算）。**缺键 = 判红**（= mac 侧第 57 轮的现场：键压根不存在）；
#     同一处出现第二个同名键也判红（= 又是一处副本）。
#   C 与 mac 侧发布台账同源：读 `Scripts/release-version.json` 的 `marketingVersion`；
#     台账 `platformAlign.policy` = `equal`（默认）⇒ 必须相等，不等判红并两边报值；
#     = `independent` ⇒ 理由必须非空（放行**逐条打印**，理由为空仍判红）。
#     对侧 `buildVersion`（构建号）**不跟随**，每次显式打印。
#   D 空跑防护：三处 + 跨端 + 锚点的比对点数低于下限即判红
#     （防「判据被掏空 ⇒ 零命中 = 通过」；台账、锚点文件缺一个也判红，不静默缩小受检面）。
#
# 逃生门：**三处之间没有逃生门**（一个值三处一致是硬不变量，不许注记放行）。
#   跨端那一半的唯一逃生门 = 台账 `platformAlign.policy` 改 `independent` **且**写非空理由。
#
# 范围外（每次显式打印，不判红；逐条理由写在台账 `notInScope`）：
#   `Core/Cargo.toml` 的内部库版本（领域层 crate 不是发布身份）、`Bench/grid/package.json`
#   （基准台不进安装包）、对侧 `buildVersion`、对侧三个镜像处、版本号的语义（该不该是 0.2.0）、
#   「装出来的 MSI 里读到的版本号」（要真跑 Tauri bundler，本机未做 —— 本判据判的是**源**）、
#   仓外构建产物（`App/dist` / `windows/target` / `*.msi` 均在 `.gitignore` 内）。
#
# 每轮真跑一遍自测（契约侧 L-72 ㈠：「判据写完不对已知改动报红，等于没有」）：
#   **十一例**固定夹具（基线 / 三处各改一处 / 缺 Cargo 版本键 / 权威处第二个同名键 /
#   跨端不等 / 跨端独立策略放行 / 锚点写错 / 判据面缺失 / 末例核对真仓库逐字节未变），
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

$script:LedgerRel = 'windows/Tools/release-version.json'
$script:FloorSites = 4

# ── 解析：JSON 里的顶层键（同一键出现几次都报出来 —— 出现第二次就是又一处副本）────────────
function Get-DoyahJsonKeySites {
  param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Key)
  $values = New-Object System.Collections.ArrayList
  $lines = New-Object System.Collections.ArrayList
  $pattern = '(?m)^[ \t]*"' + [regex]::Escape($Key) + '"[ \t]*:[ \t]*"([^"]*)"[ \t]*,?[ \t]*$'
  foreach ($m in [regex]::Matches($Text, $pattern)) {
    [void]$values.Add($m.Groups[1].Value)
    [void]$lines.Add($Text.Substring(0, $m.Index).Split("`n").Count)
  }
  return @{ Values = $values; Lines = $lines }
}

# ── 解析：TOML 指定段里的键（`[package]` 之外的同名键不算）──────────────────────────────
function Get-DoyahTomlKeySites {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Section,
    [Parameter(Mandatory = $true)][string]$Key
  )
  $want = $Section.Trim().Trim('[', ']').ToLower()
  $rows = $Text -split "`r?`n"
  $section = ''
  $values = New-Object System.Collections.ArrayList
  $lines = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $rows.Count; $i++) {
    $line = $rows[$i].Trim()
    if ($line -match '^\[(.+)\]$') { $section = $Matches[1].Trim().ToLower(); continue }
    if ($section -ne $want) { continue }
    $m = [regex]::Match($line, '^' + [regex]::Escape($Key) + '\s*=\s*"([^"]*)"')
    if ($m.Success) {
      [void]$values.Add($m.Groups[1].Value)
      [void]$lines.Add($i + 1)
    }
  }
  return @{ Values = $values; Lines = $lines }
}

function ConvertTo-DoyahFsPath {
  param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Relative)
  return (Join-Path $Root ($Relative -replace '/', '\'))
}

# ── 取 JSON **顶层**键的值（本机实测坑：mac 侧台账的 authority.keys / mirrors[].keys 里
#    也有同名键 —— 按文本匹配会先撞上嵌套的那个（实测读到 `CFBundleShortVersionString`）。
#    故：**值一律从 JSON 解析出来的顶层取**，文本匹配只用来数「同名键出现了几次」+ 报行号。）──
function Get-DoyahJsonTopValue {
  param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Key)
  $obj = $null
  try { $obj = $Text | ConvertFrom-Json } catch { return $null }
  if ($null -eq $obj) { return $null }
  $value = $obj.$Key
  if ($null -eq $value) { return $null }
  return "$value"
}

# ── 一处比对（权威处与镜像处共用一份逻辑，避免「两处各写一套」）──────────────────────────
function Compare-DoyahReleaseSite {
  param(
    [Parameter(Mandatory = $true)]$Result,
    [Parameter(Mandatory = $true)][string]$RelPath,
    [Parameter(Mandatory = $true)]$Sites,
    $TopValue,
    [Parameter(Mandatory = $true)][string]$Expected,
    [Parameter(Mandatory = $true)][string]$Kind
  )
  $n = @($Sites.Values).Count
  if ($n -eq 0) {
    [void]$Result.Problems.Add(('{0}：{1} 里找不到版本键（缺键就是 mac 侧第 57 轮那个现场：键压根不存在）' -f $Kind, $RelPath))
    return
  }
  if ($n -gt 1) {
    [void]$Result.Problems.Add(('{0}：{1} 里版本键出现 {2} 次（行 {3}）—— 只许一处，否则又是一处副本' -f $Kind, $RelPath, $n, (@($Sites.Lines) -join '、')))
  }
  $Result.Sites++
  $line = @($Sites.Lines)[0]
  if ($null -eq $TopValue -or "$TopValue" -eq '') {
    [void]$Result.Problems.Add(('{0}：{1}:{2} 有同名键（嵌套里的），但**顶层没有版本键** —— 发布产物读到的是顶层那个' -f $Kind, $RelPath, $line))
    return
  }
  $value = "$TopValue"
  if ($value -ne $Expected) {
    [void]$Result.Problems.Add(('{0}：{1}:{2} 的值 = `{3}`，台账 = `{4}`（三处必须逐字一致）' -f $Kind, $RelPath, $line, $value, $Expected))
  }
}

# ── 纯判据：在任意 Root 上跑（自测夹具复用同一份逻辑）───────────────────────────────────
function Test-DoyahReleaseVersion {
  param([Parameter(Mandatory = $true)][string]$Root)

  $Result = @{
    Problems = (New-Object System.Collections.Generic.List[string])
    Notes    = (New-Object System.Collections.Generic.List[string])
    Allowed  = (New-Object System.Collections.Generic.List[string])
    Sites    = 0
    Files    = (New-Object System.Collections.Generic.List[string])
  }

  $ledgerPath = ConvertTo-DoyahFsPath -Root $Root -Relative $script:LedgerRel
  if (-not (Test-Path $ledgerPath)) {
    [void]$Result.Problems.Add(('台账不存在：{0}（判据没有基准 ⇒ 判红，不跳过）' -f $script:LedgerRel))
    return $Result
  }
  try { $ledger = (Read-DoyahTextFile -Path $ledgerPath) | ConvertFrom-Json }
  catch { [void]$Result.Problems.Add(('{0} 不是合法 JSON：{1}' -f $script:LedgerRel, $_.Exception.Message)); return $Result }

  # ── A 台账自洽 ──────────────────────────────────────────────────────────────
  if ($null -eq $ledger.version -or ("$($ledger.version)" -notmatch '^\d+$')) { [void]$Result.Problems.Add('[台账] version 缺失或不是整数') }
  $marketing = [string]$ledger.marketingVersion
  if (-not $marketing) { [void]$Result.Problems.Add('[台账] marketingVersion 缺失或为空') }
  elseif ($marketing -notmatch '^\d+(\.\d+)*$') {
    [void]$Result.Problems.Add(('[台账] marketingVersion 形状不对（期望 `主.次.修订`）：{0}' -f $marketing))
  }
  if (-not $ledger.authority.path) { [void]$Result.Problems.Add('[台账] authority.path 缺失（谁是权威不写清 = 判据没有基准）') }
  elseif (-not $ledger.authority.keys.marketingVersion) { [void]$Result.Problems.Add('[台账] authority.keys.marketingVersion 缺失（取哪个键要写清）') }
  if (-not $ledger.platformAlign.counterpart) { [void]$Result.Problems.Add('[台账] platformAlign.counterpart 缺失（跨端口径没有对象）') }
  $mirrors = @($ledger.mirrors)
  if ($mirrors.Count -lt 1) { [void]$Result.Problems.Add('[台账] mirrors 缺失或为空（三处一致至少要有镜像处）') }
  if (@($ledger.readingRules).Count -lt 1) { [void]$Result.Problems.Add('[台账] readingRules 缺失（怎么读这份台账要写清）') }
  if (@($ledger.anchors).Count -lt 1) { [void]$Result.Problems.Add('[台账] anchors 缺失（文档里的现状声明没人看）') }
  if (@($ledger.notInScope).Count -lt 1) { [void]$Result.Problems.Add('[台账] notInScope 缺失（范围外不写清 = 偷偷放过）') }
  if ($null -eq $ledger.generatedArtifacts) { [void]$Result.Problems.Add('[台账] generatedArtifacts 缺失（没有生成物也要显式写空数组）') }
  elseif (@($ledger.generatedArtifacts).Count -eq 0 -and -not $ledger.generatedArtifactsReason) {
    [void]$Result.Problems.Add('[台账] generatedArtifacts 为空但没写 generatedArtifactsReason（空也要写清为什么空）')
  }
  if ($Result.Problems.Count -gt 0) { return $Result }

  # ── B 三处逐字一致 ──────────────────────────────────────────────────────────
  $authRel = [string]$ledger.authority.path
  $authKey = [string]$ledger.authority.keys.marketingVersion
  $authPath = ConvertTo-DoyahFsPath -Root $Root -Relative $authRel
  if (-not (Test-Path $authPath)) {
    [void]$Result.Problems.Add(('判据面不存在：{0} 不在盘上（工程已在盘上，判据无从下手 ⇒ 空跑判红，不跳过）' -f $authRel))
  }
  else {
    [void]$Result.Files.Add($authRel)
    $text = Read-DoyahTextFile -Path $authPath
    if ($ledger.authority.format -eq 'toml') {
      $sites = Get-DoyahTomlKeySites -Text $text -Section ([string]$ledger.authority.section) -Key $authKey
      $top = $null
      if (@($sites.Values).Count -ge 1) { $top = @($sites.Values)[0] }
    }
    else {
      $sites = Get-DoyahJsonKeySites -Text $text -Key $authKey
      $top = Get-DoyahJsonTopValue -Text $text -Key $authKey
    }
    Compare-DoyahReleaseSite -Result $Result -RelPath $authRel -Sites $sites -TopValue $top -Expected $marketing -Kind '权威处'
  }

  foreach ($mirror in $mirrors) {
    $rel = [string]$mirror.path
    $key = [string]$mirror.keys.marketingVersion
    if (-not $rel -or -not $key) {
      [void]$Result.Problems.Add('[台账] mirrors 里有条目缺 path 或 keys.marketingVersion（哪一处、取哪个键都要写清）')
      continue
    }
    $path = ConvertTo-DoyahFsPath -Root $Root -Relative $rel
    if (-not (Test-Path $path)) {
      [void]$Result.Problems.Add(('镜像处不在盘上：{0}（台账点了名就必须在，受检面不许静默缩小）' -f $rel))
      continue
    }
    [void]$Result.Files.Add($rel)
    $text = Read-DoyahTextFile -Path $path
    if ($mirror.format -eq 'toml') {
      $sites = Get-DoyahTomlKeySites -Text $text -Section ([string]$mirror.section) -Key $key
      $top = $null
      if (@($sites.Values).Count -ge 1) { $top = @($sites.Values)[0] }
    }
    else {
      $sites = Get-DoyahJsonKeySites -Text $text -Key $key
      $top = Get-DoyahJsonTopValue -Text $text -Key $key
    }
    Compare-DoyahReleaseSite -Result $Result -RelPath $rel -Sites $sites -TopValue $top -Expected $marketing -Kind '镜像处'
  }

  # ── C 与 mac 侧发布台账同源 ──────────────────────────────────────────────────
  $cpRel = [string]$ledger.platformAlign.counterpart
  $cpField = [string]$ledger.platformAlign.counterpartField
  if (-not $cpField) { $cpField = 'marketingVersion' }
  $cpPath = ConvertTo-DoyahFsPath -Root $Root -Relative $cpRel
  if (-not (Test-Path $cpPath)) {
    [void]$Result.Problems.Add(('跨端台账不在盘上：{0}（受检面不许静默缩小）' -f $cpRel))
  }
  else {
    [void]$Result.Files.Add($cpRel)
    $cpText = Read-DoyahTextFile -Path $cpPath
    $cpValue = Get-DoyahJsonTopValue -Text $cpText -Key $cpField
    $Result.Sites++
    if ($null -eq $cpValue -or $cpValue -eq '') {
      [void]$Result.Problems.Add(('{0} 的**顶层**读不到 {1}（跨端那一半没有基准）' -f $cpRel, $cpField))
    }
    else {
      $policy = [string]$ledger.platformAlign.policy
      if ($policy -eq 'independent') {
        $reason = ([string]$ledger.platformAlign.reason).Trim()
        if (-not $reason) {
          [void]$Result.Problems.Add('跨端口径 = independent 但 platformAlign.reason 为空 ⇒ 仍判红（放行必须给理由）')
        }
        else {
          [void]$Result.Allowed.Add(('跨端不同源（platformAlign.policy = independent）：本侧 {0} / 对侧 {1} —— {2}' -f $marketing, $cpValue, $reason))
        }
      }
      elseif ($cpValue -ne $marketing) {
        [void]$Result.Problems.Add(('跨端不同源：本侧台账 = `{0}`，mac 侧台账 {1} 的 {2} = `{3}`（同一产品的发布版本号两端必须同源；对侧升版则本侧三处跟版）' -f $marketing, $cpRel, $cpField, $cpValue))
      }
    }
    $cpBuild = Get-DoyahJsonTopValue -Text $cpText -Key 'buildVersion'
    if ($cpBuild) {
      [void]$Result.Notes.Add(('范围外（不跟随）：对侧 buildVersion = `{0}` —— 各端构建号各自递增' -f $cpBuild))
    }
  }

  # ── 锚点：文档里的现状声明逐处对账 ─────────────────────────────────────────────
  foreach ($anchor in @($ledger.anchors)) {
    $rel = [string]$anchor.path
    $path = ConvertTo-DoyahFsPath -Root $Root -Relative $rel
    if (-not (Test-Path $path)) {
      [void]$Result.Problems.Add(('锚点文件不在盘上：{0}（受检面不许静默缩小）' -f $rel))
      continue
    }
    try { $rx = New-Object System.Text.RegularExpressions.Regex ([string]$anchor.regex), ([System.Text.RegularExpressions.RegexOptions]::Multiline) }
    catch { [void]$Result.Problems.Add(('[台账] 锚点正则不合法（{0}）：{1}' -f $rel, $_.Exception.Message)); continue }
    $captures = @($anchor.captures)
    if (($rx.GetGroupNumbers().Count - 1) -ne $captures.Count) {
      [void]$Result.Problems.Add(('[台账] 锚点 {0} 的正则有 {1} 个捕获组、captures 有 {2} 个（对不上）' -f $rel, ($rx.GetGroupNumbers().Count - 1), $captures.Count))
      continue
    }
    $text = Read-DoyahTextFile -Path $path
    $hits = $rx.Matches($text)
    $min = 1
    if ($anchor.minSites) { $min = [int]$anchor.minSites }
    if ($hits.Count -lt $min) {
      [void]$Result.Problems.Add(('锚点 {0}（{1}）命中 {2} 处，少于 minSites {3} —— 现状声明被删了 / 改写了？' -f $rel, ([string]$anchor.note), $hits.Count, $min))
      continue
    }
    foreach ($hit in $hits) {
      for ($i = 0; $i -lt $captures.Count; $i++) {
        $Result.Sites++
        $field = [string]$captures[$i]
        $value = $hit.Groups[$i + 1].Value
        $expected = [string]$ledger.$field
        if ($value -ne $expected) {
          $line = $text.Substring(0, $hit.Index).Split("`n").Count
          [void]$Result.Problems.Add(('{0}:{1} 写的是 `{2}`，台账 {3} = `{4}`' -f $rel, $line, $value, $field, $expected))
        }
      }
    }
  }

  # ── D 空跑防护 ──────────────────────────────────────────────────────────────
  if ($Result.Sites -lt $script:FloorSites) {
    [void]$Result.Problems.Add(('空跑防护：全部比对点只有 {0} 处（少于下限 {1}）—— 判据被掏空了？' -f $Result.Sites, $script:FloorSites))
  }
  return $Result
}

# ── 自测夹具 ────────────────────────────────────────────────────────────────────
function Write-DoyahFixtureText {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
  [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function New-DoyahReleaseFixture {
  param(
    [Parameter(Mandatory = $true)][string]$Dir,
    [string]$Marketing = '0.2.0',
    [string]$AuthorityValue = '',
    [string]$PackageValue = '',
    [string]$CargoValue = '',
    [string]$CounterpartValue = '',
    [string]$AnchorValue = '',
    [string]$Policy = 'equal',
    [string]$AlignReason = '自测夹具：同一产品的发布版本号两端必须同源',
    [switch]$OmitAuthorityFile,
    [switch]$DropCargoVersion,
    [switch]$DuplicateAuthorityKey
  )
  if (-not $AuthorityValue) { $AuthorityValue = $Marketing }
  if (-not $PackageValue) { $PackageValue = $Marketing }
  if (-not $CargoValue) { $CargoValue = $Marketing }
  if (-not $CounterpartValue) { $CounterpartValue = $Marketing }
  if (-not $AnchorValue) { $AnchorValue = $Marketing }

  foreach ($sub in @('windows\App\src-tauri', 'windows\Tools', 'Docs', 'Scripts')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Dir $sub) | Out-Null
  }

  $tauriExtra = ''
  if ($DuplicateAuthorityKey) { $tauriExtra = ",`n  `"plugins`": {`n    `"updater`": {`n      `"version`": `"9.9.9`"`n    }`n  }" }
  $tauri = "{`n  `"productName`": `"Doyah Studio`",`n  `"version`": `"__A__`",`n  `"identifier`": `"studio.doyah.desktop.windows`"__X__`n}`n".Replace('__A__', $AuthorityValue).Replace('__X__', $tauriExtra)
  if (-not $OmitAuthorityFile) {
    Write-DoyahFixtureText -Path (Join-Path $Dir 'windows\App\src-tauri\tauri.conf.json') -Text $tauri
  }

  $pkg = "{`n  `"name`": `"fixture-shell`",`n  `"version`": `"__P__`",`n  `"private`": true`n}`n".Replace('__P__', $PackageValue)
  Write-DoyahFixtureText -Path (Join-Path $Dir 'windows\App\package.json') -Text $pkg

  if ($DropCargoVersion) {
    $cargo = "[package]`nname = `"fixture-shell`"`nedition = `"2021`"`n`n[dependencies]`nserde = { version = `"1`", features = [`"derive`"] }`n"
  }
  else {
    $cargo = "[package]`nname = `"fixture-shell`"`nversion = `"__C__`"`nedition = `"2021`"`n`n[dependencies]`nserde = { version = `"1`", features = [`"derive`"] }`n".Replace('__C__', $CargoValue)
  }
  Write-DoyahFixtureText -Path (Join-Path $Dir 'windows\App\src-tauri\Cargo.toml') -Text $cargo

  $counterpart = "{`n  `"version`": 1,`n  `"marketingVersion`": `"__V__`",`n  `"buildVersion`": `"2`"`n}`n".Replace('__V__', $CounterpartValue)
  Write-DoyahFixtureText -Path (Join-Path $Dir 'Scripts\release-version.json') -Text $counterpart

  $ledger = @'
{
  "version": 1,
  "marketingVersion": "__M__",
  "authority": { "path": "windows/App/src-tauri/tauri.conf.json", "kind": "夹具", "format": "json", "keys": { "marketingVersion": "version" } },
  "mirrors": [
    { "path": "windows/App/package.json", "kind": "夹具", "format": "json", "keys": { "marketingVersion": "version" } },
    { "path": "windows/App/src-tauri/Cargo.toml", "kind": "夹具", "format": "toml", "section": "[package]", "keys": { "marketingVersion": "version" } }
  ],
  "generatedArtifacts": [],
  "generatedArtifactsReason": "夹具：无仓内生成物",
  "platformAlign": { "policy": "__POL__", "counterpart": "Scripts/release-version.json", "counterpartField": "marketingVersion", "reason": "__REASON__" },
  "readingRules": ["夹具"],
  "anchors": [
    { "path": "Docs/概要设计.md", "regex": "发布产物版本号 `([0-9]+\\.[0-9]+\\.[0-9]+)`（三处逐字一致）", "captures": ["marketingVersion"], "minSites": 1, "note": "夹具" },
    { "path": "windows/README.md", "regex": "发布产物版本号 `([0-9]+\\.[0-9]+\\.[0-9]+)`", "captures": ["marketingVersion"], "minSites": 1, "note": "夹具" }
  ],
  "notInScope": ["夹具"]
}
'@
  $ledger = $ledger.Replace('__M__', $Marketing).Replace('__POL__', $Policy).Replace('__REASON__', $AlignReason)
  Write-DoyahFixtureText -Path (Join-Path $Dir 'windows\Tools\release-version.json') -Text $ledger

  $hld = "| 闸门 | 判据 |`n|---|---|`n| 生成物一致性 | 发布产物版本号 ``__AV__``（三处逐字一致）|`n".Replace('__AV__', $AnchorValue)
  Write-DoyahFixtureText -Path (Join-Path $Dir 'Docs\概要设计.md') -Text $hld
  $readme = "- 发布产物版本号 ``__AV__``：夹具`n".Replace('__AV__', $AnchorValue)
  Write-DoyahFixtureText -Path (Join-Path $Dir 'windows\README.md') -Text $readme
}

function Get-DoyahReleaseFingerprint {
  param([Parameter(Mandatory = $true)][string[]]$Paths)
  $sb = New-Object System.Text.StringBuilder
  foreach ($p in $Paths) {
    if (Test-Path $p) {
      $h = (Get-FileHash -Path $p -Algorithm SHA256).Hash
      [void]$sb.Append($p).Append(':').Append($h).Append("`n")
    }
    else { [void]$sb.Append($p).Append(':MISSING').Append("`n") }
  }
  return $sb.ToString()
}

# ── 主判据 ──────────────────────────────────────────────────────────────────────
Write-Host ('== 发布产物版本号「一个值、三处逐字一致」（三处 + 与 mac 侧发布台账同源）（{0}）' -f $RepoRoot)
$main = Test-DoyahReleaseVersion -Root $RepoRoot
foreach ($n in $main.Notes) { Write-Host ('    ℹ️ ' + $n) }
if ($main.Allowed.Count -gt 0) {
  Write-Host '   放行的行（跨端逃生门 platformAlign.policy = independent，逐条列出）：'
  foreach ($a in $main.Allowed) { Write-Host ('     · ' + $a) }
}
if ($main.Problems.Count -gt 0) {
  foreach ($p in $main.Problems) { Write-DoyahFail $p }
}
else {
  Write-DoyahPass (('发布产物版本号三处逐字一致 + 与 mac 侧发布台账同源（比对点 {0} 处；受检 {1} 份文件）' -f $main.Sites, $main.Files.Count))
  foreach ($f in $main.Files) { Write-Host ('       · ' + $f) }
}

# ── 自测（固定夹具十一例；夹具一律在临时目录，真仓库只被读、只被核对）────────────────────
$selfFailed = 0
if (-not $SkipSelfTest) {
  Write-Host '  ── 自测（固定夹具，临时目录）'
  $realFiles = @(
    (Join-Path $RepoRoot 'windows\App\src-tauri\tauri.conf.json'),
    (Join-Path $RepoRoot 'windows\App\package.json'),
    (Join-Path $RepoRoot 'windows\App\src-tauri\Cargo.toml'),
    (Join-Path $RepoRoot ($script:LedgerRel -replace '/', '\')),
    (Join-Path $RepoRoot 'Scripts\release-version.json')
  )
  $before = Get-DoyahReleaseFingerprint -Paths $realFiles
  $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('doyah-release-version-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
  $caseCount = 0
  $caseOk = 0
  try {
    # 例 1：基线（三处一致 + 跨端同源 + 锚点正确）⇒ 期望 0 判红
    $caseCount++
    $f = Join-Path $tmpRoot 'case1'
    New-DoyahReleaseFixture -Dir $f
    $r = Test-DoyahReleaseVersion -Root $f
    if ($r.Problems.Count -eq 0 -and $r.Sites -ge 6) { $caseOk++; Write-DoyahPass ('自测 1/11 基线：干净夹具通过（比对点 {0} 处）' -f $r.Sites) }
    else { $selfFailed++; Write-DoyahFail ('自测 1/11 基线：期望 0 判红且比对点 ≥ 6，实得 {0} 条判红 / {1} 处：{2}' -f $r.Problems.Count, $r.Sites, ($r.Problems -join ' | ')) }

    # 例 2：只改 package.json ⇒ 期望判红并点名
    $caseCount++
    $f = Join-Path $tmpRoot 'case2'
    New-DoyahReleaseFixture -Dir $f -PackageValue '9.9.9'
    $r = Test-DoyahReleaseVersion -Root $f
    if (@($r.Problems | Where-Object { $_ -like '*package.json*' -and $_ -like '*9.9.9*' }).Count -ge 1) { $caseOk++; Write-DoyahPass '自测 2/11 镜像处（package.json）：改一处 ⇒ 判红并点名' }
    else { $selfFailed++; Write-DoyahFail ('自测 2/11 镜像处：期望点名 package.json 与 9.9.9，实得：{0}' -f ($r.Problems -join ' | ')) }

    # 例 3：只改权威处 ⇒ 期望判红并点名
    $caseCount++
    $f = Join-Path $tmpRoot 'case3'
    New-DoyahReleaseFixture -Dir $f -AuthorityValue '9.9.9'
    $r = Test-DoyahReleaseVersion -Root $f
    if (@($r.Problems | Where-Object { $_ -like '*tauri.conf.json*' -and $_ -like '*9.9.9*' }).Count -ge 1) { $caseOk++; Write-DoyahPass '自测 3/11 权威处（tauri.conf.json）：改一处 ⇒ 判红并点名' }
    else { $selfFailed++; Write-DoyahFail ('自测 3/11 权威处：期望点名 tauri.conf.json 与 9.9.9，实得：{0}' -f ($r.Problems -join ' | ')) }

    # 例 4：只改 Cargo.toml ⇒ 期望判红并点名
    $caseCount++
    $f = Join-Path $tmpRoot 'case4'
    New-DoyahReleaseFixture -Dir $f -CargoValue '9.9.9'
    $r = Test-DoyahReleaseVersion -Root $f
    if (@($r.Problems | Where-Object { $_ -like '*Cargo.toml*' -and $_ -like '*9.9.9*' }).Count -ge 1) { $caseOk++; Write-DoyahPass '自测 4/11 镜像处（Cargo.toml）：改一处 ⇒ 判红并点名' }
    else { $selfFailed++; Write-DoyahFail ('自测 4/11 镜像处：期望点名 Cargo.toml 与 9.9.9，实得：{0}' -f ($r.Problems -join ' | ')) }

    # 例 5：Cargo.toml 缺版本键（= mac 侧第 57 轮那个现场）⇒ 期望判红
    $caseCount++
    $f = Join-Path $tmpRoot 'case5'
    New-DoyahReleaseFixture -Dir $f -DropCargoVersion
    $r = Test-DoyahReleaseVersion -Root $f
    if (@($r.Problems | Where-Object { $_ -like '*Cargo.toml*' -and $_ -like '*找不到版本键*' }).Count -ge 1) { $caseOk++; Write-DoyahPass '自测 5/11 缺键：`[package]` 没有 version ⇒ 判红（缺键不是「跳过」）' }
    else { $selfFailed++; Write-DoyahFail ('自测 5/11 缺键：期望点名「找不到版本键」，实得：{0}' -f ($r.Problems -join ' | ')) }

    # 例 6：权威处出现第二个同名键 ⇒ 期望判红
    $caseCount++
    $f = Join-Path $tmpRoot 'case6'
    New-DoyahReleaseFixture -Dir $f -DuplicateAuthorityKey
    $r = Test-DoyahReleaseVersion -Root $f
    if (@($r.Problems | Where-Object { $_ -like '*出现 2 次*' }).Count -ge 1) { $caseOk++; Write-DoyahPass '自测 6/11 同名键第二处：权威处出现第二个 `version` ⇒ 判红' }
    else { $selfFailed++; Write-DoyahFail ('自测 6/11 同名键第二处：期望点名「出现 2 次」，实得：{0}' -f ($r.Problems -join ' | ')) }

    # 例 7：跨端不等（policy = equal）⇒ 期望判红并两边报值
    $caseCount++
    $f = Join-Path $tmpRoot 'case7'
    New-DoyahReleaseFixture -Dir $f -CounterpartValue '9.9.9'
    $r = Test-DoyahReleaseVersion -Root $f
    if (@($r.Problems | Where-Object { $_ -like '*跨端不同源*' -and $_ -like '*9.9.9*' }).Count -ge 1) { $caseOk++; Write-DoyahPass '自测 7/11 跨端不等：mac 侧台账不同值 ⇒ 判红并两边报值' }
    else { $selfFailed++; Write-DoyahFail ('自测 7/11 跨端不等：期望点名「跨端不同源」，实得：{0}' -f ($r.Problems -join ' | ')) }

    # 例 8：跨端独立策略 + 非空理由 ⇒ 期望通过 + 1 条放行
    $caseCount++
    $f = Join-Path $tmpRoot 'case8'
    New-DoyahReleaseFixture -Dir $f -CounterpartValue '9.9.9' -Policy 'independent'
    $r = Test-DoyahReleaseVersion -Root $f
    if ($r.Problems.Count -eq 0 -and $r.Allowed.Count -ge 1) { $caseOk++; Write-DoyahPass ('自测 8/11 跨端逃生门：policy = independent + 理由非空 ⇒ 放行并逐条打印（{0} 条）' -f $r.Allowed.Count) }
    else { $selfFailed++; Write-DoyahFail ('自测 8/11 跨端逃生门：期望放行 1 条，实得判红 {0} 条 / 放行 {1} 条' -f $r.Problems.Count, $r.Allowed.Count) }

    # 例 9：锚点写错 ⇒ 期望判红并点名文件:行号
    $caseCount++
    $f = Join-Path $tmpRoot 'case9'
    New-DoyahReleaseFixture -Dir $f -AnchorValue '9.9.9'
    $r = Test-DoyahReleaseVersion -Root $f
    if (@($r.Problems | Where-Object { $_ -like '*概要设计.md:*' }).Count -ge 1) { $caseOk++; Write-DoyahPass '自测 9/11 锚点：文档里的现状声明写错 ⇒ 判红并点名 文件:行号' }
    else { $selfFailed++; Write-DoyahFail ('自测 9/11 锚点：期望点名 概要设计.md:行号，实得：{0}' -f ($r.Problems -join ' | ')) }

    # 例 10：判据面缺失（权威处不在盘上）⇒ 期望判红（不是跳过、不是通过）
    $caseCount++
    $f = Join-Path $tmpRoot 'case10'
    New-DoyahReleaseFixture -Dir $f -OmitAuthorityFile
    $r = Test-DoyahReleaseVersion -Root $f
    if (@($r.Problems | Where-Object { $_ -like '*判据面不存在*' }).Count -ge 1) { $caseOk++; Write-DoyahPass '自测 10/11 空跑：权威处不在盘上 ⇒ 判红（空跑不许通过）' }
    else { $selfFailed++; Write-DoyahFail ('自测 10/11 空跑：期望点名「判据面不存在」，实得：{0}' -f ($r.Problems -join ' | ')) }

    # 例 11（末例）：真仓库五份文件逐字节未变 + 真仓库实跑绿
    $caseCount++
    $after = Get-DoyahReleaseFingerprint -Paths $realFiles
    $real = Test-DoyahReleaseVersion -Root $RepoRoot
    $unchangedText = '未变'
    if ($before -ne $after) { $unchangedText = '发生变化 —— 夹具不该碰真仓库' }
    if ($before -eq $after -and $real.Problems.Count -eq 0) { $caseOk++; Write-DoyahPass ('自测 11/11 末例：自测前后真仓库 {0} 份文件 sha256 逐字节一致 + 真仓库实跑绿' -f $realFiles.Count) }
    else { $selfFailed++; Write-DoyahFail (('自测 11/11 末例：真仓库{0}（判红 {1} 条：{2}）' -f $unchangedText, $real.Problems.Count, ($real.Problems -join ' | '))) }
  }
  finally {
    Remove-Item -Path $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Host ('   自测：{0}/{1} 例通过' -f $caseOk, $caseCount)
}

if ($main.Problems.Count -gt 0 -or $selfFailed -gt 0) {
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}
Write-DoyahResult -Status PASS -Code 0
exit 0
