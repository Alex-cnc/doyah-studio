<!--
  Schema 对比与同步（FR-DDL-04）的**界面差异视图**。

  三条口径（都在界面上写清，不让用户猜）：
  ① **快照对快照**：两侧各自「抓当前结构」，所以两个库不在同一次会话里也能比
     （先抓左侧存着，去改库，再抓右侧对比）。
  ② **方向固定**：左 = 想要的结构，右 = 要被改的结构。标题下面那句话就是这么写的。
  ③ **删除默认关**：勾着关时删表 / 删列只**列出**、不生成语句，并把每一条跳过写出来；
     生成物只给复制 / 到编辑器打开，**面板里没有执行按钮**（与表设计器同一条动线）。
-->
<template>
  <section class="db__io schema" data-testid="schema-diff">
    <p class="db__browse-title">
      {{ t('schema.title') }}
      <button class="db__btn db__btn--icon" type="button" :title="t('schema.close')" data-testid="schema-close" @click="emit('close')">
        <ActionIcon name="close" />
      </button>
    </p>
    <p class="db__note">{{ t('schema.baseHint') }}</p>

    <div class="schema__slots">
      <div class="schema__slot" data-testid="schema-slot-base">
        <span class="schema__slot-name">{{ t('schema.base') }}</span>
        <button class="db__btn" type="button" data-testid="schema-capture-base" :disabled="busy" @click="capture('base')">
          {{ t('schema.capture') }}
        </button>
        <span class="db__note" data-testid="schema-base-state">{{ slotLine(base, t) }}</span>
      </div>
      <div class="schema__slot" data-testid="schema-slot-target">
        <span class="schema__slot-name">{{ t('schema.target') }}</span>
        <button class="db__btn" type="button" data-testid="schema-capture-target" :disabled="busy" @click="capture('target')">
          {{ t('schema.capture') }}
        </button>
        <span class="db__note" data-testid="schema-target-state">{{ slotLine(target, t) }}</span>
      </div>
    </div>

    <div class="db__writeback">
      <label class="db__freeze">
        <input v-model="schemaName" type="text" class="db__select" data-testid="schema-name" :aria-label="t('schema.schemaName')" />
        <span class="db__kind">{{ t('schema.schemaName') }}</span>
      </label>
      <label class="db__freeze">
        <input v-model="allowDrop" type="checkbox" data-testid="schema-allow-drop" @change="rerun" />
        {{ t('schema.allowDrop') }}
      </label>
      <span class="db__note">{{ t('schema.allowDropNote') }}</span>
    </div>

    <div class="db__writeback">
      <button class="db__btn" type="button" data-testid="schema-compare" :disabled="busy || !base || !target" @click="rerun">
        {{ t('schema.compare') }}
      </button>
      <button class="db__btn" type="button" data-testid="schema-copy" :disabled="!script" @click="copyScript">
        {{ t('schema.copy') }}
      </button>
      <button class="db__btn" type="button" data-testid="schema-open" :disabled="!script" @click="emit('open-sql', script)">
        {{ t('schema.openInEditor') }}
      </button>
      <span v-if="busy" class="db__note" data-testid="schema-busy">{{ t('schema.busy') }}</span>
      <span v-if="note" class="db__note" data-testid="schema-note">{{ note }}</span>
    </div>

    <p v-if="error" class="db__params-error" role="alert" data-testid="schema-error">{{ error }}</p>

    <p v-if="report && report.tableDiffs.length === 0 && report.skipped.length === 0" class="db__note" data-testid="schema-in-sync">
      {{ t('schema.inSync') }}
    </p>

    <details v-if="report && report.tableDiffs.length" open data-testid="schema-diffs">
      <summary class="db__note">{{ t('schema.diffTitle', { n: report.tableDiffs.length }) }}</summary>
      <ul class="db__dml-list">
        <li v-for="d in report.tableDiffs" :key="d.table" :data-testid="`schema-diff-${d.table}`">
          <code>{{ d.table }}</code>
          <span class="db__kind">{{ t(STATUS_KEYS[d.status]) }}</span>
          <span v-if="columnSummary(d, t)" class="db__note">{{ columnSummary(d, t) }}</span>
        </li>
      </ul>
    </details>

    <details v-if="report && report.skipped.length" open data-testid="schema-skipped">
      <summary class="db__note">{{ t('schema.skippedTitle', { n: report.skipped.length }) }}</summary>
      <ul class="db__dml-list">
        <li v-for="(s, i) in report.skipped" :key="`${s.table}-${i}`" :data-testid="`schema-skip-${i}`">
          <code>{{ s.table }}</code>
          <span class="db__kind">{{ s.what }}</span>
          <span class="db__note">{{ s.reason }}</span>
        </li>
      </ul>
    </details>

    <details v-if="report && report.statements.length" open data-testid="schema-statements">
      <summary class="db__note">
        {{ t('schema.statementTitle', { n: report.statements.length, m: report.destructiveCount }) }}
      </summary>
      <pre class="schema__sql" data-testid="schema-script">{{ script }}</pre>
    </details>
  </section>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import ActionIcon from './ActionIcon.vue'
