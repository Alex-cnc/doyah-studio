# platform/windows/ —— Doyah Studio 的 Windows 侧（另一平台）实现落点

对应设计：`Docs/概要设计.md` **§8.2**（仓库结构：同仓 `platform/windows/` 块）与 **§8.5 契约 → Windows 实现 `[独占:windows]`**。
本目录 = **实现层**：可以替换实现，**不得改变 §3 的契约与不变量**；要改契约走 `Docs/proposals/`。

**技术栈（2026-09-28 需求提出者开工令）**：前端 **Tauri 2 + Vue 3 + TypeScript**、后端 **Rust**、测试 `cargo test` + `vitest`、分发 Tauri bundler（MSI / NSIS）。原 .NET（C# / WPF / xUnit）路线**作废**；与契约字面（§8.2 树 / §3 GUI 框架行 / SRS §10.9 的 `P-19`·`P-23`·`P-24` /「原生界面栈」）的冲突走 **`Docs/proposals/0004`**（待采纳），本侧不自行放宽契约。

## 版本计划（先看这个）

**`platform/windows/版本计划.md`** —— 本侧（Windows）的功能模块地图与子版本进度：**alpha 1.0 = Database · 2.0 = Workspace · 3.0 = Notes · 4.0 = Retro · beta 1.0 = 全量整合**，模块内递子号（`1.1` / `1.2` / `3.1` / `3.2` …）。含每个子版本的**出口判据**（主链跑通 + 闸门全绿 + 如实报数）、与 §8.5.4「一样」清单 / 冻结纪律的对齐、以及「本侧不做」清单。**节奏与范围已由老板拍板（§0.1）**：里程碑编号与 macOS 侧对表、**日期不追**（只写次序 + 出口，不写交付日）、每个模块做**完整版**、子号是**进度段位**。

## 现在有什么

| 目录 | 层 | 现状 |
|---|---|---|
| `Tools/` | 闸门（§8.3.1 六项必需项 + §8.5.6-3 基准项 + §8.3 的生成物一致性） | ✅ 14 项一条命令跑全（见 `Tools/README.md`） |
| `Cargo.toml` / `Core/` | 领域层（Rust；零第三方依赖、零 UI / 平台依赖） | 🟡 首片已落地（合成数据集 / 排序筛选 / 窗口取数 / `grid-bench`；`cargo test` 15 例） |
| `Bench/grid/` | 结果集网格压力基准台（Vue 3 + TS + Vite + TanStack Virtual） | 🟡 首片已落地（见 `Bench/grid/README.md`） |
| `Bench/webview2/` | **真机基准仪器**（起真外壳 + CDP 注入驱动：空转对照 / 三档行数滚动 / **慢速滚动与样式消融档** / **变更观察档** / 「invoke 可替换性」探测 / 同轮内基线复跑 / `--quick` 交替 A/B / 进程树内存） | ✅ 已落地（第 28 轮，第 29 轮修掉消融档一处静默失效；**第 30 轮落产品侧行池 + 前瞻取数 + 单格绘制，同轮 A/B p50 49.6 → 26.2 ms**；读数、仪器地板与口径限制见 §8.5.6-3 与 `Bench/webview2/README.md`） |
| `App/` | 表示层（Tauri 2 外壳 + Vue 3 + TS） | 🟡 首片已落地（外壳 + 结果网格走「Rust 侧切片」+ 令牌层；前端 `vitest` 39 例（含令牌生成器 / 棘轮的 node 自测）、本目录 Rust 8 例；见 `App/README.md`） |
| `Cli/` | 无界面验证入口（Rust 二进制：子命令 + 退出码表 + `--json`） | ⬜ 未建 |
| `Platform/Windows/` | 平台适配层（凭据管理器 / ConPTY / 通知；唯一引 Windows 专有 API 处） | ⬜ 未建 |
| `Tests/` | 单测（Rust `cargo test` + 前端 `vitest`） | 🟡 62 例（Core 15 + App Rust 8 + 前端 39），随层增长 |

**未接网的账（如实登记，别当成已完成）**：

