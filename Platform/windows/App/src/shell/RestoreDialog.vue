<script setup lang="ts">
// **从备份恢复**（`FR-IO-05` 的 Windows 侧可见面）—— 封装本机 `pg_restore`。
//
// 与备份弹层同形（`BackupDialog.vue`），三条口径照抄、两条是恢复特有的：
//   · **命令行先摊出来**（恢复会改库，比备份更需要「我到底对你的库做了什么」这一眼）；
//   · **判不在界面**：源存在不存在 / 是不是 pg_restore 认的归档 / 程序在不在 / 能不能并行，
//     全由外壳判（`restore::check_source` / `find_program` / `effective_jobs`），这里只画它回的
//     `problem` 与**实际并行度**（`plan.jobs`，0 = 串行）；
//   · **失败不缩写**：退出码与子进程原话原样摆出来，日志被截断就如实说被砍了多少字符。
//   · 恢复特有①：取消是**强杀**，已写进库里的对象不会撤销 ⇒ 取消成功后仍要如实提醒；
//   · 恢复特有②：`--jobs` 只在目录归档上生效 ⇒ 控件按 `plan.kind` 禁用，并在读数里说串行。
//
// 纪律：本组件不自己拼参数、不自己判断路径 —— 那两件事在外壳，一处改一处生效。

import { computed, onUnmounted, ref, watch } from 'vue'
import { t as translate, type DictKey, type UiLanguage } from '../i18n'
import {
  restoreCancel,
  restorePlan,
  restorePlanSections,
  restoreRun,
  restoreRunSections,
  type DbFailure,
  type RestorePlanReport,
  type RestoreReport,
  type RestoreSection,
  type RestoreSectionsPlanReport,
  type RestoreSectionsReport,
  type SectionOutcome,
} from '../ipc'
import { pickFile, pickFolder } from './dialogs'

const props = defineProps<{
  open: boolean
  language: UiLanguage
  /** 当前连接的 id（口令按它取；没连库就是 null） */
  connectionId: string | null
  /** 当前连接的库名（作为「恢复到哪个库」的占位） */
  database: string
}>()

const emit = defineEmits<{
  (event: 'close'): void
}>()

function tr(key: DictKey, vars?: Record<string, string | number>): string {
  return translate(key, props.language, vars)
}

const source = ref('')
const database = ref('')
const program = ref('')
const clean = ref(false)
const section = ref<RestoreSection>('all')
const jobs = ref(0)
/** 逐段恢复（结构 → 数据 → 索引/约束，失败即停） */
const sectionsMode = ref(false)
/** 续跑从哪一段起（`null` = 从第一段）；只在逐段模式下有意义 */
const from = ref<RestoreSection | null>(null)

const plan = ref<RestorePlanReport | null>(null)
/** 逐段模式的计划（每段一条命令） */
const sectionsPlan = ref<RestoreSectionsPlanReport | null>(null)
const report = ref<RestoreReport | null>(null)
/** 逐段模式的结局（每段的账 + 停在哪 + 从哪续跑） */
const sectionsReport = ref<RestoreSectionsReport | null>(null)
const failure = ref<DbFailure | null>(null)
const planFailure = ref<DbFailure | null>(null)
const busy = ref(false)
const cancelling = ref(false)
/** 这次的结局是「你按了取消」（与失败分开措辞 —— 它不是出错，但库里可能停在半途）。 */
const cancelRequested = ref(false)
const cancelNote = ref<string | null>(null)
/** 跑着的秒数（本地实测：pg_restore 不报总量，编百分比等于骗人）。 */
const elapsedSeconds = ref(0)
let ticker: ReturnType<typeof setInterval> | null = null

const SECTION_KEYS: Record<RestoreSection, DictKey> = {
  all: 'restore.sectionAll',
  'pre-data': 'restore.sectionPreData',
  data: 'restore.sectionData',
  'post-data': 'restore.sectionPostData',
}

const noConnection = computed(() => !props.connectionId)
/** 三段恢复的依赖顺序（界面按它一行一段地排；与外壳的 `SECTION_SEQUENCE` 同序）。 */
const SECTION_ORDER: RestoreSection[] = ['pre-data', 'data', 'post-data']
/** 当前模式下的计划（单段 / 逐段各一份）——只有它决定「能不能跑」与 `--jobs` 门控。 */
const activePlan = computed(() =>
  sectionsMode.value ? sectionsPlan.value : plan.value,
)
const isDirectory = computed(() => activePlan.value?.kind === 'directory')
/** 现在能不能点「开始恢复」：选了源、没问题、不在跑。 */
const canRun = computed(() => {
  if (busy.value || noConnection.value) return false
  if (!source.value.trim()) return false
  if (!activePlan.value) return false
  return !activePlan.value.problem
})

