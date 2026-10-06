/**
 * 页面侧驱动（platform/windows/Bench/webview2/driver.js）
 *
 * 由 `bench.mjs`（Node 侧，CDP）注入到**真外壳**（Tauri 2 + WebView2 承载嵌入的前端产物）里执行。
 * 它做四件事：把网格设到目标规模、量 IPC 与排序、量**空转帧节奏**、量**滚动帧耗时**（三档行数）。
 *
 * 口径（与 `Bench/grid/src/bench.ts` 同一套滚动协议；两处常量由
 * `Bench/grid/src/bench-protocol.test.ts` 逐值对齐）：
 * - 帧耗时 = `requestAnimationFrame` 间隔；真机下由 WebView2 的合成器驱动，**含 GPU 合成**；
 * - 滚动步长 / 预热帧 / 测量帧数 = 288px / 30 / 240（与基准台一致，便于两侧对照）；
 * - 内存取 `performance.memory.usedJSHeapSize`（Chromium 专有），拿不到就如实 null；
 * - GPU 证据取 `WEBGL_debug_renderer_info` 的 renderer 串：读到 SwiftShader 就是软件光栅；
 * - **空转档是必需的对照**：只滚动 400k 会分不清「宿主把 rAF 压到 ~20 帧」与「这一屏真的慢」，
 *   故先量「不滚动、只等帧」的节奏，再量三档行数（40 万 / 5 万 / 2 千）的滚动 —— 把
 *   「滚动高度 1000 万像素」这一因素与「每帧重建行 DOM」分开。
 *
 * **消融档（ablation，2026-09-28 第 29 轮修）**：把滚动成本拆成两段 ——
 *   ① 基线档（`scroll@400000`，步长 288px：窗口每帧都换）；
 *   ② `+slow-scroll` 档（**步长 1px/帧**：240 帧只走 240px ⇒ 窗口每 ~26 帧才换一次，其余帧产品**照样**
 *      每帧发窗口取数、照样跑响应式与 vnode 比对，而 DOM 文本不变）⇒ `① − ②` ≈ 每帧「重建可视行 DOM」
 *      写下去的成本；`②` 本身 = IPC + 响应式 + diff + 滚动 + 宿主帧节奏的底噪。
 *   **为什么不用「页面内替换 invoke」那种消融（第 28 轮的坑）**：宿主把 `__TAURI_INTERNALS__.invoke`
 *   定义成**不可写且不可配置**（实测描述符 `writable:false, configurable:false`）⇒ 页面里既不能赋值
 *   替换（sloppy mode **静默失效**、不抛错）也不能 `defineProperty`。第 28 轮那一档正是栽在这里：
 *   它量的是与基线**完全相同**的东西，却报出「IPC 无关」的结论；铁证就在读数 JSON 里 ——
 *   `cachedWindowCalls: 0`（产品一次都没命中补丁）。现在这条事实由 `probeInvokePatchability()`
 *   **当场探一遍并进读数**（`invokePatchability`），换成任何别的消融设计都留下这条证据。
 *
 *
 * **样式消融档（ablation，2026-09-28 第 30 轮加）**：`scrollAblated(rows, css, label)` = 注入一段 CSS
 * （动态带上产品 scoped 样式用的 `data-v-*` 属性，保证**同特异性、后置生效**）→ 跑**同一套**滚动协议
 * （直接调 `scroll()`，不另抄一份协议）→ 还原样式；结果里带 `ablation.proof`（该行 / 该格的**计算后取值**：
 * `contain` / `visibility` / `text-overflow`）。规矩同源：**消融没生效不许当读数** —— 取证靠实测计算值，
 * 不靠「我注入了所以它该生效」。另加 `mutationProbe()`：在同一套协议下装 MutationObserver，数每帧 DOM
 * 变异（新增 / 删除 / 文本 / 属性）—— 用来判「每帧到底写下去多少东西」，与布局 / 样式重算的引擎计数互证。
 * 注意：**本文件不是产品代码**，只在基准台运行时被 CDP 注入；产品形态里不存在它。
 */
