<script setup lang="ts">
// **备份数据库**（`FR-IO-04` 的 Windows 侧可见面）—— 封装本机 `pg_dump`。
//
// 四档结局，**每一档都要看得见**（空态不许掩盖故障，这是本仓踩过的老坑）：
//   ① 没连库      —— 备份的对象是「当前连接」，没连就说没连；
//   ② 程序找不到  —— 说清自动找过哪儿、让人要么装客户端要么手填路径；
//   ③ 跑起来了    —— 成功（字节 / 耗时 / 路径）或失败（退出码 + pg_dump 原话的尾部）；
//   ④ 还没填路径  —— 不报错，只提示「填了就给你看命令行」。
//
// 三条口径：
//   · **命令行先摊出来**（需求原文「展示实际命令行」）：`PGPASSWORD=***` 那一段让用户一眼知道
//     口令是怎么给的 —— 它不在 argv 里；
//   · **判不在界面**：路径能不能用、程序在不在、格式对不对全由外壳判（`backup::check_target` /
//     `backup::find_program`），这里只画它回的 `problem`；
//   · **失败不缩写**：退出码与子进程原话原样摆出来，日志被截断就如实说被砍了多少字符。

import { computed, onUnmounted, ref, watch } from 'vue'
import { t as translate, type DictKey, type UiLanguage } from '../i18n'
import {
  backupCancel,
  backupPlan,
  backupProgress,
  backupRun,
  type BackupFormat,
  type BackupPlanReport,
  type BackupProgress,
  type BackupReport,
  type DbFailure,
} from '../ipc'

const props = defineProps<{
  open: boolean
  language: UiLanguage
  /** 当前连接的 id（口令按它取；没连库就是 null） */
  connectionId: string | null
  /** 当前连接的库名（作为「备份哪个库」的占位） */
  database: string
}>()

const emit = defineEmits<{
  (event: 'close'): void
}>()

function tr(key: DictKey, vars?: Record<string, string | number>): string {
  return translate(key, props.language, vars)
}

const path = ref('')
const format = ref<BackupFormat>('custom')
const program = ref('')
const databaseOverride = ref('')

const plan = ref<BackupPlanReport | null>(null)
const report = ref<BackupReport | null>(null)
const failure = ref<DbFailure | null>(null)
const busy = ref(false)
/** 取消请求已经发出去、还没看到结局（键在这个窗口里不许再点第二次）。 */
const cancelling = ref(false)
/** 这次的结局是「你按了取消」（与失败分开措辞 —— 它不是出错）。 */
const cancelled = ref(false)
/** 取消键按下去却没人可取消 / IPC 出错时的如实说明。 */
const cancelNote = ref<string | null>(null)
/** 计划自己的失败（连接没开 / 命令没起）—— 与「跑备份失败」分开摆，不然用户分不清是哪一步。 */
const planFailure = ref<DbFailure | null>(null)
/** 跑着的读数（每 500ms 问外壳一次）：已写字节 / 已跑毫秒 / 子进程最近一行。 */
const progress = ref<BackupProgress | null>(null)
/** 轮询句柄（跑完 / 关弹层 / 卸载都要停 —— 停不掉就会在后台一直 invoke）。 */
let pollTimer: ReturnType<typeof setInterval> | null = null

const FORMAT_KEYS: Record<BackupFormat, DictKey> = {
  plain: 'backup.format.plain',
  custom: 'backup.format.custom',
  directory: 'backup.format.directory',
}

const noConnection = computed(() => !props.connectionId)

/** 现在能不能点「开始备份」：有计划、没问题、不在跑、也不是「还没填路径」。 */
const canRun = computed(() => {
  if (busy.value || noConnection.value) return false
  if (!path.value.trim()) return false
  if (!plan.value) return false
  return !plan.value.problem
})

function readable(error: unknown): DbFailure {
  const asRecord = error as { message?: string; hint?: string } | null
  return { message: asRecord?.message ?? String(error), hint: asRecord?.hint ?? '' }
}

/** 停掉轮询（跑完 / 关弹层 / 卸载都要调 —— 漏一处就会在后台一直问外壳）。 */
function stopPolling(): void {
  if (pollTimer !== null) {
    clearInterval(pollTimer)
    pollTimer = null
  }
}