/** 「从哪一段起续跑」的按钮文案：把段名翻成界面语言（外壳只给段键）。 */
const resumeLabel = computed(() => {
  const failed = sectionsReport.value?.failed
  return failed ? tr(SECTION_KEYS[failed]) : ''
})

/**
 * 逐段结果表：**真的跑过的段**照回执画，其余段照实说「没跑」。
 *
 * 为什么不只列跑过的：失败之后那几段不是「不存在」，而是**还没跑** —— 少画两行会让人
 * 以为恢复做完了。
 */
const sectionRows = computed(() => {
  const outcomes: SectionOutcome[] = sectionsReport.value?.sections ?? []
  const failed = sectionsReport.value?.failed ?? null
  const stoppedAt = failed ? SECTION_ORDER.indexOf(failed) : outcomes.length
  return SECTION_ORDER.map((key, index) => {
    const outcome = outcomes.find((item) => item.section === key) ?? null
    return {
      key,
      index: index + 1,
      outcome,
      notRun: outcome === null && failed !== null && index > stoppedAt,
    }
  })
})

/** 停在第几段（1 起；`0` = 没有失败）。 */
const stoppedNumber = computed(() => {
  const failed = sectionsReport.value?.failed
  return failed ? SECTION_ORDER.indexOf(failed) + 1 : 0
})
/** 失败那一段后面还剩几段没跑。 */
const remainingSections = computed(() =>
  stoppedNumber.value ? SECTION_ORDER.length - stoppedNumber.value : 0,
)
/** 失败那一段的结局（它的退出码与日志才是要摆给人看的那一份）。 */
const failedOutcome = computed<SectionOutcome | null>(() => {
  const failed = sectionsReport.value?.failed
  if (!failed) return null
  return sectionsReport.value?.sections.find((item) => item.section === failed) ?? null
})

function readable(error: unknown): DbFailure {
  const asRecord = error as { message?: string; hint?: string } | null
  return { message: asRecord?.message ?? String(error), hint: asRecord?.hint ?? '' }
}

function stopTicker(): void {
  if (ticker !== null) {
    clearInterval(ticker)
    ticker = null
  }
}

onUnmounted(stopTicker)

/** 重算计划（**只算不跑**）：命令行与它现在的可跑性都照外壳回的读数画。 */
async function refreshPlan(): Promise<void> {
  if (!props.open) return
  planFailure.value = null
  if (!source.value.trim() || noConnection.value) {
    plan.value = null
    sectionsPlan.value = null
    return
  }
  const request = {
    connectionId: props.connectionId ?? '',
    source: source.value.trim(),
    clean: clean.value,
    section: section.value,
    jobs: jobs.value,
    database: database.value.trim() || undefined,
    program: program.value.trim() || undefined,
    sections: sectionsMode.value,
    from: from.value,
  }
  try {
    if (sectionsMode.value) {
      sectionsPlan.value = await restorePlanSections(request)
      plan.value = null
    } else {
      plan.value = await restorePlan(request)
      sectionsPlan.value = null
    }
  } catch (error) {
    plan.value = null
    sectionsPlan.value = null
    planFailure.value = readable(error)
  }
}

// 任何一个开关变了都要重算：命令行是用户点「开始恢复」之前唯一能核对的东西，
// 它要是落后于界面（比如勾了「先删后建」却还显示不带 --clean 的旧串），这一眼就白给了。
watch([source, database, program, clean, section, jobs, sectionsMode, from], () => {
  void refreshPlan()
})

watch(
  () => props.open,
  (open) => {
    if (!open) {
      stopTicker()
      return
    }
    // 每次打开都是干净的一轮：**不复用上一轮的结果**（否则关掉再打开会看到一份旧日志）
    report.value = null
    sectionsReport.value = null
    failure.value = null
    planFailure.value = null
    cancelNote.value = null
    cancelRequested.value = false
    cancelling.value = false
    elapsedSeconds.value = 0
    // 续跑起点也是「这一轮」的状态：重新打开必须回到「从第一段起」
    from.value = null
    void refreshPlan()
  },
)

