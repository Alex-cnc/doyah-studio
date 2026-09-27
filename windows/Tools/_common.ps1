# Doyah Studio · Windows 侧闸门公共库 —— windows/Tools/_common.ps1
#
# 用法（同目录下的脚本里）：
#     $ToolsDir = $PSScriptRoot
#     . (Join-Path $ToolsDir '_common.ps1')
#     $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir
#
# 退出码协议（全目录统一；§8.3.2「跳过 ≠ 通过」的机械落法）：
#     0 = 跑过且通过
#     1 = 判红
#     2 = 跳过（平台不适用 / 依赖未就位）—— 跳过必须**逐条列出来**，-RequireAll 时判红
#
# 三条本机实测坑（2026-09-27，Windows 11 + Windows PowerShell 5.1）：
#   ① 本目录 .ps1 一律 **UTF-8 带 BOM**：PowerShell 5.1 读**无 BOM** 的中文脚本时按 ANSI(GBK) 解码
#      ⇒ 字符串终止符报错、**整个脚本一行都不执行**（实测 `exit 2` 都到不了）。verify-all.ps1 第 1 项机械判它。
#   ② 中文输出要在脚本开头设 [Console]::OutputEncoding = UTF8，否则输出被重定向后是乱码（本文件已设）。
#   ③ 找 Python **不能**只看 Get-Command：Windows 上 `python3` 是应用商店占位符
#      （…\WindowsApps\python3.exe，实跑 `--version` 即退出码 49）⇒ 必须**实跑一句** Python 3 再认。
#      另外：从 MSYS bash 直接以路径调用 PowerShell 时，**任意非零退出码会被压成 1**（实测 exit 7 → $?=1）；
#      在 PowerShell 会话内、或用 `-File` 形式调用时退出码正常。脚本内的父子汇总靠 $LASTEXITCODE（实测正常）。

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

function Get-DoyahRepoRoot {
  param([Parameter(Mandatory = $true)][string]$ToolsDir)
  return (Resolve-Path (Join-Path $ToolsDir '..\..')).Path
}

function Find-DoyahPython {
  # 顺序：$env:PYTHON → py -3 → python → python3；每个候选**实跑**一句再认
  $candidates = New-Object System.Collections.ArrayList
  if ($env:PYTHON) { [void]$candidates.Add(@($env:PYTHON)) }
  [void]$candidates.Add(@('py', '-3'))
  [void]$candidates.Add(@('python'))
  [void]$candidates.Add(@('python3'))
  foreach ($candidate in $candidates) {
    $exe = $candidate[0]
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
    $pre = @()
    if ($candidate.Count -gt 1) { $pre = $candidate[1..($candidate.Count - 1)] }
    $probe = ''
    try { $probe = (& $exe @pre '-c' 'import sys;print(sys.version_info[0])' 2>$null | Out-String).Trim() } catch { continue }
    if ($LASTEXITCODE -eq 0 -and $probe -eq '3') {
      $label = ("$exe " + ($pre -join ' ')).Trim()
      return @{ Exe = $exe; Pre = $pre; Label = $label }
    }
  }
  return $null
}

function Invoke-DoyahSharedGate {
  # 跑仓内**共享判据**（Scripts/*.py —— 判据归契约层，本侧只调用、不重写）
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)]$Python,
    [Parameter(Mandatory = $true)][string]$RelativeScript,
    [string[]]$Arguments = @()
  )
  $script = Join-Path $RepoRoot $RelativeScript
  if (-not (Test-Path $script)) {
    Write-Host ("    ❌ 判据脚本不在盘上：{0}（本侧只读 `Scripts/`，被移走请提提案）" -f $RelativeScript)
    return 1
  }
  Write-Host ("    $ {0} {1} {2}" -f $Python.Label, $RelativeScript, ($Arguments -join ' '))
  $argv = @()
  $argv += $Python.Pre
  $argv += $script
  $argv += $Arguments
  # 本机实测坑（第 22 轮）：PS 5.1 在 $ErrorActionPreference = 'Stop' 下，会把原生命令写到 **stderr** 的
  # 任意一行变成**终止错误**（NativeCommandError）—— 判据明明「打印一条警告、退出码 0」，本侧闸门却整项判红。
  # 实测现场：对侧 `Scripts/check-doc-tables.py` 的 docstring 里一处无效转义 ⇒ 每次运行都往 stderr 打
  # SyntaxWarning ⇒ 本侧第 ③ 项假红（该项真判是 ✅、rc 0）。
  # 口径：**判红与否只由退出码决定**；stderr 上的文字照原样打出来（不吞、不静默），但不许据此判红。
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = (& $Python.Exe @argv 2>&1 | Out-String)
    $rc = $LASTEXITCODE
  }
  finally { $ErrorActionPreference = $prevEap }
  $trimmed = $output.TrimEnd()
  if ($trimmed) {
    foreach ($line in ($trimmed -split "`r?`n")) { Write-Host ("    | " + $line) }
  }
  return $rc
}

function Get-DoyahDotnet {
  # 本机实测：dotnet 可能**装了但没进 PATH**（C:\Program Files\dotnet\dotnet.exe）
  $exe = $null
  $command = Get-Command 'dotnet' -ErrorAction SilentlyContinue
  if ($command) { $exe = $command.Source }
  elseif (Test-Path 'C:\Program Files\dotnet\dotnet.exe') { $exe = 'C:\Program Files\dotnet\dotnet.exe' }
  if (-not $exe) { return $null }
  $sdks = @()
  try { $sdks = @(& $exe '--list-sdks' 2>$null | Where-Object { $_ }) } catch { $sdks = @() }
  return @{ Exe = $exe; Sdks = $sdks }
}

function Test-DoyahUtf8Bom {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 3) { return $false }
  return ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Read-DoyahTextFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-DoyahStep {
  param([string]$Number, [string]$Text)
  Write-Host ("==> {0} {1}" -f $Number, $Text)
}

function Write-DoyahPass {
  param([string]$Text)
  Write-Host ("  ✅ 通过：{0}" -f $Text)
}

function Write-DoyahSkip {
  param([string]$Text, [string]$Reason)
  Write-Host ("  ⏭ 跳过：{0}" -f $Text)
  Write-Host ("     原因：{0}" -f $Reason)
  Write-Host "     跳过不是「已通过」（§8.3.2；-RequireAll 时判红）"
}

function Write-DoyahFail {
  param([string]$Text)
  Write-Host ("  ❌ 判红：{0}" -f $Text)
}

function Write-DoyahResult {
  # 机器可读收尾行（ASCII 词元，不受控制台代码页影响）：PASS / SKIP / FAIL
  param([ValidateSet('PASS', 'SKIP', 'FAIL')][string]$Status, [int]$Code)
  Write-Host ("RESULT: {0} (exit {1})" -f $Status, $Code)
}