/** 问一次读数；**失败不打断备份**（读数只是显示，别让一次 IPC 抖动把备份弹层变成报错）。 */
async function readProgress(): Promise<void> {
  try {
    progress.value = await backupProgress()
  } catch {
    // 读数读不到就不更新 —— 界面继续显示上一份，不假装「已写 0」
  }
}

/** 开跑：立刻问一次（别让用户先盯着空白 500ms），之后每 500ms 一次。 */
function startPolling(): void {
  stopPolling()
  progress.value = null
  void readProgress()
  pollTimer = setInterval(() => {
    void readProgress()
  }, 500)
}

onUnmounted(stopPolling)

/**
 * 跑着的那一行读数的措辞：**没起量就如实说没起量**（不写「0 B / 0%」，
 * 那会被读成「卡住了」；也说不出「还剩多久」—— `pg_dump` 不告诉我们总量）。
 */
const progressLine = computed(() => {
  const snap = progress.value
  if (!snap) return tr('backup.progressStarting')
  const seconds = Math.max(1, Math.round(snap.elapsedMs / 1000))
  if (snap.bytes === 0) return tr('backup.progressWaiting', { s: seconds })
  return tr('backup.progress', {
    bytes: bytesLabel(snap.bytes),
    s: seconds,
    lines: snap.lines,
  })
})

/** 重算命令行（**不起进程**）。路径空 ⇒ 清掉计划，改成「填了就显示」。 */
async function refreshPlan(): Promise<void> {
  planFailure.value = null
  if (noConnection.value || !path.value.trim()) {
    plan.value = null
    return
  }
  try {
    plan.value = await backupPlan({
      connectionId: props.connectionId as string,
      path: path.value.trim(),
      format: format.value,
      database: databaseOverride.value.trim() || undefined,
      program: program.value.trim() || undefined,
    })
  } catch (error) {
    plan.value = null
    planFailure.value = readable(error)
  }
}

async function run(): Promise<void> {
  if (!canRun.value) return
  busy.value = true
  cancelling.value = false
  cancelled.value = false
  cancelNote.value = null
  failure.value = null
  report.value = null
  startPolling()
  try {
    report.value = await backupRun({
      connectionId: props.connectionId as string,
      path: path.value.trim(),
      format: format.value,
      database: databaseOverride.value.trim() || undefined,
      program: program.value.trim() || undefined,
    })
  } catch (error) {
    failure.value = readable(error)
    // 「你按了取消」与「备份出错」是两件事：前者不该用报错的口气讲
    cancelled.value = failure.value.message.includes('已取消')
  } finally {
    busy.value = false
    cancelling.value = false
    // 跑完：读数退场（不让上一轮的数字留在弹层上），轮询停掉
    stopPolling()
    progress.value = null
    // 跑完重算一次：目标现在多半已存在，命令行区应当如实变成「不覆盖既有文件」那一档
    void refreshPlan()
  }
}

/**
 * **取消**：请外壳终止 `pg_dump` 子进程（强杀），半截产物由外壳删掉。
 *
 * 这里只发请求、不自己收拾战场 —— 界面不清文件、不判成败，与「判不在界面」同一条口径。
 */
async function cancel(): Promise<void> {
  if (!busy.value || cancelling.value) return
  cancelling.value = true
  cancelNote.value = null
  try {
    const accepted = await backupCancel()
    // 没有备份在跑就别装作取消了：如实说，并放开键（用户可能刚跑完）
    if (!accepted) {
      cancelling.value = false
      cancelNote.value = tr('backup.cancelIdle')
    }
  } catch (error) {
    cancelling.value = false
    cancelNote.value = readable(error).message
  }
}

function bytesLabel(bytes: number): string {
  if (bytes < 1024) return String(bytes)
  const units = ['KB', 'MB', 'GB', 'TB']
  let value = bytes / 1024
  let unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit += 1
  }
  return `${value.toFixed(1)} ${units[unit]}`
}

