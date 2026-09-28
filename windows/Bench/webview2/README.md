# 真机基准仪器（windows/Bench/webview2）

**性质**：基准**仪器**，**不是产品代码、不是闸门项**。它起**真外壳**（`windows/App` 的发布产物 `doyah-studio.exe`，WebView2 承载嵌入的前端产物），用 CDP 注入 `driver.js`，在**真窗口 + 真 GPU** 里量结果网格 —— 补的是 `Bench/grid` 那份读数的两个缺口（§8.5.6-3 口径限制 ①②：无头软件光栅、不含 IPC 与 GPU 合成）。

## 怎么跑

```bash
cd windows
# ① 产物必须是**生产形态**（否则二进制会去连 devUrl，页面是空的 ⇒ 本仪器打印 NO_PAGE）
cd App && npm install && npm run build && cd ..
cargo build --release --workspace --features doyah-studio-shell/custom-protocol

# ② 跑仪器（会弹出真窗口，跑完自己收掉）
cd Bench/webview2 && node bench.mjs
```

参数：`--exe <路径>`（默认 `../../target/release/doyah-studio.exe`）、`--out <json>`（默认 `../../target/webview2-bench.json`，`target/` 已 gitignore）、`--port <CDP 端口>`（默认 `9444`）。
退出码：`0` 量到了 / `1` 失败 / `3` 找不到真外壳页面目标（只认 `tauri://localhost`，不认任何 `http://localhost:xxxx`）。

## 量什么（一次运行的相位）

| 相位 | 内容 | 为什么要有 |
|---|---|---|
| `setup` | 改规模到 40 万 × 20 列 → 首屏耗时 → **IPC 200 次取 64 行** → **排序**（换方向重算置换，三遍） | 取数层与排序的延迟；首屏含 Rust 侧生成 |
| `idle@400000` | 不滚动、只等帧（120 帧） | **对照档**：把「宿主自己的帧节奏」与「滚动成本」分开（没有它分不清「宿主把 rAF 压到 20 帧」与「这一屏真的慢」） |
| `scroll@400000` / `@50000` / `@2000` | 与 `Bench/grid` **同一套协议**（步长 288px、预热 30 帧、测量 240 帧，`requestAnimationFrame` 间隔） | 三档行数 = 把「数据集规模 / 1000 万像素滚动高度」这一因素分离出来 |
| `scroll@400000+slow-scroll` | 同协议，但**步长 1px/帧**（240 帧只走 240px）⇒ 窗口每 ~26 帧才真的换一次 | **消融档**：IPC / 响应式 / vnode 比对 / 滚动簿记全在，**DOM 写入基本没有** ⇒ 与同轮基线成对读，差值 ≈ 每帧「写 DOM + 重排版 / 重绘」的成本（`windowShifts` 记进读数，用来证明窗口确实没怎么换） |
| `scroll@400000+repeat` | 基线在同一轮里再跑一遍 | **同轮内对照**：跨会话漂移 > 50%（见口径限制 1），**只有同轮内的一对可以相减** |

每档前后各取一次 Chromium 引擎计数（`Performance.getMetrics` 增量）：布局次数 / 布局时长、样式重算次数 / 时长、`ScriptDuration`、`TaskDuration`、DOM 节点数。另有：`longtask` 计数、`performance.memory`、**进程树工作集**（`tree-memory.ps1`，按 `Win32_Process` 自算，只算本仪器起的那棵树）。收尾另探一次**宿主是否允许替换 `__TAURI_INTERNALS__.invoke`**（`invokePatchability`）。

## 实测（2026-09-28 本机：Windows 11 / iGPU = Intel Iris Xe / WebView2 153.0.4234.48）

窗口 1280×800、结果网格视口 **1000×669**、40 万行 × 20 列；GPU 证据 = `WEBGL_debug_renderer_info` → `ANGLE (Intel, Intel(R) Iris(R) Xe Graphics (0x00009A49) Direct3D11 vs_5_0 ps_5_0, D3D11)`。两列 = 两次会话（**同一二进制**；第 29 轮只改了仪器）。

| 项 | 第 29 轮 | 第 28 轮 |
|---|---|---|
| 空转（不滚动） | **17.9 ms（56 fps）** | 16.7 ms（60.1 fps） |
| **滚动 40 万行（240 帧）** | **p50 79.1 ms / p95 537.5 ms ⇒ 8.5 fps，240/240 帧超 16.7 ms** | p50 48.8~50.1 ms（4 轮）⇒ ≈20 fps |
| 基线复跑（同轮内） | **78.6 ms**（与上一行相差 **0.5 ms**） | — |
| 滚动 5 万行 / 2 千行 | 79.4 / 76.1 ms ⇒ 仍与 40 万行**同量级** | 50.3 / 49.4 ms |
| **消融档：慢速滚动（1px/帧）** | **p50 17.9 ms / p95 31.3 ms（46.9 fps）**、布局 0.33 s / 160 次、样式重算 0.06 s / 160 次、窗口只换了 **4** 次 | —（旧「IPC 隔离档」**无效**，见下） |
| 引擎增量（基线档） | 布局 295 次 / **6.39 s（≈21.6 ms/次）** · 样式重算 295 次 / 1.99 s · `ScriptDuration` ≈0（不是 JS 逻辑） | 布局 272 次 / 3.71 s · 样式重算 272 次 / 1.14 s |
| DOM 只实体化 | 38 行 | 38 行 |
| 首屏 | 690.2 ms | 559.6 ms |
| IPC 取 64 行（200 次） | p50 8.0 ms / p95 9.4 ms | p50 6.3 ms / p95 8.1 ms |
| 排序（换方向重算置换） | 73.8 ms | 118.7 ms |
| 进程树峰值 | ≈790 MB（估算） | 789 MB |
| `invoke` 可替换性 | `{writable:false, configurable:false}` · `definePropertyOk=false` | —（当时没探，这是那一档失效的根因） |

