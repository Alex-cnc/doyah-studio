<script setup lang="ts">
// **对话式诊断**（`FR-AI-03`）—— 两条路都能走，由用户选：
//   ① **问模型**：把这一整份资料块按「设置」里的端点真发一次，回来的正文直接填进回复框并解读；
//   ② **自己粘**：把资料块拷去任意聊天窗口问，再把回复粘回来解读（本机没有端点时这条路照样能用）。
//
// 三条口径（与领域/表示层的分工一致）：
//   ① **取数只用既有命令**：执行计划走 `explainStatement`（EXPLAIN，不加 ANALYZE），
//      慢查询走 `slowQueries`（版本感知 + 扩展缺失给可读三步），锁与表统计走通用 `dbQuery`。
//   ② **判断全在 `workspace/agentDiagnosis.ts`**：证据三态、资料块拼法、回复解析、拒绝理由都在那里，
//      本组件只显示 —— 两处各判一次必然分叉。**发出去的正文也由 Rust 装配**（屏幕上这份 + 一段固定纪律），
//      界面不自己拼提示词（否则「看到的」与「发出去的」不是一件事）。
//   ③ **建议只放进编辑器**：能不能执行由既有 `statementRisk` 判并显示，本组件不执行任何 SQL。

import { computed, ref, watch } from 'vue'
import { t as translate, type DictKey, type UiLanguage } from '../i18n'
import {
  agentDiagnosisAsk,
  dbQuery,
  explainStatement,
  slowQueries,
  statementRisk,
  type AgentGateReport,
  type AgentIssue,
  type DbFailure,
} from '../ipc'
import {
  buildBrief,
  evidenceFromPlan,
  evidenceFromRows,
  evidenceFromSlowReport,
  evidencePlan,
  evidenceUnavailable,
  parseAdvice,
  slowEvidenceSql,
  type AcceptedAdvice,
  type AdviceParseResult,
  type EvidenceItem,
  type EvidenceSpec,
} from '../workspace/agentDiagnosis'

const props = defineProps<{
  /** 开没开。 */
  open: boolean
  language: UiLanguage
  /** 要诊断的那句 SQL（由数据库视图把编辑器内容传下来）。 */
  sql: string
}>()

const emit = defineEmits<{
  (event: 'close'): void
  /** 把建议的 SQL 放进编辑器（**只放文本、不执行**）。 */
  (event: 'insert', sql: string): void
}>()

function tr(key: DictKey, vars?: Record<string, string | number>): string {
  return translate(key, props.language, vars)
}

const items = ref<EvidenceItem[]>([])
const gathering = ref(false)
const gatherError = ref('')
const reply = ref('')
const parsed = ref<AdviceParseResult | null>(null)
const copyNote = ref('')
/** 每条建议的风险判定（`safe` / `confirm` / `forbidden`），按 SQL 文本索引。 */
const riskBySql = ref<Record<string, string>>({})

/** 问模型那一路的状态（与「自己粘」互不干扰：问失败也不该清掉用户已经粘进来的字）。 */
const asking = ref(false)
const askNote = ref('')
const askError = ref('')
const askGate = ref<AgentGateReport | null>(null)
const askLimitations = ref<string[]>([])

const ISSUE_KEYS: Record<AgentIssue['code'], DictKey> = {
  endpointMissing: 'agent.issue.endpointMissing',
  modelMissing: 'agent.issue.modelMissing',
  keyMissing: 'agent.issue.keyMissing',
  endpointScheme: 'agent.issue.endpointScheme',
  endpointHost: 'agent.issue.endpointHost',
  timeoutOutOfRange: 'agent.issue.timeoutOutOfRange',
  hourlyLimitOutOfRange: 'agent.issue.hourlyLimitOutOfRange',
}

const brief = computed(() => buildBrief(items.value, (spec: EvidenceSpec) => tr(spec.titleKey)))

function titleOf(item: EvidenceItem): string {
  return tr(item.titleKey)
}

function statusLabel(item: EvidenceItem): string {
  if (item.status === 'rows') return tr('diag.status.rows', { n: item.rows.length })
  if (item.status === 'empty') return tr('diag.status.empty')
  return tr('diag.status.unavailable')
}

function readable(error: unknown): string {
  const asFailure = error as DbFailure | null
  return asFailure?.message ?? String(error)
}

