// @vitest-environment happy-dom
// 备份弹层（`FR-IO-04`）的**挂载判据**。
//
// 为什么必须挂一次：`.vue` 不在 `tsc --noEmit` 的程序里（模板引用了没 import 的名字照样编译得过，
// 点开才 ReferenceError —— 本仓踩过）。这里钉五件事：
//   ① 命令行的**打码形状**要真的画出来（`PGPASSWORD=***`）—— 这是「口令不进 argv」的可见证据；
//   ② 程序找不到时，**去哪儿找过**要摆出来（不是只写「失败」）；
//   ③ 目标问题的原因原样显示（已存在 / 不覆盖），且此时「开始备份」不可点；
//   ④ 跑成功：字节数与路径 + 日志尾部；日志被截断要如实说被砍了多少字符；
//   ⑤ 没连库时说的是「没连库」，不是把按钮灰着不给理由。
import { describe, expect, it, vi, beforeEach } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import type { BackupPlanReport, BackupReport } from '../ipc'

const state: {
  plan: BackupPlanReport | null
  planFailure: { message: string; hint: string } | null
  report: BackupReport | null
  runFailure: { message: string; hint: string } | null
  planCalls: number
  runCalls: number
} = { plan: null, planFailure: null, report: null, runFailure: null, planCalls: 0, runCalls: 0 }

vi.mock('../ipc', () => ({
  backupPlan: vi.fn(async () => {
    state.planCalls += 1
    if (state.planFailure) throw state.planFailure
    return state.plan
  }),
  backupRun: vi.fn(async () => {
    state.runCalls += 1
    if (state.runFailure) throw state.runFailure
    return state.report
  }),
}))

import BackupDialog from './BackupDialog.vue'

function plan(over: Partial<BackupPlanReport> = {}): BackupPlanReport {
  return {
    program: 'C:\\Program Files\\PostgreSQL\\18\\bin\\pg_dump.exe',
    display:
      'PGPASSWORD=*** "C:\\Program Files\\PostgreSQL\\18\\bin\\pg_dump.exe" -h db.internal -p 5432 -U doyah -d shop -F c -f D:\\backup\\shop.dump',
    database: 'shop',
    target: 'D:\\backup\\shop.dump',
    format: 'custom',
    problem: null,
    ...over,
  }
}

function report(over: Partial<BackupReport> = {}): BackupReport {
  return {
    display: 'PGPASSWORD=*** pg_dump …',
    exitCode: 0,
    log: '',
    logTrimmedChars: 0,
    bytes: 2048,
    elapsedMs: 1200,
    target: 'D:\\backup\\shop.dump',
    format: 'custom',
    ...over,
  }
}

function mountDialog(props: Record<string, unknown> = {}) {
  return mount(BackupDialog, {
    props: {
      open: true,
      language: 'zh-Hans' as const,
      connectionId: 'conn-1',
      database: '',
      ...props,
    },
  })
}

/** 填好路径并让它重算一次计划（弹层的计划是在 `change` 上重算的）。 */
async function typePath(wrapper: ReturnType<typeof mountDialog>, value: string) {
  const input = wrapper.get('[data-testid="backup-path"]')
  await input.setValue(value)
  await input.trigger('change')
  await flushPromises()
}

beforeEach(() => {
  state.plan = plan()
  state.planFailure = null
  state.report = null
  state.runFailure = null
  state.planCalls = 0
  state.runCalls = 0
})

