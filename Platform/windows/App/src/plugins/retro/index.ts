// 回放插件 · 装配入口（同笔记插件口径：本文件在 = 插件被装上）
//
// 契约§3.52-④：**插件不在 ⇒ 其挂点整体消失且不报错**。

import RetroView from './RetroView.vue'
import { registerPlugin } from '../../shell/pluginRegistry'

/** 插件 id（必须与清单里的 `id` 一致）。 */
export const PLUGIN_ID = 'retro'

/** 本插件占用的挂点（必须与清单里的 `mounts` 一致）。 */
export const PLUGIN_MOUNTS = ['activity-item', 'main-tab', 'storage-factory'] as const

/** 装配（外壳在清单装载后调用）。 */
export function install(): void {
  registerPlugin({
    id: PLUGIN_ID,
    mounts: [...PLUGIN_MOUNTS],
    view: RetroView,
  })
}
