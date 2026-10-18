<script setup lang="ts">
// 自然语言 → SQL 的**两段式**界面（FR-AI-02）。
//
// 为什么两段（不是「输入一句就发」）：
//   ① 需求原文「生成结果**永不自动执行**」——结果是文本，先进预览、再由人点「写入编辑器」；
//   ② 「外发正文先摊给人看」——第一次点击**不发请求**（`agentGeneratePreview`），
//      把将要发送的正文逐字显示出来；第二次点击（`agentGenerateSql`）才真发。
//   ③ 正文不在前端拼：Rust 那侧装配一次，预览与实发是同一份文本（领域层单测钉住）。
// 界面只做三件事：显示、转交、把失败原话摊出来。
import { computed, ref, watch } from 'vue'
import { t as translate, type DictKey, type UiLanguage } from '../i18n'
import {
  type AgentGenerateOutcome,
  type AgentGeneratePreview,
  type AgentGateReport,
  type AgentIssue,
  type AgentQuotaStatus,
  type AgentTableBrief,
  agentGeneratePreview,
  agentGenerateSql,
} from '../ipc'

const props = defineProps<{
  /** 开没开。 */
  open: boolean
  /** 随请求外发的表摘要（已加载的那些表；空数组 = 一张也没展开过）。 */
  tables: AgentTableBrief[]
  language: UiLanguage
}>()

const emit = defineEmits<{
  (event: 'close'): void
  /** 把生成的 SQL 交给编辑器（**只写文本，不执行**）。 */
  (event: 'insert', sql: string): void
  /**
   * 把生成的 SQL 交给视图去「存成已保存查询」。
   *
   * 为什么由视图去存、而不在本弹层里调保存 IPC：保存这条路上已经有一份**唯一入口**
   * （工具栏的保存面板：同名先问覆盖、写盘后刷新列表）。弹层自己再存一遍 = 第二份判重与第二份
   * 冲突提示，两处迟早不一致。所以这里只把文本交出去，保存仍只有一条路。
   */
  (event: 'save-as', sql: string): void
}>()

function tr(key: DictKey, vars?: Record<string, string | number>): string {
  return translate(key, props.language, vars)
}

/** 每条「不放行的理由」对应的语言键（短码由领域层给）。 */
const ISSUE_KEYS: Record<AgentIssue['code'], DictKey> = {
  endpointMissing: 'agent.issue.endpointMissing',
  modelMissing: 'agent.issue.modelMissing',
  keyMissing: 'agent.issue.keyMissing',
  endpointScheme: 'agent.issue.endpointScheme',
  endpointHost: 'agent.issue.endpointHost',
  timeoutOutOfRange: 'agent.issue.timeoutOutOfRange',
  hourlyLimitOutOfRange: 'agent.issue.hourlyLimitOutOfRange',
}

function readable(error: unknown): { message: string; hint: string } {
  const shape = error as { message?: unknown; hint?: unknown }
  return {
    message: typeof shape?.message === 'string' ? shape.message : String(error),
    hint: typeof shape?.hint === 'string' ? shape.hint : '',
  }
}

const question = ref('')
const preview = ref<AgentGeneratePreview | null>(null)
const result = ref<AgentGenerateOutcome | null>(null)
const blocked = ref<AgentGateReport | null>(null)
/** 本小时配额满了被拦下（**一条请求都没发**）—— 与「闸门没放行」分开显示，用户才知道是等一等而不是去改设置。 */
const throttled = ref<AgentQuotaStatus | null>(null)
const failure = ref<{ message: string; hint: string } | null>(null)
const busy = ref<'' | 'preview' | 'generate'>('')

/** 换一个问题 / 换一次表 ⇒ 上一份预览与结果都作废（**不让旧正文冒充新的**）。 */
watch(
  () => [props.open, props.tables],
  () => {
    preview.value = null
    result.value = null
    blocked.value = null
    throttled.value = null
    failure.value = null
  },
)

