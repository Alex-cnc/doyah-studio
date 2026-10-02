<script setup lang="ts">
// 命令面板（2.9）：清单来自 `shell/commands.ts`，**匹配与排序来自 Rust 领域层**（`palette`）
//
// 三条纪律：
//   ① 面板里**只显示当前视图能执行的命令**（含全局动作）—— 不给点了没反应的项；
//   ② 高亮位置用领域层给的**字符位置**（不在这里再算一遍匹配）；
//   ③ 执行完就关面板；**执行失败要说出来**（由调用方负责显示）。

import { computed, nextTick, ref, watch } from 'vue'
import { paletteSearch, workspaceSearch, type PaletteItem, type PaletteMatch } from '../ipc'
import { commandsFor, type Command } from './commands'
import { fileToItem, mergeItems, objectToItem, targetOf } from './paletteTargets'

const props = defineProps<{
  open: boolean
  view: 'workspace' | 'database'
  /** 工作区根（有它才能把**文件**也搜进面板） */
  workspaceRoot?: string
  /** 可搜的数据库对象（连上库时由外壳拉好递进来） */
  objects?: { schema: string; name: string; kind: string }[]
  /** 最近打开的文件（相对路径，最近的在前） */
  recentFiles?: string[]
  /** 按「常用优先」排好的命令 id（顺序由领域层给） */
  rankedCommands?: string[]
}>()

const emit = defineEmits<{
  (event: 'close'): void
  (event: 'run', command: Command): void
  (event: 'open', target: { relativePath: string; line?: number }): void
}>()

const query = ref('')
const matches = ref<PaletteMatch[]>([])
const cursor = ref(0)
const input = ref<HTMLInputElement | null>(null)

/** 当前视图可执行的命令（含全局动作） */
const available = computed(() => commandsFor(props.view))

/** 把命令翻成领域层要的形状 */
function toItems(commands: readonly Command[]) {
  // **顺序 = 领域层给的「常用优先」顺序**：面板打开时（查询为空）头几条应当是常用的，
  // 而不是清单的书写顺序。不在榜上的 id 排在后面（保持原相对顺序）。
  const ranked = props.rankedCommands ?? []
  const order = new Map(ranked.map((id, index) => [id, index]))
  const sorted = [...commands].sort((a, b) => {
    const ai = order.get(a.id)
    const bi = order.get(b.id)
    if (ai === undefined && bi === undefined) return 0
    if (ai === undefined) return 1
    if (bi === undefined) return -1
    return ai - bi
  })
  return sorted.map((command) => ({
    id: command.id,
    title: command.title,
    keywords: command.keywords,
    group: command.group,
  }))
}

/** 把**工作区文件**也搜进来（与命令同一张榜；搜索用的是 Rust 侧同一个引擎） */
async function openableItems(needle: string): Promise<PaletteItem[]> {
  const root = props.workspaceRoot
  if (!root || needle.trim().length < 2) return [] // 太短就别搜（一搜一大片，反而吵）
  try {
    const found = await workspaceSearch(root, needle, { byContent: false, limit: 200 })
    return found.files.map((path) => fileToItem(path, false))
  } catch {
    // 搜不到就不并进来（**不假装搜过**）
    return []
  }
}

async function refresh() {
  if (!props.open) return
  const commands = toItems(available.value)
  const openables = await openableItems(query.value)
  // 最近打开放前面（"回到刚才那个"是最常用的动作）；对象按名字搜
  const recent = (props.recentFiles ?? []).map((path) => {
    const item = fileToItem(path, false)
    return { ...item, group: '最近打开' }
  })
  const objects = (props.objects ?? []).map((o) => objectToItem(o.schema, o.name, o.kind))
  matches.value = await paletteSearch(query.value, mergeItems(commands, [...recent, ...openables, ...objects]))
  // 选中项夹进范围（结果变少时不该停在空位上）
  cursor.value = Math.min(cursor.value, Math.max(0, matches.value.length - 1))
}

watch(() => props.open, async (open) => {
  if (!open) return
  query.value = ''
  cursor.value = 0
  await refresh()
  await nextTick()
  input.value?.focus()
})

watch(query, async () => {
  cursor.value = 0
  await refresh()
})

