/**
 * WebView2 + GPU 基准复测仪器（platform/windows/Bench/webview2/bench.mjs）
 *
 * 由头：`Bench/grid` 的读数是**无头 + 软件光栅**、且不含 IPC 与 GPU 合成 ⇒ §8.5.6-3 的
 * 「三候选取舍」一直挂着「正式基准待表示层落地后在 WebView2 上复测」。本仪器就是那次复测：
 * 起**真外壳**（`config-windows targets` 的发布产物 `doyah-studio.exe`，WebView2 承载 `App/dist`），
 * 用 CDP 注入 `driver.js`，在真窗口里量 40 万行 × 20 列的结果网格。
 *
 * 零依赖：只用 Node 自带的 `fetch` / `WebSocket` / `child_process`（Node ≥ 22）。
 *
 * 用法：
 *   node bench.mjs                              # 用默认产物路径与默认端口
 *   node bench.mjs --exe <exe> --out <json> --port 9333
 *
 * 退出码：0 = 量到了 / 1 = 失败（起不来、驱动抛异常、读数缺失）/ 3 = 找不到页面目标。
 *
 * **前提（两条，都踩过）**：
 *   1. 发布产物要先构建，且前端产物**先于** `cargo build`（Tauri 编译期把 `frontendDist` 嵌进产物）。
 *   2. 产物必须是**生产形态** —— 即带 `custom-protocol` 特性：
 *      `cargo build --release --workspace --features doyah-studio-shell/custom-protocol`。
 *      **不带它编出来的二进制会去连 `devUrl`（http://localhost:5274）**，盘上没有 dev server 时页面
 *      是空的 ⇒ 本仪器打印 `NO_PAGE`（第一次实测就是这么栽的）。`platform/windows/Tools/build.ps1` 已按
 *      生产形态构建。
 */
import { spawn } from 'node:child_process'
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { tmpdir } from 'node:os'

const HERE = dirname(fileURLToPath(import.meta.url))

function parseArgs(argv) {
  const out = {
    exe: resolve(HERE, '../../target/release/doyah-studio.exe'),
    out: resolve(HERE, '../../target/webview2-bench.json'),
    port: 9444,
    quick: false,
  }
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i]
    if (a === '--exe') out.exe = resolve(argv[++i])
    else if (a === '--out') out.out = resolve(argv[++i])
    else if (a === '--port') out.port = Number(argv[++i])
    // `--quick`：只跑「空转 + 基线滚动 + 基线复跑」——供**两个产物在同一轮里交替 A/B**（跨轮漂移 >50%，
    // 见 README 限制 1 ⇒ 只有交替跑出来的成对数才可比）。
    else if (a === '--quick') out.quick = true
    else throw new Error('未知参数：' + a)
  }
  return out
}

const ARGS = parseArgs(process.argv.slice(2))
const BASE = 'http://127.0.0.1:' + ARGS.port

function log(msg) {
  process.stdout.write(msg + '\n')
}

async function listTargets() {
  const r = await fetch(BASE + '/json/list')
  return await r.json()
}

class Cdp {
  constructor(ws) {
    this.ws = ws
    this.id = 0
    this.pending = new Map()
    this.events = []
    ws.addEventListener('message', (ev) => {
      const m = JSON.parse(ev.data)
      if (m.id && this.pending.has(m.id)) {
        const { resolve: res, reject: rej } = this.pending.get(m.id)
        this.pending.delete(m.id)
        if (m.error) rej(new Error('CDP 错误（' + m.error.message + '）'))
        else res(m.result)
      } else if (m.method) {
        this.events.push(m)
      }
    })
  }

