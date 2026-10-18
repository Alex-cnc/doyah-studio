<!--
  对话页签（`FR-AI-25` 第一片）—— 挂在**工作区页签条**上，占编辑区，不是侧栏。

  这一版做到的（每一件都能在界面上看见）：
  ① 一整段对话（多轮）原样发给已配端点，回复直接出现在消息流里；
  ② 三种「没发出去」都说得清：总开关关着 / 本小时满额 / 请求失败 —— 各自给可读原因与下一步；
  ③ 用量读数：这一问是第几问、共几条消息、用了哪个模型、往返多少毫秒、尝试了几次；
  ④ **按工作区落盘**：同一工作区关掉页签 / 重开应用会读回来（`FR-AI-17`），换工作区互不可见；
      没打开工作区时如实说「这次不会存」；
  ⑤ **不执行**：模型给的语句只是正文，本组件没有任何执行入口。

  这一版**没有**做的（如实写在面板底部「已知限制」里，由 Rust 回包带过来）：
  流式逐段渲染 / 工具调用卡片 / 内联审批。
-->
<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import {
  agentChatLoad,
  agentChatSave,
  agentChatSend,
  type AgentChatTurn,
  type AgentGateReport,
  type AgentIssue,
} from '../ipc'
import { t as translate, type DictKey, type UiLanguage } from '../i18n'
import { CHAT_MAX_TURNS, budgetOf, outgoingTurns, questionCount, withReply } from './chatThread'

const props = defineProps<{
  /** 界面语言（由工作区视图传下来）。 */
  language?: UiLanguage
  /**
   * 这个对话页签绑哪个工作区（`FR-AI-17`）：有值 ⇒ 打开时读回、每问一句落盘；
   * 空 ⇒ **不落盘**（界面如实说，不假装存了）。
   */
  workspace?: string
}>()

function tr(key: DictKey, vars?: Record<string, string | number>): string {
  return translate(key, props.language ?? 'zh-Hans', vars)
}

const ISSUE_KEYS: Record<AgentIssue['code'], DictKey> = {
  endpointMissing: 'agent.issue.endpointMissing',
  modelMissing: 'agent.issue.modelMissing',
  keyMissing: 'agent.issue.keyMissing',
  endpointScheme: 'agent.issue.endpointScheme',
  endpointHost: 'agent.issue.endpointHost',
  timeoutOutOfRange: 'agent.issue.timeoutOutOfRange',
  hourlyLimitOutOfRange: 'agent.issue.hourlyLimitOutOfRange',
}

/** 消息流（用户 / 模型交替；**只在成功时**追加模型那一条）。 */
const turns = ref<AgentChatTurn[]>([])
const draft = ref('')
const sending = ref(false)
const failure = ref<{ message: string; hint: string } | null>(null)
const gate = ref<AgentGateReport | null>(null)
const throttled = ref<{ used: number; limit: number; retryAfterSecs: number } | null>(null)
const limitations = ref<string[]>([])
/** 最近一次成功那一发的读数（模型 / 耗时 / 尝试次数 / 条数）。 */
const info = ref<{ model: string; elapsedMs: number; attempts: number; turns: number } | null>(null)
const thread = ref<HTMLElement | null>(null)

/** 这段对话落在哪个文件（空 = 还没读到 / 没打开工作区）。 */
const sessionPath = ref('')
/** 读回来时交代的话（坏文件 / 属于别的工作区 / 跳过了几条）。 */
const sessionNotes = ref<string[]>([])
/** 读回了几条（只在刚打开时显示一行，之后清掉 —— 它说明的是「读回来了」这件事）。 */
const restored = ref(0)
/** 上一次落盘失败的可读原因（空 = 没失败）。 */
const saveFailure = ref<string | null>(null)
/** 上一次落盘裁掉 / 截断了什么（有才显示）。 */
const trimmed = ref<{ kept: number; dropped: number; clipped: number } | null>(null)

const workspaceId = computed(() => (props.workspace ?? '').trim())
const budget = computed(() => budgetOf(turns.value, draft.value))
const canSend = computed(() => !sending.value && draft.value.trim().length > 0)

function readable(error: unknown): { message: string; hint: string } {
  const asFailure = error as { message?: string; hint?: string } | null
  return {
    message: asFailure?.message ?? String(error),
    hint: asFailure?.hint ?? '',
  }
}

