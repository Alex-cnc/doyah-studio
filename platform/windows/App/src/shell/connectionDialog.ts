// 连接弹层（对齐 macOS `App/Views/ConnectionSettingsSheet.swift` 的**呈现形态**）：
// 连接表单与连接列表**只在弹层里**，数据库视图主区不再内联铺开。
//
// 本模块是弹层的**规则唯一出处**（把"能单测的那部分"从组件里抽出来，与
// `serverMenu.ts` / `connectionDisplay.ts` / `objectTree.ts` 同一姿势）：
//
// ① 命令 ↔ 弹层：弹层由**既有的命令清单**驱动（`shell/commands.ts` 那份"清单 ↔ 分派器 ↔
//    视图绑定"三者对账的清单），命令 id 决定弹层以哪一档打开 —— **不另造一套命令栈**；
// ② 标题文案一律走语言表：本模块只给**键**，不给中文字面量
//    （漏译棘轮扫的就是"界面里写死的中文"）；
// ③ 端口按**文本**交上去：`looseNumber` 复刻 Vue `v-model.number` 的口径
//    （`parseFloat` 不成 ⇒ 回退原文，空串仍是空串）—— 领域层的校验收的是文本，
//    界面不得先把 `''` 变成 `0` 再交上去（那是"两套规则漂移"的来路）。

import type { DictKey } from '../i18n'

/**
 * 弹层的三种打开档位。
 *
 * - `new`     —— 起一张**新表单**（新 id、字段回默认）：这是「新建连接」的定义；
 * - `edit`    —— 打开**当前这张表单**（不动字段），并把连接名聚焦：「编辑连接…」；
 * - `current` —— 打开当前这张表单、不做别的：「连接数据库」（拿手上的表单去连）。
 */
export type ConnectionDialogMode = 'new' | 'edit' | 'current'

/** 弹层标题（与命令标题**分开**：命令是"要做什么"，标题是"这个弹层是什么"）。 */
export const CONNECTION_DIALOG_TITLE_KEYS: Readonly<Record<ConnectionDialogMode, DictKey>> = {
  new: 'db.connectionDialog.title.new',
  edit: 'db.connectionDialog.title.edit',
  current: 'db.connectionDialog.title.current',
}

/** 与弹层绑定的命令 id（**顺序 = 命令清单里的相对顺序**）。这三条都开弹层，不开别的通路。 */
export const CONNECTION_DIALOG_COMMANDS: readonly string[] = [
  'database.connect',
  'database.newConnection',
  'database.editConnection',
]

const MODE_BY_COMMAND: Readonly<Record<string, ConnectionDialogMode>> = {
  'database.connect': 'current',
  'database.newConnection': 'new',
  'database.editConnection': 'edit',
}

/** 档位 ⇒ 标题 key（找不到就抛 —— 这是**编译期**的穷举，不是运行时的回退）。 */
export function connectionDialogTitleKey(mode: ConnectionDialogMode): DictKey {
  return CONNECTION_DIALOG_TITLE_KEYS[mode]
}

/** 命令 id ⇒ 弹层档位；不是这三条 ⇒ `null`（调用方按 `null` 走原路，**不猜**）。 */
export function connectionDialogModeForCommand(commandId: string): ConnectionDialogMode | null {
  return MODE_BY_COMMAND[commandId] ?? null
}

/**
 * 复刻 Vue `v-model.number` 的转换：`parseFloat` 出的数不成 ⇒ **回退原文**。
 *
 * 为什么不在弹层里写 `Number(...)`：`Number('') === 0`，端口空着会被界面偷偷变成 `0`
 * （一个"看着像填了、其实是 0"的假象）；原口径把空串原样交上去、由领域层当场拒。
 */
export function looseNumber(text: string): number | string {
  const parsed = Number.parseFloat(text)
  return Number.isNaN(parsed) ? text : parsed
}
