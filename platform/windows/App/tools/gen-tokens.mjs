#!/usr/bin/env node
// Doyah Studio · Windows 侧表示层 · 设计令牌生成器（platform/windows/App/tools/gen-tokens.mjs）
//
// 存在理由（§8.5.3 的「令牌取值单一来源」）：令牌取值属「一样」的五项之一，**不得各写一套**。
// 权威源 = macOS 侧 `Core/`（纯数据、无平台绑定），**分成两个文件**（2026-09-29 L-80 ㈠ 起）：
//   · `Core/DesignTokens.swift` —— **角色**（枚举 + case 名 + 用法规矩）＋ 数值刻度（Spacing / Radius /
//     Metrics / Overlay / TypeScale）＋ `CategoricalTone`（唯一与主题无关的色，身份色）；
//   · `Core/DesignTheme.swift`  —— **值表**：每主题一份 `ThemePalette`（18 个 `ThemeColor(light, dark)`
//     ＋ `hairlineLight` ＋ `hairlineDarkAlpha`）。
// 本生成器把这两份翻译成前端能用的 CSS 变量 —— 于是「取值」只有一处，前端只是它的一个投影。
//
// 用法：
//   node tools/gen-tokens.mjs                     写盘（生成物：src/theme/tokens.generated.css）
//   node tools/gen-tokens.mjs --check             只比对，不写盘；有漂移即 exit 1（闸门用它）
//   node tools/gen-tokens.mjs --source <f> --palette-source <f> --out <f>   自测 / 手工排障
//
// 四条纪律（都是防「静默丢令牌 / 悄悄换来源」的）：
//   1. 每个分组与**每个主题**的条数写死在 EXPECTED_* 里 —— 对侧改名 / 删项 / 加项 / 少一个主题
//      ⇒ 非零退出，不静默少生成几条；
//   2. 颜色角色一律从 `color(in: theme)` 的 `case .x: return palette.y` **解析出来**（不手抄映射），
//      值表字段若没被任何角色引用、也不在 `PALETTE_CONSUMED_WITHOUT_ROLE` 里 ⇒ 判错
//      （防「值表多了一个角色而本侧没生成」与「本侧生成的东西源里没有」两个方向）；
//   3. `SyntaxTone` 这类「不是字面量」的 case 必须显式登记在 ALIASES 里并与源里解析出的映射逐条相符，
//      否则非零退出（例：`SyntaxTone.identifier` 指向 `TextTone.primary`）；
//   4. 生成物头部写明「不许手改」，手改 ⇒ --check 判红。
//
// 主题块约定（§9.2「每个主题一个变量块」；与 macOS 侧「主题自带配套强调色」口径同构）：
//   `:root` / `:root[data-theme='dark']` / 系统跟随块 = **默认主题**（`DesignTheme.fallback`）的值；
//   `:root[data-theme-scheme='<id>']`（+ `[data-theme='dark']`、+ 系统跟随块）= 该主题的值。
//   属性选择器特异性高于 `:root`，所以「写了 data-theme-scheme」时一定压过默认块。

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, resolve, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const appDir = resolve(here, '..')
const repoRoot = resolve(here, '../../../..')
const argValue = (name) => {
  const index = process.argv.indexOf(name)
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : null
}
// `--source` / `--palette-source` / `--out` 只服务自测（夹具放临时目录）与手工排障：默认仍是真仓库那一对。
const roleSource = resolve(argValue('--source') ?? resolve(repoRoot, 'Core/DesignTokens.swift'))
const paletteSource = resolve(argValue('--palette-source') ?? resolve(repoRoot, 'Core/DesignTheme.swift'))
const outFile = resolve(argValue('--out') ?? resolve(appDir, 'src/theme/tokens.generated.css'))
const themesFile = resolve(argValue('--themes-out') ?? resolve(appDir, 'src/theme/themes.generated.ts'))

/** 数值刻度：分组 → { swift 声明所属的块, 期望条数 } */
const EXPECTED_NUMBERS = {
  spacing: { block: 'Spacing', count: 7 },
  radius: { block: 'Radius', count: 5 },
  metric: { block: 'Metrics', count: 22 },
  overlay: { block: 'Overlay', count: 4 }, // Selection + Zebra 各 2 条
  font: { block: 'TypeScale', count: 7 },
}