async function pickArchiveFile(): Promise<void> {
  const picked = await pickFile({ title: tr('restore.pickFile') })
  if (picked) source.value = picked
}

async function pickArchiveFolder(): Promise<void> {
  const picked = await pickFolder({ title: tr('restore.pickFolder') })
  if (picked) source.value = picked
}

async function run(): Promise<void> {
  if (!canRun.value) return
  busy.value = true
  report.value = null
  sectionsReport.value = null
  failure.value = null
  cancelNote.value = null
  cancelRequested.value = false
  elapsedSeconds.value = 0
  stopTicker()
  const started = Date.now()
  ticker = setInterval(() => {
    elapsedSeconds.value = Math.floor((Date.now() - started) / 1000)
  }, 500)
  const request = {
    connectionId: props.connectionId ?? '',
    source: source.value.trim(),
    clean: clean.value,
    section: section.value,
    jobs: jobs.value,
    database: database.value.trim() || undefined,
    program: program.value.trim() || undefined,
    sections: sectionsMode.value,
    from: from.value,
  }
  try {
    if (sectionsMode.value) {
      const outcome = await restoreRunSections(request)
      sectionsReport.value = outcome
      // 逐段模式下「失败」是正常结局（账在 sectionsReport 里），不走 failure 那一档；
      // 只有取消要单独说一句（库里可能停在半途）。
      if (outcome.cancelled) cancelRequested.value = true
    } else {
      report.value = await restoreRun(request)
    }
  } catch (error) {
    failure.value = readable(error)
  } finally {
    busy.value = false
    cancelling.value = false
    stopTicker()
    // 跑完把计划重算一次：`--clean` 之类没变，但「还跑不跑得动」可能变了（比如源文件被挪走）
    void refreshPlan()
  }
}

/**
 * **失败续跑**：从失败那一段起，把剩下的段补完。
 *
 * 两次调用之间只变一个量 —— `from`（续跑起点）。命令行随之重算（只剩没跑完的段），
 * 用户点之前还能再看一眼，不是「点一下黑箱往后跑」。
 */
async function resume(): Promise<void> {
  const failed = sectionsReport.value?.failed
  if (!failed) return
  from.value = failed
  await run()
}

async function cancel(): Promise<void> {
  cancelling.value = true
  cancelNote.value = null
  try {
    const accepted = await restoreCancel()
    if (accepted) {
      cancelRequested.value = true
    } else {
      cancelNote.value = tr('restore.cancelIdle')
    }
  } catch (error) {
    cancelNote.value = readable(error).message
  } finally {
    cancelling.value = false
  }
}

/** 结果行里的并行度读数：**照外壳回的实际值**说话（0 = 串行）。 */
function jobsLabel(actual: number): string {
  return actual > 1 ? tr('restore.jobsUsed', { n: actual }) : tr('restore.jobsNone')
}
</script>

