# windows/App —— Doyah Studio 的 Windows 侧**表示层**（Tauri 2 外壳 + Vue 3 + TypeScript）

**性质**：产品形态（不是基准台）。领域层在 `../Core`（Rust，零 UI / 平台依赖），本目录只做表示与取数接线。
栈见 §8.5.1；本目录 = `[独占:windows]` 实现层，可替换实现，**不得改变 §3 的契约与不变量**。

## 目录

| 路径 | 作用 |
|---|---|
| `src-tauri/src/query.rs` | 结果集取数的**可测内核**（数据集 / 排序置换缓存 / 窗口取数；**不依赖 tauri**，`cargo test` 判得了） |
| `src-tauri/src/lib.rs` | `#[tauri::command]` 命令层（只转发）+ `generate_handler!` 注册 |
| `src-tauri/src/main.rs` | 可执行入口（发布构建不弹控制台） |
| `src-tauri/tauri.conf.json` | Tauri 配置（窗口 / CSP / `frontendDist = ../dist` / bundle MSI + NSIS） |
| `src-tauri/capabilities/default.json` | 能力集：**只有 `core:default`**（不引任何插件） |
| `src-tauri/icons/` | 应用图标 —— **生成物**（`tools/gen-icons.mjs`，底色取自令牌 `--ds-color-categorical-blue`） |
| `src/ipc.ts` | 前端 ↔ Rust 的唯一出入口（命令名 `COMMANDS` + **浏览器旁路** mock） |
| `src/grid/windowing.ts` | 窗口取数的纯函数（要哪一片 / 上下留多少占位） |
| `src/theme/index.ts` | 主题档位（system / light / dark）+ 变量名拼法 |
| `src/theme/tokens.generated.css` | **生成物**（令牌取值投影；不许手改） |
| `src/theme/app.css` | 平台级合成（字体回退栈 `P-20`、发丝线 / 叠加层的底色与令牌透明度合成） |
| `src/shell/` `src/views/` | 外壳（标题栏 / 侧栏 / 状态栏）与视图（结果网格） |
| `tools/gen-tokens.mjs` | 令牌生成器（Swift 源 → CSS 变量），`--check` 判漂移 |
| `tools/token-ratchet.mjs` | 裸值棘轮（六条**与 mac 基线同名**的规则）+ **引用面 ⊆ 定义面** |
| `tools/gen-icons.mjs` | 图标生成器，`--check` 判漂移 |

## 跑起来

```bash
cd windows/App
npm install

npm run dev            # 纯浏览器（走 ipc.ts 的旁路 mock）→ http://localhost:5274
npm run tauri dev      # 真外壳（WebView2 承载；Rust 侧 IPC 供数）
npm run test           # vitest（前端单测 + 令牌工具自测）
npm run typecheck      # tsc --noEmit
npm run build          # 前端产物 → dist/（Tauri 编译期要它，**必须先于 cargo build**）
npm run check:tokens   # 令牌生成物 ⇄ 源 一致 + 裸值棘轮
```

Rust 侧（在 `windows/` 下，工作区）：

```bash
cargo test --workspace            # Core 15 例 + 本目录 query 6 例 + ipc_contract 2 例
cargo build --release --workspace # 产物 windows/target/release/doyah-studio.exe
```

## 设计要点（都是踩过才这么写的）

1. **令牌取值只有一处来源** = macOS 侧 `Core/DesignTokens.swift`。本目录不抄值：`tools/gen-tokens.mjs` 把它翻成 CSS 变量（**分组条数写死在 `EXPECTED` 里** —— 对侧改名 / 删项 / 加项即非零退出，不静默少几个变量；颜色枚举里出现「不是字面量 `ThemeColor`」的 case 必须显式登记进 `ALIASES`）。生成物与源不一致 = 判红。
2. **裸值棘轮**（`bare-color` / `bare-font` / `bare-spacing` / `bare-radius` / `bare-textstyle` / `bare-foreground`，**与 mac 侧 `Scripts/design-token-baseline.json` 同名**）：基线 `windows/Tools/design-token-baseline.json`，**只降不升**；扫描集为空即判红（不许「扫了个空」当通过）。
3. **引用面 ⊆ 定义面**：`var(--ds-*)` 里拼错的变量名在 Vue / CSS 里**不报错、只是不生效** —— 这是最难发现的一类静默失效，所以单独判（实测当场抓到 `app.css` 三处拼错的叠加层变量名）。
4. **前端不持有整份结果集**：只按可视窗口向 Rust 侧要 `len` 行（`grid/windowing.ts` 算窗口、`query.rs` 切片）。行高读 `--ds-metric-row-height`，**读不到就如实标「用了回退值」**。
5. **IPC 双向判据**：`src-tauri/tests/ipc_contract.rs` 按文本判「前端 `COMMANDS` ⊆ 本层注册」且「本层注册的都被前端用」—— 前端 `invoke` 打错名字是**运行时静默失败**，没有东西会红。
6. `npm run build` 必须**先于** `cargo build`：Tauri 在编译期把 `frontendDist` 嵌进产物（`Tools/build.ps1` 已按这个顺序编排）。

## 现状（不半建）

- ✅ 外壳 + 结果网格（走「Rust 侧切片喂前端」这条路）；令牌层与两条工具判据；图标生成。
- ⬜ 侧栏其余分区（连接 / 笔记 / 设置）只有占位 —— 未开工。
- ⬜ `Cli/`（无界面验证入口）与 `Platform/Windows/`（凭据 / ConPTY / 通知）未建。
- ⬜ **WebView2 + GPU 下的基准复测未做**：`Bench/grid/README.md` 的读数是无头软件光栅 + 同一块 `ArrayBuffer` 切片，**不含 IPC 与 GPU 合成** ⇒ 三候选（TanStack Virtual / AG Grid Community / Rust 侧切片）的取舍结论**仍待复测**（§8.5.6-3）。
- ⬜ 版本号一致性（`package.json` / `tauri.conf.json` / `Cargo.toml` 三处 + 与 mac 侧发布台账 `Scripts/release-version.json`）**尚无判据**，本轮如实登记为下一轮待办。
