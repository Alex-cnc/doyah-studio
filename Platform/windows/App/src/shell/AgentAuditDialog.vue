<script setup lang="ts">
// **智能体审计记录**（`FR-AI-09` 的审计半）—— 每一次**外发尝试**留的一条痕。
//
// 与「生成历史」是两件事（界面也不许混成一屏）：
//   · 历史只记**成功**的那一次，回答「我以前问过什么」；
//   · 审计记**每一次尝试**，连「被闸门 / 配额挡住、一条字节都没发出去」的那几次也记，回答
//     「系统到底往外发过什么 / 为什么没发出去」。
//
// 三条口径：
//   ① **只显示、不判**：脱敏、截断、条数上限、键白名单全在领域层（`Db/src/agent_audit.rs`）；
//      本组件不再算一遍（两处各算必然分叉）。
//   ② **过网与否要一眼可分**：四档里只有「成功 / 失败」真的出网，另外两档一条请求都没发。
//   ③ **读不出来就说读不出来**：与「一条都没有」分开，不用空态掩盖故障。

import { computed, ref, watch } from 'vue'
import { t as translate, type DictKey, type UiLanguage } from '../i18n'
import { agentAuditExport, agentAuditList, type AgentAuditExport, type AgentAuditRecord } from '../ipc'
import { auditTotals, hasUsage } from './auditTotals'

const props = defineProps<{
  /** 开没开。 */
  open: boolean
  language: UiLanguage
}>()

const emit = defineEmits<{
  (event: 'close'): void
}>()

function tr(key: DictKey, vars?: Record<string, string | number>): string {
  return translate(key, props.language, vars)
}

const records = ref<AgentAuditRecord[]>([])
const failure = ref<{ message: string; hint: string } | null>(null)
const loading = ref(false)

/** 四档结局的语言键（短码由领域层给，界面不写第二套判定）。 */
const VERDICT_KEYS: Record<AgentAuditRecord['verdict'], DictKey> = {
  ok: 'audit.verdict.ok',
  failed: 'audit.verdict.failed',
  blocked: 'audit.verdict.blocked',
  throttled: 'audit.verdict.throttled',
}

function verdictLabel(verdict: AgentAuditRecord['verdict']): string {
  const key = VERDICT_KEYS[verdict]
  return key ? tr(key) : verdict
}

/** 这一次到底有没有出网（只有「成功 / 失败」过网）。 */
function leftMachine(verdict: AgentAuditRecord['verdict']): boolean {
  return verdict === 'ok' || verdict === 'failed'
}

/** 时刻的短写法（本地 `MM-DD HH:mm`；`0` = 不知道 ⇒ 空串，不编一个时间）。 */
function whenLabel(atSecs: number): string {
  if (!atSecs) return ''
  const at = new Date(atSecs * 1000)
  const pad = (value: number): string => String(value).padStart(2, '0')
  return `${pad(at.getMonth() + 1)}-${pad(at.getDate())} ${pad(at.getHours())}:${pad(at.getMinutes())}`
}

function readable(error: unknown): { message: string; hint: string } {
  const asRecord = error as { message?: string; hint?: string } | null
  return {
    message: asRecord?.message ?? String(error),
    hint: asRecord?.hint ?? '',
  }
}

async function reload(): Promise<void> {
  if (loading.value) return
  loading.value = true
  failure.value = null
  try {
    records.value = await agentAuditList()
  } catch (error) {
    failure.value = readable(error)
  } finally {
    loading.value = false
  }
}

// 每次打开都重新取一份：用户可能刚在编辑器里发过几次生成（弹层一直开着就会显示陈的读数）。
watch(
  () => props.open,
  (open) => {
    if (open) void reload()
  },
  { immediate: true },
)

const empty = computed(() => !failure.value && records.value.length === 0)

/** 一屏的汇总（求和规则在 `auditTotals.ts`，组件只画）。 */
const totals = computed(() => auditTotals(records.value))

/** 这一条记到用量没有（0 / 0 = 没记到，不是「用了 0 个」）。 */
function tokensShown(record: AgentAuditRecord): boolean {
  return hasUsage(record)
}