/**
 * 颜色枚举 → { css 分组, 期望条数, 取值来源 }：
 *   `role`    = 值在主题值表里（`case .x: return palette.y`）⇒ 每主题一份；
 *   `literal` = 值就写在角色枚举里（`case .x: return ThemeColor(light: …, dark: …)`）⇒ 与主题无关；
 *   `alias`   = 值指向另一个角色（`case .x: return Enum.case.color(in: theme)`）⇒ 必须登记在 ALIASES。
 */
const EXPECTED_COLORS = {
  Surface: { group: 'surface', count: 5, from: 'role' },
  TextTone: { group: 'text', count: 5, from: 'role' },
  StatusTone: { group: 'status', count: 3, from: 'role' },
  AccentFamily: { group: 'accent', count: 5, from: 'role' },
  CategoricalTone: { group: 'categorical', count: 4, from: 'literal' },
  SyntaxTone: { group: 'syntax', count: 6, from: 'alias' },
}

/**
 * 颜色枚举里「不是字面量」的 case 指向谁 —— 必须显式登记，且与源里解析出的映射**逐条相符**。
 * 键 = `枚举名.case`，值 = 它指向的 `枚举名.case`。
 */
const ALIASES = {
  'SyntaxTone.keyword': 'AccentFamily.accentGlow',
  'SyntaxTone.identifier': 'TextTone.primary',
  'SyntaxTone.string': 'AccentFamily.warm',
  'SyntaxTone.number': 'AccentFamily.teal',
  'SyntaxTone.function': 'AccentFamily.accent',
  'SyntaxTone.comment': 'TextTone.tertiary',
}

/**
 * 值表里**不由颜色角色引用**的字段 —— 必须在这里逐条登记（登记即声明「本侧打算怎么用」）。
 * 未登记又没被角色引用 ⇒ 判错：那说明源里多了个没人消费的角色，或本侧漏生成了一组变量。
 * 每个主题必须出现的条数 = 18 色 + 这两个（由 EXPECTED_THEME 钉住）。
 */
const PALETTE_CONSUMED_WITHOUT_ROLE = {
  id: '主题 id 自身（写进 `[data-theme-scheme="…"]` 选择器，不生成变量）',
  hairlineLight: '浅色发丝线的**实色**（随主题）⇒ `--ds-color-hairline-light`',
  hairlineDarkAlpha: '深色发丝线的白色透明度（随主题）⇒ `--ds-hairline-dark-alpha`',
}

/** 每个主题值表必须恰好这么多字段（id + 18 色 + 发丝线两参数）。 */
const EXPECTED_THEME_FIELDS = Object.keys(PALETTE_CONSUMED_WITHOUT_ROLE).length + 18

/** 每个主题的 CSS 块数（浅色 / 显式深色 / 系统跟随）。 */
const THEME_BLOCK_FORMS = 3

const CSS_PREFIX = '--ds'

function fail(message) {
  process.stderr.write(`✗ gen-tokens：${message}\n`)
  process.exit(1)
}

// ── 解析：数值刻度 + 颜色角色的归属（Core/DesignTokens.swift）─────────────────