  send(method, params = {}, timeoutMs = 200000) {
    this.id += 1
    const id = this.id
    return new Promise((res, rej) => {
      const timer = setTimeout(() => {
        this.pending.delete(id)
        rej(new Error('CDP 调用超时：' + method))
      }, timeoutMs)
      this.pending.set(id, {
        resolve: (v) => {
          clearTimeout(timer)
          res(v)
        },
        reject: (e) => {
          clearTimeout(timer)
          rej(e)
        },
      })
      this.ws.send(JSON.stringify({ id, method, params }))
    })
  }

  async evaluate(expression, timeoutMs = 200000) {
    const r = await this.send(
      'Runtime.evaluate',
      { expression, awaitPromise: true, returnByValue: true },
      timeoutMs,
    )
    if (r.exceptionDetails) {
      const d = r.exceptionDetails
      throw new Error('页面异常：' + (d.exception && d.exception.description ? d.exception.description : JSON.stringify(d)))
    }
    return r.result ? r.result.value : null
  }

  /** Chromium 自己的引擎计数（布局 / 样式重算 / 脚本 / 堆）——比单一帧耗时更能说明成本落在哪 */
  async metrics() {
    const r = await this.send('Performance.getMetrics')
    const map = {}
    for (const m of r.metrics) map[m.name] = m.value
    return map
  }
}

function metricDelta(before, after, key) {
  if (before[key] === undefined || after[key] === undefined) return null
  return +(after[key] - before[key]).toFixed(4)
}

/**
 * 协议对齐（跑之前自证）：本仪器与 `Bench/grid` 量的是同一件事，**三个协议常量必须逐值相同** ——
 * 两侧各手写一遍协议是本仓反复吃亏的「同一份事实两处手抄」形态：一侧改了、另一侧不知道，
 * 读数从此不可比而没有任何东西会红。解析不到也算失败（空跑不许通过）。
 */
function assertProtocolParity() {
  const benchText = readFileSync(resolve(HERE, '../grid/src/bench.ts'), 'utf8')
  const driverText = readFileSync(resolve(HERE, 'driver.js'), 'utf8')

  const evalConst = (expr) => {
    const parts = expr.split('*').map((p) => Number(p.trim()))
    if (parts.some((n) => !Number.isFinite(n))) throw new Error('不是常量表达式：' + expr)
    return parts.reduce((a, b) => a * b, 1)
  }
  const must = (src, re, label) => {
    const m = re.exec(src)
    if (!m) throw new Error('解析不到 ' + label)
    return m[1]
  }

  const pairs = [
    ['测量帧数', evalConst(must(benchText, /opts\.frames\s*\?\?\s*([\d\s*]+)/, 'bench.ts 帧数')), Number(must(driverText, /frames:\s*(\d+)/, 'driver.js 帧数'))],
    ['滚动步长', evalConst(must(benchText, /opts\.stepPx\s*\?\?\s*([\d\s*]+)/, 'bench.ts 步长')), Number(must(driverText, /stepPx:\s*(\d+)/, 'driver.js 步长'))],
    ['预热帧数', evalConst(must(benchText, /opts\.warmup\s*\?\?\s*([\d\s*]+)/, 'bench.ts 预热')), Number(must(driverText, /warmup:\s*(\d+)/, 'driver.js 预热'))],
  ]

  const bad = pairs.filter(([, a, b]) => a !== b)
  log(
    '   协议对齐（基准台 ⇄ 本仪器）：' +
      pairs.map(([name, a, b]) => name + ' ' + a + (a === b ? '=' : '≠') + b).join(' · '),
  )
  if (bad.length > 0) {
    log('PROTOCOL_DRIFT：协议常量不一致（' + bad.map(([n]) => n).join('、') + '）—— 两侧读数不可比，先对齐再跑')
    return false
  }
  return true
}

