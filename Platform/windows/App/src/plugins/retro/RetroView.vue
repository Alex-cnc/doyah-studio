<script setup lang="ts">
// 回放插件 · 周报阅读面（FR-R-12-01 左列表 / FR-R-12-02 右正文 · FR-R-13-08 的 M0 只读）
//
// 三条纪律：
//   ① **只读**：本组件不产生任何写回包的动作（没有保存 / 编辑 / 导入按钮）；
//   ② **不自带第二套解析**：卡片字段与正文块全部由 Rust（领域层 `retro_package` +
//      `markdown::parse`）判完送来，这里只画；
//   ③ **坏包要说出来**：读不出来的期逐条列在左栏底部（缺 index / 缺正文 / 编码错 / 封面越界），
//      不让它静默消失 —— 用户放进去的包没出现，必须能查到哪里不对。

import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import BlockDocument, { type MediaSlot } from './BlockDocument.vue'
import { filterCards, groupCards } from './periodIndex'
import {
  retroAsset,
  retroPackages,
  retroReport,
  type DbFailure,
  type MdDocument,
  type RetroCard,
  type RetroMedia,
  type RetroProblem,
} from '../../ipc'
import { t as translate, type UiLanguage } from '../../i18n'

const props = defineProps<{
  /** 界面语言（由外壳传下来；不给就按中文）。 */
  language?: UiLanguage
  /** 插件版本（由外壳从清单里取）。 */
  version?: string
}>()

const lang = computed<UiLanguage>(() => props.language ?? 'zh-Hans')

function tr(key: Parameters<typeof translate>[0], vars?: Record<string, string | number>): string {
  return translate(key, lang.value, vars)
}

/** 扫描结果（根路径 / 能画的期 / 读不出来的地方）。 */
const cards = ref<RetroCard[]>([])
const problems = ref<RetroProblem[]>([])
const root = ref('')
const loading = ref(false)
const loadFailure = ref<DbFailure | null>(null)

/** 当前选中期的正文（`document` 为 `null` = 还没选）。 */
const selected = ref('')
const document = ref<MdDocument | null>(null)
const reportBytes = ref(0)
const reportFailure = ref<DbFailure | null>(null)
const reportLoading = ref(false)

const selectedCard = computed<RetroCard | null>(
  () => cards.value.find((card) => card.period === selected.value) ?? null,
)

// ── 左栏的折叠与过滤（`FR-R-13-08` 判据①）──────────────────────────────────────────
// 三条口径：① 归组 / 过滤都在纯函数里（`periodIndex.ts`），这里只画；
// ② 卡片顺序沿用 Rust 给的「新在前」，分组只做保序切分；
// ③ **正在筛选时组一律展开**（折叠状态照旧记着，清空筛选后恢复）——
//    筛出 1 期却藏在折叠组里，看起来就像「没有结果」。
const query = ref('')
/** 折叠状态：`y:<年>` / `m:<年>-<月>`（在 `Set` 里 = 收起来了）。 */
const folded = ref<Set<string>>(new Set())

const filtering = computed(() => query.value.trim().length > 0)
const filtered = computed(() => filterCards(cards.value, query.value))
const groups = computed(() => groupCards(filtered.value))

function groupKey(kind: 'y' | 'm', year: string, month = ''): string {
  return kind === 'y' ? `y:${year}` : `m:${year}-${month}`
}

/** 筛选期间一律展开（见上面第 ③ 条）。 */
function isFolded(key: string): boolean {
  if (filtering.value) return false
  return folded.value.has(key)
}

/** 折叠状态整份换新（`Set` 原地 mutate 不会触发模板重算）。 */
function toggleFold(key: string): void {
  const next = new Set(folded.value)
  if (next.has(key)) next.delete(key)
  else next.add(key)
  folded.value = next
}

function onQueryInput(event: Event): void {
  query.value = (event.target as HTMLInputElement).value
}

/** 年表头：有年就写「2026 年」，没有就如实说「年份未标注」。 */
function yearLabel(year: string): string {
  return year ? tr('plugin.retro.yearLabel', { year }) : tr('plugin.retro.unknownYear')
}

/** 月表头：`10` → 「10 月」（去掉前导零），空串就如实说「月份未标注」。 */
function monthLabel(month: string): string {
  if (!month) return tr('plugin.retro.unknownMonth')
  return tr('plugin.retro.monthLabel', { month: String(Number(month)) })
}


/** 正文里的媒体：判定（Rust 给的）+ 拉回来的 blob URL（`null` = 还没到 / 读不出来）。 */
const media = ref<MediaSlot[]>([])
/** 点图放大的浮层（`null` = 没开）。 */
const zoom = ref<{ url: string; alt: string } | null>(null)

