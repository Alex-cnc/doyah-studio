# Doyah Studio · Windows 侧闸门 ① 构建入口（platform/windows/Tools/build.ps1）
#
# 对应 §8.3.1 ①「构建入口」：一条命令产出可运行产物。
# 技术栈（2026-09-28 需求提出者开工令换栈）：**Rust 后端 + Tauri 2 / Vue 3 / TypeScript 前端**；
# 原 .NET（C# / WPF / xUnit）路线作废 ⇒ 本脚本改为 cargo（Rust 工作区 platform/windows/Cargo.toml）
# 加前端 vite 构建。
#
# 现阶段的诚实行为（**前置未就位就报「跳过 + 原因」，绝不假装成功**）：
#   · 本机找不到 cargo ⇒ 跳过（栈 = Rust；rustup 装在 %USERPROFILE%\.cargo\bin）；
#   · platform/windows\Cargo.toml 不存在 ⇒ 跳过（本侧工程未建）；
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

$windowsDir = Join-Path $RepoRoot 'platform/windows'
$manifest = Join-Path $windowsDir 'Cargo.toml'

$cargo = Find-DoyahCargo
if (-not $cargo) {
  Write-DoyahSkip -Text "构建：cargo build" -Reason "本机找不到 cargo（§8.5.1 栈 = Rust；rustup 装在 %USERPROFILE%\.cargo\bin，本脚本按该路径查找）"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}
Write-Host ("    cargo：{0}" -f $cargo)

if (-not (Test-Path $manifest)) {
  Write-DoyahSkip -Text "构建：cargo build" -Reason "Windows 侧 Rust 工程未建（platform/windows\Cargo.toml 不存在）"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

# 前端半（**必须在 cargo 之前**）：Tauri 在编译期把 `frontendDist`（= platform/windows\App\dist）嵌进产物，
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

Write-Host ("    $ cargo build --release --workspace --features doyah-studio-shell/custom-protocol（workdir={0}）" -f $windowsDir)
Push-Location $windowsDir
$env:RUSTUP_AUTO_INSTALL = '0'
# **必须带 `custom-protocol` 特性**：Tauri 2 的 `build.rs` 里 `let dev = !custom_protocol;`
# （源码依据 = tauri 2.x `build.rs`），不开它编出来的二进制**会去连 `devUrl`**（http://localhost:5274），
# 盘上没有 dev server 时是空窗口 —— 即「构建入口产出了跑不起来的产物」。
# 实测（2026-09-28 第 28 轮）：不带它编出来的 target\release\doyah-studio.exe，页面 URL 是
# `http://localhost:5274/`（空）；带上之后是 `http://tauri.localhost/`（前端产物已嵌进二进制）。
& $cargo build --release --workspace --features doyah-studio-shell/custom-protocol
$rc = $LASTEXITCODE
Pop-Location
if ($rc -ne 0) {
  Write-DoyahFail ("cargo build 失败（退出码 {0}）" -f $rc)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

# 产物目录：**认 cargo 的 CARGO_TARGET_DIR**（2026-10-02 修）。
# 由头：脚本原先写死 `platform/windows\target\release`，而本机的会话文件沙箱**拒绝仓内写入** ⇒
# 构建只能把产物指到仓外（`CARGO_TARGET_DIR` 指别处）。于是衍生判据去读**仓里那份旧二进制**
# （2026-10-02 09:46 那次），把一次**成功的生产形态构建**判成"前端产物没编进去" —— 假红，
# 而且是最坏的一种：真的检出手段指向了错的对象。判据沿 cargo 自己的解析顺序取值。
$envTarget = $env:CARGO_TARGET_DIR
if ($envTarget) {
  $targetRoot = if ([System.IO.Path]::IsPathRooted($envTarget)) { $envTarget } else { Join-Path $windowsDir $envTarget }
} else {
  $targetRoot = Join-Path $windowsDir 'target'
}
$outDir = Join-Path $targetRoot 'release'
$artifacts = @(Get-ChildItem -Path $outDir -Filter '*.exe' -File -ErrorAction SilentlyContinue)
$targetNote = if ($envTarget) { '（来自 CARGO_TARGET_DIR）' } else { '' }
Write-DoyahPass ("Rust 产物目录：{0}{1}（{2} 个可执行文件）" -f $outDir, $targetNote, $artifacts.Count)

# 衍生判据：**产物是不是生产形态**。上面的特性开关一旦被丢掉（改脚本、换机器、抄命令），
# 二进制照样编得出来，只是它里面没有前端产物 ⇒ 这里用「前端产物的文件名是否出现在二进制里」
# 机械判（构建时资源名随资源一起进二进制；实测生产形态命中、dev 形态 0 命中）。
$assetDir = Join-Path $windowsDir 'App\dist\assets'
$shellExe = Join-Path $outDir 'doyah-studio.exe'
if ((Test-Path $assetDir) -and (Test-Path $shellExe)) {
  $assets = @(Get-ChildItem -Path $assetDir -File)
  if ($assets.Count -eq 0) {
    Write-DoyahFail "前端产物目录是空的（App\dist\assets 一份都没有）—— 构建顺序错了或 vite build 没跑"
    Write-DoyahResult -Status FAIL -Code 1
    exit 1
  }
  # Latin1 = 逐字节保真（不丢高位字节），二进制里搜 ASCII 文件名够用
  $bytes = [System.IO.File]::ReadAllBytes($shellExe)
  $text = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
  $missing = @($assets | Where-Object { $text.IndexOf($_.Name) -lt 0 } | ForEach-Object { $_.Name })
  if ($missing.Count -gt 0) {
    Write-DoyahFail ("产物不是生产形态：前端产物没被编进可执行文件（缺 {0}）—— 构建必须带 custom-protocol 特性" -f ($missing -join '、'))
    Write-DoyahResult -Status FAIL -Code 1
    exit 1
  }
  Write-DoyahPass ("生产形态核对：前端产物 {0} 份（{1}）已编进 {2}" -f $assets.Count, (($assets | ForEach-Object { $_.Name }) -join '、'), (Split-Path $shellExe -Leaf))
}

Write-DoyahResult -Status PASS -Code 0
exit 0
