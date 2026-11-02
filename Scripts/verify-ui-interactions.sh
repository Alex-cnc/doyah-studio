#!/bin/bash
set -euo pipefail

# 「界面点验自动化」的入口（队列 `L-90` —— 「App 内探针 + 自渲染快照」路线，**零权限**）。
#
#   ./Scripts/verify-ui-interactions.sh                     # 跑全部交互探针
#   ./Scripts/verify-ui-interactions.sh --filter 用例片段    # 只跑一部分
#
# ## 与 `run-manual-verification-probes.sh` 的分工
#
# 那份把「待人工验收清单」的 B 类（13 条：快照 / 探针可代劳）机器化，跑**两遍**（其中一条判据要靠
# 「沙箱标记」那一面）。这一份是清单 §0.2 的 D 类（5 条：真实鼠标 / 键盘事件）改走「自己点自己」
# 之后的入口 —— 判据与进程环境无关，所以**只跑一遍**，但末尾两件事一件不少：
#
#   · **核对跑了几条、有没有跳过**（跳过 ≠ 通过：`XCTSkip` 会让「三条全过」变成零证据）；
#   · **源锚点**（判据盯的必须是产品那条线：路由判定在 Core、视图真的问过它、字节真的从
#     `TerminalInput` 那两个出口出去 —— 判据与产品脱钩的话，绿也是白绿）。
#
# ## 本批（㈠）：终端交互三面
#
# `TestsUISnapshot/TerminalInteractionProbeTests.swift` 判清单 §1 那三行的**行为面**：
#   ① `FR-STD-WS-TOOL-001` 鼠标上报 —— 按下 / 拖动 / 滚轮在**程序接管鼠标**时真的转发（SGR 报文出现在
#      「前台程序的字节出口」上），按住 ⌥ 拖动必须归本机（出现选区、报文不再增加）；
#   ② `FR-STD-WS-TOOL-001` 方向键（DECCKM）—— `?1h` 置位时 ↑ 走 SS3、复位后走 CSI；
#   ③ `FR-STD-WS-TOOL-001` 右键菜单 —— 程序接管鼠标时菜单仍归本机（五项齐备且指向产品自己的动作），
#      只有「接管 + ⌥」才转发给程序。
# 判字节出口是**真 PTY**（终端里跑 `cat -v`，把收到的字节按可见形式打回屏幕）。两条边界
# （右键「不按 ⌥」那一面**不派发事件**）写在那个文件的头注释里。
#
# ## 第二批（L-90 ㈡ 第 1 条，第 109 轮）：多光标与列编辑
#
# `TestsUISnapshot/MultiCursorProbeTests.swift` 判清单 §3 `FR-STD-WS-EDIT-016` 那一行的**行为面**
# （「⌥ 拖拽列选；⌥⌘D 选下一处；⌥⌘↑ / ↓ 加光标；多光标下打字与 ⌫」＋验收面「一次撤销能全回退、
# 光标位置不漂」）：真 `SQLEditorView` 进活宿主、从视图树里取出真 `SQLTextView`，
# 合成的 `NSEvent`（⌥⌘D / ⌥⌘↑↓ / ⌥ 拖拽）直接交给它的方法；「界面上有几个光标」
# 读 `SQLTextView.multiSelection`。三条用例各出一张图。
#
# **本轮在这条路上抓出一个真缺陷并修掉**：`NSTextView` **只收得下第一个零长度选区**
# （实测 macOS 27：设 `[{4,0},{30,0}]` 读回来 `[{4,0}]`；非零长度的多选区则原样收下）
# ⇒ `⌥⌘↑` / `⌥⌘↓` **加光标在真机上一直是静默失效的**（`selectedRanges` 恒为一条 ⇒
# 打字 / 退格的多光标分支、`drawInsertionPoint` 画次光标那段都是死代码），
# 而判 Core 的 `MultiCursorTests` 21 项照样全绿。修法：零长度那些由视图自己记
# （`rememberedCarets`），选区集合取「AppKit 收下的 + 自己记的」两份并集。
# 下面那两条源锚点盯的就是这个修法别再退回去。
#
# ## 第三批（L-90 ㈡ 第 2 条，第 110 轮）：对象树逐行右键
#
# `TestsUISnapshot/ObjectTreeContextMenuProbeTests.swift` 判清单 §4 `FR-STD-DB-META-012` 那一行
# （「依次右键表 / 视图 / 列 / 服务器 / 数据库 / schema / 函数」）：菜单**内容**与**作用在哪一行**
# 两件事这一轮都搬进了 `App/Views/ObjectTreeContextMenu.swift`（一个静态 `@ViewBuilder` 入口 + 一个纯函数），
# 于是不需要鼠标事件、也不需要任何权限 —— 每类节点渲染一遍、拿「这一遍取到的文案集合」与
# `ObjectTreeActions.isAvailable` 的规则**双向**对账；作用行用产品自己摊平的
# `ObjectTreeRows.visibleRows` 喂 `ObjectTreeMenuTarget.resolve`。
# 老缺陷的回归钉 = 「非服务器那一行**不许**出现服务器菜单项」（点数据库弹服务器菜单那次）。
#
# ## 第五批（v0.3.0 数据库运维面·第一跳）：`FR-STD-DB-RES-006` 复制为多格式
#
# `TestsUISnapshot/ResultCopyProbeTests.swift` 判这一行的**交付面**（台账备注原文是
# 「界面粘贴待人工点验」）：挂真 `ResultGrid` 进离屏真窗口 → 取出真 `NSTableView` →
# 用**产品自己那份右键菜单**（`tableView.menu`）里的菜单项 → 按菜单项自己的
# `action` / `target` 派发 → 读 `NSPasteboard.general` 里真实的字符串。七条：
#   ① 四档格式都在「复制为…」子菜单里、每档都能真的写进系统剪贴板且带表头 / 只含选中的行；
#   ② 默认 ⌘C = TSV，逐字节与需求口径一致（值里的制表符 / 换行被换成空格，不撑破行）；
#   ③ 转义：Markdown 的 `|` 与换行（`<br>`）、CSV 含换行字段加引号；
#   ④ INSERT 指向**正在浏览的那张表**（`public.orders`），没有来源表时落占位表名；
#   ⑤ 负例：没有选中行时剪贴板一个字节都不动；
#   ⑥ 只进剪贴板、不落文件（剪贴板类型里没有 `public.file-url`）。
# **证不住**：把这段文本粘进 Excel / 飞书之后长什么样（外部软件行为，与 `DB-RES-014` 同边界）。
# 反例三段（默认格式改成 markdown / INSERT 不带来源表 / 菜单少放一档格式）各判红后逐字节还原。
#
# ## 第六批（v0.3.0 数据库运维面·第二跳）：`FR-STD-DB-RES-007` 客户端排序
#
# `TestsUISnapshot/ResultSortProbeTests.swift` 判这一行的**交付面**（台账备注原文是
# 「界面点击待人工点验」）：挂真 `ResultTableView`（生产里自己持有 `ResultGridState` 的那个视图）
# 进离屏真窗口 → 取出真 `NSTableView` → 取**真表头**（`tableView.headerView`）→ 用那一列的
# 中间点造 `NSEvent`，把 `mouseUp` 投进 `NSApplication` 的事件队列，再把 `mouseDown` **直接交给
# 表头自己的 `mouseDown(with:)`** —— 用户点一下走的就是这条 AppKit 路径（跟踪循环、指示器、
# `sortDescriptorsDidChange` 都在里面）。判据读**表格里真的显示成什么**（逐行取
# `NSTableCellView.textField.stringValue`）+ 表头指示器（`tableView.sortDescriptors`）。六条：
#   ① 每列都带排序原型（没有它 AppKit 不画指示器、也不派发变化，点上去等于点死木头），
#      且点这一列的中点命中的就是这一列（点 A 排 B 的那种错行）；
#   ② 升 → 降 → 取消三档，取消后回到服务端顺序、指示器清空，且点表头不改列宽；
#   ③ 数值按数值比（`9` 排在 `10` 前）、**NULL 在两种方向下都留在末尾**（早期实现按方向取反、
#      降序时 NULL 跑到最前的那次事故的回归钉）；
#   ④ Shift 点第二列 = 追加次要键，主键不丢；
#   ⑤ Shift 再点同一个次要键先翻方向、第三下只删这一键（主键留着）；
#   ⑥ 负例：点表头**空白处**什么都不发生（不许凭空清掉排序）。
# **证不住**：真鼠标在真屏幕上的手感（双击节奏、拖几像素才算拖列）—— 输入设备行为，不在本行验收要点里。
# 反例三段（派发退回 `sortDescriptors.first` / 让 NULL 跟着方向翻 / 显示变更退回「首末行摘要」）
# 各判红后逐字节还原。
#
# **本批在这条路上抓出两个真缺陷并修掉**（不是只补判据）：
#   · Shift 加次要键时派发读 `tableView.sortDescriptors.first`，而 AppKit 把新列**追加**在后面
#     ⇒ 第一个仍是被点的老主键，多列排序永远加不上新列（`SortableHeaderView` 改为自己记
#     「点的是哪一列、有没有按 Shift」，一次点击只派发一档）；
#   · 表格「显示内容变了没有」原先用「行数 + 首行 + 末行」摘要判 —— 取消排序回到服务端顺序时
#     末行往往与降序那份的末行相同 ⇒ 摘要不变 ⇒ 不重载 ⇒ 界面上还留着旧的排序结果
#     （现改为逐行比对 `lastDisplayedRows`）。
#
# ## 第七批（v0.3.0 数据库运维面·第三跳）：`FR-STD-DB-RES-008` 客户端筛选
#
# `TestsUISnapshot/ResultFilterProbeTests.swift` 判这一行的**交付面**（台账备注原文是
# 「界面点击待人工点验」）：挂真 `ResultTableView` 进离屏真窗口 → 取真 `NSTableView` 与条上的
# 真控件 → 按钮用 `performClick(nil)`、换列 / 换运算符用 `NSPopUpButton.selectItem + sendAction`
# （与手选同一条 action 路径）、打字走**字段编辑器**（`makeFirstResponder` →
# `currentEditor().insertText`，与手打同一条路）。判据读**表格里真的显示成哪几行**。六条：
#   ① 死路回归钉：**没做过任何客户端操作**时条也在场、「+」点得动，而且加出来的（还没填值的）
#      条件**不参与筛选**（一行不少）；
#   ② 换列：条件看的是哪一列，表格跟着变（换到 id 列 ⇒ 0 行，换回 note ⇒ 3 行）；
#   ③ 换运算符：包含 / 不包含 / 为空 三档都改到显示的行，「为空」同时命中 NULL 与空串，
#      并把值输入框收掉（它不需要值）；
#   ④ 打字：逐字打进输入框，表格**当场**跟着筛，且编辑会话一直在（`currentEditor()` 不丢 ——
#      `TitleBarSearchField` 那次「字只进得去一个」的同一类风险）；
#   ⑤ 大小写开关：同一份数据按一下命中的行就变（`beta/BETA/gamma` ⇒ 只剩 `BETA`）；
#   ⑥ 多条件 AND + 删单条条件 + 删光之后条还在、还能再加（入口不许跟着条件一起消失）。
# **证不住**：真鼠标点开菜单的弹出动画与拖选文本（输入设备行为）；条右侧「清空全部条件 /
# 生成 WHERE」两颗仍是 SwiftUI `.plain` 按钮（`ToolbarIconButton` 不落成 `NSButton`，量不到点击）。
# 反例四段（条退回 `isClientViewActive` 才渲染 / 待填条件照旧参与筛选 / 列弹出按钮退回 SwiftUI
# `Menu` / WHERE 不丢待填条件）各判红后逐字节还原。
#
# **本批在这条路上抓出两个真缺陷并修掉**（不是只补判据）：
#   · 筛选条只在 `isClientViewActive` 时渲染，而唯一的「+ 加条件」入口就在条里 ⇒ 没排过序的用户
#     永远加不了第一个筛选条件（与 2026-09-23 分页条死路同一个形状）；
#   · 点「+」当场把整张表清空：新条件默认 `contains ""`，而 Foundation 里 `"abc".contains("") == false`
#     ⇒ 一条还没填值的条件筛掉了所有行。现按 `ResultFilter.isPending` 跳过，也进不了生成的 WHERE。
#
# ## 第八批（B1 批次第一片）：`FR-STD-DB-TASK-003` 执行回执页
#
# `TestsUISnapshot/ExecutionReceiptPaneProbeTests.swift` 判这一行的**交付面**（台账备注原文是
# 「差人工点一次」）：挂真 `ExecutionReceiptPane` 进离屏真窗口 → 从视图树里取出真 `NSButton`
# （本片把三枚动作从 SwiftUI `Button` 换成 `PanelIconButton`：SwiftUI 按钮在离屏宿主里不落
# `NSButton`、无障碍树也不构建 —— 本机实测合成鼠标事件投进去 action 不动、AX 子节点 0 个）
# → `performClick(nil)` → 读真 `NSPasteboard`、读 `tab.receiptLog`、读状态栏那句话。七条：
#   ① 三枚动作都在、各带各的提示、提示互不相同（按提示认按钮，不写死次序）；
#   ② 复制：剪贴板 = 整本回执（旧 → 新）逐字节等于 Core 渲染，四项读数与执行时刻都在；
#   ③ 复制不含口令原文、但留下 `***`（复制绕过 render 的那次事故的回归钉）；
#   ④ 空态：点复制 / 清空都不动剪贴板，只给一句理由；
#   ⑤ 清空：册子真空了、面板回空态（前后两张图内容占比必须不同）；
#   ⑥ 导出：`writeReceipts(_:to:)`（面板之后那一半，按钮点的也是它）写出的字节与
#      `exportData()` 逐字节相同、能解回两条、原文口令不在里面、错误原文还在；
#   ⑦ 三条回执的画面比一条多（证明每条都画了，不是只画一条）。
# **证不住**：导出按钮后面那个模态保存面板（无人值守的机器上不该弹窗，由人承担）；
# 回执正文逐字（SwiftUI `Text` 不落 `NSTextField`，那一面归 `Tests/ExecutionReceiptTests`）；
# 真鼠标拖选正文（输入设备行为）。
#
# **本批在这条路上改了一件结构**：三枚动作由 SwiftUI `Button` 换成真 `NSButton`
# （`App/Views/PanelIconButton.swift`）—— 换的理由只有「量得到」，与 `ResultFilterPopup`
# 换 `NSPopUpButton`、`TitleBarSearchBox` 整框换 AppKit 同源。
# 反例五段（复制接错页签 / 空态不给理由 / 清空不清册子 / 导出另拼一份漏脱敏 / 按钮不带提示）
# 各判红后逐字节还原，shasum 一致。

