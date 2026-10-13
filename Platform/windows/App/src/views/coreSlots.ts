// 宿主**核心**视图的登记（契约 §3.52-①：编辑器 / 工作区 / 终端 / 数据库 /
// 文件与搜索 / 设置与凭据 = **基础核心**，不进插件清单）。
//
// 为什么核心视图也走同一张表：`App.vue` 若对核心视图写 `v-if`、对插件视图写查表，
// 那就是**两套机制** —— 迟早出现"核心视图加一个忘改一处"。一张表、一个查法。

import { registerCore, type CoreSlot } from '../shell/pluginRegistry'
import DatabaseView from './DatabaseView.vue'
import WorkspaceView from './WorkspaceView.vue'

/** 核心视图登记表（**加一个核心视图只加一行**）。 */
export const CORE_SLOTS: readonly CoreSlot[] = [
  {
    // 视图 id 与活动栏项 id 同名（活动栏的可见性判据是单点的，见 `activityBar.ts`）。
    id: 'workspace',
    mounts: ['activity-item', 'main-tab'],
    view: WorkspaceView,
  },
  {
    id: 'database',
    mounts: ['activity-item', 'main-tab'],
    view: DatabaseView,
  },
]

/** 把核心视图登记进注册表（`main.ts` 启动时调一次；**先核心、后插件**）。 */
export function registerCoreSlots(): void {
  registerCore(CORE_SLOTS)
}
