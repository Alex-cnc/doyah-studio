# 按钮图标化 · 逐条盘点清单（`T-20261013-042` 第一段）

- 口径：人类主人 2026-10-13 令 + 前门 18:2x 裁定 ㈠（水平按钮一律图标 / 菜单项保留文字）。
- 面：`App/**` + `Plugins/Notes/Views/**` + `Platform/macOS/**` 的**全部** `.swift`（**127 份**，不抽样）。
- 命令：`python3 Scripts/check-button-icon-only.py --inventory`（判定物先剥注释与字符串）。

## a 类 · 水平按钮（**必改**）· 82 处

| # | 界面 | 文件:行 | 控件 | 现行字符 | 拟用图标 | 处置 |
|---|---|---|---|---|---|---|
| 1 | AccountSyncSheet | `App/Views/AccountSyncSheet.swift:126` | Button | `L(.accountSignOutAction)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 2 | AccountSyncSheet | `App/Views/AccountSyncSheet.swift:162` | Button | `L(.accountSignInAction)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 3 | AccountSyncSheet | `App/Views/AccountSyncSheet.swift:219` | Button | `L(.accountSignUpAction)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 4 | AccountSyncSheet | `App/Views/AccountSyncSheet.swift:268` | Toggle | `L(.accountSyncToggle)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 5 | AccountSyncSheet | `App/Views/AccountSyncSheet.swift:295` | Button | `L(.accountRecoveryEntry)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 6 | AgentAuditPanel | `App/Views/AgentAuditPanel.swift:166` | Button | `L(.agentApprovalReview)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 7 | AgentAuditPanel | `App/Views/AgentAuditPanel.swift:186` | Toggle | `L(.agentReadOnlyMode)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 8 | AgentAuditPanel | `App/Views/AgentAuditPanel.swift:200` | Toggle | `kind.text` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 9 | AgentAuditPanel | `App/Views/AgentAuditPanel.swift:342` | Button | `HStack(spacing: 8) { Text(AgentAuditPresentation.timestampText(record.` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 10 | AgentSQLPanel | `App/Views/AgentSQLPanel.swift:57` | Button | `L(.agentSQLSubmit)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 11 | AgentSQLPanel | `App/Views/AgentSQLPanel.swift:95` | Toggle | `L(.agentSQLIncludeTables)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 12 | AgentSQLPanel | `App/Views/AgentSQLPanel.swift:96` | Toggle | `L(.agentSQLIncludeStatement)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 13 | AgentSettingsSheet | `App/Views/AgentSettingsSheet.swift:36` | Toggle | `L(.agentEnabled)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 14 | AgentSettingsSheet | `App/Views/AgentSettingsSheet.swift:82` | Toggle | `L(.agentAPIKeyClear)` | `xmark.bin` | 改图标 + 保留 tooltip/可访问性标签 |
| 15 | AppearanceSheet | `App/Views/AppearanceSheet.swift:291` | Toggle | `L(.appearanceNebulaSkin)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 16 | AppearanceSheet | `App/Views/AppearanceSheet.swift:369` | Toggle | `L(.terminalCursorBlink)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 17 | AppearanceSheet | `App/Views/AppearanceSheet.swift:485` | Button | `HStack(alignment: .center, spacing: Spacing.m) { Image(systemName: isS` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 18 | AppearanceSheet | `App/Views/AppearanceSheet.swift:584` | Button | `HStack(alignment: .center, spacing: Spacing.m) { Image(systemName: isS` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 19 | BackupRestoreSheet | `App/Views/BackupRestoreSheet.swift:194` | Toggle | `L(.backupRestoreClean)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 20 | ConnectionFormView | `App/Views/ConnectionFormView.swift:267` | Toggle | `L(.connectionFormReadOnly)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 21 | ConnectionFormView | `App/Views/ConnectionFormView.swift:339` | Toggle | `L(.sshEnableLabel)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 22 | ConnectionFormView | `App/Views/ConnectionFormView.swift:401` | Toggle | `L(.sshKeyEncryptedLabel)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 23 | ConnectionSettingsSheet | `App/Views/ConnectionSettingsSheet.swift:47` | Toggle | `L(.connectionSettingsKeepAliveToggle)` | `gearshape` | 改图标 + 保留 tooltip/可访问性标签 |
| 24 | DataTaskPanel | `App/Views/DataTaskPanel.swift:170` | Toggle | `L(.dataTaskOnlyEnabled)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 25 | DataTaskPanel | `App/Views/DataTaskPanel.swift:196` | Button | `VStack(alignment: .leading, spacing: 2) { HStack(spacing: 4) { Image(s` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 26 | DataTaskPanel | `App/Views/DataTaskPanel.swift:405` | Toggle | `L(.dataTaskEnabled)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 27 | DataTaskPanel | `App/Views/DataTaskPanel.swift:714` | Button | `stored.isEnabled ? L(.dataTaskDisable) : L(.dataTaskEnable)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 28 | DataTaskSpecSheet | `App/Views/DataTaskSpecSheet.swift:48` | Toggle | `L(.agentSQLIncludeTables)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 29 | DiagnosisPanel | `App/Views/DiagnosisPanel.swift:110` | Button | `appState.diagnosisIsGathering ? L(.diagnosisGathering) : L(.diagnosisG` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 30 | DiagnosisPanel | `App/Views/DiagnosisPanel.swift:222` | Button | `L(.diagnosisParse)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 31 | ExecutionPlanPanel | `App/Views/ExecutionPlanPanel.swift:67` | Toggle | `L(.planAnalyze)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 32 | ExecutionPlanPanel | `App/Views/ExecutionPlanPanel.swift:69` | Toggle | `L(.planBuffers)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 33 | ExecutionPlanPanel | `App/Views/ExecutionPlanPanel.swift:71` | Toggle | `L(.planFormatJSON)` | `text.alignleft` | 改图标 + 保留 tooltip/可访问性标签 |
| 34 | ForeignKeyJumpSheet | `App/Views/ForeignKeyJumpSheet.swift:46` | Button | `HStack { Text(label(for: option)) .font(Theme.font(.body)) Spacer() if` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 35 | ImportPanel | `App/Views/ImportPanel.swift:167` | Toggle | `L(.importHasHeader)` | `square.and.arrow.down` | 改图标 + 保留 tooltip/可访问性标签 |
| 36 | LockPanel | `App/Views/LockPanel.swift:139` | Button | `L(.lockShowBlocker)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 37 | LowerPaneTabStrip | `App/Views/LowerPaneTabStrip.swift:108` | Button | `Text(L(QueryHistoryRemovalPrompt.actionTitleKey(action)))` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 38 | LowerPaneTabStrip | `App/Views/LowerPaneTabStrip.swift:130` | Button | `HStack(spacing: Spacing.xs) { Image(systemName: item.symbolName) .font` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 39 | MaintenancePanel | `App/Views/MaintenancePanel.swift:77` | Toggle | `L(.maintenanceAllowMultiple)` | `checkmark.circle` | 改图标 + 保留 tooltip/可访问性标签 |
| 40 | MaintenancePanel | `App/Views/MaintenancePanel.swift:198` | Button | `L(.maintenanceReviewAction)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 41 | PrivilegePanel | `App/Views/PrivilegePanel.swift:104` | Button | `L(.privilegeLoad)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 42 | PrivilegePanel | `App/Views/PrivilegePanel.swift:188` | Toggle | `L(.privilegeWithGrantOption)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 43 | PrivilegePanel | `App/Views/PrivilegePanel.swift:201` | Button | `L(.privilegeGrant)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 44 | QueryWorkspaceView | `App/Views/QueryWorkspaceView.swift:52` | Button | `tab.isDirty ? : tab.title` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 45 | RelaunchPromptSheet | `App/Views/RelaunchPromptSheet.swift:32` | Button | `L(.relaunchLater)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 46 | RelaunchPromptSheet | `App/Views/RelaunchPromptSheet.swift:37` | Button | `L(.relaunchNow)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 47 | ResultTableView | `App/Views/ResultTableView.swift:261` | Toggle | `Label(L(.commonEdit), systemImage: )` | `pencil` | 改图标 + 保留 tooltip/可访问性标签 |
| 48 | ResultTableView | `App/Views/ResultTableView.swift:271` | Toggle | `Label(L(.rowDetailTitle), systemImage: )` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 49 | RoutineCandidatesPanel | `App/Views/RoutineCandidatesPanel.swift:275` | Toggle | `L(.memoryGovernanceRecordingToggle)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 50 | SQLArchiveSheet | `App/Views/SQLArchiveSheet.swift:19` | Toggle | `L(.archiveEnable)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 51 | SchemaDiffPanel | `App/Views/SchemaDiffPanel.swift:86` | Toggle | `L(.schemaDiffAllowDrop)` | `trash` | 改图标 + 保留 tooltip/可访问性标签 |
| 52 | SchemaDiffPanel | `App/Views/SchemaDiffPanel.swift:251` | Button | `L(.schemaDiffCompare)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 53 | ServerObjectsPanel | `App/Views/ServerObjectsPanel.swift:253` | Button | `HStack(alignment: .firstTextBaseline, spacing: Spacing.s) { Text(objec` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 54 | ServerObjectsPanel | `App/Views/ServerObjectsPanel.swift:322` | Toggle | `L(.serverObjectsCanLogin)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 55 | ServerObjectsPanel | `App/Views/ServerObjectsPanel.swift:323` | Toggle | `L(.serverObjectsSuperuser)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 56 | SessionPanel | `App/Views/SessionPanel.swift:46` | Button | `Label(L(.sessionRefresh), systemImage: )` | `arrow.clockwise` | 改图标 + 保留 tooltip/可访问性标签 |
| 57 | SessionPanel | `App/Views/SessionPanel.swift:97` | Button | `L(.sessionTerminate)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 58 | SessionPanel | `App/Views/SessionPanel.swift:121` | Button | `L(.sessionTerminateConfirm)` | `checkmark` | 改图标 + 保留 tooltip/可访问性标签 |
| 59 | SessionPanel | `App/Views/SessionPanel.swift:127` | Button | `L(.commonCancel)` | `xmark.circle` | 改图标 + 保留 tooltip/可访问性标签 |
| 60 | SyntheticDataPanel | `App/Views/SyntheticDataPanel.swift:93` | Toggle | `L(.syntheticOverwrite)` | `square.and.pencil` | 改图标 + 保留 tooltip/可访问性标签 |
| 61 | TableDesignExtrasSection | `App/Views/TableDesignExtrasSection.swift:84` | Button | `Label(L(.tableDesignAddConstraint), systemImage: )` | `plus` | 改图标 + 保留 tooltip/可访问性标签 |
| 62 | TableDesignExtrasSection | `App/Views/TableDesignExtrasSection.swift:90` | Button | `Label(L(.tableDesignAddForeignKey), systemImage: )` | `plus` | 改图标 + 保留 tooltip/可访问性标签 |
| 63 | TableDesignExtrasSection | `App/Views/TableDesignExtrasSection.swift:132` | Button | `Label(L(.tableDesignAddIndex), systemImage: )` | `plus` | 改图标 + 保留 tooltip/可访问性标签 |
| 64 | TableDesignExtrasSection | `App/Views/TableDesignExtrasSection.swift:198` | Toggle | `L(.tableDesignIndexUnique)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 65 | TransactionControl | `App/Views/TransactionControl.swift:64` | Button | `if current == target { Label(title, systemImage: ) } else { Text(title` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 66 | WorkspaceAreaView | `App/Views/WorkspaceAreaView.swift:108` | Button | `Label( L(.workspacePreviewToggle), systemImage: tabs.previewVisible ? ` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 67 | WorkspaceAreaView | `App/Views/WorkspaceAreaView.swift:207` | Button | `Label(L(.workspaceOpenFileButton), systemImage: )` | `arrow.up.forward.app` | 改图标 + 保留 tooltip/可访问性标签 |
| 68 | WorkspaceAreaView | `App/Views/WorkspaceAreaView.swift:214` | Button | `Label(L(.workspaceChooseFolderButton), systemImage: )` | `folder` | 改图标 + 保留 tooltip/可访问性标签 |
| 69 | WorkspaceHeaderSearch | `App/Views/WorkspaceHeaderSearch.swift:202` | Button | `L(.workspaceReplaceAll)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 70 | WorkspaceHeaderSearch | `App/Views/WorkspaceHeaderSearch.swift:278` | Button | `L(.commandReplace)` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 71 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:227` | Toggle | `Label(L(.notesFavoriteOnly), systemImage: ) .labelStyle(.iconOnly) .fo` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 72 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:313` | Button | `Label { Text(L(note.isFavorite ? .notesUnmarkFavorite : .notesMarkFavo` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 73 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:332` | Button | `Label { Text(L(note.isPinned ? .notesUnmarkPinned : .notesMarkPinned))` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 74 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:472` | Button | `HStack(spacing: Spacing.xs) { Image(systemName: ) Text(L(NotebookCreat` | `checkmark` | 改图标 + 保留 tooltip/可访问性标签 |
| 75 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:714` | Button | `Text(L(ContainerEditPrompt.confirmKey))` | `checkmark` | 改图标 + 保留 tooltip/可访问性标签 |
| 76 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:721` | Button | `Text(L(ContainerEditPrompt.cancelKey))` | `xmark.circle` | 改图标 + 保留 tooltip/可访问性标签 |
| 77 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:742` | Button | `Text(L(ContainerRemovalPrompt.titleKey(for: action, kind: request.kind` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 78 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:760` | Button | `Label { Text(L(direction.titleKey)) } icon: { Image(systemName: direct` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 79 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:780` | Button | `target.isCurrent ? target.name + L(NotebookShelfMovePrompt.currentMark` | `checkmark` | 改图标 + 保留 tooltip/可访问性标签 |
| 80 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:808` | Button | `HStack(spacing: Spacing.xs) { Image(systemName: systemImage) .font(The` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |
| 81 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:1246` | Button | `Text(L(action == .cancel ? .notesRemoveCancel : .notesDelete))` | `xmark.circle` | 改图标 + 保留 tooltip/可访问性标签 |
| 82 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:1866` | Toggle | `Text(L(.todoHasDueLabel)) .font(Theme.font(.caption))` | **待定**（口径未定：语义近似的 SF Symbol 有多枚，需设计一句话） | 改图标 + 保留 tooltip/可访问性标签 |

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
| 29 | AgentSettingsSheet | `App/Views/AgentSettingsSheet.swift:57` | Button | `name` | 保留文字（可选加图标前缀） |
| 30 | ConnectionListView | `App/Views/ConnectionListView.swift:47` | Button | `L(.commonEdit)` | 保留文字（可选加图标前缀） |
| 31 | ConnectionListView | `App/Views/ConnectionListView.swift:50` | Button | `L(.commonDelete)` | 保留文字（可选加图标前缀） |
| 32 | DataTaskPanel | `App/Views/DataTaskPanel.swift:443` | Button | `bookmark.displayName` | 保留文字（可选加图标前缀） |
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
| 73 | ResultTableView | `App/Views/ResultTableView.swift:280` | Button | `L(.exportCSV)` | 保留文字（可选加图标前缀） |
| 74 | ResultTableView | `App/Views/ResultTableView.swift:281` | Button | `L(.exportCSVGB18030)` | 保留文字（可选加图标前缀） |
| 75 | ResultTableView | `App/Views/ResultTableView.swift:282` | Button | `L(.exportJSON)` | 保留文字（可选加图标前缀） |
| 76 | ResultTableView | `App/Views/ResultTableView.swift:283` | Button | `L(.exportXLSX)` | 保留文字（可选加图标前缀） |
| 77 | ResultTableView | `App/Views/ResultTableView.swift:285` | Button | `L(.exportTSV)` | 保留文字（可选加图标前缀） |
| 78 | ResultTableView | `App/Views/ResultTableView.swift:286` | Button | `L(.exportMarkdown)` | 保留文字（可选加图标前缀） |
| 79 | ResultTableView | `App/Views/ResultTableView.swift:287` | Button | `L(.exportSQLInsert)` | 保留文字（可选加图标前缀） |
| 80 | TableDesignExtrasSection | `App/Views/TableDesignExtrasSection.swift:240` | Button | `L(.referentialActionNone)` | 保留文字（可选加图标前缀） |
| 81 | TableDesignExtrasSection | `App/Views/TableDesignExtrasSection.swift:242` | Button | `ForeignKeyDraft.labelKey(action)` | 保留文字（可选加图标前缀） |
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
| 94 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:546` | Button | `Label { Text(L(NotebookCreation.menuTitleKey)) } icon: { Image(systemN` | 保留文字（可选加图标前缀） |
| 95 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:557` | Button | `Label { Text(L(ContainerEditPrompt.menuTitleKey)) } icon: { Image(syst` | 保留文字（可选加图标前缀） |
| 96 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:573` | Button | `Label { Text(L(ContainerRemovalPrompt.menuTitleKey(for: .shelf))) } ic` | 保留文字（可选加图标前缀） |
| 97 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:595` | Button | `Label { Text(L(ContainerEditPrompt.menuTitleKey)) } icon: { Image(syst` | 保留文字（可选加图标前缀） |
| 98 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:619` | Button | `Label { Text(L(NotebookShelfMovePrompt.noTargetKey)) } icon: { Image(s` | 保留文字（可选加图标前缀） |
| 99 | NotesPanel | `Plugins/Notes/Views/NotesPanel.swift:635` | Button | `Label { Text(L(ContainerRemovalPrompt.menuTitleKey(for: .notebook))) }` | 保留文字（可选加图标前缀） |

## 已合格 · 已是纯图标按钮 · 67 处

- `App/Views/ActivityBarView.swift:68`
- `App/Views/ActivityBarView.swift:110`
- `App/Views/AgentChatView.swift:90`
- `App/Views/BrowserTabView.swift:48`
- `App/Views/BrowserTabView.swift:58`
- `App/Views/BrowserTabView.swift:68`
- `App/Views/DataTaskPanel.swift:338`
- `App/Views/ERDiagramPanel.swift:288`
- `App/Views/ERDiagramPanel.swift:292`
- `App/Views/LowerPaneTabStrip.swift:170`
- `App/Views/LowerPaneView.swift:246`
- `App/Views/LowerPaneView.swift:257`
- `App/Views/LowerPaneView.swift:322`
- `App/Views/ObjectTreeRowContent.swift:45`
- `App/Views/ObjectTreeToolbar.swift:48`
- `App/Views/ObjectTreeToolbar.swift:56`
- `App/Views/QueryToolbar.swift:180`
- `App/Views/QueryToolbar.swift:279`
- `App/Views/QueryToolbar.swift:298`
- `App/Views/QueryToolbar.swift:347`
- `App/Views/QueryToolbar.swift:363`
- `App/Views/QueryToolbar.swift:381`
- `App/Views/QueryToolbar.swift:396`
- `App/Views/QueryWorkspaceView.swift:62`
- `App/Views/QueryWorkspaceView.swift:79`
- `App/Views/ResultClientViewBar.swift:35`
- `App/Views/ResultClientViewBar.swift:52`
- `App/Views/ResultClientViewBar.swift:98`
- `App/Views/ResultClientViewBar.swift:168`
- `App/Views/ResultClientViewBar.swift:182`
- `App/Views/ResultPagerBar.swift:39`
- `App/Views/ResultPagerBar.swift:48`
- `App/Views/ResultPagerBar.swift:62`
- `App/Views/ResultPagerBar.swift:71`
- `App/Views/RowDetailPanel.swift:202`
- `App/Views/TableDesignExtrasSection.swift:202`
- `App/Views/TableDesignExtrasSection.swift:226`
- `App/Views/TableDesignExtrasSection.swift:257`
- `App/Views/TableDesignSheet.swift:201`
- `App/Views/TerminalSubToolbar.swift:85`
- …… 共 67 处（余 27 处）

## 存疑（登记待裁）· 2 处

- `App/Views/WorkspaceAreaView.swift:225` Button：`homeRow(title: entry.displayName, detail: entry.path, symbol: )`
- `App/Views/WorkspaceAreaView.swift:248` Button：`homeRow(title: entry.displayName, detail: entry.path, symbol: )`

## 附录 · 非按钮控件 `Picker`（归口待裁）· 49 处

- `App/Views/AccountSyncSheet.swift:137` ``
- `App/Views/AgentAuditPanel.swift:262` ``
- `App/Views/AgentAuditPanel.swift:271` ``
- `App/Views/AgentSettingsSheet.swift:45` `L(.agentProvider)`
- `App/Views/AppearanceSheet.swift:93` ``
- `App/Views/AppearanceSheet.swift:121` `L(.appearanceMonoFamily)`
- `App/Views/AppearanceSheet.swift:339` ``
- `App/Views/AppearanceSheet.swift:362` ``
- `App/Views/BackupRestoreSheet.swift:64` ``
- `App/Views/BackupRestoreSheet.swift:73` `L(.backupRestoreFormat)`
- `App/Views/BackupRestoreSheet.swift:182` ``
- `App/Views/ConnectionDialectSection.swift:72` `L(.connectionFormDbType)`
- `App/Views/ConnectionDialectSection.swift:100` `L(.connectionFormSSLMode)`
- `App/Views/ConnectionFormView.swift:233` ``
- `App/Views/ConnectionFormView.swift:247` ``
- `App/Views/ConnectionFormView.swift:384` ``
- `App/Views/ConnectionFormView.swift:427` ``
- `App/Views/DataTaskPanel.swift:323` ``
- `App/Views/DataTaskPanel.swift:370` ``
- `App/Views/DataTaskPanel.swift:397` ``
- `App/Views/DataTaskPanel.swift:429` ``
- `App/Views/DataTaskVersionSheet.swift:153` ``
- `App/Views/DatabasePropertiesSheet.swift:42` `L(.dbPropsAllowConnections)`
- `App/Views/EgressLogSheet.swift:68` ``
- `App/Views/EgressLogSheet.swift:77` ``
- `App/Views/EgressLogSheet.swift:88` ``
- `App/Views/ImportPanel.swift:158` ``
- `App/Views/ImportPanel.swift:178` ``
- `App/Views/ImportPanel.swift:311` ``
- `App/Views/ObjectTreeToolbar.swift:36` ``
- `App/Views/PrivilegePanel.swift:162` `L(.privilegeObjectKind)`
- `App/Views/QueryContextBar.swift:19` `L(.contextServer)`
- `App/Views/QueryContextBar.swift:49` `L(.contextDatabase)`
- `App/Views/QueryParameterSheet.swift:103` ``
- `App/Views/ResultPagerBar.swift:25` ``
- `App/Views/ResultTableView.swift:244` ``
- `App/Views/RoutineCandidatesPanel.swift:62` ``
- `App/Views/RoutineCandidatesPanel.swift:342` ``
- `App/Views/SchemaDiffPanel.swift:105` ``
- `App/Views/ServerObjectsPanel.swift:152` ``
- `App/Views/TodoCalendarView.swift:41` `L(.notesModuleTodos)`
- `App/Views/TodoCalendarView.swift:96` `L(.todoPaneCalendar)`
- `App/Views/TodoCalendarView.swift:564` `L(.todoFilterLabel)`
- `App/Views/TodoCalendarView.swift:591` `L(.todoSortLabel)`
- `App/Views/TodoCalendarView.swift:602` `L(.todoGroupLabel)`
- `Plugins/Notes/Views/NotesPanel.swift:244` `L(.notesSortBy)`
- `Plugins/Notes/Views/NotesPanel.swift:1373` `L(.notesSearchScopeTitle)`
- `Plugins/Notes/Views/NotesPanel.swift:1880` `L(.todoPriorityLabel)`
- `Plugins/Notes/Views/NotesPanel.swift:2011` `L(.reminderSection)`

## 空串按钮（豁免：无可见文案）· 4 处

- `App/Views/MainWindow.swift:266`
- `App/Views/TableDesignExtrasSection.swift:153`
- `App/Views/TableDesignSheet.swift:190`
- `App/Views/TableDesignSheet.swift:194`