async function scrollToEnd() {
  await nextTick()
  const node = thread.value
  if (node) node.scrollTop = node.scrollHeight
}

/**
 * 把这段对话落盘（`FR-AI-17`）。**没打开工作区就什么都不做**（界面那行会如实说不会存）。
 *
 * 失败要**说出来**并留在界面上：静默失败等于「用户以为存了，关掉就没了」。
 */
async function persist(next: AgentChatTurn[]) {
  const workspace = workspaceId.value
  if (!workspace) return
  try {
    const saved = await agentChatSave(workspace, next)
    sessionPath.value = saved.path
    saveFailure.value = null
    restored.value = 0
    trimmed.value =
      saved.dropped > 0 || saved.clipped > 0
        ? { kept: saved.messages, dropped: saved.dropped, clipped: saved.clipped }
        : null
  } catch (error) {
    saveFailure.value = readable(error).message
  }
}

/** 打开时（以及换工作区时）读回这个工作区上一次的对话（`FR-AI-17`）。 */
async function reload() {
  const workspace = workspaceId.value
  turns.value = []
  sessionNotes.value = []
  restored.value = 0
  trimmed.value = null
  saveFailure.value = null
  sessionPath.value = ''
  if (!workspace) return
  try {
    const session = await agentChatLoad(workspace)
    turns.value = session.messages
    sessionPath.value = session.path
    sessionNotes.value = session.notes
    restored.value = session.messages.length
    await scrollToEnd()
  } catch (error) {
    // 读不出来不该让对话不可用：当空对话开始，但要说清为什么（不静默）。
    const why = readable(error)
    sessionNotes.value = [why.hint ? `${why.message} ${why.hint}` : why.message]
  }
}

onMounted(reload)
// 换工作区 ⇒ 换一段对话：不重读的话，旧工作区的消息会被写进新工作区那份文件里。
watch(workspaceId, () => {
  void reload()
})

async function send() {
  failure.value = null
  gate.value = null
  throttled.value = null
  const outgoing = outgoingTurns(turns.value, draft.value, (over) =>
    tr('chat.tooLong', {
      turns: over.turns,
      chars: over.chars,
      limitTurns: over.limitTurns,
      limitChars: over.limitChars,
    }),
  )
  if (!outgoing.ok) {
    failure.value = { message: outgoing.problem, hint: tr('chat.tooLongHint') }
    return
  }
  const asked = outgoing.turns
  turns.value = asked
  draft.value = ''
  sending.value = true
  await scrollToEnd()
  try {
    const reply = await agentChatSend(asked)
    if (reply.status === 'blocked') {
      gate.value = reply.gate
      // 没发出去 ⇒ 这一问留在消息流里（用户不用重敲），但没有模型回复。
      limitations.value = []
      return
    }
    if (reply.status === 'throttled') {
      throttled.value = {
        used: reply.quota.used,
        limit: reply.quota.limit,
        retryAfterSecs: reply.quota.retryAfterSecs,
      }
      return
    }
    turns.value = withReply(asked, reply.text)
    limitations.value = reply.limitations
    info.value = {
      model: reply.model,
      elapsedMs: reply.elapsedMs,
      attempts: reply.attempts.length,
      turns: reply.turns,
    }
    // 只在这一问**真拿到回复之后**落盘：没发出去的那一问答不进历史，
    // 落盘也不该替它编一条（否则重开时会看到一段「模型答过」的假历史）。
    await persist(turns.value)
    await scrollToEnd()
  } catch (error) {
    // 失败也**把这句问题留在流里**：重发时用户只按一次，不用重新敲。
    failure.value = readable(error)
  } finally {
    sending.value = false
  }
}

function clear() {
  turns.value = []
  draft.value = ''
  failure.value = null
  gate.value = null
  throttled.value = null
  info.value = null
  limitations.value = []
  trimmed.value = null
  // 清空也要落盘：否则重开页签会把刚清掉的对话又读回来（「点了清空却说没清」）。
  void persist([])
}
</script>

