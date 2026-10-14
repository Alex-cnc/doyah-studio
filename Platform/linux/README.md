# Linux 端（Doyah Studio 全量 PC 端第三端）

**归属**：`babyhippo`（奶牙小河马）—— 2026-10-14 人类主人令「Doyah Studio 全量 PC 端还要补一个 Linux 平台，小河马负责的」。
**状态**：🟡 **骨架已落地**（开工方案 + 构建入口 + 应用工程骨架 + 前端同源装配；派单 `T-20261014-016`，实现按片推进）。
**平台设计层**：`Docs/概要设计.md` **§8.6 契约 → Linux 实现 `[独占:linux]`** —— 设计层文字归那一节，本页只放**骨架与命令面**，不另立一份设计（避免同一件事两处写）。

## 定位（一句口径）

Linux 与 macOS / Windows 是**同级的「全量 PC 端」** —— 目标是**功能一致**（需求规范书 §1 原话），不是降级子集。
平台差异照旧逐条登记在 `Docs/概要设计.md`（差异表 §10.9 / 等价矩阵 §10.10）。

## 技术栈（契约层已落 · 概要设计 §2 GUI 框架行 v2.169）

- **Tauri 2**（Rust 壳）+ **系统 WebView = WebKitGTK（`webkit2gtk-4.1`）** 承载界面；
- **复用同一套 Vue 3 / TypeScript 前端**（Windows 侧即 Tauri 2 + WebView2 ⇒ 前端同源，同源面 = `Platform/windows/App/`）；
- 与总契约自洽：**原生界面栈** · **不打包浏览器内核** · **不含虚拟机运行时**（不用第二套 GUI 工具包重写一遍界面）。

## 骨架（本目录 · 盘上实物）

| 路径 | 层（§8.6.1 表） | 现状 |
|---|---|---|
| `build.sh` | 构建入口（§8.6.2） | ✅ 一条命令 + 退出码表 5 档（0/1/2/3/4）+ 交付物身份四项 |
| `src-tauri/` | 表示层外壳（Tauri 2 + WebKitGTK） | ✅ 壳 + 命令面（平台能力表 / 启动前置报告）；**编译未验**（本机非 Linux 宿主） |
| `src-tauri/Core/` | 领域层（纯逻辑） | ✅ 零第三方依赖 · 交付物身份四项 + 能力取值解析 · `cargo test` **9 例**（本机已跑） |
| `src-tauri/Cli/` | 无界面验证入口 | ✅ 子命令 + 退出码表 + `--json`；本机实跑见下（**rc=2**：非 Linux 宿主缺 4 项） |
| `src-tauri/Platform/Linux/` | 平台适配层 | 🟡 **能力探测**（六项，存在性检查；不手写 FFI）· `cargo test` **4 例**；**真绑定未接**（见未接网清单） |
| `Tools/check-linux-skeleton.py` | 本端判据（骨架 / 领域层边界 / 前端同源） | ✅ rc=0 · 自测 **9/9** |

**前端同源**：本目录**没有** `App/` —— 界面就是 `Platform/windows/App/`（`src-tauri/tauri.conf.json` 的 `frontendDist` / `devUrl` 指过去）。
判据 D 条把这条钉死：`frontendDist` 解析结果必须落在同源面，且**盘上不许出现本端自存的 `App/` 或 `dist/`**。

## 构建入口（一条命令）

```
Platform/linux/build.sh --deps     # 依赖探测（只读；缺项逐条点名）
Platform/linux/build.sh            # 前端装配（同源目录 npm ci）+ 构建 + 打包，收尾打印交付物身份四项
python Platform/linux/Tools/check-linux-skeleton.py --self-test   # 本端判据（骨架 / 领域层边界 / 前端同源）
```

依赖：`cargo`（Tauri 2 需 Rust ≥ 1.77）· `webkit2gtk-4.1` 与 `libgtk-3-dev` / `librsvg2-dev` / `libayatana-appindicator3-dev`（经 `pkg-config` 探测）· Node ≥ 20 + **npm**。
**非 Linux 宿主机**上脚本**不假装能构建**：打印缺项 + 说明，**退出码 2**（如实，不当绿）；应用骨架未落地退出码 `3`；同源前端缺失退出码 `4`。

## 打包形态

- **`.deb`** —— Debian / Ubuntu 系（公司环境与常见发行版）：系统包管理器安装、依赖自动解析；
- **`.AppImage`** —— 跨发行版便携（免安装、单文件）；
- **交付物身份四项**（**目录 / 标签 / `sha256` / 构建时刻**）由 `build.sh` 收尾打印，身份卡随包走。
- 命名与发布形态跟 `Docs/发布方案.md` / `Docs/发布计划.md`；Linux 端**在本仓构建**，**公司环境可作构建与验机场地**（沿用「不填个人凭据」纪律）。