<template>
  <div v-if="open" class="restore" data-testid="restore-dialog">
    <div class="restore__sheet" role="dialog" aria-modal="true" :aria-label="tr('restore.title')">
      <div class="restore__head">
        <p class="restore__title">{{ tr('restore.title') }}</p>
        <button type="button" class="restore__close" data-testid="restore-close" @click="emit('close')">
          {{ tr('restore.close') }}
        </button>
      </div>
      <p class="restore__note">{{ tr('restore.note') }}</p>

      <p v-if="noConnection" class="restore__problem" data-testid="restore-no-connection">
        {{ tr('restore.noConnection') }}
      </p>

      <template v-else>
        <!-- ① 源：手填或系统选择器（两档：单文件归档 / 目录归档） -->
        <label class="restore__field">
          <span class="restore__label">{{ tr('restore.source') }}</span>
          <span class="restore__row">
            <input
              v-model="source"
              class="restore__input"
              data-testid="restore-source"
              type="text"
              spellcheck="false"
              :placeholder="tr('restore.sourceHint')"
            />
            <button type="button" class="restore__pick" data-testid="restore-pick-file" @click="pickArchiveFile">
              {{ tr('restore.pickFile') }}
            </button>
            <button type="button" class="restore__pick" data-testid="restore-pick-folder" @click="pickArchiveFolder">
              {{ tr('restore.pickFolder') }}
            </button>
          </span>
        </label>

        <div class="restore__row">
          <label class="restore__field">
            <span class="restore__label">{{ tr('restore.database') }}</span>
            <input
              v-model="database"
              class="restore__input"
              data-testid="restore-database"
              type="text"
              spellcheck="false"
              :placeholder="props.database || tr('restore.databaseHint')"
            />
          </label>
          <label class="restore__field">
            <span class="restore__label">{{ tr('restore.program') }}</span>
            <input
              v-model="program"
              class="restore__input"
              data-testid="restore-program"
              type="text"
              spellcheck="false"
              :placeholder="tr('restore.programHint')"
            />
          </label>
        </div>

        <!-- ② 三个开关：clean / section / jobs（jobs 按源形态门控） -->
        <div class="restore__options" data-testid="restore-options">
          <p class="restore__label">{{ tr('restore.options') }}</p>
          <label class="restore__check">
            <input v-model="clean" type="checkbox" data-testid="restore-clean" />
            <span>{{ tr('restore.clean') }}</span>
          </label>
          <p class="restore__hint">{{ tr('restore.cleanHint') }}</p>
          <label class="restore__check">
            <input v-model="sectionsMode" type="checkbox" data-testid="restore-sections" />
            <span>{{ tr('restore.sections') }}</span>
          </label>
          <p class="restore__hint">{{ tr('restore.sectionsHint') }}</p>
          <label class="restore__field">
            <span class="restore__label">{{ tr('restore.section') }}</span>
            <select
              v-model="section"
              class="restore__select"
              data-testid="restore-section"
              :disabled="sectionsMode"
            >
              <option v-for="(key, value) in SECTION_KEYS" :key="value" :value="value">{{ tr(key) }}</option>
            </select>
          </label>
          <label class="restore__field">
            <span class="restore__label">{{ tr('restore.jobs') }}</span>
            <select
              v-model.number="jobs"
              class="restore__select"
              data-testid="restore-jobs"
              :disabled="activePlan !== null && !isDirectory"
            >
              <option :value="0">1</option>
              <option :value="2">2</option>
              <option :value="4">4</option>
              <option :value="8">8</option>
            </select>
            <span class="restore__hint" data-testid="restore-jobs-hint">
              {{ activePlan !== null && !isDirectory ? tr('restore.jobsSerial') : tr('restore.jobsHint') }}
            </span>
          </label>
        </div>

        <!-- ③ 计划：命令行先摊出来（口令写 ***）；问题照实摆。
             逐段模式的「先摊命令行」是**每段一条**（三行），不是一行。 -->
        <div v-if="sectionsMode && sectionsPlan" class="restore__plan" data-testid="restore-sections-plan">
          <p class="restore__label">{{ tr('restore.sectionsPreview') }}</p>
          <div v-for="(cmd, index) in sectionsPlan.commands" :key="cmd.section" class="restore__section-cmd">
            <p class="restore__label" data-testid="restore-section-command-label">
              {{ tr('restore.sectionIndex', { n: index + 1 }) }} · {{ tr(SECTION_KEYS[cmd.section]) }}
            </p>
            <code class="restore__cmd" data-testid="restore-section-command">{{ cmd.display }}</code>
          </div>
          <p v-if="sectionsPlan.program" class="restore__hint" data-testid="restore-program-found">
            {{ tr('restore.programFound', { path: sectionsPlan.program }) }}
          </p>
          <p v-else class="restore__problem" data-testid="restore-program-missing">
            {{ tr('restore.programMissing') }}
          </p>
          <p v-if="sectionsPlan.problem" class="restore__error" data-testid="restore-problem">
            {{ sectionsPlan.problem.message }}
            <span v-if="sectionsPlan.problem.hint" class="restore__hint"> — {{ sectionsPlan.problem.hint }}</span>
          </p>
        </div>
        <div v-else-if="plan" class="restore__plan" data-testid="restore-plan">
          <p class="restore__label">{{ tr('restore.preview') }}</p>
          <code class="restore__cmd" data-testid="restore-command">{{ plan.display }}</code>
          <p v-if="plan.program" class="restore__hint" data-testid="restore-program-found">
            {{ tr('restore.programFound', { path: plan.program }) }}
          </p>
          <p v-else class="restore__problem" data-testid="restore-program-missing">
            {{ tr('restore.programMissing') }}
          </p>
          <p v-if="plan.problem" class="restore__error" data-testid="restore-problem">
            {{ plan.problem.message }}
            <span v-if="plan.problem.hint" class="restore__hint"> — {{ plan.problem.hint }}</span>
          </p>
        </div>
        <p v-else-if="!source.trim()" class="restore__hint" data-testid="restore-need-path">
          {{ tr('restore.needPath') }}
        </p>
        <p v-if="planFailure" class="restore__error" data-testid="restore-plan-error">
          {{ planFailure.message }}
          <span v-if="planFailure.hint" class="restore__hint"> — {{ planFailure.hint }}</span>
        </p>

        <div class="restore__actions">
          <button type="button" class="restore__run" data-testid="restore-run" :disabled="!canRun" @click="run">
            {{ busy ? tr('restore.running') : tr('restore.run') }}
          </button>
          <button
            v-if="busy"
            type="button"
            class="restore__cancel"
            data-testid="restore-cancel-run"
            :disabled="cancelling"
            @click="cancel"
          >
            {{ cancelling ? tr('restore.cancelling') : tr('restore.cancel') }}
          </button>
        </div>
        <p v-if="cancelNote" class="restore__hint" data-testid="restore-cancel-idle">{{ cancelNote }}</p>

        <p v-if="busy" class="restore__progress" data-testid="restore-progress">
          {{ tr('restore.progress', { s: elapsedSeconds }) }}
        </p>

        <!-- ④ 跑完了：成功 / 失败两档，**都带日志尾部** -->
        <div v-if="report" class="restore__result" data-testid="restore-result">
          <p class="restore__ok" data-testid="restore-ok">
            {{
              tr('restore.ok', {
                source: report.source,
                database: report.database,
                ms: report.elapsedMs,
                jobs: jobsLabel(report.jobs),
              })
            }}
          </p>
          <p class="restore__label">{{ tr('restore.log') }}</p>
          <pre class="restore__log" data-testid="restore-log">{{ report.log || tr('restore.logEmpty') }}</pre>
          <p v-if="report.logTrimmedChars" class="restore__hint" data-testid="restore-log-trimmed">
            {{ tr('restore.logTrimmed', { n: report.logTrimmedChars }) }}
          </p>
        </div>

        <!-- ⑤ 逐段模式的结局：一行一段的账 + 停在哪 + 从哪一段起续跑 -->
        <div v-if="sectionsReport" class="restore__result" data-testid="restore-sections-result">
          <p v-if="!sectionsReport.failed" class="restore__ok" data-testid="restore-sections-ok">
            {{
              tr('restore.sectionsDone', {
                source: sectionsReport.source,
                database: sectionsReport.database,
                ms: sectionsReport.elapsedMs,
                jobs: jobsLabel(sectionsReport.jobs),
              })
            }}
          </p>
          <p v-else class="restore__error" data-testid="restore-sections-stopped">
            {{
              tr('restore.sectionsStopped', {
                n: stoppedNumber,
                label: resumeLabel,
                rest: remainingSections,
              })
            }}
          </p>

          <ul class="restore__sections" data-testid="restore-sections-rows">
            <li
              v-for="row in sectionRows"
              :key="row.key"
              class="restore__section-row"
              data-testid="restore-section-row"
            >
              <span>{{ tr('restore.sectionIndex', { n: row.index }) }} · {{ tr(SECTION_KEYS[row.key]) }}</span>
              <span v-if="row.outcome && row.outcome.ok" class="restore__ok">
                {{ tr('restore.sectionOk', { ms: row.outcome.elapsedMs }) }}
              </span>
              <span v-else-if="row.outcome && row.outcome.cancelled" class="restore__problem">
                {{ tr('restore.sectionCancelled', { ms: row.outcome.elapsedMs }) }}
              </span>
              <span v-else-if="row.outcome" class="restore__problem">
                {{ tr('restore.sectionFailed', { code: row.outcome.exitCode ?? '—' }) }}
              </span>
              <span v-else class="restore__hint">{{ tr('restore.sectionNotRun') }}</span>
            </li>
          </ul>

          <p v-if="sectionsReport.failure" class="restore__error" data-testid="restore-sections-failure">
            {{ sectionsReport.failure.message }}
            <span v-if="sectionsReport.failure.hint" class="restore__hint">
              — {{ sectionsReport.failure.hint }}
            </span>
          </p>

          <!-- 失败那一段自己的输出（含它自己的退出码）：其余段没跑，没有日志可给 -->
          <template v-if="failedOutcome">
            <p class="restore__label">{{ tr('restore.log') }}</p>
            <pre class="restore__log" data-testid="restore-log">{{
              failedOutcome.log || tr('restore.logEmpty')
            }}</pre>
            <p v-if="failedOutcome.logTrimmedChars" class="restore__hint" data-testid="restore-log-trimmed">
              {{ tr('restore.logTrimmed', { n: failedOutcome.logTrimmedChars }) }}
            </p>
          </template>

          <div v-if="sectionsReport.failed" class="restore__resume" data-testid="restore-resume">
            <p class="restore__label">{{ tr('restore.resumeCommand') }}</p>
            <code class="restore__cmd" data-testid="restore-resume-command">
              {{ sectionsReport.resumeCommand }}
            </code>
            <p class="restore__hint">{{ tr('restore.resumeNote') }}</p>
            <button
              type="button"
              class="restore__run"
              data-testid="restore-resume-run"
              :disabled="busy"
              @click="resume"
            >
              {{ tr('restore.resumeRun', { label: resumeLabel }) }}
            </button>
          </div>
        </div>

        <div v-if="failure" class="restore__failure" data-testid="restore-failure">
          <p class="restore__error" data-testid="restore-failure-message">
            {{ failure.message }}
            <span v-if="failure.hint" class="restore__hint"> — {{ failure.hint }}</span>
          </p>
          <!-- 取消的结局：强杀不会撤销已写入的对象 —— 这一句必须留在界面上 -->
          <p v-if="cancelRequested" class="restore__hint" data-testid="restore-cancelled-hint">
            {{ tr('restore.cancelledHint') }}
          </p>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