function parseRoleSource(text) {
  const lines = text.split(/\r?\n/)
  const numbers = new Map() // 分组 → [{name, value}]
  const roles = new Map() // 枚举名 → Map(case → palette 字段)
  const literals = new Map() // 枚举名 → [{name, light, dark}]
  const aliasSeen = new Map() // `枚举.case` → `枚举.case`

  // 块栈：**按花括号深度**维护（不只看 `}` 行）—— Swift 里 `public var color: ThemeColor {`
  // 与 `switch self {` 也是花括号，只认「整行 `}`」会让枚举在第五行就被弹出（实测踩过）。
  const stack = []
  let pendingName = null

  const numbersBlockOf = {
    Spacing: 'spacing',
    Radius: 'radius',
    Metrics: 'metric',
    TypeScale: 'font',
  }

  const namedBlocks = () => stack.filter((entry) => entry !== null)
  const innermost = () => namedBlocks()[namedBlocks().length - 1]
  const parentOf = () => namedBlocks()[namedBlocks().length - 2]

  for (let i = 0; i < lines.length; i += 1) {
    const rawLine = lines[i]
    const lineNo = i + 1
    const commentStart = rawLine.indexOf('//')
    const line = commentStart >= 0 ? rawLine.slice(0, commentStart) : rawLine

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
        if (type === 'Double' && key !== 'overlay') {
          fail(`第 ${lineNo} 行：${key} 组的 ${name} 是 Double（本生成器只认 CGFloat）—— 结构变过，先看一遍`)
        }
        push(numbers, key, name, value)
      }
    }

    // 取值在主题值表里（`case .x: return palette.y`）—— 角色与值的接线由这一行给出。
    const roleMatch = rawLine.match(/^\s*case \.(\w+): return palette\.(\w+)\s*$/)
    if (roleMatch) {
      const [, name, field] = roleMatch
      const enumName = innermost()
      if (!enumName || !EXPECTED_COLORS[enumName] || EXPECTED_COLORS[enumName].from !== 'role') {
        fail(`第 ${lineNo} 行：role 取色落在没登记的枚举里（${enumName ?? '当前块无名字'}）`)
      }
      const list = roles.get(enumName) ?? new Map()
      if (list.has(name)) fail(`第 ${lineNo} 行：${enumName}.${name} 重复声明`)
      list.set(name, field)
      roles.set(enumName, list)
    }

    // 与主题无关的字面量取色（`CategoricalTone`）。
    const literalMatch = rawLine.match(/^\s*case \.(\w+): return ThemeColor\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})\)\s*$/)
    if (literalMatch) {
      const [, name, light, dark] = literalMatch
      const enumName = innermost()
      if (!enumName || !EXPECTED_COLORS[enumName] || EXPECTED_COLORS[enumName].from !== 'literal') {
        fail(`第 ${lineNo} 行：字面量取色落在没登记的枚举里（${enumName ?? '当前块无名字'}）—— 若它本该随主题，请改走主题值表`)
      }
      const list = literals.get(enumName) ?? []
      list.push({ name, light: light.toUpperCase(), dark: dark.toUpperCase() })
      literals.set(enumName, list)
    }

    // 别名（指向另一个角色）—— 必须登记在 ALIASES。
    const aliasMatch = rawLine.match(/^\s*case \.(\w+): return (\w+)\.(\w+)\.color\(in: theme\)\s*$/)
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
      aliasSeen.set(`${enumName}.${name}`, ref)
    }

    for (let n = 0; n < opens; n += 1) {
      stack.push(n === 0 && pendingName ? pendingName : null)
      pendingName = null
    }
    for (let n = 0; n < closes && stack.length > 0; n += 1) stack.pop()
  }

  for (const key of Object.keys(ALIASES)) {
    if (!aliasSeen.has(key)) fail(`ALIASES 里登记的 ${key} 在 Swift 源里没有出现（别名被删了，或写法变了）`)
  }
  return { numbers, roles, literals }
}

function push(map, group, name, value) {
  const list = map.get(group) ?? []
  list.push({ name, value })
  map.set(group, list)
}

// ── 解析：主题枚举的 id（Core/DesignTheme.swift）─────────────────────────────
//
// `ThemePalette` 的 `id:` 写的是**枚举 case 名**（`.techBlue`），而 CSS 里的取值必须是
// `DesignTheme.rawValue`（`tech-blue`）—— 两者是两回事，硬把 case 名写进选择器会让前端
// 永远匹配不上（属性选择器不报错，只是不生效：又一例「静默失效」）。

/**
 * 「推导草案」判定式的解析（`public var isDerivedDraft: Bool { … }`）。
 *
 * 两种写法都认；**认不出一律判红**（不猜、不退回旧口径 —— 猜错的后果是界面把实际值标成
 * 「推导草案」或反过来）：
 *   · `self != .<case>`                  —— 补集写法（除该主题外都算推导草案）；
 *   · `self == .<a> || self == .<b> …`   —— **逐主题点名**（2026-10-01 起对侧写法：
 *     新增主题必须显式决定自己算不算推导）。点名的 case 必须都在 `DesignTheme` 里（笔误即判红）。
 */