- ~~`Tools/check-core-boundary.ps1` 只认 C# 形态~~ ⇒ **已销账（第 25 轮）**：判据按 **Rust 形态**重建（`Cargo.toml` 依赖面 + `Core/**/*.rs` 源码面 + 空跑判红），判据与 **7 例自测**一次调用里都真跑，见 `Tools/README.md`。
- ~~`Tools/check-design-tokens.ps1` 的 Windows 侧棘轮要等 `App/` 落地~~ ⇒ **已销账（第 26 轮）**：`App/` 落地后 ③ 交给表示层自己的 node 判据（`App/tools/gen-tokens.mjs --check` + `token-ratchet.mjs`），本项**不再有跳过档**（见 `Tools/README.md`）。**第 30 轮再补**：对侧把令牌值表**按主题分组**（新增 `Core/DesignTheme.swift`）⇒ 本侧生成器改**双源**、产出**两件生成物**（每主题变量块 `[data-theme-scheme=…]` 的 CSS + 主题集 `src/theme/themes.generated.ts`），外壳加**同名下拉**（候选与「推导草案」标记由生成物派生），发丝线浅色档改**源侧实色**。
- ~~`App/` 侧的版本号一致性没有网~~ ⇒ **已销账（第 27 轮）**：发布产物版本号 `0.2.0`（三处逐字一致）由判据 `Tools/check-release-version.ps1` + 台账 `Tools/release-version.json` 机械判（闸门**第 13 项**）—— 三处各改一处都判红并点名、缺键也判红，另判**与 mac 侧发布台账同源**（不等即判红，对侧 `buildVersion` 不跟随）。
- **仍未接网（如实登记，别当成已完成）**：① ~~**WebView2 + GPU 下的基准复测未做**~~ ⇒ **已销账（第 28 轮）**：仪器 `Bench/webview2/` 已落地并跑出真机读数（真 GPU = ANGLE / Intel Iris Xe D3D11）—— 空转 16.7 ms（60 fps）而**滚动 40 万行 p50 50.1 ms（19.3 fps）**，且**行数无关 + IPC 无关**两档诊断把瓶颈指向「每帧重建可视行 DOM + 重排版 / 重绘」⇒ **复测做了，但这一关没过**：三候选取舍仍挂着，见 §8.5.6-3。**（第 30 轮进展）**产品侧三处（**行池 + 轮转槽位** / **前瞻取数 `LOOKAHEAD=12`** / **单格绘制 `clip` + 行 `contain`**）按同轮 A/B 把 p50 从 **49.6 ms 降到 26.2 ms（−47%）**、**内容成本（p50 − 同轮空转地板）31.7 → 8.3 ms**（已低于一个 16.7 ms 帧预算）；但**仪器自己的空转地板就是 ≈17.9 ms（≈56 fps）⇒ 60 fps 这一关无法由本仪器读出**，口径待需求提出者拍板 ⇒ 三候选取舍仍挂着。**（第 29 轮更正）**上一轮那条「IPC 无关」诊断**已作废** —— 它是仪器里一处**静默失效的消融档**（宿主把 `__TAURI_INTERNALS__.invoke` 定义成不可写 + 不可配置，页面里的替换从未生效；铁证 = 该档 `cachedWindowCalls: 0`）；第 29 轮换成**慢速滚动消融档**（不改页面代码）并把成本重新钉在「写 DOM + 重排版 / 重绘」上：**慢速滚动 17.9 ms 对同轮基线 79.1 ms**（跨会话漂移 > 50%，只有同轮内的一对可以相减）；② **装出来的 MSI / NSIS 里读到的版本号未实测** —— 本侧判据判的是**源**，要真跑一次 Tauri bundler 再读产物元数据；③ 本侧这个值三处**都是源**，仓内没有携带它的生成物（`dist/` 与 `target/` 都不入库）⇒「生成物 ↔ 源」那一半无对象。
- 契约侧 **L-46**（语言表模板 ↔ 调用点实参）判的是 Swift 源码 ⇒ 本端等价判据待本地化层落地后按同规则名重建。

