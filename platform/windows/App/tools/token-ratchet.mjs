#!/usr/bin/env node
// Doyah Studio · Windows 侧表示层 · 裸值棘轮（platform/windows/App/tools/token-ratchet.mjs）
//
// 对应 §8.5.3 的「设计令牌棘轮」：macOS 侧 `Scripts/check-design-tokens.py` 是 **Swift 专用**
// （扫 `App/` 下 .swift 统计裸值），无法在 Windows 侧跑 ⇒ 本脚本按**同一套规则名**在
// Tauri / Vue / TS 这一栈上重建棘轮 —— **只降不升**。
//
// 规则名（必须与 mac 侧基线 `Scripts/design-token-baseline.json` 里出现过的规则名一致，
// 判据 `platform/windows/Tools/check-design-tokens.ps1` 的 ① 项会逐名对账）：
//   bare-color      —— 裸色值（`#RRGGBB`）
//   bare-font       —— 裸字号（`font-size: 13px`）
//   bare-spacing    —— 裸间距（`padding: 8px` / `gap: 12px`；非零才计）
//   bare-radius     —— 裸圆角（`border-radius: 6px`；非零才计）
//   bare-foreground —— 文字色不走令牌（`color: #333` / `color: red`）
//   bare-textstyle  —— 文本样式不走令牌（`font:` 简写）
//
// 用法：
//   node tools/token-ratchet.mjs                 比对基线（闸门用；超基线即 exit 1）
//   node tools/token-ratchet.mjs --print         打印各文件各规则计数（人工下调基线时看它）
//
// 三条纪律：
//   1. **空扫不许通过**：扫到 0 个文件（或找不到令牌生成物）⇒ exit 1，不是「已通过」；
//   2. 生成物 `src/theme/tokens.generated.css` **按名字显式排除**（那里正是取值该在的地方），
//      排除名单写死在 EXCLUDED 里，改名前先看这里；
//   3. 基线里出现的文件必须在盘上（基线不许指向不存在的文件 —— 那是一条永远为真的旁路）。