# **源锚点归位（开发循环第 113 轮，队列 `L-103`）**：2026-09-29 23:25–23:36 那个会话把行渲染搬进
# `ObjectTreeRowContent.swift`、把右键改由**行的 AppKit 捕获器**自己给出（`ObjectTreeRightClick.swift`
# → `ObjectTreeAppKitMenu.build(object: row.object…)`），附录里原先钉的三条（`.contextMenu {` /
# `ObjectTreeMenuTarget.resolve(` / `ObjectTreeContextMenu.items(` 在 `ObjectTreeView.swift` 里）
# 跟着失效 ⇒ 本入口**九条探针全绿却在源锚点那一步 exit 1**。归位后盯的是**同一件事的新形状**：
# 每一行有自己的捕获器、菜单由这一行现建、目标就是 `row.object`（「不许退回整树一份 + 悬停解析」
# 那半由两份 Swift 判据的 `XCTAssertFalse` 钉住，不在这里重复）。

# ## 第十批（B1 批次第三片）：`FR-STD-DB-IO-002` 整表 / 整库导出真跑一次落文件
#
# `TestsUISnapshot/TableExportStreamProbeTests.swift` 判这一行的**交付面**（台账备注原文是
# 「差人工点一次」）。本机没有 PG、也不该去碰 217 真库 ⇒ 用**假 `DatabaseService`**：
# `streamTable` 只依赖 `execute` 这一条缝，假服务按 `BEGIN` / `DECLARE` / `FETCH n` / `CLOSE` /
# `COMMIT` 逐条应答并记下收到的每条语句。于是量到的是**生产那条路** —— 真 `CursorFetcher` 分页、
# 真 `ResultStreamWriter` 逐页写盘、真 `TableExport.selectSQL` 拼语句：
#   ① 2500 行 ⇒ 盘上 2501 行（表头 + 全部行）、FETCH 三趟（1000 · 1000 · 500）、CLOSE 与 COMMIT 各一次；
#   ② 空表 ⇒ 抛可读错误、**不落文件**（本条在这一片上抓出一个真缺陷：`nextPage()` 对空页返回的是
#      「那一页」而不是 nil，早先只判 nil ⇒ 空表会落一个只有表头的文件、面板还报「成功 0 行」）；
#   ③ 取到一半失败 ⇒ 报错、不留半成品、事务回滚（末条 ROLLBACK）；
#   ④ 整库逐张落文件：成的那张一个文件、空表与断掉的那张记进「没成」、一张没成不打断后面；
#   ⑤ 源锚点：`streamTable` 恰好两个调用点（整表 / 整库），不许有人另开一条逐行取数的循环。
# 边界：保存面板 / 选目录面板没点（模态，无人值守不该弹）；不是真数据库（真库那一面见 R-036 的
# 12 万行 / 27 MB 记录）；内存峰值不做断言。

# ## 第十一批 / 第十二批（B1 批次第四片）：审批单两枚动作 · 对象树失败行的「重试」
#
# `TestsUISnapshot/AgentApprovalDecisionProbeTests.swift` 判 `FR-STD-DB-TASK-002` 的**交付面**
# （台账备注原文是「差人工在审批单上点一次」）：两枚动作换成真 `NSButton`，接线收进
# `AgentApprovalDecisionWiring.make`（审批单与探针读同一处），审计落点可由 `agentAuditLogOverride`
# 指到临时目录。探针 `performClick(nil)` 之后判 `AppState` 的**状态**：
#   ① 两枚都在、各带各的提示、批准是回车等价；在途时两枚全灰（不许点第二次决策）；
#   ② 点「拒绝」⇒ 待审批队列清空、`agentApprovalRequest` 清掉、历史最后一条 `rejected` 且带备注、
#      内存与盘上都没有 `executed` —— 「未确认不发送任何语句」是这一步的可见后果；
#   ③ 覆盖写入（`TRUNCATE` + `INSERT`）逐条带自己的目标库、序号 1 起、影响面问之前不冒充 0 行，
#      拒绝交出 0 条语句；
#   ④ 源锚点：审批单走这一份（旧的 `decide(approve:)` 与两枚 SwiftUI 按钮不许回来）。
#
# `TestsUISnapshot/ObjectTreeRetryProbeTests.swift` 判 `FR-STD-DB-META-006` ③ 的**交付面**：
# 失败那一行收进 `ObjectTreePlaceholderRow`、入口换成真 `NSButton`，两步执行收进
# `Core/ObjectTreeRetry.apply`（顺序即口径）。五条：① 那一行落出一枚真按钮、点两次跑两次；
# ② 四档「不出」逐档渲染 0 枚（在途 / 收起 / 没失败 / 已缓存）、该出那一档 1 枚且计划是两步；
# ③ 点一下之后顺序是「先清旧错误、再取数」，取数那一刻旧错误已清；④ 在途时同一行上入口消失；
# ⑤ 源锚点：树的失败分支走这一行、两步走 Core、SwiftUI 版按钮不许回来。
# 边界：不是真数据库（真库那一面归 `run-manual-verification-probes.sh`）；行内红字读不出来（SwiftUI `Text`）。