.restore {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding: var(--ds-spacing-xxl) var(--ds-spacing-l);
  background: color-mix(in srgb, var(--ds-color-surface-window) 70%, transparent);
  z-index: 40;
}

.restore__sheet {
  width: min(680px, 100%);
  max-height: 100%;
  overflow: auto;
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-m);
  padding: var(--ds-spacing-l);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-panel);
  background: var(--ds-color-surface-panel);
  color: var(--ds-color-text-primary);
  box-shadow: 0 18px 48px rgb(0 0 0 / 32%);
}

.restore__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.restore__title {
  margin: 0;
  font-size: var(--ds-font-title-size);
  font-weight: 600;
}

.restore__close,
.restore__run,
.restore__cancel,
.restore__pick {
  padding: var(--ds-spacing-xs) var(--ds-spacing-m);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: transparent;
  color: var(--ds-color-text-primary);
  cursor: pointer;
}

.restore__run:disabled,
.restore__cancel:disabled {
  cursor: default;
  color: var(--ds-color-text-secondary);
}

.restore__note,
.restore__hint {
  margin: 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.restore__field {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  flex: 1;
  min-width: 0;
}

.restore__row {
  display: flex;
  gap: var(--ds-spacing-s);
  align-items: flex-end;
  flex-wrap: wrap;
}

.restore__label {
  margin: 0;
  font-size: var(--ds-font-caption-size);
  font-weight: 600;
}

.restore__input,
.restore__select {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-window);
  color: var(--ds-color-text-primary);
  font: inherit;
  min-width: 0;
}

.restore__options {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  padding: var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
}

.restore__check {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  font-size: var(--ds-font-caption-size);
}

.restore__plan,
.restore__result,
.restore__failure {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
}

.restore__cmd,
.restore__log {
  margin: 0;
  padding: var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-window);
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-caption-size);
  white-space: pre-wrap;
  word-break: break-all;
}

.restore__log {
  max-height: 220px;
  overflow: auto;
}

.restore__section-cmd {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
}

.restore__sections {
  margin: 0;
  padding: 0;
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
}

.restore__section-row {
  display: flex;
  justify-content: space-between;
  gap: var(--ds-spacing-s);
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
}

.restore__resume {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
}

.restore__error {
  margin: 0;
  padding: var(--ds-spacing-s);
  border: 1px solid var(--ds-color-status-warning);
  border-radius: var(--ds-radius-control);
  color: var(--ds-color-text-primary);
}

.restore__problem {
  margin: 0;
  color: var(--ds-color-status-warning);
  font-size: var(--ds-font-caption-size);
}

.restore__ok {
  margin: 0;
  color: var(--ds-color-accent-accent);
}

.restore__progress {
  margin: 0;
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
}

.restore__actions {
  display: flex;
  gap: var(--ds-spacing-s);
}
</style>
