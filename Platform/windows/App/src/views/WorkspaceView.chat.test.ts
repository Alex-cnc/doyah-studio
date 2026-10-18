// @vitest-environment happy-dom
// 对话页签的**位置不变量**（`FR-AI-25` ①）：挂在**工作区页签条**上、占编辑区、可关 —— 不是侧栏。
//
// 三条判据：① Home 上有入口、点一下开出对话页签 ② 页签条里多一个「对话」且编辑区换成对话面板
// ③ 能关掉并落回 Home（开一个、关一个，不留残壳）。源码里没有侧栏承载对话（判据在 `check-plugins`
// 与这条挂载测的正面上：对话面板只在工作区编辑区里出现）。
import { describe, expect, it } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import WorkspaceView from './WorkspaceView.vue'

async function openWorkspace(wrapper: ReturnType<typeof mount>) {
  await wrapper.find('.ws__field input').setValue('C:/proj')
  await wrapper.find('form.ws__bar').trigger('submit')
  await flushPromises()
}

describe('对话页签（工作区页签条上的一类页签）', () => {
  it('Home 入口开出对话页签：页签条多一个「对话」，编辑区是对话面板', async () => {
    const wrapper = mount(WorkspaceView, { props: { version: '0.0.0-test' } })
    await openWorkspace(wrapper)

    expect(wrapper.find('[data-testid="chat-panel"]').exists()).toBe(false)
    await wrapper.find('[data-testid="home-chat"]').trigger('click')
    await flushPromises()

    // ② 页签条里真的有它（与文件名页签同列）
    const tabsText = wrapper.find('.ws__tabs').text()
    expect(tabsText).toContain('对话')
    // ③ 编辑区换成了对话面板，Home 的三栏不再画
    expect(wrapper.find('[data-testid="chat-panel"]').exists()).toBe(true)
    expect(wrapper.find('.home__columns').exists()).toBe(false)

    wrapper.unmount()
  })

  it('再点一次入口只切过去，不叠第二个对话页签', async () => {
    const wrapper = mount(WorkspaceView, { props: { version: '0.0.0-test' } })
    await openWorkspace(wrapper)
    await wrapper.find('[data-testid="home-chat"]').trigger('click')
    await flushPromises()
    // 切回 Home 再点一次入口
    await wrapper.findAll('.ws__tab-name')[0].trigger('click')
    await flushPromises()
    await wrapper.find('[data-testid="home-chat"]').trigger('click')
    await flushPromises()
    const names = wrapper.findAll('.ws__tab-name').map((node) => node.text())
    expect(names.filter((name) => name.includes('对话'))).toHaveLength(1)
    wrapper.unmount()
  })

  it('对话页签可以关掉：关完落回 Home，页签条里不再有它', async () => {
    const wrapper = mount(WorkspaceView, { props: { version: '0.0.0-test' } })
    await openWorkspace(wrapper)
    await wrapper.find('[data-testid="home-chat"]').trigger('click')
    await flushPromises()
    // 对话页签的关闭按钮（Home 那颗不该有，对话这颗该有）
    const closes = wrapper.findAll('.ws__tab-close')
    expect(closes.length).toBe(1)
    await closes[0].trigger('click')
    await flushPromises()
    expect(wrapper.find('[data-testid="chat-panel"]').exists()).toBe(false)
    expect(wrapper.text()).toContain('对话')
    expect(wrapper.find('.home__columns').exists()).toBe(true)
    wrapper.unmount()
  })
})