# ## 第九批（B1 批次第二片）：`FR-STD-DB-TASK-001` 工具栏「任务」菜单
#
# `TestsUISnapshot/SQLTaskMenuProbeTests.swift` 判这一行的**交付面**（台账备注原文是
# 「差人工点一次」）：菜单内容收进 `Core/SQLTaskMenuPlan`（纯值），铺设收进
# `SQLTaskAppKitMenu.build`（真 `NSMenu`），动作接线收进 `SQLTaskAppKitMenu.actions`
# —— 工具栏与探针读同一处。探针按文案认行、再让它走行自己的 `target/action`
# （`NSApp.sendAction`，用户点它时 AppKit 派发的就是这一条），判据读 `AppState` 里的状态：
#   ① 每行写清「名字 · 库 · 只读/可写 · 上限」，行序 = 册子序，删除子菜单一行一条；
#   ② 册子空时有一句人话（灰着）「保存」跟着页签里有没有语句走，点了只叫一次表单；
#   ③ 点「载入」⇒ 语句进页签、库与连接切到定义那一对、页签绑上；
#   ④ 点「解除绑定」⇒ 页签松开而任务还在册子里，菜单不再写绑定关系；
#   ⑤ 点删除子菜单那一项 ⇒ 册子里少一条、盘上也少一条（临时目录，不碰真账）；
#   ⑥ 源锚点：工具栏走的是这一份（不许再自己写一套 SwiftUI `Menu`）。
# **本批在这条路上改了一件结构**：菜单由 SwiftUI `Menu` 换成真 `NSButton` + 真 `NSMenu`
# （离屏宿主里 SwiftUI 菜单不落任何可点的 AppKit 控件，只能靠人点）。
# 边界：不真弹菜单（`popUp` 是模态的，无人值守不该弹）、保存表单的填写归 `SQLTaskDefinitionTests`。

# ## 第四批（`T-20261002-027`，开发循环第 162 轮）：标题栏搜索栏**点击地图**
#
# `TestsUISnapshot/TitleBarSearchClickProbeTests.swift` 判「**看得见的框 = 能点的框**」这条：
# 可见框内的采样点逐点断言命中目标 = 输入框或其接力层（任一点落空 ⇒ 判红）、留白点按下真的把
# 键盘交给同一框里的输入框、清空按钮那一段留给 SwiftUI、以及**同一套量法喂修前那份框必须判红**
# （红/绿成对）。**真因**（第 162 轮量到的）：SwiftUI 画的背景填充与 `strokeBorder` 默认参与命中
# 测试，压在那层接力之上 ⇒ 第 161 轮那层「装上却没接到点击」。宿主是**手工搭的真窗口 + 工具条**
# （与 SwiftUI 工具条项同形），进程内合成事件 ⇒ 零权限。

# ## B5 批次：会话面与诊断面（`FR-STD-DB-SESS-002` · `-003` · `-004` · `FR-STD-DB-DIAG-003` · `-004`）
#
# `TestsUISnapshot/SessionDiagnosticsProbeTests.swift`（13 例）判这五行的**交付面**
# （台账备注原文是「界面点击待人工点验」）。为什么以前只能人点：这五个面的服务都从
# `AppState.ensureService` 取，而它写在私有方法里、没有注入口 ⇒ 探针只能拍到「没连接的红字」。
# 本批开的**唯一**一处结构：`AppState.serviceOverride`（生产默认 nil = 真连接），
# 假服务记下收到的每一条语句并按 SQL 内容回不同结果集。于是：
#   ① 会话列表：一次刷新只发一条 `pg_stat_activity` 查询；排序「等待 → 活跃 → 空闲」
#      （`wait_event_type=Client` 不算阻塞）；没有 pid 的行丢弃、不变成「会话号 0」；
#   ② 取消语句发的是 `pg_cancel_backend`（不是 terminate —— 那会把整条连接掐掉），
#      成功时状态栏说清是哪条会话；
#   ③ 终止：自己的会话当场拒、**一条语句都不发**；服务端回 `false` 时如实说「被拒」，
#      不许写「已终止」；
#   ④ 服务器级对象：三类各一条查询、解析出角色 / 表空间 / 扩展；写操作**预览那一句就是
#      发出去的那一句**（逐字、只发一次）；只读连接上在**发之前**就被拒；
#   ⑤ 统计面板：四类各一条查询；一次都没扫过的表命中率是「无扫描数据」而不是 0%；
#   ⑥ 慢查询排行：排序口径真的换 ORDER BY；列名按服务器主版本选
#      （12 用 `total_time`、18 用 `total_exec_time`）；扩展没装时给可照做的安装步骤且
#      **不发**排行查询；非 PG 方言直说「不支持」且不发语句；点一行只把原文放进编辑器、不执行。
# 反例三段（每段判红后 `git checkout` 还原、`sha256` 逐字节比对）：取消接成终止（4 红）·
# 列名写死 13+（2 红）· 扩展没装也当空排行（1 红）。
# 边界：不是真数据库（217 真库那一段本跳连接超时 ⇒ 记「未知」）；面板版面与按钮灰显归快照层；
# 真鼠标点一行由人承担。
#
# ## 第十五批（B5 批次余项）：`FR-STD-DB-DIAG-006` 连接上下文里的诊断入口
#
# `TestsUISnapshot/ObjectDiagnosisProbeTests` 判这一行的三条判据（台账备注此前一直是「目标列 —」）：
#   ① 从对象树右键可唤起且**上下文自动带入** —— 两套渲染（AppKit 生产路径 / SwiftUI 那份）都在，
#      点下去 `objectDiagnosisScope` 里连接 / 库 / 对象 / 最近一次执行的读数齐备，提示词里也带上了；
#   ② 结论里的对象名**可点击跳到对应节点** —— 切段是 Core 的纯函数（长名优先 + 词边界），
#      链接解回身份后发出的跳转请求逐字段对上（类型 / 名字 / schema / 库）；
#   ③ 无统计读数时**明说「未取到」，不编** —— 列 / 视图 / 函数 / 非 PG 方言各自的理由，
#      且一条语句都不发（不给空表：空表会被读成「这张表从来没被扫过」）。
# 反例三段（各判红后 `shasum -a 256` 逐字节还原）：统计不按对象收窄（2 红）· 去掉词边界（1 红）·
# 被拒的那一跑当成执行读数（1 红）。
# 边界：不是真数据库（217 连不通 ⇒ 真统计读数记「未知」）；真鼠标点一下链接由人承担；
# 树的展开 / 选中是视图内部状态（判的是「请求里是什么」）。

ROOT="$(cd "$(dirname "${0}")/.." && pwd -P)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SWIFT="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SCRATCH="${ROOT}/.build"
CACHE="${ROOT}/.build-cache"
OUT="${SCRATCH}/ui-interactions"
FILTER="NotesUndoAndLongDocumentProbeTests|TerminalInteractionProbeTests|MultiCursorProbeTests|FormatMenuWiringProbeTests|EditAssistProbeTests|ObjectTreeContextMenuProbeTests|TitleBarSearchClickProbeTests|ResultCopyProbeTests|ResultSortProbeTests|ResultFilterProbeTests|ResultPagingProbeTests|ResultStreamExportProbeTests|ResultXLSXExportProbeTests|ExecutionReceiptPaneProbeTests|SQLTaskMenuProbeTests|TableExportStreamProbeTests|AgentApprovalDecisionProbeTests|ObjectTreeRetryProbeTests|BackupRestoreImportProbeTests|SessionDiagnosticsProbeTests|ObjectDiagnosisProbeTests|TableEditDDLProbeTests|UISnapshotSidebarStateTests"
while [ $# -gt 0 ]; do
    case "${1}" in
        --filter) FILTER="${2:-}"; shift 2 ;;
        *) echo "未知参数：${1}（支持 --filter <片段>）"; exit 2 ;;
    esac
done

export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH="${SCRATCH}/clang-module-cache"
export SWIFT_MODULE_CACHE_PATH="${SCRATCH}/swift-module-cache"
export DOYAH_UI_SNAPSHOT=1

# 与用户真实数据解耦：笔记 / 外发日志指到每轮清空的临时目录
# （探针真开 shell，但不该往真实数据家里写一个字节）。
PROBE_DATA="${SCRATCH}/ui-interaction-data"
rm -rf "${PROBE_DATA}"
mkdir -p "${PROBE_DATA}/notes" "${PROBE_DATA}/egress"
export DOYAH_NOTES_DIR="${PROBE_DATA}/notes"
export DOYAH_EGRESS_LOG_DIR="${PROBE_DATA}/egress"

mkdir -p "${CACHE}" "${SCRATCH}" "${CLANG_MODULE_CACHE_PATH}" "${SWIFT_MODULE_CACHE_PATH}" "${OUT}"
cd "${ROOT}"

LOG="${OUT}/run-$(date +%Y%m%d-%H%M%S).log"
echo "==> 跑交互探针（${FILTER}）—— 证据日志 ${LOG}"
# 证据面（T-20261009-095 ②）：回执里的「工具链」必须可复现 ⇒ 每次跑都写进输出（`DEVELOPER_DIR` 仍可外部覆盖）。
echo "ℹ️ 工具链证据: DEVELOPER_DIR=${DEVELOPER_DIR} · $("${DEVELOPER_DIR}/usr/bin/xcodebuild" -version 2>/dev/null | tr '\n' ' ')"
set +e
"${SWIFT}" test \
    --disable-sandbox \
    --package-path . \
    --cache-path "${CACHE}" \
    --scratch-path "${SCRATCH}" \
    --manifest-cache local \
    -Xswiftc -disable-sandbox \
    --filter "${FILTER}" 2>&1 | tee "${LOG}"
