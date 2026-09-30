# windows/ —— Doyah Studio 的 Windows 侧（另一平台）实现落点

对应设计：`Docs/概要设计.md` **§8.2**（仓库结构：同仓 `windows/` 块）与 **§8.5 契约 → Windows 实现 `[独占:windows]`**。
本目录 = **实现层**：可以替换实现，**不得改变 §3 的契约与不变量**；要改契约走 `Docs/proposals/`。

**技术栈（2026-09-28 需求提出者开工令）**：前端 **Tauri 2 + Vue 3 + TypeScript**、后端 **Rust**、测试 `cargo test` + `vitest`、分发 Tauri bundler（MSI / NSIS）。原 .NET（C# / WPF / xUnit）路线**作废**；与契约字面（§8.2 树 / §3 GUI 框架行 / SRS §10.9 的 `P-19`·`P-23`·`P-24` /「原生界面栈」）的冲突走 **`Docs/proposals/0004`**（待采纳），本侧不自行放宽契约。

## 现在有什么

| 目录 | 层 | 现状 |
|---|---|---|
| `Tools/` | 闸门（§8.3.1 六项必需项 + §8.5.6-3 基准项 + §8.3 的生成物一致性） | ✅ 14 项一条命令跑全（见 `Tools/README.md`） |
| `Cargo.toml` / `Core/` | 领域层（Rust；零第三方依赖、零 UI / 平台依赖） | 🟡 首片已落地（合成数据集 / 排序筛选 / 窗口取数 / `grid-bench`；`cargo test` 15 例） |
| `Bench/grid/` | 结果集网格压力基准台（Vue 3 + TS + Vite + TanStack Virtual） | 🟡 首片已落地（见 `Bench/grid/README.md`） |
| `Bench/webview2/` | **真机基准仪器**（起真外壳 + CDP 注入驱动：空转对照 / 三档行数滚动 / **慢速滚动与样式消融档** / **变更观察档** / 「invoke 可替换性」探测 / 同轮内基线复跑 / `--quick` 交替 A/B / 进程树内存） | ✅ 已落地（第 28 轮，第 29 轮修掉消融档一处静默失效；**第 30 轮落产品侧行池 + 前瞻取数 + 单格绘制，同轮 A/B p50 49.6 → 26.2 ms**；读数、仪器地板与口径限制见 §8.5.6-3 与 `Bench/webview2/README.md`） |
| `App/` | 表示层（Tauri 2 外壳 + Vue 3 + TS） | 🟡 首片已落地（外壳 + 结果网格走「Rust 侧切片」+ 令牌层；前端 `vitest` 35 例（含令牌生成器 / 棘轮的 node 自测）、本目录 Rust 8 例；见 `App/README.md`） |
| `Cli/` | 无界面验证入口（Rust 二进制：子命令 + 退出码表 + `--json`） | ⬜ 未建 |
| `Platform/Windows/` | 平台适配层（凭据管理器 / ConPTY / 通知；唯一引 Windows 专有 API 处） | ⬜ 未建 |
| `Tests/` | 单测（Rust `cargo test` + 前端 `vitest`） | 🟡 58 例（Core 15 + App Rust 8 + 前端 35），随层增长 |

**未接网的账（如实登记，别当成已完成）**：

- ~~`Tools/check-core-boundary.ps1` 只认 C# 形态~~ ⇒ **已销账（第 25 轮）**：判据按 **Rust 形态**重建（`Cargo.toml` 依赖面 + `Core/**/*.rs` 源码面 + 空跑判红），判据与 **7 例自测**一次调用里都真跑，见 `Tools/README.md`。
- ~~`Tools/check-design-tokens.ps1` 的 Windows 侧棘轮要等 `App/` 落地~~ ⇒ **已销账（第 26 轮）**：`App/` 落地后 ③ 交给表示层自己的 node 判据（`App/tools/gen-tokens.mjs --check` + `token-ratchet.mjs`），本项**不再有跳过档**（见 `Tools/README.md`）。**第 30 轮再补**：对侧把令牌值表**按主题分组**（新增 `Core/DesignTheme.swift`）⇒ 本侧生成器改**双源**、产出**两件生成物**（每主题变量块 `[data-theme-scheme=…]` 的 CSS + 主题集 `src/theme/themes.generated.ts`），外壳加**同名下拉**（候选与「推导草案」标记由生成物派生），发丝线浅色档改**源侧实色**。
- ~~`App/` 侧的版本号一致性没有网~~ ⇒ **已销账（第 27 轮）**：发布产物版本号 `0.2.0`（三处逐字一致）由判据 `Tools/check-release-version.ps1` + 台账 `Tools/release-version.json` 机械判（闸门**第 13 项**）—— 三处各改一处都判红并点名、缺键也判红，另判**与 mac 侧发布台账同源**（不等即判红，对侧 `buildVersion` 不跟随）。
- **仍未接网（如实登记，别当成已完成）**：① ~~**WebView2 + GPU 下的基准复测未做**~~ ⇒ **已销账（第 28 轮）**：仪器 `Bench/webview2/` 已落地并跑出真机读数（真 GPU = ANGLE / Intel Iris Xe D3D11）—— 空转 16.7 ms（60 fps）而**滚动 40 万行 p50 50.1 ms（19.3 fps）**，且**行数无关 + IPC 无关**两档诊断把瓶颈指向「每帧重建可视行 DOM + 重排版 / 重绘」⇒ **复测做了，但这一关没过**：三候选取舍仍挂着，见 §8.5.6-3。**（第 30 轮进展）**产品侧三处（**行池 + 轮转槽位** / **前瞻取数 `LOOKAHEAD=12`** / **单格绘制 `clip` + 行 `contain`**）按同轮 A/B 把 p50 从 **49.6 ms 降到 26.2 ms（−47%）**、**内容成本（p50 − 同轮空转地板）31.7 → 8.3 ms**（已低于一个 16.7 ms 帧预算）；但**仪器自己的空转地板就是 ≈17.9 ms（≈56 fps）⇒ 60 fps 这一关无法由本仪器读出**，口径待需求提出者拍板 ⇒ 三候选取舍仍挂着。**（第 29 轮更正）**上一轮那条「IPC 无关」诊断**已作废** —— 它是仪器里一处**静默失效的消融档**（宿主把 `__TAURI_INTERNALS__.invoke` 定义成不可写 + 不可配置，页面里的替换从未生效；铁证 = 该档 `cachedWindowCalls: 0`）；第 29 轮换成**慢速滚动消融档**（不改页面代码）并把成本重新钉在「写 DOM + 重排版 / 重绘」上：**慢速滚动 17.9 ms 对同轮基线 79.1 ms**（跨会话漂移 > 50%，只有同轮内的一对可以相减）；② **装出来的 MSI / NSIS 里读到的版本号未实测** —— 本侧判据判的是**源**，要真跑一次 Tauri bundler 再读产物元数据；③ 本侧这个值三处**都是源**，仓内没有携带它的生成物（`dist/` 与 `target/` 都不入库）⇒「生成物 ↔ 源」那一半无对象。
- 契约侧 **L-46**（语言表模板 ↔ 调用点实参）判的是 Swift 源码 ⇒ 本端等价判据待本地化层落地后按同规则名重建。

