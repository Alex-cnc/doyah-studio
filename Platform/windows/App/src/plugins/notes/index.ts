// 笔记插件 · 装配入口（**这个文件就是"插件被装上了"这件事本身**）
//
// 口径（契约§3.52-④）：**插件不在 ⇒ 其挂点整体消失且不报错**。
// 所以"拔掉插件"= 不再 import 本文件（或删掉本目录）；界面**不会**因此报错：
// 注册表里没有该 id ⇒ 入口与视图**都不出现**。

import NotesView from './NotesView.vue'
import { registerPlugin } from '../../shell/pluginRegistry'

/** 插件 id（**必须与清单里的 `id` 一致**，判据 `check-plugins.mjs` 会对账）。 */
export const PLUGIN_ID = 'notes'

/** 本插件占用的挂点（必须与清单里的 `mounts` 一致）。 */
export const PLUGIN_MOUNTS = ['activity-item', 'main-tab', 'search-index', 'storage-factory'] as const

/** 装配（外壳在清单装载后调用）。 */
export function install(): void {
  registerPlugin({
    id: PLUGIN_ID,
    mounts: [...PLUGIN_MOUNTS],
    view: NotesView,
  })
}
