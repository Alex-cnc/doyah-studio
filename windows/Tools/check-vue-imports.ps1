# 判据：Vue 组合式 API **用了就必须从 vue 导入**（防"空白页"复发）
#
# 为什么需要它（2026-10-04 实测事故）：
#   `App.vue` 里用了 `computed(...)`，但 `import { ... } from 'vue'` 里没有 `computed`。
#   ⇒ **整个应用白屏**：Vue 挂载成功（`#app` 有 `data-v-app`），但根组件 setup 抛
#   `ReferenceError: computed is not defined`，渲染成 `<!---->`（空注释），什么都看不见。
#
# 为什么既有的两道网都没拦住：
#   ① `tsc --noEmit` 不校验 setup 里对未声明标识符的引用；
#   ② `vitest` 是纯逻辑单测，**根本不挂载组件** ⇒ 同一课：真跑才炸。
#   ⇒ 只能靠"文本层面对账"兜住（与 Tools/ 里既有那批判据同一姿势）。
#
# 退出码：0 = 通过；1 = 判红并逐条点名。

$ErrorActionPreference = 'Stop'

$appDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'App'
$srcDir = Join-Path $appDir 'src'

if (-not (Test-Path $srcDir)) {
    Write-Host "判红：找不到源码目录 $srcDir"
    exit 1
}

# 纳入对账的组合式 API（只列本侧真在用的；加新的就往这里补一条）
$apis = @(
    'computed', 'watch', 'watchEffect', 'ref', 'reactive', 'readonly',
    'onMounted', 'onBeforeUnmount', 'onUnmounted', 'nextTick',
    'toRefs', 'toRef', 'shallowRef', 'triggerRef'
)

$files = Get-ChildItem $srcDir -Recurse -File | Where-Object { $_.Extension -in '.vue', '.ts' }
$problems = @()
$checked = 0

foreach ($file in $files) {
    $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $checked++

    $imported = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in [regex]::Matches($text, "import\s*\{([^}]*)\}\s*from\s*'vue'")) {
        $inner = $m.Groups[1].Value
        foreach ($name in ($inner -split ',')) {
            $clean = ($name -replace '\s', '')
            $clean = $clean -replace '^type', ''
            if ($clean.Length -gt 0) { [void]$imported.Add($clean) }
        }
    }

    foreach ($api in $apis) {
        $pattern = "(?<![A-Za-z0-9_.])" + [regex]::Escape($api) + "\s*\("
        if ([regex]::IsMatch($text, $pattern)) {
            if (-not $imported.Contains($api)) {
                $rel = $file.FullName.Replace($appDir + '\', '')
                $problems += ($rel + " 用了 " + $api + "( 但没有从 vue 导入它")
            }
        }
    }
}

Write-Host "  对账 $checked 个文件（.vue / .ts），组合式 API 清单 $($apis.Count) 项"

if ($problems.Count -gt 0) {
    Write-Host "判红：以下文件用了组合式 API 却没导入 —— 这类错会让整个页面白屏（tsc 与 vitest 都抓不到）："
    foreach ($p in $problems) { Write-Host "   . $p" }
    Write-Host "   修法：在该文件的 import { ... } from 'vue' 里补上缺的名字。"
    exit 1
}

Write-Host "通过：所有用到组合式 API 的文件都从 vue 导入了它们"
exit 0