/** 取证据：四份按编号顺序取，**每份单独兜错**（一份没取到不该让整面板空着）。 */
async function gather(): Promise<void> {
  const plan = evidencePlan(props.sql)
  gathering.value = true
  gatherError.value = ''
  parsed.value = null
  reply.value = ''
  copyNote.value = ''
  riskBySql.value = {}
  askNote.value = ''
  askError.value = ''
  askGate.value = null
  askLimitations.value = []
  const collected: EvidenceItem[] = []
  try {
    for (const spec of plan) {
      try {
        if (spec.kind === 'plan') {
          const text = await explainStatement(props.sql)
          collected.push(evidenceFromPlan(spec, text))
        } else if (spec.kind === 'slow') {
          const report = await slowQueries('total', 10)
          const evidence = evidenceFromSlowReport(spec, report)
          if (report.available) {
            evidence.sql = slowEvidenceSql(report.totalColumn, report.meanColumn)
          }
          collected.push(evidence)
        } else {
          const result = await dbQuery(spec.sql)
          collected.push(evidenceFromRows(spec, result.columns, result.rows, result.truncated))
        }
      } catch (error) {
        collected.push(evidenceUnavailable(spec, readable(error)))
      }
    }
    items.value = collected
  } catch (error) {
    gatherError.value = readable(error)
  } finally {
    gathering.value = false
  }
}

// 每次打开都重取：用户可能刚改过语句（面板一直开着就会显示上一次的证据）。
watch(
  () => props.open,
  (open) => {
    if (open) void gather()
  },
  { immediate: true },
)

async function copyBrief(): Promise<void> {
  copyNote.value = ''
  try {
    const clipboard = navigator.clipboard
    if (!clipboard || typeof clipboard.writeText !== 'function') throw new Error('no clipboard api')
    await clipboard.writeText(brief.value.text)
    copyNote.value = tr('diag.copied')
  } catch (error) {
    copyNote.value = tr('diag.copyFailed', { reason: readable(error) })
  }
}

/**
 * **问模型**（`FR-AI-03` 第二片）：把面板上这份资料块原样发出去，回来的正文填进回复框并直接解读。
 *
 * 三种「没拿到回复」的处境都要在界面上说清：闸门不放行（逐条列缺什么）/ 本小时满额（还要等多久）/
 * 请求失败（可读原因）。**只有真拿到正文才动回复框** —— 挡住时不该把用户已粘进来的字清掉。
 */
async function askModel(): Promise<void> {
  askNote.value = ''
  askError.value = ''
  askGate.value = null
  askLimitations.value = []
  if (!brief.value.text.trim()) {
    askError.value = tr('diag.ask.needsBrief')
    return
  }
  asking.value = true
  try {
    const answer = await agentDiagnosisAsk(brief.value.text)
    if (answer.status === 'blocked') {
      askGate.value = answer.gate
      askNote.value = tr('diag.ask.blocked')
      return
    }
    if (answer.status === 'throttled') {
      askNote.value = tr('diag.ask.throttled', {
        minutes: Math.max(1, Math.ceil(answer.quota.retryAfterSecs / 60)),
      })
      return
    }
    reply.value = answer.text
    askLimitations.value = answer.limitations
    askNote.value = tr('diag.ask.answered', { model: answer.model, ms: answer.elapsedMs })
    await readReply()
  } catch (error) {
    askError.value = tr('diag.ask.failed', { reason: readable(error) })
  } finally {
    asking.value = false
  }
}

/** 解读回复：解析在纯函数里，风险判定问既有命令（每句一次，结果留着显示）。 */
async function readReply(): Promise<void> {
  const result = parseAdvice(reply.value, items.value)
  const risks: Record<string, string> = {}
  for (const advice of result.accepted) {
    if (advice.kind !== 'suggestion') continue
    if (risks[advice.text]) continue
    try {
      risks[advice.text] = await statementRisk(advice.text)
    } catch {
      // 判不出来就**不显示判定**（不编一个「安全」出来）
      risks[advice.text] = ''
    }
  }
  riskBySql.value = risks
  parsed.value = result
}

function riskLabel(advice: AcceptedAdvice): string {
  const risk = riskBySql.value[advice.text] ?? ''
  if (risk === 'safe') return tr('diag.risk.safe')
  if (risk === 'confirm') return tr('diag.risk.confirm')
  if (risk === 'forbidden') return tr('diag.risk.forbidden')
  return ''
}

function rejectReason(reason: AdviceParseResult['rejected'][number]['reason']): string {
  return tr(`diag.reject.${reason}` as DictKey)
}
</script>

