<script setup lang="ts">
// 回放插件 · 周报阅读面（FR-R-12-01 左列表 / FR-R-12-02 右正文 · FR-R-13-08 的 M0 只读）
//
// 三条纪律：
//   ① **不改写已有包**：本组件不编辑、不保存、不覆盖任何已存在的期；唯一的写入动作是
//      「导入包…」—— 那是把**新**包复制进库（`FR-R-12-04`），落盘与判定全在 Rust 侧，
//      前端只把结果原话摆出来；
//   ② **不自带第二套解析**：卡片字段与正文块全部由 Rust（领域层 `retro_package` +
//      `markdown::parse`）判完送来，这里只画；
//   ③ **坏包要说出来**：读不出来的期逐条列在左栏底部（缺 index / 缺正文 / 编码错 / 封面越界），
//      不让它静默消失 —— 用户放进去的包没出现，必须能查到哪里不对。

import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import BlockDocument, { type MediaSlot } from './BlockDocument.vue'
import { coverMime, formatGeneratedAt } from './cardMeta'
import { filterCards, groupCards } from './periodIndex'
import {
  openExternal,
  retroAsset,
  retroImport,
  retroImportBatch,
  retroPackages,
  retroReport,
  retroReveal,
  type DbFailure,
  type MdDocument,
  type RetroBatchImport,
  type RetroCard,
  type RetroImport,
  type RetroImportState,
  type RetroMedia,
  type RetroProblem,
} from '../../ipc'
import { pickFolder } from '../../shell/pluginRegistry'
import { t as translate, type UiLanguage } from '../../i18n'
import {
  docFontClass,
  readDocFontSize,
  stepDocFontSize,
  storeDocFontSize,
  type DocFontSize,
  type KeyValueStore,
} from './docPrefs'
import { outlineOf, type OutlineEntry } from './outline'

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
/** 外链打开失败的原因（键 = 正文里写的原文；切期清空）。 */
const openFailures = ref<Record<string, string>>({})

/**
 * 媒体汇总（`FR-R-13-09` 判据③④的「报告一条」）：
 * 判定 `ok` 的不算问题（哪怕字节还在路上，那是「正在读」而不是「显示不出来」）。
 */
const mediaTrouble = computed(() => {
  const counts = { missing: 0, external: 0, unsupported: 0, rejected: 0 }
  for (const slot of media.value) {
    if (slot.state === 'missing') counts.missing += 1
    else if (slot.state === 'external') counts.external += 1
    else if (slot.state === 'unsupported') counts.unsupported += 1
    else if (slot.state === 'rejected') counts.rejected += 1
  }
  return counts
})

const mediaTroubleTotal = computed(
  () => mediaTrouble.value.missing + mediaTrouble.value.external + mediaTrouble.value.unsupported + mediaTrouble.value.rejected,
)

/** 汇总条里的分项（只写非 0 的那几项，不让「缺失 0」占字数）。 */
const mediaTroubleDetail = computed(() => {
  const parts: string[] = []
  const c = mediaTrouble.value
  if (c.missing) parts.push(tr('plugin.retro.mediaSummaryMissing', { n: c.missing }))
  if (c.external) parts.push(tr('plugin.retro.mediaSummaryExternal', { n: c.external }))
  if (c.unsupported) parts.push(tr('plugin.retro.mediaSummaryUnsupported', { n: c.unsupported }))
  if (c.rejected) parts.push(tr('plugin.retro.mediaSummaryRejected', { n: c.rejected }))
  return parts.join(' · ')
})

/**
 * 点「用系统默认打开」（`FR-R-13-09` ②）：交给系统，**视图内不加载、不出网**。
 *
 * 失败就地写原因（键 = 正文原文），下次点同一个链接会先清掉旧原因 ——
 * 否则「上次失败」会一直挂着，看起来像这次也没成。
 */
async function openExternalTarget(target: string): Promise<void> {
  if (openFailures.value[target]) {
    const cleared = { ...openFailures.value }
    delete cleared[target]
    openFailures.value = cleared
  }
  try {
    await openExternal(target)
  } catch (error) {
    openFailures.value = { ...openFailures.value, [target]: describeError(error).message }
  }
}

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

/** 生成时间：包里写了就显示那个墙上时间，没写就如实说「未标注」（`cardMeta.ts` 里定口径）。 */
function generatedText(card: RetroCard): string {
  const at = formatGeneratedAt(card.generatedAt)
  return at ? tr('plugin.retro.generatedAt', { t: at }) : tr('plugin.retro.noGeneratedAt')
}

