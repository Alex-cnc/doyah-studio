#!/usr/bin/env node
// Doyah Studio · Windows 侧表示层 · 设计令牌生成器（windows/App/tools/gen-tokens.mjs）
//
// 存在理由（§8.5.3 的「令牌取值单一来源」）：令牌取值属「一样」的五项之一，**不得各写一套**。
// 权威源 = macOS 侧 `Core/DesignTokens.swift`（纯数据，无平台绑定）；本生成器把它翻译成
// 前端能用的 CSS 变量 —— 于是「取值」只有一处，前端只是它的一个投影。
//
// 用法：
//   node tools/gen-tokens.mjs            写盘（生成物：src/theme/tokens.generated.css）
//   node tools/gen-tokens.mjs --check    只比对，不写盘；有漂移即 exit 1（闸门用它）
//
// 三条纪律（都是防「静默丢令牌」的）：
//   1. 每个分组的条数写死在 EXPECTED 里 —— 对侧改名 / 删项 / 加项 ⇒ 非零退出，不静默少生成几条；
//   2. 颜色枚举里出现「不是字面量 ThemeColor」的 case ⇒ 必须显式登记在 ALIASES 里，
//      否则非零退出（例：SyntaxTone.identifier 指向 TextTone.primary）；
//   3. 生成物头部写明「不许手改」，手改 ⇒ --check 判红。

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, resolve, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const appDir = resolve(here, '..')
const repoRoot = resolve(here, '../../..')
const argValue = (name) => {
  const index = process.argv.indexOf(name)
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : null
}
// `--source` / `--out` 只服务自测（夹具放临时目录）与手工排障：默认仍是真仓库那一对。
const swiftSource = resolve(argValue('--source') ?? resolve(repoRoot, 'Core/DesignTokens.swift'))
const outFile = resolve(argValue('--out') ?? resolve(appDir, 'src/theme/tokens.generated.css'))

/** 分组 → { swift 声明所属的块, 期望条数 } */
const EXPECTED = {
  spacing: { block: 'Spacing', count: 7 },
  radius: { block: 'Radius', count: 5 },
  metric: { block: 'Metrics', count: 22 },
  overlay: { block: 'Overlay', count: 4 }, // Selection + Zebra 各 2 条
  hairline: { block: 'Hairline', count: 2 },
  font: { block: 'TypeScale', count: 7 },
  surface: { block: 'Surface', count: 5 },
  text: { block: 'TextTone', count: 4 },
  status: { block: 'StatusTone', count: 3 },
  categorical: { block: 'CategoricalTone', count: 4 },
  syntax: { block: 'SyntaxTone', count: 5 }, // 5 条字面量 + identifier 走 ALIASES
}

/**
 * 颜色枚举里「不是字面量 ThemeColor」的 case —— 必须显式登记，否则生成器判错。
 * 键 = `枚举名.case`，值 = 它指向的 `枚举名.case`。
 */
const ALIASES = {
  'SyntaxTone.identifier': 'TextTone.primary',
}

const CSS_PREFIX = '--ds'

function fail(message) {
  process.stderr.write(`✗ gen-tokens：${message}\n`)
  process.exit(1)
}

// ── 解析 Swift 源 ───────────────────────────────────────────────────────────