function tokenLabel(record: AgentAuditRecord): string {
  if (!tokensShown(record)) return tr('audit.tokens.none')
  return tr('audit.tokens', { input: record.inputTokens ?? 0, output: record.outputTokens ?? 0 })
}

/** 正在导出的格式（挡住重复点击）与上一次导出的落点。 */
const exporting = ref<'json' | 'csv' | null>(null)
const exported = ref<AgentAuditExport | null>(null)
const exportFailure = ref('')

async function exportAs(format: 'json' | 'csv'): Promise<void> {
  if (exporting.value) return
  exporting.value = format
  exported.value = null
  exportFailure.value = ''
  try {
    exported.value = await agentAuditExport(format)
  } catch (error) {
    exportFailure.value = readable(error).message
  } finally {
    exporting.value = null
  }
}
</script>

<template>
  <div
    v-if="open"
    class="audit"
    data-testid="agent-audit"
    role="dialog"
    aria-modal="true"
  >
    <div class="audit__sheet">
      <header class="audit__head">
        <h2 class="audit__title">{{ tr('audit.title') }}</h2>
        <button type="button" class="audit__close" data-testid="audit-close" @click="emit('close')">
          {{ tr('audit.close') }}
        </button>
      </header>

      <p class="audit__note" data-testid="audit-note">{{ tr('audit.note') }}</p>

      <p v-if="failure" class="audit__error" data-testid="audit-error">
        {{ failure.message
        }}<span v-if="failure.hint" class="audit__hint"> — {{ failure.hint }}</span>
      </p>

      <p v-else-if="empty" class="audit__empty" data-testid="audit-empty">{{ tr('audit.empty') }}</p>

      <ol v-else class="audit__list" data-testid="audit-list">
        <li
          v-for="(record, index) in records"
          :key="`${record.atSecs}-${index}`"
          class="audit__row"
          :class="`audit__row--${record.verdict}`"
          data-testid="audit-row"
        >
          <div class="audit__rowhead">
            <span class="audit__verdict" data-testid="audit-verdict">{{ verdictLabel(record.verdict) }}</span>
            <span class="audit__when">{{ whenLabel(record.atSecs) }}</span>
            <span class="audit__egress" data-testid="audit-egress">
              {{ leftMachine(record.verdict) ? tr('audit.egress.sent') : tr('audit.egress.notSent') }}
            </span>
          </div>
          <p class="audit__summary">{{ record.summary || tr('audit.summary.empty') }}</p>
          <p v-if="record.detail" class="audit__detail" data-testid="audit-detail">{{ record.detail }}</p>
          <p class="audit__meta">
            <span v-if="record.model">{{ tr('audit.model', { model: record.model }) }}</span>
            <span
              class="audit__tokens"
              :class="{ 'audit__tokens--none': !tokensShown(record) }"
              data-testid="audit-tokens"
            >{{ tokenLabel(record) }}</span>
            <span v-if="record.tableCount">{{ tr('audit.tables', { n: record.tableCount }) }}</span>
            <span v-if="record.durationMs">{{ tr('audit.duration', { ms: record.durationMs }) }}</span>
            <span v-if="record.endpoint" class="audit__endpoint">{{ record.endpoint }}</span>
          </p>
        </li>
      </ol>

      <footer class="audit__foot">
        <p v-if="!failure && records.length" class="audit__totals" data-testid="audit-totals">
          {{
            totals.withUsage
              ? tr('audit.totals', {
                  n: totals.records,
                  sent: totals.sent,
                  input: totals.input,
                  output: totals.output,
                })
              : tr('audit.totals.none', { n: totals.records, sent: totals.sent })
          }}
        </p>
        <div class="audit__actions">
          <button type="button" class="audit__refresh" data-testid="audit-refresh" @click="reload">
            {{ tr('audit.refresh') }}
          </button>
          <button
            type="button"
            class="audit__export"
            data-testid="audit-export-json"
            :disabled="exporting !== null || !records.length"
            @click="exportAs('json')"
          >
            {{ tr('audit.export.json') }}
          </button>
          <button
            type="button"
            class="audit__export"
            data-testid="audit-export-csv"
            :disabled="exporting !== null || !records.length"
            @click="exportAs('csv')"
          >
            {{ tr('audit.export.csv') }}
          </button>
        </div>
        <p v-if="exported" class="audit__exported" data-testid="audit-exported">
          {{
            tr('audit.export.done', {
              n: exported.entries,
              path: exported.path,
              bytes: exported.bytes,
            })
          }}
        </p>
        <p v-if="exportFailure" class="audit__exported audit__exported--bad" data-testid="audit-export-error">
          {{ tr('audit.export.failed', { message: exportFailure }) }}
        </p>
      </footer>
    </div>
  </div>
