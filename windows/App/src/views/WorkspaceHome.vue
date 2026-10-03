<!--
  工作区 Home 页（布局对齐 macOS 封面图）

  图里这一页是**三栏卡片**：最近打开的文件 / 最近打开的工作区 / 连接，
  上面是欢迎语、一行版本与隐私说明、一个「打开文件…」按钮。
  本版把原来的"只有一栏纯路径按钮"换成这个结构。

  三条口径：
  1. **认不出就不显示**：没连过库就**不画"连接"那一栏**（不留一个空栏位充数）；
  2. **当前工作区打勾**：图里 `projects` 有个对勾 —— 那是"当前根"，与"最近用过"不是一回事
     （领域层把 `currentRoot` 单列一项，就是为了"关掉当前工作区"不等于"删掉一条记录"）；
  3. **点一下就该有用**：文件 / 工作区点一下直接打开；连接点一下是**告诉外层去连**（本组件不连库）。
-->
<script setup lang="ts">
import type { HistoryEntry, SavedConnection } from '../ipc'

const props = defineProps<{
  /** 最近打开的文件（带完整路径，图里是路径小字） */
  recentFiles: readonly HistoryEntry[]
  /** 最近打开的工作区 */
  recentWorkspaces: readonly HistoryEntry[]
  /** 当前工作区根（用来给那一栏打勾） */
  currentRoot: string
  /** 已保存的连接（没连过库就是空数组 ⇒ 不画那一栏） */
  connections: readonly SavedConnection[]
  /** 版本号（图里那行"版本 0.2.0（构建 2）"） */
  version: string
}>()

const emit = defineEmits<{
  (event: 'open-file'): void
  (event: 'open-workspace', path: string): void
  (event: 'open-connection', id: string): void
}>()

/** 路径太长时中间省略（图里那些路径也是截过的，但**保留头尾**便于分辨）。 */
function ellipsize(path: string, limit = 48): string {
  if (path.length <= limit) return path
  const head = Math.ceil((limit - 1) / 2)
  const tail = Math.floor((limit - 1) / 2)
  return `${path.slice(0, head)}…${path.slice(path.length - tail)}`
}

/** 连接的副标题（图里是 `PostgreSQL · 127.0.0.1:55433`）。 */
function connectionSubtitle(connection: SavedConnection): string {
  return `${connection.host} · ${connection.database}`
}
</script>

<template>
  <div class="home">
    <h2 class="home__title">欢迎回来</h2>
    <p class="home__lead">左边选工作区，点文件就能在编辑器里打开；配色与补全按文件类型自动匹配。</p>
    <p class="home__meta">版本 {{ props.version }}</p>
    <p class="home__meta">© 2026 DoyahStudio · 本机优先：数据与文件不出这台机器</p>

    <button class="home__open" type="button" @click="emit('open-file')">📂 打开文件…</button>

    <div class="home__columns">
      <!-- ① 最近打开的文件 -->
      <section class="home__column">
        <h3 class="home__column-title">最近打开的文件</h3>
        <p v-if="props.recentFiles.length === 0" class="home__empty">还没有打开过文件。</p>
        <ul v-else class="home__list">
          <li v-for="entry in props.recentFiles" :key="entry.path">
            <button
              class="home__item"
              type="button"
              :title="entry.path"
              @click="emit('open-workspace', entry.path)"
            >
              <span class="home__item-name">{{ entry.displayName }}</span>
              <span class="home__item-path">{{ ellipsize(entry.path) }}</span>
            </button>
          </li>
        </ul>
      </section>

      <!-- ② 最近打开的工作区（当前那个打勾） -->
      <section class="home__column">
        <h3 class="home__column-title">最近打开的工作区</h3>
        <p v-if="props.recentWorkspaces.length === 0" class="home__empty">还没有打开过工作区。</p>
        <ul v-else class="home__list">
          <li v-for="entry in props.recentWorkspaces" :key="entry.path">
            <button
              class="home__item"
              type="button"
              :title="entry.path"
              @click="emit('open-workspace', entry.path)"
            >
              <span class="home__item-name">
                {{ entry.displayName }}
                <span v-if="entry.path === props.currentRoot" class="home__tick" title="当前工作区">✓</span>
              </span>
              <span class="home__item-path">{{ ellipsize(entry.path) }}</span>
            </button>
          </li>
        </ul>
      </section>

      <!-- ③ 连接（**没连过库就不画这一栏**，不留空栏位充数） -->
      <section v-if="props.connections.length > 0" class="home__column">
        <h3 class="home__column-title">连接</h3>
        <ul class="home__list">
          <li v-for="connection in props.connections" :key="connection.id">
            <button
              class="home__item"
              type="button"
              :title="`连接到 ${connection.name}`"
              @click="emit('open-connection', connection.id)"
            >
              <span class="home__item-name">{{ connection.name }}</span>
              <span class="home__item-path">{{ connectionSubtitle(connection) }}</span>
            </button>
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>

<style scoped>
.home {
  padding: var(--ds-spacing-l);
  overflow: auto;
}

.home__title {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-bright);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-title-size);
}

.home__lead {
  margin: 0 0 var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-body-size);
}

.home__meta {
  margin: 0;
  color: var(--ds-color-text-tertiary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

.home__open {
  margin: var(--ds-spacing-m) 0;
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-m);
  border: var(--ds-metric-hairline) solid var(--ds-hairline);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-raised);
  color: var(--ds-color-text-primary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-body-size);
  cursor: pointer;
}

.home__open:hover {
  border-color: var(--ds-color-accent-accent);
}

.home__columns {
  display: grid;
  /* 三栏等宽；窄窗自动折行（图里是宽窗的样子） */
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: var(--ds-spacing-l);
  margin-top: var(--ds-spacing-m);
}

.home__column-title {
  margin: 0 0 var(--ds-spacing-s);
  color: var(--ds-color-text-primary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-body-size);
  font-weight: 600;
}

.home__empty {
  margin: 0;
  color: var(--ds-color-text-tertiary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
}

.home__list {
  margin: 0;
  padding: 0;
  list-style: none;
}

.home__item {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-hair);
  width: 100%;
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: none;
  border-radius: var(--ds-radius-control);
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.home__item:hover {
  background: var(--ds-color-surface-raised);
}

.home__item-name {
  color: var(--ds-color-text-primary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-body-size);
}

.home__item-path {
  color: var(--ds-color-text-tertiary);
  font-family: var(--ds-font-stack);
  font-size: var(--ds-font-caption-size);
  word-break: break-all;
}

.home__tick {
  color: var(--ds-color-accent-accent);
}
</style>