import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { dirname, resolve, relative, sep, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const appDir = resolve(here, '..')
const repoRoot = resolve(here, '../../../..')
const baselinePath = resolve(repoRoot, 'platform/windows/Tools/design-token-baseline.json')

export const RULES = ['bare-color', 'bare-font', 'bare-spacing', 'bare-radius', 'bare-textstyle', 'bare-foreground']

/** 生成物与令牌源：不参与计数（取值本来就该在这里）。 */
export const EXCLUDED = ['platform/windows/App/src/theme/tokens.generated.css']

/** 令牌源文件：必须在盘上（否则「没有裸值」只是因为根本没有令牌层）。 */
export const TOKEN_SOURCE = 'platform/windows/App/src/theme/tokens.generated.css'

/** 平台级合成层：可以**定义**自己的合成变量（如发丝线 `--ds-hairline`），但取值只能来自令牌。 */
export const PLATFORM_STYLE = 'platform/windows/App/src/theme/app.css'

const DEFINED_VAR_RE = /(--ds-[a-z0-9-]+)\s*:/g
// 引用必须是**完整名字**：后面紧跟 `)` / `,` / `;` / 空白 / 串尾。
// 模板串里的占位（`var(--ds-${group}-…)` / `var(--ds-color-${…})`）因此不算引用 —— 那是拼名字的代码。
const REFERENCED_VAR_RE = /var\((--ds-[a-z0-9-]*[a-z0-9])(?=[),;\s]|$)/g

const SCAN_EXT = ['.vue', '.ts', '.mts', '.css']

/** 允许出现的字面量取值（非令牌是合法的那些）。 */
const COLOR_KEYWORDS = ['inherit', 'currentcolor', 'transparent', 'none', 'unset', 'initial', 'revert']

const toRepoPath = (absolute) => relative(repoRoot, absolute).split(sep).join('/')

/**
 * 两条仓内路径是不是同一个（**大小写不敏感**）。
 *
 * 为什么不能用 `===`：Windows 的文件系统不区分大小写，而**路径的大小写取决于它是怎么被拼出来的**
 * —— 同一个目录，`node tools/token-ratchet.mjs` 拿到 `platform/…`，vitest 解析模块真实路径时
 * 拿到 `Platform/…`（磁盘上的真实大小写）。用 `===` 比会**假红**：生成物 `tokens.generated.css`
 * 明明登记在 EXCLUDED 里，却因为大小写不同而没被排除、被当成 299 处裸色值判红
 * （2026-10-06 实测：`npm test` 判红、单独跑同一个脚本通过）。判据该判的是"路径指同一个文件"，
 * 不是"字符串逐字节相同"。Linux / macOS 上这条恒等于 `===`（不会放过任何真实的路径差异）。
 */
const sameRepoPath = (a, b) => a.toLowerCase() === b.toLowerCase()

/** 一行里第 N 个捕获组的值里有没有「非零数字」（`0` / `0px` 不算裸值 —— 与 Spacing.hair 同级的最小例外）。 */
const hasNonZeroNumber = (value) => /(?<![\d.])[1-9]/.test(value)

/**
 * 统计一段源码里的裸值。导出给单测用（`tests/token-ratchet.test.mjs`）。
 * @param {string} text
 * @returns {Record<string, number>}
 */
export function countBareValues(text) {
  const counts = Object.fromEntries(RULES.map((rule) => [rule, 0]))

  counts['bare-color'] = (text.match(/#[0-9A-Fa-f]{3,8}\b/g) ?? []).length

  counts['bare-font'] = (text.match(/font-size\s*:\s*[0-9]/g) ?? []).length

  const spacingRe = /(?:^|[;{\s])(?:margin|padding|gap|row-gap|column-gap)(?:-[a-z]+)?\s*:\s*([^;{}\n]*)/g
  for (const match of text.matchAll(spacingRe)) {
    if (hasNonZeroNumber(match[1])) counts['bare-spacing'] += 1
  }

  const radiusRe = /border-radius\s*:\s*([^;{}\n]*)/g
  for (const match of text.matchAll(radiusRe)) {
    if (hasNonZeroNumber(match[1])) counts['bare-radius'] += 1
  }

  const colorRe = /(?:^|[;{\s])color\s*:\s*([^;{}\n]*)/g
  for (const match of text.matchAll(colorRe)) {
    const value = match[1].trim().toLowerCase()
    if (value.startsWith('var(--ds-')) continue
    if (COLOR_KEYWORDS.includes(value)) continue
    counts['bare-foreground'] += 1
  }

  const fontShorthandRe = /(?:^|[;{\s])font\s*:\s*([^;{}\n]*)/g
  for (const match of text.matchAll(fontShorthandRe)) {
    const value = match[1].trim().toLowerCase()
    if (value.startsWith('var(--ds-')) continue
    if (value === 'inherit' || value === 'unset' || value === 'initial') continue
    counts['bare-textstyle'] += 1
  }

  return counts
}

/**
 * 收集本文件里 `var(--ds-*)` 引用的变量名（去重）。
 * 用它判「引用面 ⊆ 定义面」—— 拼错变量名的样式**不会报错、只是不生效**，
 * 这是 Vue / CSS 里最难发现的一类静默失效。
 */
export function collectReferencedVars(text) {
  return new Set([...text.matchAll(REFERENCED_VAR_RE)].map((match) => match[1]))
}

/** 收集**定义面**（生成物 + 平台级合成层）里的变量名。 */
export function collectDefinedVars(texts) {
  const names = new Set()
  for (const text of texts) for (const match of text.matchAll(DEFINED_VAR_RE)) names.add(match[1])
  return names
}

function walk(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === 'dist' || entry.name === 'target') continue
    const full = join(dir, entry.name)
    if (entry.isDirectory()) walk(full, out)
    else if (SCAN_EXT.some((ext) => entry.name.endsWith(ext))) out.push(full)
  }
  return out
}

export function scan() {
  const srcDir = resolve(appDir, 'src')
  const files = existsSync(srcDir) ? walk(srcDir) : []
  const scanned = []
  const skipped = []
  for (const file of files.sort()) {
    const repoPath = toRepoPath(file)
    if (EXCLUDED.some((excluded) => sameRepoPath(excluded, repoPath))) {
      skipped.push(repoPath)
      continue
    }
    scanned.push({ path: repoPath, counts: countBareValues(readFileSync(file, 'utf8')) })
  }
  return { scanned, skipped }
}

/**
 * 判据自测夹具（`--self-test`）—— **负例**：证明棘轮真的抓得到它声称抓的东西。
 *
 * 为什么要有它：这类工具最容易的失效不是「规则写错」，而是**看着在守、其实没守**
 * （扫描集为空 / 正则写漏 / 生成物被误排除）。所以自测里既有「该判红的」，
 * 也有两条「**不该**判红的」（走令牌 / 零值）—— 只测一半等于没测。
 */
export const SELF_TEST_FIXTURES = [
  { label: '裸色值（#RRGGBB）', text: '.a { background: #D9534F; }', rule: 'bare-color', expected: 1 },
  { label: '裸前景（color: red）', text: '.a { color: red; }', rule: 'bare-foreground', expected: 1 },
  { label: '裸字号（font-size: 13px）', text: '.a { font-size: 13px; }', rule: 'bare-font', expected: 1 },
  { label: '非零间距（padding: 6px）', text: '.a { padding: 6px; }', rule: 'bare-spacing', expected: 1 },
  { label: '非零圆角（border-radius: 6px）', text: '.a { border-radius: 6px; }', rule: 'bare-radius', expected: 1 },
  // 两条反面：棘轮要是把这些也算上，第一天就没法维护
  { label: '走令牌不算（color: var(--ds-color-status-danger)）', text: '.a { color: var(--ds-color-status-danger); }', rule: 'bare-foreground', expected: 0 },
  { label: '零值不算（padding: 0）', text: '.a { padding: 0; }', rule: 'bare-spacing', expected: 0 },
]

/**
 * 跑自测，返回 `{ cases, failures }`。
 * 值面用 `countBareValues` 逐夹具比计数；引用面单独两条（悬空要抓得到 / 已定义要放行）。
 */
export function runSelfTest() {
  const failures = []
  let cases = 0
  for (const fixture of SELF_TEST_FIXTURES) {
    cases += 1
    const actual = countBareValues(fixture.text)[fixture.rule]
    if (actual !== fixture.expected) {
      failures.push(`${fixture.label}：${fixture.rule} 期望 ${fixture.expected}，实际 ${actual}`)
    }
  }

  const defined = collectDefinedVars([':root { --ds-color-status-danger: #D9534F; }'])
  const dangling = [...collectReferencedVars('.a { color: var(--ds-color-status-danger); background: var(--ds-color-nope); }')].filter(
    (name) => !defined.has(name),
  )
  cases += 1
  if (dangling.length !== 1 || dangling[0] !== '--ds-color-nope') {
    failures.push(`悬空引用：期望 ['--ds-color-nope']，实际 ${JSON.stringify(dangling)}`)
  }
  const resolved = [...collectReferencedVars('.a { color: var(--ds-color-status-danger); }')].filter(
    (name) => !defined.has(name),
  )
  cases += 1
  if (resolved.length !== 0) {
    failures.push(`已定义引用被误判为悬空：${JSON.stringify(resolved)}`)
  }

  return { cases, failures }
}

function main() {
  const printOnly = process.argv.includes('--print')
  const selfTestOnly = process.argv.includes('--self-test')

  if (selfTestOnly) {
    const { cases, failures } = runSelfTest()
    if (failures.length > 0) {
      for (const failure of failures) process.stderr.write(`✗ 自测失败：${failure}\n`)
      process.stdout.write(`判据自测：${cases - failures.length}/${cases} 例通过\n`)
      process.exit(1)
    }
    process.stdout.write(`✅ 判据自测：${cases}/${cases} 例通过（棘轮抓得到它声称抓的东西）\n`)
    process.exit(0)
  }

  const { scanned, skipped } = scan()

  if (!existsSync(resolve(repoRoot, TOKEN_SOURCE))) {
    process.stderr.write(`✗ 令牌源不在盘上：${TOKEN_SOURCE}（先跑 node tools/gen-tokens.mjs）—— 空扫不许通过\n`)
    process.exit(1)
  }
  if (scanned.length === 0) {
    process.stderr.write('✗ 受检面为空（platform/windows/App/src 下一个 .vue / .ts / .css 都没有）—— 空扫不许通过\n')
    process.exit(1)
  }

  let baseline = { files: {} }
  if (!printOnly) {
    if (!existsSync(baselinePath)) {
      process.stderr.write(
        `✗ 棘轮基线不在盘上：${toRepoPath(baselinePath)}（棘轮必须有基线，否则第一次就无参照）\n`,
      )
      process.exit(1)
    }
    baseline = JSON.parse(readFileSync(baselinePath, 'utf8'))
    for (const repoPath of Object.keys(baseline.files ?? {})) {
      if (!existsSync(resolve(repoRoot, repoPath))) {
        process.stderr.write(`✗ 基线里的文件不在盘上：${repoPath}（基线不许指向不存在的文件）\n`)
        process.exit(1)
      }
    }
  }

  let totals = 0
  const violations = []
  const lines = []

  // 引用面 ⊆ 定义面（Vue / CSS 里拼错变量名不报错、只是不生效）
  const definedVars = collectDefinedVars([
    readFileSync(resolve(repoRoot, TOKEN_SOURCE), 'utf8'),
    readFileSync(resolve(repoRoot, PLATFORM_STYLE), 'utf8'),
  ])
  let danglingCount = 0
  for (const { path: repoPath } of scanned) {
    const text = readFileSync(resolve(repoRoot, repoPath), 'utf8')
    for (const name of collectReferencedVars(text)) {
      if (!definedVars.has(name)) {
        danglingCount += 1
        violations.push(`${repoPath}：var(${name}) 在令牌层没有定义 —— 样式会静默不生效`)
      }
    }
  }

  for (const { path: repoPath, counts } of scanned) {
    const ceilings = baseline.files?.[repoPath] ?? {}
    const parts = []
    for (const rule of RULES) {
      const count = counts[rule]
      if (count === 0) continue
      totals += count
      const ceiling = Number(ceilings[rule] ?? 0)
      parts.push(`${rule}=${count}${ceiling ? `/${ceiling}` : ''}`)
      if (!printOnly && count > ceiling) violations.push(`${repoPath}：${rule} = ${count} > 基线 ${ceiling}`)
    }
    if (parts.length > 0) lines.push(`  ${repoPath}：${parts.join(' ')}`)
  }

  if (printOnly) {
    process.stdout.write(`扫描 ${scanned.length} 个文件（排除生成物 ${skipped.length} 个），裸值合计 ${totals}\n`)
    process.stdout.write(`引用面检查：${danglingCount} 处指向未定义的变量\n`)
    for (const line of lines) process.stdout.write(`${line}\n`)
    process.exit(0)
  }

  if (violations.length > 0) {
    for (const violation of violations) process.stderr.write(`✗ ${violation}\n`)
    if (danglingCount === 0) {
      process.stderr.write('✗ 设计令牌棘轮只降不升：新代码请用 var(--ds-*)；确需例外就把它显式登记进基线\n')
    }
    process.exit(1)
  }

  process.stdout.write(
    `✅ 裸值棘轮未升高（扫 ${scanned.length} 个文件 / 排除生成物 ${skipped.length} 个；` +
      `规则 ${RULES.length} 条；裸值合计 ${totals}；引用面 ${danglingCount} 处未定义命名）\n`,
  )
  if (lines.length > 0) for (const line of lines) process.stdout.write(`${line}\n`)
  process.exit(0)
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  main()
}
