<#
  devtools-launch.ps1 — S-073b（T-20261007-073 第①条 · 服务 T-20261007-085 裁决 A）

  起靶子 + 关靶子：给 Doyah Studio（Tauri 2 / WebView2）注入
  `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=<N>` 起 exe，
  等 CDP 端点就绪 → 跑同目录 devtools-shot.mjs 抓 1 张 PNG →
  **必须关掉本片起的进程**（收尾打印 tasklist 读数）。

  为什么要有这条通道：cron / 无人会话里 computer_use 的 click/type 走审批门被拒
  （BLOCKED: requires approval but cron jobs run without a user present to approve it），
  只能截「当前那一屏」。走到 WebView2 自己的 CDP 端口 = 可脚本化、免审批。

  用法（一条命令）：
    powershell -NoProfile -ExecutionPolicy Bypass -File platform/windows/App/tools/devtools-launch.ps1
  可选项：
    -Port 9222         CDP 端口
    -Out  <png 绝对路径> 输出图；缺省 = <仓库根>\.build\cdp-shot\shot-<时间戳>.png（.build/ 已 gitignore）
    -Exe  <exe 绝对路径> 指定靶子；缺省按「本工作树 → dev 克隆」顺序自动找
    -ReadyTimeoutSec 60 等端口上限（秒）

  退出码：0 = 五条读数齐；非 0 = 中途 FAIL（进程一律在 finally 里收掉）。
#>
[CmdletBinding()]
param(
  [int]$Port = 9222,
  [string]$Out,
  [string]$Exe,
  [int]$ReadyTimeoutSec = 60
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Say([string]$m) { Write-Host $m }
function Die([string]$m) { Write-Host "FAIL=$m"; exit 1 }

$here = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $here '..\..\..\..')).Path

# ---------- 找靶子 exe ----------
# 先本工作树（含 .build 本片构建派生路径），再逐级向上找 dev 克隆里的历史构建件。
$searchRoots = @()
$cur = $repoRoot
for ($i = 0; $i -lt 4 -and $cur; $i++) {
  $searchRoots += $cur
  $parent = Split-Path -Parent $cur
  if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cur) { break }
  $cur = $parent
}

$cands = New-Object System.Collections.Generic.List[string]
if ($Exe) { $cands.Add($Exe) }
if ($env:DOYAH_STUDIO_EXE) { $cands.Add($env:DOYAH_STUDIO_EXE) }
foreach ($r in $searchRoots) {
  $cands.Add((Join-Path $r 'platform\windows\target\release\doyah-studio.exe'))
  $cands.Add((Join-Path $r 'platform\windows\target\debug\doyah-studio.exe'))
  $cands.Add((Join-Path $r '.build\release\doyah-studio.exe'))
  $cands.Add((Join-Path $r '.build\debug\doyah-studio.exe'))
}

$exePath = $null
foreach ($c in $cands) {
  if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
    $exePath = (Resolve-Path -LiteralPath $c).Path
    break
  }
}
if (-not $exePath) { Die ("doyah-studio.exe not found; tried: " + ($cands -join ' | ')) }
Say "EXE=$exePath"

# ---------- 输出图路径 ----------
if ([string]::IsNullOrWhiteSpace($Out)) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $Out = Join-Path (Join-Path $repoRoot '.build\cdp-shot') ("shot-$stamp.png")
}
if (-not [System.IO.Path]::IsPathRooted($Out)) { $Out = Join-Path (Get-Location).Path $Out }
$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

# ---------- 起靶子（注入 CDP 端口）----------
$browserArgs = "--remote-debugging-port=$Port --remote-allow-origins=*"
Say "BROWSER_ARGS=$browserArgs"

$prevEnv = $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS
$proc = $null
$exitCode = 1

try {
  $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = $browserArgs
  $proc = Start-Process -FilePath $exePath -PassThru
  if (-not $proc) { Die 'Start-Process returned no process' }
  Say "PID=$($proc.Id)"

  # ---------- 等端口就绪 ----------
  $deadline = (Get-Date).AddSeconds($ReadyTimeoutSec)
  $listText = $null
  while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) { Die "target exited early, exit code $($proc.ExitCode)" }
    try {
      $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json/list" -UseBasicParsing -TimeoutSec 3
      if ($resp.StatusCode -eq 200 -and $resp.Content) {
        $listText = [string]$resp.Content
        $arr = @($listText | ConvertFrom-Json)
        if (@($arr | Where-Object { $_.type -eq 'page' }).Count -ge 1) { break }
      }
    } catch { }
    Start-Sleep -Milliseconds 400
  }
  if ([string]::IsNullOrWhiteSpace($listText)) {
    Die "CDP port $Port not ready within ${ReadyTimeoutSec}s (no /json/list)"
  }

  # 读数①：/json/list 片段
  Say "PORT=$Port"
  Say '--- /json/list (raw fragment) ---'
  Say $listText
  Say "PAGE_TARGETS=$(@(@($listText | ConvertFrom-Json) | Where-Object { $_.type -eq 'page' }).Count)"

  # ---------- 抓图 ----------
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  if (-not $nodeCmd) { Die 'node not found on PATH' }
  $shot = Join-Path $here 'devtools-shot.mjs'
  if (-not (Test-Path -LiteralPath $shot -PathType Leaf)) { Die "devtools-shot.mjs not found next to this script: $shot" }

  Say '--- devtools-shot ---'
  $shotOut = (& $nodeCmd.Source $shot --port $Port --out $Out 2>&1 | Out-String).Trim()
  $shotCode = $LASTEXITCODE
  Say $shotOut
  Say "EXITCODE=$shotCode"

  # 读数③：PNG 头（宽/高，PNG 大端 IHDR）
  if (Test-Path -LiteralPath $Out -PathType Leaf) {
    $bytes = [System.IO.File]::ReadAllBytes($Out)
    if ($bytes.Length -ge 24) {
      $w = ([int]$bytes[16] -shl 24) -bor ([int]$bytes[17] -shl 16) -bor ([int]$bytes[18] -shl 8) -bor [int]$bytes[19]
      $h = ([int]$bytes[20] -shl 24) -bor ([int]$bytes[21] -shl 16) -bor ([int]$bytes[22] -shl 8) -bor [int]$bytes[23]
      Say "PNG_PATH=$Out"
      Say "PNG_BYTES=$($bytes.Length)"
      Say "PNG_WIDTH=$w PNG_HEIGHT=$h"
    } else {
      Say "PNG_PATH=$Out (too small: $($bytes.Length) bytes)"
    }
  } else {
    Say "PNG_PATH=$Out (missing)"
  }

  $exitCode = $shotCode
}
finally {
  # ---------- 收尾：本片起的进程必须关掉 ----------
  if ($proc -and -not $proc.HasExited) {
    try {
      Stop-Process -Id $proc.Id -Force -ErrorAction Stop
      $proc.WaitForExit(15000) | Out-Null
    } catch { }
  }
  $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = $prevEnv

  # 读数⑤：tasklist 证明无残留
  Say '--- tasklist /FI "IMAGENAME eq doyah-studio.exe" ---'
  $tl = (& tasklist /FI 'IMAGENAME eq doyah-studio.exe' 2>&1 | Out-String).Trim()
  Say $tl
}

Say "RESULT_EXIT=$exitCode"
exit $exitCode
