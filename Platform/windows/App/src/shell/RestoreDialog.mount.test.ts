// @vitest-environment happy-dom
// 恢复弹层（`FR-IO-05`）的**挂载判据**。
//
// `.vue` 不在 `tsc --noEmit` 的程序里（模板里调了未 import 的名字照样「类型门」绿 —— 本仓踩过），
// 所以这里挂一次真组件，钉六件事：
//   ① 没选源时说的是「先选一份备份」，不是把按钮灰着不给理由；
//   ② 选源 ⇒ 外壳的 `restorePlan` 真被调用，且**命令行画出来**（含 `PGPASSWORD=***` 与两个旗标）；
//   ③ 勾「先删后建」⇒ 计划**重算**（旧串留在界面上等于骗人）；
//   ④ 源是文件归档时 `--jobs` 控件**禁用**并说串行（`pg_restore` 不接文件归档上的 `-j`）；
//   ⑤ 点「开始恢复」⇒ `restoreRun` 真被调用，结果行照回执的 source / database / 实际并行度说话；
//   ⑥ 失败 + 取消：错误原话要摆出来，且「已写入的对象不会撤销」这句必须出现。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import type {
  RestorePlanReport,
  RestoreReport,
  RestoreSectionsPlanReport,
  RestoreSectionsReport,
  SectionOutcome,
} from '../ipc'

const state: {
  plan: RestorePlanReport | null
  planFailure: { message: string; hint: string } | null
  report: RestoreReport | null
  runFailure: { message: string; hint: string } | null
  planCalls: number
  runCalls: number
  lastRequest: Record<string, unknown> | null
  /** **真正发起恢复**的那一次请求（`lastRequest` 会被随后的计划重算覆盖，续跑类断言必须看这个） */
  lastRunRequest: Record<string, unknown> | null
  cancelCalls: number
  cancelAccepts: boolean
  /** 逐段模式的计划 / 结局（FR-IO-05 失败续跑这一半） */
  sectionsPlan: RestoreSectionsPlanReport | null
  sectionsReport: RestoreSectionsReport | null
  sectionsPlanCalls: number
  sectionsRunCalls: number
  /** 让 `restoreRun` 挂住不返回（用来验「跑着 → 取消」这一档） */
  hold: boolean
  settle: { resolve: (value: RestoreReport) => void; reject: (reason: unknown) => void } | null
} = {
  plan: null,
  planFailure: null,
  report: null,
  runFailure: null,
  planCalls: 0,
  runCalls: 0,
  lastRequest: null,
  lastRunRequest: null,
  cancelCalls: 0,
  cancelAccepts: true,
  sectionsPlan: null,
  sectionsReport: null,
  sectionsPlanCalls: 0,
  sectionsRunCalls: 0,
  hold: false,
  settle: null,
}

vi.mock('../ipc', () => ({
  restorePlan: vi.fn(async (request: Record<string, unknown>) => {
    state.planCalls += 1
    state.lastRequest = request
    if (state.planFailure) throw state.planFailure
    return state.plan
  }),
  restoreRun: vi.fn(async (request: Record<string, unknown>) => {
    state.runCalls += 1
    state.lastRequest = request
    state.lastRunRequest = request
    if (state.hold) {
      return await new Promise<RestoreReport>((resolve, reject) => {
        state.settle = { resolve, reject }
      })
    }
    if (state.runFailure) throw state.runFailure
    return state.report
  }),
  restorePlanSections: vi.fn(async (request: Record<string, unknown>) => {
    state.sectionsPlanCalls += 1
    state.lastRequest = request
    if (state.planFailure) throw state.planFailure
    return state.sectionsPlan
  }),
  restoreRunSections: vi.fn(async (request: Record<string, unknown>) => {
    state.sectionsRunCalls += 1
    state.lastRequest = request
    state.lastRunRequest = request
    if (state.runFailure) throw state.runFailure
    return state.sectionsReport
  }),
  restoreCancel: vi.fn(async () => {
    state.cancelCalls += 1
    return state.cancelAccepts
  }),
}))