<template>
  <section class="chat" data-testid="chat-panel">
    <header class="chat__head">
      <h3 class="chat__title">{{ tr('chat.title') }}</h3>
      <span class="chat__budget" data-testid="chat-budget">
        {{ tr('chat.budget', {
          turns: budget.turns,
          chars: budget.chars,
          limitTurns: budget.limitTurns,
          limitChars: budget.limitChars,
        }) }}
      </span>
      <button class="chat__act" type="button" :disabled="turns.length === 0 && !draft" data-testid="chat-clear" @click="clear">
        {{ tr('chat.clear') }}
      </button>
    </header>

    <div ref="thread" class="chat__thread" data-testid="chat-thread">
      <p v-if="turns.length === 0" class="chat__empty">{{ tr('chat.empty') }}</p>
      <article
        v-for="(turn, index) in turns"
        :key="index"
        class="chat__turn"
        :class="turn.role === 'user' ? 'chat__turn--user' : 'chat__turn--model'"
      >
        <p class="chat__who">{{ turn.role === 'user' ? tr('chat.you') : tr('chat.model') }}</p>
        <pre class="chat__body">{{ turn.content }}</pre>
      </article>
      <p v-if="sending" class="chat__waiting" data-testid="chat-sending">{{ tr('chat.sending') }}</p>
    </div>

    <!-- 三种「没发出去」各说各的（外形分开，用户一眼能分清该改什么） -->
    <div v-if="gate" class="chat__stale" role="alert" data-testid="chat-blocked">
      <p class="chat__stale-msg">{{ tr('chat.blocked') }}</p>
      <ul v-if="gate.issues.length" class="chat__issues">
        <li v-for="issue in gate.issues" :key="issue.code + String(issue.detail ?? '')">
          {{ tr(ISSUE_KEYS[issue.code], issue.detail === undefined ? {} : { detail: String(issue.detail) }) }}
        </li>
      </ul>
    </div>
    <div v-if="throttled" class="chat__stale" role="alert" data-testid="chat-throttled">
      <p class="chat__stale-msg">
        {{ tr('chat.throttled', {
          used: throttled.used,
          limit: throttled.limit,
          minutes: Math.ceil(throttled.retryAfterSecs / 60),
        }) }}
      </p>
    </div>
    <div v-if="failure" class="chat__stale" role="alert" data-testid="chat-failure">
      <p class="chat__stale-msg">{{ failure.message }}</p>
      <p v-if="failure.hint" class="chat__stale-hint">{{ failure.hint }}</p>
    </div>

    <footer class="chat__foot">
      <!-- 会话落在哪儿（`FR-AI-17`）：没打开工作区就如实说不会存，不假装存了 -->
      <p v-if="!workspaceId" class="chat__session" data-testid="chat-session-off">{{ tr('chat.sessionOff') }}</p>
      <p v-else-if="sessionPath" class="chat__session" data-testid="chat-session">
        {{ tr('chat.session', { path: sessionPath }) }}
        <span v-if="restored" class="chat__restored" data-testid="chat-restored">
          {{ tr('chat.loaded', { n: restored, q: questionCount(turns) }) }}
        </span>
      </p>
      <ul v-if="sessionNotes.length" class="chat__session-notes" data-testid="chat-session-notes">
        <li v-for="line in sessionNotes" :key="line">{{ line }}</li>
      </ul>
      <p v-if="saveFailure" class="chat__session-bad" data-testid="chat-save-failed">
        {{ tr('chat.saveFailed', { reason: saveFailure }) }}
      </p>
      <p v-if="trimmed" class="chat__session-notes" data-testid="chat-trimmed">
        {{ tr('chat.saveTrimmed', {
          kept: trimmed.kept,
          dropped: trimmed.dropped,
          clipped: trimmed.clipped,
          limit: CHAT_MAX_TURNS,
        }) }}
      </p>
      <textarea
        v-model="draft"
        class="chat__draft"
        data-testid="chat-draft"
        :placeholder="tr('chat.placeholder')"
        rows="3"
        @keydown.enter.exact.prevent="canSend && send()"
      />
      <div class="chat__actions">
        <button class="chat__send" type="button" :disabled="!canSend" data-testid="chat-send" @click="send">
          {{ sending ? tr('chat.sending') : tr('chat.send') }}
        </button>
        <span class="chat__hint">{{ tr('chat.hint') }}</span>
      </div>
      <p v-if="info" class="chat__info" data-testid="chat-info">
        {{ tr('chat.answered', {
          model: info.model,
          ms: info.elapsedMs,
          n: questionCount(turns),
          turns: info.turns,
        }) }}
        <span v-if="info.attempts > 1" class="chat__attempts" data-testid="chat-attempts">
          {{ tr('chat.attempts', { n: info.attempts }) }}
        </span>
      </p>
      <ul v-if="limitations.length" class="chat__limits" data-testid="chat-limits">
        <li v-for="line in limitations" :key="line">{{ line }}</li>
      </ul>
    </footer>
  </section>