(function install() {
  if (globalThis.__DOYAH_WV2_BENCH__) return

  const CFG = {
    rows: 400000,
    cols: 20,
    seed: 20260928,
    frames: 240,
    stepPx: 288,
    warmup: 30,
    windowRows: 64,
    windows: 200,
    idleFrames: 120,
    scrollRows: [400000, 50000, 2000],
  }

  const now = () => performance.now()
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
  const nextFrame = () => new Promise((resolve) => requestAnimationFrame(() => resolve(now())))

  function percentile(sorted, p) {
    if (sorted.length === 0) return 0
    const i = Math.min(sorted.length - 1, Math.max(0, Math.round((p / 100) * (sorted.length - 1))))
    return sorted[i]
  }

  /** 与 Bench/grid/src/bench.ts::frameStats 同口径 */
  function frameStats(deltas) {
    const sorted = [...deltas].sort((a, b) => a - b)
    const sum = deltas.reduce((a, b) => a + b, 0)
    const avg = deltas.length ? sum / deltas.length : 0
    return {
      frames: deltas.length,
      avgMs: +avg.toFixed(3),
      p50Ms: +percentile(sorted, 50).toFixed(3),
      p95Ms: +percentile(sorted, 95).toFixed(3),
      maxMs: +(sorted.length ? sorted[sorted.length - 1] : 0).toFixed(3),
      fps: +(avg > 0 ? 1000 / avg : 0).toFixed(1),
      over16ms: deltas.filter((d) => d > 16.7).length,
      over33ms: deltas.filter((d) => d > 33.4).length,
    }
  }

  function heapMB() {
    const m = performance.memory
    if (!m) return { used: null, total: null }
    return { used: +(m.usedJSHeapSize / 1048576).toFixed(1), total: +(m.totalJSHeapSize / 1048576).toFixed(1) }
  }

  function gpuInfo() {
    try {
      const canvas = document.createElement('canvas')
      const gl = canvas.getContext('webgl2') || canvas.getContext('webgl')
      if (!gl) return { renderer: null, vendor: null, note: '拿不到 WebGL 上下文' }
      const ext = gl.getExtension('WEBGL_debug_renderer_info')
      return {
        renderer: ext ? String(gl.getParameter(ext.UNMASKED_RENDERER_WEBGL)) : String(gl.getParameter(gl.RENDERER)),
        vendor: ext ? String(gl.getParameter(ext.UNMASKED_VENDOR_WEBGL)) : String(gl.getParameter(gl.VENDOR)),
        note: ext ? null : '没有 WEBGL_debug_renderer_info（拿的是笼统 renderer）',
      }
    } catch (e) {
      return { renderer: null, vendor: null, note: '探测抛异常：' + String(e) }
    }
  }

  const scroller = () => document.querySelector('.results__scroller')
  const domRows = () => document.querySelectorAll('.results__row').length
  const metaText = () => {
    const el = document.querySelector('.results__meta')
    return el ? el.textContent.replace(/\s+/g, ' ').trim() : ''
  }
  /** 从状态行读行高（行高来自令牌生成物，前端不写死）——读不到就返回 null，不猜 */
  function rowHeightPx() {
    const m = /行高\s*([\d.]+)\s*px/.exec(metaText())
    return m ? Number.parseFloat(m[1]) : null
  }

  async function waitFor(fn, timeoutMs, label) {
    const deadline = now() + timeoutMs
    while (now() < deadline) {
      const v = fn()
      if (v) return v
      await sleep(100)
    }
    throw new Error('等待超时（' + label + '）：' + timeoutMs + ' ms')
  }

  function setInput(el, value) {
    el.value = String(value)
    el.dispatchEvent(new Event('input', { bubbles: true }))
  }

  /** 把网格换到指定行数并等它真的到位（总行数与渲染行都到位，再稳两帧） */
  let lastRows = null

  async function setRows(rows) {
    const inputs = document.querySelectorAll('.results__field input')
    if (inputs.length < 2) throw new Error('找不到行 / 列输入框（.results__field input）')
    if (rows === lastRows && domRows() > 0) {
      await nextFrame()
      return { rows, changed: false }
    }
    const t0 = now()
    setInput(inputs[0], rows)
    setInput(inputs[1], CFG.cols)
    await waitFor(() => domRows() > 0 && /本片\s*[1-9]/.test(metaText()), 120000, '换规模后的数据行')
    await waitFor(() => {
      const vp = document.querySelector('.results__viewport')
      if (!vp) return false
      const h = Number.parseFloat(vp.style.height || '0')
      const rh = rowHeightPx()
      return rh ? h >= rows * rh - 2 * rh : h > 0
    }, 60000, '总行数到位')
    lastRows = rows
    await nextFrame()
    await nextFrame()
    return { rows, changed: true, settleMs: +(now() - t0).toFixed(1) }
  }

  /** 规模 + 首屏 + IPC + 排序（滚动之前调用一次） */
  async function setup() {
    const out = { config: { ...CFG }, notes: [], errors: [] }

    await waitFor(() => scroller(), 60000, '结果网格挂载')
    out.gpu = gpuInfo()
    out.ua = navigator.userAgent
    out.devicePixelRatio = window.devicePixelRatio
    out.windowSize = { w: window.innerWidth, h: window.innerHeight }

    const invoke = window.__TAURI_INTERNALS__ && window.__TAURI_INTERNALS__.invoke
    if (typeof invoke !== 'function') throw new Error('这不是 Tauri 外壳：拿不到 __TAURI_INTERNALS__.invoke')
    out.backend = 'tauri'

    // ① 首屏：从「改规模」到「有行渲染出来」——含 Rust 侧生成 + 排序 + IPC + 首次布局
    const t0 = now()
    await setRows(CFG.rows)
    out.firstLoadMs = +(now() - t0).toFixed(1)
    out.meta = metaText()
    out.rowHeightPx = rowHeightPx()
    out.rowHeightSource = /回退值/.test(out.meta) ? 'fallback' : 'token'

    const sc = scroller()
    out.viewport = { w: sc.clientWidth, h: sc.clientHeight, scrollHeight: sc.scrollHeight }
    out.domRowsAfterMount = domRows()
    out.heapAfterMountMB = heapMB()

    // ② IPC 窗口取数：200 次顺序取 64 行（起点按行数均匀铺开，确定式）
    const windowMs = []
    for (let i = 0; i < CFG.windows; i += 1) {
      const start = Math.floor((i * (CFG.rows - CFG.windowRows)) / CFG.windows)
      const s = now()
      const payload = await invoke('grid_window', {
        rows: CFG.rows,
        cols: CFG.cols,
        seed: CFG.seed,
        orderDesc: false,
        start,
        len: CFG.windowRows,
      })
      const ms = now() - s
      if (!payload || !Array.isArray(payload.cells) || payload.cells.length === 0) {
        throw new Error('grid_window 在第 ' + i + ' 次没有回数据（start=' + start + '）')
      }
      if (payload.total !== CFG.rows) throw new Error('grid_window 回的 total = ' + payload.total + '，期望 ' + CFG.rows)
      windowMs.push(ms)
    }
    const ws = [...windowMs].sort((a, b) => a - b)
    out.windowIpc = {
      calls: windowMs.length,
      rowsPerCall: CFG.windowRows,
      p50Ms: +percentile(ws, 50).toFixed(3),
      p95Ms: +percentile(ws, 95).toFixed(3),
      maxMs: +(+ws[ws.length - 1]).toFixed(3),
      avgMs: +(windowMs.reduce((a, b) => a + b, 0) / windowMs.length).toFixed(3),
    }

    // ③ 排序：三次取数交替方向（换方向 ⇒ 必须重算置换）；第二遍起不含数据集生成
    const timeOnce = async (desc) => {
      const s = now()
      await invoke('grid_window', { rows: CFG.rows, cols: CFG.cols, seed: CFG.seed, orderDesc: desc, start: 0, len: CFG.windowRows })
      return +(now() - s).toFixed(1)
    }
    const sortA = await timeOnce(true)
    const sortB = await timeOnce(false)
    const sortC = await timeOnce(true)
    out.sortMs = { firstRun: sortA, otherDirection: sortB, secondRunSameDirection: sortC }
    out.sortSecondRunMs = sortC

    return out
  }

  /** 空转档：不滚动、只等帧（有 40 万行的滚动容器在盘上）—— 用来把「宿主帧节奏」与「滚动成本」分开 */
  async function idle() {
    await setRows(CFG.rows)
    const deltas = []
    let prev = now()
    for (let i = 0; i < CFG.idleFrames; i += 1) {
      await nextFrame()
      const t = now()
      deltas.push(t - prev)
      prev = t
    }
    return {
      phase: 'idle',
      rows: lastRows,
      stats: frameStats(deltas),
      domRows: domRows(),
      heapMB: heapMB(),
      meta: metaText(),
    }
  }

  /** 滚动档（指定行数）；协议与基准台一致：预热 → 归零 → 逐帧记录 */
  async function scroll(rows) {
    const target = rows === undefined ? CFG.rows : rows
    const settle = await setRows(target)
    const sc = scroller()
    if (!sc) throw new Error('结果网格不在盘上（.results__scroller 消失）')
    const maxScroll = Math.max(0, sc.scrollHeight - sc.clientHeight)
    const notes = []

    const longTasks = []
    let observer = null
    try {
      observer = new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) longTasks.push(entry.duration)
      })
      observer.observe({ entryTypes: ['longtask'] })
    } catch (e) {
      notes.push('longtask 观测不可用：' + String(e))
    }

    for (let i = 0; i < CFG.warmup; i += 1) {
      sc.scrollTop = Math.min(maxScroll, sc.scrollTop + CFG.stepPx)
      await nextFrame()
    }
    sc.scrollTop = 0
    await nextFrame()

    const deltas = []
    let prev = now()
    for (let i = 0; i < CFG.frames; i += 1) {
      sc.scrollTop = Math.min(maxScroll, (i + 1) * CFG.stepPx)
      await nextFrame()
      const t = now()
      deltas.push(t - prev)
      prev = t
    }
    if (observer) observer.disconnect()

    return {
      phase: 'scroll',
      rows: target,
      settle,
      stats: frameStats(deltas),
      maxScrollPx: maxScroll,
      stepPx: CFG.stepPx,
      domRows: domRows(),
      scrollTopAfter: Math.round(sc.scrollTop),
      heapMB: heapMB(),
      longTasks: {
        count: longTasks.length,
        totalMs: +longTasks.reduce((a, b) => a + b, 0).toFixed(1),
        maxMs: +(longTasks.length ? Math.max(...longTasks) : 0).toFixed(1),
      },
      rowHeightPx: rowHeightPx(),
      viewport: { w: sc.clientWidth, h: sc.clientHeight },
      meta: metaText(),
      notes,
    }
  }

  /** 宿主把 `__TAURI_INTERNALS__.invoke` 定义成**不可写且不可配置**（第 29 轮实测描述符
   *  `writable:false, configurable:false`）⇒ **在页面里替换它做不到**：sloppy mode 下直接赋值
   *  **静默失效**、`defineProperty` 抛 `Cannot redefine property: invoke`。第 28 轮的「IPC 隔离档」
   *  正是栽在这里（量了与基线完全一样的东西、却报出「IPC 无关」）。本函数把这条事实**当场探一遍**
   *  并进读数 —— 以后换任何别的消融设计，这条证据都还在。 */
  function probeInvokePatchability() {
    const out = { target: '__TAURI_INTERNALS__.invoke', descriptor: null, definePropertyOk: null, restored: null, note: null }
    try {
      const internals = window.__TAURI_INTERNALS__
      const original = internals.invoke
      const d = Object.getOwnPropertyDescriptor(internals, 'invoke') || {}
      out.descriptor = {
        writable: d.writable === undefined ? null : d.writable,
        configurable: d.configurable === undefined ? null : d.configurable,
        accessor: !!(d.get || d.set),
      }
      try {
        Object.defineProperty(internals, 'invoke', { value: () => {}, configurable: true, writable: true })
        out.definePropertyOk = true
        Object.defineProperty(internals, 'invoke', { value: original, configurable: true, writable: true })
        out.restored = Object.is(internals.invoke, original)
        out.note = '宿主允许替换 ⇒ 理论上可做「本地立即返回」消融（本档没做，见 README）'
      } catch (e) {
        out.definePropertyOk = false
        out.note =
          '宿主不允许替换（' + String(e && e.message ? e.message : e) +
          '）⇒ 页面内无法消融 IPC；要量 IPC 成本只能走「滚动距离」这类不改代码的对照，或另编一个变体'
      }
    } catch (e) {
      out.note = '探测抛异常：' + String(e)
    }
    return out
  }

  /** **消融档：慢速滚动**（1px/帧，240 帧共 240px）。它不碰页面里的任何补丁（宿主不许），
   *  只用「滚动距离」这一个可调项把**内容更新率**压到约 1/26：窗口每 ~26 帧才真的换一次
   *  （`plan.start` 变化），其余帧产品**照样**每帧发一次窗口取数、照样跑响应式与 vnode 比对，
   *  而 DOM 文本不变 ⇒ **IPC / 响应式 / diff / 滚动成本全在，DOM 写入基本没有**。
   *  与同轮的基线档成对读：`基线 − 本档` ≈ 每帧把「重建好的可视行 DOM」写下去的成本。
   *  **本档不参与协议常量对齐**（步长与基准台不同）—— 它只做同轮内的一对，不做跨台比较。 */
  async function scrollSlow(rows) {
    const target = rows === undefined ? CFG.rows : rows
    const settle = await setRows(target)
    const sc = scroller()
    if (!sc) throw new Error('结果网格不在盘上（.results__scroller 消失）')
    const deltas = []
    let windowShifts = 0
    let lastStart = null
    let prev = now()
    for (let i = 0; i < CFG.frames; i += 1) {
      sc.scrollTop = i + 1
      await nextFrame()
      const t = now()
      deltas.push(t - prev)
      prev = t
      const m = /窗口\s*(\d+)/.exec(metaText())
      const s = m ? m[1] : null
      if (s !== lastStart) {
        windowShifts += 1
        lastStart = s
      }
    }
    return {
      phase: 'scroll-slow',
      rows: target,
      settle,
      stats: frameStats(deltas),
      stepPx: 1,
      scrollTopAfter: Math.round(sc.scrollTop),
      windowShifts,
      rowHeightPx: rowHeightPx(),
      domRows: domRows(),
      heapMB: heapMB(),
      meta: metaText(),
      notes: ['本档专用：步长 1px/帧（把内容更新率压到约 1/26），不参与协议常量对齐'],
    }
  }

  // ───────────────────── 样式消融档（第 30 轮加：不改产品代码的候选消融） ─────────────────────

  const ABLATION_STYLE_ID = 'doyah-ablation'

  /** 产品样式是 scoped 的（选择器带 `data-v-*` 属性）⇒ 注入的同名类选择器**特异性更低、不会生效**。
   *  这里从真实节点的属性里**取**那个哈希，拼出同特异性选择器，再靠「注入的 `<style>` 后置」胜出。
   *  取不到就退回类选择器（并在读数里体现：`ablation.proof` 会显示它到底生没生效）。 */
  function scoped(sel) {
    const el = document.querySelector(sel)
    if (!el) return sel
    for (const a of Array.from(el.attributes)) if (a.name.startsWith('data-v-')) return sel + '[' + a.name + ']'
    return sel
  }

  /** 注入 / 清除消融样式（`css` 为 null 即清除）。返回注入文本，便于进读数。 */
  function setAblation(css) {
    const old = document.getElementById(ABLATION_STYLE_ID)
    if (old) old.remove()
    if (!css) return null
    const style = document.createElement('style')
    style.id = ABLATION_STYLE_ID
    style.textContent = css
    document.head.appendChild(style)
    return css
  }

  /** 消融是否**真的**生效 —— 取**计算后取值**（不是「我注入了所以它该生效」）。
   *  第 29 轮的教训：那一档「替换 invoke」从未生效、却出了读数；这一条就是防它重演。 */
  function ablationProof() {
    const row = document.querySelector('.results__row')
    const cell = document.querySelector('.results__cell')
    const g = (el, prop) => (el ? getComputedStyle(el).getPropertyValue(prop) : null)
    return {
      styleTagInDom: !!document.getElementById(ABLATION_STYLE_ID),
      rowContain: g(row, 'contain'),
      rowVisibility: g(row, 'visibility'),
      rowTransform: g(row, 'transform'),
      cellTextOverflow: g(cell, 'text-overflow'),
      cellContain: g(cell, 'contain'),
      cellsInRow: row ? row.children.length : null,
      domRows: domRows(),
    }
  }

  /** **样式消融档**：注入 css → 跑**同一套**滚动协议（直接调 `scroll()`，不另抄一份协议）→ 还原样式。
   *  结果里带 `ablation.proof`（该行 / 该格的**计算后取值**）—— 消融没生效不许当读数。
   *  口径：与同轮基线档成对读；本档只做同轮内的一对，不做跨台比较。 */
  async function scrollAblated(rows, css, label) {
    setAblation(css)
    await nextFrame()
    await nextFrame()
    const proof = ablationProof()
    let out = null
    try {
      out = await scroll(rows)
    } finally {
      setAblation(null)
    }
    out.phase = 'scroll-ablate'
    out.ablation = { label, css, proof }
    return out
  }

  /** **变异探针档**：同一套协议（同样调 `scroll()`）+ MutationObserver，数**每帧到底写下去多少**
   *  （新增 / 删除 / 文本 / 属性）。它是「布局 / 样式重算引擎计数」的交叉印证：若每帧 DOM 变异极少
   *  而布局照旧 20+ ms，那成本就不在「写 DOM」上。**本档自带观测开销**（如实记进 notes）——
   *  故它的帧耗时只与同轮基线档比大小，不当成「去掉观测的纯值」。 */
  async function mutationProbe(rows) {
    const host = document.querySelector('.results__viewport') || document.body
    const counts = { childList: 0, characterData: 0, attributes: 0, addedNodes: 0, removedNodes: 0, attributeNames: {} }
    const addedByTag = {}
    const removedByTag = {}
    const targetsByClass = {}
    const bump = (m, k) => {
      m[k] = (m[k] || 0) + 1
    }
    const nameOf = (n) => (n.nodeType === 3 ? '#text' : n.nodeName)
    const classOf = (el) => (el && el.className ? String(el.className).replace(/\s+/g, '.').slice(0, 40) : '(no-class)')
    const obs = new MutationObserver((records) => {
      for (const r of records) {
        if (r.type === 'childList') {
          counts.childList += 1
          counts.addedNodes += r.addedNodes.length
          counts.removedNodes += r.removedNodes.length
          bump(targetsByClass, classOf(r.target))
          for (const n of Array.from(r.addedNodes)) bump(addedByTag, nameOf(n))
          for (const n of Array.from(r.removedNodes)) bump(removedByTag, nameOf(n))
        } else if (r.type === 'characterData') {
          counts.characterData += 1
        } else if (r.type === 'attributes') {
          counts.attributes += 1
          const n = r.attributeName || '?'
          counts.attributeNames[n] = (counts.attributeNames[n] || 0) + 1
          bump(targetsByClass, classOf(r.target))
        }
      }
    })
    obs.observe(host, { childList: true, subtree: true, characterData: true, attributes: true })
    let out = null
    try {
      out = await scroll(rows)
    } finally {
      obs.disconnect()
    }
    const f = CFG.warmup + (out.stats.frames || 0)
    out.phase = 'mutations'
    out.mutations = {
      ...counts,
      framesCounted: f,
      addedByTag,
      removedByTag,
      targetsByClass,
      perFrame: {
        childList: +(counts.childList / f).toFixed(2),
        addedNodes: +(counts.addedNodes / f).toFixed(2),
        removedNodes: +(counts.removedNodes / f).toFixed(2),
        characterData: +(counts.characterData / f).toFixed(2),
        attributes: +(counts.attributes / f).toFixed(2),
      },
    }
    out.notes.push('本档带 MutationObserver 观测开销（计 ' + f + ' 帧：预热 ' + CFG.warmup + ' + 测量 ' + out.stats.frames + '）')
    return out
  }
  globalThis.__DOYAH_WV2_BENCH__ = {
    config: CFG,
    setup,
    idle,
    scroll,
    scrollSlow,
    probeInvokePatchability,
    scrollAblated,
    mutationProbe,
    scoped,
    ablationProof,
  }
})()
