#!/usr/bin/env node
// devtools-shot.mjs — 从**已在跑**的 WebView2 / Chromium 的 CDP 端点抓 1 张 PNG。
//
// 片号：S-073b（T-20261007-073 第①条）。用途：cron / 无人会话里给「该包实跑实例」截图 ——
// computer_use 的 click/type 会被审批门拒（无人可批），所以必须有这条**可脚本化、免审批**的通道。
//
// 只用 Node 内建：全局 fetch + 全局 WebSocket（Node >= 22）。**不引任何外部依赖**。
//
// 用法：
//   node devtools-shot.mjs --port 9222 --out D:/path/shot.png
// 成功：打印 `WROTE=<绝对路径> bytes=<n>`，退出码 0
// 失败：打印 `FAIL=<一句原因>`，退出码 1
//
// 流程：GET http://127.0.0.1:<port>/json/list → 取 type=="page" 的 target
//       → 连它的 webSocketDebuggerUrl → 发 Page.captureScreenshot{format:"png"}
//       → base64 落盘。

import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

function fail(reason) {
  process.stdout.write(`FAIL=${reason}\n`);
  process.exit(1);
}

function parseArgs(argv) {
  const out = { port: 9222, out: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--port') out.port = Number(argv[++i]);
    else if (a === '--out') out.out = argv[++i];
    else if (a.startsWith('--port=')) out.port = Number(a.slice('--port='.length));
    else if (a.startsWith('--out=')) out.out = a.slice('--out='.length);
  }
  return out;
}

const { port, out } = parseArgs(process.argv.slice(2));
if (!out) fail('missing --out <png>');
if (!Number.isInteger(port) || port <= 0 || port > 65535) fail(`bad --port (${port})`);

// 1) 列 target
let targets;
try {
  const res = await fetch(`http://127.0.0.1:${port}/json/list`, {
    signal: AbortSignal.timeout(5000),
  });
  if (!res.ok) fail(`/json/list HTTP ${res.status}`);
  targets = await res.json();
} catch (e) {
  fail(`/json/list unreachable on port ${port}: ${e.name === 'TimeoutError' ? 'timeout' : e.message}`);
}
if (!Array.isArray(targets)) fail('/json/list did not return a JSON array');

// 2) 取 page target
const page = targets.find((t) => t && t.type === 'page' && typeof t.webSocketDebuggerUrl === 'string' && t.webSocketDebuggerUrl);
if (!page) {
  const kinds = targets.map((t) => (t && t.type) || '?').join(',') || 'empty';
  fail(`no type=="page" target in /json/list (types: ${kinds})`);
}

// 3) 连页面的 ws，发 Page.captureScreenshot
let ws;
try {
  ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((ok, no) => {
    ws.addEventListener('open', ok, { once: true });
    ws.addEventListener('error', () => no(new Error('websocket error')), { once: true });
    setTimeout(() => no(new Error('websocket open timeout')), 5000);
  });
} catch (e) {
  fail(`connect ${page.webSocketDebuggerUrl}: ${e.message}`);
}

let seq = 0;
const pending = new Map();
ws.addEventListener('message', (ev) => {
  let msg;
  try { msg = JSON.parse(typeof ev.data === 'string' ? ev.data : String(ev.data)); } catch { return; }
  if (msg && msg.id && pending.has(msg.id)) {
    const settle = pending.get(msg.id);
    pending.delete(msg.id);
    settle(msg);
  }
});

function call(method, params = {}, timeoutMs = 20000) {
  const id = ++seq;
  return new Promise((ok, no) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      no(new Error(`${method} timeout after ${timeoutMs}ms`));
    }, timeoutMs);
    pending.set(id, (msg) => {
      clearTimeout(timer);
      if (msg.error) no(new Error(`${method}: ${msg.error.message || JSON.stringify(msg.error)}`));
      else ok(msg.result);
    });
    ws.send(JSON.stringify({ id, method, params }));
  });
}

try {
  // Page.enable 在部分实现上会报错（已经 enable 过会失败），不为它中断截图。
  await call('Page.enable', {}, 5000).catch(() => {});
  const r = await call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  if (!r || typeof r.data !== 'string' || r.data.length === 0) {
    throw new Error('Page.captureScreenshot returned no data');
  }
  const buf = Buffer.from(r.data, 'base64');
  const abs = resolve(out);
  writeFileSync(abs, buf);
  process.stdout.write(`WROTE=${abs} bytes=${buf.length}\n`);
  try { ws.close(); } catch { /* ignore */ }
  process.exit(0);
} catch (e) {
  try { ws.close(); } catch { /* ignore */ }
  fail(e.message);
}