const gate = computed<AgentGateReport | null>(() => blocked.value ?? preview.value?.gate ?? null)
/** 配额读数：被拦的读数 > 发完之后的读数 > 预览里的读数（都由 Rust 侧给，界面不自己算）。 */
const quota = computed<AgentQuotaStatus | null>(
  () => throttled.value ?? result.value?.quota ?? preview.value?.quota ?? null,
)
const canGenerate = computed(
  () =>
    !!preview.value &&
    preview.value.gate.state === 'ready' &&
    !busy.value &&
    (quota.value?.remaining ?? 0) > 0,
)
const questionReady = computed(() => question.value.trim().length > 0)

/** 「还要等多久」的写法：超过一分钟给分 + 秒，否则只给秒。 */
function waitLabel(secs: number): string {
  const whole = Math.max(0, Math.round(secs))
  const minutes = Math.floor(whole / 60)
  const seconds = whole % 60
  return minutes > 0
    ? tr('agent.generate.quotaWaitMin', { m: minutes, s: seconds })
    : tr('agent.generate.quotaWaitSec', { s: seconds })
}

async function showPreview(): Promise<void> {
  if (busy.value || !questionReady.value) return
  busy.value = 'preview'
  failure.value = null
  blocked.value = null
  throttled.value = null
  result.value = null
  try {
    preview.value = await agentGeneratePreview(question.value, props.tables)
  } catch (error) {
    failure.value = readable(error)
    preview.value = null
  } finally {
    busy.value = ''
  }
}

async function generate(): Promise<void> {
  if (!canGenerate.value) return
  busy.value = 'generate'
  failure.value = null
  throttled.value = null
  try {
    const reply = await agentGenerateSql(question.value, props.tables)
    if (reply.status === 'blocked') {
      blocked.value = reply.gate
      result.value = null
    } else if (reply.status === 'throttled') {
      // 本小时满了：**一条请求都没发**。读数直接取回包里那份（不自己算「还要等多久」）。
      throttled.value = reply.quota
      result.value = null
      blocked.value = null
    } else {
      result.value = {
        sql: reply.sql,
        explanation: reply.explanation,
        tablesUsed: reply.tablesUsed,
        model: reply.model,
        elapsedMs: reply.elapsedMs,
        tableCount: reply.tableCount,
        quota: reply.quota,
        limitations: reply.limitations,
      }
    }
  } catch (error) {
    failure.value = readable(error)
  } finally {
    busy.value = ''
  }
}

function insert(): void {
  if (!result.value) return
  emit('insert', result.value.sql)
}

/** 交给视图存成已保存查询（**不写编辑器、不执行** —— 视图那边走的是同一条保存入口）。 */
function saveAsQuery(): void {
  if (!result.value || !result.value.sql.trim()) return
  emit('save-as', result.value.sql)
}
</script>

