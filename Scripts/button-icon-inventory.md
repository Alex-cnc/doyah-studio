# 按钮图标化 · 逐条盘点清单（`T-20261013-042` 第一段）

- 口径：人类主人 2026-10-13 令 + 前门 18:2x 裁定 ㈠（水平按钮一律图标 / 菜单项保留文字）。
- 加令：`T-20261013-051`（范围确认「全部图标化」不缩面 + 质量硬要求：图标须有明显含义 / 同一动作同一图标 / 纯图标按钮须带提示或无障碍标签）。
- 进度：第一段盘点 **277** 处 → 第二段批 1–5 落地 223 处 → 批 6（33 处切换式按钮 + 1 处 `.labelStyle(.iconOnly)` 判据校正）⇒ a 类 **20** 处（余 = 弹框 / 内容承载 / 归属待裁）。
- 面：`App/**` + `Plugins/Notes/Views/**` + `Platform/macOS/**` 的**全部** `.swift`（**127 份**，不抽样）。
- 命令：`python3 Scripts/check-button-icon-only.py --inventory`（判定物先剥注释与字符串）。

## a 类 · 水平按钮（**必改**）· 20 处

| # | 界面 | 文件:行 | 控件 | 现行字符 | 拟用图标 | 语义依据 | 处置 |
|---|---|---|---|---|---|---|---|
| 1 | AgentAuditPanel | `App/Views/AgentAuditPanel.swift:350` | Button | `HStack(spacing: 8) { Text(AgentAuditPresentation.timestampText(record.` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 2 | AppearanceSheet | `App/Views/AppearanceSheet.swift:493` | Button | `HStack(alignment: .center, spacing: Spacing.m) { Image(systemName: isS` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 3 | AppearanceSheet | `App/Views/AppearanceSheet.swift:592` | Button | `HStack(alignment: .center, spacing: Spacing.m) { Image(systemName: isS` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 4 | DataTaskPanel | `App/Views/DataTaskPanel.swift:200` | Button | `VStack(alignment: .leading, spacing: 2) { HStack(spacing: 4) { Image(s` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 5 | ForeignKeyJumpSheet | `App/Views/ForeignKeyJumpSheet.swift:46` | Button | `HStack { Text(label(for: option)) .font(Theme.font(.body)) Spacer() if` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 6 | LowerPaneTabStrip | `App/Views/LowerPaneTabStrip.swift:108` | Button | `Text(L(QueryHistoryRemovalPrompt.actionTitleKey(action)))` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 7 | LowerPaneTabStrip | `App/Views/LowerPaneTabStrip.swift:130` | Button | `HStack(spacing: Spacing.xs) { Image(systemName: item.symbolName) .font` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 8 | QueryWorkspaceView | `App/Views/QueryWorkspaceView.swift:52` | Button | `tab.isDirty ? : tab.title` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 9 | ServerObjectsPanel | `App/Views/ServerObjectsPanel.swift:253` | Button | `HStack(alignment: .firstTextBaseline, spacing: Spacing.s) { Text(objec` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 10 | SessionPanel | `App/Views/SessionPanel.swift:119` | Button | `L(.sessionTerminateConfirm)` | `checkmark` | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 11 | SessionPanel | `App/Views/SessionPanel.swift:125` | Button | `L(.commonCancel)` | `xmark.circle` | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 12 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:313` | Button | `Label { Text(L(note.isFavorite ? .notesUnmarkFavorite : .notesMarkFavo` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 13 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:332` | Button | `Label { Text(L(note.isPinned ? .notesUnmarkPinned : .notesMarkPinned))` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 14 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:710` | Button | `Text(L(ContainerEditPrompt.confirmKey))` | `checkmark` | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 15 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:717` | Button | `Text(L(ContainerEditPrompt.cancelKey))` | `xmark.circle` | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 16 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:738` | Button | `Text(L(ContainerRemovalPrompt.titleKey(for: action, kind: request.kind` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 17 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:756` | Button | `Label { Text(L(direction.titleKey)) } icon: { Image(systemName: direct` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 18 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:776` | Button | `target.isCurrent ? target.name + L(NotebookShelfMovePrompt.currentMark` | `checkmark` | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 19 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:804` | Button | `HStack(spacing: Spacing.xs) { Image(systemName: systemImage) .font(The` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |
| 20 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:1242` | Button | `Text(L(action == .cancel ? .notesRemoveCancel : .notesDelete))` | `xmark.circle` | —（本批未落地：见 `T-20261013-042` 结果 §待裁） | 改图标 + 保留 tooltip/可访问性标签 |

## b 类 · 菜单项（**保留文字**，只盘不改）· 99 处

| # | 界面 | 文件:行 | 控件 | 现行字符 | 处置 |
|---|---|---|---|---|---|
| 1 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:47` | Button | `L(.menuFormat)` | 保留文字（可选加图标前缀） |
| 2 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:54` | Button | `L(.menuNewQuery)` | 保留文字（可选加图标前缀） |
| 3 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:62` | Button | `L(.menuNewBrowserTab)` | 保留文字（可选加图标前缀） |
| 4 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:75` | Button | `L(.menuRelaunchApp)` | 保留文字（可选加图标前缀） |
| 5 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:80` | Button | `L(.menuAboutLicense)` | 保留文字（可选加图标前缀） |
| 6 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:86` | Button | `L(.menuAccountSync)` | 保留文字（可选加图标前缀） |
| 7 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:92` | Button | `L(.archiveTitle)` | 保留文字（可选加图标前缀） |
| 8 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:100` | Button | `L(.menuImportData)` | 保留文字（可选加图标前缀） |
| 9 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:106` | Button | `L(.menuAgentSettings)` | 保留文字（可选加图标前缀） |
| 10 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:113` | Button | `L(.menuAgentGenerateSQL)` | 保留文字（可选加图标前缀） |
| 11 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:119` | Button | `L(.menuDiagnoseQuery)` | 保留文字（可选加图标前缀） |
| 12 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:124` | Button | `L(.menuMaintenanceTasks)` | 保留文字（可选加图标前缀） |
| 13 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:129` | Button | `L(.menuNotes)` | 保留文字（可选加图标前缀） |
| 14 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:134` | Button | `L(.menuMCPApprovals)` | 保留文字（可选加图标前缀） |
| 15 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:140` | Button | `L(.menuDataTask)` | 保留文字（可选加图标前缀） |
| 16 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:147` | Button | `L(.menuAgentAudit)` | 保留文字（可选加图标前缀） |
| 17 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:152` | Button | `L(.menuEgressLog)` | 保留文字（可选加图标前缀） |
| 18 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:174` | Button | `command.title` | 保留文字（可选加图标前缀） |
| 19 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:186` | Button | `L(item.menuKey)` | 保留文字（可选加图标前缀） |
| 20 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:201` | Button | `L(.menuAppearance)` | 保留文字（可选加图标前缀） |
| 21 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:205` | Button | `L(.menuConnectionSettings)` | 保留文字（可选加图标前缀） |
| 22 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:209` | Button | `L(.databaseStatsTitle)` | 保留文字（可选加图标前缀） |
| 23 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:215` | Button | `L(.menuServerObjects)` | 保留文字（可选加图标前缀） |
| 24 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:219` | Button | `L(.schemaDiffTitle)` | 保留文字（可选加图标前缀） |
| 25 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:223` | Button | `L(.menuERDiagram)` | 保留文字（可选加图标前缀） |
| 26 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:229` | Button | `L(.lowerPaneToggle)` | 保留文字（可选加图标前缀） |
| 27 | DoyahStudioCommands | `App/DoyahStudioCommands.swift:239` | Toggle | `language.displayName` | 保留文字（可选加图标前缀） |
| 28 | AgentAuditPanel | `App/Views/AgentAuditPanel.swift:94` | Button | `format.text` | 保留文字（可选加图标前缀） |
| 29 | AgentSettingsSheet | `App/Views/AgentSettingsSheet.swift:61` | Button | `name` | 保留文字（可选加图标前缀） |
| 30 | ConnectionListView | `App/Views/ConnectionListView.swift:47` | Button | `L(.commonEdit)` | 保留文字（可选加图标前缀） |
| 31 | ConnectionListView | `App/Views/ConnectionListView.swift:50` | Button | `L(.commonDelete)` | 保留文字（可选加图标前缀） |
| 32 | DataTaskPanel | `App/Views/DataTaskPanel.swift:451` | Button | `bookmark.displayName` | 保留文字（可选加图标前缀） |
| 33 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:122` | Button | `L(.tableDesignTitle)` | 保留文字（可选加图标前缀） |
| 34 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:130` | Button | `L(.treeActionBrowseRows, ObjectTreeActions.defaultBrowseLimit)` | 保留文字（可选加图标前缀） |
| 35 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:136` | Button | `L(.treeActionSelectTemplate)` | 保留文字（可选加图标前缀） |
| 36 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:142` | Button | `L(.treeActionInsertTemplate)` | 保留文字（可选加图标前缀） |
| 37 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:148` | Button | `L(.treeActionCopyQualifiedName)` | 保留文字（可选加图标前缀） |
| 38 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:154` | Button | `L(.treeActionCopyColumnName)` | 保留文字（可选加图标前缀） |
| 39 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:160` | Button | `L(.treeActionBrowseWithCondition)` | 保留文字（可选加图标前缀） |
| 40 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:169` | Button | `L(.syntheticGenerate) +` | 保留文字（可选加图标前缀） |
| 41 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:178` | Button | `L(.treeActionViewDDL)` | 保留文字（可选加图标前缀） |
| 42 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:188` | Button | `L(.tableDesignAlterTitle)` | 保留文字（可选加图标前缀） |
| 43 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:193` | Button | `L(.treeActionTruncate)` | 保留文字（可选加图标前缀） |
| 44 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:199` | Button | `L(.treeActionDrop)` | 保留文字（可选加图标前缀） |
| 45 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:226` | Button | `L(.objectTreeMenuConnect)` | 保留文字（可选加图标前缀） |
| 46 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:231` | Button | `L(.objectTreeMenuDisconnect)` | 保留文字（可选加图标前缀） |
| 47 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:238` | Button | `L(.objectTreeMenuEditConnection)` | 保留文字（可选加图标前缀） |
| 48 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:248` | Button | `L(.objectTreeMenuDatabaseProperties)` | 保留文字（可选加图标前缀） |
| 49 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:253` | Button | `L(.objectTreeMenuDropDatabase)` | 保留文字（可选加图标前缀） |
| 50 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:261` | Button | `L(.objectTreeMenuPrivileges)` | 保留文字（可选加图标前缀） |
| 51 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:266` | Button | `L(.objectTreeMenuLocks)` | 保留文字（可选加图标前缀） |
| 52 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:273` | Button | `L(.sessionTitle) +` | 保留文字（可选加图标前缀） |
| 53 | ObjectTreeContextMenu | `App/Views/ObjectTreeContextMenu.swift:284` | Button | `L(.objectTreeMenuCreateDatabase)` | 保留文字（可选加图标前缀） |
| 54 | QueryToolbar | `App/Views/QueryToolbar.swift:100` | Button | `Text(historyLabel(for: entry))` | 保留文字（可选加图标前缀） |
| 55 | QueryToolbar | `App/Views/QueryToolbar.swift:110` | Button | `L(.historyClear)` | 保留文字（可选加图标前缀） |
| 56 | QueryToolbar | `App/Views/QueryToolbar.swift:144` | Toggle | `L(.safetySafeMode)` | 保留文字（可选加图标前缀） |
| 57 | QueryToolbar | `App/Views/QueryToolbar.swift:147` | Toggle | `L(.safetyConfirmAllWrites)` | 保留文字（可选加图标前缀） |
| 58 | QueryToolbar | `App/Views/QueryToolbar.swift:190` | Button | `L(.toolbarSaveAs)` | 保留文字（可选加图标前缀） |
| 59 | QueryToolbar | `App/Views/QueryToolbar.swift:209` | Button | `L(.editMenuFind)` | 保留文字（可选加图标前缀） |
| 60 | QueryToolbar | `App/Views/QueryToolbar.swift:214` | Button | `L(.editMenuReplace)` | 保留文字（可选加图标前缀） |
| 61 | QueryToolbar | `App/Views/QueryToolbar.swift:221` | Button | `L(.editMenuGoToLine)` | 保留文字（可选加图标前缀） |
| 62 | QueryToolbar | `App/Views/QueryToolbar.swift:228` | Button | `L(.editMenuIndent)` | 保留文字（可选加图标前缀） |
| 63 | QueryToolbar | `App/Views/QueryToolbar.swift:233` | Button | `L(.editMenuOutdent)` | 保留文字（可选加图标前缀） |
| 64 | QueryToolbar | `App/Views/QueryToolbar.swift:240` | Button | `L(.editMenuClear)` | 保留文字（可选加图标前缀） |
| 65 | QueryToolbar | `App/Views/QueryToolbar.swift:245` | Button | `L(.editMenuFormat)` | 保留文字（可选加图标前缀） |
| 66 | QueryToolbar | `App/Views/QueryToolbar.swift:253` | Button | `L(.editMenuSelectNextOccurrence)` | 保留文字（可选加图标前缀） |
| 67 | QueryToolbar | `App/Views/QueryToolbar.swift:261` | Button | `L(.editMenuAddCursorAbove)` | 保留文字（可选加图标前缀） |
| 68 | QueryToolbar | `App/Views/QueryToolbar.swift:266` | Button | `L(.editMenuAddCursorBelow)` | 保留文字（可选加图标前缀） |
| 69 | QueryToolbar | `App/Views/QueryToolbar.swift:315` | Button | `Text(query.name)` | 保留文字（可选加图标前缀） |
| 70 | QueryToolbar | `App/Views/QueryToolbar.swift:326` | Button | `query.name` | 保留文字（可选加图标前缀） |
| 71 | ResultClientViewBar | `App/Views/ResultClientViewBar.swift:126` | Button | `meta.name` | 保留文字（可选加图标前缀） |
| 72 | ResultClientViewBar | `App/Views/ResultClientViewBar.swift:140` | Button | `filterOperatorLabel(op)` | 保留文字（可选加图标前缀） |
| 73 | ResultTableView | `App/Views/ResultTableView.swift:282` | Button | `L(.exportCSV)` | 保留文字（可选加图标前缀） |
| 74 | ResultTableView | `App/Views/ResultTableView.swift:283` | Button | `L(.exportCSVGB18030)` | 保留文字（可选加图标前缀） |
| 75 | ResultTableView | `App/Views/ResultTableView.swift:284` | Button | `L(.exportJSON)` | 保留文字（可选加图标前缀） |
| 76 | ResultTableView | `App/Views/ResultTableView.swift:285` | Button | `L(.exportXLSX)` | 保留文字（可选加图标前缀） |
| 77 | ResultTableView | `App/Views/ResultTableView.swift:287` | Button | `L(.exportTSV)` | 保留文字（可选加图标前缀） |
| 78 | ResultTableView | `App/Views/ResultTableView.swift:288` | Button | `L(.exportMarkdown)` | 保留文字（可选加图标前缀） |
| 79 | ResultTableView | `App/Views/ResultTableView.swift:289` | Button | `L(.exportSQLInsert)` | 保留文字（可选加图标前缀） |
| 80 | TableDesignExtrasSection | `App/Views/TableDesignExtrasSection.swift:247` | Button | `L(.referentialActionNone)` | 保留文字（可选加图标前缀） |
| 81 | TableDesignExtrasSection | `App/Views/TableDesignExtrasSection.swift:249` | Button | `ForeignKeyDraft.labelKey(action)` | 保留文字（可选加图标前缀） |
| 82 | TerminalTabsBar | `App/Views/TerminalTabsBar.swift:82` | Button | `L(.terminalTabRename)` | 保留文字（可选加图标前缀） |
| 83 | TerminalTabsBar | `App/Views/TerminalTabsBar.swift:83` | Button | `L(.terminalTabClose)` | 保留文字（可选加图标前缀） |
| 84 | TodoCalendarView | `App/Views/TodoCalendarView.swift:439` | Button | `L(.commonEdit)` | 保留文字（可选加图标前缀） |
| 85 | TodoCalendarView | `App/Views/TodoCalendarView.swift:443` | Button | `L(todo.done ? .todoMarkOpen : .todoMarkDone)` | 保留文字（可选加图标前缀） |
| 86 | TodoCalendarView | `App/Views/TodoCalendarView.swift:446` | Button | `L(.todoReschedule)` | 保留文字（可选加图标前缀） |
| 87 | TodoCalendarView | `App/Views/TodoCalendarView.swift:452` | Button | `L(.todoDelete)` | 保留文字（可选加图标前缀） |
| 88 | WorkspaceExplorerView | `App/Views/WorkspaceExplorerView.swift:217` | Button | `L(.workspaceReveal)` | 保留文字（可选加图标前缀） |
| 89 | WorkspaceExplorerView | `App/Views/WorkspaceExplorerView.swift:267` | Button | `L(.workspaceNewFile)` | 保留文字（可选加图标前缀） |
| 90 | WorkspaceExplorerView | `App/Views/WorkspaceExplorerView.swift:268` | Button | `L(.workspaceNewFolder)` | 保留文字（可选加图标前缀） |
| 91 | WorkspaceTabStrip | `App/Views/WorkspaceTabStrip.swift:123` | Button | `L(.workspaceFormatMenuItem, AppShortcut.formatCode.display)` | 保留文字（可选加图标前缀） |
| 92 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:362` | Button | `moveLabel(for: target)` | 保留文字（可选加图标前缀） |
| 93 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:372` | Button | `Label { Text(L(NotebookMovePrompt.noTargetKey)) } icon: { Image(system` | 保留文字（可选加图标前缀） |
| 94 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:542` | Button | `Label { Text(L(NotebookCreation.menuTitleKey)) } icon: { Image(systemN` | 保留文字（可选加图标前缀） |
| 95 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:553` | Button | `Label { Text(L(ContainerEditPrompt.menuTitleKey)) } icon: { Image(syst` | 保留文字（可选加图标前缀） |
| 96 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:569` | Button | `Label { Text(L(ContainerRemovalPrompt.menuTitleKey(for: .shelf))) } ic` | 保留文字（可选加图标前缀） |
| 97 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:591` | Button | `Label { Text(L(ContainerEditPrompt.menuTitleKey)) } icon: { Image(syst` | 保留文字（可选加图标前缀） |
| 98 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:615` | Button | `Label { Text(L(NotebookShelfMovePrompt.noTargetKey)) } icon: { Image(s` | 保留文字（可选加图标前缀） |
| 99 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:631` | Button | `Label { Text(L(ContainerRemovalPrompt.menuTitleKey(for: .notebook))) }` | 保留文字（可选加图标前缀） |

## 已合格 · 已是纯图标按钮 · 108 处

- `App/Views/AccountSyncSheet.swift:268`
- `App/Views/ActivityBarView.swift:68`
- `App/Views/ActivityBarView.swift:110`
- `App/Views/AgentAuditPanel.swift:186`
- `App/Views/AgentAuditPanel.swift:204`
- `App/Views/AgentChatView.swift:90`
- `App/Views/AgentSQLPanel.swift:95`
- `App/Views/AgentSQLPanel.swift:100`
- `App/Views/AgentSettingsSheet.swift:36`
- `App/Views/AgentSettingsSheet.swift:86`
- `App/Views/AppearanceSheet.swift:291`
- `App/Views/AppearanceSheet.swift:373`
- `App/Views/BackupRestoreSheet.swift:194`
- `App/Views/BrowserTabView.swift:48`
- `App/Views/BrowserTabView.swift:58`
- `App/Views/BrowserTabView.swift:68`
- `App/Views/ConnectionFormView.swift:267`
- `App/Views/ConnectionFormView.swift:343`
- `App/Views/ConnectionFormView.swift:409`
- `App/Views/ConnectionSettingsSheet.swift:47`
- `App/Views/DataTaskPanel.swift:170`
- `App/Views/DataTaskPanel.swift:342`
- `App/Views/DataTaskPanel.swift:409`
- `App/Views/DataTaskSpecSheet.swift:48`
- `App/Views/ERDiagramPanel.swift:288`
- `App/Views/ERDiagramPanel.swift:292`
- `App/Views/ExecutionPlanPanel.swift:67`
- `App/Views/ExecutionPlanPanel.swift:73`
- `App/Views/ExecutionPlanPanel.swift:79`
- `App/Views/ImportPanel.swift:167`
- `App/Views/LowerPaneTabStrip.swift:170`
- `App/Views/LowerPaneView.swift:246`
- `App/Views/LowerPaneView.swift:257`
- `App/Views/LowerPaneView.swift:322`
- `App/Views/MaintenancePanel.swift:77`
- `App/Views/ObjectTreeRowContent.swift:45`
- `App/Views/ObjectTreeToolbar.swift:48`
- `App/Views/ObjectTreeToolbar.swift:56`
- `App/Views/PrivilegePanel.swift:188`
- `App/Views/QueryToolbar.swift:180`
- …… 共 108 处（余 68 处）

## 存疑（登记待裁）· 2 处

- `App/Views/WorkspaceAreaView.swift:224` Button：`homeRow(title: entry.displayName, detail: entry.path, symbol: )`
- `App/Views/WorkspaceAreaView.swift:247` Button：`homeRow(title: entry.displayName, detail: entry.path, symbol: )`

## 附录 · 非按钮控件 `Picker`（归口待裁）· 49 处

- `App/Views/AccountSyncSheet.swift:137` ``
- `App/Views/AgentAuditPanel.swift:270` ``
- `App/Views/AgentAuditPanel.swift:279` ``
- `App/Views/AgentSettingsSheet.swift:49` `L(.agentProvider)`
- `App/Views/AppearanceSheet.swift:93` ``
- `App/Views/AppearanceSheet.swift:121` `L(.appearanceMonoFamily)`
- `App/Views/AppearanceSheet.swift:343` ``
- `App/Views/AppearanceSheet.swift:366` ``
- `App/Views/BackupRestoreSheet.swift:64` ``
- `App/Views/BackupRestoreSheet.swift:73` `L(.backupRestoreFormat)`
- `App/Views/BackupRestoreSheet.swift:182` ``
- `App/Views/ConnectionDialectSection.swift:72` `L(.connectionFormDbType)`
- `App/Views/ConnectionDialectSection.swift:100` `L(.connectionFormSSLMode)`
- `App/Views/ConnectionFormView.swift:233` ``
- `App/Views/ConnectionFormView.swift:247` ``
- `App/Views/ConnectionFormView.swift:392` ``
- `App/Views/ConnectionFormView.swift:439` ``
- `App/Views/DataTaskPanel.swift:327` ``
- `App/Views/DataTaskPanel.swift:374` ``
- `App/Views/DataTaskPanel.swift:401` ``
- `App/Views/DataTaskPanel.swift:437` ``
- `App/Views/DataTaskVersionSheet.swift:153` ``
- `App/Views/DatabasePropertiesSheet.swift:42` `L(.dbPropsAllowConnections)`
- `App/Views/EgressLogSheet.swift:68` ``
- `App/Views/EgressLogSheet.swift:77` ``
- `App/Views/EgressLogSheet.swift:88` ``
- `App/Views/ImportPanel.swift:158` ``
- `App/Views/ImportPanel.swift:182` ``
- `App/Views/ImportPanel.swift:315` ``
- `App/Views/ObjectTreeToolbar.swift:36` ``
- `App/Views/PrivilegePanel.swift:162` `L(.privilegeObjectKind)`
- `App/Views/QueryContextBar.swift:19` `L(.contextServer)`
- `App/Views/QueryContextBar.swift:49` `L(.contextDatabase)`
- `App/Views/QueryParameterSheet.swift:103` ``
- `App/Views/ResultPagerBar.swift:25` ``
- `App/Views/ResultTableView.swift:244` ``
- `App/Views/RoutineCandidatesPanel.swift:62` ``
- `App/Views/RoutineCandidatesPanel.swift:343` ``
- `App/Views/SchemaDiffPanel.swift:109` ``
- `App/Views/ServerObjectsPanel.swift:152` ``
- `App/Views/TodoCalendarView.swift:41` `L(.notesModuleTodos)`
- `App/Views/TodoCalendarView.swift:96` `L(.todoPaneCalendar)`
- `App/Views/TodoCalendarView.swift:564` `L(.todoFilterLabel)`
- `App/Views/TodoCalendarView.swift:591` `L(.todoSortLabel)`
- `App/Views/TodoCalendarView.swift:602` `L(.todoGroupLabel)`
- `Plugins/Notes/Views/NotesPanel.swift:244` `L(.notesSortBy)`
- `Plugins/Notes/Views/NotesPanel.swift:1369` `L(.notesSearchScopeTitle)`
- `Plugins/Notes/Views/NotesPanel.swift:1878` `L(.todoPriorityLabel)`
- `Plugins/Notes/Views/NotesPanel.swift:2009` `L(.reminderSection)`

## 空串按钮（豁免：无可见文案）· 4 处

- `App/Views/MainWindow.swift:266`
- `App/Views/TableDesignExtrasSection.swift:156`
- `App/Views/TableDesignSheet.swift:190`
- `App/Views/TableDesignSheet.swift:194`