function parseDerivedDraft(text, ids) {
  const match = text.match(/public var isDerivedDraft: Bool \{\s*([^}]*?)\s*\}/)
  if (!match) fail('解析不到 `isDerivedDraft` 的判定式（哪个主题还是「推导草案」的唯一来源）—— 写法变了？')
  const expr = match[1]

  const complement = expr.match(/^self != \.(\w+)$/)
  if (complement) {
    if (!ids.has(complement[1])) {
      fail(`isDerivedDraft 的 \`!= .${complement[1]}\` 不在 DesignTheme 的 case 列表里（改名了？）`)
    }
    return new Set([...ids.keys()].filter((caseName) => caseName !== complement[1]))
  }

  const parts = expr.split('||').map((part) => part.trim())
  if (parts.length > 0 && parts.every((part) => /^self == \.\w+$/.test(part))) {
    const cases = parts.map((part) => part.replace(/^self == \./, ''))
    for (const caseName of cases) {
      if (!ids.has(caseName)) {
        fail(`isDerivedDraft 里点名的 \`.${caseName}\` 不在 DesignTheme 的 case 列表里（笔误？）`)
      }
    }
    if (new Set(cases).size !== cases.length) fail('isDerivedDraft 的判定式里有重复点名的主题')
    return new Set(cases)
  }

  fail(
    `isDerivedDraft 的判定式写法没登记过（${expr}）—— 只认「\`self != .<case>\`」与` +
      '「`self == .<case>` 逐主题点名」两种；先核对语义再登记，别让本侧自己猜',
  )
  return new Set()
}

function parseThemeMeta(text) {
  const enumMatch = text.match(/public enum DesignTheme: [^{]*\{/)
  if (!enumMatch) fail('值表源里找不到 `public enum DesignTheme`（主题 id 的唯一来源）')
  const body = text.slice(text.indexOf(enumMatch[0]))
  const ids = new Map()
  for (const line of body.split(/\r?\n/)) {
    const match = line.match(/^\s*case (\w+) = "([^"]+)"\s*$/)
    if (match) ids.set(match[1], match[2])
  }
  if (ids.size < 2) fail(`DesignTheme 只解析到 ${ids.size} 个主题 id（写法变了？）`)

  const fallback = text.match(/public static let fallback = DesignTheme\.(\w+)/)
  if (!fallback) fail('解析不到 `DesignTheme.fallback`（默认主题的唯一来源）—— 写法变了？')
  const derivedCases = parseDerivedDraft(text, ids)

  const nameKeys = new Map()
  for (const line of body.split(/\r?\n/)) {
    const match = line.match(/^\s*case \.(\w+): return \.(designTheme\w+)\s*$/)
    if (match) nameKeys.set(match[1], match[2])
  }
  for (const caseName of ids.keys()) {
    if (!nameKeys.has(caseName)) fail(`DesignTheme.${caseName} 没有 nameKey（显示名的唯一来源）—— 写法变了？`)
  }

  return { ids, fallbackCase: fallback[1], derivedCases, nameKeys }
}

function resolveThemeIds(palettes, meta) {
  if (!meta.ids.has(meta.fallbackCase)) fail(`fallback 指向的 ${meta.fallbackCase} 不在主题 case 列表里`)
  for (const palette of palettes) {
    const id = palette.fields.get('id')
    const caseName = id?.value
    const rawId = meta.ids.get(caseName)
    if (!rawId) {
      fail(`${palette.swiftName} 的 id 是 .${caseName ?? '（缺）'}，但 DesignTheme 里没有这个 case 的 rawValue（改名了？）`)
    }
    id.kind = 'themeId'
    id.caseName = caseName
    id.value = rawId
    id.fallback = caseName === meta.fallbackCase
    // 「推导草案」= 源里那条判定式（`self != .<case>` 或 `self == .<a> || …` 逐主题点名）
    // —— 本侧不另抄一份，免得不一致时界面照旧标着推导值。
    id.derivedDraft = meta.derivedCases.has(caseName)
    id.nameKey = meta.nameKeys.get(caseName)
  }
}

// ── 解析：主题值表（Core/DesignTheme.swift）──────────────────────────────────

function parsePalettes(text) {
  const lines = text.split(/\r?\n/)
  const palettes = []
  let current = null

  for (let i = 0; i < lines.length; i += 1) {
    const rawLine = lines[i]
    const lineNo = i + 1

    if (!current) {
      const open = rawLine.match(/public static let (\w+) = ThemePalette\(/)
      if (open) current = { swiftName: open[1], lineNo, fields: new Map(), order: [] }
      continue
    }

    if (/^\s*\)\s*$/.test(rawLine)) {
      palettes.push(current)
      current = null
      continue
    }

    const idMatch = rawLine.match(/^\s*id: \.(\w+),?\s*$/)
    if (idMatch) {
      setField(current, 'id', { kind: 'themeId', value: idMatch[1] }, lineNo)
      continue
    }

    const colorMatch = rawLine.match(/^\s*(\w+): ThemeColor\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})\),?\s*$/)
    if (colorMatch) {
      const [, name, light, dark] = colorMatch
      setField(current, name, { kind: 'color', light: light.toUpperCase(), dark: dark.toUpperCase() }, lineNo)
      continue
    }

    const hexMatch = rawLine.match(/^\s*(\w+): 0x([0-9A-Fa-f]{6}),?\s*$/)
    if (hexMatch) {
      setField(current, hexMatch[1], { kind: 'hex', light: hexMatch[2].toUpperCase() }, lineNo)
      continue
    }

    const numberMatch = rawLine.match(/^\s*(\w+): ([\d.]+),?\s*$/)
    if (numberMatch) {
      setField(current, numberMatch[1], { kind: 'number', value: Number(numberMatch[2]) }, lineNo)
      continue
    }

    if (rawLine.trim() !== '') {
      fail(`第 ${lineNo} 行：值表里出现了本生成器没认出的字段写法（${rawLine.trim()}）—— 先登记再生成`)
    }
  }

  if (current) fail(`值表第 ${current.lineNo} 行开始的主题没有收尾括号（括号深度变了？）`)
  return palettes
}

