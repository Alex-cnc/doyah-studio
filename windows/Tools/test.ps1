# Doyah Studio · Windows 侧闸门 ② 单测（windows/Tools/test.ps1）
#
# 对应 §8.3.1 ②「单测」：另一平台要求 = `dotnet test`（xUnit），等价覆盖，
# 且「GUI 框架不得进入领域层」（项目引用强制，见 check-core-boundary.ps1）。
# 现阶段的诚实行为同 build.ps1：前置未就位 ⇒ 跳过 + 写明原因，不假装通过。
#
# 退出码：0 = 全绿 / 1 = 判红（有失败用例）/ 2 = 跳过

param(
  [string]$RepoRoot = '',
  [string]$Configuration = 'Release'
)

$ToolsDir = $PSScriptRoot
. (Join-Path $ToolsDir '_common.ps1')
if (-not $RepoRoot) { $RepoRoot = Get-DoyahRepoRoot -ToolsDir $ToolsDir }

Write-Host ("== ② 单测：dotnet test（{0}）" -f $RepoRoot)

$dotnet = Get-DoyahDotnet
if (-not $dotnet) {
  Write-DoyahSkip -Text "单测：dotnet test（xUnit）" -Reason "本机找不到 dotnet（§8.5.1 栈 = C# / .NET 8）"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

$windowsDir = Join-Path $RepoRoot 'windows'
$testProjects = @()
$solutions = @()
if (Test-Path $windowsDir) {
  $testProjects = @(Get-ChildItem -Path $windowsDir -Filter '*.csproj' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\Tests\\' })
  $solutions = @(Get-ChildItem -Path $windowsDir -Include '*.sln', '*.slnx' -Recurse -File -ErrorAction SilentlyContinue)
}

if ($testProjects.Count -eq 0) {
  Write-DoyahSkip -Text "单测：dotnet test（xUnit）" -Reason "Windows 测试工程未建（§8.5.1 工程结构 windows\Tests\；§8.5.7 ⬜ 未开工）"
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

$hasSdk8 = @($dotnet.Sdks | Where-Object { $_ -match '^8\.' }).Count -gt 0
if (-not $hasSdk8) {
  Write-DoyahSkip -Text "单测：dotnet test（xUnit）" -Reason ("缺 .NET SDK 8；本机实测 SDK：{0}" -f (($dotnet.Sdks | ForEach-Object { ($_ -split ' ')[0] }) -join '、'))
  Write-DoyahResult -Status SKIP -Code 2
  exit 2
}

if ($solutions.Count -gt 0) { $target = $solutions[0].FullName } else { $target = $testProjects[0].FullName }
Write-Host ("    $ dotnet test {0} -c {1}" -f $target, $Configuration)
& $dotnet.Exe test $target -c $Configuration
if ($LASTEXITCODE -ne 0) {
  Write-DoyahFail ("dotnet test 失败（退出码 {0}）" -f $LASTEXITCODE)
  Write-DoyahResult -Status FAIL -Code 1
  exit 1
}

Write-DoyahPass ("dotnet test 全绿（{0} 个测试工程）" -f $testProjects.Count)
Write-DoyahResult -Status PASS -Code 0
exit 0
