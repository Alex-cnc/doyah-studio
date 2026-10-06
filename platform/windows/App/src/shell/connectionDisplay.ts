// 连接呈现面 · **共用唯一出处**（FR-CONN-14 / FR-CONN-15 / FR-CONN-16 · Windows 侧）
//
// 为什么要有这个文件、而不是各处各拼一次：
//   · FR-CONN-14 的显示名 =「名称 (登录用户名)」要出现在**侧边栏连接行**与**查询上下文栏**；
//   · FR-CONN-16 的环境标签与颜色也要**两处一致**（侧栏标了生产、上下文栏没标 ⇒ 正好会让人连错库）。
//   同一个东西在两个地方各拼一次，迟早会出现「一处有一处没有」——
//   所以「显示什么、用什么颜色」在这一个文件里算，视图只负责把它画出来。
//
// 两条安全口径（照抄 macOS 侧 Core/ConnectionAppearance.swift 的结论，不另立一套）：
//   ① **颜色优先级：环境标签 > 自选色**（安全信息不能被自定义色盖掉）；
//   ② 自选色**按名字存、不存色值**（色值会随主题演化；存了它就要为「颜色改了、旧配置怎么办」再写一次迁移）。
//
// 本文件**一个色值都没有**：色条 / 徽标只引用生成物里的 `--ds-*` 令牌变量名，
// 由 `platform/windows/App/tools/token-ratchet.mjs` 的裸值棘轮守着（判红 0）。

import type { DictKey } from '../i18n'
import type { SavedConnection } from '../ipc'

// ── 环境标签（FR-CONN-16）────────────────────────────────────────────────────────

/** 与 macOS 侧 `ConnectionEnvironment` 的 rawValue 逐字一致（配置里存的就是这几个词）。 */
export type ConnectionEnvironment = 'production' | 'staging' | 'testing' | 'development'

/** 语义色角色（Core 只给角色；具体颜色由平台层令牌给）。 */
export type StatusTone = 'danger' | 'warning' | 'success'

/** 徽标色角色（未知标签兜底用中性色 —— 不冒充任何安全色）。 */
export type ToneRole = StatusTone | 'neutral'

/** 下拉与徽标的顺序：**生产在最前**，不会藏在最后。 */
export const ENVIRONMENT_ORDER: readonly ConnectionEnvironment[] = [
  'production',
  'staging',
  'testing',
  'development',
]

/** 环境 → 语言表键（键写死，不做模板串拼名字：拼错不会报错，只会显示 `⟪…⟫`）。 */
export const ENVIRONMENT_LABEL_KEY: Record<ConnectionEnvironment, DictKey> = {
  production: 'db.env.production',
  staging: 'db.env.staging',
  testing: 'db.env.testing',
  development: 'db.env.development',
}

export function isEnvironment(value: string | null | undefined): value is ConnectionEnvironment {
  return (
    value === 'production' || value === 'staging' || value === 'testing' || value === 'development'
  )
}

/**
 * 环境 → 语义色角色。
 *
 * 生产用**危险色**不是「好看」：整屏里唯一一个红点，扫一眼就知道自己在哪台库上。
 * 预发用警告色（同属「别乱来」的那一档）；测试 / 开发在语义上是安全档。
 */
export function environmentTone(env: ConnectionEnvironment): StatusTone {
  switch (env) {
    case 'production':
      return 'danger'
    case 'staging':
      return 'warning'
    case 'testing':
      return 'success'
    case 'development':
      return 'success'
  }
}

/** 是否建议只读（生产 / 预发）—— 与 macOS 侧 `recommendsReadOnly` 同口径。 */
export function recommendsReadOnly(env: ConnectionEnvironment | null | undefined): boolean {
  return env === 'production' || env === 'staging'
}

/** 环境徽标的显示计划（`known = false` = 认不出的标签，走兜底）。 */
export interface EnvironmentBadge {
  /** 认得出的标签：语言表键。 */
  labelKey: DictKey | null
  /** 认不出的标签：**原样显示配置里的词**（不许静默当没标 —— 那正是「连错库」的来路）。 */
  labelRaw: string | null
  tone: ToneRole
  known: boolean
}

/**
 * 环境标签 → 徽标计划（`null` = 这条连接没标环境，不画徽标）。
 *
 * 兜底口径：`environment` 非空但认不出 ⇒ **原样显示 + 中性色**，不是「当作没标」。
 * 认不出就静默吞掉，等于把一条安全声明藏起来 —— 与「别连错库」这条需求的目的是相反的。
 */
