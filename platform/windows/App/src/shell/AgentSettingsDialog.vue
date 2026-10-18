<script setup lang="ts">
// 智能体设置（FR-AI-01）—— 总开关 / 端点 / 模型 / 配额 / 密钥，外加**一句实时裁决**。
//
// 三处口径都是从需求条文直接落下来的：
//   ① **总开关是第一位**：关掉时那句「不会向任何模型服务发送数据」要写在最显眼处，
//      而不是让用户从「配置齐不齐」去猜；
//   ② **密钥永不回显**：只显示「已配置 / 未配置」与存放方式（DPAPI），输入框保存后立刻清空；
//   ③ **裁决在 Rust 一处算**：`snapshot.gate` 原样显示，本组件不写第二套判断
//      （两套判定迟早分叉，用户看到「可以外发」而实际被拦最难查）。
//
// 弹层由命令面板「智能体设置…」打开（命令登记在 `shell/commands.ts`，分派在 `App.vue`）。

import { computed, ref, watch } from 'vue'
import { t as translate, type DictKey, type UiLanguage } from '../i18n'
import {
  agentKeyClear,
  agentKeySave,
  agentSettingsGet,
  agentSettingsSave,
  type AgentConfiguration,
  type AgentIssue,
  type AgentSettingsSnapshot,
} from '../ipc'
import {
  AGENT_PRESETS,
  modelChoices,
  presetById,
  presetForEndpoint,
  presetHasModelList,
} from './agentSettings'

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

const snapshot = ref<AgentSettingsSnapshot | null>(null)
const draft = ref<AgentConfiguration>({
  enabled: false,
  endpoint: '',
  model: '',
  timeoutSecs: 60,
  hourlyLimit: 60,
  preset: 'custom',
})
const keyDraft = ref('')
const busy = ref<'' | 'save' | 'key' | 'clear'>('')
const failure = ref<{ message: string; hint: string } | null>(null)
const note = ref('')

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

const models = computed(() => modelChoices(draft.value.preset, draft.value.model))
const hasModelList = computed(() => presetHasModelList(draft.value.preset))

async function load(): Promise<void> {
  failure.value = null
  note.value = ''
  try {
    const payload = await agentSettingsGet()
    snapshot.value = payload
    draft.value = { ...payload.config }
    keyDraft.value = ''
  } catch (error) {
    failure.value = readable(error)
  }
}

watch(
  () => props.open,
  (open) => {
    if (open) void load()
  },
  { immediate: true },
)

/** 异常统一读成「原话 + 出路」两段（外壳给的就是两段；旁路的抛法同形）。 */
function readable(error: unknown): { message: string; hint: string } {
  const asRecord = error as { message?: string; hint?: string } | null
  return {
    message: asRecord?.message ?? String(error),
    hint: asRecord?.hint ?? '',
  }
}

/** 换预设：端点与模型跟着预填；「自定义」不动用户已经填的东西。 */
function choosePreset(id: string): void {
  const preset = presetById(id)
  draft.value = {
    ...draft.value,
    preset: preset.id,
    endpoint: preset.endpoint || draft.value.endpoint,
    model: preset.models.length ? preset.models[0] : draft.value.model,
  }
}

/** 端点被手改 ⇒ 选中项跟着落回它真正匹配的那一条（匹配不上就 `custom`，不撒谎）。 */
function onEndpointInput(value: string): void {
  draft.value = { ...draft.value, endpoint: value, preset: presetForEndpoint(value) }
}

async function save(): Promise<void> {
  if (busy.value) return
  busy.value = 'save'
  failure.value = null
  note.value = ''
  try {
    const payload = await agentSettingsSave({
      ...draft.value,
      endpoint: draft.value.endpoint.trim(),
      model: draft.value.model.trim(),
    })
    snapshot.value = payload
    draft.value = { ...payload.config }
    note.value = tr('agent.saved')
  } catch (error) {
    failure.value = readable(error)
  } finally {
    busy.value = ''
  }
}

async function saveKey(): Promise<void> {
  if (busy.value) return
  busy.value = 'key'
  failure.value = null
  note.value = ''
  try {
    const payload = await agentKeySave(keyDraft.value)
    snapshot.value = payload
    keyDraft.value = ''
    note.value = tr('agent.key.saved')
  } catch (error) {
    failure.value = readable(error)
  } finally {
    busy.value = ''
  }
}

