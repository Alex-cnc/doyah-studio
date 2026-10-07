// 连接弹层的**行为判据**（alpha S-7a）：连接面从主区内联搬进弹层后，这里守三件事：
//
//   ① **命令驱动**：弹层由既有命令清单里的命令打开 —— 三条绑定命令都在清单里、
//      都绑在数据库视图上、都过 `auditCommands()` 三者对账（**不另造一套命令栈**）；
//   ② **文案走语言表**：弹层标题只给 key，且两种语言都在（切英文不该留中文）；
//   ③ **端口按文本交上去**：`looseNumber` 复刻 Vue `v-model.number`，空串仍是空串
//      （不许把"没填"偷偷变成 `0`）。

import { describe, expect, it } from 'vitest'
import { auditCommands, commandById, COMMANDS_LIST } from './commands'
import {
  CONNECTION_DIALOG_COMMANDS,
  CONNECTION_DIALOG_TITLE_KEYS,
  connectionDialogModeForCommand,
  connectionDialogTitleKey,
  looseNumber,
  type ConnectionDialogMode,
} from './connectionDialog'
import { DICT } from '../i18n'

describe('连接弹层：由菜单命令驱动（走既有命令清单）', () => {
  it('三条绑定命令都在清单里，且 id → 档位是穷举的', () => {
    const modes = new Map<string, ConnectionDialogMode>([
      ['database.connect', 'current'],
      ['database.newConnection', 'new'],
      ['database.editConnection', 'edit'],
    ])
    expect(CONNECTION_DIALOG_COMMANDS.length).toBe(modes.size)
    for (const [id, mode] of modes) {
      expect(CONNECTION_DIALOG_COMMANDS).toContain(id)
      // 命令清单里真的有它（分派器不会取空）
      expect(commandById(id)).toBeDefined()
      expect(connectionDialogModeForCommand(id)).toBe(mode)
    }
  })

  it('不是这三条命令 ⇒ null（调用方走原路，不猜）', () => {
    expect(connectionDialogModeForCommand('workspace.newFile')).toBeNull()
    expect(connectionDialogModeForCommand('database.runQuery')).toBeNull()
    expect(connectionDialogModeForCommand('')).toBeNull()
  })

  it('绑定命令都过三者对账，且都绑在数据库视图上', () => {
    expect(auditCommands()).toEqual([])
    for (const id of CONNECTION_DIALOG_COMMANDS) {
      const command = commandById(id)
      expect(command?.scope.kind).toBe('view')
      if (command?.scope.kind === 'view') expect(command.scope.view).toBe('database')
    }
  })

  it('清单里「新建连接 / 编辑连接」两条与弹层的绑定**同源**（清单改了这里就会红）', () => {
    const ids = COMMANDS_LIST.map((c) => c.id)
    expect(ids).toContain('database.newConnection')
    expect(ids).toContain('database.editConnection')
  })
})

describe('连接弹层：文案只在语言表里', () => {
  it('三个档位的标题 key 各不相同、且两种语言都在表里', () => {
    const modes: ConnectionDialogMode[] = ['new', 'edit', 'current']
    const keys = modes.map((mode) => connectionDialogTitleKey(mode))
    expect(new Set(keys).size).toBe(modes.length)
    for (const mode of modes) {
      const key = CONNECTION_DIALOG_TITLE_KEYS[mode]
      expect(Object.keys(DICT)).toContain(key)
      const entry = DICT[key as keyof typeof DICT]
      expect(entry['zh-Hans'].length).toBeGreaterThan(0)
      expect(entry.en.length).toBeGreaterThan(0)
    }
    expect(Object.keys(DICT)).toContain('db.connectionDialog.close')
  })
})

describe('连接弹层：端口按文本交上去', () => {
  it('复刻 v-model.number：空的仍是空串，数字出数，非数字回退原文', () => {
    expect(looseNumber('')).toBe('')
    expect(looseNumber('5432')).toBe(5432)
    expect(looseNumber('0')).toBe(0)
    expect(looseNumber('65536')).toBe(65536)
    // `parseFloat` 的口径：前缀是合法数字就取前缀（与 v-model.number 一致）
    expect(looseNumber('5432px')).toBe(5432)
    // 前缀不是数字 ⇒ 原样交上去，由领域层当场拒
    expect(looseNumber('abc')).toBe('abc')
    expect(looseNumber('-')).toBe('-')
  })
})