**方向性结论（第 29 轮，比第 28 轮强的一条）**：消融档 **17.9 ms**（与同轮空转档 17.9 ms 同日而语）对照同轮基线 **79.1 ms** ⇒ **传输（IPC）+ 响应式 + vnode 比对 + 滚动簿记合计不足一个 vsync 周期，61 ms/帧 全部花在「把新的 38×20 个单元格文本写进 DOM + 重排版 / 重绘」上**（布局 ≈21.6 ms/次 × 295 次）。40 万 × 20 列在当前产品形态（手写虚拟化 + 每帧窗口取数）下 **≈8.5 fps（第 28 轮 ≈20 fps），未达标**。

## 第 28 轮那个消融档是坏的（第 29 轮修正）

旧版的做法是在页面里把 `__TAURI_INTERNALS__.invoke` 换成「缓存立即返回」（`internals.invoke = fn`）。宿主把该属性定义为**不可写且不可配置**（第 29 轮实测描述符 `writable:false, configurable:false`；`Object.defineProperty` 抛 `Cannot redefine property: invoke`）⇒ 那一步**从未生效**（sloppy mode 下赋值静默失败、不抛错），那一档于是量了与基线**完全相同**的东西（51.0 ms 对 50.1 ms），却报出一个「IPC 无关」的结论。**铁证一直在读数 JSON 里**：`cachedWindowCalls: 0`（产品一次都没命中补丁）—— 当时的报告与文档都没读它。

处置（都在第 29 轮）：① 仪器**当场探一遍**并把结论写进读数（`invokePatchability`）—— 「消融没生效」不许再当读数；② 换成**不需要改页面代码**的消融档（慢速滚动，见上）；③ 加**同轮内基线复跑**（跨会话漂移 > 50%，见口径限制 1）。

## 口径限制（不得据此宣布达标）

1. **跨会话漂移 > 50%（第 29 轮新记，最要紧的一条）**：同一二进制、同一窗口尺寸、同一 GPU —— 第 28 轮 p50 48.8~50.1 ms、第 29 轮 79.1 / **78.6 ms（轮内两次相差 0.5 ms）** ⇒ **轮间可比性只在同一轮内成立**，候选比较一律同轮 A/B（仪器已加基线复跑档）；跨轮把两个数相减是不可信的。
2. **单次运行、无统计分布**：每档 240 帧，档内无重复；第 28 轮手工跑了 4 轮（p50 = 46.1 / 49.6 / 50.1 / 48.8 ms），第 29 轮每档一次但**基线跑了两遍**（79.1 / 78.6 ms）。
3. 仪器给宿主加了 `--disable-backgrounding-occluded-windows` / `--disable-renderer-backgrounding`：不加时窗口被遮挡 / 不在前台会让 Chromium 把 rAF 压到 1 Hz，量到的是**节流后的帧率**（真机前台使用不受影响）。
4. 滚动由**程序化**赋值 `scrollTop` 驱动，**不含真实指针 / 滚轮事件与输入延迟**。
5. 真机上 `requestAnimationFrame` 与 vsync 对齐 ⇒ 帧耗时被**量化到 16.7 ms 的整数倍**（79.1 ≈ 4.7 帧、50.1 ≈ 3 帧）；读数给出的是「帧预算档位」而不是纯工作量 —— 消融档的 17.9 ms 只说明「**该档工作量 < 一个 vsync 周期**」，不是「它的纯工作量是 17.9 ms」。
6. 消融档只压低了**内容更新率**（`windowShifts` = 4），**没有**去掉 IPC：慢速滚动下产品仍每帧发一次窗口取数（`plan` 是每帧新建的对象 ⇒ 每帧触发一次取数）。这正是它比旧档强的地方 —— 它证明的是「传输那部分可忽略」，不是「传输被拿掉了」。
7. 进程树内存是 `Win32_Process` 工作集求和（**估算**，含 6~7 个 WebView2 子进程），不是本应用的常驻；`performance.memory` 在 WebView2 下读数小且离散（2~13 MB），**不可用于内存结论**。
8. 结论**不许跨形态沿用**（`P-27`）：`Bench/grid` 的无头读数（21.3 ms / 45.4 fps）与本仪器读数**方向相反、不可相减** —— 两者不是同形态（数据在前端内存、无 IPC、无头下 rAF 不受 vsync 约束）。

## 文件

| 文件 | 作用 |
|---|---|
| `bench.mjs` | Node 侧（零依赖）：起产物 → 找 `tauri://localhost` 页面 → CDP 注入 → 逐档取引擎增量 → 收读数 → **只收自己起的进程**；跑前先做协议常量对齐（与 `Bench/grid` 逐值比，不符即 `PROTOCOL_DRIFT` 退出 1） |
| `driver.js` | 页面侧驱动（基准协议与 `Bench/grid/src/bench.ts` 同一套；常量由 `Bench/grid/src/bench-protocol.test.ts` 逐值对齐）+ **消融档** + **`invoke` 可替换性探测** |
| `tree-memory.ps1` | 进程树工作集（`Win32_Process` 自算；**ASCII-only**，避开 PS 5.1 无 BOM 时按 ANSI 解码的坑） |