**对侧两笔合流后的本侧适用性（Windows 侧第 31 轮，2026-10-01）**：对侧本轮推两笔 —— **`L-144`**（概要设计 **§3.30【契约】**：工作区 chrome 行 / 页签条的高度**只由内边距与字高决定**，不随内容、页签数量、窗口宽度变；量法 = 离屏 `sizeThatFits`，随门禁每轮跑）与 **`L-149` ③④**（**内置浏览器页签的归属 = 工作区**，与 Home / 文件页签同类，**不是**数据库 SQL 工作台的页签；旧措辞「编辑器区」已作废）。本侧据此登记两条等价义务（**暂不动代码** —— Studio 不在当前队列，Notes 安卓未完工）：① 表示层出现页签时**只画一条**页签条（浏览器与 Home / 文件同类），**高度不随内容 / 数量 / 宽度变**；② 浏览器页签**不得**挂进数据库侧视图（对侧判据 `Scripts/check-browser-tab-ownership.py` 的正面口径），AppKit 窗口标题栏那一层仍归人工点验。**该判据在本机（Windows）实测可跑且绿**（本侧无 Swift 表示层对象，先只读登记）；`P-14` 的行为契约与「引擎可换」那半一字未变。

**本机（Windows）跑对侧共享判据的实况（第 31 轮实测，供两侧参照）**：`Scripts/` 下 13 条跨平台判据在本机 **9 绿 / 4 红，4 红全部与本轮合流无关** —— `check-doc-tables.py` 红因**本侧循环镜像台账** `Docs/循环台账.md`（`/Docs/*` 已 gitignore，但它是「有表格却不在受检清单」的本地文档）⇒ 连带 `check-doc-numbers.py` 的 `[doc-tables-files]` 一项红；`check-release-version.py` 与 `check-self-test-counts.py` 红因**本机没有那两份被 gitignore 的本地文档**（`Docs/发布方案.md` / `Docs/design/开发循环-任务队列.md`）。另有一处纯环境现象：跑 `Scripts/check-self-test-counts.py`（它会实跑各判据自测）后，`Scripts/lib/test-env.sh` / `real-db-scripts.txt` / `remote-bypass-scripts.json` / `test-er-diagram.sh` 四个**被跟踪文件出现纯行尾（CRLF）抖动、内容零差异** ⇒ 还原姿势 `git checkout HEAD -- <文件>`（本侧 `Tools/*.ps1` 一律 UTF-8 带 BOM 的纪律不受影响）。

## 先跑闸门

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\Tools\verify-all.ps1
```

收尾行会如实报「跑了哪些 / 跳过哪些」——**跳过不是「已通过」**（§8.3.2）。

## 构建 / 跑基准

```bash
cd windows
cd App && npm install && npm run build && cd ..   # 前端产物必须先于 cargo（Tauri 编译期把 dist 嵌进产物）
cargo build --release --workspace \
  --features doyah-studio-shell/custom-protocol            # **生产形态**（前端产物嵌进可执行文件）
#   不带 custom-protocol ⇒ 产物会去连 devUrl（http://localhost:5274），盘上没 dev server 时是空窗口
#   （实测缺陷，第 28 轮；`Tools/build.ps1` 已按生产形态构建并机械核对）
cargo test --workspace                                     # 单测
cd App && npm run tauri dev                                # 真外壳（WebView2 承载）；纯前端调试用 npm run dev → http://localhost:5274
cd App && npm test && npm run check:tokens                 # 前端单测 + 令牌生成物/棘轮
cargo run --release --bin grid-bench -- --rows 400000 --cols 20 \
  --data-dir Bench/grid/public/data --out Bench/grid/public/data/rust-result.json
cd Bench/grid && npm install && npm run dev                # 基准台 → http://localhost:5273/?bench=1
```

用法、判据归属、实测坑见 `Tools/README.md`；基准读数与**口径限制**见 `Bench/grid/README.md` 与概要设计 §8.5.6-3。
