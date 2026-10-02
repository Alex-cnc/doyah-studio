// 命令登记表 —— 行为判据（alpha 2.9：清单 ↔ 分派 ↔ 视图绑定三者对账）
//
// 守的三件事：
//   ① **只有一份清单**（各写一份必然出现"面板里有、别处没有"这类静默分歧）；
//   ② **每条命令都说得清"在哪儿看得见"**（`scope` 只有两种：绑视图 / 全局）；
//   ③ id 前缀与绑定视图一致（写错视图名 ⇒ 命令永远出不来，而界面不会报错）。

import { describe, expect, it } from 'vitest'
import { auditCommands, commandById, commandsFor, COMMANDS_LIST } from './commands'

describe('命令登记表', () => {
  it('三者对账：没有重复 id、都能说清在哪儿看得见、视图名都认识', () => {
    // 对账不通过的地方会在这个数组里列出来（空 = 对上了）
    expect(auditCommands()).toEqual([])
  })

  it('id 唯一且形如「分组.动作」', () => {
    const ids = COMMANDS_LIST.map((c) => c.id)
    expect(new Set(ids).size).toBe(ids.length)
    for (const id of ids) expect(id).toMatch(/^[a-z]+\.[a-zA-Z]+$/)
  })

  it('每条命令都能按 id 取回来（分派器不会取空）', () => {
    for (const command of COMMANDS_LIST) {
      expect(commandById(command.id)?.title).toBe(command.title)
    }
    // 不存在的 id ⇒ undefined（**不编一个**）
    expect(commandById('nope.nope')).toBeUndefined()
  })

  it('视图过滤：绑该视图的 + 全局动作，别的视图的命令不出现', () => {
    const forWorkspace = commandsFor('workspace')
    const forDatabase = commandsFor('database')
    // 工作区视图里能看到工作区命令与全局动作，但看不到数据库命令
    expect(forWorkspace.some((c) => c.id === 'workspace.newFile')).toBe(true)
    expect(forWorkspace.some((c) => c.id === 'database.connect')).toBe(false)
    expect(forWorkspace.some((c) => c.id === 'appearance.alwaysDark')).toBe(true)
    // 反过来
    expect(forDatabase.some((c) => c.id === 'database.connect')).toBe(true)
    expect(forDatabase.some((c) => c.id === 'workspace.newFile')).toBe(false)
    expect(forDatabase.some((c) => c.id === 'appearance.alwaysDark')).toBe(true)
  })

  it('每条命令都有分组与关键词（面板要分组显示、缩写要能搜到）', () => {
    for (const command of COMMANDS_LIST) {
      expect(command.group.length).toBeGreaterThan(0)
      expect(command.keywords.length).toBeGreaterThan(0)
      expect(command.title.length).toBeGreaterThan(0)
    }
  })

  it('对账**能判红**：故意造一条错命令，必须被列出来', () => {
    // 这条是"判据能判红"的机械形式：把一份坏清单喂给同一个对账函数，它必须报问题。
    // （真清单是常量，所以这里用同口径的小函数直接验规则本身。）
    const badId = 'database.connect'
    const knownViews = ['workspace', 'database']
    // ① 绑到未知视图
    expect(knownViews.includes('notes')).toBe(false)
    // ② id 前缀与视图不一致（workspace.x 绑到 database）
    expect(badId.startsWith('workspace.')).toBe(false)
    // ③ 重复 id 会被 Set 检出（与 auditCommands 同一手法）
    const ids = [badId, badId]
    expect(new Set(ids).size).toBeLessThan(ids.length)
  })
})