STATUS="${PIPESTATUS[0]}"
set -e
if [ "${STATUS}" -ne 0 ]; then
    echo "✗ swift test 退出码 ${STATUS}（完整日志 ${LOG}）"
    exit "${STATUS}"
fi

echo
echo "==> 核对：跑了几条、有没有跳过（跳过 ≠ 通过）"
python3 - "${LOG}" <<'PY'
import re
import sys

log = open(sys.argv[1], encoding="utf-8", errors="replace").read()
failures = []

executed = re.findall(r"Executed (\d+) tests?, with (\d+) failures? \((\d+) unexpected\)", log)
if not executed:
    failures.append(
        "日志里没有 \"Executed N tests\" —— 探针根本没跑（检查 --filter / DOYAH_UI_SNAPSHOT）"
    )
else:
    # 一个 xctest 进程里会打好几个套件（本套件 + 过滤后剩 0 条的空套件）⇒ 取**条数最多**那条汇总，
    # 否则会被后面那些 0 条的空套件盖掉（本次实测第一版就是这么假红的）。
    total, failed, unexpected = max(executed, key=lambda row: int(row[0]))
    if int(failed) or int(unexpected):
        failures.append(f"汇总非零失败：{failed} 失败 / {unexpected} 意外")
    if int(total) < 133:
        failures.append(
            f"只跑了 {total} 条 —— 十九批一百三十三条（鼠标上报 / DECCKM / 右键归属 / ⌥⌘D 多光标 /"
            " ⌥⌘↑↓ 加光标 / ⌥ 拖拽列选 / 逐行菜单内容 / 菜单作用行 / 菜单确定性与跟随行 /"
            " 点击地图 / 留白点给键盘 / 清空按钮三态 + 回车接线 / 打字后回车交词 / 修前对照 / 整框源锚点 /"
            " 复制四档格式与默认 TSV / 排序三档与 NULL / Shift 次要键 / 筛选条默认在场 /"
            " 换列与换运算符 / 逐字打值 / 大小写开关 / 多条件 AND 与删条件 /"
            " 回执三枚动作都在且各带各的提示 / 复制整本进剪贴板 / 口令不在剪贴板里 /"
            " 空态给理由不动剪贴板 / 清空后回空态 / 导出字节与结构一致 / 每条回执都画出来 /"
            " 任务菜单每行四段与删除子菜单 / 空册子给理由且保存跟着语句走 / 点载入切语句库连接 /"
            " 点解绑松开页签 / 点删除盘上少一条 / 工具栏走同一份菜单判定 /"
            " 整表导出真落文件与三趟 FETCH / 空表不落文件 / 半途失败不留半成品 /"
            " 整库逐张落文件且一张没成不打断 / 两条导出入口共用一条取数路 /"
            " 审批单两枚真按钮且各自带提示 / 点拒绝一条都没发且历史读作已拒绝 /"
            " 覆盖写入逐条带目标库且拒绝交空表 / 审批单走同一份接线 /"
            " 失败行一枚真重试按钮且点得动 / 四档不出逐档无按钮 / 先清旧错误再取数 /"
            " 在途时入口消失 / 树的占位行走这一份 /"
            " 分页六档与页码字面 / 换档位回第 1 页 / 四枚箭头各自到头 / 越界页码夹取 /"
            " 分页后只复制当前页的行 / 十万行只物化一页 / 标注只对已加载行分页 /"
            " 十二万行游标顺序落盘且无 LIMIT·OFFSET / 分块落盘与进度 / 中途失败不留残件且能重试 /"
            " xlsx 是标准 ZIP 六件齐 / 数值与文本类型映射 / 行列数与逐字节一致 / 不引第三方 xlsx 库 /"
            " 诊断上下文（连接·库·对象·最近一次执行读数）带入 / 右键入口点在同一条收口上 /"
            " 对象统计按对象收窄 / 没有统计视图时明说未取到且不发查询 /"
            " 结论里的对象名带链接且解得回身份 / 词中间不许认出短名 / 提示词带齐上下文 /"
            " 条件计数只发一条且多语句被拒 / 行详情列序与 JSON 竖排与空串分得开 /"
            " 外键入口要等元数据且只给有外键的列 / 跳转带值且无外键不生成语句 /"
            " 新列不带默认类型且空类型整批拒绝 / 结构变更先预览再按固定顺序执行 /"
            " 结构对比默认不动目标多出的表且被跳过的如实列出 /"
            " 折叠状态活过一次活动栏切换（连接分组：折叠到像素上、视图树重建后逐字节相同） /"
            " 格式化菜单与 ⇧⌘F 打到同一入口 / 格式化投递落到真编辑器 / 一次撤销逐字回到原文 /"
            " 认不出语言时明说且正文一字未动 /"
            " 编辑区 AI 辅助的闸门在发请求之前 / 模型名没配与连不上分得开 / 面板两行读真配置 /"
            " 应用走可撤销那条路且只应用一次 / 「不发送」档一次请求都不发 / 连不上如实说 /"
            " 应用之后一次 ⌘Z 逐字回到原文 / 解释态没有可应用的东西 /"
            " 笔记正文一次撤销只退一段 / 格式化撤销不退文字 / 一万行装得进来且编辑不重排整篇）应当都跑到"
        )