## 桌面集成（对应 §3 契约的落地）

- **菜单**：应用内菜单栏（Tauri menu API）；
- **快捷键**：与 Windows 端同键位，冲突处逐条登记在 §8.6；
- **文件关联**：笔记库 / 导出件的后缀关联走 `.desktop` 的 `MimeType`；
- **深色跟随**：跟随系统主题（WebKitGTK 的 `prefers-color-scheme`）；
- **凭据 / 目录授权 / 终端 / 通知 / 剪贴板**：按 §3 契约逐条落，**不适用就写「不适用」**（逐条登记在 §8.6）。

## 实测读数（2026-10-14 · 宿主 = Windows 开发机，`uname -s` = `MINGW64_NT-10.0-26300`）

| 命令 | rc | 读数 |
|---|---|---|
| `bash Platform/linux/build.sh --deps` | **1** | `cargo` / `node` / `npm` 在；`webkit2gtk-4.1` / `gtk+-3.0` / `libayatana-appindicator3-0.1` **缺 3 项**（逐条点名） |
| `bash Platform/linux/build.sh` | **2** | 非 Linux 宿主 ⇒ **如实拒绝**，并指向对应端的入口 |
| `cargo test -p doyah-studio-core -p doyah-studio-linux-platform -p doyah-studio-linux-cli` | **0** | Core **9 例** / Platform **4 例** 全过（CLI 只编译，无单测） |
| `doyah-studio-cli capabilities` | **2** | `webview missing` · `secret-service missing` · `pty present` · `notifications missing` · `clipboard present`（X11）· `tray missing` —— 非 Linux 宿主如实读数，**unknown 不计入缺失** |
| `python Platform/linux/Tools/check-linux-skeleton.py --self-test` | **0** | 骨架 / 边界 / 同源三条干净（工作区 3 层 · Core 依赖 **0** 条 / 源文件 3 个）· 自测 **9/9** |

## 未接网清单（如实；逐条销账后才算「已落」）

| # | 项 | 现状 | 销账条件 |
|---|---|---|---|
| 1 | **真构建与安装包**（`.deb` / `.AppImage`） | ⬜ 未跑（非 Linux 宿主、无 WebKitGTK 开发包） | Linux 宿主上 `build.sh` rc=0 且打出包 + 身份四项 |
| 2 | **前端同源指向的构建期验证**（`frontendDist` 指向仓外同源面，Tauri 是否接受该相对路径） | 🟡 静态判据已钉（指向同源面 + 不另存一份），**构建期未验** | Linux 宿主真构建通过；若不接受 ⇒ 退路 = 同源 `dist` 软链进本目录（判据 D 条同步跟版） |
| 3 | **WebKitGTK 真绑定**（版本查询 / 缺版本给什么提示，§8.6.6 待定项 3） | 🟡 现为存在性探测（`Present` = 前置在盘上，**不等于接口可用**） | 接 `webkit2gtk` 版本查询 + 与 Windows 侧 `P-26` 口径对齐 |
| 4 | **密钥环真绑定**（Secret Service：`keyring` crate） | ⬜ | 取 / 存 / 清各一条端上判据；**无密钥环时如实报错、不回落明文** |
| 5 | **PTY 真绑定**（`portable-pty`）+ 屏幕模型接线 | ⬜ | 起真交互 shell + §3.7 屏幕模型判据 |
| 6 | **`.desktop` 集成**（文件关联 / 图标 / 菜单项集合） | ⬜ | 安装包内 `.desktop` 逐项对账 |
| 7 | **本端判据接进本仓闭环**（`Scripts/verify-all.sh` 的 Linux 分支调用本件） | ⬜ | `Scripts/` 属共享面 ⇒ 走 shared_ledger 登记后接（下一片） |

**包管理器收口（一处口径订正）**：§8.6.1 原写「Node ≥ 20 + **pnpm**（与 Windows 侧同包管理器）」，而**实体前端**是 `Platform/windows/App/`（里面有 `package-lock.json`、Windows 侧 `Tools/build.ps1` 用 `npm run build`）⇒ 骨架片按**实体前端**收口为 **npm**（`build.sh` 探测项与 `tauri.conf.json` 的 `beforeBuildCommand` 都已是 npm），并在 §8.6.1 就地登记。

## 自检

`Scripts/verify-all.sh`（Linux 宿主按 `uname -s` 自动取 `DOYAH_PLATFORM_SIDE=linux`，无需额外参数）；
本端专属自检命令 = `python Platform/linux/Tools/check-linux-skeleton.py`（骨架 / 领域层边界 / 前端同源；**空跑判红**，退出码 0/1），实测读数见上表与 §8.6.6；接进本仓闭环（`Scripts/verify-all.sh`）属共享面，列在「未接网清单」第 7 项。
