// 插件槽位与视图注册表（契约依据 = 概要设计 §3.52；本侧落法 = §8.5.8）
//
// ## 这个文件解决什么
//
// 契约③要求「插件只能经**宿主挂点**接进来」，契约④要求「插件不在 ⇒ 其挂点**整体消失且不报错**」。
// 所以界面不能各处 `import DatabaseView from …` 直接写死，而要：
//
//   1. **宿主自带的核心视图**（工作区 / 数据库）走同一张表登记；
//   2. **插件视图**（笔记 / 回放）由**插件自己**在自己的目录里登记；
//   3. 表里查不到 ⇒ 界面**什么都不画**（不是画个报错，也不是回退到别的视图）。
//
// ## 为什么用"动态 import + 查表"而不是静态 import
//
// 静态 `import` 会让**构建期**就依赖插件目录：插件被拔掉时**构建直接失败**，
// 而契约④要的是"拔掉后**不报错**"。动态 `import()` 让"目录不在"表现为
// **加载期的一次 rejected promise**，界面据此走空态 —— 这才是可装卸。
//
// ## 与清单的关系
//
// 这里的 `id` **必须**能在清单（领域层 `Db/src/plugins.rs`）里找到出处；
// 对账由 `App/tools/check-plugins.mjs` 做（判据，不在运行时）。

import { defineAsyncComponent, type Component } from 'vue'

/** 插件界面在自己的目录里登记一项（**只有插件目录会调它**）。 */
export interface PluginSlot {
  /** 视图 id（= 插件清单里的 `id`；**不在清单里的 id 视为未登记**）。 */
  id: string
  /** 挂点集合（只能取七类之一；当前界面用到的是 `activity-item` 与 `main-tab`）。 */
  mounts: string[]
  /** 插件自己的界面根组件。 */
  view: Component
}

/** 宿主**基础核心**的视图（不进插件清单 —— 契约 §3.52-① 把编辑器 / 工作区 / 终端 /
 *  数据库 / 文件与搜索 / 设置与凭据列为核心）。 */
export interface CoreSlot {
  id: string
  mounts: string[]
  view: Component
}

/** 视图注册表：`id → 组件`。**查不到就什么都不画。** */
const registry = new Map<string, Component>()

/** 登记宿主核心视图（由 `views/coreSlots.ts` 在启动时调一次）。 */
export function registerCore(slots: readonly CoreSlot[]): void {
  for (const slot of slots) {
    registry.set(slot.id, slot.view)
  }
}

/** 登记一个插件（由插件目录的 `index.ts` 在启动时调）。 */
export function registerPlugin(slot: PluginSlot): void {
  // 同一 id 重复登记 ⇒ 后登记的覆盖前者是**静默错误**，宁可不管也不撒谎：
  // 这里保留先登记的，并把重复暴露给判据（`check-plugins.mjs` 会查"同 id 登记两次"）。
  if (!registry.has(slot.id)) {
    registry.set(slot.id, slot.view)
  }
}

/** 表里有没有这个视图（**未登记 = 不画**，调用方不要自己编兜底）。 */
export function hasView(id: string): boolean {
  return registry.has(id)
}

/**
 * 取视图组件；**未登记返回 `undefined`**。
 *
 * 调用方（`App.vue`）据此决定：`undefined` ⇒ 该插件未装 / 未登记 ⇒ **入口也不该出现**
 * （入口可见性由清单决定，两边同一个来源）。
 */
export function resolveView(id: string): Component | undefined {
  return registry.get(id)
}

/** 已登记的视图 id（判据与调试用；**不是**活动栏顺序）。 */
export function registeredIds(): string[] {
  return [...registry.keys()]
}

/** 仅供判据/测试：清空注册表（**用例之间必须互相隔离** —— 注册表是模块级状态）。 */
export function resetRegistryForTest(): void {
  registry.clear()
}

/** 懒加载一个插件视图（路径按约定拼：`./plugins/<entry>/View.vue`）。
 *
 *  Vite 要求动态 import 的路径**可静态分析**，所以这里用一层显式表 ——
 *  新增插件时**只加一行**（这一行就是"构建面"的登记点，`check-plugins.mjs` 会对账）。
 */
export function lazyPluginView(entry: string): Component {
  const loaders: Record<string, () => Promise<unknown>> = {
    notes: () => import('../plugins/notes/NotesView.vue'),
    retro: () => import('../plugins/retro/RetroView.vue'),
  }
  const load = loaders[entry]
  if (!load) {
    // 未知入口：返回一个"如实说没装"的极小组件，**不抛异常**（契约④：不许报错）。
    return defineAsyncComponent(async () => {
      const { h } = await import('vue')
      return {
        name: 'PluginMissing',
        render: () => h('div', { class: 'plugin-missing' }, `插件入口未登记：${entry}`),
      }
    })
  }
  return defineAsyncComponent(load as () => Promise<Component>)
}

// ── 宿主能力（插件只从这里拿，**不许** import shell 的其它模块）──────────────────────
//
// 由头（`FR-R-12-04` 包导入）：插件要弹系统「选文件夹」对话框，但插件边界判据
// （`check-plugins.mjs` ④）只许插件 import 挂点契约 + 公共面（`i18n` / `ipc` / `vue`）——
// 让插件直接 import `shell/dialogs` 会把 shell 内部结构暴露给插件，插件也就跟着宿主改。
//
// 做法：把「弹选择器」收成**契约上的一项宿主能力**。实现仍只有一处（`shell/dialogs.ts`），
// 插件只认识这个函数名 —— 宿主换实现（换插件、换权限）不牵动任何插件代码。

/** 弹系统「选择文件夹」对话框：返回绝对路径；用户取消或非真外壳 ⇒ `null`。 */
export async function pickFolder(options: { title?: string } = {}): Promise<string | null> {
  const { pickFolder: open } = await import('./dialogs')
  return open(options)
}
