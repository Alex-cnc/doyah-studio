// 活动栏选中态的单点 —— 行为判据
//
// 守的是「存储坏了界面也要起得来」这条：假存储 + **故意抛错的存储**两路都验，
// 而不是把「存储不可用会怎样」留到用户机器上才发现。

import { describe, expect, it } from 'vitest'
import { ACTIVITY_BAR_STORAGE_KEY, ITEMS, type ActivityBarItemId } from './activityBar'
import { loadItemFrom, saveItemTo, type KeyValueStore } from './activityBarStore'

/** 内存假存储（够真：读写删三件都在）。 */
function fakeStore(initial: Record<string, string> = {}): KeyValueStore & { data: Map<string, string> } {
  const data = new Map<string, string>(Object.entries(initial))
  return {
    data,
    getItem: (k) => data.get(k) ?? null,
    setItem: (k, v) => void data.set(k, v),
    removeItem: (k) => void data.delete(k),
  }
}

/** 一台「什么都抛」的存储（隐私模式 / 权限策略下的真实形状）。 */
const hostileStore: KeyValueStore = {
  getItem() {
    throw new Error('SecurityError: storage disabled')
  },
  setItem() {
    throw new Error('SecurityError: storage disabled')
  },
  removeItem() {
    throw new Error('SecurityError: storage disabled')
  },
}

describe('活动栏选中态：读取', () => {
  it('没有存储（浏览器外 / 测试环境）⇒ 回退到数据库，不抛', () => {
    expect(loadItemFrom(null)).toBe('database')
    expect(loadItemFrom(undefined)).toBe('database')
  })

  it('存储里没有这一项 ⇒ 回退；存了认得的值 ⇒ 用它', () => {
    expect(loadItemFrom(fakeStore())).toBe('database')
    for (const item of ITEMS) {
      expect(loadItemFrom(fakeStore({ [ACTIVITY_BAR_STORAGE_KEY]: item }))).toBe(item)
    }
  })

  it('存储里是脏值（手改过 / 老版本残留）⇒ 回退，不报错', () => {
    expect(loadItemFrom(fakeStore({ [ACTIVITY_BAR_STORAGE_KEY]: 'settings' }))).toBe('database')
    expect(loadItemFrom(fakeStore({ [ACTIVITY_BAR_STORAGE_KEY]: '' }))).toBe('database')
  })

  it('存储读抛错 ⇒ 回退，不把异常抛给界面', () => {
    expect(() => loadItemFrom(hostileStore)).not.toThrow()
    expect(loadItemFrom(hostileStore)).toBe('database')
  })

  it('可见集里没有默认项时，回退到可见集第一项（不返回栏上不存在的视图）', () => {
    const visible: readonly ActivityBarItemId[] = ['notes']
    expect(loadItemFrom(null, visible)).toBe('notes')
    expect(loadItemFrom(fakeStore({ [ACTIVITY_BAR_STORAGE_KEY]: 'retro' }), visible)).toBe('notes')
  })
})

describe('活动栏选中态：落盘', () => {
  it('写进的是约定键，值就是 id（没有多余包装）', () => {
    const store = fakeStore()
    expect(saveItemTo(store, 'notes')).toBe(true)
    expect(store.data.get(ACTIVITY_BAR_STORAGE_KEY)).toBe('notes')
    expect(store.data.size).toBe(1)
  })

  it('没有存储 ⇒ 返回 false（没记住），但不抛', () => {
    expect(saveItemTo(null, 'notes')).toBe(false)
    expect(() => saveItemTo(undefined, 'notes')).not.toThrow()
  })

  it('存储写抛错 ⇒ 返回 false，界面这一下仍然切得动（调用方先改状态再落盘）', () => {
    expect(saveItemTo(hostileStore, 'workspace')).toBe(false)
  })

  it('写进去再读出来，还是同一项（往返一致）', () => {
    const store = fakeStore()
    for (const item of ITEMS) {
      saveItemTo(store, item)
      expect(loadItemFrom(store)).toBe(item)
    }
  })
})