function setField(palette, name, value, lineNo) {
  if (palette.fields.has(name)) fail(`第 ${lineNo} 行：值表 ${palette.swiftName} 里 ${name} 重复声明`)
  palette.fields.set(name, value)
  palette.order.push(name)
}

// ── 形状校验（条数 / 期望块 / 未消费字段）──────────────────────────────────

function checkShape({ numbers, roles, literals, palettes }) {
  const problems = []

  for (const [group, spec] of Object.entries(EXPECTED_NUMBERS)) {
    const got = numbers.get(group)?.length ?? 0
    if (got !== spec.count) problems.push(`${group}：期望 ${spec.count} 条，实际 ${got} 条（Swift 块 ${spec.block}）`)
  }
  for (const group of numbers.keys()) if (!EXPECTED_NUMBERS[group]) problems.push(`多出未登记的数字分组 ${group}`)

  if (palettes.length < 2) problems.push(`主题值表只解析到 ${palettes.length} 份（至少要有默认主题 + 一个备选；写法变了？）`)

  const consumedFields = new Set()
  for (const [enumName, spec] of Object.entries(EXPECTED_COLORS)) {
    const got =
      spec.from === 'role'
        ? roles.get(enumName)?.size ?? 0
        : spec.from === 'literal'
          ? literals.get(enumName)?.length ?? 0
          : Object.keys(ALIASES).filter((key) => key.startsWith(`${enumName}.`)).length
    if (got !== spec.count) problems.push(`${spec.group}：期望 ${spec.count} 条，实际 ${got} 条（Swift 枚举 ${enumName}）`)
    if (spec.from !== 'role') continue
    for (const field of roles.get(enumName).values()) consumedFields.add(field)
  }
  for (const enumName of roles.keys()) if (!EXPECTED_COLORS[enumName]) problems.push(`多出未登记的颜色枚举 ${enumName}`)
  for (const enumName of literals.keys()) if (!EXPECTED_COLORS[enumName]) problems.push(`多出未登记的颜色枚举 ${enumName}`)

  for (const palette of palettes) {
    if (palette.fields.size !== EXPECTED_THEME_FIELDS) {
      problems.push(
        `${palette.swiftName}：期望 ${EXPECTED_THEME_FIELDS} 个字段，实际 ${palette.fields.size} 个（18 色 + ${Object.keys(PALETTE_CONSUMED_WITHOUT_ROLE).length} 个非角色字段）`,
      )
    }
    for (const field of palette.order) {
      if (consumedFields.has(field) || PALETTE_CONSUMED_WITHOUT_ROLE[field]) continue
      problems.push(`${palette.swiftName}.${field}：值表里多出一个没人消费的字段（颜色角色没引用它、也没登记进 PALETTE_CONSUMED_WITHOUT_ROLE）`)
    }
    for (const field of consumedFields) {
      if (!palette.fields.has(field)) problems.push(`${palette.swiftName} 缺字段 ${field}（有颜色角色引用它）`)
    }
    const id = palette.fields.get('id')
    if (!id || id.kind !== 'themeId') problems.push(`${palette.swiftName} 缺 id（主题选择器的取值来源）`)
  }

  const ids = palettes.map((palette) => palette.fields.get('id')?.value)
  if (new Set(ids).size !== ids.length) problems.push(`主题 id 有重复：${ids.join(' / ')}`)

  const fallbackCount = palettes.filter((palette) => palette.fields.get('id')?.fallback).length
  if (fallbackCount !== 1) problems.push(`默认主题（DesignTheme.fallback）应当恰好一个，实际 ${fallbackCount} 个`)

  return problems
}