// 系统选择器：真外壳里弹系统对话框，单测里只验「点了它 ⇒ 选择器被调用 ⇒ 选回来的路径进了输入框」
const pick = { file: null as string | null, folder: null as string | null, fileCalls: 0, folderCalls: 0 }
vi.mock('./dialogs', () => ({
  pickFile: vi.fn(async () => {
    pick.fileCalls += 1
    return pick.file
  }),
  pickFolder: vi.fn(async () => {
    pick.folderCalls += 1
    return pick.folder
  }),
}))

import RestoreDialog from './RestoreDialog.vue'

function plan(over: Partial<RestorePlanReport> = {}): RestorePlanReport {
  return {
    program: 'C:\\Program Files\\PostgreSQL\\18\\bin\\pg_restore.exe',
    display:
      'PGPASSWORD=*** "C:\\Program Files\\PostgreSQL\\18\\bin\\pg_restore.exe" -h db.internal -p 5432 -U doyah -d shop --verbose --clean --if-exists D:\\backup\\shop.dump',
    database: 'shop',
    source: 'D:\\backup\\shop.dump',
    kind: 'file',
    section: 'all',
    jobs: 0,
    problem: null,
    ...over,
  }
}

function report(over: Partial<RestoreReport> = {}): RestoreReport {
  return {
    display: 'PGPASSWORD=*** pg_restore ...',
    exitCode: 0,
    log: 'pg_restore: creating TABLE public.orders\npg_restore: processing data for table "public.orders"',
    logTrimmedChars: 0,
    elapsedMs: 1234,
    source: 'D:\\backup\\shop.dump',
    section: 'all',
    jobs: 0,
    database: 'shop',
    ...over,
  }
}

function sectionOutcome(section: SectionOutcome['section'], ok: boolean): SectionOutcome {
  return {
    section,
    ok,
    cancelled: false,
    exitCode: ok ? 0 : 1,
    elapsedMs: ok ? 320 : 210,
    display: `PGPASSWORD=*** pg_restore.exe -h db.internal -p 5432 -U doyah -d shop --verbose --section=${section} --exit-on-error D:\\backup\\shop.dump`,
    log: ok ? `pg_restore: ${section} done` : 'pg_restore: error: relation "public.orders" does not exist',
    logTrimmedChars: 0,
  }
}

function sectionsPlan(over: Partial<RestoreSectionsPlanReport> = {}): RestoreSectionsPlanReport {
  const sections: SectionOutcome['section'][] = ['pre-data', 'data', 'post-data']
  return {
    program: 'C:\\Program Files\\PostgreSQL\\18\\bin\\pg_restore.exe',
    commands: sections.map((section) => ({
      section,
      display: `PGPASSWORD=*** "C:\\Program Files\\PostgreSQL\\18\\bin\\pg_restore.exe" -h db.internal -p 5432 -U doyah -d shop --verbose --clean --if-exists --section=${section} --exit-on-error D:\\backup\\shop.dump`,
      jobs: 0,
    })),
    database: 'shop',
    source: 'D:\\backup\\shop.dump',
    kind: 'file',
    jobs: 0,
    problem: null,
    ...over,
  }
}

function sectionsReport(over: Partial<RestoreSectionsReport> = {}): RestoreSectionsReport {
  return {
    source: 'D:\\backup\\shop.dump',
    database: 'shop',
    jobs: 0,
    sections: [sectionOutcome('pre-data', true), sectionOutcome('data', false)],
    failed: 'data',
    cancelled: false,
    failure: {
      message: 'pg_restore 退出码 1：relation "public.orders" does not exist',
      hint: '看上面子进程的原话',
    },
    resumeFrom: ['data', 'post-data'],
    resumeCommand:
      'PGPASSWORD=*** "C:\\Program Files\\PostgreSQL\\18\\bin\\pg_restore.exe" -h db.internal -p 5432 -U doyah -d shop --verbose --clean --if-exists --section=data --exit-on-error D:\\backup\\shop.dump',
    elapsedMs: 530,
    ...over,
  }
}

