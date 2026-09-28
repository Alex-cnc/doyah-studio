# Doyah Studio · Windows 侧闸门 ② 单测（windows/Tools/test.ps1）
#
# 对应 §8.3.1 ②「单测」：等价覆盖 + 「GUI / 平台依赖不得进入领域层」（见 check-core-boundary.ps1）。
# 技术栈（2026-09-28 开工令换栈）：Rust 侧 cargo test（workspace）加前端 vitest run。
# 前置未就位 ⇒ 跳过 + 写明原因，不假装通过。
#
# 退出码：0 = 全绿 / 1 = 判红（有失败用例）/ 2 = 跳过

param(
  [string]$RepoRoot = '',
  [string]$Configuration = 'Release'
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

# 判红与否只由退出码决定（cargo / npm 的进度行走 stderr；PS 5.1 在 Stop 下会把它当终止错误 ⇒ 假红）
$ErrorActionPreference = 'Continue'

Write-Host ("== ② 单测：cargo test + vitest（{0}）" -f $RepoRoot)

function Find-DoyahCargo {
  $cands = @()
  if ($env:CARGO_HOME) { $cands += (Join-Path $env:CARGO_HOME 'bin\cargo.exe') }
  if ($env:USERPROFILE) { $cands += (Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe') }
  $cands += 'C:\Users\Alex\.cargo\bin\cargo.exe'
  foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  $cmd = Get-Command cargo -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return ''
}

$windowsDir = Join-Path $RepoRoot 'windows'
$manifest = Join-Path $windowsDir 'Cargo.toml'

$cargo = Find-DoyahCargo
if (-not $cargo) {
  Write-DoyahSkip -Text "单测：cargo test" -Reason "本机找不到 cargo（§8.5.1 栈 = Rust；rustup 装在 %USERPROFILE%\.cargo\bin）"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}
Write-Host ("    cargo：{0}" -f $cargo)

if (-not (Test-Path $manifest)) {
  Write-DoyahSkip -Text "单测：cargo test" -Reason "Windows 侧 Rust 工程未建（windows\Cargo.toml 不存在）"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

Push-Location $windowsDir
$env:RUSTUP_AUTO_INSTALL = '0'
$env:PYTHONDONTWRITEBYTECODE = '1'
Write-Host ("    $ cargo test --workspace（workdir={0}）" -f $windowsDir)
$out = & $cargo test --workspace 2>&1
$rc = $LASTEXITCODE
Pop-Location
$out | Select-Object -Last 12 | ForEach-Object { Write-Host ("    {0}" -f $_) }
if ($rc -ne 0) {
  Write-DoyahFail ("cargo test 失败（退出码 {0}）" -f $rc)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$lines = @($out | Where-Object { $_ -match 'test result:' })
$passed = 0
$failedCount = 0
foreach ($l in $lines) {
  if ($l -match '(\d+) passed') { $passed += [int]$Matches[1] }
  if ($l -match '(\d+) failed') { $failedCount += [int]$Matches[1] }
}
if ($passed -eq 0) {
  Write-DoyahFail "cargo test 没有任何用例（空跑不许通过）"
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}
Write-DoyahPass ("Rust 单测：通过 {0} / 失败 {1}" -f $passed, $failedCount)

# 前端半：依赖已装才跑（缺依赖可见、不判红）
$gridDir = Join-Path $windowsDir 'Bench\grid'
if ((Test-Path (Join-Path $gridDir 'package.json')) -and (Test-Path (Join-Path $gridDir 'node_modules'))) {
  $npm = Get-Command npm -ErrorAction SilentlyContinue
  if ($npm) {
    Push-Location $gridDir
    $out2 = & $npm.Source test 2>&1
    $rc2 = $LASTEXITCODE
    Pop-Location
    $out2 | Select-Object -Last 6 | ForEach-Object { Write-Host ("    {0}" -f $_) }
    if ($rc2 -ne 0) {
      Write-DoyahFail ("vitest 失败（退出码 {0}）" -f $rc2)
      Write-DoyahResult -Status FAIL -Code 1
      exit 1
    }
    Write-DoyahPass "前端单测：vitest run 全绿"
  }
}
else {
  Write-Host "    前端：Bench\grid 依赖未装 ⇒ 前端单测未跑（先 npm install；Rust 半已通过）"
}

# 前端半 · 产品外壳（windows\App）：外壳自己的 vitest（含令牌生成器 / 棘轮的自测）
$appDir = Join-Path $windowsDir 'App'
if ((Test-Path (Join-Path $appDir 'package.json')) -and (Test-Path (Join-Path $appDir 'node_modules'))) {
  $npm = Get-Command npm -ErrorAction SilentlyContinue
  if ($npm) {
    Push-Location $appDir
    $out3 = & $npm.Source test 2>&1
    $rc3 = $LASTEXITCODE
    Pop-Location
    $out3 | Select-Object -Last 8 | ForEach-Object { Write-Host ("    {0}" -f $_) }
    if ($rc3 -ne 0) {
      Write-DoyahFail ("外壳 vitest 失败（退出码 {0}）" -f $rc3)
      Write-DoyahResult -Status FAIL -Code 1
      exit 1
    }
    Write-DoyahPass "外壳单测：vitest run 全绿"
  }
}
else {
  Write-Host "    外壳前端：windows\App 依赖未装 ⇒ 外壳单测未跑（先 cd windows\App; npm install）"
}

Write-DoyahResult -Status PASS -Code 0
exit 0