// ── 渲染 ────────────────────────────────────────────────────────────────────

const numberVar = (group, name) => `${CSS_PREFIX}-${group}-${name.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`
const colorVar = (group, name) => `${CSS_PREFIX}-color-${group}-${name}`

function render({ numbers, roles, literals, palettes }, sourceInfo) {
  const lines = []
  const colorGroups = Object.entries(EXPECTED_COLORS)
    .filter(([, spec]) => spec.from === 'role')
    .map(([enumName, spec]) => [spec.group, enumName])
  const categoricalEnum = Object.entries(EXPECTED_COLORS).find(([, spec]) => spec.from === 'literal')?.[0]

  lines.push('/*')
  lines.push(' * ⚠️ 生成物 —— 不许手改（改了下次生成即被覆盖，且 CI/闸门会判红）。')
  lines.push(' *')
  lines.push(' * 令牌取值的**单一来源** = macOS 侧 Core/DesignTokens.swift（角色与刻度）')
  lines.push(' *                        + Core/DesignTheme.swift（每主题一份值表；§8.5.3「令牌取值」属「一样」的五项之一）。')
  lines.push(' * 重新生成：node platform/windows/App/tools/gen-tokens.mjs（比对：--check）')
  lines.push(` * 源 sha256：role ${sourceInfo.roleSha256.slice(0, 12)} / palette ${sourceInfo.paletteSha256.slice(0, 12)}`)
  lines.push(' *')
  lines.push(' * 主题块：`:root` 三态 = 默认主题的值；`[data-theme-scheme="<id>"]` 三态 = 该主题的值')
  lines.push(' * （属性选择器特异性更高 ⇒ 写了 data-theme-scheme 时一定压过默认块）。')
  lines.push(' */')
  lines.push('')
  lines.push(':root {')

  const emitNumber = (group, comment) => {
    const list = numbers.get(group)
    if (!list) return
    lines.push(`  /* ${comment} */`)
    for (const { name, value } of list) lines.push(`  ${numberVar(group, name)}: ${value}px;`)
  }

  emitNumber('spacing', '间距刻度（Spacing）')
  emitNumber('radius', '圆角刻度（Radius）')
  emitNumber('metric', '度量（Metrics）')
  emitNumber('font', '排版级差（TypeScale）')
  lines.push('  /* 叠加层透明度（Overlay；取值是 0..1 的数，不是色值） */')
  for (const { name, value } of numbers.get('overlay') ?? []) {
    lines.push(`  ${numberVar('overlay', name)}: ${value};`)
  }
  lines.push('')

  const categoricalEntries = literals.get(categoricalEnum) ?? []

  const emitColors = (palette, mode, indent) => {
    const pad = ' '.repeat(indent)
    for (const [group, enumName] of colorGroups) {
      const roleList = roles.get(enumName) ?? new Map()
      for (const [name, field] of roleList) {
        const value = palette.fields.get(field)
        if (!value) fail(`${palette.swiftName} 缺字段 ${field}（角色 ${enumName}.${name} 引用它）`)
        lines.push(`${pad}${colorVar(group, name)}: #${value[mode]};`)
      }
    }
    // 语法六档：一律是别的角色的变量引用（取值不在这里，改一处两端同时变）。
    for (const key of Object.keys(ALIASES)) {
      const [enumName, name] = key.split('.')
      if (enumName !== 'SyntaxTone') continue
      const [targetEnum, targetCase] = ALIASES[key].split('.')
      const targetGroup = EXPECTED_COLORS[targetEnum]?.group
      if (!targetGroup) fail(`ALIASES 的 ${key} 指向没登记的分组（${targetEnum}）`)
      lines.push(`${pad}${colorVar('syntax', name)}: var(${colorVar(targetGroup, targetCase)});`)
    }
    const hairlineLight = palette.fields.get('hairlineLight')
    const hairlineDarkAlpha = palette.fields.get('hairlineDarkAlpha')
    if (mode === 'light') {
      lines.push(`${pad}${CSS_PREFIX}-color-hairline-light: #${hairlineLight.light};`)
    } else {
      lines.push(`${pad}${CSS_PREFIX}-hairline-dark-alpha: ${hairlineDarkAlpha.value};`)
    }
  }

  const emitCategorical = (mode, indent) => {
    const pad = ' '.repeat(indent)
    for (const { name, light, dark } of categoricalEntries) {
      lines.push(`${pad}${colorVar('categorical', name)}: #${mode === 'light' ? light : dark};`)
    }
  }

  // ── 默认主题（DesignTheme.fallback）写在 `:root` 三态上 ──
  const fallback = palettes[0]
  lines.push('  /* 浅色档：默认主题（与下面 [data-theme-scheme] 的第一块同值） */')
  emitCategorical('light', 2)
  emitColors(fallback, 'light', 2)
  lines.push('}')
  lines.push('')

  lines.push(":root[data-theme='dark'] {")
  lines.push('  /* 深色档：默认主题 */')
  emitCategorical('dark', 2)
  emitColors(fallback, 'dark', 2)
  lines.push('}')
  lines.push('')

  lines.push('@media (prefers-color-scheme: dark) {')
  lines.push("  :root:not([data-theme='light']):not([data-theme='dark']) {")
  emitColors(fallback, 'dark', 4)
  lines.push('  }')
  lines.push('}')
  lines.push('')

  // ── 每个主题一个变量块（§9.2）──
  for (const palette of palettes) {
    const id = palette.fields.get('id').value
    const caseName = palette.fields.get('id').caseName
    lines.push(`/* 主题：${id}（${palette.swiftName} / DesignTheme.${caseName}）—— ${THEME_BLOCK_FORMS} 态 */`)
    lines.push(`:root[data-theme-scheme='${id}'] {`)
    emitCategorical('light', 2)
    emitColors(palette, 'light', 2)
    lines.push('}')
    lines.push('')
    lines.push(`:root[data-theme-scheme='${id}'][data-theme='dark'] {`)
    emitColors(palette, 'dark', 2)
    lines.push('}')
    lines.push('')
    lines.push('@media (prefers-color-scheme: dark) {')
    lines.push(`  :root[data-theme-scheme='${id}']:not([data-theme='light']):not([data-theme='dark']) {`)
    emitColors(palette, 'dark', 4)
    lines.push('  }')
    lines.push('}')
    lines.push('')
  }

  return lines.join('\n')
}