</template>

<style scoped>
.audit {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding: var(--ds-spacing-xxl) var(--ds-spacing-l);
  background: color-mix(in srgb, var(--ds-color-surface-window) 70%, transparent);
  z-index: 40;
}

.audit__sheet {
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

.audit__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.audit__title {
  margin: 0;
  font-size: var(--ds-font-title-size);
  font-weight: 600;
}

.audit__close,
.audit__refresh {
  padding: var(--ds-spacing-xs) var(--ds-spacing-m);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: transparent;
  color: var(--ds-color-text-primary);
  cursor: pointer;
}

.audit__note,
.audit__hint {
  margin: 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.audit__error {
  margin: 0;
  padding: var(--ds-spacing-s);
  border: 1px solid var(--ds-color-status-warning);
  border-radius: var(--ds-radius-control);
  color: var(--ds-color-text-primary);
}

.audit__empty {
  margin: 0;
  padding: var(--ds-spacing-l);
  color: var(--ds-color-text-secondary);
  text-align: center;
}

.audit__list {
  margin: 0;
  padding: 0;
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-s);
}

.audit__row {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  padding: var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-left: calc(var(--ds-spacing-hair) * 3) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
}

/* 过网的两档用强调色左条；没出网的两档保持中性 —— 一眼分得出「发过」与「没发」。 */
.audit__row--ok {
  border-left-color: var(--ds-color-accent-accent);
}

.audit__row--failed {
  border-left-color: var(--ds-color-status-warning);
}

.audit__rowhead {
  display: flex;
  align-items: baseline;
  gap: var(--ds-spacing-s);
}

.audit__verdict {
  font-weight: 600;
}

.audit__when,
.audit__egress,
.audit__meta {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
}

.audit__summary {
  margin: 0;
}

.audit__detail {
  margin: 0;
  color: var(--ds-color-text-secondary);
}

.audit__meta {
  margin: 0;
  display: flex;
  flex-wrap: wrap;
  gap: var(--ds-spacing-s);
}

.audit__endpoint {
  font-family: var(--ds-font-stack-mono);
}

/* token 用量（FR-AI-24）：与耗时 / 表数同档；「没记到」用弱化色，别让它看起来像 0 个。 */
.audit__tokens {
  font-variant-numeric: tabular-nums;
}

.audit__tokens--none {
  color: var(--ds-color-text-secondary);
  font-style: italic;
}

.audit__foot {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-s);
  border-top: 1px solid var(--ds-hairline);
  padding-top: var(--ds-spacing-s);
}

.audit__totals {
  margin: 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
}

.audit__actions {
  display: flex;
  justify-content: flex-end;
  gap: var(--ds-spacing-s);
}

.audit__export {
  padding: var(--ds-spacing-xs) var(--ds-spacing-m);
  border: 1px solid var(--ds-color-accent-accent);
  border-radius: var(--ds-radius-control);
  background: transparent;
  color: var(--ds-color-accent-accent);
  cursor: pointer;
}

.audit__export:disabled {
  border-color: var(--ds-hairline);
  color: var(--ds-color-text-secondary);
  cursor: not-allowed;
}

.audit__exported {
  margin: 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
  word-break: break-all;
}

.audit__exported--bad {
  color: var(--ds-color-status-warning);
}
</style>