**对侧两笔合流后的本侧适用性（Windows 侧第 31 轮，2026-10-01）**：对侧本轮推两笔 —— **`L-144`**（概要设计 **§3.30【契约】**：工作区 chrome 行 / 页签条的高度**只由内边距与字高决定**，不随内容、页签数量、窗口宽度变；量法 = 离屏 `sizeThatFits`，随门禁每轮跑）与 **`L-149` ③④**（**内置浏览器页签的归属 = 工作区**，与 Home / 文件页签同类，**不是**数据库 SQL 工作台的页签；旧措辞「编辑器区」已作废）。本侧据此登记两条等价义务（**暂不动代码** —— Studio 不在当前队列，Notes 安卓未完工）：① 表示层出现页签时**只画一条**页签条（浏览器与 Home / 文件同类），**高度不随内容 / 数量 / 宽度变**；② 浏览器页签**不得**挂进数据库侧视图（对侧判据 `Scripts/check-browser-tab-ownership.py` 的正面口径），AppKit 窗口标题栏那一层仍归人工点验。**该判据在本机（Windows）实测可跑且绿**（本侧无 Swift 表示层对象，先只读登记）；`P-14` 的行为契约与「引擎可换」那半一字未变。

**对侧两笔合流后的本侧适用性（Windows 侧第 32 轮，2026-10-01）**：对侧本轮推两笔 —— **`L-149①`**（`db609bd`：内置浏览器的**页签状态**从 `AppState` 搬进 `App/WorkspaceBrowserModel.swift` —— 页签集 / 选中 / 引擎缓存 / 新建·选中·关闭 / 地址栏导航 / 会话恢复与落盘；宿主只留下载目录 / 外发留痕 / 失败告知，形状由 `WorkspaceBrowserHost` 协议定；**并删掉数据库侧最后一处浏览器耦合**（`QueryWorkspaceView` 不再读浏览器选中态））与 **`b186a26`**（概要设计变更行多出一格的表格修复，纯文档）。本侧据此**补登记一条等价义务**（**暂不动代码** —— Studio 不在当前队列，Notes 安卓未完工）：③ **浏览器页签的状态所有者只此一处** —— 本侧对应物 = 表示层一个具名具状态（前端 store / Rust 侧单点），**不得散落**在多个 store 或窗口级全局；**宿主只提供三件事**（下载目录 / 外发留痕 / 失败告知）并以宿主接口注入；**数据库侧视图不得读浏览器选中态**（与 ② 同向、更严：连「读」都不许）。对侧判据 `Scripts/check-browser-tab-ownership.py` **在本机实测可跑且绿**（状态所有者 = `App/WorkspaceBrowserModel.swift` 只此一处 / 落点全部在台账内 / 数据库侧零命中 / 台账逐条真命中）—— 本侧无 Swift 表示层对象，故先只读登记。**本机全量扫一遍对侧共享判据（供两侧参照）**：`Scripts/check-*.py` **43 条 = 34 绿 / 9 红**，9 红逐条归属为**环境面或本地缺档**，无一与本轮合流相关 —— `check-design-tokens.py` / `check-design-mock-tokens.py`（要 macOS 侧生成的令牌基线）/ `check-doc-numbers.py` + `check-doc-tables.py` + `check-terminal-tabs.py` + `check-release-version.py`（受检的本地文档被 gitignore：`Docs/循环台账.md` / `Docs/design/开发循环-任务队列.md` / `Docs/发布方案.md`）/ `check-terminal-palette.py` + `check-ui-snapshot-languages.py`（要 `.build` 产物 / UI 快照清单）/ `check-self-test-counts.py`（跑全量自测，超时；且会带出 `Scripts/lib/*` 四个被跟踪文件的**纯行尾抖动** ⇒ 还原姿势 `git checkout HEAD -- <文件>`，本轮已还原、工作区回 0 脏）。