function parseSwift(text) {
  const lines = text.split(/\r?\n/)
  const numbers = new Map() // 分组 → [{name, value, note}]
  const colors = new Map() // 枚举名 → [{name, light, dark}]
  const aliasesSeen = new Set()

  // 块栈：**按花括号深度**维护（不只看 `}` 行）—— Swift 里 `public var color: ThemeColor {`
  // 与 `switch self {` 也是花括号，只认「整行 `}`」会让枚举在第五行就被弹出（实测踩过）。
  const stack = [] // 元素 = 块名（`public enum X {` 给名，其余为 null）
  let pendingName = null

  const numbersBlockOf = {
    Spacing: 'spacing',
    Radius: 'radius',
    Metrics: 'metric',
    TypeScale: 'font',
    Hairline: 'hairline',
  }
  const colorBlockOf = {
    Surface: 'surface',
    TextTone: 'text',
    StatusTone: 'status',
    CategoricalTone: 'categorical',
    SyntaxTone: 'syntax',
  }

  const namedBlocks = () => stack.filter((entry) => entry !== null)
  const innermost = () => namedBlocks()[namedBlocks().length - 1]
  const parentOf = () => namedBlocks()[namedBlocks().length - 2]

  for (let i = 0; i < lines.length; i += 1) {
    const rawLine = lines[i]
    const lineNo = i + 1
    const braceSlashes = rawLine.indexOf('//')
    const line = braceSlashes >= 0 ? rawLine.slice(0, braceSlashes) : rawLine

    const enumMatch = line.match(/public enum (\w+)[^{]*\{/)
    if (enumMatch) pendingName = enumMatch[1]

    const opens = (line.match(/\{/g) ?? []).length
    const closes = (line.match(/\}/g) ?? []).length

    // 先按本行内容归位（声明行自己不承载 case），再结算深度。
    const letMatch = rawLine.match(/^\s*public static let (\w+): (CGFloat|Double) = ([\d.]+)\s*$/)
    if (letMatch) {
      const [, name, type, rawValue] = letMatch
      const value = Number(rawValue)
      if (!Number.isFinite(value)) fail(`第 ${lineNo} 行：数值解析失败（${rawValue}）`)
      if (!pendingName && !innermost()) fail(`第 ${lineNo} 行：数值声明不在任何具名块里（${name}）`)
      if (parentOf() === 'Overlay') {
        push(numbers, 'overlay', `${innermost().toLowerCase()}-${name}`, value)
      } else {
        const block = innermost()
        const key = numbersBlockOf[block]
        if (!key) fail(`第 ${lineNo} 行：出现了本生成器没登记的数字声明块（${stack.join('.')} / ${name}）—— 先登记再生成`)
        if (type === 'Double' && key !== 'hairline' && key !== 'overlay') {
          fail(`第 ${lineNo} 行：${key} 组的 ${name} 是 Double（本生成器只认 CGFloat）—— 结构变过，先看一遍`)
        }
        push(numbers, key, name, value)
      }
    }

    const colorMatch = rawLine.match(/^\s*case \.(\w+): return ThemeColor\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})\)\s*$/)
    if (colorMatch) {
      const [, name, light, dark] = colorMatch
      const enumName = innermost()
      if (!colorBlockOf[enumName]) {
        fail(`第 ${lineNo} 行：颜色落在没登记的枚举里（${enumName ?? '当前块无名字'}）`)
      }
      const list = colors.get(enumName) ?? []
      list.push({ name, light: light.toUpperCase(), dark: dark.toUpperCase() })
      colors.set(enumName, list)
    }

    const aliasMatch = rawLine.match(/^\s*case \.(\w+): return (\w+)\.(\w+)\.color\s*$/)
    if (aliasMatch) {
      const [, name, targetEnum, targetCase] = aliasMatch
      const enumName = innermost()
      const ref = `${targetEnum}.${targetCase}`
      if (ALIASES[`${enumName}.${name}`] !== ref) {
        fail(
          `第 ${lineNo} 行：${enumName}.${name} 指向 ${ref}，但 ALIASES 里没有登记（或登记的不是它）` +
            ' ⇒ 令牌取值可能已经换了来源，先核对再生成',
        )
      }
      aliasesSeen.add(`${enumName}.${name}`)
    }

    for (let n = 0; n < opens; n += 1) {
      stack.push(n === 0 && pendingName ? pendingName : null)
      pendingName = null
    }
    for (let n = 0; n < closes && stack.length > 0; n += 1) stack.pop()
  }

  for (const key of Object.keys(ALIASES)) {
    if (!aliasesSeen.has(key)) fail(`ALIASES 里登记的 ${key} 在 Swift 源里没有出现（别名被删了？）`)
  }
  return { numbers, colors }
}