expected = [
    # 笔记正文档（`FR-NTS-NOTE-FORMAT-001` ②③）：撤销粒度与万行文档。
    "testOneUndoRemovesExactlyTheLastParagraph",
    "testUndoAfterAFormatCommandKeepsTheText",
    "testATenThousandLineDocumentOpensAndStaysEditable",
    "testMouseReportingForwardsToTheProgramAndOptionKeepsItLocal",
    "testCursorKeyBytesFollowDECCKMOnARealProgram",
    "testRightClickMenuStaysLocalAndOnlyOptionForwardsIt",
    "testOptionCommandDTypesInEveryOccurrenceAndOneUndoRevertsAll",
    "testOptionArrowMultipliesCaretsAndEditingHitsEveryCaret",
    "testOptionDragSelectsAColumnAcrossLinesWithoutCrossingThem",
    "testEachRowKindGetsItsOwnMenuNotTheServersMenu",
    "testMenuTargetFollowsTheRowUnderTheMouse",
    "testMenuIsDeterministicAndFollowsTheRow",
    "testEverySamplePointInTheVisibleBoxLandsOnTheBoxOrItsControls",
    "testPaddingClicksHandTheFieldTheKeyboard",
    "testClearButtonShowsWithTextAndClearsIt",
    "testTypedTextThenReturnStillHandsTheWordOut",
    "testLegacySwiftUISearchBoxWouldSwallowThePaddingPoints",
    "testSourceAnchorsKeepTheBoxPureAppKit",
    # 第五批（v0.3.0 数据库运维面第一跳 · FR-STD-DB-RES-006）：复制为多格式
    "testEveryFormatIsOnTheMenuAndReachesTheRealPasteboard",
    "testDefaultCopyIsTSVWithHeaderWithoutAnyEscapingDamage",
    "testEscapingSurvivesTheRealCopyPath",
    "testInsertCopyPointsAtTheTableBeingBrowsed",
    "testInsertCopyWithoutASourceTableSaysPlaceholderInsteadOfGuessing",
    "testEmptySelectionLeavesThePasteboardUntouched",
    "testCopyNeverLeavesAFileOnDisk",
    # 第六批（v0.3.0 数据库运维面第二跳 · FR-STD-DB-RES-007）：客户端排序
    "testEveryHeaderCellIsSortableAndAClickLandsOnItsOwnColumn",
    "testClickingTheHeaderCyclesAscendingDescendingAndBackToServerOrder",
    "testNullsStayAtTheEndInBothDirections",
    "testShiftClickAddsASecondaryKeyWithoutLosingThePrimary",
    "testShiftClickOnTheSecondaryKeyFlipsThenRemovesOnlyThatKey",
    "testClickingTheEmptyHeaderAreaChangesNothing",
    # 第七批（v0.3.0 数据库运维面第三跳 · FR-STD-DB-RES-008）：客户端筛选
    "testBarIsAlwaysPresentAndAddingAWaitingConditionKeepsEveryRow",
    "testTheColumnPopupChangesWhichColumnIsFiltered",
    "testTheOperatorPopupSwitchesContainsNotContainsAndEmptiness",
    "testTypedValueFiltersLiveAndKeepsTheEditingSession",
    "testCaseSensitiveToggleChangesWhichRowsMatch",
    "testMultipleConditionsAreAndedAndRemovingThemRestoresServerOrder",
    # 第八批（B1 批次第一片 · FR-STD-DB-TASK-003）：执行回执页
    "testTheThreeActionsAreRealButtonsWithTheirOwnHints",
    "testCopyReachesTheSystemPasteboardWithEveryReceiptNewestFirst",
    "testCopyNeverCarriesThePasswordLiteral",
    "testEmptyPaneExplainsItselfAndLeavesThePasteboardAlone",
    "testClearEmptiesTheLogAndThePaneFallsBackToItsEmptyState",
    "testExportWritesExactlyWhatTheStructureHoldsAndNoSecret",
    "testMoreReceiptsPaintMoreOfThePane",
    # 第九批（B1 批次第二片 · FR-STD-DB-TASK-001）：工具栏「任务」菜单
    "testEachRowCarriesNameDatabaseModeAndLimit",
    "testEmptyBookExplainsItselfAndSaveFollowsTheScript",
    "testClickingLoadBringsScriptConnectionDatabaseAndBinding",
    "testClickingUnbindReleasesTheTabAndKeepsTheTask",
    "testClickingDeleteRemovesExactlyThatTask",
    "testToolbarUsesTheSameMenuBuilder",
    # 第十批（B1 批次第三片 · FR-STD-DB-IO-002）：整表 / 整库导出真跑一次落文件
    "testCursorExportWritesARealFileWithEveryRow",
    "testEmptyTableThrowsAndLeavesNoFileBehind",
    "testFailureMidwayLeavesNoPartialFile",
    "testDatabaseExportWritesOneFilePerTableAndKeepsOneFailureFromStoppingTheRest",
    "testBothExportEntriesShareOneStreamingPath",
    # 第十一批（B1 批次第四片 · FR-STD-DB-TASK-002）：审批单两枚动作
    "testTheDecisionRowIsTwoRealButtonsAndGoesGreyWhileWorking",
    "testClickingRejectSendsNothingAndLeavesRejectedInHistory",
    "testOverwritePlanListsTwoStatementsWithTheirOwnTargetAndRejectionSendsNone",
    "testTheSheetUsesThatRowAndWiring",
    # 第十三批（B2 批次 · FR-STD-DB-RES-009 / 011）：分页控制条与大结果集分页
    "testPagerOffersEveryPageSizeAndSaysWhichPageOfHowMany",
    "testChangingPageSizeGoesBackToTheFirstPage",
    "testFirstPreviousNextAndLastEachLandOnTheirPage",
    "testOutOfRangePageIndexIsClampedNotShownAsPageTenOfThree",
    "testCopyAfterPagingTakesOnlyTheRowsOnTheCurrentPage",
    "testLargeResultPagesOnePageAtATimeAndStaysResponsive",
    "testPagerSaysItOnlyPagesTheLoadedRows",
    # 第十三批（B2 批次 · FR-STD-DB-RES-013）：超大结果集流式落盘
    "testLargeResultSetStreamsThroughACursorWithoutLimitOrOffset",
    "testStreamedWriteIsChunkedAndReportsProgressPerPage",
    "testCancelMidwayLeavesNoFileAndReleasesTheCursor",
    # 第十三批（B2 批次 · FR-STD-DB-RES-014）：导出 Excel（.xlsx）
    "testWorkbookIsARealZipWithEveryPartInside",
    "testNumericAndTextCellsAreTypedTheWayTheResultSays",
    "testEveryRowLandsOnceAndTheSameInputExportsIdenticalBytes",
    "testTheWriterDoesNotPullAThirdPartyXLSXLibrary",
    # 第十四批（B4 批次 · FR-STD-DB-IO-003 / 004 / 006 / 007）：备份 · 逐段恢复 · 导入
    "testDumpRunsExactlyOneCommandWithTheArgvThePanelPreviewed",
    "testDumpFailureSurfacesExitCodeAndTailInsteadOfSayingDone",
    "testSectionedRestoreWalksAllThreeSectionsAgainstTheChosenDatabase",
    "testSectionedRestoreStopsAtTheFailingSectionAndOffersTheResumeCommand",
    "testCSVImportSendsEveryValueToTheRightColumnOverCopy",
    "testImportFallsBackToBatchedInsertAndReportsEveryRow",
    "testXLSXWizardReadsARealWorkbookAndImportsEveryCell",
    "testReadOnlyConnectionRefusesTheImportBeforeAnythingIsSent",
    "testBackupAndImportStayOnOneProductionPath",
    # 第十二批（B1 批次第四片 · FR-STD-DB-META-006）：失败那一行的「重试」
    "testFailureRowDrawsARealRetryButtonAndClickingItRunsOnce",
    "testCoreJudgementDecidesWhetherTheEntryIsDrawn",
    "testClickingRetryClearsTheErrorBeforeReloading",
    "testInFlightRowDrawsNoEntry",
    "testObjectTreeUsesThatRowAndCoreJudgement",
    # 第十五批（B5 批次余项 · FR-STD-DB-DIAG-006）：连接上下文里的诊断入口
    "testScopeCarriesConnectionDatabaseObjectAndLastExecutionReadings",
    "testRefusedOrMissingReceiptReadsAsNotAvailableInsteadOfZero",
    "testTableScopeGathersScopedStatisticsAndTheLastReadingInOrder",
    "testObjectWithoutStatisticsSaysNotAvailableAndSendsNoQuery",
    "testDiagnoseEntryIsInBothRenderingsAndCarriesTheContext",
    "testClickedObjectNameBecomesALinkAndJumpsToThatNode",
    "testNamesInsideLongerIdentifiersAreNotLinked",
    "testPromptCarriesTheContextForTheModel",
    # 第十六批（B6 批次 · FR-STD-DB-DATA-002 / 005 / 006 · DDL-003 / 004）：数据编辑与表结构
    "testCountEntrySendsOneCountStatementAndOpensItInATab",
    "testCountRefusesMultiStatementAndSendsNothing",
    "testRowDetailPanelModelKeepsOrderAndFormatsLongJSON",
    "testJumpEntryNeedsForeignKeyMetadataBeforeItIsShown",
    "testJumpOpensTheReferencedTableWithTheValueBakedIn",
    "testJumpWithoutForeignKeySaysSoAndOpensNothing",
    "testDesignSheetStartsNewColumnsWithoutAGuessedType",
    "testAlterPlanRunsOnlyAfterItsPreviewAndInTheFixedOrder",
    "testSchemaDiffScriptsOnlyTickedChangesAndNeverDropsByDefault",
    # 第十七批（B7 批次 · FR-STD-DB-CONN-012）：连接分组的折叠状态要活过活动栏切换
    "testGroupCollapseSurvivesActivityBarSwitch",
    # 第十八批（v0.6.0 判据债 · FR-STD-WS-NAV-014）：格式化这条链的五条
    "testScrambledJSONThroughTheModelPath",
    "testEditMenuFormatItemIsWiredToTheSameEntry",
    "testFormatIsUndoableBackToTheExactOriginal",
    "testLanguageWithoutABuiltinSaysSoAndLeavesTheTextAlone",
    "testDeliveryActuallyLandsInTheRealEditor",
    # 第十九批（v0.6.0 判据债 · FR-STD-WS-AI-001）：编辑区 AI 辅助的九条
    "testGateRefusesBeforeAnyRequest",
    "testMissingModelIsDistinguishedFromUnreachable",
    "testPanelCarriesRealModelAndEndpoint",
    "testApplyLandsThroughTheUndoableEditPath",
    "testSameDeliveryAppliesOnlyOnce",
    "testNoSendBoundaryNeverCallsTheRunner",
    "testUnreachableSaysSoInsteadOfPretending",
    "testApplyingAssistIsUndoableBackToTheExactOriginal",
    "testAnswerPhaseHasNothingToApply",
]
for name in expected:
    if name not in log:
        failures.append(f"日志里没有 {name}")
    elif not re.search(rf"Test Case '[^']*{re.escape(name)}\]' passed", log):
        failures.append(f"{name} 没有以 passed 收尾（跳过 / 失败都会走到这里）")

if "skipped" in log:
    failures.append("日志里出现 skipped —— 探针被跳过了，那不是通过")

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)
print(f"✓ {total} 条都真跑过（十九批）、都以 passed 收尾、没有跳过")
PY

echo
echo "==> 源锚点：判据盯的必须是产品那条线"
python3 - "${ROOT}" <<'PY'
import os
import sys

