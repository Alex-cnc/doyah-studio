// 活动栏选中态的**单点**（Windows 侧外壳）
//
// 口径（照抄对侧 `AppState` 那一层的行为，本侧落在表示层一个具名模块里）：
//   · 选中项只有这一处状态 —— 视图里不许各存一份；
//   · 落盘只写 `ActivityBarItem` 的 id（键见 `ACTIVITY_BAR_STORAGE_KEY`），**解析一律过 `resolveActivityBarItem`**
//     （写进去的是什么不重要，读出来必须是栏上真正存在的一项）；
//   · 存储不可用（无 storage / 配额满 / 被禁用）⇒ **界面照常起来**，只是记不住 —— 不抛、不白屏。
//
// 为什么把「读取」单独抽成 `loadItemFrom`：这样它能拿一个假存储单测，
// 而不是把「存储坏了会怎样」留到某天用户机器上才发现。

import { ref, type Ref } from 'vue'
import {
  ACTIVITY_BAR_STORAGE_KEY,
  ITEMS,
  resolveActivityBarItem,
  type ActivityBarItemId,
} from './activityBar'

/** 最小存储面（`Storage` 的结构子集）—— 只用到读 / 写 / 删三个动作。 */
export interface KeyValueStore {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
  removeItem(key: string): void
}

function hostStorage(): KeyValueStore | null {
  try {
    const s = (globalThis as { localStorage?: KeyValueStore }).localStorage
    return s ?? null
  } catch {
    // 某些环境下**访问** localStorage 本身就抛（隐私模式 / 权限策略）⇒ 当作「没有存储」
    return null
  }
}

/** 从存储里读一项；存储缺失或抛错都回退（回退值由 `resolveActivityBarItem` 定）。 */
export function loadItemFrom(
  store: KeyValueStore | null | undefined,
  visible: readonly ActivityBarItemId[] = ITEMS,
): ActivityBarItemId {
  let raw: string | null = null
  try {
    raw = store ? store.getItem(ACTIVITY_BAR_STORAGE_KEY) : null
  } catch {
    raw = null
  }
  return resolveActivityBarItem(raw, visible)
}

/** 写一项；存储缺失或抛错都**不影响界面**（返回 false 表示没记住）。 */
export function saveItemTo(
  store: KeyValueStore | null | undefined,
  item: ActivityBarItemId,
): boolean {
  if (!store) return false
  try {
    store.setItem(ACTIVITY_BAR_STORAGE_KEY, item)
    return true
  } catch {
    return false
  }
}

/** 选中态（单点）。视图只读它，切换只经 `setActive`。 */
export const activeItem: Ref<ActivityBarItemId> = ref(loadItemFrom(hostStorage()))

/** 切换视图：先改状态（界面立即响应），再落盘（记不住也不影响这一下能切）。 */
export function setActive(item: ActivityBarItemId): boolean {
  activeItem.value = item
  return saveItemTo(hostStorage(), item)
}