**本机（Windows）跑对侧共享判据的实况（第 31 轮实测，供两侧参照）**：`Scripts/` 下 13 条跨平台判据在本机 **9 绿 / 4 红，4 红全部与本轮合流无关** —— `check-doc-tables.py` 红因**本侧循环镜像台账** `Docs/循环台账.md`（`/Docs/*` 已 gitignore，但它是「有表格却不在受检清单」的本地文档）⇒ 连带 `check-doc-numbers.py` 的 `[doc-tables-files]` 一项红；`check-release-version.py` 与 `check-self-test-counts.py` 红因**本机没有那两份被 gitignore 的本地文档**（`Docs/发布方案.md` / `Docs/design/开发循环-任务队列.md`）。另有一处纯环境现象：跑 `Scripts/check-self-test-counts.py`（它会实跑各判据自测）后，`Scripts/lib/test-env.sh` / `real-db-scripts.txt` / `remote-bypass-scripts.json` / `test-er-diagram.sh` 四个**被跟踪文件出现纯行尾（CRLF）抖动、内容零差异** ⇒ 还原姿势 `git checkout HEAD -- <文件>`（本侧 `Tools/*.ps1` 一律 UTF-8 带 BOM 的纪律不受影响）。

**对侧一笔合流后的本侧适用性（Windows 侧第 33 轮，2026-10-01）**：对侧本轮推一笔 —— **`L-137` 第三片**（`d1789aa`：**工作区 Markdown 只读预览**。新增 `App/Views/MarkdownPreviewView.swift`（块级模型 → SwiftUI 视图树；**行内 span 复用契约层「一处解析」的产物** `NoteBodyProjection.parseInline`，`App/` 里不引第二套解析；围栏代码块复用 `CodeLexer` + `SyntaxTone`）；`WorkspaceTabsModel.previewVisible` 开关 + `WorkspaceAreaView` 的 `HSplitView` 分屏 + 提示条开关；`CodeEditorView.onCursorLine` 上报光标行（行号复用 `Core/CodeLines`）+ `MarkdownPreviewCursorModel` 去重；6 条文案进语言表（中英）；**概要设计 §3.29 补「渲染侧三条口径」：只读 / 落点 = 顶层块下标 / 如实报数**）。本侧据此登记**一条等价义务（④）**（**暂不动代码** —— Studio 不在当前队列，Notes 安卓未完工）：

④ **预览 = 「一份解析、两个消费者」**：本侧表示层将来做笔记 / 工作区 Markdown 预览时 —— ① **块级模型只许核心层构造**（表示层不得自己造块，也**不得引第三方 Markdown 解析库**）；② **行内 span 必须与编辑器 / 渲染共用同一处解析实现**（各写一套即判红）；③ 渲染侧守三条 —— **只读**（预览不是第二个编辑器 ⇒ 渲染树里不许出现可编辑控件）/ **滚动落点 = 顶层块下标**（嵌套子块只滚到它的顶层块，越界什么都不做）/ **如实报数**（超限截断时给计数，干净文档一行不多）。对侧判据 `Scripts/check-markdown-single-source.py` **在本机（Windows）实测可跑且绿**（行内扫描器唯一定义在 `Core/NoteBody.swift` / 块级模型唯一产地 `Core/MarkdownDocument.swift`（9 处构造）/ 同源调用 6 处 / 无第三方解析库 / 解析层用例 35 个）；本侧无表示层预览对象，故先只读登记。**另**：对侧 `Scripts/panel-root-frames.json` 扫描范围 `App/Views/` **76 → 77**（多一个文件）—— 本侧对应物是**自己那份**目录扫描台账（`Tools/check-p-parity.ps1` 同族），等表示层铺开时按同名规则重建，别把对侧的台账当本侧的基线。

