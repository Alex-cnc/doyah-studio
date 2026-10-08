#!/usr/bin/env node
// devtools-shot.mjs — 从**已在跑**的 WebView2 / Chromium 的 CDP 端点抓图。
//
// 片号：S-073b 起（T-20261007-073 第①条）· S-073d 扩（同一锚点：CDP 驱动切视图 + 连抓截图集）。
// 用途：cron / 无人会话里给「该包实跑实例」截图 —— computer_use 的 click/type 会被审批门拒
//      （无人可批），所以必须有这条**可脚本化、免审批**的通道。
//
// 只用 Node 内建：全局 fetch + 全局 WebSocket + node:fs（Node >= 22）。**不引任何外部依赖**
// （卡面禁区：不许 `npm i ws`）。
//
// 两种模式（由 `--out` 的形状自动分）：
//
//   ① 单张（S-073b 原样，向后兼容）：
//        node devtools-shot.mjs --port 9222 --out D:/path/shot.png
//      → 抓当前那一屏到指定 PNG。
//
//   ② 步骤集（S-073d）：`--out` 给**目录**，按**顺序**执行一组步骤
//      （切视图 / 点按钮 / 开命令面板 / 按键 / 等元素），**每到一个 shot 步抓一张**：
//        node devtools-shot.mjs --port 9222 --out D:/path/shots --tag beta1.0
//      → 产出一组 `NN-<屏名>-<包标签>-<HHMM>.png`。
//      步骤集缺省 = 本文件内建的 073 三条屏（工作区 / 数据库连接 / 终端）+ W-B「点前/点后」对
//      + 一张同视图复拍（证明抓图管线对同一 DOM 是确定性的）。要换一组就 `--set <file.json>`。
//
// 步骤集 JSON = 一个数组，元素按顺序执行，字段：
//   { "kind": "wait",     "ms": 900 }
//   { "kind": "click",    "selector": "...", "title": "...", "aria": "...", "text": "...", "optional": true }
//   { "kind": "palette",  "title": "新建连接" }         // Ctrl+K 开面板 → 点标题匹配的条目
//   { "kind": "key",      "key": "Escape" }
//   { "kind": "waitFor",  "selector": ".dlg", "absent": false, "timeoutMs": 8000, "optional": true }
//   { "kind": "eval",     "js": "( ... )" }
//   { "kind": "shot",     "name": "01-工作区", "expectSelector": ".ws" }
//   { "kind": "comment",  "note": "..." }               // 只打印，不动界面
//
// 成功：每张打印 `WROTE=<绝对路径> bytes=<n>`，末行 `SHOT_COUNT=<n>`，退出码 0
// 失败：打印 `FAIL=<一句原因>`，退出码 1（**不产半套静默成功的图**）

import { writeFileSync, mkdirSync, readFileSync, existsSync } from 'node:fs'
import { resolve, isAbsolute, join, dirname } from 'node:path'

function fail(reason) {
  process.stdout.write(`FAIL=${reason}\n`)
  process.exit(1)
}

function parseArgs(argv) {
  const out = { port: 9222, out: null, set: null, tag: 'pkg', settleMs: 0 }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    const next = () => argv[++i]
    if (a === '--port') out.port = Number(next())
    else if (a === '--out') out.out = next()
    else if (a === '--set') out.set = next()
    else if (a === '--tag') out.tag = next()
    else if (a === '--settle-ms') out.settleMs = Number(next())
    else if (a.startsWith('--port=')) out.port = Number(a.slice('--port='.length))
    else if (a.startsWith('--out=')) out.out = a.slice('--out='.length)
    else if (a.startsWith('--set=')) out.set = a.slice('--set='.length)
    else if (a.startsWith('--tag=')) out.tag = a.slice('--tag='.length)
  }
  return out
}

