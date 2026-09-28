# 结果网格压力基准台（windows/Bench/grid）

**性质**：基准台，**不是产品表示层**。服务 §8.5.6-3 与 2026-09-28 开工令的第一件事：**40 万行 × 20 列**的结果集网格 —— 滚动帧率 / 内存 / 排序筛选延迟，「**过了再铺功能**」。

**栈**：Vue 3 + TypeScript + Vite + TanStack Virtual（自绘虚拟化）；数据由 Rust 侧 `windows/Core` 的 `grid-bench` 产出（`grid.f64.bin` = rows×cols 小端 f64 + `grid.meta.json` = 列名 / 列型 / 文本列字典）。基准台**只读取**，不改动原数据。

## 怎么跑

```bash
# ① 数据侧（在 windows/ 下）
cargo run --release --bin grid-bench -- --rows 400000 --cols 20 \
  --data-dir Bench/grid/public/data --out Bench/grid/public/data/rust-result.json

# ② 前端侧
cd Bench/grid && npm install      # 一次
npm run dev                       # 固定端口 5273（strictPort：被占即失败，不静默换端口）
#  浏览器打开 http://localhost:5273/?bench=1 —— 自动跑基准，读数落在 window.__DOYAH_GRID_BENCH__
```

单测 / 类型 / 构建：`npm test`（vitest）· `npm run typecheck`（`tsc --noEmit`）· `npm run build`（vite）。

## 实测（2026-09-28，本机）

**Rust 侧**（40 万行 × 20 列，release）：生成 386.3 ms / 排序（降序置换）**77.8 ms** / 文本等值筛选 3.17 ms / 数值区间筛选 2.49 ms / 200 个 64 行窗口实体化 144.5 ms / 20 万次随机单元格取文本 118.9 ms / 列数据 102.9 MB（**字节估算，非进程 RSS**）。

**前端侧**（无头 Chromium 151，`--disable-gpu` 软件光栅）：虚拟滚动 240 帧 **p50 21.3 ms / p95 31.2 ms / 均 22.0 ms（45.4 fps）/ 超 16.7 ms 204 帧**；**DOM 只实体化 31 行**；首屏 942.1 ms（含 64 MB 数据读入）；JS 堆 90.1 MB；前端排序 494.5 ms、前端筛选 13.2 ms。

## 口径限制（不得据此宣布达标）

1. 无头软件光栅，**不含 GPU 合成与输入延迟** —— 真机复测**已落地（第 28 轮）**，仪器 = `windows/Bench/webview2/`（真外壳 + 真 GPU + CDP 注入），读数 **p50 50.1 ms / 19.3 fps**（本台为 21.3 ms / 45.4 fps）⇒ **两套数字方向相反、不可相减**：本台数据已在前端内存、无 IPC，且无头下 `requestAnimationFrame` 不受 vsync 约束（真机帧耗时被量化到 16.7 ms 的整数倍）。另如实记一条：本台这次跑的时候**没有记录网格视口尺寸**，所以两侧连视口都不是同一个 ⇒ 只作同形态内的对比（下一轮补记视口）；
2. 数据窗口由同一块 ArrayBuffer 直接切出（Rust 窗口 API 的等价语义），**未含 Tauri IPC 开销**；
3. 单次运行、无统计分布；
4. 前端排序 / 筛选为 JS 实现，**仅作与 Rust 侧的对照**（方向性结论：排序应落在后端）。

## 文件

| 文件 | 作用 |
|---|---|
| `src/gridData.ts` | 取数层（读 Rust 产物；窗口取数 / 排序 / 筛选 / 单元格格式化） |
| `src/bench.ts` | 测量（rAF 帧耗时统计 / 堆 / 两遍计时 / p50、p95） |
| `src/App.vue` | 虚拟网格（TanStack Virtual 自绘）+ 控件 + 结果面板 |
| `src/gridData.test.ts` | vitest 单测（5 例，小夹具，不依赖数据文件） |
| `public/data/` | **Rust 侧产物（不入库，见根 `.gitignore`）** |
| `vite.config.ts` | 固定端口 5273 + `strictPort`（便于脚本 / CDP 直连） |