describe('备份弹层（FR-IO-04）', () => {
  it('把将要执行的命令行摊出来，口令位置只写 ***', async () => {
    const wrapper = mountDialog()
    await typePath(wrapper, 'D:\\backup\\shop.dump')

    const command = wrapper.get('[data-testid="backup-command"]')
    expect(command.text()).toContain('PGPASSWORD=***')
    expect(command.text()).toContain('-F c')
    expect(command.text()).toContain('pg_dump.exe')
    // 口令本体一个字符都不许出现在界面上
    expect(wrapper.text()).not.toContain('PGPASSWORD=hunter2')
    // 找到的程序要写出来（用户据此判断是不是自己想用的那一份）
    expect(wrapper.get('[data-testid="backup-program-found"]').text()).toContain('pg_dump.exe')
  })

  it('程序找不到时说清「找过哪些地方」，并且不许点开始', async () => {
    state.plan = plan({
      program: null,
      display: 'PGPASSWORD=*** pg_dump …',
      problem: {
        message: '找不到 pg_dump（本机没装 PostgreSQL 客户端，或装在了别处）',
        hint: '找过这些地方：PATH / C:\\Program Files\\PostgreSQL\\<版本>\\bin',
      },
    })
    const wrapper = mountDialog()
    await typePath(wrapper, 'D:\\backup\\shop.dump')

    expect(wrapper.get('[data-testid="backup-program-missing"]').text()).toContain('没找到')
    const problem = wrapper.get('[data-testid="backup-problem"]').text()
    expect(problem).toContain('找过这些地方')
    expect(problem).toContain('PATH')
    expect(wrapper.get('[data-testid="backup-run"]').attributes('disabled')).toBeDefined()
  })

  it('目标已存在时把原因原样摆出来，且不许点开始', async () => {
    state.plan = plan({
      problem: {
        message: 'D:\\backup\\shop.dump 已经存在 —— 备份不覆盖既有文件',
        hint: '换一个文件名，或自己先把旧备份挪走',
      },
    })
    const wrapper = mountDialog()
    await typePath(wrapper, 'D:\\backup\\shop.dump')

    expect(wrapper.get('[data-testid="backup-problem"]').text()).toContain('不覆盖既有文件')
    expect(wrapper.get('[data-testid="backup-run"]').attributes('disabled')).toBeDefined()
  })

  it('还没填路径时不报错，只说明「填了就给你看命令行」', async () => {
    const wrapper = mountDialog()
    await flushPromises()

    expect(wrapper.find('[data-testid="backup-need-path"]').exists()).toBe(true)
    expect(wrapper.find('[data-testid="backup-command"]').exists()).toBe(false)
    expect(wrapper.get('[data-testid="backup-run"]').attributes('disabled')).toBeDefined()
    expect(state.planCalls).toBe(0)
  })

  it('跑成功：字节 / 路径 / 耗时 + 日志尾部，日志被截断要说被砍了多少', async () => {
    state.report = report({
      bytes: 4096,
      elapsedMs: 2500,
      log: 'pg_dump: dumping contents of table "orders"',
      logTrimmedChars: 1200,
    })
    const wrapper = mountDialog()
    await typePath(wrapper, 'D:\\backup\\shop.dump')
    await wrapper.get('[data-testid="backup-run"]').trigger('click')
    await flushPromises()

    const ok = wrapper.get('[data-testid="backup-ok"]').text()
    expect(ok).toContain('4.0 KB')
    expect(ok).toContain('D:\\backup\\shop.dump')
    expect(ok).toContain('2500')
    expect(wrapper.get('[data-testid="backup-log"]').text()).toContain('dumping contents of table')
    expect(wrapper.get('[data-testid="backup-log-trimmed"]').text()).toContain('1200')
  })

  it('跑失败：退出码与子进程原话照实显示（不缩写成「失败」两个字）', async () => {
    state.runFailure = {
      message: 'pg_dump 退出码 1：pg_dump: error: connection to server at "db.internal" failed',
      hint: '口令被拒：核对连接里的用户名与口令',
    }
    const wrapper = mountDialog()
    await typePath(wrapper, 'D:\\backup\\shop.dump')
    await wrapper.get('[data-testid="backup-run"]').trigger('click')
    await flushPromises()

    const failure = wrapper.get('[data-testid="backup-failure-message"]').text()
    expect(failure).toContain('退出码 1')
    expect(failure).toContain('connection to server')
    expect(failure).toContain('口令被拒')
    expect(wrapper.find('[data-testid="backup-ok"]').exists()).toBe(false)
  })

  it('没连库时说的是「没连库」，而不是把按钮灰着不给理由', async () => {
    const wrapper = mountDialog({ connectionId: null })
    await flushPromises()

    expect(wrapper.get('[data-testid="backup-no-connection"]').text()).toContain('还没有连接')
    expect(wrapper.find('[data-testid="backup-path"]').exists()).toBe(false)
    expect(state.planCalls).toBe(0)
  })
})