function push(map, group, name, value) {
  const list = map.get(group) ?? []
  list.push({ name, value })
  map.set(group, list)
}

// ── 形状校验（条数 / 期望块）────────────────────────────────────────────────

function checkShape({ numbers, colors }) {
  const problems = []
  for (const [group, spec] of Object.entries(EXPECTED)) {
    const isColor = ['surface', 'text', 'status', 'categorical', 'syntax'].includes(group)
    const got = isColor
      ? colors.get(spec.block)?.length ?? 0
      : numbers.get(group)?.length ?? 0
    if (got !== spec.count) {
      problems.push(`${group}：期望 ${spec.count} 条，实际 ${got} 条（Swift 块 ${spec.block}）`)
    }
  }
  for (const group of numbers.keys()) if (!EXPECTED[group]) problems.push(`多出未登记的数字分组 ${group}`)
  for (const enumName of colors.keys()) {
    const group = Object.entries(EXPECTED).find(([, spec]) => spec.block === enumName)?.[0]
    if (!group) problems.push(`多出未登记的颜色枚举 ${enumName}`)
  }
  return problems
}

// ── 渲染 ────────────────────────────────────────────────────────────────────

const numberVar = (group, name) => `${CSS_PREFIX}-${group}-${name.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`

function render({ numbers, colors }, sourceInfo) {
  const lines = []
  lines.push('/*')
  lines.push(' * ⚠️ 生成物 —— 不许手改（改了下次生成即被覆盖，且 CI/闸门会判红）。')
  lines.push(' *')
  lines.push(' * 令牌取值的**单一来源** = macOS 侧 Core/DesignTokens.swift（§8.5.3「令牌取值」属「一样」的五项之一）。')
  lines.push(' * 重新生成：node windows/App/tools/gen-tokens.mjs（比对：--check）')
  lines.push(` * 源 sha256：${sourceInfo.sha256}`)
  lines.push(' */')
  lines.push('')
  lines.push(':root {')

  const emit = (group, comment) => {
    const list = numbers.get(group)
    if (!list) return
    lines.push(`  /* ${comment} */`)
    for (const { name, value } of list) lines.push(`  ${numberVar(group, name)}: ${value}px;`)
  }

  emit('spacing', '间距刻度（Spacing）')
  emit('radius', '圆角刻度（Radius）')
  emit('metric', '度量（Metrics）')
  emit('font', '排版级差（TypeScale）')

  lines.push('  /* 叠加层透明度（Overlay；取值是 0..1 的数，不是色值） */')
  for (const { name, value } of numbers.get('overlay') ?? []) {
    lines.push(`  ${numberVar('overlay', name)}: ${value};`)
  }
  lines.push('  /* 发丝线透明度（Hairline） */')
  for (const { name, value } of numbers.get('hairline') ?? []) {
    lines.push(`  ${numberVar('hairline', name)}: ${value};`)
  }
  lines.push('')

  // 颜色：浅色档写在 :root，深色档写在 [data-theme='dark'] 与系统跟随块里。
  const colorVar = (group, name) => `${CSS_PREFIX}-color-${group}-${name}`

  const colorGroups = [
    ['surface', 'Surface', '表面层次（明度由暗到亮：window → sidebar → content → panel → raised）'],
    ['text', 'TextTone', '文本层级'],
    ['status', 'StatusTone', '状态色'],
    ['categorical', 'CategoricalTone', '分类色（身份色，不是状态色）'],
    ['syntax', 'SyntaxTone', '语法着色'],
  ]

  lines.push('  /* 浅色档 */')
  for (const [group, enumName, comment] of colorGroups) {
    lines.push(`  /* ${comment} */`)
    for (const { name, light } of colors.get(enumName) ?? []) {
      const aliasTarget = ALIASES[`${enumName}.${name}`]
      if (aliasTarget) {
        const [targetEnum, targetCase] = aliasTarget.split('.')
        const targetGroup = Object.entries(EXPECTED).find(([, spec]) => spec.block === targetEnum)?.[0]
        lines.push(`  ${colorVar(group, name)}: var(${colorVar(targetGroup, targetCase)});`)
        continue
      }
      lines.push(`  ${colorVar(group, name)}: #${light};`)
    }
  }
  lines.push('}')
  lines.push('')

  lines.push(":root[data-theme='dark'] {")
  lines.push('  /* 深色档 */')
  for (const [group, enumName] of colorGroups) {
    for (const { name, dark } of colors.get(enumName) ?? []) {
      const aliasTarget = ALIASES[`${enumName}.${name}`]
      if (aliasTarget) {
        const [targetEnum, targetCase] = aliasTarget.split('.')
        const targetGroup = Object.entries(EXPECTED).find(([, spec]) => spec.block === targetEnum)?.[0]
        lines.push(`  ${colorVar(group, name)}: var(${colorVar(targetGroup, targetCase)});`)
        continue
      }
      lines.push(`  ${colorVar(group, name)}: #${dark};`)
    }
  }
  lines.push('}')
  lines.push('')

  // 系统跟随：只在没有显式 data-theme 时生效（显式选择优先，口径与 macOS 侧一致）。
  lines.push('@media (prefers-color-scheme: dark) {')
  lines.push("  :root:not([data-theme='light']):not([data-theme='dark']) {")
  for (const [group, enumName] of colorGroups) {
    for (const { name, dark } of colors.get(enumName) ?? []) {
      const aliasTarget = ALIASES[`${enumName}.${name}`]
      if (aliasTarget) {
        const [targetEnum, targetCase] = aliasTarget.split('.')
        const targetGroup = Object.entries(EXPECTED).find(([, spec]) => spec.block === targetEnum)?.[0]
        lines.push(`    ${colorVar(group, name)}: var(${colorVar(targetGroup, targetCase)});`)
        continue
      }
      lines.push(`    ${colorVar(group, name)}: #${dark};`)
    }
  }
  lines.push('  }')
  lines.push('}')
  lines.push('')
  return lines.join('\n')
}

