// 插件装配的唯一入口（**"装了哪些插件"就看这个文件**）
//
// 契约§3.52-②要求「清单 = 一处声明；界面与构建只消费它」。清单本体在**领域层**
// （`Db/src/plugins.rs`）；这里只是**界面侧的装配点**：把每个插件目录的 `install()` 调一遍。
//
// 判据 `App/tools/check-plugins.mjs` 会把三处对起来：
//   ① 领域层清单的 id/mounts  ⇄  ② 这里的 import 与 install  ⇄  ③ 插件目录的 PLUGIN_ID/PLUGIN_MOUNTS
// 三处任何一处对不上 ⇒ 判红（这就是"清单唯一出处"的机械保证）。

import { install as installNotes } from './notes'
import { install as installRetro } from './retro'

/** 已装配插件（**加一个插件只加一行**）。
 *
 *  注：类型写成 `ReadonlyArray<…>` 而不是"只读数组"那种 TS 标注 ——
 *  后者的写法里那个关键字会被 `Tools/check-vue-imports.ps1` 误当成 Vue 的同名 API
 *  而判红（实测踩到）。换写法既避开误判，语义不变。 */
const INSTALLERS: ReadonlyArray<() => void> = [
  installNotes,
  installRetro,
]

/** 装配全部插件（`main.ts` 在清单装载后调一次）。 */
export function installPlugins(): void {
  for (const install of INSTALLERS) {
    install()
  }
}