async function clearKey(): Promise<void> {
  if (busy.value) return
  busy.value = 'clear'
  failure.value = null
  note.value = ''
  try {
    const payload = await agentKeyClear()
    snapshot.value = payload
    keyDraft.value = ''
    note.value = tr('agent.key.cleared')
  } catch (error) {
    failure.value = readable(error)
  } finally {
    busy.value = ''
  }
}

/** 密钥存放方式的人话（`dpapi` / 其他一律如实写「本机不可用」）。 */
const storageText = computed(() =>
  snapshot.value?.keyStorage === 'dpapi' ? tr('agent.key.storage.dpapi') : tr('agent.key.storage.unavailable'),
)
</script>

<template>
  <div v-if="open" class="agent" data-testid="agent-settings" role="dialog" aria-modal="true">
    <div class="agent__sheet">
      <header class="agent__head">
        <h2 class="agent__title">{{ tr('agent.title') }}</h2>
        <button type="button" class="agent__close" data-testid="agent-close" @click="emit('close')">
          {{ tr('agent.close') }}
        </button>
      </header>

      <p v-if="failure" class="agent__error" data-testid="agent-error">
        {{ failure.message }}<span v-if="failure.hint" class="agent__hint"> — {{ failure.hint }}</span>
      </p>

      <section class="agent__section">
        <label class="agent__check">
          <input
            v-model="draft.enabled"
            type="checkbox"
            data-testid="agent-enabled"
            @change="save"
          />
          <span>{{ tr('agent.enabled') }}</span>
        </label>
        <!-- 裁决：一句话说清「现在会不会外发」 -->
        <p
          v-if="snapshot"
          class="agent__gate"
          :class="`agent__gate--${snapshot.gate.state}`"
          data-testid="agent-gate"
        >
          <template v-if="snapshot.gate.state === 'disabled'">{{ tr('agent.gate.disabled') }}</template>
          <template v-else-if="snapshot.gate.state === 'ready'">
            {{
              tr('agent.gate.ready', {
                model: snapshot.gate.model,
                scope: tr(snapshot.gate.scope === 'local' ? 'agent.scope.local' : 'agent.scope.remote'),
              })
            }}
          </template>
          <template v-else>{{ tr('agent.gate.missing') }}</template>
        </p>
        <ul v-if="snapshot && snapshot.gate.issues.length" class="agent__issues" data-testid="agent-issues">
          <li v-for="issue in snapshot.gate.issues" :key="issue.code + String(issue.detail ?? '')">
            {{ tr(ISSUE_KEYS[issue.code], issue.detail === undefined ? {} : { detail: String(issue.detail) }) }}
          </li>
        </ul>
      </section>

      <section class="agent__section">
        <label class="agent__field">
          <span>{{ tr('agent.preset') }}</span>
          <select
            :value="draft.preset"
            data-testid="agent-preset"
            @change="choosePreset(($event.target as HTMLSelectElement).value)"
          >
            <option v-for="preset in AGENT_PRESETS" :key="preset.id" :value="preset.id">
              {{ tr(preset.labelKey as DictKey) }}
            </option>
          </select>
        </label>
        <label class="agent__field">
          <span>{{ tr('agent.endpoint') }}</span>
          <input
            :value="draft.endpoint"
            data-testid="agent-endpoint"
            :placeholder="tr('agent.endpoint.placeholder')"
            @input="onEndpointInput(($event.target as HTMLInputElement).value)"
          />
        </label>
        <label class="agent__field">
          <span>{{ tr('agent.model') }}</span>
          <input
            v-model="draft.model"
            :list="hasModelList ? 'ds-agent-models' : undefined"
            data-testid="agent-model"
            :placeholder="tr('agent.model.placeholder')"
          />
          <datalist v-if="hasModelList" id="ds-agent-models">
            <option v-for="name in models" :key="name" :value="name" />
          </datalist>
        </label>
        <p v-if="!hasModelList" class="agent__hint" data-testid="agent-model-note">
          {{ tr('agent.model.manual') }}
        </p>
        <label class="agent__field agent__field--narrow">
          <span>{{ tr('agent.timeout') }}</span>
          <input v-model.number="draft.timeoutSecs" type="number" min="1" max="600" data-testid="agent-timeout" />
        </label>
        <label class="agent__field agent__field--narrow">
          <span>{{ tr('agent.hourlyLimit') }}</span>
          <input
            v-model.number="draft.hourlyLimit"
            type="number"
            min="1"
            max="100000"
            data-testid="agent-hourly"
          />
        </label>
        <button type="button" class="agent__primary" :disabled="busy !== ''" data-testid="agent-save" @click="save">
          {{ busy === 'save' ? tr('agent.saving') : tr('agent.save') }}
        </button>
        <span v-if="note" class="agent__note" data-testid="agent-note">{{ note }}</span>
      </section>

      <section class="agent__section">
        <p class="agent__label">{{ tr('agent.key') }}</p>
        <p class="agent__hint" data-testid="agent-key-state">
          {{ snapshot?.keyPresent ? tr('agent.key.present') : tr('agent.key.absent') }} ·
          {{ storageText }}
        </p>
        <p v-if="snapshot?.keyNote" class="agent__warn" data-testid="agent-key-note">{{ snapshot.keyNote }}</p>
        <div class="agent__keyrow">
          <input
            v-model="keyDraft"
            type="password"
            autocomplete="off"
            data-testid="agent-key-input"
            :placeholder="tr('agent.key.placeholder')"
          />
          <button type="button" class="agent__primary" :disabled="busy !== ''" data-testid="agent-key-save" @click="saveKey">
            {{ tr('agent.key.save') }}
          </button>
          <button
            type="button"
            class="agent__secondary"
            :disabled="busy !== '' || !snapshot?.keyPresent"
            data-testid="agent-key-clear"
            @click="clearKey"
          >
            {{ tr('agent.key.clear') }}
          </button>
        </div>
        <p class="agent__hint">{{ tr('agent.key.note') }}</p>
        <p v-if="snapshot" class="agent__path" data-testid="agent-path">{{ snapshot.configPath }}</p>
      </section>
    </div>
  </div>