// ── 封面缩略图（`FR-R-13-08` 判据① 的「封面缩略图」）──────────────────────────────
// 三条口径：① 路径合法性 / 在不在包里已由 Rust 判过（`retro_package`），这里只取字节；
// ② 字节走既有的 `retroAsset` 命令（**不开 asset 协议**，CSP 仍是「出网只走 IPC」）；
// ③ 取不到就说「封面读不出来」——不留一块空白让用户猜。
const coverUrls = ref<Record<string, string>>({})
const coverFailed = ref<Set<string>>(new Set())
/** 重扫一次就作废上一批晚到的字节（同 `loadMedia` 的「切期丢弃」口径）。 */
let coverEpoch = 0

function releaseCovers(): void {
  // 自增即作废：上一批还在飞的字节回来后对不上 epoch，会被丢掉
  coverEpoch += 1
  for (const url of Object.values(coverUrls.value)) URL.revokeObjectURL(url)
  coverUrls.value = {}
  coverFailed.value = new Set()
}

/**
 * 拉一批封面。
 *
 * **逐张顺序取**：包目录里的期数是个位 / 十位数，一张张来既不会把 IPC 打满，
 * 也不会在卡片顺序上出现「谁先到谁先亮」的抖动。
 */
async function loadCovers(list: RetroCard[]): Promise<void> {
  releaseCovers()
  const epoch = coverEpoch
  for (const card of list) {
    if (!card.cover) continue
    const target = card.cover
    try {
      const bytes = await retroAsset(card.period, target)
      const url = URL.createObjectURL(new Blob([bytes], { type: coverMime(target) }))
      if (epoch !== coverEpoch) {
        // 已经重扫过一轮：这张是上一批的，丢掉（否则会把旧封面挂到新卡上）
        URL.revokeObjectURL(url)
        return
      }
      coverUrls.value = { ...coverUrls.value, [card.period]: url }
    } catch {
      if (epoch !== coverEpoch) return
      const next = new Set(coverFailed.value)
      next.add(card.period)
      coverFailed.value = next
    }
  }
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
    void loadCovers(snapshot.cards)
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
    releaseCovers()
  } finally {
    loading.value = false
  }
}

// ── 导入一个包（`FR-R-12-04` ①③）───────────────────────────────────────────────────
//
// 三条口径：
// ① **选择器只有一处**：目录由挂点契约的宿主能力 `pickFolder` 弹（实现在 `shell/dialogs.ts`；
//    插件不许直接 import shell 内部模块 —— 判据 `check-plugins.mjs` ④）；
// ② **判定不在前端**：幂等 / 冲突 / 拒收都是 Rust 回的结果态，这里只把原话摆出来；
// ③ **导进来就要在列表里**：成功后立刻 `refresh()`，用户点一下就能看见新的一期（否则等于没导入）。

/** 正在导入（按钮置灰，防连点导两份）。 */
const importing = ref(false)
/** 上一次导入的结果（成功 / 幂等 / 冲突 / 拒收都从这里显示）。 */
const importResult = ref<RetroImport | null>(null)
/** 导入彻底失败（连判定都没拿到：不是目录 / 命令报错）。 */
const importFailure = ref<DbFailure | null>(null)

async function importPackage(): Promise<void> {
  if (importing.value) return
  importFailure.value = null
  importResult.value = null
  let source: string | null = null
  try {
    source = await pickFolder({ title: tr('plugin.retro.importPickTitle') })
  } catch (error) {
    importFailure.value = describeError(error)
    return
  }
  // 用户取消：什么都不做（不报错、不提示 —— 取消不是失败）
  if (!source) return
  importing.value = true
  try {
    importResult.value = await retroImport(source)
    // 导进来 / 已存在 / 冲突：三种情况都重扫一遍（冲突时列表要如实显示库里那一份）
    await refresh()
  } catch (error) {
    importFailure.value = describeError(error)
  } finally {
    importing.value = false
  }
}

// ── 整批导入（`FR-R-12-04` 批量形态）──────────────────────────────────────────────
//
// 口径与单包完全一样，只是「一次选一层」：选中的目录本身就是一个包 ⇒ 退回单包口径（用户常点进包里再选）；
// 否则逐个**子目录**走同一套单包判定（先判后拷 / 幂等 / 冲突），界面只把 Rust 给的逐条结果摆出来。
// 不是包的条目**只计数**（`skipped`），不逐条刷屏 —— 选了一整个下载目录也不会被红字淹掉。

