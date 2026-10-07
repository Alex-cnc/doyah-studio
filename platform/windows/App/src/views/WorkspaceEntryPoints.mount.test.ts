// @vitest-environment happy-dom
// 入口可发现性（W-A-1，2026-10-07）：Home 页「📂 打开文件…」与命令面板「打开工作区文件夹」
// 两处入口必须**真的调起系统选择器** —— 改前两处都只写一行提示（点了没反应），
// 前门单 `T-20261007-015` 一 裁决为**真缺陷**。
//
// 判据面：mock 掉 `shell/dialogs`（**唯一的**系统选择器调用点），断言触发入口后
// 「选择器 API 被调用次数 = 1」。**改前**在旧实现上跑同一用例 ⇒ 红（一次都没调用）；**改后** ⇒ 绿。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'

const pickerMocks = vi.hoisted(() => ({ pickFile: vi.fn(), pickFolder: vi.fn() }))

vi.mock('../shell/dialogs', () => ({
  pickFile: pickerMocks.pickFile,
  pickFolder: pickerMocks.pickFolder,
}))

import WorkspaceView from './WorkspaceView.vue'
import App from '../App.vue'
import CommandPalette from '../shell/CommandPalette.vue'
import { commandById } from '../shell/commands'

beforeEach(() => {
  pickerMocks.pickFile.mockReset()
  pickerMocks.pickFolder.mockReset()
})

describe('入口可发现性：两处入口都真的调起系统选择器', () => {
  it('Home「📂 打开文件…」⇒ 文件选择器被调用一次（取消 ⇒ 到此为止，不往下走）', async () => {
    pickerMocks.pickFile.mockResolvedValue(null)
    const wrapper = mount(WorkspaceView, { props: {} })
    await flushPromises()

    // 先打开一个工作区，让 Home 页签出现（WorkspaceHome 只在 Home 页签里画）
    await wrapper.find('.ws__field input').setValue('C:/proj')
    await wrapper.find('form.ws__bar').trigger('submit')
    await flushPromises()
    expect(wrapper.find('.home__open').exists()).toBe(true)

    await wrapper.find('.home__open').trigger('click')
    await flushPromises()

    expect(pickerMocks.pickFile).toHaveBeenCalledTimes(1)
    wrapper.unmount()
  })

  it('命令面板「打开工作区文件夹」⇒ 文件夹选择器被调用一次', async () => {
    pickerMocks.pickFolder.mockResolvedValue(null)
    const wrapper = mount(App)
    await flushPromises()

    const palette = wrapper.findComponent(CommandPalette)
    const command = commandById('workspace.openFolder')
    expect(command).toBeDefined()
    palette.vm.$emit('run', command)
    await flushPromises()

    expect(pickerMocks.pickFolder).toHaveBeenCalledTimes(1)
    wrapper.unmount()
  })

  it('外壳递进「请打开这个目录」信号 ⇒ WorkspaceView 走**既有** openWorkspace 打开它', async () => {
    const wrapper = mount(WorkspaceView, { props: { openFolderSignal: null } })
    await flushPromises()
    await wrapper.setProps({ openFolderSignal: 'C:/picked/folder' })
    await flushPromises()
    expect((wrapper.find('.ws__field input').element as HTMLInputElement).value).toBe('C:/picked/folder')
    wrapper.unmount()
  })
})
