
## R53（2026-10-29）

**R53（2026-10-29）已把 `FR-STD-WS-WEB-003`（网页文件在编辑器内的预览）做成一条纵切**：
① `Core/HTMLPreview` 计划层 —— 渲染哪一份（盘上文件 / **有未保存改动就渲染缓冲**）+ 读权限根 = **这份文件所在的目录**
（同目录 css / 图片要一起读；**目录是磁盘根 `/` 时不给计划** = 不为页面授整机读权限）+ 页面里的资源与链接三档
（根内 `file:` 放行 / 根外拒并带路径 / **远程地址交浏览器页签**）+ 路径按**分量**比不认字符串前缀；
② 引擎 `localReadRoot`（只预览页设，浏览器页签不设 ⇒ 行为不变）+ `loadHTMLString(_:baseDirectory:)`（渲染未保存缓冲，无出网）；
③ 界面 `App/Views/HTMLPreviewView.swift`（与 Markdown 预览同一套交互：分屏只读 · **共用同一枚预览开关** · 刷新 · 「在浏览器页签中打开」）
+ 树上网页文件右键多一枚「以源码打开」（`WorkspaceTabsModel.openAsSource`，当文本打开那段抽成一处）。判据 `Tests/HTMLPreviewTests` 15 例
（反例四段各判红后逐字节还原；开发期被自己判据抓出两处真错：目录 URL 的形状、`../` 多退一级）。实现 **🟡**（差人工点一眼）/ 判据 **✅**。
下一条活 = 台账 `FR-STD-WS-EDIT-022`（缩进检测与状态栏切换；优先=低，但判据全是纯逻辑、跑得快）。
备选：`FR-STD-WS-EDIT-017`（代码折叠）· `FR-STD-WS-EDIT-014`（撤销语义粒度）。
⚠️ `FR-STD-WS-TOOL-003`（DAP 调试器）与 `FR-STD-WS-AI-001`（编辑区 AI 辅助）纵切过大，排后。
**有一条待主人拍板**（已登记，别当已决）：命名分组标题上要不要也给「＋」（现在只有「未分组」那段有）。
**另一条待人工点验**（本批新增，别重复问）：网页预览那一眼 —— 编辑器里切预览看到渲染页 / 同目录样式生效 / 切回源码改动还在 / 点 `../` 链接被拒并说明。

## R59–R65（2026-10-29 搬出）