import { t as translate, type DictKey, type UiLanguage } from '../i18n'
import {
  schemaDiffPlan as ipcSchemaDiffPlan,
  schemaSnapshot as ipcSchemaSnapshot,
  type DbFailure,
  type SchemaDiffReport,
  type SchemaSnapshot,
} from '../ipc'
import { STATUS_KEYS, columnSummary, slotLine, statementScript } from './schemaDiff'

const props = defineProps<{ language: UiLanguage }>()
const emit = defineEmits<{
  (event: 'close'): void
  (event: 'open-sql', sql: string): void
}>()

/** 语言表查询（语言是 prop ⇒ 切语言时面板跟着换，不读一次性全局）。 */
const t = (key: DictKey, vars?: Record<string, string | number>): string =>
  translate(key, props.language, vars)

const base = ref<SchemaSnapshot | null>(null)
const target = ref<SchemaSnapshot | null>(null)
const report = ref<SchemaDiffReport | null>(null)
const schemaName = ref('public')
const allowDrop = ref(false)
const busy = ref(false)
const error = ref('')
const note = ref('')

const script = computed(() => statementScript(report.value))

/** 失败原话（服务端 / 旁路给的那两句），不吞成一句「失败」。 */
function failureText(e: unknown): string {
  const failure = e as DbFailure | undefined
  if (failure && typeof failure.message === 'string') {
    return failure.hint ? `${failure.message} —— ${failure.hint}` : failure.message
  }
  return e instanceof Error ? e.message : String(e)
}

/**
 * 抓一侧的快照。两侧都到手时**顺手对比一次** —— 用户抓完第二侧就要看差异，
 * 不该还要求他再点一次「对比」。
 */
async function capture(side: 'base' | 'target'): Promise<void> {
  busy.value = true
  error.value = ''
  note.value = ''
  try {
    const label = side === 'base' ? t('schema.base') : t('schema.target')
    const snapshot = await ipcSchemaSnapshot(schemaName.value.trim() || 'public', label)
    if (side === 'base') base.value = snapshot
    else target.value = snapshot
    if (base.value && target.value) await compare()
  } catch (e) {
    error.value = failureText(e)
  } finally {
    busy.value = false
  }
}

/** 重新对比（已抓到两侧时；否则明说还缺哪一步，不静默什么都不做）。 */
async function rerun(): Promise<void> {
  if (!base.value || !target.value) {
    note.value = t('schema.needBoth')
    return
  }
  await compare()
}

async function compare(): Promise<void> {
  if (!base.value || !target.value) return
  busy.value = true
  error.value = ''
  note.value = ''
  try {
    report.value = await ipcSchemaDiffPlan(base.value, target.value, allowDrop.value)
  } catch (e) {
    error.value = failureText(e)
    report.value = null
  } finally {
    busy.value = false
  }
}

async function copyScript(): Promise<void> {
  if (!script.value || !report.value) return
  try {
    await navigator.clipboard.writeText(script.value)
    note.value = t('schema.copyDone', { n: report.value.statements.length })
  } catch {
    note.value = t('schema.copyFailed')
  }
  setTimeout(() => (note.value = ''), 2500)
}
</script>

<style scoped>
.schema__slots {
  display: flex;
  gap: var(--ds-spacing-s);
  flex-wrap: wrap;
  margin: var(--ds-spacing-xs) 0;
}

.schema__slot {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
}

.schema__slot-name {
  color: var(--ds-color-text-primary);
  font-size: var(--ds-font-body-size);
}

.schema__sql {
  max-height: var(--ds-metric-plan-raw-max-height);
  overflow: auto;
  margin: var(--ds-spacing-xs) 0 0;
  padding: var(--ds-spacing-xs);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-mono-small-size);
  white-space: pre-wrap;
}
</style>