</template>

<style scoped>
.agent {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding: var(--ds-spacing-xxl) var(--ds-spacing-l);
  background: color-mix(in srgb, var(--ds-color-surface-window) 70%, transparent);
  z-index: 40;
}

.agent__sheet {
  width: min(560px, 100%);
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

.agent__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.agent__title {
  margin: 0;
  font-size: var(--ds-font-title-size);
  font-weight: 600;
}

.agent__close,
.agent__secondary {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: transparent;
  color: var(--ds-color-text-secondary);
  cursor: pointer;
}

.agent__primary {
  padding: var(--ds-spacing-xs) var(--ds-spacing-m);
  border: 1px solid var(--ds-color-accent-accent);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-raised);
  color: var(--ds-color-text-primary);
  cursor: pointer;
}

.agent__primary:disabled,
.agent__secondary:disabled {
  opacity: 0.5;
  cursor: default;
}

.agent__section {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-s);
  padding-top: var(--ds-spacing-s);
  border-top: 1px solid var(--ds-hairline);
}

.agent__check {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
}

.agent__gate {
  margin: 0;
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border-radius: var(--ds-radius-control);
  font-variant-numeric: tabular-nums;
  background: var(--ds-color-surface-content);
}

.agent__gate--disabled {
  color: var(--ds-color-text-secondary);
}

.agent__gate--missing {
  color: var(--ds-color-accent-warm);
}

.agent__gate--ready {
  color: var(--ds-color-accent-teal);
}

.agent__issues {
  margin: 0;
  padding-left: var(--ds-spacing-l);
  color: var(--ds-color-accent-warm);
  font-size: var(--ds-font-caption-size);
}

.agent__field {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
}

.agent__field > span {
  width: 96px;
  flex: none;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.agent__field input,
.agent__field select,
.agent__keyrow input {
  flex: 1;
  min-width: 0;
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: 1px solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  font-family: var(--ds-font-stack-mono);
}

.agent__field--narrow input {
  max-width: 120px;
}

.agent__keyrow {
  display: flex;
  gap: var(--ds-spacing-s);
}

.agent__hint {
  margin: 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}

.agent__warn {
  margin: 0;
  color: var(--ds-color-accent-warm);
  font-size: var(--ds-font-caption-size);
}

.agent__error {
  margin: 0;
  padding: var(--ds-spacing-s) var(--ds-spacing-s);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-accent-warm);
  font-size: var(--ds-font-caption-size);
}

.agent__path {
  margin: 0;
  color: var(--ds-color-text-secondary);
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-mono-small-size);
  word-break: break-all;
}

.agent__note {
  color: var(--ds-color-accent-teal);
  font-size: var(--ds-font-caption-size);
}

.agent__label {
  margin: 0;
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-secondary);
}
</style>