/** 进程树内存采样（Node 这边只能靠 tasklist/CIM；口径 = 估算，见 README 限制） */
function makeMemorySampler(parentPid) {
  const ps1 = resolve(HERE, 'tree-memory.ps1')
  let peakMb = 0
  let last = null
  let stopped = false
  const samples = []

  async function sampleOnce() {
    const out = await new Promise((res) => {
      const p = spawn('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps1, '-ParentPid', String(parentPid)], {
        stdio: ['ignore', 'pipe', 'ignore'],
      })
      let buf = ''
      p.stdout.on('data', (d) => (buf += d))
      p.on('error', () => res(null))
      p.on('close', () => res(buf.trim()))
    })
    if (!out) return null
    try {
      const parsed = JSON.parse(out)
      const mb = +(parsed.workingSetBytes / 1048576).toFixed(1)
      samples.push(mb)
      if (mb > peakMb) peakMb = mb
      last = parsed
      return mb
    } catch (e) {
      return null
    }
  }

  return {
    async start() {
      await sampleOnce()
      const timer = setInterval(() => {
        if (!stopped) sampleOnce()
      }, 500)
      return () => {
        stopped = true
        clearInterval(timer)
      }
    },
    async finish() {
      await sampleOnce()
      return {
        peakMb,
        lastProcesses: last ? last.processes : null,
        lastMb: last ? +(last.workingSetBytes / 1048576).toFixed(1) : null,
        samples: samples.length,
      }
    },
  }
}