<template>
  <div v-if="props.open" class="diag" data-testid="diagnosis-panel">
    <header class="diag__head">
      <h2 class="diag__title">{{ tr('diag.title') }}</h2>
      <button class="diag__close" type="button" data-testid="diagnosis-close" @click="emit('close')">
        {{ tr('diag.close') }}
      </button>
    </header>
    <p class="diag__intro">{{ tr('diag.intro') }}</p>

    <p v-if="gathering" class="diag__note" data-testid="diagnosis-gathering">{{ tr('diag.gathering') }}</p>
    <p v-else-if="gatherError" class="diag__error" data-testid="diagnosis-error">
      {{ tr('diag.gatherFailed', { message: gatherError }) }}
    </p>

    <section class="diag__evidence" data-testid="diagnosis-evidence">
      <article
        v-for="item in items"
        :key="item.id"
        class="diag__item"
        :class="`diag__item--${item.status}`"
      >
        <div class="diag__item-head">
          <span class="diag__item-id">{{ item.id }}</span>
          <span class="diag__item-title">{{ titleOf(item) }}</span>
          <span class="diag__item-status" :data-status="item.status">{{ statusLabel(item) }}</span>
        </div>
        <p v-if="item.status === 'unavailable'" class="diag__reason" :data-reason="item.id">
          {{ item.reason }}
        </p>
        <table v-else-if="item.rows.length" class="diag__rows">
          <thead v-if="item.columns.length">
            <tr>
              <th v-for="column in item.columns" :key="column">{{ column }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(row, i) in item.rows.slice(0, 5)" :key="`${item.id}:${i}`">
              <td v-for="(cell, j) in row" :key="j">{{ cell }}</td>
            </tr>
          </tbody>
        </table>
        <p class="diag__sql-label">{{ tr('diag.evidenceSql') }}</p>
        <pre class="diag__sql">{{ item.sql }}</pre>
      </article>
    </section>

    <section class="diag__brief">
      <label class="diag__label" for="diag-brief">{{ tr('diag.briefLabel') }}</label>
      <textarea id="diag-brief" class="diag__brief-text" readonly data-testid="diagnosis-brief" :value="brief.text" />
      <div class="diag__brief-actions">
        <button class="diag__btn" type="button" data-testid="diagnosis-copy" @click="copyBrief">
          {{ tr('diag.copy') }}
        </button>
        <button
          class="diag__btn diag__btn--primary"
          type="button"
          data-testid="diagnosis-ask"
          :disabled="asking"
          @click="askModel"
        >
          {{ tr('diag.ask') }}
        </button>
        <span v-if="copyNote" class="diag__note" data-testid="diagnosis-copy-note">{{ copyNote }}</span>
      </div>
      <p class="diag__tip" data-testid="diagnosis-ask-tip">{{ tr('diag.ask.tip') }}</p>
      <p v-if="asking" class="diag__note" data-testid="diagnosis-asking">{{ tr('diag.ask.working') }}</p>
      <p v-else-if="askNote" class="diag__note" data-testid="diagnosis-ask-note">{{ askNote }}</p>
      <p v-if="askError" class="diag__error" data-testid="diagnosis-ask-error">{{ askError }}</p>
      <ul v-if="askGate && askGate.issues.length" class="diag__issues" data-testid="diagnosis-ask-issues">
        <li v-for="issue in askGate.issues" :key="issue.code + String(issue.detail ?? '')">
          {{ tr(ISSUE_KEYS[issue.code], issue.detail === undefined ? {} : { detail: String(issue.detail) }) }}
        </li>
      </ul>
      <ul v-if="askLimitations.length" class="diag__limits" data-testid="diagnosis-ask-limits">
        <li v-for="(line, i) in askLimitations" :key="`l:${i}`">{{ line }}</li>
      </ul>
    </section>

    <section class="diag__reply">
      <label class="diag__label" for="diag-reply">{{ tr('diag.replyLabel') }}</label>
      <p class="diag__tip">{{ tr('diag.replyTip') }}</p>
      <textarea
        id="diag-reply"
        v-model="reply"
        class="diag__reply-text"
        data-testid="diagnosis-reply"
        spellcheck="false"
        rows="6"
      />
      <button class="diag__btn diag__btn--primary" type="button" data-testid="diagnosis-parse" @click="readReply">
        {{ tr('diag.parse') }}
      </button>
    </section>

    <section class="diag__parsed" data-testid="diagnosis-parsed">
      <p v-if="!parsed" class="diag__note">{{ tr('diag.noReply') }}</p>
      <template v-else>
        <p class="diag__counts">
          <span data-testid="diagnosis-accepted-count">{{ tr('diag.acceptedCount', { n: parsed.accepted.length }) }}</span>
          ·
          <span data-testid="diagnosis-rejected-count">{{ tr('diag.rejectedCount', { n: parsed.rejected.length }) }}</span>
          <template v-if="parsed.unrecognized.length">
            ·
            <span data-testid="diagnosis-unrecognized-count">{{
              tr('diag.unrecognizedCount', { n: parsed.unrecognized.length })
            }}</span>
          </template>
        </p>
        <ul class="diag__accepted">
          <li v-for="(advice, i) in parsed.accepted" :key="`a:${i}`" :data-kind="advice.kind">
            <template v-if="advice.kind === 'conclusion'">
              <span class="diag__tag">{{ tr('diag.citations') }}: {{ advice.citations.join(', ') }}</span>
              <span class="diag__text">{{ advice.text }}</span>
            </template>
            <template v-else>
              <span class="diag__tag">{{ tr('diag.suggestionFor', { n: advice.forConclusion ?? 0 }) }}</span>
              <code class="diag__sql-inline">{{ advice.text }}</code>
              <span v-if="riskLabel(advice)" class="diag__risk">{{ riskLabel(advice) }}</span>
              <button
                class="diag__btn"
                type="button"
                data-testid="diagnosis-insert"
                @click="emit('insert', advice.text)"
              >
                {{ tr('diag.insert') }}
              </button>
            </template>
          </li>
        </ul>
        <ul v-if="parsed.rejected.length" class="diag__rejected">
          <li v-for="(row, i) in parsed.rejected" :key="`r:${i}`" :data-reason="row.reason">
            {{ rejectReason(row.reason) }} — {{ row.detail }}
          </li>
        </ul>
        <ul v-if="parsed.unrecognized.length" class="diag__unrecognized">
          <li v-for="(line, i) in parsed.unrecognized" :key="`u:${i}`">{{ line }}</li>
        </ul>
      </template>
    </section>
  </div>
</template>

<style scoped>
.diag {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-m);
  padding: var(--ds-spacing-m);
  overflow: auto;
  height: 100%;
  color: var(--ds-color-text-primary);
  background: var(--ds-color-surface-panel);
}
.diag__head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: var(--ds-spacing-s);
}
.diag__title {
  font-size: var(--ds-font-title-size);
  font-weight: 600;
}
.diag__intro,
.diag__tip,
.diag__note {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}
.diag__error {
  color: var(--ds-color-status-danger);
  font-size: var(--ds-font-caption-size);
}
.diag__evidence {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-s);
}
.diag__item {
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  padding: var(--ds-spacing-s);
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
}
.diag__item--unavailable {
  border-color: var(--ds-color-status-danger);
}
.diag__item-head {
  display: flex;
  align-items: baseline;
  gap: var(--ds-spacing-s);
}
.diag__item-id {
  font-family: var(--ds-font-stack-mono);
  color: var(--ds-color-text-tertiary);
}
.diag__item-title {
  font-weight: 600;
}
.diag__item-status {
  margin-left: auto;
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-secondary);
}
.diag__item-status[data-status='unavailable'] {
  color: var(--ds-color-status-danger);
}
.diag__reason {
  color: var(--ds-color-status-danger);
  font-size: var(--ds-font-caption-size);
}
.diag__rows {
  border-collapse: collapse;
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-caption-size);
}
.diag__rows th,
.diag__rows td {
  border: 1px solid var(--ds-hairline);
  padding: var(--ds-spacing-hair) var(--ds-spacing-xs);
  text-align: left;
}
.diag__sql-label {
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-tertiary);
}
.diag__sql {
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-caption-size);
  white-space: pre-wrap;
  color: var(--ds-color-text-secondary);
}
.diag__label {
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-secondary);
}
.diag__brief-text,
.diag__reply-text {
  width: 100%;
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-caption-size);
  background: var(--ds-color-surface-window);
  color: var(--ds-color-text-primary);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  padding: var(--ds-spacing-xs);
}
.diag__brief-text {
  min-height: 9rem;
}
.diag__brief-actions {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
}
.diag__btn {
  align-self: flex-start;
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-window);
  color: var(--ds-color-text-primary);
  padding: var(--ds-spacing-hair) var(--ds-spacing-s);
  cursor: pointer;
}
.diag__btn--primary {
  border-color: var(--ds-color-accent-accent);
  color: var(--ds-color-accent-accent);
}
.diag__counts {
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-secondary);
}
.diag__accepted,
.diag__rejected,
.diag__unrecognized {
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
}
.diag__tag {
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-tertiary);
  margin-right: var(--ds-spacing-s);
}
.diag__risk {
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-secondary);
  margin: 0 var(--ds-spacing-s);
}
.diag__sql-inline {
  font-family: var(--ds-font-stack-mono);
}
.diag__rejected li {
  color: var(--ds-color-status-danger);
  font-size: var(--ds-font-caption-size);
}
.diag__unrecognized li {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}
.diag__issues,
.diag__limits {
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  font-size: var(--ds-font-caption-size);
}
.diag__issues li {
  color: var(--ds-color-status-danger);
}
.diag__limits li {
  color: var(--ds-color-text-tertiary);
}
</style>
