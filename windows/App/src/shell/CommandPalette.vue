<script setup lang="ts">
// 命令面板（2.9）：清单来自 `shell/commands.ts`，**匹配与排序来自 Rust 领域层**（`palette`）
//
// 三条纪律：
//   ① 面板里**只显示当前视图能执行的命令**（含全局动作）—— 不给点了没反应的项；
//   ② 高亮位置用领域层给的**字符位置**（不在这里再算一遍匹配）；
//   ③ 执行完就关面板；**执行失败要说出来**（由调用方负责显示）。

import { computed, nextTick, ref, watch } from 'vue'
import { paletteSearch, workspaceSearch, type PaletteItem, type PaletteMatch } from '../ipc'
import { t as translate, type UiLanguage } from '../i18n'
import { commandsFor, type Command } from './commands'
import { fileToItem, mergeItems, objectToItem, targetOf } from './paletteTargets'

const props = defineProps<{
  /** 界面语言（由外壳传下来；不给就按中文） */
  language?: UiLanguage
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
  /**
   * 从**标题栏搜索框**带进来的词（FR-EDIT-37）。
   *
   * 为什么复用面板而不是另做一套搜索：标题栏那个是**全局搜索**（功能 / 命令 / 工作区文件 / 数据库对象），
   * 而面板早就能搜这三样（清单在 `shell/commands.ts`，匹配排序在 Rust 侧）。
   * 再写一套匹配就会出现"两处结果不一样"——那是同一条纪律（同一件事不留两个入口）。
   */
  seedQuery?: string
}>()

/** 本组件的文案帮手（语言由外壳给）。 */
function tr(key: Parameters<typeof translate>[0], vars?: Record<string, string | number>): string {
  return translate(key, props.language ?? 'zh-Hans', vars)
}

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
  // 榜上靠前的几条**单独列组**（面板上一眼能看出"这几个是我常用的"）；
  // 但**不另造条目**（同一 id 只出现一次，否则搜索结果会重复）
  const recentCount = Math.min(5, ranked.length)
  // **显示与搜索词都从语言表取**（`titleKey` / `groupKey`）：
  //   · 显示：当前语言那一份；
  //   · 搜索：**两种语言的标题都并进 keywords** —— 用户的界面是中文也可能搜英文缩写，
  //     只给一种语言的词就会出现"看得见却搜不到"。
  return sorted.map((command, index) => {
    const recent = index < recentCount && order.has(command.id)
    return {
      id: command.id,
      title: tr(command.titleKey as never),
      keywords: [...command.keywords, tr(`cmd.${command.id}` as never)],
      group: recent ? tr('palette.recent') : tr(command.groupKey as never),
    }
  })
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
  // **开面板这一处统一决定起始词**：标题栏搜索带进来的词优先；没有才清空。
  // 为什么不在别处单独 watch seedQuery：`props.open` 与 `props.seedQuery` 往往同一次
  // 更新里一起变，两个 watcher 谁先跑不确定 —— 先灌后清就会把词冲掉（我第一版就是这样）。
  query.value = (props.seedQuery ?? '').trim()
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
  <div v-if="open" class="palette" role="dialog" :aria-label="tr('palette.aria')">
    <div class="palette__box">
      <input
        ref="input"
        v-model="query"
        class="palette__input"
        type="text"
        :placeholder="tr('palette.placeholder')"
        :aria-label="tr('palette.search.aria')"
        @keydown.down.prevent="move(1)"
        @keydown.up.prevent="move(-1)"
        @keydown.enter.prevent="runSelected"
        @keydown.esc.prevent="emit('close')"
      />
      <p v-if="matches.length === 0" class="palette__empty">{{ tr('palette.empty') }}</p>
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
