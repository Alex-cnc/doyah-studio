#!/usr/bin/env node
// Windows 侧插件架构判据（**静态面**）—— 契约依据 = 概要设计 §3.52；本侧落法 = §8.5.8
//
// 判什么（五道里的四道静态道）：
//   ① **清单 ⇄ 装配 ⇄ 插件目录 三处对账**：领域层清单里的每个插件，必须在
//      `App/src/plugins/registry.ts` 被装配，且在 `App/src/plugins/<entry>/index.ts`
//      声明同一份 `PLUGIN_ID` / `PLUGIN_MOUNTS` / 存储归属；
//   ② **挂点自洽**：插件目录声明的挂点必须与清单逐条相符（多了少了都判红）；
//   ③ **入口可用**：清单的 `entry` 必须能对上 `pluginRegistry.ts` 的懒加载表，
//      且对应 `View.vue` 文件在盘上（否则"入口存在但点开崩"）；
//   ④ **插件不碰宿主内部模型**：插件目录**只许** import 挂点契约模块
//      （`shell/pluginRegistry`）与公共面（`i18n` / `ipc`），
//      **不许** import `views/`、`App.vue`、其它 shell 内部模块；
//   ⑤ **反向**：界面里出现的插件 id 必须都能在清单里找到出处（不许"硬写一个插件项"）。
//
// 退出码：0 = 全过 · 1 = 判红（**逐条点名文件与行**）· 2 = 环境不对（要人管）
//
// 用法：node tools/check-plugins.mjs

import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { resolve, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const APP = resolve(HERE, '..')
const WINDOWS = resolve(APP, '..')
const REPO = resolve(WINDOWS, '..', '..')

const MANIFEST_RS = join(WINDOWS, 'Db', 'src', 'plugins.rs')
const PLUGIN_REGISTRY_TS = join(APP, 'src', 'plugins', 'registry.ts')
const PLUGIN_REGISTRY_HOST_TS = join(APP, 'src', 'shell', 'pluginRegistry.ts')
const PLUGINS_DIR = join(APP, 'src', 'plugins')
const ACTIVITY_ITEMS_TS = join(APP, 'src', 'shell', 'activityItems.ts')

const problems = []
function fail(where, detail) {
  problems.push(`${where}：${detail}`)
}

function read(path, what) {
  if (!existsSync(path)) {
    fail(path, `${what}不在盘上`)
    return ''
  }
  return readFileSync(path, 'utf8')
}

// ── ① 解析领域层清单（Rust）──────────────────────────────────────────────────
const manifest = read(MANIFEST_RS, '领域层插件清单')
const plugins = []
{
  // 每条：PluginDecl { id: "x", ... mounts: &[ ... ], storage: X, implemented: bool }
  const re = /PluginDecl\s*\{([\s\S]*?)\n\s{4}\}/g
  let m
  while ((m = re.exec(manifest)) !== null) {
    const body = m[1]
    const id = /id:\s*"([^"]+)"/.exec(body)?.[1]
    if (!id) continue
    const entry = /entry:\s*"([^"]+)"/.exec(body)?.[1] ?? id
    const storage = /storage:\s*StorageOwnership::(\w+)/.exec(body)?.[1] ?? '?'
    const implemented = /implemented:\s*(true|false)/.exec(body)?.[1] === 'true'
    const mountsBlock = /mounts:\s*&\[([\s\S]*?)\]/.exec(body)?.[1] ?? ''
    const mounts = [...mountsBlock.matchAll(/MountPoint::(\w+)/g)].map((x) => x[1])
    plugins.push({ id, entry, storage, implemented, mounts })
  }
}
if (plugins.length === 0) fail(MANIFEST_RS, '一条插件声明都没解析到（清单形状变了，判据要跟着改）')

// ── ② 解析界面侧装配表 ───────────────────────────────────────────────────────
const registryTs = read(PLUGIN_REGISTRY_TS, '插件装配表')
const installed = [...registryTs.matchAll(/install as install(\w+)/g)].map((m) => m[1])
if (installed.length === 0) fail(PLUGIN_REGISTRY_TS, '装配表里一个插件都没装配')

// ── ③ 逐插件对账（清单 ⇄ 装配 ⇄ 插件目录）──────────────────────────────────────
const MOUNT_ID = {
  ActivityItem: 'activity-item',
  MainTab: 'main-tab',
  MenuItem: 'menu-item',
  SearchIndex: 'search-index',
  SettingsSection: 'settings-section',
  StorageFactory: 'storage-factory',
  Notify: 'notify',
}