function mountDialog(props: Partial<{ open: boolean; connectionId: string | null }> = {}) {
  return mount(RestoreDialog, {
    props: {
      open: true,
      language: 'zh-Hans' as const,
      connectionId: 'conn-1' as string | null,
      database: 'shop',
      ...props,
    },
  })
}

beforeEach(() => {
  state.plan = plan()
  state.planFailure = null
  state.report = report()
  state.runFailure = null
  state.planCalls = 0
  state.runCalls = 0
  state.lastRequest = null
  state.lastRunRequest = null
  state.cancelCalls = 0
  state.cancelAccepts = true
  state.sectionsPlan = sectionsPlan()
  state.sectionsReport = sectionsReport()
  state.sectionsPlanCalls = 0
  state.sectionsRunCalls = 0
  pick.file = 'D:\\backup\\shop.dump'
  pick.folder = 'D:\\backup\\shop-dir'
  pick.fileCalls = 0
  pick.folderCalls = 0
})

describe('RestoreDialog（FR-IO-05 的可见面）', () => {
  it('没选源时给的是「先选一份备份」，且开始键不可点', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    expect(wrapper.find('[data-testid="restore-need-path"]').exists()).toBe(true)
    expect(wrapper.find('[data-testid="restore-command"]').exists()).toBe(false)
    expect(wrapper.find('[data-testid="restore-run"]').attributes('disabled')).toBeDefined()
    // 没填东西不该去问外壳要计划（空源问一次只会得到一条无意义的错）
    expect(state.planCalls).toBe(0)
  })

  it('选归档文件后：计划真的被问了一次，命令行原样画出来（口令打码）', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    await wrapper.find('[data-testid="restore-pick-file"]').trigger('click')
    await flushPromises()
    expect(pick.fileCalls).toBe(1)
    expect(state.planCalls).toBeGreaterThan(0)
    const command = wrapper.find('[data-testid="restore-command"]').text()
    expect(command).toContain('PGPASSWORD=***')
    expect(command).toContain('pg_restore.exe')
    expect(command).toContain('D:\\backup\\shop.dump')
    // 命令行里不许出现真口令（这份回执本来就只可能是打码串，这里是回归钉子）
    expect(command).not.toContain('PGPASSWORD=secret')
    expect(wrapper.find('[data-testid="restore-program-found"]').exists()).toBe(true)
  })

  it('勾「先删后建」会重算计划（界面上的命令行走在开关之后）', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    await wrapper.find('[data-testid="restore-pick-file"]').trigger('click')
    await flushPromises()
    const before = state.planCalls
    await wrapper.find('[data-testid="restore-clean"]').setValue(true)
    await flushPromises()
    expect(state.planCalls).toBeGreaterThan(before)
    expect(state.lastRequest?.clean).toBe(true)
  })

  it('源是文件归档时并行度控件禁用并说串行；是目录归档才可选', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    await wrapper.find('[data-testid="restore-pick-file"]').trigger('click')
    await flushPromises()
    expect(wrapper.find('[data-testid="restore-jobs"]').attributes('disabled')).toBeDefined()
    expect(wrapper.find('[data-testid="restore-jobs-hint"]').text()).toContain('串行')

    state.plan = plan({ kind: 'directory', source: 'D:\\backup\\shop-dir', jobs: 4 })
    await wrapper.find('[data-testid="restore-pick-folder"]').trigger('click')
    await flushPromises()
    expect(pick.folderCalls).toBe(1)
    expect(wrapper.find('[data-testid="restore-jobs"]').attributes('disabled')).toBeUndefined()
  })

  it('点开始恢复：命令真被调用，结果行照回执的实际并行度与日志尾部说话', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    await wrapper.find('[data-testid="restore-pick-file"]').trigger('click')
    await flushPromises()
    state.report = report({ jobs: 0, logTrimmedChars: 37 })
    await wrapper.find('[data-testid="restore-run"]').trigger('click')
    await flushPromises()
    expect(state.runCalls).toBe(1)
    const ok = wrapper.find('[data-testid="restore-ok"]').text()
    expect(ok).toContain('shop')
    expect(ok).toContain('D:\\backup\\shop.dump')
    expect(ok).toContain('串行')
    expect(wrapper.find('[data-testid="restore-log"]').text()).toContain('public.orders')
    expect(wrapper.find('[data-testid="restore-log-trimmed"]').text()).toContain('37')
  })

  it('失败：错误原话摆出来；取消之后再失败还要说清「已写入的对象不会撤销」', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    await wrapper.find('[data-testid="restore-pick-file"]').trigger('click')
    await flushPromises()
    state.runFailure = { message: 'pg_restore 退出码 1：relation already exists', hint: '勾上「先删后建」再跑' }
    await wrapper.find('[data-testid="restore-run"]').trigger('click')
    await flushPromises()
    const failure = wrapper.find('[data-testid="restore-failure-message"]').text()
    expect(failure).toContain('退出码 1')
    expect(failure).toContain('先删后建')
    expect(wrapper.find('[data-testid="restore-cancelled-hint"]').exists()).toBe(false)

    // 换一档：这次是「跑着 → 点取消 → 外壳以取消为由返回失败」那条真路径
    state.hold = true
    state.runFailure = null
    await wrapper.find('[data-testid="restore-run"]').trigger('click')
    await flushPromises()
    await wrapper.find('[data-testid="restore-cancel-run"]').trigger('click')
    await flushPromises()
    expect(state.cancelCalls).toBe(1)
    state.settle?.reject({
      message: '恢复已取消：你在第 400 ms 叫停了它，库里可能停在半途',
      hint: '已被 pg_restore 写进去的对象不会自动撤销。',
    })
    await flushPromises()
    expect(wrapper.find('[data-testid="restore-failure-message"]').text()).toContain('恢复已取消')
    expect(wrapper.find('[data-testid="restore-cancelled-hint"]').text()).toContain('不会自动撤销')
    state.hold = false
  })

  it('没连库时说的是「还没连接」，不是把按钮灰着不给理由', async () => {
    const wrapper = mountDialog({ connectionId: null })
    await flushPromises()
    expect(wrapper.find('[data-testid="restore-no-connection"]').exists()).toBe(true)
    expect(wrapper.find('[data-testid="restore-source"]').exists()).toBe(false)
  })

  // ── 逐段恢复 / 失败续跑（FR-IO-05 的这一半）────────────────────────────────

  it('勾「逐段恢复」：问的是逐段计划，三段命令行**每段一条**都摊出来', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    await wrapper.find('[data-testid="restore-pick-file"]').trigger('click')
    await flushPromises()
    expect(state.sectionsPlanCalls).toBe(0)

    await wrapper.find('[data-testid="restore-sections"]').setValue(true)
    await flushPromises()
    expect(state.sectionsPlanCalls).toBeGreaterThan(0)
    // 单段计划不该再被画出来（两套命令行同屏 = 用户不知道哪条真会跑）
    expect(wrapper.find('[data-testid="restore-command"]').exists()).toBe(false)
    const commands = wrapper.findAll('[data-testid="restore-section-command"]')
    expect(commands.length).toBe(3)
    expect(commands[0].text()).toContain('--section=pre-data')
    expect(commands[1].text()).toContain('--section=data')
    expect(commands[2].text()).toContain('--section=post-data')
    // 每段都要有 --exit-on-error（失败即停的机械前提）
    for (const command of commands) expect(command.text()).toContain('--exit-on-error')
    expect(commands[0].text()).toContain('PGPASSWORD=***')
    // 段选下拉在逐段模式下没有意义
    expect(wrapper.find('[data-testid="restore-section"]').attributes('disabled')).toBeDefined()
  })

  it('逐段点开始：走的是逐段命令（不是单段），请求里带 sections:true', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    await wrapper.find('[data-testid="restore-pick-file"]').trigger('click')
    await flushPromises()
    await wrapper.find('[data-testid="restore-sections"]').setValue(true)
    await flushPromises()
    state.sectionsReport = sectionsReport({ sections: [sectionOutcome('pre-data', true), sectionOutcome('data', true), sectionOutcome('post-data', true)], failed: null, failure: null, resumeFrom: [], resumeCommand: null })
    await wrapper.find('[data-testid="restore-run"]').trigger('click')
    await flushPromises()
    expect(state.sectionsRunCalls).toBe(1)
    expect(state.runCalls).toBe(0)
    expect(state.lastRunRequest?.sections).toBe(true)
    const ok = wrapper.find('[data-testid="restore-sections-ok"]').text()
    expect(ok).toContain('shop')
    expect(ok).toContain('串行')
    const rows = wrapper.findAll('[data-testid="restore-section-row"]')
    expect(rows.length).toBe(3)
    expect(rows.map((row) => row.text()).join('|')).toContain('通过')
  })

  it('第 2 段失败：停在第 2 段、第 3 段如实说没跑，并给出续跑命令与按钮', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    await wrapper.find('[data-testid="restore-pick-file"]').trigger('click')
    await flushPromises()
    await wrapper.find('[data-testid="restore-sections"]').setValue(true)
    await flushPromises()
    await wrapper.find('[data-testid="restore-run"]').trigger('click')
    await flushPromises()

    const stopped = wrapper.find('[data-testid="restore-sections-stopped"]').text()
    expect(stopped).toContain('第 2 段')
    expect(stopped).toContain('1 段还没跑')
    // 失败那一段的原话与日志都在（不是只剩一句「失败了」）
    expect(wrapper.find('[data-testid="restore-sections-failure"]').text()).toContain('does not exist')
    expect(wrapper.find('[data-testid="restore-log"]').text()).toContain('does not exist')
    // 第三段：没跑，不是「失败」
    const rows = wrapper.findAll('[data-testid="restore-section-row"]')
    expect(rows[2].text()).toContain('没跑')
    // 能直接粘贴的续跑命令（含 --section=data 与 --exit-on-error）
    const resumeCommand = wrapper.find('[data-testid="restore-resume-command"]').text()
    expect(resumeCommand).toContain('--section=data')
    expect(resumeCommand).toContain('--exit-on-error')
    expect(wrapper.find('[data-testid="restore-resume-run"]').text()).toContain('数据')
  })

  it('点「从这一段起续跑」：第二次调用带 from=data（只补没跑完的段）', async () => {
    const wrapper = mountDialog()
    await flushPromises()
    await wrapper.find('[data-testid="restore-pick-file"]').trigger('click')
    await flushPromises()
    await wrapper.find('[data-testid="restore-sections"]').setValue(true)
    await flushPromises()
    await wrapper.find('[data-testid="restore-run"]').trigger('click')
    await flushPromises()
    expect(state.lastRunRequest?.from).toBe(null)

    // 续跑这一轮三段都过
    state.sectionsReport = sectionsReport({
      sections: [sectionOutcome('data', true), sectionOutcome('post-data', true)],
      failed: null,
      failure: null,
      resumeFrom: [],
      resumeCommand: null,
    })
    await wrapper.find('[data-testid="restore-resume-run"]').trigger('click')
    await flushPromises()
    expect(state.sectionsRunCalls).toBe(2)
    expect(state.lastRunRequest?.from).toBe('data')
    // 续跑成功后不该再留一个「续跑」按钮（它会让人以为还有活没干）
    expect(wrapper.find('[data-testid="restore-resume"]').exists()).toBe(false)
    expect(wrapper.find('[data-testid="restore-sections-ok"]').exists()).toBe(true)
  })
})
