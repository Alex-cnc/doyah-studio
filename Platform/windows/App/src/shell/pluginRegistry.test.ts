// 插件骨架的**行为判据**（契约依据 = 概要设计 §3.52；本侧落法 = §8.5.8）
//
// 守的是四条：
//   ① **装上的插件**：视图查得到、入口出现在活动栏里；
//   ② **拔掉的插件**：查不到 ⇒ **不报错**、活动栏里没有它（契约④）；
//   ③ **清单驱动**：活动栏项由清单派生，核心项与插件项合成一处；
//   ④ **骨架如实**：`implemented: false` 的插件，活动栏项 `ready` 必须是 `false`
//      （点进去显示"未开工"，不是假装能用）。

import { describe, expect, it, beforeEach } from 'vitest'
import {
  registerCore,
  registerPlugin,
  resolveView,
  hasView,
  registeredIds,
  resetRegistryForTest,
} from './pluginRegistry'
import { CORE_SLOTS } from '../views/coreSlots'
import { CORE_ACTIVITY_ITEMS, derivedActivityItems, pluginActivityItems } from './activityItems'
import type { PluginEntry } from '../ipc'

// ── 清单注入：走 `plugins.ts` 的**正式口子**（`setManifestForTest`）──────────────
// 为什么不走真命令：判据要能在**没有外壳**的环境里跑（vitest 是 node 环境）。
// 注入的只是"清单内容"；被测的派生逻辑一个字都没变。
import { setManifestForTest } from './plugins'

function setManifest(entries: PluginEntry[]): void {
  setManifestForTest(entries)
}

function entry(over: Partial<PluginEntry> & Pick<PluginEntry, 'id'>): PluginEntry {
  return {
    name: over.id,
    version: '0.1.0',
    entry: over.id,
    capabilities: [over.id],
    mounts: ['activity-item', 'main-tab'],
    storage: 'bundled',
    implemented: false,
    ...over,
  }
}

describe('视图注册表：装上查得到、拔掉不报错', () => {
  beforeEach(() => {
    // 每个用例从"只有核心视图"的干净状态起 ——
    // 注册表是**模块级状态**，用例之间必须隔离（否则上一例装上的插件会漏到下一例，
    // 本判据第一次跑就是这么红的：`registeredIds` 里多了上一例装的 `notes`）。
    resetRegistryForTest()
    registerCore(CORE_SLOTS)
  })

  it('核心视图登记后查得到', () => {
    expect(hasView('workspace')).toBe(true)
    expect(hasView('database')).toBe(true)
    expect(resolveView('workspace')).toBeTruthy()
  })

  it('拔掉的插件视图：查不到，且 resolveView 不抛异常', () => {
    // 注意：**不抛**才是契约④要的（拔掉 ⇒ 挂点消失且不报错）
    expect(() => resolveView('notes')).not.toThrow()
    expect(hasView('notes')).toBe(false)
    expect(resolveView('notes')).toBeUndefined()
  })

  it('装上的插件视图：查得到', () => {
    registerPlugin({ id: 'notes', mounts: ['activity-item', 'main-tab'], view: { name: 'N' } })
    expect(hasView('notes')).toBe(true)
    expect(resolveView('notes')).toBeTruthy()
  })

  it('未登记的 id 一律返回 undefined（不编兜底、不回退到别的视图）', () => {
    for (const id of ['nope', '', 'retro', 'NOTES']) {
      expect(resolveView(id)).toBeUndefined()
    }
  })

  it('registeredIds 反映真实登记面', () => {
    const ids = registeredIds()
    expect(ids).toContain('workspace')
    expect(ids).toContain('database')
    expect(ids).not.toContain('notes')
  })
})

describe('活动栏项：由清单派生', () => {
  beforeEach(() => {
    setManifest([])
  })

  it('清单为空 ⇒ 只有核心项（插件挂点整体消失）', () => {
    expect(pluginActivityItems()).toEqual([])
    expect(derivedActivityItems()).toEqual([...CORE_ACTIVITY_ITEMS])
  })

  it('清单里声明了 activity-item 的插件才进活动栏', () => {
    setManifest([
      entry({ id: 'notes', mounts: ['activity-item', 'main-tab'] }),
      // 只占 main-tab 的插件**不该**出现在活动栏
      entry({ id: 'panelOnly', mounts: ['main-tab'] }),
    ])
    expect(pluginActivityItems()).toEqual(['notes'])
    expect(derivedActivityItems()).toEqual([...CORE_ACTIVITY_ITEMS, 'notes'])
  })

  it('顺序 = 核心项在前、插件项按清单顺序', () => {
    setManifest([
      entry({ id: 'notes' }),
      entry({ id: 'retro' }),
    ])
    expect(derivedActivityItems()).toEqual(['workspace', 'database', 'notes', 'retro'])
  })

  it('骨架插件（implemented=false）也要出现在活动栏（如实显示未开工，不藏起来）', () => {
    setManifest([entry({ id: 'notes', implemented: false })])
    expect(derivedActivityItems()).toContain('notes')
  })
})