/** 每次打开都重置成一份「新的一次备份」：上次的路径留着（同一个库常连着备），结果清掉。 */
watch(
  () => props.open,
  (open) => {
    if (!open) return
    report.value = null
    failure.value = null
    planFailure.value = null
    cancelNote.value = null
    cancelled.value = false
    cancelling.value = false
    progress.value = null
    stopPolling()
    databaseOverride.value = ''
    void refreshPlan()
  },
  { immediate: true },
)
</script>

<template>
  <div v-if="open" class="backup" data-testid="backup-dialog" role="dialog" aria-modal="true">
    <div class="backup__sheet">
      <header class="backup__head">
        <h2 class="backup__title">{{ tr('backup.title') }}</h2>
        <button type="button" class="backup__close" data-testid="backup-close" @click="emit('close')">
          {{ tr('backup.close') }}
        </button>
      </header>

      <p class="backup__note">{{ tr('backup.note') }}</p>

      <!-- ① 没连库：说清对象是谁，而不是让「开始备份」灰着不给理由 -->
      <p v-if="noConnection" class="backup__error" data-testid="backup-no-connection">
        {{ tr('backup.noConnection') }}
      </p>

      <template v-else>
        <label class="backup__field">
          <span class="backup__label">{{ tr('backup.path') }}</span>
          <input
            v-model="path"
            class="backup__input"
            data-testid="backup-path"
            type="text"
            :placeholder="tr('backup.pathHint')"
            @change="refreshPlan"
          />
        </label>

        <div class="backup__row">
          <label class="backup__field backup__field--half">
            <span class="backup__label">{{ tr('backup.format') }}</span>
            <select v-model="format" class="backup__input" data-testid="backup-format" @change="refreshPlan">
              <option v-for="(key, value) in FORMAT_KEYS" :key="value" :value="value">
                {{ tr(key) }}
              </option>
            </select>
          </label>
          <label class="backup__field backup__field--half">
            <span class="backup__label">{{ tr('backup.database') }}</span>
            <input
              v-model="databaseOverride"
              class="backup__input"
              data-testid="backup-database"
              type="text"
              :placeholder="database || tr('backup.databaseHint')"
              @change="refreshPlan"
            />
          </label>
        </div>

        <label class="backup__field">
          <span class="backup__label">{{ tr('backup.program') }}</span>
          <input
            v-model="program"
            class="backup__input"
            data-testid="backup-program"
            type="text"
            :placeholder="tr('backup.programHint')"
            @change="refreshPlan"
          />
        </label>

        <!-- 计划区：命令行先摊出来（口令写 ***）；问题照实摆 -->
        <div v-if="plan" class="backup__plan" data-testid="backup-plan">
          <p class="backup__label">{{ tr('backup.preview') }}</p>
          <code class="backup__cmd" data-testid="backup-command">{{ plan.display }}</code>
          <p v-if="plan.program" class="backup__hint" data-testid="backup-program-found">
            {{ tr('backup.programFound', { path: plan.program }) }}
          </p>
          <p v-else class="backup__problem" data-testid="backup-program-missing">
            {{ tr('backup.programMissing') }}
          </p>
          <p v-if="plan.problem" class="backup__error" data-testid="backup-problem">
            {{ plan.problem.message }}
            <span v-if="plan.problem.hint" class="backup__hint"> — {{ plan.problem.hint }}</span>
          </p>
        </div>
        <p v-else-if="!path.trim()" class="backup__hint" data-testid="backup-need-path">
          {{ tr('backup.needPath') }}
        </p>
        <p v-if="planFailure" class="backup__error" data-testid="backup-plan-error">
          {{ planFailure.message }}
          <span v-if="planFailure.hint" class="backup__hint"> — {{ planFailure.hint }}</span>
        </p>

        <div class="backup__actions">
          <button
            type="button"
            class="backup__run"
            data-testid="backup-run"
            :disabled="!canRun"
            @click="run"
          >
            {{ busy ? tr('backup.running') : tr('backup.run') }}
          </button>
          <!-- 跑着才露出来：大库跑起来之后唯一的出路就是这里 -->
          <button
            v-if="busy"
            type="button"
            class="backup__cancel"
            data-testid="backup-cancel"
            :disabled="cancelling"
            @click="cancel"
          >
            {{ cancelling ? tr('backup.cancelling') : tr('backup.cancel') }}
          </button>
        </div>
        <p v-if="cancelNote" class="backup__hint" data-testid="backup-cancel-idle">
          {{ cancelNote }}
        </p>

        <!-- 跑着的时候：已写多少 / 跑了多久 / 子进程最近一行（都是实测读数，没有百分比） -->
        <div v-if="busy" class="backup__progress" data-testid="backup-progress">
          <p class="backup__progress-line" data-testid="backup-progress-line">
            {{ progressLine }}
          </p>
          <p v-if="progress && progress.lastLine" class="backup__hint" data-testid="backup-progress-last">
            {{ tr('backup.progressLast', { line: progress.lastLine }) }}
          </p>
        </div>

        <!-- ③ 跑完了：成功 / 失败两档，**都带日志尾部** -->
        <div v-if="report" class="backup__result" data-testid="backup-result">
          <p class="backup__ok" data-testid="backup-ok">
            {{
              tr('backup.ok', {
                bytes: bytesLabel(report.bytes),
                path: report.target,
                ms: report.elapsedMs,
              })
            }}
          </p>
          <p class="backup__label">{{ tr('backup.log') }}</p>
          <pre class="backup__log" data-testid="backup-log">{{ report.log || tr('backup.logEmpty') }}</pre>
          <p v-if="report.logTrimmedChars" class="backup__hint" data-testid="backup-log-trimmed">
            {{ tr('backup.logTrimmed', { n: report.logTrimmedChars }) }}
          </p>
        </div>

        <div v-if="failure" class="backup__failure" data-testid="backup-failure">
          <p class="backup__error" data-testid="backup-failure-message">
            {{ failure.message }}
            <span v-if="failure.hint" class="backup__hint"> — {{ failure.hint }}</span>
          </p>
          <!-- 取消的结局：说明这是强杀 + 半截产物已清（别把盘上旧文件当成这一份） -->
          <p v-if="cancelled" class="backup__hint" data-testid="backup-cancelled-hint">
            {{ tr('backup.cancelledHint') }}
          </p>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