/** 正在整批导入（两个按钮一起置灰，别让用户在这中间又点一次单包）。 */
const batchImporting = ref(false)
/** 上一次整批的结果（`null` = 还没导过）。 */
const batchResult = ref<RetroBatchImport | null>(null)

/** 逐条结果的计数（合计条用；态本身由 Rust 判，这里只数）。 */
const batchCounts = computed(() => {
  const counts: Record<RetroImportState, number> = {
    imported: 0,
    already: 0,
    conflict: 0,
    rejected: 0,
    failed: 0,
  }
  for (const item of batchResult.value?.items ?? []) counts[item.state] += 1
  return counts
})

/** 态标签（`plugin.retro.state.*`）：只给一个人话的词，判定不在前端。 */
function stateLabel(state: RetroImportState): string {
  return tr(`plugin.retro.state.${state}` as Parameters<typeof translate>[0])
}

async function importFolder(): Promise<void> {
  if (batchImporting.value || importing.value) return
  importFailure.value = null
  batchResult.value = null
  let source: string | null = null
  try {
    source = await pickFolder({ title: tr('plugin.retro.importBatchPickTitle') })
  } catch (error) {
    importFailure.value = describeError(error)
    return
  }
  // 取消不是失败：什么都不做、什么都不说
  if (!source) return
  batchImporting.value = true
  try {
    batchResult.value = await retroImportBatch(source)
    // 只要这一批里有任何一期真落进来，列表就得当场多出来（否则等于没导入）
    await refresh()
  } catch (error) {
    importFailure.value = describeError(error)
  } finally {
    batchImporting.value = false
  }
}

// ── 打开所在文件夹（本机存储的可见面）───────────────────────────────────────────────
//
// 只传期号：目录由库根 + 期号在 Rust 侧拼（`validate_period` 会挡越界写法），界面给不了任意路径。
// 成功没有额外提示 —— 资源管理器窗口本身就是反馈；失败则把原话与提示摆出来（不静默）。

const revealing = ref(false)
const revealFailure = ref<DbFailure | null>(null)

async function revealSelected(): Promise<void> {
  const period = selected.value
  if (!period || revealing.value) return
  revealing.value = true
  revealFailure.value = null
  try {
    await retroReveal(period)
  } catch (error) {
    if (selected.value === period) revealFailure.value = describeError(error)
  } finally {
    revealing.value = false
  }
}

// ── 显示设定：目录锚点 + 字号三档（`FR-R-13-08` ①）────────────────────────────────
//
// 口径：**显示设定只改「怎么看」，一个字节都不写回包** —— 大纲是正文标题的派生
// （`outline.ts` 纯函数），字号是容器上的一个 class；两者都不触发 IPC 写命令，也不重读正文。

/** 大纲面板是否展开（默认收起：周报多是通读，面板摊着白占位置）。 */
const outlineOpen = ref(false)
/** 大纲里当前跳到的那一行（`null` = 还没跳过）；切期一并清掉。 */
const activeLine = ref<number | null>(null)
/** 正文容器（滚动要它的 ref —— `scrollIntoView` 得先有容器才能找节点）。 */
const docEl = ref<HTMLElement | null>(null)

const outlineEntries = computed<OutlineEntry[]>(() => outlineOf(document.value))

/** 取 localStorage（隐私模式下**访问**这一层就可能抛 ⇒ 当「没有存储」）。 */
function prefs(): KeyValueStore | null {
  try {
    const store = (globalThis as { localStorage?: KeyValueStore }).localStorage
    return store ?? null
  } catch {
    return null
  }
}

/** 字号档（冷启动读回上次的；读不出 = 标准档，判定在 `docPrefs`）。 */
const fontSize = ref<DocFontSize>(readDocFontSize(prefs()))

/** 容器 class：`retro__document` + 档位 class（CSS 只认这三个名字）。 */
const documentClasses = computed(() => ['retro__document', docFontClass(fontSize.value)])

/** 换档并记住（记不住只丢偏好，正文照旧）。 */
function setFontSize(next: DocFontSize): void {
  fontSize.value = next
  storeDocFontSize(prefs(), next)
}