// ── 主流程 ─────────────────────────────────────────────────────────────────

const { createHash } = await import('node:crypto')

if (!existsSync(swiftSource)) {
  fail(`权威令牌源不在盘上：${relative(repoRoot, swiftSource)}（§8.5.3：令牌取值没有基准 ⇒ 不许生成，更不许通过）`)
}

const swiftText = readFileSync(swiftSource, 'utf8')
const sha256 = createHash('sha256').update(swiftText, 'utf8').digest('hex')
const parsed = parseSwift(swiftText)
const problems = checkShape(parsed)
if (problems.length > 0) {
  for (const problem of problems) process.stderr.write(`✗ ${problem}\n`)
  fail('Swift 令牌源的形状与 EXPECTED 对不上（对侧改名 / 删项 / 加项）⇒ 先核对，别让前端悄悄少几个变量')
}

const output = render(parsed, { sha256 })
const outRelative = relative(repoRoot, outFile).split(sep).join('/')
const checkOnly = process.argv.includes('--check')

if (checkOnly) {
  if (!existsSync(outFile)) fail(`生成物不在盘上：${outRelative}（跑一次 node tools/gen-tokens.mjs）`)
  const onDisk = readFileSync(outFile, 'utf8')
  if (onDisk !== output) {
    fail(`生成物与 Swift 令牌源不一致：${outRelative} —— 手改过生成物，或改了源没重新生成`)
  }
  process.stdout.write(`✅ 令牌生成物与源一致（${outRelative}；源 sha256 ${sha256.slice(0, 12)}）\n`)
  process.exit(0)
}

mkdirSync(dirname(outFile), { recursive: true })
writeFileSync(outFile, output, 'utf8')
const counts = [
  ...[...parsed.numbers.entries()].map(([group, list]) => `${group} ${list.length}`),
  ...[...parsed.colors.entries()].map(([group, list]) => `${group} ${list.length}`),
].join(' / ')
process.stdout.write(`✅ 已生成 ${outRelative}（${counts}；源 sha256 ${sha256.slice(0, 12)}）\n`)