/** 文件名里不能出现的字符（Windows 一套）一律换成 `_`；空串回退 `pkg`。 */
function sanitizeTag(tag) {
  const cleaned = String(tag == null ? '' : tag)
    .replace(/[\\/:*?"<>|\s]+/g, '_')
    .replace(/^_+|_+$/g, '')
  return cleaned.length > 0 ? cleaned : 'pkg'
}

/** 本地时刻 `HHMM`（四个字符，用在文件名里）。 */
function hhmm() {
  const d = new Date()
  const p = (n) => String(n).padStart(2, '0')
  return `${p(d.getHours())}${p(d.getMinutes())}`
}

// ── 内建步骤集：T-20261007-073 的三条屏（W-A / W-B / W-C）+ W-B 点前对 + 同视图复拍 ──────────
//
// 每张图对应一条**界面路径**（点哪里到的那一屏）写进 `note`，运行时会打印出来，回帖里逐条抄。
// 选择器与 `App/src/shell/*.vue` 里的类名同源（只读产品代码，不改产品代码）。
const DEFAULT_SET = [
  { kind: 'comment', note: '等界面起来（WebView2 首帧 + appInfo/appearance 两次 IPC）' },
  { kind: 'wait', ms: 2500 },

  // W-A 工作区：活动栏第一格（folder 图标，aria/title = 工作区）
  { kind: 'click', selector: 'nav.sidebar button[data-glyph="folder"]', note: '活动栏 → 工作区' },
  { kind: 'waitFor', selector: '.ws', timeoutMs: 8000 },
  { kind: 'wait', ms: 1500 },
  { kind: 'shot', name: '01-工作区', expectSelector: '.ws' },
  // 同视图背靠背复拍：DOM 未动 ⇒ 两张应当逐字节相同（抓图管线确定性）
  { kind: 'shot', name: '05-工作区-复拍', expectSelector: '.ws' },

  // W-B（点前）：数据库视图，连接弹层尚未开出
  { kind: 'click', selector: 'nav.sidebar button[data-glyph="cylinder"]', note: '活动栏 → 数据库' },
  { kind: 'waitFor', selector: '.db', timeoutMs: 8000 },
  { kind: 'wait', ms: 1500 },
  { kind: 'shot', name: '04-数据库-点前', expectSelector: '.db' },

  // W-B（点后）：命令面板「新建连接」 ⇒ 连接弹层打开（连接面的唯一入口在弹层里）
  { kind: 'palette', title: '新建连接', note: '命令面板 Ctrl+K → 新建连接' },
  { kind: 'waitFor', selector: '.dlg', timeoutMs: 10000 },
  { kind: 'wait', ms: 1200 },
  { kind: 'shot', name: '02-数据库连接', expectSelector: '.dlg' },

  // 关弹层 → 底部面板终端页签（按需起会话）→ 再点 ＋ 新建一条终端
  { kind: 'click', selector: 'button.dlg__close', optional: true, note: '关掉连接弹层' },
  { kind: 'waitFor', selector: '.dlg', absent: true, timeoutMs: 5000, optional: true },
  { kind: 'click', selector: 'button.panel__tab[title="终端"]', note: '底部面板 → 终端页签' },
  { kind: 'waitFor', selector: 'button.panel__session-new', timeoutMs: 8000 },
  { kind: 'wait', ms: 2000 },
  { kind: 'click', selector: 'button.panel__session-new', note: '终端 → 新建终端（＋）' },
  { kind: 'wait', ms: 2500 },
  { kind: 'shot', name: '03-终端', expectSelector: '.panel__terminal' },
]

const args = parseArgs(process.argv.slice(2))
if (!args.out) fail('missing --out <png|dir>')
if (!Number.isInteger(args.port) || args.port <= 0 || args.port > 65535) fail(`bad --port (${args.port})`)

const outArg = resolve(args.out)
const singleMode = /\.png$/i.test(outArg)

let steps = null
if (!singleMode) {
  if (args.set) {
    const setPath = isAbsolute(args.set) ? args.set : resolve(args.set)
    if (!existsSync(setPath)) fail(`--set file not found: ${setPath}`)
    try {
      steps = JSON.parse(readFileSync(setPath, 'utf8'))
    } catch (e) {
      fail(`--set file is not valid JSON (${setPath}): ${e.message}`)
    }
    if (!Array.isArray(steps)) fail('--set file must contain a JSON array of steps')
  } else {
    steps = DEFAULT_SET
  }
} else if (args.set) {
  fail('--set only applies to a step set (--out must be a directory, not a .png)')
}

const tag = sanitizeTag(args.tag)

// ── CDP 连接 ────────────────────────────────────────────────────────────────
let targets
try {
  const res = await fetch(`http://127.0.0.1:${args.port}/json/list`, { signal: AbortSignal.timeout(5000) })
  if (!res.ok) fail(`/json/list HTTP ${res.status}`)
  targets = await res.json()
} catch (e) {
  fail(`/json/list unreachable on port ${args.port}: ${e.name === 'TimeoutError' ? 'timeout' : e.message}`)
}
if (!Array.isArray(targets)) fail('/json/list did not return a JSON array')

const page = targets.find(
  (t) => t && t.type === 'page' && typeof t.webSocketDebuggerUrl === 'string' && t.webSocketDebuggerUrl,
)
if (!page) {
  const kinds = targets.map((t) => (t && t.type) || '?').join(',') || 'empty'
  fail(`no type=="page" target in /json/list (types: ${kinds})`)
}

let ws
try {
  ws = new WebSocket(page.webSocketDebuggerUrl)
  await new Promise((ok, no) => {
    ws.addEventListener('open', ok, { once: true })
    ws.addEventListener('error', () => no(new Error('websocket error')), { once: true })
    setTimeout(() => no(new Error('websocket open timeout')), 5000)
  })
} catch (e) {
  fail(`connect ${page.webSocketDebuggerUrl}: ${e.message}`)
}

let seq = 0
const pending = new Map()
ws.addEventListener('message', (ev) => {
  let msg
  try {
    msg = JSON.parse(typeof ev.data === 'string' ? ev.data : String(ev.data))
  } catch {
    return
  }
  if (msg && msg.id && pending.has(msg.id)) {
    const settle = pending.get(msg.id)
    pending.delete(msg.id)
    settle(msg)
  }
})

function call(method, params = {}, timeoutMs = 20000) {
  const id = ++seq
  return new Promise((ok, no) => {
    const timer = setTimeout(() => {
      pending.delete(id)
      no(new Error(`${method} timeout after ${timeoutMs}ms`))
    }, timeoutMs)
    pending.set(id, (msg) => {
      clearTimeout(timer)
      if (msg.error) no(new Error(`${method}: ${msg.error.message || JSON.stringify(msg.error)}`))
      else ok(msg.result)
    })
    ws.send(JSON.stringify({ id, method, params }))
  })
}

function shutdown(code) {
  try {
    ws.close()
  } catch {
    /* ignore */
  }
  process.exit(code)
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms))
}