// ── 渲染：主题集（供前端下拉用；同样是从源派生，不手抄）─────────────────────

function renderThemeModule(palettes) {
  const lines = []
  lines.push('// ⚠️ 生成物 —— 不许手改（改了下次生成即被覆盖，且闸门会判红）。')
  lines.push('//')
  lines.push('// 主题集（§9.2「候选同名同值」）：id / 显示名键 / 是否「推导草案」/ 谁是默认主题')
  lines.push('// 全部由 `tools/gen-tokens.mjs` 从 macOS 侧 Core/DesignTheme.swift 解析 —— 本侧不手抄，')
  lines.push('// 免得对侧改了主题集（改名 / 增删 / 值到位后不再是推导草案）而这边照旧显示。')
  lines.push('// 重新生成：node platform/windows/App/tools/gen-tokens.mjs（比对：--check）')
  lines.push('')
  lines.push('export const THEME_SCHEMES = [')
  for (const palette of palettes) {
    const id = palette.fields.get('id')
    lines.push(
      `  { id: '${id.value}', swift: '${id.caseName}', nameKey: '${id.nameKey}', fallback: ${id.fallback}, derivedDraft: ${id.derivedDraft} },`,
    )
  }
  lines.push('] as const')
  lines.push('')
  lines.push("export type ThemeSchemeId = (typeof THEME_SCHEMES)[number]['id']")
  lines.push('')
  return lines.join('\n')
}

