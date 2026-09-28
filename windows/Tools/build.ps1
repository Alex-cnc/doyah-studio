# Doyah Studio · Windows 侧闸门 ① 构建入口（windows/Tools/build.ps1）
#
# 对应 §8.3.1 ①「构建入口」：一条命令产出可运行产物。
# 技术栈（2026-09-28 需求提出者开工令换栈）：**Rust 后端 + Tauri 2 / Vue 3 / TypeScript 前端**；
# 原 .NET（C# / WPF / xUnit）路线作废 ⇒ 本脚本改为 cargo（Rust 工作区 windows/Cargo.toml）
# 加前端 vite 构建。
#
# 现阶段的诚实行为（**前置未就位就报「跳过 + 原因」，绝不假装成功**）：
#   · 本机找不到 cargo ⇒ 跳过（栈 = Rust；rustup 装在 %USERPROFILE%\.cargo\bin）；
#   · windows\Cargo.toml 不存在 ⇒ 跳过（本侧工程未建）；
#   · 前端依赖未装（Bench 下没有 node_modules）⇒ **Rust 半照跑**，前端半如实打印「未构建」
#     —— 不作「已通过」计，也不因此判红（缺的是一句 npm install，属环境不属代码）。
#
# 退出码：0 = 产物已产出 / 1 = 判红 / 2 = 跳过

param(
  [string]$RepoRoot = '',
  [string]$Configuration = 'Release'
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

# 判红与否只由退出码决定（PS 5.1 在 $ErrorActionPreference='Stop' 下会把原生命令写到 stderr 的
# 任意一行当终止错误 —— cargo 的进度行走 stderr，实测会假红；stderr 照原样打印，不吞不静默）。
$ErrorActionPreference = 'Continue'

Write-Host ("== ① 构建入口（{0}；{1}）" -f $RepoRoot, $Configuration)

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
  Write-DoyahSkip -Text "构建：cargo build" -Reason "本机找不到 cargo（§8.5.1 栈 = Rust；rustup 装在 %USERPROFILE%\.cargo\bin，本脚本按该路径查找）"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}
Write-Host ("    cargo：{0}" -f $cargo)

if (-not (Test-Path $manifest)) {
  Write-DoyahSkip -Text "构建：cargo build" -Reason "Windows 侧 Rust 工程未建（windows\Cargo.toml 不存在）"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

# 前端半（**必须在 cargo 之前**）：Tauri 在编译期把 `frontendDist`（= windows\App\dist）嵌进产物，
# 前端产物不在盘上时 Rust 半会直接失败 ⇒ 顺序不能颠倒（实测：先 cargo 后 vite 会红在建产物这一步）。
# 两个前端各自独立：Bench\grid = 压力基准台；App = 产品外壳。缺依赖可见、不判红（缺的是 npm install）。
function Invoke-DoyahFrontend {
  param([string]$Dir, [string]$Label)
  if (-not (Test-Path (Join-Path $Dir 'package.json'))) { return }
  if (-not (Test-Path (Join-Path $Dir 'node_modules'))) {
    Write-Host ("    {0}：node_modules 未装 ⇒ 未构建（先 cd {1}; npm install）" -f $Label, $Dir)
    return
  }
  $npm = Get-Command npm -ErrorAction SilentlyContinue
  if (-not $npm) {
    Write-Host ("    {0}：本机找不到 npm ⇒ 未构建" -f $Label)
    return
  }
  Write-Host ("    $ npm run build（workdir={0}）" -f $Dir)
  Push-Location $Dir
  & $npm.Source run build
  $rc = $LASTEXITCODE
  Pop-Location
  if ($rc -ne 0) {
    Write-DoyahFail ("{0} 的 vite build 失败（退出码 {1}）" -f $Label, $rc)
    Write-DoyahResult -Status FAIL -Code 1
    exit 1
  }
  Write-DoyahPass ("{0} 产物：{1}" -f $Label, (Join-Path $Dir 'dist'))
}

Invoke-DoyahFrontend -Dir (Join-Path $windowsDir 'Bench\grid') -Label '基准台前端（Bench\grid）'
Invoke-DoyahFrontend -Dir (Join-Path $windowsDir 'App') -Label '外壳前端（App）'

Write-Host ("    $ cargo build --release --workspace（workdir={0}）" -f $windowsDir)
Push-Location $windowsDir
$env:RUSTUP_AUTO_INSTALL = '0'
& $cargo build --release --workspace
$rc = $LASTEXITCODE
Pop-Location
if ($rc -ne 0) {
  Write-DoyahFail ("cargo build 失败（退出码 {0}）" -f $rc)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$outDir = Join-Path $windowsDir 'target\release'
$artifacts = @(Get-ChildItem -Path $outDir -Filter '*.exe' -File -ErrorAction SilentlyContinue)
Write-DoyahPass ("Rust 产物目录：{0}（{1} 个可执行文件）" -f $outDir, $artifacts.Count)

Write-DoyahResult -Status PASS -Code 0
exit 0