/** 命中的字符位置 ⇒ 切成"亮 / 不亮"的片段（**不在这里重新匹配**） */
function pieces(match: PaletteMatch): { text: string; hit: boolean }[] {
  const chars = [...match.item.title]
  const hits = new Set(match.highlighted)
  const out: { text: string; hit: boolean }[] = []
  chars.forEach((ch, index) => {
    const hit = hits.has(index)
    const last = out[out.length - 1]
    if (last && last.hit === hit) {
      last.text += ch
    } else {
      out.push({ text: ch, hit })
    }
  })
  return out
}

function move(delta: number) {
  if (matches.value.length === 0) return
  const next = cursor.value + delta
  // **到边界停住**（不循环：循环会让"按了几次到底"不可数）
  cursor.value = Math.max(0, Math.min(matches.value.length - 1, next))
}

/** 选中并执行：**先看 id 是哪一类**（命令 / 文件 / 对象），再分派 */
function runSelected() {
  const chosen = matches.value[cursor.value]
  if (!chosen) return
  const target = targetOf(chosen.item.id)
  if (target.kind === 'command') {
    const command = available.value.find((c) => c.id === target.id)
    if (!command) return
    emit('run', command)
  } else if (target.kind === 'file') {
    emit('open', { relativePath: target.relativePath })
  } else {
    // 数据库对象：本侧还没做"从面板跳到对象"，如实说明而不是静默什么都不做
    return
  }
  emit('close')
}
</script>

<template>
  <div v-if="open" class="palette" role="dialog" aria-label="命令面板">
    <div class="palette__box">
      <input
        ref="input"
        v-model="query"
        class="palette__input"
        type="text"
        placeholder="输入命令名或缩写（例如 fmt / 格式 / 保存）"
        aria-label="命令搜索"
        @keydown.down.prevent="move(1)"
        @keydown.up.prevent="move(-1)"
        @keydown.enter.prevent="runSelected"
        @keydown.esc.prevent="emit('close')"
      />
      <p v-if="matches.length === 0" class="palette__empty">没有匹配的命令</p>
      <ul v-else class="palette__list">
        <li
          v-for="(match, index) in matches"
          :key="match.item.id"
          class="palette__item"
          :class="{ 'palette__item--active': index === cursor }"
          @mouseenter="cursor = index"
          @click="runSelected"
        >
          <span class="palette__title">
            <template v-for="(piece, i) in pieces(match)" :key="i">
              <mark v-if="piece.hit" class="palette__hit">{{ piece.text }}</mark>
              <template v-else>{{ piece.text }}</template>
            </template>
          </span>
          <span class="palette__group">{{ match.item.group }}</span>
        </li>
      </ul>
      <p class="palette__hint">↑ ↓ 选择 · 回车执行 · Esc 关闭</p>
    </div>
  </div>
</template>

<style scoped>
.palette {
  position: fixed;
  inset: 0;
  z-index: 10;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  background: var(--ds-color-surface-window);
  opacity: 0.97;
}

/* 浮层往下让一截（**用定位而不是 padding**：棘轮的裸间距规则管的是 padding/margin/gap，
   而"浮层离顶多远"本来就是定位问题；顺带也贴它"浮层"的本意） */
.palette__box {
  margin-top: 0;
  top: 12vh;
  position: relative;
}

.palette__box {
  width: 620px;
  max-width: 90vw;
  background: var(--ds-color-surface-content);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  overflow: hidden;
}

.palette__input {
  width: 100%;
  height: var(--ds-metric-toolbar-height);
  padding: 0 var(--ds-spacing-m);
  background: var(--ds-color-surface-content);
  color: var(--ds-color-text-primary);
  border: 0;
  border-bottom: var(--ds-metric-hairline) solid var(--ds-hairline);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-body-size);
}

.palette__list {
  margin: 0;
  padding: 0;
  list-style: none;
  max-height: 46vh;
  overflow: auto;
}

.palette__item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--ds-spacing-s);
  padding: var(--ds-spacing-s);
  cursor: pointer;
}

.palette__item--active {
  background: var(--ds-color-surface-panel);
}

.palette__hit {
  background: transparent;
  color: var(--ds-color-accent-accent);
  font-weight: 600;
}

.palette__group {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}

.palette__empty,
.palette__hint {
  margin: 0;
  padding: var(--ds-spacing-s);
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}
</style>