export function environmentBadge(environment: string | null | undefined): EnvironmentBadge | null {
  if (environment == null) return null
  const value = environment.trim()
  if (value === '') return null
  if (isEnvironment(value)) {
    return { labelKey: ENVIRONMENT_LABEL_KEY[value], labelRaw: null, tone: environmentTone(value), known: true }
  }
  return { labelKey: null, labelRaw: value, tone: 'neutral', known: false }
}

// ── 自选色（FR-CONN-16）─────────────────────────────────────────────────────────

/** 按**名字**存的自选色（与 macOS 侧 `CategoricalTone` 同名字集）。 */
export const CATEGORICAL_TONES = ['amber', 'blue', 'magenta', 'teal'] as const
export type CategoricalTone = (typeof CATEGORICAL_TONES)[number]

export function isCategoricalTone(value: string | null | undefined): value is CategoricalTone {
  return value != null && (CATEGORICAL_TONES as readonly string[]).includes(value)
}

/** 自选色名的语言表键（给悬停 / 读屏用；色条本身不写字）。 */
export const CATEGORICAL_LABEL_KEY: Record<CategoricalTone, DictKey> = {
  amber: 'db.color.amber',
  blue: 'db.color.blue',
  magenta: 'db.color.magenta',
  teal: 'db.color.teal',
}

// ── 「该显示什么、用什么颜色」的**唯一函数**（侧边栏与查询上下文栏共用）──────────────

/** 呈现面需要的那几个字段（`SavedConnection` 满足它；测试里可以直接给字面量）。 */
export interface ConnectionAppearanceSource {
  name: string
  username: string
  environment?: string | null
  colorTag?: string | null
}

export interface ConnectionPresentation {
  /** 显示名 =「名称 (登录用户名)」（FR-CONN-14）。 */
  title: string
  /** 环境徽标（null = 不显示）。 */
  badge: EnvironmentBadge | null
  /**
   * 该用哪个色（null = 不画色条）。**这里是「用什么颜色」的唯一决定**：
   * 环境标签 > 自选色，自选色不承担安全含义。
   * 只给**语义角色名**，不给色值 —— 角色 → `--ds-*` 令牌的映射落在共用组件的样式里
   * （`platform/windows/App/tools/token-ratchet.mjs` 守着那一步，色值一个都不许出现）。
   */
  accent: ConnectionAccent | null
  /** 建议只读（生产 / 预发）—— 表单 / 连接提示可以据此提示。 */
  recommendsReadOnly: boolean
}

/** 色条的语义角色（决定用哪一档令牌，不决定具体色值）。 */
export type ConnectionAccent =
  | { kind: 'environment'; tone: StatusTone }
  | { kind: 'categorical'; tone: CategoricalTone }

/**
 * **唯一函数**：一条连接在界面上「显示什么、用什么颜色」。
 *
 * 侧边栏连接行与查询上下文栏都必须调它（不许任何一处自己拼显示名或自己挑颜色）——
 * 判据 `src/shell/connectionDisplay.test.ts` 会扫源码：两处各拼一次字符串即判红。
 *
 * @param connection 连接（`SavedConnection` 满足）
 * @param untitled 名称为空时的占位文案（本地化文案由调用方给；本文件不硬编码语言）
 */
export function connectionPresentation(
  connection: ConnectionAppearanceSource,
  untitled: string,
  displayTitle?: string,
): ConnectionPresentation {
  const badge = environmentBadge(connection.environment)
  let accent: ConnectionAccent | null = null
  if (badge?.known && isEnvironment(connection.environment)) {
    // 环境标签优先：安全信息不能被自定义色盖掉。
    accent = { kind: 'environment', tone: environmentTone(connection.environment) }
  } else if (!badge && isCategoricalTone(connection.colorTag)) {
    // 只有「没标环境」时才轮到自选色（认不出的标签走中性色，不冒充任何安全色）。
    accent = { kind: 'categorical', tone: connection.colorTag }
  }
  return {
    title: displayTitle ?? connectionDisplayTitle(connection.name, connection.username, untitled),
    badge,
    accent,
    recommendsReadOnly: recommendsReadOnly(isEnvironment(connection.environment) ? connection.environment : null),
  }
}

