# Doyah Studio · Windows 侧闸门 · 领域层边界（windows/Tools/check-core-boundary.ps1）
#
# 对应 §8.3「单测（领域层）」那行的判据 —— **GUI 框架不得进入领域层**，
# 以及 §8.5.1「领域层边界由项目引用强制」（= mac 侧 Scripts/check-core-portability.py 的机械等价物）。
#
# 本侧判法（工程建成后逐条生效；工程未建 ⇒ 跳过，不是通过）：
#   ① windows/Core/*.csproj 不得开 WPF / WinForms / Windows App SDK，也不得引 GUI 包；
#   ② windows/Core/**/*.cs 不得出现平台命名空间（System.Windows / Windows.UI / System.Windows.Forms /
#      Microsoft.Win32）与 P/Invoke（DllImport —— P/Invoke 只允许在 Platform/Windows/ 里）。
#
# 退出码：0 = 通过 / 1 = 判红 / 2 = 跳过

param([string]$RepoRoot = '')

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

Write-Host ("== 领域层边界（GUI 不得进入领域层）（{0}）" -f $RepoRoot)

$coreDir = Join-Path $RepoRoot 'windows\Core'
$coreProjects = @()
if (Test-Path $coreDir) {
  $coreProjects = @(Get-ChildItem -Path $coreDir -Filter '*.csproj' -Recurse -File -ErrorAction SilentlyContinue)
}

if ($coreProjects.Count -eq 0) {
  Write-DoyahSkip -Text "领域层边界（windows\Core）" -Reason "Windows 领域层工程未建（§8.5.7 ⬜ 未开工）—— 建成后本项由项目引用关系 + 源码扫描双判"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

$failed = $false

# ── ① 项目引用 / 开关 ────────────────────────────────────────────────────────
$bannedProjectTokens = @(
  'UseWPF',
  'UseWindowsForms',
  'Microsoft.WindowsAppSDK',
  'CommunityToolkit.WinUI',
  'System.Windows.Forms',
  'PresentationFramework'
)
foreach ($project in $coreProjects) {
  $text = Read-DoyahTextFile -Path $project.FullName
  foreach ($token in $bannedProjectTokens) {
    if ($text -match [regex]::Escape($token)) {
      Write-DoyahFail ("{0} 出现 GUI / 平台依赖标记：{1}" -f $project.Name, $token)
      $failed = $true
    }
  }
}

# ── ② 源码里的平台命名空间与 P/Invoke ────────────────────────────────────────
$bannedSourcePatterns = @(
  @{ Name = 'System.Windows'; Pattern = 'using\s+System\.Windows(?!\.Forms)' },
  @{ Name = 'Windows.UI / Windows.Win32'; Pattern = 'using\s+Windows\.(UI|Win32|Graphics)' },
  @{ Name = 'System.Windows.Forms'; Pattern = 'using\s+System\.Windows\.Forms' },
  @{ Name = 'Microsoft.Win32'; Pattern = 'using\s+Microsoft\.Win32' },
  @{ Name = 'DllImport（P/Invoke 只允许在 Platform/Windows/）'; Pattern = 'DllImport' }
)
$sourceFiles = @(Get-ChildItem -Path $coreDir -Filter '*.cs' -Recurse -File -ErrorAction SilentlyContinue)
foreach ($file in $sourceFiles) {
  $lines = (Read-DoyahTextFile -Path $file.FullName) -split "`r?`n"
  for ($i = 0; $i -lt $lines.Count; $i++) {
    foreach ($rule in $bannedSourcePatterns) {
      if ($lines[$i] -match $rule.Pattern) {
        Write-DoyahFail ("{0}:{1} 出现 {2}" -f $file.Name, ($i + 1), $rule.Name)
        $failed = $true
      }
    }
  }
}

if ($failed) {
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

Write-DoyahPass ("领域层边界干净（{0} 个项目 / {1} 个源文件；GUI 与平台依赖只在 Platform\Windows\）" -f $coreProjects.Count, $sourceFiles.Count)
Write-DoyahResult -Status PASS -Code 0
exit 0
