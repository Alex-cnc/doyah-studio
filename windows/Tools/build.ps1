# Doyah Studio · Windows 侧闸门 ① 构建入口（windows/Tools/build.ps1）
#
# 对应 §8.3.1 ①「构建入口」：一条命令产出可运行产物（§8.5.2-3 = 便携 zip + MSIX），步骤不靠人记。
# 现阶段的诚实行为：**前置未就位就明确报「跳过 + 原因」，绝不假装成功** ——
#   · 本机没有 dotnet ⇒ 跳过（原因写明 §8.5.1 栈要求 = C# / .NET 8）；
#   · 有 dotnet 但没有 8.x SDK ⇒ 跳过（列出本机实测 SDK 列表，让"该装什么"一眼可见）；
#   · 有 SDK 但 windows\ 下没有工程 ⇒ 跳过（本侧未开工）。
# 三者都就位时才真的 publish + 打包，并打印产物路径。
#
# MSIX 说明：MSIX 需要代码签名证书（§8.5.2-3 / P-21），证书不在仓里 —— 本脚本只做
# 便携 zip（未签名版）；签名版 MSIX 走发布流程，见 §8.5.2-3。
#
# 退出码：0 = 产物已产出 / 1 = 判红 / 2 = 跳过

param(
  [string]$RepoRoot = '',
  [string]$Configuration = 'Release',
  [string]$Runtime = 'win-x64'
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

Write-Host ("== ① 构建入口（{0}；{1} / {2}）" -f $RepoRoot, $Configuration, $Runtime)

$dotnet = Get-DoyahDotnet
if (-not $dotnet) {
  Write-DoyahSkip -Text "构建：dotnet publish + 便携 zip" -Reason "本机找不到 dotnet（§8.5.1 栈 = C# / .NET 8；注意 dotnet 可能装了但没进 PATH —— 本脚本也查 C:\Program Files\dotnet\dotnet.exe）"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

Write-Host ("    dotnet：{0}" -f $dotnet.Exe)
if ($dotnet.Sdks.Count -gt 0) {
  foreach ($sdk in $dotnet.Sdks) { Write-Host ("    SDK：{0}" -f $sdk) }
}
else {
  Write-Host "    SDK：（--list-sdks 无输出）"
}

$hasSdk8 = @($dotnet.Sdks | Where-Object { $_ -match '^8\.' }).Count -gt 0

$windowsDir = Join-Path $RepoRoot 'windows'
$appProjects = @()
$solutions = @()
if (Test-Path $windowsDir) {
  $appProjects = @(Get-ChildItem -Path $windowsDir -Filter '*.csproj' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\App\\' })
  $solutions = @(Get-ChildItem -Path $windowsDir -Include '*.sln', '*.slnx' -Recurse -File -ErrorAction SilentlyContinue)
}

if ($appProjects.Count -eq 0) {
  Write-DoyahSkip -Text "构建：dotnet publish + 便携 zip" -Reason "Windows 工程未建（windows\App 下没有 .csproj；§8.5.7 ⬜ 未开工）—— 先有闸门再有功能，本入口已就位"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

if (-not $hasSdk8) {
  Write-DoyahSkip -Text "构建：dotnet publish + 便携 zip" -Reason ("缺 .NET SDK 8（§8.5.1 要求 net8.0-windows）；本机实测 SDK：{0}" -f (($dotnet.Sdks | ForEach-Object { ($_ -split ' ')[0] }) -join '、'))
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

$outputDir = Join-Path $windowsDir 'dist\app'
Write-Host ("    $ dotnet publish {0} -c {1} -r {2}" -f $appProjects[0].FullName, $Configuration, $Runtime)
& $dotnet.Exe publish $appProjects[0].FullName -c $Configuration -r $Runtime --self-contained false -o $outputDir
if ($LASTEXITCODE -ne 0) {
  Write-DoyahFail ("dotnet publish 失败（退出码 {0}）" -f $LASTEXITCODE)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

$zipPath = Join-Path $windowsDir ("dist\DoyahStudio-{0}-portable.zip" -f $Runtime)
if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force }
Compress-Archive -Path (Join-Path $outputDir '*') -DestinationPath $zipPath -Force

Write-DoyahPass ("产物：{0}（便携 zip）；签名版 MSIX 走 §8.5.2-3 的发布流程（证书不在仓里）" -f $zipPath)
Write-DoyahResult -Status PASS -Code 0
exit 0
