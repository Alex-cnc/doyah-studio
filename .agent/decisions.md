# 自行决策留痕

- 2026-11-01 · 队列用 `.agent/plan.yaml` **派生**台账，不另立第二事实源 · 理由：台账是活书，用户反复强调不要两份账 · 影响：台账变动后本文件重出，翻 ✅ 一律写回台账
- 2026-11-01 · 所有 `done_when` 统一走 `Scripts/ledger-row.py` · 理由：判据必须可跑且同一形状 · 影响：台账表格列序变了要同步改这个脚本
- 2026-11-01 · `FR-STD-DB-RES-006` 的「界面粘贴待人工点验」按**交付面未取证**处理，不当成「必须人点」 · 理由：本条验收要点 ①~④ 全在剪贴板内容这一侧，可机械判 · 做法：真视图 + 真右键菜单 + 真 `NSPasteboard` 派发读回，挂进 `verify-ui-interactions.sh` 第五批 · 影响：探针默认 `XCTSkip`，取证跑（`DOYAH_UI_SNAPSHOT=1`）
- 2026-11-01 · 复制 INSERT 的表名按 `QueryTab.sourceTable` 写真实表名（原为一律占位 `table_name`） · 理由：与第七十二批 CLI 侧「看着对、跑不通的 SQL」同一类缺陷，属本条（复制为 INSERT 文本）范围内的真缺陷，不是扩范围 · 影响：手写 SQL 的结果仍落占位、不猜；`ResultClipboard.placeholderTableName` 成为占位串唯一出处
- 2026-11-01 · `FR-STD-DB-RES-007` 的「界面点击待人工点验」按**交付面未取证**处理，不当成「必须人点」 · 理由：本条验收要点（点表头排序 / 多列 / 升降 / NULL 位置）全在表头点击这一侧，可用真表头 + 真 AppKit 跟踪循环机械判 · 做法：`TestsUISnapshot/ResultSortProbeTests`（6 例）挂进 `verify-ui-interactions.sh` 第六批 · 影响：探针默认 `XCTSkip`，取证跑（`DOYAH_UI_SNAPSHOT=1`）
- 2026-11-01 · Shift 点击不靠 AppKit 的 `sortDescriptors` 认列，改由 `SortableHeaderView` 自己记那一击 · 理由：AppKit 把新列追加在后面（`first` 还是老主键），且实测 macOS 27 离屏窗口里 Shift 点击它干脆不派发 ⇒ 只靠它，多列排序静默失效 · 影响：`super` 仍要调（列宽拖动 / 换列排序），过滤条件 = 「没派发过 + 没拖动 + 不在分界线上 + 单击」
- 2026-11-01 · 表格「显示内容变了没有」从首末行摘要改成逐行比对 · 理由：取消排序回到服务端顺序时末行常与降序那份相同 ⇒ 摘要不变 ⇒ 不重载 ⇒ 界面上留着旧顺序（探针实测） · 影响：`ResultGrid.Coordinator` 每次 update 做一次 O(行数) 早退比较
