// 服务器节点右键三动作（FR-META-11 第一期）—— 正例 + **禁用态** + 负例
//
// 验收点写得很具体：三动作**各一例**，且要有**无连接时的禁用态**一例。
// 所以这里按"已连接 / 未连接 / 有动作在路上"三种态各判一遍，并守住两条容易烂的规矩：
//   ① 不可用时**不隐藏**（三动作永远都在）；
//   ② 禁用时**必须给原因**（不做"灰着但不说为什么"）。
import { describe, it, expect } from 'vitest'

import { DICT } from '../i18n'
import { SERVER_MENU_ORDER, serverMenuAction, serverMenuActions } from './serverMenu'

function byId(actions: ReturnType<typeof serverMenuActions>, id: string) {
  return actions.find((action) => action.id === id)!
}

describe('服务器节点右键菜单（FR-META-11 第一期）', () => {
  it('三个动作齐全且顺序固定：连接 → 断开 → 编辑连接', () => {
    const actions = serverMenuActions({ connected: false })
    expect(actions.map((a) => a.id)).toEqual([...SERVER_MENU_ORDER])
    expect(actions.map((a) => a.labelKey)).toEqual([
      'db.server.menu.connect',
      'db.server.menu.disconnect',
      'db.server.menu.editConnection',
    ])
  })

  it('已连接：连接不可用（已连着）、断开可用、编辑连接可用', () => {
    const actions = serverMenuActions({ connected: true })
    expect(byId(actions, 'connect').enabled).toBe(false)
    expect(byId(actions, 'connect').reasonKey).toBe('db.server.reason.alreadyConnected')
    expect(byId(actions, 'disconnect').enabled).toBe(true)
    expect(byId(actions, 'disconnect').reasonKey).toBeNull()
    expect(byId(actions, 'editConnection').enabled).toBe(true)
  })

  it('未连接：*禁用态* —— 断开不可用且给出原因；连接可用；编辑连接照常可用', () => {
    const actions = serverMenuActions({ connected: false })
    const disconnect = byId(actions, 'disconnect')
    expect(disconnect.enabled).toBe(false)
    expect(disconnect.reasonKey).toBe('db.server.reason.notConnected')
    expect(byId(actions, 'connect').enabled).toBe(true)
    expect(byId(actions, 'connect').reasonKey).toBeNull()
    // 编辑连接改的是表单，不需要活连接
    expect(byId(actions, 'editConnection').enabled).toBe(true)
  })

  it('有动作在路上（连接中 / 断开中）：三个全禁用，且都给原因（防连点）', () => {
    const actions = serverMenuActions({ connected: true, busy: true })
    expect(actions.every((a) => !a.enabled)).toBe(true)
    expect(actions.every((a) => a.reasonKey === 'db.server.reason.busy')).toBe(true)
  })

  it('不可用时**不隐藏**：禁用态下三个动作一个都不少', () => {
    for (const state of [{ connected: false }, { connected: true }, { connected: true, busy: true }]) {
      expect(serverMenuActions(state)).toHaveLength(3)
    }
  })

  it('负例：禁用却不给原因（"灰着但不说为什么"）当场判红', () => {
    const actions = serverMenuActions({ connected: false })
    for (const action of actions) {
      if (!action.enabled) expect(action.reasonKey).not.toBeNull()
      else expect(action.reasonKey).toBeNull()
    }
    // 朴素写法：只置灰、不给原因 —— 上面那条断言抓的就是它
    const naive = [{ id: 'disconnect', enabled: false, reasonKey: null }]
    expect(naive[0].reasonKey).toBeNull()
  })

  it('负例：把不可用的动作从菜单里摘掉（隐藏而不是置灰）就凑不出三个动作', () => {
    const visibleOnly = serverMenuActions({ connected: false }).filter((a) => a.enabled)
    expect(visibleOnly.map((a) => a.id)).toEqual(['connect', 'editConnection'])
    expect(visibleOnly).not.toHaveLength(3)
  })

  it('文案键都在语言表里、且 zh / en 成对（漏译棘轮判红 0）', () => {
    // 三种态各取一遍，把出现过的标签键与原因键都收齐
    const keys = new Set<string>()
    for (const state of [
      { connected: false },
      { connected: true },
      { connected: true, busy: true },
    ]) {
      for (const action of serverMenuActions(state)) {
        keys.add(action.labelKey)
        if (action.reasonKey) keys.add(action.reasonKey)
      }
    }
    // 三动作 + "已连着 / 没连着 / 有动作在跑" 三类原因，一个都不许漏
    expect([...keys].sort()).toEqual(
      [
        'db.server.menu.connect',
        'db.server.menu.disconnect',
        'db.server.menu.editConnection',
        'db.server.reason.alreadyConnected',
        'db.server.reason.busy',
        'db.server.reason.notConnected',
      ].sort(),
    )
    for (const key of keys) {
      const entry = DICT[key as keyof typeof DICT]
      expect(entry, `语言表缺 ${key}`).toBeTruthy()
      expect(entry['zh-Hans'].length, `${key} 缺中文`).toBeGreaterThan(0)
      expect(entry.en.length, `${key} 缺英文`).toBeGreaterThan(0)
    }
  })

  it('按 id 取动作：找不到给 null，不抛错', () => {
    expect(serverMenuAction({ connected: true }, 'connect')?.enabled).toBe(false)
    // @ts-expect-error 故意传一个不存在的 id
    expect(serverMenuAction({ connected: true }, 'createDatabase')).toBeNull()
  })
})