/** 在页面里求值一个表达式并取回值（异常 ⇒ 抛，不静默）。 */
async function evalJs(expression) {
  const r = await call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }, 20000)
  if (r && r.exceptionDetails) {
    const d = r.exceptionDetails
    const detail = d.exception && d.exception.description ? d.exception.description : d.text
    throw new Error(`页面求值抛异常: ${detail}`)
  }
  return r && r.result ? r.result.value : undefined
}

/** 轮询一个求值表达式直到它返回真值（超时 ⇒ 抛）。 */
async function pollEval(expression, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const value = await evalJs(expression)
    if (value) return value
    await sleep(150)
  }
  throw new Error(`等不到：${label}（${timeoutMs}ms 超时）`)
}

function exprClick(opts) {
  return `(() => {
    const o = ${JSON.stringify(opts)};
    const norm = (s) => String(s == null ? '' : s).replace(/\\s+/g, ' ').trim();
    let el = null;
    if (o.selector) el = document.querySelector(o.selector);
    if (!el && o.title) el = Array.from(document.querySelectorAll('*')).find((e) => norm(e.getAttribute && e.getAttribute('title')) === norm(o.title));
    if (!el && o.aria) el = Array.from(document.querySelectorAll('*')).find((e) => norm(e.getAttribute && e.getAttribute('aria-label')) === norm(o.aria));
    if (!el && o.text) el = Array.from(document.querySelectorAll('*')).find((e) => norm(e.textContent) === norm(o.text));
    if (!el) return 'NOTFOUND';
    el.click();
    return 'OK';
  })()`
}

const exprOpenPalette =
  "(() => { window.dispatchEvent(new KeyboardEvent('keydown', { key: 'k', ctrlKey: true, bubbles: true })); return 'OK'; })()"

function exprPaletteClick(title) {
  return `(() => {
    const want = ${JSON.stringify(title)};
    const items = Array.from(document.querySelectorAll('.palette__item'));
    const hit = items.find((li) => {
      const t = li.querySelector('.palette__title');
      return t && t.textContent.replace(/\\s+/g, ' ').trim() === want;
    });
    if (!hit) return 'NOTFOUND';
    hit.dispatchEvent(new MouseEvent('mouseenter'));
    hit.click();
    return 'OK';
  })()`
}

function exprKey(key) {
  return `(() => {
    const el = document.activeElement || document.body || document.documentElement;
    el.dispatchEvent(new KeyboardEvent('keydown', { key: ${JSON.stringify(key)}, bubbles: true, cancelable: true }));
    return 'OK';
  })()`
}

const exprShotCheck = (selector, absent) =>
  absent
    ? `!document.querySelector(${JSON.stringify(selector)})`
    : `!!document.querySelector(${JSON.stringify(selector)})`

/** 抓一张到指定 PNG（绝对路径）。 */
async function captureTo(absPath) {
  await call('Page.enable', {}, 5000).catch(() => {})
  const r = await call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false }, 20000)
  if (!r || typeof r.data !== 'string' || r.data.length === 0) {
    throw new Error('Page.captureScreenshot returned no data')
  }
  const buf = Buffer.from(r.data, 'base64')
  mkdirSync(dirname(absPath), { recursive: true })
  writeFileSync(absPath, buf)
  return buf.length
}