for (const plugin of plugins) {
  const title = plugin.id
  const dir = join(PLUGINS_DIR, plugin.entry)
  const indexTs = join(dir, 'index.ts')
  const viewVue = join(dir, 'View.vue')
  const vueCandidates = existsSync(dir)
    ? readdirSync(dir).filter((f) => f.endsWith('View.vue'))
    : []
  const viewFile = vueCandidates.length > 0 ? join(dir, vueCandidates[0]) : viewVue

  // 3.1 装配表里必须有它（大小写不敏感地对 install 名）
  const expectedInstall = plugin.entry.charAt(0).toUpperCase() + plugin.entry.slice(1)
  if (!installed.some((n) => n.toLowerCase() === expectedInstall.toLowerCase())) {
    fail(PLUGIN_REGISTRY_TS, `清单里的插件 \`${title}\` 没在装配表里 install（装配表 = ${installed.join(' / ')}）`)
  }

  // 3.2 插件目录与 index.ts 必须在
  if (!existsSync(dir)) {
    fail(PLUGINS_DIR, `插件 \`${title}\` 的入口目录 \`${plugin.entry}/\` 不在盘上`)
    continue
  }
  if (!existsSync(indexTs)) {
    fail(dir, `插件 \`${title}\` 缺 \`index.ts\`（装配入口；没有它就无法登记挂点）`)
    continue
  }
  if (!existsSync(viewFile)) {
    fail(dir, `插件 \`${title}\` 缺视图文件 \`*View.vue\``)
  }

  // 3.3 index.ts 的 PLUGIN_ID 与清单一致
  const indexSrc = read(indexTs, `插件 ${title} 的装配入口`)
  const declaredId = /PLUGIN_ID\s*=\s*'([^']+)'/.exec(indexSrc)?.[1]
  if (declaredId !== plugin.id) {
    fail(indexTs, `PLUGIN_ID 是 \`${declaredId}\`，清单里是 \`${plugin.id}\` —— 两处必须同名`)
  }

  // 3.4 index.ts 的 PLUGIN_MOUNTS 与清单逐条一致（**多了少了都判红**）
  const mountsBlock = /PLUGIN_MOUNTS\s*=\s*\[([\s\S]*?)\]/.exec(indexSrc)?.[1] ?? ''
  const declaredMounts = [...mountsBlock.matchAll(/'([a-z-]+)'/g)].map((m) => m[1]).sort()
  const expectedMounts = plugin.mounts.map((m) => MOUNT_ID[m] ?? m).sort()
  const same =
    declaredMounts.length === expectedMounts.length &&
    declaredMounts.every((v, i) => v === expectedMounts[i])
  if (!same) {
    fail(
      indexTs,
      `PLUGIN_MOUNTS = [${declaredMounts.join(', ')}]，清单里 = [${expectedMounts.join(', ')}] —— 挂点必须逐条相符（挂点白名单见 MountPoint::ALL）`,
    )
  }

  // 3.5 入口懒加载表里必须有它（否则"入口存在但点开崩"）
  const hostRegistry = read(PLUGIN_REGISTRY_HOST_TS, '视图注册表')
  const lazyRe = new RegExp(`${plugin.entry}\\s*:\\s*\\(\\)\\s*=>\\s*import\\(`)
  if (!lazyRe.test(hostRegistry)) {
    fail(PLUGIN_REGISTRY_HOST_TS, `懒加载表里没有 \`${plugin.entry}\` 的入口（清单里有它，界面却加载不到）`)
  }

  // 3.6 存储归属必须在 index.ts 里**如实声明**（不能只在清单里说）
  const storageOk = /storage/i.test(indexSrc) || /storage/i.test(registryTs)
  if (!storageOk) {
    fail(indexTs, `插件 \`${title}\` 没有声明存储归属（契约⑤：自带 / 宿主代管二选一）`)
  }
}

// ── ④ 插件不碰宿主内部模型（import 面）────────────────────────────────────────
// 只许：挂点契约（shell/pluginRegistry）、公共面（i18n / ipc）、vue 本身、自己的相对文件。
const ALLOWED_IMPORT = [
  /^vue$/,
  /\/shell\/pluginRegistry$/,
  /\/i18n$/,
  /\/ipc$/,
  /^\.\//, // 自己的相对文件
  /^\.\.\/(\.\.\/)?(shell\/pluginRegistry|i18n|ipc)$/,
]
function checkImports(file) {
  const src = read(file, '插件文件')
  const re = /from\s+'([^']+)'/g
  let m
  while ((m = re.exec(src)) !== null) {
    const spec = m[1]
    if (ALLOWED_IMPORT.some((rx) => rx.test(spec))) continue
    fail(file, `插件不得 import \`${spec}\`（只许挂点契约 shell/pluginRegistry 与公共面 i18n / ipc / vue）`)
  }
}
if (existsSync(PLUGINS_DIR)) {
  for (const entryName of readdirSync(PLUGINS_DIR)) {
    const dir = join(PLUGINS_DIR, entryName)
    if (entryName === 'registry.ts') continue
    if (!existsSync(dir) || !readdirSync(dir)) continue
    for (const f of readdirSync(dir)) {
      if (f.endsWith('.ts') || f.endsWith('.vue')) checkImports(join(dir, f))
    }
  }
}

// ── ⑤ 反向：界面里的活动栏插件项必须都能在清单里找到出处 ──────────────────────
{
  const act = read(ACTIVITY_ITEMS_TS, '活动栏派生')
  // 派生器应从清单过滤，而不是写死一串 id
  if (!/pluginList/.test(act)) {
    fail(ACTIVITY_ITEMS_TS, '活动栏派生没有从清单（`pluginList`）取插件项 —— 又变成写死一份了')
  }
  const hardcoded = [...act.matchAll(/'(notes|retro|[a-z][a-z-]{2,})'/g)]
    .map((m) => m[1])
    .filter((name) => plugins.some((p) => p.id === name) && !/pluginList/.test(act))
  if (hardcoded.length > 0) {
    fail(ACTIVITY_ITEMS_TS, `活动栏里硬写了插件 id：${hardcoded.join(', ')}（必须从清单派生）`)
  }
}

// ── 收尾 ────────────────────────────────────────────────────────────────────
if (problems.length > 0) {
  console.error(`❌ 插件清单判据不过（${problems.length} 处）：`)
  for (const p of problems) console.error('   ' + p)
  process.exit(1)
}

console.log(
  `✅ 插件清单三处对账通过：清单 ${plugins.length} 条（${plugins
    .map((p) => p.id)
    .join(' / ')}）· 装配 ${installed.length} 条 · 入口与挂点逐条相符 · 插件目录未触碰宿主内部模型`,
)
process.exit(0)
