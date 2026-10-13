// 活动栏的**清单驱动**派生（契约 §3.52-②③④ / §8.5.8）
//
// ## 这个文件解决什么
//
// 以前活动栏的"已开工项"是**写死在类型里**的常量（`activityBar.ts` 的 `BUILT_ITEMS`），
// 于是"加一个插件"要改好几处。契约②要求**清单是唯一出处**，所以这里把
// 「清单里声明了活动栏挂点的插件」**派生**成活动栏项。
//
// ## 三条纪律
//
// 1. **核心项与插件项合成一处**：活动栏项 = 核心项（工作区 / 数据库）+ 插件派生项。
// 2. **未实现的插件也要出现**（但点进去如实显示"未开工"）—— 与核心项里
//    "笔记未开工"是同一口径；**不假装能点、也不藏起来**。
// 3. **插件不在 ⇒ 派生结果里就没有它**（派生天然满足契约④：挂点整体消失、不报错）。

import type { ActivityBarItemId } from './activityBar'
import { pluginList } from './plugins'

/** 宿主自带的活动栏项（契约 §3.52-① 的**基础核心**：编辑器 / 工作区 / 终端 / 数据库 /
 *  文件与搜索 / 设置与凭据）。 */
export const CORE_ACTIVITY_ITEMS: readonly ActivityBarItemId[] = ['workspace', 'database']

/** 清单里**声明要占活动栏项**的插件 id（顺序 = 清单顺序）。 */
export function pluginActivityItems(): ActivityBarItemId[] {
  return pluginList.value
    .filter((p) => p.mounts.includes('activity-item'))
    .map((p) => p.id as ActivityBarItemId)
}

/**
 * 活动栏最终可见项 = **核心项 + 插件派生项**。
 *
 * 注意：返回的是**新的数组**（每次调用重算），调用方要放进 `computed` 里用。
 */
export function derivedActivityItems(): ActivityBarItemId[] {
  return [...CORE_ACTIVITY_ITEMS, ...pluginActivityItems()]
}
