import SwiftUI
import DoyahCore

struct QueryWorkspaceView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            // **浏览器页签不在这里**（队列 `L-149`，2026-09-30 需求提出者实测反馈）：
            // 数据库侧是 **SQL 这门语言的工作台**；浏览器页签属于**工作区**（与 Home 同一类页签，
            // 因为 html 也是一种文件）。原先它在这里既占内容区又占页签条。
            if let tab = appState.selectedTab {
                // **下方面板不在这里**（2026-09-30）：它搬到了 `MainWindow.sectionWithLowerPane`，
                // 与「工作区」段共享同一个实例（需求提出者实测反馈：「带 terminal 的底部区域是在
                // 两个功能中共享的」）。所以这一层只画页签条 + 编辑器，最大化也由那一层统一判。
                VStack(spacing: 0) {
                    tabBar
                    Divider()
                    QueryEditorView(tab: tab)
                }
            } else {
                ContentUnavailableView(
                    L(.workspaceNoTabsTitle),
                    systemImage: "doc.text",
                    description: Text(L(.workspaceNoTabsDescription))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // **底色走主题令牌**（2026-09-30 需求提出者实测：数据库客户端与工作区配色差很大）。
        // 原来写的是系统 `textBackgroundColor` —— 它跟 `DesignTheme` 无关，于是同一屏里
        // 「工作区是科技蓝、数据库客户端是系统白」并存。令牌化后两段同一个底色家族。
        // 底色由父层统一给（`sectionWithLowerPane` 的 `NebulaBackground`）——
    // 这里再铺不透明色会把星云皮肤**整片盖住**（2026-10-01 实测）。
    .background(Color.clear)
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(appState.tabs) { tab in
                    HStack(spacing: Spacing.s) {
                        if tab.isExecuting {
                            ProgressView()
                                .controlSize(.mini)
                        }

                        // 数据库侧**不认识浏览器**（队列 `L-149` 剩余①）：这里原先会顺手清掉浏览器
                        // 页签的选中态、加粗也看「浏览器有没有被选中」—— 那两处是浏览器还长在
                        // 编辑区时留下的耦合。浏览器现在是**工作区的一类页签**，在数据库侧点
                        // SQL 页签与它无关（要清选中态是工作区页签条自己的事，见 `WorkspaceTabStrip`）。
                        Button(tab.isDirty ? "\(tab.title) •" : tab.title) {
                            appState.selectedTabID = tab.id
                        }
                        .buttonStyle(.plain)
                        .fontWeight(
                            appState.selectedTabID == tab.id
                                ? .semibold
                                : .regular
                        )

                        Button {
                            appState.closeTab(tab.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(Theme.font(.caption))
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.tabs.count <= 1 || tab.isExecuting)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.card)
                            .fill(appState.selectedTabID == tab.id ? Color.accentColor.opacity(0.16) : Color.clear)
                    )
                }

                Button {
                    appState.newQueryTab()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

struct QueryEditorView: View {
    @EnvironmentObject private var appState: AppState
    let tab: QueryTab
    /// 编辑器缓冲（队列 `L-148`）：每键只写它 ⇒ 重算范围只有这一小块，
    /// 而不是观测全局 `AppState` 的整个窗口。
    @EnvironmentObject private var editorBuffer: QueryEditorBuffer
    @State private var isSaveQueryPresented = false
    @State private var isGoToLinePresented = false

    var body: some View {
        let diagnostics = QueryDiagnostics.analyze(tab: tab, in: appState)

        VStack(spacing: 0) {
            QueryContextBar()
            Divider()

            // 工具条只放按钮 / 下拉框（2026-09-24 需求提出者要求）：连接信息不再传进来，
            // 「连着哪台库、哪个库」由它上面那一条上下文档负责（服务器 / 数据库两个下拉框）。
            QueryToolbar(
                tab: tab,
                onOpenFile: {
                    appState.openFileFromPanel()
                },
                onSaveFile: {
                    appState.saveCurrentFile(for: tab.id, forceSaveAs: false)
                },
                onSaveFileAs: {
                    appState.saveCurrentFile(for: tab.id, forceSaveAs: true)
                },
                onSaveQuery: { isSaveQueryPresented = true },
                onRequestGoToLine: { isGoToLinePresented = true },
                onEditCommand: { command in
                    EditorCommandCenter.shared.send(command, to: tab.id)
                }
            )
            Divider()

            // 三块自下而上：编辑区 → 结果表 → 下方面板，分隔条都可拖拽。
            // **结果表留在查询自己的地盘**（它是数据，不是日志），下方面板只放应用级页签
            // （问题 / 输出 / 终端 / 调试控制台）—— 这样面板与产品未来无关。
            //
            // 两条默认值（需求提出者要求）：
            // ① **结果区默认不显示** —— 只有执行过、且确实有表格结果才出现，一上来空着会显得拥挤；
            // ② **下方面板默认占 20% 高度** —— 让人知道有这么个面板，又不至于把编辑区挤扁。
            // VSplitView 的子视图数量必须按分支固定，所以四种组合各写一条。
            // **下方面板已搬到段一级**（2026-09-30，见 `MainWindow.sectionWithLowerPane`）——
            // 这里只剩「编辑区 → 结果表」两块（`VSplitView` 的子视图数量必须按分支固定，所以两种组合各一条）。
            GeometryReader { geometry in
                let total = geometry.size.height
                let editorIdeal = showsResult ? total * 0.55 : total
                let resultIdeal = total * 0.45

                Group {
                    if showsResult {
                        VSplitView {
                            editorArea(diagnostics)
                                .frame(minHeight: 100, idealHeight: editorIdeal)
                            resultArea
                                .frame(minHeight: 100, idealHeight: resultIdeal)
                        }
                    } else {
                        editorArea(diagnostics)
                    }
                }

            }
            // 折叠态：把**标题栏**留在**底部**（向上箭头就在它右边）。
            //
            // 位置踩过一次坑（2026-09-24 需求提出者：「折成一行标题栏应该放底部，放上面恰好遮住了
            // SQL 编辑窗口的第一行」）：一开始它写在上面的 `GeometryReader` **里面** ——
            // `GeometryReader` 的内容不负责纵向排布，`ViewBuilder` 里的第二个视图会跟第一个**重叠**在
            // 同一个原点，于是标题栏跑到顶部、盖住编辑器第一行。
            // 放到这里（外层 VStack 里 GeometryReader **之后**）才真的在底部。
            // 折叠态标题栏也归段一级那一层（`sectionWithLowerPane` 传 `isCollapsed`）。
        }
        .sheet(isPresented: $isSaveQueryPresented) {
            SaveQuerySheet(
                defaultName: defaultQueryName,
                isDuplicate: { name in
                    appState.savedQueries.contains { $0.name == name }
                },
                onSave: { name in
                    Task { await appState.saveCurrentQuery(for: tab.id, name: name) }
                }
            )
        }
        .sheet(isPresented: $isGoToLinePresented) {
            GoToLineSheet { line, column in
                EditorCommandCenter.shared.send(.goToLine(line: line, column: column), to: tab.id)
            }
        }
    }

    private var defaultQueryName: String {
        appState.suggestedQueryName(for: tab)
    }

    /// 结果区要不要出现：执行过、且确实有表格结果（没有结果集的语句不进结果区）。
    private var showsResult: Bool {
        tab.hasTabularResult
    }

    // MARK: - 编辑区

    private func editorArea(_ diagnostics: [SQLDiagnostic]) -> some View {
        VStack(spacing: 0) {
            SQLEditorView(
                text: editorBuffer.displayText(for: tab.id, authoritative: tab.sql),
                databaseType: appState.connection(for: tab)?.dbType ?? .postgresql,
                diagnostics: diagnostics,
                tabID: tab.id,
                // 每键只写缓冲（队列 `L-148`）：写 `appState` 会让整个窗口每键重算
                // —— 5,000 行实测 31.74 ms/键。
                onTextChange: { editorBuffer.noteEdit($0, for: tab.id) },
                // 查询记忆（FR-AI-13 S4）：索引来自归档，按**连接名**隔离 ——
                // 生产库跑过的语句不会跑到测试库的补全里。
                memoryIndex: appState.queryMemoryIndex,
                memoryConnection: appState.connection(for: tab)?
                    .displayTitle(untitled: L(.connectionUntitled))
            )
            // **提交点**（队列 `L-148`）：视图消失 = 切页签 / 切模块，
            // 此刻把草稿写回权威副本，避免"切回来发现最后一段编辑没了"。
            .onDisappear { appState.commitEditorDraft(for: tab.id) }

            if !diagnostics.isEmpty {
                Divider()
                diagnosticsBar(diagnostics)
            }
        }
    }

    private func diagnosticsBar(_ diagnostics: [SQLDiagnostic]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(diagnostics.prefix(3)) { diagnostic in
                HStack(alignment: .top, spacing: Spacing.s) {
                    Image(systemName: diagnostic.severity == .error
                          ? "xmark.octagon.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(diagnostic.severity == .error ? Theme.status(.danger) : Theme.status(.warning))
                    Text("\(L(.lintLocation, diagnostic.line, diagnostic.column))：\(diagnostic.message)")
                        .font(Theme.font(.caption))
                        .foregroundStyle(diagnostic.severity == .error ? Theme.status(.danger) : Theme.status(.warning))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }

            if diagnostics.count > 3 {
                Text(L(.workspaceMoreDiagnostics, diagnostics.count - 3))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.status(.danger).opacity(0.06))
    }

    // MARK: - 结果区

    private var resultArea: some View {
        VStack(spacing: 0) {
            // 结果集的「出处」（第 N 条语句 · X 行 × Y 列）。这是结果集自己的元信息，
            // 所以留在结果表这一块，而不是再往 Output 日志抄一遍。
            if let provenance = selectedProvenance {
                Text(provenance)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                Divider()
            }

            ResultTableView(
                result: tab.result,
                resultCount: tab.results.count,
                selectedIndex: tab.selectedResultIndex,
                onSelectResult: { index in
                    appState.selectResult(index, for: tab.id)
                },
                isExecuting: tab.isExecuting,
                onExport: { format, encoding in
                    Task { await appState.exportResult(for: tab.id, format: format, encoding: encoding) }
                },
                onGenerateWhere: { clause in
                    appState.applyClientFilterWhere(clause, for: tab.id)
                },
                onJumpToReferencedRow: { column, value in
                    appState.jumpToReferencedRow(column: column, value: value)
                },
                // 内联编辑（FR-DATA-04）要知道"改的是哪个页签、哪张表"：
                // 页签给出连接与目标库；来源表**只认 `sourceTable`** ——
                // 手写 SQL 的结果没有它，那时界面直说"不知道是哪张表"，绝不猜表名。
                tabID: tab.id,
                sourceTable: tab.sourceTable
            )
        }
    }

    /// 当前选中结果集的「出处」；没有（例如刚清空）时为 nil。
    private var selectedProvenance: String? {
        let index = tab.selectedResultIndex
        guard tab.resultSummaries.indices.contains(index) else { return nil }
        let value = tab.resultSummaries[index]
        return value.isEmpty ? nil : value
    }
}