// ── 显示名（FR-CONN-14）────────────────────────────────────────────────────────

/**
 * **唯一函数**：连接在界面上的显示名 =「名称 (登录用户名)」。
 *
 * 三条口径（与 macOS 侧 `ConnectionConfig.displayTitle(untitled:)` 逐字一致）：
 *   ① 名称为空 ⇒ 用占位文案（`untitled`）；
 *   ② 用户名为空 ⇒ **只显示名称，不产生空括号**（`名称 ()` 比不括还难看）；
 *   ③ 名称与用户名先各去首尾空白再判空。
 */
export function connectionDisplayTitle(name: string, username: string, untitled: string): string {
  const trimmedName = name.trim()
  const title = trimmedName === '' ? untitled : trimmedName
  const trimmedUser = username.trim()
  if (trimmedUser === '') return title
  return `${title} (${trimmedUser})`
}

/** 从保存的连接取显示名（侧边栏连接行 / 查询上下文栏都只用它）。 */
export function savedConnectionTitle(connection: SavedConnection, untitled: string): string {
  return connectionDisplayTitle(connection.name, connection.username, untitled)
}

// ── 分组（FR-CONN-15）────────────────────────────────────────────────────────

/** 一个分组段（`group = null` = 未分组那一段）。 */
export interface ConnectionSection {
  /** 分组名（未分组为 `null`；标题文案由视图给，本文件不硬编码语言）。 */
  group: string | null
  items: SavedConnection[]
}

/**
 * 连接列表分组：**没分组的归到一段、永远排最后**，其余按名字排（顺序稳定，用户才记得住位置）。
 * 组内保持传入顺序（Rust 侧定的顺序，前端不重排）。
 */
export function groupConnections(
  connections: readonly SavedConnection[],
): ConnectionSection[] {
  const byGroup = new Map<string | null, SavedConnection[]>()
  for (const connection of connections) {
    const key = (connection.group ?? '').trim() || null
    const list = byGroup.get(key) ?? []
    list.push(connection)
    byGroup.set(key, list)
  }
  return [...byGroup.entries()]
    .map(([group, items]) => ({ group, items }))
    .sort((a, b) => {
      if (a.group === null) return 1
      if (b.group === null) return -1
      return a.group.localeCompare(b.group)
    })
}

// ── 折叠状态持久化（FR-CONN-15）──────────────────────────────────────────────

/** 折叠状态落点：WebView2 按应用持久化；折叠态是界面偏好，不塞进连接配置文件。 */
export const COLLAPSED_GROUPS_KEY = 'doyah.connection.collapsedGroups'

/** localStorage 的最小面（取成接口，测试里可以给内存替身，不必真有 window）。 */
export interface KeyValueStore {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
}

/**
 * 冷启动读回折叠的分组名集合。
 *
 * 三条口径：**存不下 / 读不出 / 坏值都当作「没折叠」**（全展开是安全默认 ——
 * 不能因为一段坏 JSON 就把用户的连接藏起来），且**只认字符串数组里的非空项**。
 */
export function readCollapsedGroups(store: KeyValueStore | null | undefined): Set<string> {
  if (!store) return new Set()
  let raw: string | null = null
  try {
    raw = store.getItem(COLLAPSED_GROUPS_KEY)
  } catch {
    return new Set()
  }
  if (!raw) return new Set()
  let parsed: unknown
  try {
    parsed = JSON.parse(raw)
  } catch {
    return new Set()
  }
  if (!Array.isArray(parsed)) return new Set()
  const names = parsed.filter((value): value is string => typeof value === 'string' && value.trim() !== '')
  return new Set(names)
}

/** 记住折叠的分组名（排序后写：同一份状态落在盘上是同一个串，便于比对）。 */
export function writeCollapsedGroups(
  store: KeyValueStore | null | undefined,
  collapsed: Iterable<string>,
): void {
  if (!store) return
  try {
    store.setItem(COLLAPSED_GROUPS_KEY, JSON.stringify([...collapsed].sort()))
  } catch {
    // 存不下不该挡住「折叠」这件事本身
  }
}

/** 折叠 / 展开一段（返回新集合；不改传入的那个）。 */
export function toggleCollapsedGroup(collapsed: ReadonlySet<string>, group: string): Set<string> {
  const next = new Set(collapsed)
  if (next.has(group)) next.delete(group)
  else next.add(group)
  return next
}