<template>
  <div v-if="open" class="gen" data-testid="agent-generate" role="dialog" aria-modal="true">
    <div class="gen__sheet">
      <header class="gen__head">
        <h2 class="gen__title">{{ tr('agent.generate.title') }}</h2>
        <button type="button" class="gen__close" data-testid="generate-close" @click="emit('close')">
          {{ tr('agent.close') }}
        </button>
      </header>

      <p class="gen__hint">{{ tr('agent.generate.intro') }}</p>

      <label class="gen__label">
        <span>{{ tr('agent.generate.question') }}</span>
        <textarea
          v-model="question"
          class="gen__question"
          rows="3"
          spellcheck="false"
          data-testid="generate-question"
          :placeholder="tr('agent.generate.questionPlaceholder')"
          @keydown.esc.stop.prevent="emit('close')"
        />
      </label>

      <div class="gen__actions">
        <button
          type="button"
          class="gen__btn"
          data-testid="generate-preview"
          :disabled="!questionReady || !!busy"
          @click="showPreview"
        >
          {{ busy === 'preview' ? tr('agent.generate.previewing') : tr('agent.generate.previewButton') }}
        </button>
        <button
          type="button"
          class="gen__btn gen__btn--primary"
          data-testid="generate-send"
          :disabled="!canGenerate"
          @click="generate"
        >
          {{ busy === 'generate' ? tr('agent.generate.sending') : tr('agent.generate.sendButton') }}
        </button>
        <span class="gen__count" data-testid="generate-table-count">
          {{
            tr('agent.generate.tableCount', {
              n: preview ? preview.tableCount : props.tables.length,
            })
          }}
        </span>
      </div>

      <p v-if="failure" class="gen__error" data-testid="generate-error" role="alert">
        {{ failure.message }}<span v-if="failure.hint" class="gen__error-hint"> — {{ failure.hint }}</span>
      </p>

      <!-- 配额读数：发之前就能看到还剩几次；满了就点名还要等多久（灰按钮不解释 = 用户不知道能干什么） -->
      <p
        v-if="quota"
        class="gen__quota"
        :class="{ 'gen__quota--full': quota.remaining === 0 }"
        data-testid="generate-quota"
      >
        <template v-if="quota.remaining > 0">
          {{
            tr('agent.generate.quotaLeft', {
              used: quota.used,
              limit: quota.limit,
              remaining: quota.remaining,
            })
          }}
        </template>
        <template v-else>
          {{ tr('agent.generate.quotaFull', { limit: quota.limit, wait: waitLabel(quota.retryAfterSecs) }) }}
        </template>
      </p>

      <!-- 真发被配额拦下：说清「这次一条都没发」，与「闸门没放行」分开显示 -->
      <p v-if="throttled" class="gen__error" data-testid="generate-throttled" role="alert">
        {{
          tr('agent.generate.throttled', {
            limit: throttled.limit,
            wait: waitLabel(throttled.retryAfterSecs),
          })
        }}
      </p>

      <!-- 裁决：一句话说清「现在能不能发」；不能发就逐条点名 -->
      <p
        v-if="gate"
        class="gen__gate"
        :class="`gen__gate--${gate.state}`"
        data-testid="generate-gate"
      >
        <template v-if="gate.state === 'disabled'">{{ tr('agent.gate.disabled') }}</template>
        <template v-else-if="gate.state === 'ready'">
          {{
            tr('agent.gate.ready', {
              model: gate.model,
              scope: tr(gate.scope === 'local' ? 'agent.scope.local' : 'agent.scope.remote'),
            })
          }}
        </template>
        <template v-else>{{ tr('agent.gate.missing') }}</template>
      </p>
      <ul v-if="gate && gate.issues.length" class="gen__issues" data-testid="generate-issues">
        <li v-for="issue in gate.issues" :key="issue.code + String(issue.detail ?? '')">
          {{ tr(ISSUE_KEYS[issue.code], issue.detail === undefined ? {} : { detail: String(issue.detail) }) }}
        </li>
      </ul>

      <!-- ① 将要外发的正文（**逐字**；与实发同一份） -->
      <section v-if="preview" class="gen__section">
        <h3 class="gen__section-title">{{ tr('agent.generate.outgoing') }}</h3>
        <p class="gen__meta" data-testid="generate-url">{{ preview.url }}</p>
        <p v-if="preview.dropped > 0" class="gen__warn" data-testid="generate-dropped">
          {{ tr('agent.generate.dropped', { n: preview.dropped }) }}
        </p>
        <pre class="gen__preview" data-testid="generate-preview-text">{{ preview.human }}</pre>
      </section>

      <!-- ② 结果：只有文本，要人再点一次才进编辑器 -->
      <section v-if="result" class="gen__section">
        <h3 class="gen__section-title">{{ tr('agent.generate.result') }}</h3>
        <pre class="gen__sql" data-testid="generate-sql">{{ result.sql }}</pre>
        <p v-if="result.explanation" class="gen__explain" data-testid="generate-explanation">
          {{ result.explanation }}
        </p>
        <p class="gen__meta" data-testid="generate-tables">
          {{
            result.tablesUsed.length
              ? tr('agent.generate.tablesUsed', { tables: result.tablesUsed.join('、') })
              : tr('agent.generate.tablesNone')
          }}
        </p>
        <p class="gen__meta">{{ tr('agent.generate.stats', { model: result.model, ms: result.elapsedMs }) }}</p>
        <ul class="gen__limits" data-testid="generate-limits">
          <li v-for="line in result.limitations" :key="line">{{ line }}</li>
        </ul>
        <p class="gen__never">{{ tr('agent.generate.neverRuns') }}</p>
        <div class="gen__result-actions">
          <button type="button" class="gen__btn gen__btn--primary" data-testid="generate-insert" @click="insert">
            {{ tr('agent.generate.insert') }}
          </button>
          <!-- 第二条出路：不写编辑器、不执行，直接交给视图的保存面板（同一条保存入口） -->
          <button
            type="button"
            class="gen__btn"
            data-testid="generate-save-as-query"
            :title="tr('agent.generate.saveAsQueryTip')"
            @click="saveAsQuery"
          >
            {{ tr('agent.generate.saveAsQuery') }}
          </button>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.gen {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: var(--ds-spacing-xxl) var(--ds-spacing-l);
  background: color-mix(in srgb, var(--ds-color-surface-window) 70%, transparent);
  z-index: 40;
}