**对侧两笔合流后的本侧适用性（Windows 侧第 34 轮，2026-10-01）**：对侧本轮推两笔 —— **`L-141`**（`61f4ea9`：**标题栏搜索栏的宽度从系统手里收回来**。由头 = 需求提出者内测清单**甲1**原话「不是全屏时搜索框没有同步缩小，遮住了 `Doyah Studio - Workspace` 标题」；根因 = 搜索栏原走系统 `.searchable(placement: .toolbarPrincipal)`，**宽度由系统给、与窗口宽度无关**。订正后：位置**仍居中**（`ToolbarItem(placement: .principal)`），宽度改由**契约层纯函数** `Core/TitleBarSearchLayout.swift` 算 —— 居中 ⇒ **两侧对称让位**、理想 360 / 最小 180、连最小都放不下 ⇒ **收成 0（整条不显示，回车入口仍在快捷键 / 命令面板）**；界面 = 自绘 `App/Views/TitleBarSearchField.swift`；**两条不变量** = 任何窗口宽度下都不侵入标题带 / 不做「既遮标题又不能用」那一档；判据 = 纯逻辑 **10 项**（含**对照**：写死 320 在窄窗口必判越界）+ 离屏探针 **5 例**）与 **`L-142`**（`7680c4c`：**新增 §3.31【契约】编辑面的底色与字色只用主题令牌** —— 由头 = 内测清单**甲2**「笔记的正文编辑区背景色明显不符合其他 2 个的配色方案」，根因**不是值写错，而是什么都没写**：`TextEditor` 不给底色时自己画系统的 `textBackgroundColor`（深色实测 `(30, 30, 30)`），另两个编辑面走主题令牌（科技蓝深色 `#0B1A2A`）⇒ 同一窗口两种底，切主题 / 切深浅都不成套。四条规则（三端一致）：① 底色 = **该主题该深浅档**的内容面令牌（不许落系统色、不许裸色）；② 字色 = 主题正文色、与底色同源；③ **每端只有一处**定义编辑面外观（本侧 `App/Views/EditorSurface.swift` 的 `.editorSurface()`，**7 处**编辑面只许挂）；④ **每处编辑面都要在台账里有落着**（新加未登记即判红）；判据 = `Scripts/check-editor-surface-tokens.py` **13 例** + 深色像素探针（含对照件））。本侧据此登记**两条等价义务（⑤ ⑥）**（**暂不动代码** —— Studio 不在当前队列，Notes 安卓未完工）：
⑤ **编辑面的外观归主题令牌、不归系统**（§3.31 原文点名「**Windows 的 WebView 内编辑区**」）：本侧表示层每一处多行文本编辑面（含 WebView2 里那一块）—— ① 底色 = **该主题该深浅档**的内容面令牌，**不许**落 WebView2 / 系统默认底、不许就地写色值；② 字色与底色**同源同档**；③ 每端**只有一处**定义编辑面外观（TS 侧一个具名样式入口或 Rust 侧单点），编辑面只许**挂**、不许就地拼一份；④ 每处编辑面都要在**本侧自己的**台账里登记（画 / 不画 + 为什么；新加未登记即判红）。本侧判据待表示层编辑面落地后按同名规则重建。
⑥ **标题栏搜索栏的宽度 = 契约层纯函数给，不由系统件给**：本侧对应物 = 自绘搜索栏 + 宽度纯函数（居中 ⇒ **两侧对称让位** / 理想与最小两档 / 连最小都放不下收成 0），**两条不变量照抄**（任何窗口宽度下不侵入标题带；不做「既遮标题又不能用」那一档），回车入口保留在快捷键与命令面板。
**本机（Windows）实测**：对侧新判据 `Scripts/check-editor-surface-tokens.py` **可跑且绿**（7 处编辑面全挂唯一写法 / 唯一出处无裸值 / 台账双向对账）；`platform/windows/Tools/verify-all.ps1` **14 项跑 14 / 跳过 0 / 失败 0**。**顺手修掉一处恒假红**：本机循环镜像台账原先写在 `Docs/循环台账.md`（`/Docs/*` 已 gitignore，但对侧 `check-doc-tables.py` 判据 E「有表格却不在受检清单里」照样命中 ⇒ 本侧闸门第 ③ 项**每轮恒红**，此前只登记未处置）⇒ 移出文档面到 `platform/windows/循环台账.md`（本侧自有目录）并在 `.gitignore` 的「Windows 侧」段补一行忽略（打点脚本 `doyah-loop-mark.sh` 的 studio 镜像路径同步改），第 ③ 项随之转绿。

