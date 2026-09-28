# windows/ —— Doyah Studio 的 Windows 侧（另一平台）实现落点

对应设计：`Docs/概要设计.md` **§8.2**（仓库结构：同仓 `windows/` 块）与 **§8.5 契约 → Windows 实现 `[独占:windows]`**。
本目录 = **实现层**：可以替换实现，**不得改变 §3 的契约与不变量**；要改契约走 `Docs/proposals/`。

**技术栈（2026-09-28 需求提出者开工令）**：前端 **Tauri 2 + Vue 3 + TypeScript**、后端 **Rust**、测试 `cargo test` + `vitest`、分发 Tauri bundler（MSI / NSIS）。原 .NET（C# / WPF / xUnit）路线**作废**；与契约字面（§8.2 树 / §3 GUI 框架行 / SRS §10.9 的 `P-19`·`P-23`·`P-24` /「原生界面栈」）的冲突走 **`Docs/proposals/0004`**（待采纳），本侧不自行放宽契约。

## 现在有什么

| 目录 | 层 | 现状 |
|---|---|---|
| `Tools/` | 闸门（§8.3.1 六项必需项 + §8.5.6-3 基准项） | ✅ 13 项一条命令跑全（见 `Tools/README.md`） |
| `Cargo.toml` / `Core/` | 领域层（Rust；零第三方依赖、零 UI / 平台依赖） | 🟡 首片已落地（合成数据集 / 排序筛选 / 窗口取数 / `grid-bench`；`cargo test` 15 例） |
| `Bench/grid/` | 结果集网格压力基准台（Vue 3 + TS + Vite + TanStack Virtual） | 🟡 首片已落地（见 `Bench/grid/README.md`） |
| `App/` | 表示层（Tauri 2 外壳 + Vue 3 + TS） | 🟡 首片已落地（外壳 + 结果网格走「Rust 侧切片」+ 令牌层；前端 `vitest` 24 例、本目录 Rust 8 例；见 `App/README.md`） |
| `Cli/` | 无界面验证入口（Rust 二进制：子命令 + 退出码表 + `--json`） | ⬜ 未建 |
| `Platform/Windows/` | 平台适配层（凭据管理器 / ConPTY / 通知；唯一引 Windows 专有 API 处） | ⬜ 未建 |
| `Tests/` | 单测（Rust `cargo test` + 前端 `vitest`） | 🟡 47 例（Core 15 + App Rust 8 + 前端 24），随层增长 |

**未接网的账（如实登记，别当成已完成）**：

- ~~`Tools/check-core-boundary.ps1` 只认 C# 形态~~ ⇒ **已销账（第 25 轮）**：判据按 **Rust 形态**重建（`Cargo.toml` 依赖面 + `Core/**/*.rs` 源码面 + 空跑判红），判据与 **7 例自测**一次调用里都真跑，见 `Tools/README.md`。
- ~~`Tools/check-design-tokens.ps1` 的 Windows 侧棘轮要等 `App/` 落地~~ ⇒ **已销账（第 26 轮）**：`App/` 落地后 ③ 交给表示层自己的 node 判据（`App/tools/gen-tokens.mjs --check` + `token-ratchet.mjs`），本项**不再有跳过档**（见 `Tools/README.md`）。
- **`App/` 侧新账（如实登记，别当成已完成）**：① **版本号一致性没有网** —— `App/package.json` / `src-tauri/tauri.conf.json` / `src-tauri/Cargo.toml` 三处版本号 + 与 mac 侧发布台账（`Scripts/release-version.json`）的对应关系**尚无判据**（下一轮按 `Scripts/check-release-version.py` 的规则名重建）；② **WebView2 + GPU 下的基准复测未做** —— `Bench/grid` 的读数是无头软件光栅、且不含 IPC 与 GPU 合成 ⇒ 三候选的取舍结论仍待复测（§8.5.6-3）。
- 契约侧 **L-46**（语言表模板 ↔ 调用点实参）判的是 Swift 源码 ⇒ 本端等价判据待本地化层落地后按同规则名重建。

## 先跑闸门

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\Tools\verify-all.ps1
```

收尾行会如实报「跑了哪些 / 跳过哪些」——**跳过不是「已通过」**（§8.3.2）。

## 构建 / 跑基准

```bash
cd windows
cd App && npm install && npm run build && cd ..   # 前端产物必须先于 cargo（Tauri 编译期把 dist 嵌进产物）
cargo build --release                                      # Rust 侧（工作区：Core + App/src-tauri）
cargo test --workspace                                     # 单测
cd App && npm run tauri dev                                # 真外壳（WebView2 承载）；纯前端调试用 npm run dev → http://localhost:5274
cd App && npm test && npm run check:tokens                 # 前端单测 + 令牌生成物/棘轮
cargo run --release --bin grid-bench -- --rows 400000 --cols 20 \
  --data-dir Bench/grid/public/data --out Bench/grid/public/data/rust-result.json
cd Bench/grid && npm install && npm run dev                # 基准台 → http://localhost:5273/?bench=1
```

用法、判据归属、实测坑见 `Tools/README.md`；基准读数与**口径限制**见 `Bench/grid/README.md` 与概要设计 §8.5.6-3。