root = sys.argv[1]
anchors = {
    "App/Views/SQLEditorView.swift": (
        ("private var rememberedCarets: [NSRange] = []",
         "视图不再自己记住 AppKit 收不下的裸光标（⌥⌘↑↓ 加光标会静默失效）"),
        ("selectedRanges.map(\\.rangeValue) + rememberedCarets,",
         "选区集合不再并上自己记的裸光标"),
        ("guard rangeValues.count > 1, !text.isEmpty else {",
         "多光标打字不再看那份含裸光标的集合"),
        ("if event.keyCode == 53, rangeValues.count > 1 {",
         "Esc 收敛不再看那份含裸光标的集合"),
        ("if !isApplyingMultiSelection { rememberedCarets = [] }",
         "用户自己动光标时不再作废裸光标（会退回「看着一个光标、打字却在两处」）"),
    ),
    "Core/MultiCursor.swift": (
        ("let end = range.location + min(maxColumn + 1, contentLength)",
         "列选不再夹到行尾（短行会被拽过换行）"),
    ),
    "App/Views/TerminalView.swift": (
        ("TerminalInput.route(", "视图不再问 Core 的归属判定（拖动 / 滚轮那条线）"),
        ("TerminalInput.rightClickRoute(", "视图不再问 Core 的右键归属判定"),
        ("guard forwardsRightClick(event) else { return super.rightMouseDown(with: event) }",
         "右键「归本机」那一支不再走 AppKit 的弹菜单（菜单会永远不出现）"),
        ("if isReportingMouse(event) {", "鼠标事件不再先判归属再分发"),
        ("applicationCursorKeys: model.screen.isApplicationCursorKeysEnabled",
         "方向键不再带上 DECCKM（vim / less 分不出两种键序）"),
        ("TerminalInput.mouseReport(", "鼠标上报字节不再经唯一出口"),
        ("TerminalInput.shouldReport(", "鼠标上报不再按模式过滤"),
    ),
    "App/Views/ObjectTreeView.swift": (
        ("@State private var hoverBox = HoverBox()",
         "悬停行不再存进那个**无观察者**的盒子 ⇒ 鼠标停着不动界面会自己闪（2026-09-24 那次）"),
        ("RowMouseCatcher(",
         "每一行不再挂自己的鼠标捕获器 ⇒ 右键与「零等待选中」都会退回旧路"),
        ("makeMenu: {",
         "行里不再现建那一份菜单 ⇒ 会退回「整树一份 + 按列表行解析」那种错行"),
        ("object: row.object",
         "菜单的目标不再是**这一行自己的对象** ⇒ 会退回按悬停 / 上次选中解析"),
        ("ObjectTreePlaceholderRow(",
         "占位行不再走那一份（重试入口又会退回离屏点不到的 SwiftUI 按钮）"),
        ("ObjectTreeRetry.apply(",
         "重试两步不再走 Core 的 `apply` ⇒ 顺序散回视图里自己 for 一遍（判据读不到）"),
        # 反向那半（整树兜底菜单 `menuTargetObject` / `ObjectTreeMenuTarget.resolve(` 不许回来）由
        # `Tests/ObjectTreeRowMenuConventionTests.swift` 与 `Tests/ObjectTreeMenuConventionTests.swift`
        # 的 `XCTAssertFalse` 钉住 —— 这个脚本只支持「在场」形状，别把它写成第二个判据。
    ),
    "App/Views/ObjectTreeContextMenu.swift": (
        ("static func items(",
         "菜单内容不再有唯一入口（判据与界面读的会是两份东西）"),
        ("ObjectTreeActions.isAvailable(.", "菜单项的呈现不再由 Core 的规则决定（视图里会另写一份类型判断）"),
        ("ObjectTreeActions.hasContextMenu(row.object.kind)",
         "「这一行有没有菜单」不再问 Core 的 `menuKinds`"),
    ),
    "TestsUISnapshot/ObjectTreeContextMenuProbeTests.swift": (
        ("VStack(alignment: .leading, spacing: 6) {",
         "快照的容器不再由判据那一侧加 ⇒ 兄弟节点叠成一行，图上看着像「菜单只有一个条目」"),
    ),
    "App/Views/ObjectTreeRows.swift": (
        ("static func visibleRows(", "可见行不再是产品自己摊平出来的那一份（探针拿它当输入）"),
    ),
    "Core/ObjectTreeActions.swift": (
        ("public static let menuKinds: Set<DatabaseObject.Kind> = [",
         "「哪些节点类型该有右键菜单」不再在 Core 里单点定义（漏一个就判不出来了）"),
    ),
    # 第五批（`FR-STD-DB-RES-006`）：探针点的必须是**产品那份菜单与那条写剪贴板的路**。
    # 第六批（`FR-STD-DB-RES-007`）：再加表头点击那条路 —— 同一个文件，**一个键**（重复的键会让
    #   Python 字典静默丢掉先出现的那一份，第五批三条判据就白钉了）。
    "App/Views/ResultGrid.swift": (
        ("for format in ResultClipboard.Format.allCases {",
         "「复制为…」子菜单不再按格式枚举现建 ⇒ 少一档格式用户就点不到，探针也就量成了别的菜单"),
        ("pasteboard.setString(text, forType: .string)",
         "复制不再写系统剪贴板（改成落文件 / 只打日志，用户粘贴到的就是旧内容）"),
        ("tableName: copySourceTable?.name ?? ResultClipboard.placeholderTableName,",
         "复制的 INSERT 不再用来源表名 ⇒ 贴回库里的语句指向 table_name 这张不存在的表"),
        ("final class SortableHeaderView: NSTableHeaderView",
         "表头退回裸 `NSTableHeaderView` ⇒ 认不出「点的是哪一列、有没有按 Shift」，多列排序又会退回读 `sortDescriptors.first`"),
        ("if let header = tableView.headerView as? SortableHeaderView, let click = header.takeClick()",
         "派发不再问表头记下的那一击 ⇒ Shift 加次要键时翻的是老主键（多列排序加不上新列）"),
        ("onClick?(column, clickedAdditively)",
         "表头认得出列号却不派发 ⇒ 表头点击只剩 AppKit 那条随版本飘的路"),
        ("lastDisplayedRows != rows",
         "显示内容变更退回「首末行摘要」判断 ⇒ 取消排序后表格不重载，界面上留着旧顺序"),
    ),
    "App/Views/ResultTableView.swift": (
        ("copySourceTable: sourceTable",
         "结果区不再把来源表交给表格 ⇒ 复制 INSERT 只能落占位表名（而来源表本来就是它手里的事实）"),
        # 第六批（`FR-STD-DB-RES-007`）：表头点击真的接到状态层。
        ("gridState.toggleSort(columnIndex: columnIndex, additive: additive)",
         "表头点击不再交给状态层（排序循环只活在 Core 里，点表头会变成「什么都没发生」）"),
        # 第七批（`FR-STD-DB-RES-008`）：筛选条与「+ 加条件」入口默认在场。
        ("if !result.columns.isEmpty {",
         "筛选条退回 `isClientViewActive` 才渲染 ⇒ 没排过序的用户永远加不了第一个筛选条件（死路）"),
        ("isClientViewActive: gridState.isClientViewActive,",
         "条拿不到「现在有没有客户端操作」⇒ 提示要么不出现、要么一进来就喊"),
        # 第十三批（`FR-STD-DB-RES-009` / `RES-011` / `RES-014`）：分页条要拿到「已取回多少行」，
        # xlsx 导出那一项必须在菜单里 —— 两件事都在这一个文件里，所以都钉在这一块。
        ("loadedRowCount: result.rows.count,",
         "分页条不再拿到「已取回的行数」⇒ RES-011 ② 那句标注要么消失、要么写了个别的数"),
        ("Button(L(.exportXLSX)) { onExport(.xlsx, .utf8) }",
         "导出菜单里没有「导出为 Excel（.xlsx）」这一项 ⇒ 能力在 Core 里、用户却点不到"),
    ),
    # 第十三批（`FR-STD-DB-RES-009` / `RES-011`）：分页条必须是**真 AppKit 控件**、标注必须由
    # 「已取回的行数」算出来。退回 SwiftUI `Picker` / `Button` 时离屏宿主里只会剩下 0 枚控件，
    # 判据立刻变白绿（这正是这两行原先只能靠人点的原因）。
    "App/Views/ResultPagerBar.swift": (
        ("final class ResultPagerControlsView: NSView",
         "分页条退回 SwiftUI 控件 ⇒ 离屏宿主里不落 NSPopUpButton / NSButton，四枚箭头与档位又只能靠人点"),
        ("sizePopup.selectItem(at: index)",
         "下拉不再跟着生效的档位走 ⇒ 用户看到「100」、实际按 200 切"),
        ("loadedNote.stringValue = isPaged ? L(.resultPageClientOnlyNote, loadedRowCount) : \"\"",
         "RES-011 ② / R-21 那句「仅对已加载的 N 行分页」消失或脱离已取回行数 ⇒ 用户会以为翻页在查服务端"),
        ("button.toolTip = help",
         "箭头没有各自的提示 ⇒ 四枚同形图标分不出谁是谁（也是探针认按钮的依据）"),
    ),
    "Core/ResultView.swift": (
        ("public static var pageSizeChoices: [Int] { pageSizeOptions + [pageSizeAll] }",
         "档位清单不再是一处 ⇒ 界面与判据各写一份，少一档「全部」用户就切不回分页"),
    ),
    "App/Views/ResultClientViewBar.swift": (
        ("ResultFilterPopup(",
         "列 / 运算符退回 SwiftUI `Menu`（菜单项要到弹出那一刻才建，离屏探针量不到 ⇒ 换列换运算符又只剩人点）"),
        ("titles: ResultFilterOperator.allCases.map(filterOperatorLabel)",
         "运算符候选不再来自 Core 的 allCases（少一档用户就选不到，判据也量不到这一档）"),
        ("if isClientViewActive {",
         "R-21 提示不按状态判断 ⇒ 条默认在场之后每次查询都喊一句「仅对已加载的行生效」"),
    ),
    "Core/ResultView.swift": (
        ("public var isPending: Bool { op.requiresValue && value.isEmpty }",
         "「还没填值」的概念消失 ⇒ 点「+」那一刻 contains \"\" 会把整张表清空（用户什么都没输入就先丢光行）"),
        ("let effective = filters.filter { !$0.isPending }",
         "筛选不再跳过待填条件 ⇒ 刚加的那条当场筛掉所有行"),
        ("case (true, false):\n                        return descriptor.nullsFirst",
         "NULL 的先后不再只由 nullsFirst 决定 ⇒ 降序时 NULL 会跑到最前面（NULL 位置固定这条就没钉住）"),
    ),
    # 第八批（`FR-STD-DB-TASK-003`）：三枚动作必须是**真 `NSButton`**、必须落到 `AppState` 的方法上；
    # 写盘那条路只有一条（面板与探针共用）。钉住这几条，判据才不会在控件退回 SwiftUI 时变白绿。
    "App/Views/ExecutionReceiptPane.swift": (
        ("PanelIconButton(systemName: \"doc.on.doc\", help: L(.receiptCopyAll)",
         "复制那枚退回 SwiftUI `Button` ⇒ 离屏宿主里不落 `NSButton`，探针只能量到 0 枚（又得靠人点）"),
        ("appState.copyReceipts(for: tab.id)", "复制不再落到 `AppState` 的整本复制（视图里另拼了一份文本）"),
        ("appState.exportReceipts(for: tab.id)", "导出不再走 `AppState`（写盘那半条出口被绕开）"),
        ("appState.clearReceipts(for: tab.id)", "清空不再落到 `AppState`（册子还留着，界面看着清了）"),
    ),
    "App/Views/PanelIconButton.swift": (
        ("button.toolTip = help", "图标按钮不带悬停提示 ⇒ 用户看不出这枚是干什么的（也是探针认按钮的依据）"),
        ("button.setAccessibilityLabel(label ?? help)", "图标按钮没有读屏标签 ⇒ 读屏只会念「按钮」"),
    ),
    "App/AppState.swift": (
        ("func writeReceipts(_ log: ExecutionReceiptLog, to url: URL) -> Bool {",
         "落盘那一半不再是单独一个出口 ⇒ 面板与探针会各写一份 JSON（脱敏就能在其中一条上失效）"),
        ("let data = try log.exportData()", "导出不再用结构自己的 `exportData()` ⇒ 复制/导出/界面三处可能不是同一份"),
    # 第十批（`FR-STD-DB-IO-002`）：空表要在写盘**之前**认出来、逐表落盘只许一处。
    # 第十一批 / 第十二批（`FR-STD-DB-TASK-002` / `META-006`）：审计落点可注入、重试两步的出口只剩一处。
    # ⚠️ 同一个文件**只许一个键**：Python 字典会静默丢掉先出现的那一份 —— 第八批那两条判据
    #    曾因此死了两批（第二次出现的是第十批那个键）。加针请加进**同一个**块里。
        ("guard let first = try await fetcher.nextPage(), !first.rows.isEmpty else {",
         "空表又只判 nil ⇒ 会落一个只有表头的文件、面板报「导出成功 0 行」"),
        ("func streamDatabase(",
         "整库逐表落盘那一半又被塞回面板闭包里 ⇒ 它只能靠人点一次来验"),
        ("var agentAuditLogOverride: AgentAuditLog?",
         "审计落点不可注入 ⇒ 验一次「点拒绝」就得往用户的真审计里写一行（探针只能靠人手点）"),
        # 第十三批（`FR-STD-DB-RES-013` / `RES-014`）：流式导出的服务注入点、xlsx 的一次性分支。
        ("service: any DatabaseService,\n        onReport: ((ResultStreamWriter.Report) -> Void)? = nil",
         "流式导出不再有「服务可注入」的落地口 ⇒ 十二万行那条链只能靠人在保存面板上点一次"),
        ("if format.isBinary {",
         "xlsx 不再走「一次性写完」那条分支 ⇒ 二进制工作簿被塞进逐页写入器（要么报错、要么写出坏文件）"),
        # 第十四批（B4 批次 · FR-STD-DB-IO-003 / 004 / 006 / 007）：四条链的注入缝 —— 没有它们，
        # 「点了执行到底跑了几条命令 / 发了几条语句」只能靠人点（那正是四条长期挂 🟡 的真因）。
        ("var backupRunner: any ExternalProcessRunner",
         "备份执行器又不可注入 ⇒ 备份 / 逐段恢复只能靠人手点一次"),
        ("if let importServiceOverride",
         "导入的服务又不可注入 ⇒ 「值有没有串列」只能靠人点一次"),
        # 第十五批（`FR-STD-DB-DIAG-006`）：上下文带入的唯一收口 / 跳转请求 / 按对象取证。
        ("func beginObjectDiagnosis(for object: DatabaseObject)",
         "对象诊断的上下文不再有一处收口 ⇒ 菜单与面板各拼一份「连接 / 库 / 对象」，迟早对不上"),
        ("plan = scope.plannedEvidence(dialect: dialect, language: language)",
         "取证不再按作用域取计划 ⇒ 又回到「按页签那条语句」那条路，对象统计根本不取"),
        ("objectDiagnosisScope?.linkTargets ?? []",
         "可点对象名的候选集不再来自作用域 ⇒ 结论里随便一个同名词都会被拿去树上猜"),
        # 第十六批（B6 批次 · FR-STD-DB-DATA-006）：入口可见性只有一处判定、元数据读到才放行。
        ("func ensureForeignKeyColumns(for table: DatabaseObjectRef) async {",
         "外键元数据不再有唯一读取口 ⇒ 菜单要露不露只能靠视图自己猜（又回到常驻入口）"),
        ("func jumpableColumns(for table: DatabaseObjectRef?) -> Set<String>? {",
         "「这张表能跳哪几列」不再从一处读 ⇒ 面板与探针各拿一份"),
    ),
    # 第九批（`FR-STD-DB-TASK-001`）：菜单内容只许有一处判定、铺设只许走 AppKit 那份。
    "App/Views/SQLTaskAppKitMenu.swift": (
        ("static func actions(",
         "动作接线不再是一处 ⇒ 工具栏与探针会各拼一套「点载入之后做什么」"),
        ("menu.autoenablesItems = false",
         "菜单交给 AppKit 自己判可用性 ⇒ 「保存」的灰与亮由 AppKit 另判一遍，与 Core 的判定不是同一句话"),
    ),
    "App/Views/QueryToolbar.swift": (
        ("SQLTaskMenuPlan.make(", "工具栏不再走 Core 那份菜单判定"),
        ("SQLTaskAppKitMenu.build(", "工具栏不再走 AppKit 那份铺设（又回到离屏点不到的 SwiftUI 菜单）"),
        ("SQLTaskAppKitMenu.actions(", "工具栏自己拼了一份动作接线"),
    ),
    "Core/SQLTaskMenuPlan.swift": (
        ("public func label(readOnlyText: String, writableText: String) -> String {",
         "行文案不再带库 / 模式 / 上限 ⇒ 同名不同库的两条定义在菜单里长得一样"),
        ("!tabSQL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty",
         "「保存」不再跟着语句是否空白走 ⇒ 空脚本也能存成一条永远会被拒的定义"),
    ),
    # 第十一批（`FR-STD-DB-TASK-002`）：两枚审批动作必须是**真 `NSButton`**，接线只有一处。
    "App/Views/AgentApprovalDecisionRow.swift": (
        ("static func make(",
         "动作接线不再是一处 ⇒ 审批单与探针会各拼一套「点了之后做什么」"),
        ("button.isEnabled = isEnabled",
         "在途时按钮不变灰（状态机已流转过，再点一次就是第二次决策）"),
        ("func row(isWorking: Bool) -> AgentApprovalDecisionRow",
         "接线不再产出审批单那一行 ⇒ 探针只能自己拼一行（点的未必是用户点的那一枚）"),
        ("button.target = context.coordinator",
         "按钮没有 target/action ⇒ 点了什么都不发生"),
    ),
    "App/Views/AgentApprovalSheet.swift": (
        # 归位（2026-11-01 B2 批次）：上一片把这一行收进 `AgentApprovalDecisionWiring` 之后，
        # 审批单自己**不再点名**行类型，只拿接线产出的那一行 ⇒ 旧钉子成了永远判红的陈旧钉。
        # 现在钉「动作区还在、且从接线取那一行」；「产出那一行的地方」由 `AgentApprovalDecisionRow.swift` 那块管。
        ("private var decisionRow: some View {",
         "审批单的动作区不见了（两枚决策入口整块消失）"),
        ("AgentApprovalDecisionWiring.make(",
         "审批单自己拼了一份接线 ⇒ 探针量到的不是用户点的那条路"),
        ("actions.row(isWorking: isWorking)",
         "审批单没用接线给的那一行 ⇒ 探针点的是自己拼的一行"),
    ),
    # 第十二批（`FR-STD-DB-META-006`）：失败那一行与重试入口是 AppKit、两步执行只有一处。
    "App/Views/ObjectTreePlaceholderRow.swift": (
        ("ObjectTreeRetryButton(title: L(.commonRetry)",
         "重试入口退回 SwiftUI `Button` ⇒ 离屏宿主里落不出 `NSButton`（又只能靠人手点）"),
        ("button.setAccessibilityLabel(title)",
         "重试按钮没有读屏标签 ⇒ 读屏只会念「按钮」"),
    ),
    "Core/ObjectTreeRetry.swift": (
        ("public static func apply(",
         "两步执行（先清错误、再取数）不再有唯一出口 ⇒ 顺序又只有视图自己知道"),
    ),
    # 第十五批（B5 批次余项 · `FR-STD-DB-DIAG-006`）：两套渲染都要有诊断入口，统计必须按对象收窄，
    # 词边界必须真的判（否则「长名里认出短名」会跳到别的对象），链接必须由本层收口（不弹浏览器）。
    "App/Views/ObjectTreeContextMenu.swift": (
        ("L(.treeActionDiagnose)",
         "SwiftUI 那份右键菜单少了诊断入口（第七十批的老毛病：只改了一份，用户点的是另一份）"),
        ("appState.beginObjectDiagnosis(for: object)",
         "SwiftUI 那份菜单自己拼上下文 ⇒ 与 AppKit 那条路不是同一份"),
    ),
    "App/Views/ObjectTreeAppKitMenu.swift": (
        ("appState.beginObjectDiagnosis(for: object)",
         "生产右键（AppKit）不再接同一条收口 ⇒ 点下去面板里的上下文是空的"),
    ),
    "Core/DiagnosisScope.swift": (
        ("WHERE s.relname = \\(Self.literal(objectName))\\(schemaFilter)",
         "表级统计不再按对象收窄 ⇒ 拿整库排行冒充「这张表」"),
        ("case .cancelled, .refused: return nil",
         "被拒 / 取消的那一跑被当成执行读数 ⇒ 上下文里会写出「0 行 0 ms」这种编出来的读数"),
        ("public func statisticsQuery(dialect: any SQLDialect) -> String? {",
         "对象统计查询不再是可判的一处 ⇒ 判据只能去读界面文案"),
    ),
    "Core/DiagnosisObjectLinks.swift": (
        ("if isBoundary(before), isBoundary(after) {",
         "词边界不再判 ⇒ 长名（orders_archive）里认出短名，点了跳到别的对象"),
        ("piece.link = url",
         "对象名不再带链接属性 ⇒ 判据 ② 的入口整块消失（只剩一句「可以点」的提示）"),
    ),
    "App/Views/DiagnosisLinkedText.swift": (
        ("OpenURLAction { url in",
         "点了链接不再由本层收口 ⇒ 会交给系统浏览器（一个 doyah-object:// 的地址）"),
    ),
    # 第十六批（B6 批次）：计数 / 外键入口 / 表结构编辑器的三处**结构性**落点。
    "App/Views/ResultGrid.swift": (
        ("item.isHidden = !ForeignKeyNavigation.entryVisible(",
         "右键外键入口不再问 Core 那条判定 ⇒ 没有外键的列也会露出（点下去才说没有）"),
        ("clickedColumn: clickedColumnName",
         "入口判定不再看**右键点的那一格** ⇒ 露出的是选中列而不是用户点的列"),
    ),
    "App/Views/ResultTableView.swift": (
        ("jumpableColumns: appState.jumpableColumns(for: sourceTable)",
         "结果视图不再把「有外键的列」交给表格 ⇒ 菜单只能靠猜"),
        (".task(id: sourceTable?.qualifiedName) {",
         "外键元数据不再随结果视图挂载读取 ⇒ 入口永远不露（判据会变成永远绿的空判据）"),
    ),
    "Core/ForeignKeyNavigation.swift": (
        ("public static func entryVisible(jumpable: Set<String>?, clickedColumn: String?) -> Bool {",
         "入口可见性不再是可判的纯函数 ⇒ 判据只能去读界面"),
    ),
    "Core/TableDesign.swift": (
        ("guard columnChanges.allSatisfy({ $0.hasExplicitType }) else { return [] }",
         "列类型为空也照发 DDL ⇒ 生成 `ALTER TABLE t ALTER COLUMN c TYPE ;`（不许猜列类型这条失效）"),
        ("public static func blankColumn() -> TableColumnDefinition {",
         "新增列的初始定义不再有唯一构造口 ⇒ 界面又能悄悄预填一个类型"),
        ("guard columns.allSatisfy({ !$0.typeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {",
         "建表计划不再拒空类型 ⇒ 替人猜一个类型建出错误的列"),
    ),
    "App/Views/TableDesignSheet.swift": (
        ("columns.append(TableDesign.blankColumn())",
         "新增列又被预填了默认类型 ⇒ 使用者没选过的类型被写进 DDL"),
    ),
    "App/Views/TitleBarSearchField.swift": (
        ("final class TitleBarSearchBoxView: NSView",
         "整框不再是 AppKit 视图 ⇒ 命中测试又会被 SwiftUI 那层接走，可见框里的留白重新点不动（T-20261002-027 二次复测打回后的结构性换法）"),
        ("final class TitleBarSearchFieldView: NSTextField",
         "输入框不再是自己的 `NSTextField` ⇒ 非活动窗口的第一击（`acceptsFirstMouse`）没处放"),
        ("override func mouseDown(with event: NSEvent)",
         "整框不再自己接留白点击 ⇒ 那几处重新变成「点上去没反应」"),
        ("DOYAH_SEARCHBOX_PROBE",
         "真窗口命中地图探针没了 ⇒ 判据又只能量手工搭的宿主（第 162 轮就是在那里看偏的）"),
    ),
}

