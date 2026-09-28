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
| `App/` | 表示层（Tauri 2 外壳 + Vue 3 + TS） | ⬜ 未建 |
| `Cli/` | 无界面验证入口（Rust 二进制：子命令 + 退出码表 + `--json`） | ⬜ 未建 |
| `Platform/Windows/` | 平台适配层（凭据管理器 / ConPTY / 通知；唯一引 Windows 专有 API 处） | ⬜ 未建 |
| `Tests/` | 单测（Rust `Core/tests/` + 前端 vitest） | 🟡 20 例（Core 15 + 前端 5），随层增长 |

**未接网的账（如实登记，别当成已完成）**：

- `Tools/check-core-boundary.ps1` 现只认 C# 形态（`.csproj` / `DllImport`）⇒ **换栈后需按 Rust 形态改写**（扫 `Cargo.toml` 依赖与源码里的 GUI / 平台 crate 名）。
- `Tools/check-design-tokens.ps1` 的 Windows 侧棘轮要等 `App/` 落地（规则名对齐 + 令牌源在盘两项已 ✅）。
- 契约侧 **L-46**（语言表模板 ↔ 调用点实参）判的是 Swift 源码 ⇒ 本端等价判据待本地化层落地后按同规则名重建。

## 先跑闸门

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\Tools\verify-all.ps1
```

收尾行会如实报「跑了哪些 / 跳过哪些」——**跳过不是「已通过」**（§8.3.2）。

## 构建 / 跑基准

```bash
cd windows
cargo build --release                                      # Rust 侧（工作区）
cargo test --workspace                                     # 单测
cargo run --release --bin grid-bench -- --rows 400000 --cols 20 \
  --data-dir Bench/grid/public/data --out Bench/grid/public/data/rust-result.json
cd Bench/grid && npm install && npm run dev                # 基准台 → http://localhost:5273/?bench=1
```

用法、判据归属、实测坑见 `Tools/README.md`；基准读数与**口径限制**见 `Bench/grid/README.md` 与概要设计 §8.5.6-3。