**R65（2026-10-29）已把 `FR-STD-WS-EDIT-014`（撤销语义粒度）接通**：三条验收此前**一条机制都没有** —— 撤销全靠 `NSTextView` 默认行为，编辑菜单那一行永远是通用「撤销」，`applyEditPlan` 无条件把选区改成计划落点。判定住 Core `Core/UndoGranularity.swift`（`UndoEditKind` 14 类 + `isAtomic`：只有连续键入 / 连续删除许合并，其余一次动作一步；`decide` 出「前断 / 后断」；`EditSelectionPolicy.after` 等长替换原样保留选区与光标、变长用计划落点并按文档长度夹住）+ 14 条动作名键中英齐；收口住 `App/Views/UndoScope.swift`（`performUndoable`：动手前 `breakUndoCoalescing`、落地后 `setActionName`、原子动作后再断一次；**不开 begin/endUndoGrouping** —— 探针实测空分组会留一层废步：`groupingLevel` 停在 1、`canUndo` 变真、按一次 ⌘Z 什么都不发生）；两个编辑面**所有**文本落地口都从它过（工作区 3 / SQL 4，唯一例外是整段外部载入那处不进撤销栈、并在载入时 `restartUndoChain`）。实现 **🟡**（差人工点一次：连打一行字按一次 ⌘Z 应整段回原 / 移行·注释切换·补全各一步 / 编辑菜单那一行写得出动作名 / ⌘L 光标不跳）/判据 **✅**（17 + 8 例；反例四段各判红后逐字节还原）；包 `420a920a（07:13:12）`，同标签 07:12:23 那份 `1d97776a`（含片补本条之前）作废。**R64 留下的探针边界本轮已量清**：无事件流下三次不分组替换与三次分组替换的撤销层数**都是 1** ⇒ ①「连续输入合成一步」探针判不了、只能人工按 ⌘Z；可机械判的是「在哪断开」（纯函数）与「这一步叫什么」（真视图上的 `undoActionName`）。明细见 `.agent/evidence/2026-10-29-EDIT-014.md`。
**R62（2026-10-29）已把 `FR-STD-WS-FS-010`（多工作区切换）接通**：此前工作区**同时只有一个**（`choose()` 先 `store.removeAll()` 再存一条，
换文件夹 = 把上一个从授权表删掉；首页「最近打开的工作区」只展示、点不动）。`Core/WorkspaceRegistry.swift` 一张表收四条口径：
**同一目录只登记一条**（去重按解析出的路径，活动那条优先留下 —— 否则重选一次当前目录会把活动状态随去重丢掉）· **同一时刻只有一个活动**
（`activeID` 一格，`Entry` 不许自带 `isActive`）· **不可用 ≠ 不可见**（目录没了 / 没权限的仍留在表里并写明理由，但 `decision(for:)` 拒绝切过去；
`alreadyActive` 是**什么都不做**，重取一次授权 = 树整棵塌一次）· **容量 8、永不淘汰活动那条**。接线：`WorkspaceStore` 持表 + `switchTo`
（**先确认真能取用再动活动**，失败就留在原工作区只说理由）+ 活动 id 落盘（老版本无记录 ⇒ 第一条当活动）；`choose()` 改成按表算出的 id 落盘。
界面两处**同一份列表、同一个动作**：文件树标头 `WorkspaceSwitchMenu` + 首页 `WorkspaceKnownRow`（原来那三行读的是 `tabs.history.workspaces` ——
流水不是授权表，已换掉）。实现 **🟡**（差人工点一次）/ 判据 **✅**（16 + 5 例；反例五段各判红后逐字节还原）；包 `594b301e（06:22:20）`，
同标签 06:21:52 那份 `1fc685cd`（含片补本条之前）与 06:04:40 那份 `dafed86a` 作废。明细见 `.agent/evidence/2026-10-29-FS-010.md`。
**R63（2026-10-29）陈旧标记归正 8 条**（只翻判据列 🟡 → ✅，**零新增用例、Core 总数 4825 不变、零源码改动 ⇒ 未重建，包沿用 `594b301e`**）：
`FR-STD-WS-NAV-004`（`InlineGhostCompletion` 18 + `InlineGhostSQL` 12 + `InlineGhostPath` 16 = 46 例）· `FS-009`（`WorkspaceChangeScope` 9）· `EDIT-013`（`WorkspaceHeaderSearch` 12）· `UI-003`（`WorkspaceClosePolicy` 10）· `EDIT-006`/`EDIT-007`（同一份 `MarkdownEditing` 18）· `EDIT-019`（`CodeAutoPairing` 21）· `EDIT-008`（`CodeCommentToggle` 12），九个 `--filter` 全 `Executed N … 0 failures`。三处旧数字按实测改登记（30 条 ⇒ 12 例 / 8 例 ⇒ 10 例 / 17 例 ⇒ 18 例）；`FS-009` 实现列 ✅ → 🟡 **如实下调**（备注自己写着「剩：界面点验」）。分族 ⇒ 实现 126/81/6 · 判据 158/48/6/—1（= 213）。明细 `.agent/evidence/2026-10-29-stale-marks-R63.md`。
**R64（2026-10-29）已把 `FR-STD-WS-NAV-006`（悬停文档 + 跳转到定义，词法级）接通**：`Core/SymbolOutline.swift` 建同文件符号表 ——
声明扫描按语言的声明关键字表（`SymbolRules.table`，加语言只动一行）· **作用域由内向外**（`{ }` 建作用域森林，兄弟函数里的同名**不许借**，
走到底没有就明说查不到 —— 需求末栏「不是全文搜一遍同名」）· 字符串 / 注释里的同名不算符号（掩码取 `CodeLexer.protectedSpans`，与折叠 / 片段同一份）·
SQL 的 `FROM orders o` 记别名 `target`、`o.total` 说得出是哪张表的列。接线 `App/Views/SymbolHover.swift` **一份给两个编辑面**：
悬停 = 系统 tooltip 动态文案（弹出那一刻按位置解析）、⌘ 点击 = 跳定义（**查不到不吞点击**），`CodeTextView` 按页签语言 / `SQLTextView` 固定 SQL。
实现 **🟡**（差人工点一次：停在函数调用处应浮出「名字 · 函数 · 行 N · ⌘ 点击跳到定义」/ ⌘ 点它光标落到函数名 / 字符串里的同名不弹 /
本文件没声明就明说查不到）/ 判据 **✅**（21 + 4 例；反例两段各判红后逐字节还原）；包 `6547b7b9（06:54:32）`，
同标签 06:54:16 那份 `26e918e8` 作废。**菜单项 / 快捷键入口没做**（需求 ② 的「点或快捷键」已满足其一 —— ⌘ 点击）：
加菜单项要动 `App/ShortcutCatalog`（快捷键单一事实来源）+ 菜单语言表，属另一片，本轮不顺手扩范围。
⚠️ 同批补登 `check-language-registry` 的 A 档声明面（含第六十一批漏登记的 `Core/SnippetTemplate.swift`）⇒ 该判据由红转绿（补登记不是放宽）。
明细见 `.agent/evidence/2026-10-29-NAV-006.md`。
⚠️ **R64 实测留一条给下一轮**：撤销粒度（`FR-STD-WS-EDIT-014`）用「手工造撤销分组」的探针**量不出真实按键粒度** ——
无事件流的探针里 `breakUndoCoalescing()` 不起作用（整段打字的撤销全并成一层），探针读数会诱人写出一个错的修法。
**R61（2026-10-29）已把 `FR-STD-WS-NAV-005`（片段模板 / snippets）接通**：骨架是数据、判定是纯函数 ——
`Core/SnippetTemplate.swift` 三件纯事：**解析**（`$1` / `${1:默认}` / `$0`；`$$`·`\$` 转义；认不出的 `${…` 原样落字符）·
**触发**（整词、大小写不敏感、后面还接词字符就拒、**触发词范围**落在字符串 / 注释里就拒 —— 判词不判光标：`'select'` 与 `-- select` 那两种现场光标都可能刚好在掩码外一格）·
**会话**（落点用文档绝对坐标，`noteEdit` 随编辑平移；跨落点的改动如实作废、Tab 回缩进）。片段表住 `CodeLanguageDefinitions.snippets`
（SQL `select`/`join`/`insert`/`ctable` · Markdown `table`/`task` · python/swift/js/ts/shell 若干）。接线两个编辑器：
`insertTab` 次序写死 **会话 → 灰字 → 片段 → 缩进**（`CodeTextView` 与 `SQLTextView` 各一遍），`shouldChangeText` 回报编辑。
同批掩码收成一份 `CodeLexer.protectedSpans`（折叠改为转发）。实现 **🟡**（差人工点一次）/ 判据 **✅**（23 + 5 例；反例六段各判红后逐字节还原）；
包 `dafed86a（06:04:40）`，同标签 05:45:45 那份 `50553049` 作废。⚠️ 同批**改写**了 `Tests/IndentProfileTests` 里「Tab 三个动作」那条锚点（现在是四分支、次序写死，理由写在该用例注释里）—— 不是放宽。
明细见 `.agent/evidence/2026-10-29-NAV-005.md`。
**R60（2026-10-29）已把 `FR-STD-DB-META-006` ③（**加载失败在该节点可读错误** **并可重试**）补上**：
此前失败那一行只有一句红字（`ErrorPresenter` 的人话），界面上**没有任何入口** —— 用户唯一出路是自己折起来再展开，
而这件事界面上一个字都没提。`Core/ObjectTreeRetry` 一处收口「出不出入口」与「点了做什么」：四档不出
（`inFlight` 在途 / `notExpanded` 收起 / `noFailure` 空态 / `alreadyLoaded` 已缓存）· 计划 `steps` 顺序即口径
（**先清旧错误再取数**）· `cachedCount: Int?` 分得清「加载过 0 条」与「从没加载过」。接线：失败分支传入口
（**文字**「重试」按钮，带 help / 无障碍标签）+ `retryAction` 只读判定 + `performRetry` 走与手点同一条 `loadChildren`。
实现 **🟡**（差人工点一次）/ 判据 **✅**（11 + 5 例；反例六段各判红后逐字节还原）；包 `50553049（05:45:45）`，
同标签 05:45:26 那份 `164a7fe0` 作废。明细见 `.agent/evidence/2026-10-29-META-006.md`。
**R59（2026-10-29）已把 `FR-STD-WS-EDIT-015`（整批撤回）接通**：账仍是唯一前像来源（`agentEditJournal.before`）—— `snapshots(from:)` → `plan`（同一路径合并时**前像取最早、摘要取最新**；原来取最后一次写，一批里改两次就只撤掉一半，与「一次撤回把所有改动还原」相反）→ `inverse(of:reader:)` 出反向批次（冲突步不生成）⇒ 撤回本身可再撤回 → `AgentBatchRevertReceipt` 留痕（计数取自 `apply` 的读数）。接线：`AppState.revertAgentBatch` / `redoAgentBatchRevert`（路径过沙箱、越界抛错不写盘、撤完同步正开着的页签）+ 对话页输入框上方一行「这一轮 Agent 改了 N 个文件 · 整批撤回 / 已撤回 N 个（M 处没动）· 撤销这次撤回」+ 语言表 6 键中英齐。实现 **🟡**（差人工点一次：① 让 Agent 改两个文件点「整批撤回」，两个都应回到改前；② 撤前手工再改其中一个 ⇒ 那个读「没动」且内容一个字不动；③ 点「撤销这次撤回」应回到 Agent 写完那一版）/ 判据 **✅**（`Tests/AgentBatchRevertTests` 9 例 + `Tests/AgentBatchRevertSourceTests` 5 例，反例四段各判红后逐字节还原）；包 `a120a874（05:28:14）`，同标签 05:25:26 那份 `20adc61a` 作废。明细见 `.agent/evidence/2026-10-29-EDIT-015.md`。
⚠️ 同批把第五十七批留下的 8 条 `check-format-arguments` 真红修干净：四处回执文案从「模板串交给 Core 去格式化」改成**值格式闭包**（`{ L(.receiptSeconds, $0) }`）—— 模板与实参回到同一句，判 B 不再是假红、A/A′ 开始真的检查这四句；形状台账按实测对齐（+5 形状 / 3 处处数跟版 / 预算 170 → 188，理由写进 note）。
