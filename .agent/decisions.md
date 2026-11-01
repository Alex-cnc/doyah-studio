# 自行决策留痕

- 2026-11-01 · 队列用 `.agent/plan.yaml` **派生**台账，不另立第二事实源 · 理由：台账是活书，用户反复强调不要两份账 · 影响：台账变动后本文件重出，翻 ✅ 一律写回台账
- 2026-11-01 · 所有 `done_when` 统一走 `Scripts/ledger-row.py` · 理由：判据必须可跑且同一形状 · 影响：台账表格列序变了要同步改这个脚本
- 2026-11-01 · `FR-STD-DB-RES-006` 的「界面粘贴待人工点验」按**交付面未取证**处理，不当成「必须人点」 · 理由：本条验收要点 ①~④ 全在剪贴板内容这一侧，可机械判 · 做法：真视图 + 真右键菜单 + 真 `NSPasteboard` 派发读回，挂进 `verify-ui-interactions.sh` 第五批 · 影响：探针默认 `XCTSkip`，取证跑（`DOYAH_UI_SNAPSHOT=1`）
- 2026-11-01 · 复制 INSERT 的表名按 `QueryTab.sourceTable` 写真实表名（原为一律占位 `table_name`） · 理由：与第七十二批 CLI 侧「看着对、跑不通的 SQL」同一类缺陷，属本条（复制为 INSERT 文本）范围内的真缺陷，不是扩范围 · 影响：手写 SQL 的结果仍落占位、不猜；`ResultClipboard.placeholderTableName` 成为占位串唯一出处
- 2026-11-01 · `FR-STD-DB-RES-007` 的「界面点击待人工点验」按**交付面未取证**处理，不当成「必须人点」 · 理由：本条验收要点（点表头排序 / 多列 / 升降 / NULL 位置）全在表头点击这一侧，可用真表头 + 真 AppKit 跟踪循环机械判 · 做法：`TestsUISnapshot/ResultSortProbeTests`（6 例）挂进 `verify-ui-interactions.sh` 第六批 · 影响：探针默认 `XCTSkip`，取证跑（`DOYAH_UI_SNAPSHOT=1`）
- 2026-11-01 · Shift 点击不靠 AppKit 的 `sortDescriptors` 认列，改由 `SortableHeaderView` 自己记那一击 · 理由：AppKit 把新列追加在后面（`first` 还是老主键），且实测 macOS 27 离屏窗口里 Shift 点击它干脆不派发 ⇒ 只靠它，多列排序静默失效 · 影响：`super` 仍要调（列宽拖动 / 换列排序），过滤条件 = 「没派发过 + 没拖动 + 不在分界线上 + 单击」
- 2026-11-01 · 表格「显示内容变了没有」从首末行摘要改成逐行比对 · 理由：取消排序回到服务端顺序时末行常与降序那份相同 ⇒ 摘要不变 ⇒ 不重载 ⇒ 界面上留着旧顺序（探针实测） · 影响：`ResultGrid.Coordinator` 每次 update 做一次 O(行数) 早退比较
- 2026-11-01 `FR-STD-DB-RES-008`：把筛选条里的列 / 运算符从 SwiftUI `Menu` 换成真 `NSPopUpButton`（`ResultFilterPopup`）—— 理由：`Menu` 的菜单项只在弹出那一刻才建（实测 `itemTitles == []`、`menu.update()` 与 `menuNeedsUpdate` 都填不进），换列 / 换运算符在离屏探针里量不到；与 `TitleBarSearchField` 那次「要能量就得是真控件」的换法同源。
- 2026-11-01 `FR-STD-DB-TASK-003`（B1 第一片）：把回执页三枚动作从 SwiftUI `Button` 换成真 `NSButton`（新 `App/Views/PanelIconButton.swift`）—— 理由：SwiftUI 按钮在离屏宿主里不落 `NSButton`、无障碍树也不构建（本机实测：合成鼠标事件投进去 action 不动、`accessibilityChildren()` = 0），三枚正是验收要点里要点的动作，不换就只能靠人点；与 `ResultFilterPopup` / `TitleBarSearchBox` 的换法同源。
- 2026-11-01 `FR-STD-DB-TASK-003`：导出拆成两半（`exportReceipts(for:)` 只问路径，`writeReceipts(_:to:)` 落盘）—— 理由：模态 `NSSavePanel` 无人值守不该弹窗、探针也不该去点它，而「写出去的字节里有没有原文」是这条验收唯一能把住的一环；拆开之后探针拿**同一个函数**只换路径，不另开一条写盘路。
- 2026-11-01 B1 批次的划分前提有一半不成立：`batches.yaml` 原写「只补点验与接线」，实测 TASK-001/002 的入口（工具栏任务菜单 / 审批单）也是 SwiftUI ⇒ 先要把入口换成真 AppKit 控件才量得到。已写进 `plan-batches.py` 的 B1 说明，本跳只收口 TASK-003，余 4 条留给下一跳。
- 2026-11-01 `FR-STD-DB-TASK-002`（B1 第四片）：两枚审批动作从 `DialogActionButton` 换成真 `NSButton`（新 `App/Views/AgentApprovalDecisionRow.swift`），并把「点了做什么」收成 `AgentApprovalDecisionWiring.make` 一处、由它直接产出那一行（`wiring.row(isWorking:)`）—— 理由：上一版探针自己拼一行、审批单另拼一行，实测「把两枚动作在审批单里接反」判不红（探针点的不是用户点的那一枚）；换成接线产出整行之后同一改动当场判红。
- 2026-11-01 `FR-STD-DB-TASK-002`：给 `AppState` 加了 `agentAuditLogOverride`（与 `sqlTaskStoreOverride` 同形）—— 理由：验一次「点拒绝 ⇒ 历史读作已拒绝」必须读盘上那份 JSONL，而 `agentAuditLog` 原本写死 `.shared`，那等于往用户的真审计里写一行。
- 2026-11-01 `FR-STD-DB-META-006`（B1 第四片）：失败那一行的两步执行从视图 `performRetry` 搬进 `Core/ObjectTreeRetry.apply` —— 理由：顺序（先清错误、再取数）原先只活在 `@State` 上，除人点一次没有第二条路能读；搬进 Core 之后探针把两个回调接成记账状态就能判顺序。
- 2026-11-01 `verify-ui-interactions.sh` 源锚点字典里 `"App/AppState.swift"` 登记了两次（第八批 + 第十批）⇒ Python 字典静默丢掉先出现那份，第八批两条判据两批以来是死的。已合成一个键并在原地加注「一个文件只许一个键」。这是坏判据（红线 #2/#14），不是本片引入。
- 2026-11-01 B2 批次：分页条整条换成 AppKit 控件（不是「加一枚隐藏按钮」）—— 理由 = 离屏宿主里 SwiftUI `Picker` / `Button` 不落可点控件，四枚箭头与六档位在自动化里一次都量不到；换法沿用 `ResultFilterPopup` / `PanelIconButton` 两条既有先例。
- 2026-11-01 B2 批次：`AgentApprovalDecisionProbeTests` 与源锚点里「审批单里要有 `AgentApprovalDecisionRow(`」改成反向钉（审批单**不许**自己构造那一行）—— 该钉子钉的是上一片之前那个旧形状，保留它等于保留一条永远判红的判据；产出者的锚点仍在 `AgentApprovalDecisionRow.swift` 那块。