function describeError(error: unknown): DbFailure {
  if (error && typeof error === 'object' && 'message' in error && 'hint' in error) return error as DbFailure
  return { message: error instanceof Error ? error.message : String(error), hint: '' }
}

/** 日期范围：两端都有就「起 → 止」，只有一端就那一端，都没有就说「未标注」（不编一个日期）。 */
function rangeText(card: RetroCard): string {
  if (card.dateStart && card.dateEnd) return `${card.dateStart} → ${card.dateEnd}`
  if (card.dateStart) return card.dateStart
  if (card.dateEnd) return card.dateEnd
  return tr('plugin.retro.noDate')
}

/** 扫一遍包目录。选中项还在就保留，不在了就清掉（别让右区停在已经不存在的期上）。 */
async function refresh(): Promise<void> {
  loading.value = true
  loadFailure.value = null
  try {
    const snapshot = await retroPackages()
    root.value = snapshot.root
    cards.value = snapshot.cards
    problems.value = snapshot.problems
    if (selected.value && !snapshot.cards.some((card) => card.period === selected.value)) {
      selected.value = ''
      document.value = null
      reportFailure.value = null
      reportBytes.value = 0
      releaseMedia()
      zoom.value = null
    }
  } catch (error) {
    loadFailure.value = describeError(error)
    cards.value = []
    problems.value = []
  } finally {
    loading.value = false
  }
}

/** 打开一期。切期时先清掉上一期的正文 —— 不留残留（`FR-R-12-02` ③）。 */
async function open(card: RetroCard): Promise<void> {
  selected.value = card.period
  document.value = null
  reportFailure.value = null
  reportBytes.value = 0
  reportLoading.value = true
  zoom.value = null
  releaseMedia()
  try {
    const report = await retroReport(card.period)
    document.value = report.document
    reportBytes.value = report.bytes
    void loadMedia(card.period, report.media)
  } catch (error) {
    reportFailure.value = describeError(error)
  } finally {
    reportLoading.value = false
  }
}

/** 放开上一期的 blob URL（不释放会一直占内存 —— 切期是常态操作）。 */
function releaseMedia(): void {
  for (const slot of media.value) {
    if (slot.url) URL.revokeObjectURL(slot.url)
  }
  media.value = []
}

/**
 * 拉媒体的字节并建 blob URL。
 *
 * 三条口径：① 只有 `ok` 才去取（`missing` / 外链 / 白名单外**不该**发请求）；
 * ② 取回来时如果用户已经切期 ⇒ **丢掉**（否则会把上一期的图挂到这一期）；
 * ③ 取失败就地改成「读不出来」，占位里说清，不白屏。
 */
async function loadMedia(period: string, entries: RetroMedia[]): Promise<void> {
  media.value = entries.map((entry) => ({ ...entry, url: null }))
  for (const entry of entries) {
    if (entry.state !== 'ok') continue
    let url: string | null = null
    try {
      const bytes = await retroAsset(period, entry.target)
      url = URL.createObjectURL(new Blob([bytes], { type: entry.mime ?? 'application/octet-stream' }))
    } catch {
      const slot = media.value.find((item) => item.target === entry.target)
      if (slot && selected.value === period) {
        slot.state = 'missing'
        slot.reason = tr('plugin.retro.mediaLoadFailed')
      }
      continue
    }
    if (selected.value !== period) {
      URL.revokeObjectURL(url)
      continue
    }
    const slot = media.value.find((item) => item.target === entry.target)
    if (slot) slot.url = url
  }
}

function openZoom(payload: { url: string; alt: string }): void {
  zoom.value = payload
}

onBeforeUnmount(() => {
  releaseMedia()
})

onMounted(() => {
  void refresh()
})
</script>