.backup {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding: var(--ds-spacing-xxl) var(--ds-spacing-l);
  background: color-mix(in srgb, var(--ds-color-surface-window) 70%, transparent);
  z-index: 40;
}

.backup__sheet {
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

.backup__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.backup__title {
  margin: 0;
  font-size: var(--ds-font-title-size);
  font-weight: 600;
}

.backup__close,
.backup__run,
.backup__cancel {
  padding: var(--ds-spacing-xs) var(--ds-spacing-m);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: transparent;
  color: var(--ds-color-text-primary);
  cursor: pointer;
}

.backup__run:disabled,
.backup__cancel:disabled {
  cursor: default;
  color: var(--ds-color-text-secondary);
}

.backup__note,
.backup__hint {
  margin: 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.backup__field {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  flex: 1;
}

.backup__row {
  display: flex;
  gap: var(--ds-spacing-s);
}

.backup__label {
  margin: 0;
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-secondary);
}

.backup__input {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-window);
  color: var(--ds-color-text-primary);
  font: inherit;
}

.backup__cmd {
  display: block;
  padding: var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-window);
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-caption-size);
  overflow-wrap: anywhere;
}

.backup__error {
  margin: 0;
  padding: var(--ds-spacing-s);
  border: 1px solid var(--ds-color-status-warning);
  border-radius: var(--ds-radius-control);
  color: var(--ds-color-text-primary);
}

.backup__problem {
  margin: 0;
  color: var(--ds-color-status-warning);
  font-size: var(--ds-font-caption-size);
}

.backup__ok {
  margin: 0;
  color: var(--ds-color-accent-accent);
}

/* 跑着的读数：等宽数字（字节与秒数会跳动，比例字体下会左右抖） */
.backup__progress {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  padding: var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-window);
}

.backup__progress-line {
  margin: 0;
  color: var(--ds-color-accent-accent);
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
}

.backup__log {
  margin: 0;
  max-height: 240px;
  overflow: auto;
  padding: var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-window);
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-caption-size);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
</style>