**对侧两笔合流后的本侧适用性 + 一处真断点的修复（Windows 侧第 35 轮，2026-10-01）**：对侧本轮推两笔 —— **`T-20261001-031` ①**（`95fa5ab` 17:25：**第 4 个主题「星空紫」落地** —— `DesignTheme.stardust` / `AccentTheme.stardust` / 文案键 `designThemeStardust` / 样张链路）与 **`d7919c1` 17:57**（把星空紫纳入判据面；**同一笔把 `isDerivedDraft` 从「不是默认主题就算推导」改成逐主题点名** `self == .beanGreen || self == .roseGold`，理由写在源码注释里：星空紫的值来自需求提出者给的观感，是**实际值**，按旧写法界面会把它标成「推导草案」= 在界面上说假话）。**断点与证据**：本侧生成器 `App/tools/gen-tokens.mjs` 的解析式只认旧写法（`self != .<baseline>`）⇒ 从 17:57 起**本侧闸门两项恒红**（第 ④ 项 `test.ps1` 里外壳 4 例失败、第 ⑦ 项 `check-design-tokens.ps1` 的 `gen-tokens --check` 判红），而**两侧都没有任何东西会红**（对侧门禁不跑本侧生成器、本侧那一轮只做了 ff-only 拉齐没跑闸门）—— 实测口径见本节末。**本轮修法（全部落在本侧 `platform/windows/` 目录）**：① `App/tools/gen-tokens.mjs` 的 `isDerivedDraft` 解析改成**两形都认**（补集 `self != .x` / 逐主题点名 `self == .a || self == .b`），**认不出即判红**（不猜、不退回旧口径），点名了不存在的主题（笔误）也判红；② **重生成两件生成物** ⇒ 主题集 **3 → 4**（`stardust` / `derivedDraft: false`）、CSS 多一个 `[data-theme-scheme='stardust']` 三态块；③ `App/src/theme/index.ts` 补中文显示名 **星空紫**（与对侧语言表 `.designThemeStardust: 星空紫 / Star Purple` 同口径），并把「三个主题」这类易漂计数从注释里去掉；④ 自测 **35 → 39 例**：新增「点名写法」「补集写法仍认」「没登记过的写法判红」「点名笔误判红」四例，并把「每个主题一个变量块」从写死三个 id 改成**从生成物读 id**（对侧再增主题时自动跟着要求它有三态块，且 CSS 里多出来的 `data-theme-scheme` 取值判红）。**证据**：`App` 前端 `vitest` **39/39**；`platform/windows/Tools/verify-all.ps1` **14 项跑 14 / 跳过 0 / 失败 0 / `RESULT: PASS (exit 0)`**（修前同一命令为「跑 12 / 失败 2」）。

⑦ **等价义务（对侧已落、本侧未做 —— 如实登记，别当成已完成）**：**星空紫「星云皮肤」**（对侧队列 `L-153` / `L-155`，`Docs/design/外观方案-v1.md` §9.7）：键 `ui.nebulaSkin` / 缺省**开** / **只在星空紫下生效且可关** / 规则唯一出处 `Core/NebulaSkinPreference.swift` / 判据三层（门禁判据 I 29 处落点 + 像素探针 2 例 + 规则单测 10 例）。**本侧现状 = 只到「4 个主题的令牌块 + 同名下拉 + 推导草案标记」，没有皮肤这一层**。落点与做法（将来做时照抄形状）：① 皮肤是**叠加层**、不是第二套令牌（关掉 ⇒ 逐像素回纯色表面）；② 生效条件必须同时含「主题 = 星空紫」与「开关 = 开」**两个条件**且**只许一处**（对侧那一轮实测：写成两处分叉会被判据放过 ⇒ 按「唯一出处 + 只许调用」判）；③ 持久化读法用 `object(forKey:)`（`bool(forKey:)` 会把「从未设过」当 false ⇒ 新装用户看不到皮肤）；④ 皮肤**不属于「必须一致」的令牌值**（它是本侧新增主题的观感层）⇒ 做成**本侧自己的判据**，不冒充跨端等价。**暂不动代码**（Studio 不在当前队列，Notes 安卓未完工）。**读法提醒**：对侧 §9 写的是「**PC 两端**（macOS + Windows）在菜单里**一键换主题**」⇒ **4 主题是本侧义务**（本轮已跟上），皮肤则是「对侧已落、本侧待做」的那一档。


## 先跑闸门

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File platform/windows\Tools\verify-all.ps1
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