<template>
  <section class="retro" data-plugin="retro">
    <!-- 左：周报卡片列表 -->
    <aside class="retro__list">
      <header class="retro__list-head">
        <h2 class="retro__title">{{ tr('plugin.retro.title') }}</h2>
        <span v-if="props.version" class="retro__version">v{{ props.version }}</span>
        <button class="retro__refresh" type="button" :disabled="loading" @click="refresh">
          {{ tr('plugin.retro.refresh') }}
        </button>
      </header>

      <p v-if="cards.length" class="retro__count" data-role="retro-count">
        {{
          filtering
            ? tr('plugin.retro.match', { m: filtered.length, n: cards.length })
            : tr('plugin.retro.count', { n: cards.length })
        }}
      </p>

      <!-- 关键词过滤（`FR-R-13-08` 判据①）：空白分隔多个词是「都要命中」 -->
      <div v-if="cards.length" class="retro__filter">
        <input
          class="retro__filter-input"
          type="search"
          data-role="retro-filter"
          :value="query"
          :placeholder="tr('plugin.retro.filterHint')"
          :aria-label="tr('plugin.retro.filterHint')"
          @input="onQueryInput"
        />
        <button
          v-if="query"
          class="retro__filter-clear"
          type="button"
          data-role="retro-filter-clear"
          :title="tr('plugin.retro.filterClear')"
          :aria-label="tr('plugin.retro.filterClear')"
          @click="query = ''"
        >
          ×
        </button>
      </div>

      <p v-if="loading" class="retro__hint">{{ tr('plugin.retro.loading') }}</p>

      <!-- 读不出来：逐条列出（不静默） -->
      <p v-if="loadFailure" class="retro__failure" data-role="retro-load-failure">
        {{ tr('plugin.retro.loadFailed') }}：{{ loadFailure.message }}
        <span v-if="loadFailure.hint" class="retro__failure-hint">{{ loadFailure.hint }}</span>
      </p>

      <!-- 空态：给出放包目录（用户得知道包该放哪儿） -->
      <div v-if="!loading && !cards.length && !loadFailure" class="retro__empty" data-role="retro-empty">
        <p class="retro__empty-title">{{ tr('plugin.retro.empty') }}</p>
        <p class="retro__empty-hint">{{ tr('plugin.retro.emptyHint', { root }) }}</p>
      </div>

      <!-- 没有匹配：说清楚 + 带上关键词（不许画一片空白） -->
      <p v-if="filtering && !filtered.length" class="retro__hint" data-role="retro-no-match">
        {{ tr('plugin.retro.noMatch', { q: query.trim() }) }}
      </p>

      <ul v-if="groups.length" class="retro__groups">
        <li v-for="group in groups" :key="group.year" class="retro__year" :data-year="group.year">
          <button
            class="retro__year-head"
            type="button"
            :data-role="`retro-year-${group.year || 'unknown'}`"
            :aria-expanded="!isFolded(groupKey('y', group.year))"
            @click="toggleFold(groupKey('y', group.year))"
          >
            <span class="retro__caret" :class="{ 'retro__caret--folded': isFolded(groupKey('y', group.year)) }"
              >▾</span
            >
            <span class="retro__group-label">{{ yearLabel(group.year) }}</span>
            <span class="retro__group-count">{{ group.count }}</span>
          </button>

          <ul v-if="!isFolded(groupKey('y', group.year))" class="retro__months">
            <li v-for="month in group.months" :key="month.month" class="retro__month" :data-month="month.month">
              <button
                class="retro__month-head"
                type="button"
                :data-role="`retro-month-${group.year || 'unknown'}-${month.month || 'unknown'}`"
                :aria-expanded="!isFolded(groupKey('m', group.year, month.month))"
                @click="toggleFold(groupKey('m', group.year, month.month))"
              >
                <span
                  class="retro__caret"
                  :class="{ 'retro__caret--folded': isFolded(groupKey('m', group.year, month.month)) }"
                  >▾</span
                >
                <span class="retro__group-label">{{ monthLabel(month.month) }}</span>
                <span class="retro__group-count">{{ month.cards.length }}</span>
              </button>

              <ul v-if="!isFolded(groupKey('m', group.year, month.month))" class="retro__cards">
                <li v-for="card in month.cards" :key="card.period">
                  <button
                    class="retro__card"
                    :class="{ 'retro__card--active': card.period === selected }"
                    type="button"
                    :data-period="card.period"
                    @click="open(card)"
                  >
                    <span class="retro__card-title">{{ card.title }}</span>
                    <span class="retro__card-meta">
                      <code class="retro__period">{{ card.period }}</code>
                      <span class="retro__range">{{ rangeText(card) }}</span>
                    </span>
                    <span v-if="card.tags.length" class="retro__tags">
                      <span v-for="tag in card.tags" :key="tag" class="retro__tag">{{ tag }}</span>
                    </span>
                  </button>
                </li>
              </ul>
            </li>
          </ul>
        </li>
      </ul>

      <!-- 坏包逐条（放在列表下方，不占正文位置） -->
      <details v-if="problems.length" class="retro__problems" data-role="retro-problems">
        <summary>{{ tr('plugin.retro.problems', { n: problems.length }) }}</summary>
        <ul>
          <li v-for="(problem, index) in problems" :key="`${problem.period}-${index}`">
            <code class="retro__period">{{ problem.period }}</code>
            <span class="retro__problem-text">{{ problem.message }}</span>
          </li>
        </ul>
      </details>
    </aside>

    <!-- 右：正文 -->
    <div class="retro__body">
      <p v-if="!selected" class="retro__hint retro__hint--center" data-role="retro-pick">
        {{ tr('plugin.retro.pickOne') }}
      </p>
      <template v-else>
        <header class="retro__body-head">
          <h3 class="retro__body-title">{{ selectedCard?.title ?? selected }}</h3>
          <p class="retro__body-meta">
            <code class="retro__period">{{ selected }}</code>
            <span v-if="selectedCard" class="retro__range">{{ rangeText(selectedCard) }}</span>
            <span v-if="reportBytes" class="retro__bytes">{{ reportBytes }} B</span>
          </p>
        </header>
        <p v-if="reportLoading" class="retro__hint">{{ tr('plugin.retro.loading') }}</p>
        <p v-else-if="reportFailure" class="retro__failure" data-role="retro-report-failure">
          {{ tr('plugin.retro.reportFailed') }}：{{ reportFailure.message }}
          <span v-if="reportFailure.hint" class="retro__failure-hint">{{ reportFailure.hint }}</span>
        </p>
        <div v-else-if="document" class="retro__document" data-role="retro-document">
          <BlockDocument
            :document="document"
            :media="media"
            :language="lang"
            @zoom="openZoom"
          />
        </div>
      </template>
    </div>

    <!-- 点图放大：同页浮层（不新开窗口、不出网） -->
    <div v-if="zoom" class="retro__zoom" data-role="retro-zoom" @click.self="zoom = null">
      <img class="retro__zoom-image" :src="zoom.url" :alt="zoom.alt" data-role="retro-zoom-image" />
      <div class="retro__zoom-bar">
        <span class="retro__zoom-caption">{{ zoom.alt }}</span>
        <button class="retro__zoom-close" type="button" @click="zoom = null">
          {{ tr('plugin.retro.mediaClose') }}
        </button>
      </div>
    </div>
  </section>