.gen__sheet {
  width: min(760px, 100%);
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
  font-size: var(--ds-font-body-size);
  box-shadow: 0 18px 48px rgb(0 0 0 / 32%);
}

.gen__head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: var(--ds-spacing-m);
}

.gen__title {
  margin: 0;
  font-size: var(--ds-font-title-size);
  font-weight: 600;
}

.gen__close,
.gen__btn {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-raised);
  color: var(--ds-color-text-primary);
  cursor: pointer;
  font-size: var(--ds-font-body-size);
}

.gen__btn--primary {
  border-color: var(--ds-color-accent-accent);
  background: var(--ds-color-accent-accent);
  color: var(--ds-color-surface-window);
  font-weight: 600;
}

.gen__btn:disabled {
  color: var(--ds-color-text-disabled);
  cursor: not-allowed;
}

.gen__hint,
.gen__meta,
.gen__never,
.gen__count {
  margin: 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.gen__label {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
}

.gen__question,
.gen__preview,
.gen__sql {
  width: 100%;
  padding: var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-mono-size);
  white-space: pre-wrap;
  word-break: break-word;
}

.gen__actions {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
  flex-wrap: wrap;
}

.gen__count {
  margin-left: auto;
}

.gen__section {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  padding-top: var(--ds-spacing-m);
  border-top: 1px solid var(--ds-hairline);
}

.gen__section-title {
  margin: 0;
  font-size: var(--ds-font-body-size);
  font-weight: 600;
}

/* 结果区的两颗按钮（写入编辑器 / 存成已保存查询）：窄窗口下换行，不挤成一条 */
.gen__result-actions {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
  flex-wrap: wrap;
}

/* 三段裁决：靠**左侧色条**区分，不新增底色（底色会与主题的层级语义打架） */
.gen__gate {
  margin: 0;
  padding: var(--ds-spacing-xs) 0 var(--ds-spacing-xs) var(--ds-spacing-s);
  border-left: 3px solid var(--ds-color-text-tertiary);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.gen__gate--missing {
  border-left-color: var(--ds-color-status-warning);
}

.gen__gate--ready {
  border-left-color: var(--ds-color-status-success);
}

.gen__issues,
.gen__limits {
  margin: 0;
  padding-left: var(--ds-spacing-l);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.gen__error {
  margin: 0;
  color: var(--ds-color-status-danger);
  font-size: var(--ds-font-caption-size);
}

.gen__error-hint {
  color: var(--ds-color-text-secondary);
}

/* 配额读数：等宽数字（同一行里的数字换行时也不跳动），满额时用警示色 */
.gen__quota {
  margin: 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
}

.gen__quota--full {
  color: var(--ds-color-status-warning);
}

.gen__warn {
  margin: 0;
  color: var(--ds-color-status-warning);
  font-size: var(--ds-font-caption-size);
}

.gen__explain {
  margin: 0;
  font-size: var(--ds-font-caption-size);
  white-space: pre-wrap;
}
</style>
