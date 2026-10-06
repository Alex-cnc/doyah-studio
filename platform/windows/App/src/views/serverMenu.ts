// 服务器节点右键菜单（FR-META-11 第一期）—— **三个动作与"现在能不能用"的唯一出处**
//
// 需求：右键「服务器」节点提供 ① 连接 ② 断开 ③ 编辑连接…
// （第一期只做服务器节点；建库那一项要权限探测，本片不做，故这里只有三动作。）
//
// 三条口径（这就是把这个规则从组件里抽出来的原因 —— 散在模板里就没法逐条判）：
// ① **三动作永远都在**：不可用时**不隐藏**，而是置灰并**说明为什么** ——
//    菜单里少一项，用户会以为"这个功能不存在"，而不是"现在不能用"；
// ② **可用性由连接态唯一决定**：
//      · 已连接 ⇒ 连接不可用（已经是连着的），断开可用；
//      · 未连接 ⇒ 断开不可用（没有可断的），连接可用；
//      · 编辑连接**始终可用** —— 它改的是表单，不需要一条活连接；
// ③ **有动作在跑（连接中 / 断开中）⇒ 三个全禁用**：防连点，也避免"断开"和"连接"同时在路上。
//
// 文案一律走语言表（`zh` / `en` 成对），本模块只给出**键**，不给出中文字面量
// （漏译棘轮扫的就是"界面里写死的中文"）。

import type { DictKey } from '../i18n'

/** 服务器节点右键菜单的三个动作（**顺序固定** = 需求里 ①②③ 的顺序）。 */
export type ServerMenuActionId = 'connect' | 'disconnect' | 'editConnection'

/** 固定的动作顺序。 */
export const SERVER_MENU_ORDER: readonly ServerMenuActionId[] = [
  'connect',
  'disconnect',
  'editConnection',
]

/** 一个动作：文案键 + 现在能不能用 + 不能用时的原因键。 */
export interface ServerMenuAction {
  readonly id: ServerMenuActionId
  /** 菜单项文案（走语言表） */
  readonly labelKey: DictKey
  /** 现在能不能点 */
  readonly enabled: boolean
  /** 不能点的原因（**可用时为 `null`**；不可用时必给 —— 不做"灰着但不说为什么"） */
  readonly reasonKey: DictKey | null
}

/** 决定三动作可用性的输入面。 */
export interface ServerMenuState {
  /** 当前是不是已经连着（界面用 `info` 是否为空） */
  readonly connected: boolean
  /** 有没有动作在路上（连接中 / 断开中）；缺省 = 没有 */
  readonly busy?: boolean
}

const LABELS: Record<ServerMenuActionId, DictKey> = {
  connect: 'db.server.menu.connect',
  disconnect: 'db.server.menu.disconnect',
  editConnection: 'db.server.menu.editConnection',
}

/**
 * 按连接态算出服务器节点菜单的三个动作。
 *
 * 返回顺序**总是** [`SERVER_MENU_ORDER`]（判据按这个顺序对账），三个动作一个都不少。
 */
export function serverMenuActions(state: ServerMenuState): ServerMenuAction[] {
  const busy = state.busy === true
  return SERVER_MENU_ORDER.map((id) => {
    let enabled: boolean
    let reasonKey: DictKey | null = null
    if (busy) {
      enabled = false
      reasonKey = 'db.server.reason.busy'
    } else if (id === 'connect') {
      enabled = !state.connected
      reasonKey = enabled ? null : 'db.server.reason.alreadyConnected'
    } else if (id === 'disconnect') {
      enabled = state.connected
      reasonKey = enabled ? null : 'db.server.reason.notConnected'
    } else {
      // 编辑连接：改的是表单，不需要活连接 —— 只有"有动作在跑"时禁用（上面那条已拦）
      enabled = true
    }
    return { id, labelKey: LABELS[id], enabled, reasonKey }
  })
}

/** 按 id 取一个动作（调用方按 id 分派时用；找不到给 `null`，不抛错）。 */
export function serverMenuAction(
  state: ServerMenuState,
  id: ServerMenuActionId,
): ServerMenuAction | null {
  return serverMenuActions(state).find((action) => action.id === id) ?? null
}