</template>

<style scoped>
/* 只用设计令牌（本侧铁律：不写裸值，令牌棘轮会判红）。 */
.retro {
  display: flex;
  height: 100%;
  color: var(--ds-color-text-primary);
}
.retro__list {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-s);
  width: var(--ds-metric-sidebar-width);
  padding: var(--ds-spacing-m);
  background: var(--ds-color-surface-sidebar);
  border-right: var(--ds-hairline) solid var(--ds-color-hairline-light);
  overflow-y: auto;
}
.retro__list-head {
  display: flex;
  align-items: baseline;
  gap: var(--ds-spacing-s);
}
.retro__title {
  font-size: var(--ds-font-title-size);
  font-weight: 600;
}
.retro__version {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}
.retro__refresh {
  margin-left: auto;
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: var(--ds-hairline) solid var(--ds-color-hairline-light);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-panel);
  color: var(--ds-color-text-secondary);
  font: inherit;
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}
.retro__refresh:disabled {
  color: var(--ds-color-text-disabled);
  cursor: default;
}
.retro__count {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
}
.retro__hint {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-body-size);
}
.retro__hint--center {
  margin: auto;
}
.retro__empty {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  padding: var(--ds-spacing-s);
  border: var(--ds-hairline) dashed var(--ds-color-hairline-light);
  border-radius: var(--ds-radius-card);
}
.retro__empty-title {
  font-size: var(--ds-font-body-size);
}
.retro__empty-hint {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
  word-break: break-all;
}
.retro__filter {
  position: relative;
  display: flex;
  align-items: center;
}
.retro__filter-input {
  width: 100%;
  height: var(--ds-metric-control-height);
  padding: 0 var(--ds-spacing-s);
  border: var(--ds-hairline) solid var(--ds-color-hairline-light);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-panel);
  color: var(--ds-color-text-primary);
  font: inherit;
  font-size: var(--ds-font-caption-size);
}
.retro__filter-input::placeholder {
  color: var(--ds-color-text-disabled);
}
.retro__filter-clear {
  position: absolute;
  right: var(--ds-spacing-xs);
  padding: 0 var(--ds-spacing-xs);
  border: none;
  background: transparent;
  color: var(--ds-color-text-tertiary);
  font: inherit;
  font-size: var(--ds-font-body-size);
  cursor: pointer;
}
.retro__filter-clear:hover {
  color: var(--ds-color-text-primary);
}
.retro__groups {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-s);
  list-style: none;
}
.retro__months,
.retro__cards {
  list-style: none;
}
.retro__months {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  padding-left: var(--ds-spacing-xs);
}
.retro__year-head,
.retro__month-head {
  display: flex;
  align-items: baseline;
  gap: var(--ds-spacing-xs);
  width: 100%;
  padding: var(--ds-spacing-hair) var(--ds-spacing-xs);
  border: none;
  border-radius: var(--ds-radius-control);
  background: transparent;
  color: var(--ds-color-text-secondary);
  font: inherit;
  font-size: var(--ds-font-caption-size);
  text-align: left;
  cursor: pointer;
}
.retro__year-head:hover,
.retro__month-head:hover {
  background: var(--ds-color-surface-raised);
  color: var(--ds-color-text-primary);
}
.retro__year-head .retro__group-label {
  font-weight: 600;
  color: var(--ds-color-text-primary);
}
.retro__caret {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}
.retro__caret--folded {
  transform: rotate(-90deg);
}
.retro__group-count {
  margin-left: auto;
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
}
.retro__cards {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  list-style: none;
}
.retro__card {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-hair);
  width: 100%;
  padding: var(--ds-spacing-s);
  border: var(--ds-hairline) solid transparent;
  border-radius: var(--ds-radius-card);
  background: var(--ds-color-surface-panel);
  color: inherit;
  font: inherit;
  text-align: left;
  cursor: pointer;
}
.retro__card:hover {
  border-color: var(--ds-color-hairline-light);
}
.retro__card--active {
  border-color: var(--ds-color-accent-accent);
  background: var(--ds-color-surface-raised);
}
.retro__card-title {
  font-size: var(--ds-font-body-size);
  font-weight: 600;
}
.retro__card-meta {
  display: flex;
  gap: var(--ds-spacing-s);
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}
.retro__period {
  color: var(--ds-color-text-secondary);
  font-family: var(--ds-font-stack-mono);
  font-size: var(--ds-font-mono-small-size);
}
.retro__range {
  font-variant-numeric: tabular-nums;
}
.retro__tags {
  display: flex;
  flex-wrap: wrap;
  gap: var(--ds-spacing-hair);
}
.retro__tag {
  padding: 0 var(--ds-spacing-xs);
  border-radius: var(--ds-radius-badge);
  background: var(--ds-color-surface-raised);
  color: var(--ds-color-accent-teal);
  font-size: var(--ds-font-caption-size);
}
.retro__problems {
  margin-top: auto;
  color: var(--ds-color-status-warning);
  font-size: var(--ds-font-caption-size);
}
.retro__problems ul {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-hair);
  margin-top: var(--ds-spacing-xs);
  list-style: none;
}
.retro__problems li {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-hair);
}
.retro__problem-text {
  color: var(--ds-color-status-danger);
}
.retro__body {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: var(--ds-spacing-s);
  padding: var(--ds-spacing-m);
  overflow-y: auto;
}
.retro__body-head {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-xs);
  padding-bottom: var(--ds-spacing-s);
  border-bottom: var(--ds-hairline) solid var(--ds-color-hairline-light);
}
.retro__body-title {
  font-size: var(--ds-font-title-size);
  font-weight: 600;
}
.retro__body-meta {
  display: flex;
  gap: var(--ds-spacing-s);
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}
.retro__bytes {
  font-variant-numeric: tabular-nums;
}
.retro__failure {
  padding: var(--ds-spacing-s);
  border: var(--ds-hairline) solid var(--ds-color-status-danger);
  border-radius: var(--ds-radius-card);
  color: var(--ds-color-status-danger);
  font-size: var(--ds-font-caption-size);
}
.retro__failure-hint {
  display: block;
  margin-top: var(--ds-spacing-xs);
  color: var(--ds-color-text-secondary);
}
.retro__document {
  flex: 1;
}
.retro__zoom {
  position: fixed;
  inset: 0;
  z-index: 40;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: var(--ds-spacing-s);
  padding: var(--ds-spacing-l);
  background: color-mix(in srgb, var(--ds-color-surface-window) 70%, transparent);
}
.retro__zoom-image {
  max-width: 92vw;
  max-height: 82vh;
  border-radius: var(--ds-radius-card);
  background: var(--ds-color-surface-content);
}
.retro__zoom-bar {
  display: flex;
  align-items: baseline;
  gap: var(--ds-spacing-s);
}
.retro__zoom-caption {
  color: var(--ds-color-text-secondary);
  font-size: var(--ds-font-caption-size);
}
.retro__zoom-close {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: var(--ds-hairline) solid var(--ds-color-hairline-light);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-panel);
  color: var(--ds-color-text-primary);
  font: inherit;
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}
</style>
