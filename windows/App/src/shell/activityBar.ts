// 活动栏（视图切换项）与窗口标题的**唯一出处** —— Windows 侧
//
// 契约来源（三书）：
//   · `Docs/概要设计.md` §3.31 / §8.5.4「一样」清单：**能力清单与行为语义两端一致**
//   · macOS 侧等价物 `Core/ActivityBar.swift`（`ActivityBarItem` / `WindowTitle`）
//     —— 本文件按它的**行为**重建，不引 Swift 类型，也不在视图里再排一次顺序。
//
// 四条口径（照抄对侧，改一条就等于两端分叉）：
//   1. **顺序 = 栏上的上下位置**，只由 ITEMS 的声明顺序决定 —— 视图里不许再排一次
//      （2026-09-25 老板：「活动栏排序调整一下：工作区在最上面」）。
//   2. **切换项与动作分开**：本文件只管**有选中态的切换项**；设置 / 账户那类无选中态的动作
//      不混进来（混了迟早出现「设置被选中、右侧面板变成设置页」这种结构性问题）。
//   3. **窗口标题由活动栏项派生**，不另存一份视图名 —— 将来 Retro 进栏那天标题自动跟上。
//   4. **未知持久化值一律回退默认项**，不报错：配置被手改或将来删掉某个视图时，界面都必须照常起来。

/** 活动栏项 id（与对侧 `ActivityBarItem.rawValue` 同名同序）。 */
export type ActivityBarItemId = 'workspace' | 'database' | 'notes' | 'retro'

/** 栏上顺序 = 声明顺序（**唯一出处**，视图不许再排）。 */
export const ITEMS: readonly ActivityBarItemId[] = ['workspace', 'database', 'notes', 'retro'] as const

/** 对侧只有三项（许可证决定可见性）；`retro` 是对侧「进活动栏即自动延用同一机制」预留的那一项。 */
export const MAC_ITEMS: readonly ActivityBarItemId[] = ['workspace', 'database', 'notes'] as const

/**
 * 本侧**已开工**的视图（其余如实标「未开工」，不半建）。
 * `retro` 未开工 —— 与 `windows/版本计划.md` 的 alpha 4.0 一致。
 */
export const BUILT_ITEMS: readonly ActivityBarItemId[] = ['workspace', 'database', 'notes'] as const

/** 持久化键：与工程内其它 UI 偏好同一套 `ui.` 前缀（对侧 `ActivityBarItem.storageKey` 逐字相同）。 */
export const ACTIVITY_BAR_STORAGE_KEY = 'ui.activityBarItem'

/** 品牌名（产品名不翻译；中文界面出「Doyah Studio - 数据库」）。 */
export const BRAND = 'Doyah Studio'

/** 品牌段与视图段之间的分隔符：两处各写一遍「 - 」迟早会漂（对侧 `WindowTitle.separator`）。 */
export const TITLE_SEPARATOR = ' - '

export type UiLanguage = 'zh-Hans' | 'en'

interface ItemText {
  /** 悬停提示 / 无障碍标签 */
  readonly title: string
  /** 视图菜单项文案（对侧 `menuKey` 的等价物） */
  readonly menu: string
}

const TEXT: Record<ActivityBarItemId, Record<UiLanguage, ItemText>> = {
  workspace: {
    'zh-Hans': { title: '工作区', menu: '显示工作区' },
    en: { title: 'Workspace', menu: 'Show Workspace' },
  },
  database: {
    'zh-Hans': { title: '数据库', menu: '显示数据库' },
    en: { title: 'Database', menu: 'Show Database' },
  },
  notes: {
    'zh-Hans': { title: '笔记', menu: '显示笔记' },
    en: { title: 'Notes', menu: 'Show Notes' },
  },
  retro: {
    'zh-Hans': { title: '复盘', menu: '显示复盘' },
    en: { title: 'Retro', menu: 'Show Retro' },
  },
}

/**
 * 图标名 —— **本侧不是 SF Symbol**：这里登记的是**语义名**（`database` / `folder` / …），
 * 由视图层映射成自己的字形或内联 SVG。不把 SF Symbol 名硬抄过来，是因为那名字只在苹果平台有意义。
 */
const GLYPH: Record<ActivityBarItemId, string> = {
  workspace: 'folder',
  database: 'cylinder',
  notes: 'note',
  retro: 'chart',
}

export function isActivityBarItem(value: string): value is ActivityBarItemId {
  return (ITEMS as readonly string[]).includes(value)
}

export function itemTitle(item: ActivityBarItemId, language: UiLanguage = 'zh-Hans'): string {
  return TEXT[item][language].title
}

export function itemMenuLabel(item: ActivityBarItemId, language: UiLanguage = 'zh-Hans'): string {
  return TEXT[item][language].menu
}

export function itemGlyph(item: ActivityBarItemId): string {
  return GLYPH[item]
}

/**
 * 由持久化的 id 解析；**未知值一律回退到数据库视图**（与对侧逐字同口径）。
 * @param id 持久化里读到的值（可能是任意字符串 / null）
 * @param visible 当前栏上可见的项（许可证决定）；缺省 = 本侧已开工的三项 + 未开工的 retro
 */
export function resolveActivityBarItem(
  id: string | null | undefined,
  visible: readonly ActivityBarItemId[] = ITEMS,
): ActivityBarItemId {
  const fallback = visible.includes('database') ? 'database' : visible[0]
  if (id === null || id === undefined || id === '') return fallback
  if (!isActivityBarItem(id)) return fallback
  // 持久化里存了一个**当前不可见**的项（许可证降级 / 视图被关掉）⇒ 同样回退，不返回一个栏上不存在的视图
  return visible.includes(id) ? id : fallback
}

/**
 * 菜单快捷键序号 ⌘1 / ⌘2 / ⌘3 ……（与 VS Code「按序号切视图」同一习惯）。
 *
 * 序号**跟着栏上顺序**走（栏上第一项就是 ⌘1），所以必须由「当前栏上可见的那几项」算 ——
 * 写死在项上会让「按序号切视图」这条习惯失灵。不可见 = 没有序号（返回 null）。
 */
export function shortcutIndex(
  item: ActivityBarItemId,
  visible: readonly ActivityBarItemId[] = ITEMS,
): number | null {
  const position = visible.indexOf(item)
  return position < 0 ? null : position + 1
}

/** `Doyah Studio - 数据库`：品牌段不翻译，视图段走语言表（对侧 `WindowTitle.text`）。 */
export function windowTitle(item: ActivityBarItemId, language: UiLanguage = 'zh-Hans'): string {
  return BRAND + TITLE_SEPARATOR + itemTitle(item, language)
}

/** 栏上可显示的项（本侧口径：`visible` 由调用方给，缺省 = 全部声明项）。 */
export function visibleItems(): readonly ActivityBarItemId[] {
  return ITEMS
}