async function main() {
  const driver = readFileSync(resolve(HERE, 'driver.js'), 'utf8')

  log('== WebView2 + GPU 基准复测（真外壳）')
  log('   exe  = ' + ARGS.exe)
  log('   端口 = ' + ARGS.port)

  if (!assertProtocolParity()) process.exit(1)

  const profile = resolve(tmpdir(), 'doyah-wv2-bench-profile')
  mkdirSync(profile, { recursive: true })

  const child = spawn(ARGS.exe, [], {
    env: {
      ...process.env,
      // WebView2 的调试端口靠这个环境变量传给宿主（Tauri 不暴露 devtools 开关）。
      // 后两个开关是基准口径：窗口被别的窗口遮挡 / 不在前台时 Chromium 会把 rAF 降到 1Hz，
      // 不加就量的是「被节流后的帧率」而不是渲染能力（真机前台使用不受影响）—— 见 README 限制。
      WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS:
        '--remote-debugging-port=' + ARGS.port + ' --disable-backgrounding-occluded-windows --disable-renderer-backgrounding',
      WEBVIEW2_USER_DATA_FOLDER: profile,
    },
    stdio: 'ignore',
  })
  child.on('error', (e) => {
    log('启动失败：' + e.message)
    process.exit(1)
  })

  const sampler = makeMemorySampler(child.pid)
  const stopSampling = await sampler.start()

  let page = null
  const deadline = Date.now() + 60000
  while (!page && Date.now() < deadline) {
    try {
      const targets = await listTargets()
      // 只认真外壳的页面目标：Tauri 2 在 Windows 上把前端产物的来源标成 `tauri://localhost`
      // （老版本 / 兼容模式可能是 `http://tauri.localhost`）。**不认任何 http://localhost:xxxx** ——
      // 那是**别的**调试端点（先例：上一轮无头基准台占着 vite 端口），连上去量的是别的页面。
      page = (targets || []).find(
        (t) => t.type === 'page' && /^(tauri:|https?:\/\/tauri\.localhost)/i.test(t.url || ''),
      )
    } catch (e) {
      /* 宿主还没起来 */
    }
    if (!page) await new Promise((r) => setTimeout(r, 1000))
  }
  if (!page) {
    log('NO_PAGE：60 s 内没拿到真外壳的页面调试目标（只认 tauri://localhost）')
    stopSampling()
    child.kill()
    process.exit(3)
  }
  log('   页面 = ' + page.url)

  const ws = await new Promise((res, rej) => {
    const sock = new WebSocket(page.webSocketDebuggerUrl)
    sock.addEventListener('open', () => res(sock))
    sock.addEventListener('error', () => rej(new Error('连不上页面调试端点')))
  })
  const cdp = new Cdp(ws)
  await cdp.send('Runtime.enable')
  await cdp.send('Performance.enable')

  // 连上之后先自证「这是真外壳」：不是的话立刻停，别拿别的页面出读数
  const isShell = await cdp.evaluate('!!window.__TAURI_INTERNALS__')
  if (!isShell) {
    log('NOT_THE_SHELL：连上的页面没有 __TAURI_INTERNALS__（' + page.url + '）')
    ws.close()
    stopSampling()
    child.kill()
    process.exit(1)
  }

  await cdp.evaluate(driver)
  const hasDriver = await cdp.evaluate('!!globalThis.__DOYAH_WV2_BENCH__')
  if (!hasDriver) {
    log('DRIVER_NOT_INSTALLED：注入后拿不到 __DOYAH_WV2_BENCH__')
    ws.close()
    stopSampling()
    child.kill()
    process.exit(1)
  }

  const result = { instrument: 'platform/windows/Bench/webview2/bench.mjs', when: new Date().toISOString() }

  log('== ① 规模 + 首屏 + IPC + 排序（含数据生成与排序置换）')
  const setup = await cdp.evaluate('globalThis.__DOYAH_WV2_BENCH__.setup()')
  Object.assign(result, setup)
  log('   首屏 ' + setup.firstLoadMs + ' ms · GPU renderer = ' + (setup.gpu && setup.gpu.renderer))
  log('   IPC 取 64 行 p50 ' + setup.windowIpc.p50Ms + ' ms / p95 ' + setup.windowIpc.p95Ms + ' ms')
  log('   排序（第二遍）' + setup.sortSecondRunMs + ' ms')

  // 逐档测量：每档前后各取一次 Chromium 引擎计数 ⇒ 该档自己的布局 / 样式重算 / 脚本成本
  async function phase(label, expression) {
    const before = await cdp.metrics()
    const value = await cdp.evaluate(expression)
    const after = await cdp.metrics()
    const engine = {
      layoutCount: metricDelta(before, after, 'LayoutCount'),
      layoutMs: metricDelta(before, after, 'LayoutDuration'),
      recalcStyleCount: metricDelta(before, after, 'RecalcStyleCount'),
      recalcStyleMs: metricDelta(before, after, 'RecalcStyleDuration'),
      scriptMs: metricDelta(before, after, 'ScriptDuration'),
      taskMs: metricDelta(before, after, 'TaskDuration'),
      jsHeapUsedMB: after.JSHeapUsedSize ? +(after.JSHeapUsedSize / 1048576).toFixed(1) : null,
      domNodes: after.Nodes === undefined ? null : after.Nodes,
      layoutObjects: after.LayoutObjects === undefined ? null : after.LayoutObjects,
    }
    log(
      '   [' + label + '] 帧 p50 ' + value.stats.p50Ms + ' ms / p95 ' + value.stats.p95Ms + ' ms · ' +
        value.stats.fps + ' fps · 超 16.7ms ' + value.stats.over16ms + '/' + value.stats.frames +
        ' · DOM 行 ' + value.domRows + ' · 布局 ' + engine.layoutMs + ' s / ' + engine.layoutCount + ' 次 · 样式重算 ' +
        engine.recalcStyleMs + ' s / ' + engine.recalcStyleCount + ' 次',
    )
    return { label, measured: value, engine }
  }

  if (ARGS.quick) log('   （--quick：只跑空转 + 基线滚动 + 基线复跑，供两个产物交替 A/B）')

  log('== ② 空转帧节奏（不滚动；对照档）')
  const phases = []
  phases.push(await phase('idle@400000', 'globalThis.__DOYAH_WV2_BENCH__.idle()'))

  log('== ③ 滚动 ' + setup.config.frames + ' 帧 × 三档行数（步长 ' + setup.config.stepPx + 'px，预热 ' + setup.config.warmup + ' 帧）')
  for (const rows of setup.config.scrollRows) {
    if (ARGS.quick && rows !== setup.config.rows) continue
    phases.push(await phase('scroll@' + rows, 'globalThis.__DOYAH_WV2_BENCH__.scroll(' + rows + ')'))
  }

  /** 样式消融档：注入同特异性 CSS（页面里现取 `data-v-*` 拼选择器）→ 跑**同一套**协议（`scroll()` 本体） */
  const ablate = (name, sel, decl) =>
    phase(
      'scroll@' + setup.config.rows + '+ablate:' + name,
      'globalThis.__DOYAH_WV2_BENCH__.scrollAblated(' + setup.config.rows + ', ' +
        "globalThis.__DOYAH_WV2_BENCH__.scoped('" + sel + "') + ' { " + decl + " }', '" + name + "')",
    )

  if (!ARGS.quick) {
    log('== ④ 样式消融档（不改产品代码：只注入 CSS；读数带 ablation.proof 的计算后取值当实证）')
    phases.push(await ablate('contain-row', '.results__row', 'contain: layout paint'))
    phases.push(await ablate('clip-cell', '.results__cell', 'text-overflow: clip'))
    phases.push(await ablate('hidden-rows', '.results__row', 'visibility: hidden'))
    phases.push(await ablate('contain-cell', '.results__cell', 'contain: layout paint'))
  }

  log('== ' + (ARGS.quick ? '④' : '⑤') + ' 变异探针档（同一套协议 + MutationObserver：数每帧到底写下去多少）')
  phases.push(await phase('mutations@' + setup.config.rows, 'globalThis.__DOYAH_WV2_BENCH__.mutationProbe(' + setup.config.rows + ')'))

  if (!ARGS.quick) {
    log('== ⑥ 消融档：慢速滚动（步长 1px/帧 ⇒ 窗口每 ~26 帧才换一次；IPC / 响应式 / diff 全在，DOM 写入基本没有）')
    phases.push(
      await phase('scroll@' + setup.config.rows + '+slow-scroll', 'globalThis.__DOYAH_WV2_BENCH__.scrollSlow(' + setup.config.rows + ')'),
    )
  }

  log('== ' + (ARGS.quick ? '④' : '⑦') + ' 基线复跑（同轮内对照 —— 单次读数的轮间波动可观，跨轮两个数相减不可信）')
  phases.push(await phase('scroll@' + setup.config.rows + '+repeat', 'globalThis.__DOYAH_WV2_BENCH__.scroll(' + setup.config.rows + ')'))

  // 页面内能否消融 IPC 路径：宿主把 `__TAURI_INTERNALS__.invoke` 定义为不可写 + 不可配置
  // ⇒ 第 28 轮那种「替换 invoke」的消融**做不到**（赋值静默失效）。这条事实进读数，免得下一个人再试一次。
  result.invokePatchability = await cdp.evaluate('globalThis.__DOYAH_WV2_BENCH__.probeInvokePatchability()')
  log(
    '   invoke 可替换性：descriptor=' + JSON.stringify(result.invokePatchability.descriptor) +
      ' · definePropertyOk=' + result.invokePatchability.definePropertyOk,
  )

  result.phases = phases
  const scroll400k = phases.find((p) => p.label === 'scroll@' + setup.config.rows)
  const idle400k = phases.find((p) => p.label.startsWith('idle@'))
  const slowScroll = phases.find((p) => p.label.endsWith('+slow-scroll'))
  const repeatRun = phases.find((p) => p.label.endsWith('+repeat'))
  const smallest = phases.filter((p) => /^scroll@\d+$/.test(p.label)).slice(-1)[0]

  const mem = await sampler.finish()
  stopSampling()
  result.processTreeMemory = mem

  log('   进程树峰值 ' + mem.peakMb + ' MB（估算，含 WebView2 子进程）')

  mkdirSync(dirname(ARGS.out), { recursive: true })
  writeFileSync(ARGS.out, JSON.stringify(result, null, 2) + '\n', 'utf8')
  log('   读数已落盘：' + ARGS.out)

  const s400 = scroll400k.measured.stats
  const idle = idle400k.measured.stats
  // 汇总行按**实际跑过的档**拼（`--quick` 少了消融 / 慢速档 —— 缺档不许静默打印成 0）
  const parts = [
    'WEBVIEW2_GRID_BENCH rows=' + setup.config.rows + ' cols=' + setup.config.cols,
    'idle400k_p50_ms=' + idle.p50Ms,
    'scroll400k_p50_ms=' + s400.p50Ms,
    'scroll400k_p95_ms=' + s400.p95Ms,
    'scroll400k_avg_ms=' + s400.avgMs,
    'fps=' + s400.fps,
    'over16=' + s400.over16ms + '/' + s400.frames,
    'dom_rows=' + scroll400k.measured.domRows,
    'first_load_ms=' + setup.firstLoadMs,
    'ipc64_p50_ms=' + setup.windowIpc.p50Ms,
    'ipc64_p95_ms=' + setup.windowIpc.p95Ms,
    'sort_ms=' + setup.sortSecondRunMs,
    'tree_peak_mb=' + mem.peakMb,
    'layout400k_ms=' + scroll400k.engine.layoutMs,
    'recalc_style400k_ms=' + scroll400k.engine.recalcStyleMs,
    'smallest_scroll_' + smallest.measured.rows + '_p50_ms=' + smallest.measured.stats.p50Ms,
  ]
  for (const p of phases.filter((x) => x.label.includes('+ablate:'))) {
    parts.push('ablate_' + p.label.replace(/^.*\+ablate:/, '') + '_p50_ms=' + p.measured.stats.p50Ms)
    parts.push('ablate_' + p.label.replace(/^.*\+ablate:/, '') + '_layout_ms=' + p.engine.layoutMs)
  }
  const mut = phases.find((p) => p.label.startsWith('mutations@'))
  if (mut) {
    parts.push('mutations_per_frame_added=' + mut.measured.mutations.perFrame.addedNodes)
    parts.push('mutations_per_frame_chardata=' + mut.measured.mutations.perFrame.characterData)
    parts.push('mutations_per_frame_attrs=' + mut.measured.mutations.perFrame.attributes)
    parts.push('mutations_attr_names=' + JSON.stringify(mut.measured.mutations.attributeNames))
  }
  if (slowScroll) {
    parts.push('slow_scroll400k_p50_ms=' + slowScroll.measured.stats.p50Ms)
    parts.push('slow_scroll_window_shifts=' + slowScroll.measured.windowShifts)
  }
  if (repeatRun) parts.push('baseline_repeat400k_p50_ms=' + repeatRun.measured.stats.p50Ms)
  parts.push('invoke_patchable=' + result.invokePatchability.definePropertyOk)
  parts.push('renderer=' + (setup.gpu && setup.gpu.renderer))
  log(parts.join(' '))

  // 收尾：先请页面自己关，关不掉再由本仪器按 pid 收 —— 只杀**本仪器起的那个进程**
  try {
    ws.send(JSON.stringify({ id: 999999, method: 'Page.close', params: {} }))
  } catch (e) {
    /* 忽略 */
  }
  await new Promise((r) => setTimeout(r, 2000))
  if (child.exitCode === null) child.kill()
  await new Promise((r) => setTimeout(r, 1500))
  if (child.exitCode === null) {
    await new Promise((res) => {
      const p = spawn('taskkill', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore' })
      p.on('close', () => res())
      p.on('error', () => res())
    })
  }
  try {
    ws.close()
  } catch (e) {
    /* 忽略 */
  }
  process.exit(0)
}

main().catch((e) => {
  log('FAILED：' + (e && e.stack ? e.stack : String(e)))
  process.exit(1)
})