/** 加一档 / 减一档（到头停住，不绕回 —— 绕回会像点错了）。 */
function stepFont(direction: -1 | 1): void {
  setFontSize(stepDocFontSize(fontSize.value, direction))
}

/** 点大纲：标成当前 + 滚到那一段（节点不在就只标高亮，不假装滚了）。 */
function jumpToHeading(entry: OutlineEntry): void {
  activeLine.value = entry.line
  const host = docEl.value
  if (!host) return
  const target = host.querySelector<HTMLElement>(`[id="${entry.id}"]`)
  if (!target) return
  if (typeof target.scrollIntoView === 'function') {
    target.scrollIntoView({ block: 'start' })
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
  openFailures.value = {}
  revealFailure.value = null
  activeLine.value = null
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
  releaseCovers()
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
        <button
          class="retro__refresh"
          type="button"
          data-role="retro-import"
          :disabled="importing || batchImporting"
          :title="tr('plugin.retro.importHint')"
          @click="importPackage"
        >
          {{ importing ? tr('plugin.retro.importing') : tr('plugin.retro.import') }}
        </button>
        <button
          class="retro__refresh"
          type="button"
          data-role="retro-import-batch"
          :disabled="importing || batchImporting"
          :title="tr('plugin.retro.importBatchHint')"
          @click="importFolder"
        >
          {{ batchImporting ? tr('plugin.retro.importing') : tr('plugin.retro.importBatch') }}
        </button>
      </header>

      <!-- 整批导入的结果（`FR-R-12-04` 批量形态）：一条合计 + 可展开的逐条明细 -->
      <template v-if="batchResult">
        <p
          v-if="batchResult.items.length"
          class="retro__count"
          :data-state="batchCounts.imported ? 'imported' : 'already'"
          data-role="retro-import-batch-result"
        >
          {{
            tr('plugin.retro.batchSummary', {
              n: batchResult.items.length,
              added: batchCounts.imported,
              already: batchCounts.already,
              conflict: batchCounts.conflict,
              bad: batchCounts.rejected + batchCounts.failed,
            })
          }}
        </p>
        <p
          v-else
          class="retro__hint"
          data-role="retro-import-batch-result"
          data-state="empty"
        >
          {{ tr('plugin.retro.batchNothing', { n: batchResult.scanned }) }}
          <span class="retro__failure-hint">{{ tr('plugin.retro.batchNothingHint') }}</span>
        </p>
        <p
          v-if="batchResult.items.length && batchResult.skipped"
          class="retro__hint"
          data-role="retro-import-batch-skipped"
        >
          {{ tr('plugin.retro.batchSkipped', { n: batchResult.skipped }) }}
        </p>
        <details
          v-if="batchResult.items.length"
          class="retro__problems"
          data-role="retro-import-batch-items"
        >
          <summary>{{ tr('plugin.retro.batchDetails', { n: batchResult.items.length }) }}</summary>
          <ul>
            <li
              v-for="item in batchResult.items"
              :key="item.period"
              :data-period="item.period"
              :data-state="item.state"
            >
              <code class="retro__period">{{ item.period }}</code>
              <span class="retro__problem-text">{{ stateLabel(item.state) }} · {{ item.message }}</span>
            </li>
          </ul>
        </details>
      </template>

      <!-- 导入结果（`FR-R-12-04` ①③）：成功 / 已导入 / 冲突 / 拒收都如实说一句 -->
      <p
        v-if="importResult"
        class="retro__count"
        :data-state="importResult.state"
        data-role="retro-import-result"
      >
        {{ importResult.message }}
      </p>
      <p v-if="importFailure" class="retro__failure" data-role="retro-import-failure">
        {{ tr('plugin.retro.importFailed') }}：{{ importFailure.message }}
        <span v-if="importFailure.hint" class="retro__failure-hint">{{ importFailure.hint }}</span>
      </p>

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
        <p class="retro__empty-hint">{{ tr('plugin.retro.emptyImportHint') }}</p>
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
                    <!-- 封面缩略图（`FR-R-13-08` 判据①）：有就用字节画，没有 / 读不出来都如实占位 -->
                    <span v-if="card.cover" class="retro__cover" data-role="retro-cover">
                      <img
                        v-if="coverUrls[card.period]"
                        class="retro__cover-image"
                        :src="coverUrls[card.period]"
                        :alt="tr('plugin.retro.coverAlt', { title: card.title })"
                        data-role="retro-cover-image"
                      />
                      <span
                        v-else-if="coverFailed.has(card.period)"
                        class="retro__cover-note"
                        data-role="retro-cover-failed"
                        >{{ tr('plugin.retro.coverFailed') }}</span
                      >
                      <span v-else class="retro__cover-note">{{ tr('plugin.retro.coverLoading') }}</span>
                    </span>
                    <span
                      v-else
                      class="retro__cover retro__cover--empty"
                      data-role="retro-cover-empty"
                      >{{ tr('plugin.retro.noCover') }}</span
                    >
                    <span class="retro__card-title">{{ card.title }}</span>
                    <span class="retro__card-meta">
                      <code class="retro__period">{{ card.period }}</code>
                      <span class="retro__range">{{ rangeText(card) }}</span>
                    </span>
                    <span class="retro__generated" data-role="retro-generated">{{ generatedText(card) }}</span>
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
          <!-- 打开所在文件夹（本机存储的可见面）：只传期号，路径在 Rust 侧拼 -->
          <button
            class="retro__refresh"
            type="button"
            data-role="retro-reveal"
            :disabled="revealing"
            :title="tr('plugin.retro.revealHint')"
            @click="revealSelected"
          >
            {{ tr('plugin.retro.reveal') }}
          </button>
          <!-- 字号三档（`FR-R-13-08` ①「显示设定」）：只改容器 class，不碰包 -->
          <span v-if="document" class="retro__font" role="group" :aria-label="tr('plugin.retro.fontAria')">
            <button
              class="retro__font-step"
              type="button"
              data-role="retro-font-down"
              :disabled="fontSize === 'sm'"
              :title="tr('plugin.retro.fontSmaller')"
              @click="stepFont(-1)"
            >
              A−
            </button>
            <span class="retro__font-current" data-role="retro-font-current">
              {{ tr(`plugin.retro.font.${fontSize}` as Parameters<typeof translate>[0]) }}
            </span>
            <button
              class="retro__font-step"
              type="button"
              data-role="retro-font-up"
              :disabled="fontSize === 'lg'"
              :title="tr('plugin.retro.fontLarger')"
              @click="stepFont(1)"
            >
              A+
            </button>
          </span>
          <!-- 目录锚点（`FR-R-13-08` ①）：有标题才有面板，空文档不画一个「0 条」 -->
          <button
            v-if="outlineEntries.length"
            class="retro__refresh"
            type="button"
            data-role="retro-outline-toggle"
            :aria-expanded="outlineOpen"
            :title="tr('plugin.retro.outlineHint')"
            @click="outlineOpen = !outlineOpen"
          >
            {{ tr('plugin.retro.outlineToggle', { n: outlineEntries.length }) }}
          </button>
        </header>
        <!-- 大纲：条目 = 正文标题（层级按源文缩进；当前那一节带左侧强调线） -->
        <nav
          v-if="outlineOpen && outlineEntries.length"
          class="retro__outline"
          data-role="retro-outline"
          :aria-label="tr('plugin.retro.outlineAria')"
        >
          <ul class="retro__outline-list">
            <li v-for="entry in outlineEntries" :key="entry.id">
              <button
                class="retro__outline-item"
                type="button"
                data-role="retro-outline-item"
                :data-level="entry.level"
                :data-line="entry.line"
                :aria-current="activeLine === entry.line ? 'location' : undefined"
                @click="jumpToHeading(entry)"
              >
                {{ entry.text || tr('plugin.retro.outlineUntitled') }}
              </button>
            </li>
          </ul>
        </nav>
        <p v-if="revealFailure" class="retro__failure" data-role="retro-reveal-failure">
          {{ tr('plugin.retro.revealFailed') }}：{{ revealFailure.message }}
          <span v-if="revealFailure.hint" class="retro__failure-hint">{{ revealFailure.hint }}</span>
        </p>
        <p v-if="reportLoading" class="retro__hint">{{ tr('plugin.retro.loading') }}</p>
        <p v-else-if="reportFailure" class="retro__failure" data-role="retro-report-failure">
          {{ tr('plugin.retro.reportFailed') }}：{{ reportFailure.message }}
          <span v-if="reportFailure.hint" class="retro__failure-hint">{{ reportFailure.hint }}</span>
        </p>
        <div v-else-if="document" ref="docEl" :class="documentClasses" data-role="retro-document">
          <!-- 媒体汇总（`FR-R-13-09` ③④）：逐条报告的同时给一条看得见的合计，省得一行行找 -->
          <p v-if="mediaTroubleTotal" class="retro__media-summary" data-role="retro-media-summary">
            {{ tr('plugin.retro.mediaSummary', { n: mediaTroubleTotal, detail: mediaTroubleDetail }) }}
          </p>
          <BlockDocument
            :document="document"
            :media="media"
            :language="lang"
            :open-failures="openFailures"
            :active-line="activeLine"
            @zoom="openZoom"
            @open-external="openExternalTarget"
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
/* 封面缩略图：一条 100% 宽的扁条（复用工具栏高度令牌 —— 不为它新造一个易漂的尺寸值） */
.retro__cover {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: var(--ds-metric-toolbar-height);
  overflow: hidden;
  border-radius: var(--ds-radius-badge);
  background: var(--ds-color-surface-raised);
}
.retro__cover--empty {
  border: var(--ds-hairline) dashed var(--ds-color-hairline-light);
  background: transparent;
  color: var(--ds-color-text-disabled);
  font-size: var(--ds-font-caption-size);
}
.retro__cover-image {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.retro__cover-note {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
}
.retro__generated {
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
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
/* 字号三档（`FR-R-13-08` ①「显示设定：字号」）：只在容器上写一个缩放变量 ——
   `BlockDocument` 的正文 / 标题 / 代码按它算，媒体说明与表头这类界面件**不缩放**。 */
.retro__document--sm {
  --retro-doc-scale: 0.92;
}
.retro__document--md {
  --retro-doc-scale: 1;
}
.retro__document--lg {
  --retro-doc-scale: 1.14;
}
/* 字号按钮组：与「刷新 / 打开文件夹」同一套控制件令牌（不新造尺寸与颜色） */
.retro__font {
  display: inline-flex;
  align-items: center;
  gap: var(--ds-spacing-xs);
}
.retro__font-step {
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: var(--ds-hairline) solid var(--ds-color-hairline-light);
  border-radius: var(--ds-radius-control);
  background: var(--ds-color-surface-panel);
  color: var(--ds-color-text-secondary);
  font: inherit;
  font-size: var(--ds-font-caption-size);
  cursor: pointer;
}
.retro__font-step:disabled {
  color: var(--ds-color-text-disabled);
  cursor: default;
}
.retro__font-current {
  min-width: var(--ds-spacing-xl);
  color: var(--ds-color-text-tertiary);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
  text-align: center;
}
/* 大纲面板（目录锚点）：一行一条，层级越深越往里缩；当前那一节与正文里的强调线对应 */
.retro__outline {
  padding: var(--ds-spacing-s) 0;
  border-bottom: var(--ds-hairline) solid var(--ds-color-hairline-light);
  max-height: 220px;
  overflow-y: auto;
}
.retro__outline-list {
  display: flex;
  flex-direction: column;
  gap: var(--ds-spacing-hair);
  list-style: none;
}
.retro__outline-item {
  width: 100%;
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: 0;
  border-left: var(--ds-hairline) solid transparent;
  border-radius: var(--ds-radius-control);
  background: transparent;
  color: var(--ds-color-text-secondary);
  font: inherit;
  font-size: var(--ds-font-caption-size);
  text-align: left;
  cursor: pointer;
}
.retro__outline-item:hover {
  background: var(--ds-color-surface-panel);
  color: var(--ds-color-text-primary);
}
.retro__outline-item[aria-current='location'] {
  border-left-color: var(--ds-color-accent-accent);
  color: var(--ds-color-accent-accent);
}
/* 层级缩进（按源文 1~6，两档够用：一级顶格、其余缩一档） */
.retro__outline-item[data-level='2'] {
  padding-left: var(--ds-spacing-m);
}
.retro__outline-item[data-level='3'],
.retro__outline-item[data-level='4'],
.retro__outline-item[data-level='5'],
.retro__outline-item[data-level='6'] {
  padding-left: var(--ds-spacing-l);
}
/* 媒体汇总条（`FR-R-13-09` ③④）：一条看得见的合计，不是第二套状态机 */
.retro__media-summary {
  margin-bottom: var(--ds-spacing-s);
  padding: var(--ds-spacing-xs) var(--ds-spacing-s);
  border: var(--ds-hairline) dashed var(--ds-color-status-warning);
  border-radius: var(--ds-radius-badge);
  color: var(--ds-color-status-warning);
  font-size: var(--ds-font-caption-size);
  font-variant-numeric: tabular-nums;
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