failures = []
for relative, needles in anchors.items():
    path = os.path.join(root, relative)
    if not os.path.exists(path):
        failures.append(f"{relative} 不在盘上")
        continue
    text = open(path, encoding="utf-8").read()
    for needle, why in needles:
        if needle not in text:
            failures.append(f"{relative} 里「{needle}」不见了：{why}")

for probe in ("TerminalInteractionProbeTests", "MultiCursorProbeTests", "ObjectTreeContextMenuProbeTests",
              "TitleBarSearchClickProbeTests", "ResultCopyProbeTests", "ResultSortProbeTests",
              "ResultFilterProbeTests", "ExecutionReceiptPaneProbeTests",
              "SQLTaskMenuProbeTests", "TableExportStreamProbeTests",
              "AgentApprovalDecisionProbeTests", "ObjectTreeRetryProbeTests",
              "ResultPagingProbeTests", "ResultStreamExportProbeTests",
              "ResultXLSXExportProbeTests", "BackupRestoreImportProbeTests",
              "SessionDiagnosticsProbeTests", "ObjectDiagnosisProbeTests",
              "TableEditDDLProbeTests", "UISnapshotSidebarStateTests"):
    if not os.path.exists(os.path.join(root, f"TestsUISnapshot/{probe}.swift")):
        failures.append(f"TestsUISnapshot/{probe}.swift 不在盘上")

