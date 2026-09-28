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
| `scroll@400000+instant-ipc` | 同上，但把 `__TAURI_INTERNALS__.invoke` 换成「缓存立即返回」（只补在本仪器注入的页面里） | **隔离档**：把「取数传输成本」与「渲染 / 布局成本」分开 |

每档前后各取一次 Chromium 引擎计数（`Performance.getMetrics` 增量）：布局次数 / 布局时长、样式重算次数 / 时长、`ScriptDuration`、`TaskDuration`、DOM 节点数。另有：`longtask` 计数、`performance.memory`、**进程树工作集**（`tree-memory.ps1`，按 `Win32_Process` 自算，只算本仪器起的那棵树）。

## 实测（2026-09-28，本机：Windows 11 / iGPU = Intel Iris Xe / WebView2 153.0.4234.48）

窗口 1280×800、结果网格视口 **1000×669**、40 万行 × 20 列；GPU 证据 = `WEBGL_debug_renderer_info` → `ANGLE (Intel, Intel(R) Iris(R) Xe Graphics (0x00009A49) Direct3D11 vs_5_0 ps_5_0, D3D11)`。

| 项 | 读数 |
|---|---|
| 空转（不滚动） | **p50 16.7 ms（60.1 fps）** ⇒ 宿主有 60 fps 能力 |
| **滚动 40 万行（240 帧）** | **p50 48.8~50.1 ms / p95 63.1~64.4 ms ⇒ ≈19~20 fps；240/240 帧超 16.7 ms**（50.1 ≈ 3 个 vsync 周期）—— 4 轮复跑：46.1 / 49.6 / 50.1 / 48.8 ms |
| 滚动 5 万行 / 2 千行 | 50.3 / 49.4 ms（复跑：54.2 / 42.6 ms）⇒ 与 40 万行**同一量级**，数据集规模不是主因 |
| IPC 隔离档（40 万行） | 51.0 ms（对照 50.1 ms）⇒ **IPC 无关** |
| DOM 只实体化 | 38 行（视口可见 ≈26 行 + overscan 12） |
| 首屏 | 559.6 ms |
| IPC 取 64 行（200 次） | p50 6.3 ms / p95 8.1 ms / 最大 14.4 ms |
| 排序（换方向重算置换） | 118.7 ms |
| 引擎增量（滚动档） | 布局 272 次 / 3.71 s（≈13.6 ms/帧）· 样式重算 272 次 / 1.14 s（≈4.2 ms/帧）· `TaskDuration` 14.2 s（≈墙钟 ⇒ 主线程饱和）· `ScriptDuration` **0.04 s**（≈0 ⇒ 不是 JS 逻辑） |
| 长任务 | 53 次 / 总 3.0 s / 最长 73 ms |
| 进程树峰值 | ≈789 MB（估算，含 6~7 个 WebView2 子进程） |

**方向性结论**：40 万 × 20 列在当前产品形态（手写虚拟化 + 每帧窗口取数）下 **≈19~21 fps，未达标**；且**行数无关 + IPC 无关**两条诊断把成本指向「**每帧重建可视行 DOM + 重排版 / 重绘**」。下一步候选（都在这台仪器上做）：① 同栈外壳里跑基准台的 TanStack Virtual 形态；② AG Grid Community 同规模对照；③ 产品侧先做行 / 单元格节点复用再量同一协议。

## 口径限制（不得据此宣布达标）

1. **单次运行、无统计分布**：本轮手工跑了 **4 轮**，p50 = 46.1 / 49.6 / 50.1 / 48.8 ms、首屏 702.9 / 576.7 / 559.6 / 452.3 ms、IPC p50 = 12.1 / 5.9 / 6.3 / 5.2 ms ⇒ 轮间波动可观（首跑最慢，含应用预热）。
2. 仪器给宿主加了 `--disable-backgrounding-occluded-windows` / `--disable-renderer-backgrounding`：不加时窗口被遮挡 / 不在前台会让 Chromium 把 rAF 压到 1 Hz，量到的是**节流后的帧率**（真机前台使用不受影响）。
3. 滚动由**程序化**赋值 `scrollTop` 驱动，**不含真实指针 / 滚轮事件与输入延迟**。
4. 真机上 `requestAnimationFrame` 与 vsync 对齐 ⇒ 帧耗时被**量化到 16.7 ms 的整数倍**（50.1 ≈ 3 帧），读数给出的是「帧预算档位」而不是纯工作量。
5. 进程树内存是 `Win32_Process` 工作集求和（**估算**），不是本应用的真实常驻；`performance.memory` 在 WebView2 下读数小且离散（2~13 MB），**不可用于内存结论**。
6. 结论**不许跨形态沿用**（`P-27`）：`Bench/grid` 的无头读数（21.3 ms / 45.4 fps）与本仪器读数（50.1 ms / 19.3 fps）**方向相反、不可相减** —— 两者不是同形态（数据在前端内存、无 IPC、无头下 rAF 不受 vsync 约束）。

## 文件

| 文件 | 作用 |
|---|---|
| `bench.mjs` | Node 侧（零依赖）：起产物 → 找 `tauri://localhost` 页面 → CDP 注入 → 逐档取引擎增量 → 收读数 → **只收自己起的进程** |
| `driver.js` | 页面侧驱动（基准协议与 `Bench/grid/src/bench.ts` 同一套；常量由 `Bench/grid/src/bench-protocol.test.ts` 逐值对齐） |
| `tree-memory.ps1` | 进程树工作集（`Win32_Process` 自算；**ASCII-only**，避开 PS 5.1 无 BOM 时按 ANSI 解码的坑） |
