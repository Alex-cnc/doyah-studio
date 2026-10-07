// 系统选择器（文件 / 文件夹）—— **两处「入口」共用这一份，不许各写一套**
//
// 由头（前门单 `T-20261007-015` 一 · 人类主人 2026-10-07 实测「工作区功能还没有」）：
// 整屏挂不上的 P0 修掉之后，还剩**两条入口死路** —— Home 页「📂 打开文件…」只往界面写一行提示、
// 命令面板「打开工作区文件夹」只回一句「请在视图里用界面按钮执行」。按钮名承诺了动作、行为却只是提示。
//
// 做法：接 Tauri 2 官方的对话框能力（Rust 侧 `tauri-plugin-dialog`、前端 `@tauri-apps/plugin-dialog`）。
// **本模块是唯一调用点** —— 视图只调这里的 `pickFile` / `pickFolder`，不直接 import 插件。
// 为什么收成一处：① 两处入口接的是**同一个**系统选择器，各写一套必然漂移；② 自动化判据
// （`vitest`）只需对**一处**打桩，就能断言「触发入口 ⇒ 选择器真的被调用」，不自欺。
import { open } from '@tauri-apps/plugin-dialog'
import { inTauri } from '../ipc'

export interface PickOptions {
  /** 对话框标题（给人看的；不传就用系统缺省） */
  title?: string
}

/**
 * 打开系统「选择文件」对话框 —— 返回**绝对路径**；用户取消 ⇒ `null`。
 *
 * 非真外壳（浏览器旁路 / 单测）⇒ 一律 `null`：没有系统选择器可弹，如实返回"没选"，
 * 不去猜一个假路径（猜出来的路径打开必然是错的）。
 */
export async function pickFile(options: PickOptions = {}): Promise<string | null> {
  if (!inTauri()) return null
  const selected = await open({ multiple: false, directory: false, title: options.title })
  return typeof selected === 'string' ? selected : null
}

/**
 * 打开系统「选择文件夹」对话框 —— 返回**绝对路径**；用户取消 ⇒ `null`。
 *
 * 口径与 macOS 侧 `WorkspaceStore.pickAndChoose()` 逐条对齐：只选目录、不选文件、不允许多选、
 * 不许在对话框里新建目录（`canChooseFiles=false` / `canChooseDirectories=true` /
 * `allowsMultipleSelection=false` / `canCreateDirectories=false`）。
 */
export async function pickFolder(options: PickOptions = {}): Promise<string | null> {
  if (!inTauri()) return null
  const selected = await open({ multiple: false, directory: true, title: options.title })
  return typeof selected === 'string' ? selected : null
}