</template>

<style scoped>
/* 全部走设计令牌（`tokens.generated.css`）：裸值会被 `tools/token-ratchet.mjs` 当场判红 */
.chat {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  padding: var(--ds-spacing-s) var(--ds-spacing-m);
  gap: var(--ds-spacing-s);
  font-family: var(--ds-font-stack);
}
.chat__head {
  display: flex;
  align-items: baseline;
  gap: var(--ds-spacing-s);
}
.chat__title {
  margin: 0;
  font-size: var(--ds-font-body-size);
}
.chat__budget {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
}
.chat__act {
  margin-left: auto;
  background: none;
  border: var(--ds-metric-hairline) solid var(--ds-color-hairline-light);
  border-radius: var(--ds-radius-control);
  color: inherit;
  cursor: pointer;
  font-size: var(--ds-font-caption-size);
  padding: var(--ds-spacing-hair) var(--ds-spacing-s);
}
.chat__thread {
  flex: 1;
  min-height: 0;
  overflow: auto;
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-s);
  border: var(--ds-metric-hairline) solid var(--ds-color-hairline-light);
  border-radius: var(--ds-radius-card);
  padding: var(--ds-spacing-s);
}
.chat__empty {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
  margin: 0;
}
.chat__turn {
  border-radius: var(--ds-radius-card);
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  max-width: 86%;
}
.chat__turn--user {
  align-self: flex-end;
  background: var(--ds-color-surface-raised);
}
.chat__turn--model {
  align-self: flex-start;
  background: var(--ds-color-surface-panel);
}
.chat__who {
  margin: 0 0 var(--ds-spacing-hair);
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-tertiary);
}
.chat__body {
  margin: 0;
  font-family: inherit;
  font-size: var(--ds-font-body-size);
  line-height: 1.55;
  white-space: pre-wrap;
  word-break: break-word;
}
.chat__waiting {
  margin: 0;
  font-size: var(--ds-font-caption-size);
  color: var(--ds-color-text-secondary);
}
.chat__stale {
  border: var(--ds-metric-hairline) solid var(--ds-color-status-warning);
  border-radius: var(--ds-radius-card);
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  font-size: var(--ds-font-caption-size);
}
.chat__stale-msg,
.chat__stale-hint {
  margin: 0;
}
.chat__stale-hint {
  color: var(--ds-color-text-secondary);
}
.chat__issues {
  margin: var(--ds-spacing-xs) 0 0;
  padding-left: var(--ds-spacing-m);
}
.chat__foot {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
}
.chat__draft {
  width: 100%;
  resize: vertical;
  background: var(--ds-color-surface-content);
  border: var(--ds-metric-hairline) solid var(--ds-color-hairline-light);
  border-radius: var(--ds-radius-card);
  color: inherit;
  font: inherit;
  font-size: var(--ds-font-body-size);
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
}
.chat__actions {
  display: flex;
  align-items: center;
  gap: var(--ds-spacing-s);
}
.chat__send {
  background: var(--ds-color-accent-accent);
  border: none;
  border-radius: var(--ds-radius-control);
  color: var(--ds-color-text-bright);
  cursor: pointer;
  font-size: var(--ds-font-body-size);
  padding: var(--ds-spacing-hair) var(--ds-spacing-m);
}
.chat__send:disabled {
  cursor: default;
  opacity: 0.5;
}
.chat__hint,
.chat__info {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
  margin: 0;
}
.chat__attempts {
  margin-left: var(--ds-spacing-xs);
  color: var(--ds-color-status-warning);
}
.chat__limits {
  margin: 0;
  padding-left: var(--ds-spacing-m);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}
/* 会话存放位置 / 读回的交代 / 存盘失败（`FR-AI-17`）：一行说明，不抢正文的位置 */
.chat__session,
.chat__session-notes,
.chat__session-bad {
  margin: 0;
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
  word-break: break-all;
}
.chat__session-notes {
  padding-left: var(--ds-spacing-m);
}
.chat__session-bad {
  color: var(--ds-color-status-warning);
}
.chat__restored {
  margin-left: var(--ds-spacing-xs);
  color: var(--ds-color-accent-accent);
}
</style>