// ── 主流程 ─────────────────────────────────────────────────────────────────

const { createHash } = await import('node:crypto')

for (const [label, path] of [
  ['角色与刻度源', roleSource],
  ['主题值表源', paletteSource],
]) {
  if (!existsSync(path)) {
    fail(`${label}不在盘上：${relative(repoRoot, path)}（§8.5.3：令牌取值没有基准 ⇒ 不许生成，更不许通过）`)
  }
}

const roleText = readFileSync(roleSource, 'utf8')
const paletteText = readFileSync(paletteSource, 'utf8')
const sha256 = (text) => createHash('sha256').update(text, 'utf8').digest('hex')
const sourceInfo = { roleSha256: sha256(roleText), paletteSha256: sha256(paletteText) }

const parsed = {
  ...parseRoleSource(roleText),
  palettes: parsePalettes(paletteText),
}
resolveThemeIds(parsed.palettes, parseThemeMeta(paletteText))
const problems = checkShape(parsed)
if (problems.length > 0) {
  for (const problem of problems) process.stderr.write(`✗ ${problem}\n`)
  fail('Swift 令牌源的形状与 EXPECTED 对不上（对侧改名 / 删项 / 加项 / 值表换了结构）⇒ 先核对，别让前端悄悄少几个变量')
}

const output = render(parsed, sourceInfo)
const outRelative = relative(repoRoot, outFile).split(sep).join('/')
const themesRelative = relative(repoRoot, themesFile).split(sep).join('/')
const checkOnly = process.argv.includes('--check')

// 两个生成物（CSS 变量 + 主题集 TS）同一套来源、同一套形状校验：比对 / 写盘都走这一张表。
const artifacts = [
  { file: outFile, relative: outRelative, label: 'CSS 变量', text: output },
  { file: themesFile, relative: themesRelative, label: '主题集 TS', text: renderThemeModule(parsed.palettes) },
]

if (checkOnly) {
  for (const artifact of artifacts) {
    if (!existsSync(artifact.file)) {
      fail(`生成物不在盘上：${artifact.relative}（跑一次 node tools/gen-tokens.mjs）`)
    }
    if (readFileSync(artifact.file, 'utf8') !== artifact.text) {
      fail(`生成物与 Swift 令牌源不一致：${artifact.relative} —— 手改过生成物，或改了源没重新生成`)
    }
  }
  process.stdout.write(
    `✅ 令牌生成物与源一致（${artifacts.length} 份；theme ${parsed.palettes.length} 个）\n`,
  )
  process.exit(0)
}

for (const artifact of artifacts) {
  mkdirSync(dirname(artifact.file), { recursive: true })
  writeFileSync(artifact.file, artifact.text, 'utf8')
}
const counts = [
  ...[...parsed.numbers.entries()].map(([group, list]) => `${group} ${list.length}`),
  ...[...parsed.roles.entries()].map(([enumName, list]) => `${EXPECTED_COLORS[enumName].group} ${list.size}`),
  ...[...parsed.literals.entries()].map(([enumName, list]) => `${EXPECTED_COLORS[enumName].group} ${list.length}`),
  `theme ${parsed.palettes.length}`,
].join(' / ')
process.stdout.write(`✅ 已生成 ${outRelative} + ${themesRelative}（${counts}）\n`)