if failures:
    for item in failures:
        print(f"✗ {item}")
    sys.exit(1)
print("✓ 源锚点都在：路由判定在 Core、视图真的问过它、字节从 TerminalInput 出去、裸光标由视图自己记、"
      "菜单由 Core 的规则决定且悬停行存在无观察者的盒子里")
PY

echo
echo "==> 完成：证据日志在 ${OUT}/"
echo "    本入口判住的各条（按批）："
echo "    · §1 FR-STD-WS-TOOL-001 鼠标上报（真 PTY 上的 SGR 报文：右下角点击列行变大、拖动 32、滚轮 64、⌥ 归本机）"
echo "    · §1 FR-STD-WS-TOOL-001 方向键 DECCKM（?1h 时 ^[OA、复位后 ^[[B）"
echo "    · §1 FR-STD-WS-TOOL-001 右键菜单（五项齐备且指向产品自己的动作、接管 + ⌥ 时按钮码 10 转发）"
echo "    · §3 FR-STD-WS-EDIT-016 ⌥⌘D 选下一处（三处同内容都进选区、打字三处一起改、一次撤销全回退、光标不漂）"
echo "    · §3 FR-STD-WS-EDIT-016 ⌥⌘↑ / ↓ 加光标（第 109 轮修的缺陷：加出来的光标必须真的在；打字 / ⌫ / 回车逐个生效；Esc 收敛）"
echo "    · §3 FR-STD-WS-EDIT-016 ⌥ 拖拽列选（逐行一段、短行夹到行尾、绝不跨换行、一次撤销）"
echo "    · §4 FR-STD-DB-META-012 逐行菜单**内容**（七类节点各一张图；动作项与 Core 的规则双向对账；非服务器行不许出现服务器菜单项）"
echo "    · §4 FR-STD-DB-META-012 菜单作用在**哪一行**（悬停优先 / 盒子空退回选中项 / 表头与无菜单节点 / 都不成立时的空菜单）"
echo "    · §4 FR-STD-DB-META-012 菜单确定性与跟随行（同一行两次逐字节一致、不同行必须画成两个样子）"
echo "    · §1 FR-STD-WS-UI-006 标题栏搜索栏点击地图（可见框内 21 点全部落到整框 / 输入框 / 清空按钮；上一轮那版同期必须判红）"
echo "    · §1 FR-STD-WS-UI-006 留白点按下把键盘交给输入框（左留白 + 上下留白逐点：第一响应者 = 输入框或它的字段编辑器）"
echo "    · §1 FR-STD-WS-UI-006 清空按钮三态（空词隐藏 / 有词显示 / 点它清空并回调）"
echo "    · §1 FR-STD-WS-UI-006 打字之后按回车那个词真的交出去（打字不许把 AppKit 的编辑会话收掉 —— 2026-10-02 晚的真缺陷）"
echo "    · §1 FR-STD-WS-UI-006 修前对照（装饰参与命中测试的那份框必须判红 —— 这条判据量得出来）"
echo "    · §3.4 FR-STD-DB-RES-006 复制为多格式（真视图 + 真菜单 + 真系统剪贴板：四档格式都在菜单里、默认 ⌘C = 带表头 TSV、转义不乱、只复制选中的行、INSERT 指向正在浏览的表、空选中不动剪贴板、不落文件）"
echo "    · §3.4 FR-STD-DB-RES-008 客户端筛选（真控件点击 + 真字段编辑器打字：条默认在场、加条件不丢行、换列换运算符、逐字打值、大小写开关、多条件 AND、删光条件后入口仍在）"
echo "    · §3.4 FR-STD-DB-TASK-003 执行回执（真 AppKit 按钮 performClick + 真系统剪贴板：三枚动作都在且各带提示、复制整本新的在前且口令已抹、空态给理由不动剪贴板、清空后回空态、导出字节与结构一致、三条比一条画得多）"
echo "    · §3.4 FR-STD-DB-IO-002 整表 / 整库导出（假服务应答游标 + 真 streamTable 写盘：2500 行 / 2501 行文件、三趟 FETCH、空表不落文件、半途失败不留残件、整库逐张落文件且一张没成不打断）"
echo "    · §3.4 FR-STD-DB-TASK-001 工具栏「任务」菜单（真 NSMenu 按行派发：行文案四段、空册子给理由、「保存」跟着语句走、点载入切语句·库·连接并绑上、点解绑松开页签、点删除册子与盘上各少一条、工具栏走同一份判定）"
echo "    · §3.4 FR-STD-DB-TASK-002 审批单两枚动作（真 NSButton performClick：两枚都在且各带提示 / 在途全灰 / 点拒绝后队列清空、历史与盘上都是已拒绝且一条都没执行 / 覆盖写入两条各带目标库、拒绝交空表）"
echo "    · §3.4 FR-STD-DB-META-006 失败那一行「重试」（真 NSButton performClick：按钮在且点得动 / 四档不出逐档零按钮 / 先清旧错误再取数 / 在途时入口消失）"
echo "    · §3.4 FR-STD-DB-DIAG-006 连接上下文里的诊断入口（两套右键渲染都在、点下去连接 / 库 / 对象 / 最近一次执行读数齐备、对象统计按对象收窄、没有统计视图时明说不发查询、结论里的对象名带链接且解得回身份、词中间不许认出短名、提示词带齐上下文）"
echo "    · §3.4 FR-STD-DB-CONN-012 连接分组的折叠（离屏真渲染：折叠到像素上、切活动栏回来状态还在、视图树重建后逐字节相同）"
echo "    · §3.4 FR-STD-DB-RES-007 客户端排序（真表头点击 + 真 AppKit 跟踪循环：升 → 降 → 取消三档、数值按数值比、NULL 两种方向都留末尾、Shift 加 / 翻 / 删次要键、点空白处不动、排序不改列宽）"