try {
  if (singleMode) {
    const bytes = await captureTo(outArg)
    process.stdout.write(`WROTE=${outArg} bytes=${bytes}\n`)
    process.stdout.write('SHOT_COUNT=1\n')
    shutdown(0)
  }

  // ── 步骤集模式 ─────────────────────────────────────────────────────────────
  mkdirSync(outArg, { recursive: true })
  process.stdout.write(`MODE=set OUTDIR=${outArg} TAG=${tag} STEPS=${steps.length}\n`)
  if (args.settleMs > 0) await sleep(args.settleMs)

  const written = []
  let warnings = 0

  for (let i = 0; i < steps.length; i++) {
    const step = steps[i]
    const at = `[${i + 1}/${steps.length}] ${step.kind}`
    switch (step.kind) {
      case 'comment': {
        process.stdout.write(`STEP ${at} :: ${step.note || ''}\n`)
        break
      }
      case 'wait': {
        const ms = Number(step.ms) || 0
        process.stdout.write(`STEP ${at} :: 等 ${ms}ms${step.note ? ' · ' + step.note : ''}\n`)
        await sleep(ms)
        break
      }
      case 'click': {
        const res = await evalJs(exprClick(step))
        process.stdout.write(
          `STEP ${at} :: ${res}${step.note ? ' · ' + step.note : ''}${step.selector ? ' · ' + step.selector : ''}\n`,
        )
        if (res !== 'OK') {
          if (step.optional) {
            warnings++
            process.stdout.write(
              `WARN 点不到（可选步，继续）：${step.selector || step.title || step.aria || step.text}\n`,
            )
          } else {
            throw new Error(`点不到元素：${step.selector || step.title || step.aria || step.text}`)
          }
        }
        break
      }
      case 'palette': {
        process.stdout.write(`STEP ${at} :: Ctrl+K${step.note ? ' · ' + step.note : ''}\n`)
        await evalJs(exprOpenPalette)
        await pollEval(
          "(() => Array.from(document.querySelectorAll('.palette__item')).length > 0)()",
          8000,
          '命令面板列表',
        )
        await evalJs(
          "(() => { const el = document.querySelector('.palette__input'); if (el) el.focus(); return 'OK'; })()",
        )
        const res = await evalJs(exprPaletteClick(step.title))
        if (res !== 'OK') throw new Error(`命令面板里找不到「${step.title}」`)
        process.stdout.write(`PALETTE_ITEM=${step.title}\n`)
        break
      }
      case 'key': {
        await evalJs(exprKey(step.key))
        process.stdout.write(`STEP ${at} :: ${step.key}\n`)
        break
      }
      case 'waitFor': {
        try {
          await pollEval(
            exprShotCheck(step.selector, !!step.absent),
            Number(step.timeoutMs) || 8000,
            `${step.selector}${step.absent ? ' 应消失' : ' 应出现'}`,
          )
          process.stdout.write(`STEP ${at} :: OK ${step.selector}${step.absent ? ' 已消失' : ' 已出现'}\n`)
        } catch (e) {
          if (step.optional) {
            warnings++
            process.stdout.write(`WARN ${e.message}（可选步，继续）\n`)
          } else {
            throw e
          }
        }
        break
      }
      case 'eval': {
        const v = await evalJs(step.js)
        process.stdout.write(`STEP ${at} :: ${typeof v === 'string' ? v : JSON.stringify(v)}\n`)
        break
      }
      case 'shot': {
        if (step.expectSelector) {
          try {
            await pollEval(
              exprShotCheck(step.expectSelector, false),
              Number(step.timeoutMs) || 8000,
              step.expectSelector,
            )
          } catch (e) {
            throw new Error(`抓「${step.name}」前界面没到位：${e.message}`)
          }
        }
        const file = join(outArg, `${step.name}-${tag}-${hhmm()}.png`)
        const bytes = await captureTo(file)
        written.push({ file, bytes })
        process.stdout.write(`WROTE=${file} bytes=${bytes}\n`)
        break
      }
      default:
        throw new Error(`未知步骤 kind=${step.kind}`)
    }
  }

  process.stdout.write(`SHOT_COUNT=${written.length}\n`)
  process.stdout.write(`WARNINGS=${warnings}\n`)
  if (written.length === 0) throw new Error('步骤集一张图都没产出')
  shutdown(0)
} catch (e) {
  process.stdout.write(`FAIL=${e.message}\n`)
  shutdown(1)
}
// S-073e 复现点：只改 App/tools/**（本行注释）并提交后重建 —— 改前 build.rs 不重跑，徽标滞留旧短号。
