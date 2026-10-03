import DoyahCore
import SwiftUI

/// 笔记区的两块（DOYAH-01 / 03）：**列表**进侧栏、**编辑器**进右侧。
///
/// 为什么拆成两个视图而不是原来那个"一个面板装下所有"：
/// 笔记在 Standard 下就是**整个应用**（活动栏只有它一项），必须有正经的侧栏 + 正文两栏，
/// 而不是浮在别人界面上的一个弹窗 —— 弹窗被关掉以后，用户会不确定笔记还在不在。
/// 两栏的分工也正好对上活动栏的信息架构：「看哪个视图」（笔记）与「视图里看什么」（哪一条）。
///
/// 两条刻意的口径（与拆分前一致）：
/// ① **来源与「含数据」必须一眼可见** —— 笔记将来会同步到云端，"这条是哪来的、含不含数据"
///    是用户必须能直接看出来的事实，不能藏在详情里；
/// ② 编辑已有笔记时**保留原来源**（来源是事实，不该因为改了几个字就丢掉）。
struct NotesListView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            // **两级导航**（队列 `L-97` ②）：架 → 笔记本 → 笔记。放在列表上方（同一栏内）而不是
            // 再切一列 —— 侧栏只有 240~380pt，再切一列两边都读不清（`FR-EDIT-37` 那一课：
            // 宽度不够时别硬塞）。范围选中态由 `AppState.selectNotesScope` 统一归一。
            NotesContainerTreeView()
            Divider()
            // **搜索范围**（队列 `L-97` ⑤）：只在搜索那一层起作用 —— 「当前范围」= 限定在看的那一块，
            // 「全部笔记本」= 跨笔记本搜（结果行里如实标出每条属于哪个笔记本）。
            Picker(L(.notesSearchScopeTitle), selection: $appState.notesSearchScope) {
                Text(L(.notesSearchScopeCurrent)).tag(NotesSearchScope.current)
                Text(L(.notesSearchScopeAll)).tag(NotesSearchScope.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Spacing.s)
            .accessibilityIdentifier("notes-search-scope")
            TextField(L(.notesSearchPlaceholder), text: $appState.notesQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, Spacing.s)
            // **检索走库**（队列 L-44）：搜索框里变一个字就重算一次。`.task(id:)` 在 id 变化时
            // 会取消上一次任务；`AppState.searchNotes()` 里还有一道「结果过期就丢」的守卫，
            // 打字比查库快也不会把旧结果盖上来。
            if let hint = appState.noteSearchHint {
                // 这一行是**如实交代**：走的是子串兜底，还是检索压根没跑成 —— 两种都不是
                // 「没找到」，所以不能只给一个空列表了事。
                Text(hint)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .padding(.horizontal, Spacing.s)
            }
            if appState.visibleNotes.isEmpty {
                // 分两种"空"：一条笔记都没有，和"搜不到"—— 后者要提示改搜索词，
                // 否则用户会以为笔记丢了。
                Text(appState.notesQuery.isEmpty ? L(.notesEmpty) : L(.noteSearchNoMatch))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .padding(Spacing.s)
                Spacer()
            } else {
                List(appState.visibleNotes) { note in
                    Button {
                        appState.edit(note)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Spacing.xs) {
                                Text(note.title)
                                    .font(Theme.font(.body))
                                    .lineLimit(1)
                                if note.containsRowData {
                                    Text(L(.notesContainsRowData))
                                        .font(Theme.font(.caption))
                                        .foregroundStyle(Theme.status(.warning))
                                }
                            }
                            Text(note.source.kind.displayName + " · " + (note.source.connectionName ?? "—"))
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.text(.secondary))
                            // 跨笔记本搜（搜索范围 = 全部笔记本）时如实标出这条属于哪个笔记本 ——
                            // 否则结果里一堆同名笔记，看不出它们不是一回事（队列 `L-97` ⑤）。
                            if appState.showsNotebookInNoteRow, let notebook = appState.notebookName(for: note) {
                                Text(L(.notesRowNotebook, notebook))
                                    .font(Theme.font(.caption))
                                    .foregroundStyle(Theme.text(.secondary))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note-row-\(note.id.uuidString)")
                }
            }
        }
        .padding(.vertical, Spacing.s)
        .accessibilityIdentifier("notes-list")
        // 侧栏底色与工作区侧栏同一令牌（2026-09-30 实测反馈：笔记界面与工作区配色差很大）。
        .scrollContentBackground(.hidden)
        .background(Theme.surface(.sidebar))
        // 搜索框里的词一变就重算一次（与上面那条注释同源：`task(id:)` 会取消上一次任务）。
        // 空查询进这里也只是把状态置回 `.idle` —— 不查库、不改列表。
        .task(id: appState.notesQuery) {
            await appState.searchNotes()
        }
    }
}

/// **两级导航**（队列 `L-97` ②）：笔记本架 → 笔记本，最上面一行「全部」。
///
/// 三条口径写在这儿（都各自有理由）：
///  ① **行上的数字是「这里真正有多少条」**（按归属逐条重算，见 `NotesNavigation.noteCount`）——
///     不是估算、也不是「索引里有多少」；两处不一致时以归属为准（契约 §2.12 第 5 条）。
///  ② **点架 = 看整架**（架里的所有笔记本）—— 架不只是一个「分组标题」，它自己也是一个范围。
///  ③ **默认容器不特殊显示**：用户眼里它就是「笔记本」这个名字（契约只要求它**不可删**，
///     没要求界面上把它标成默认 —— 标出来反而像另一种东西）。
///
/// 未做（如实登记，留给下一片）：重命名 / 新建 / 排序 / 拖拽 / 右键菜单 / 删除确认框
/// —— 那些要走删除确认框与跨笔记本移动（队列 `L-97` ③④），本片只落「看哪一块」。
struct NotesContainerTreeView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(
                scope: .all,
                systemImage: "tray.full",
                title: L(.notesAllNotes),
                count: appState.notes.count,
                indent: 0,
                identifier: "notes-scope-all"
            )
            ForEach(appState.notesNavigation.shelves) { shelf in
                row(
                    scope: .shelf(uid: shelf.uid),
                    systemImage: "books.vertical",
                    title: shelf.name,
                    count: appState.notesNavigation.noteCount(inShelf: shelf.uid, notes: appState.notes),
                    indent: 0,
                    identifier: "notes-scope-shelf-\(shelf.uid)"
                )
                ForEach(appState.notesNavigation.notebooks(inShelf: shelf.uid)) { notebook in
                    row(
                        scope: .notebook(uid: notebook.uid),
                        systemImage: "book",
                        title: notebook.name,
                        count: appState.notesNavigation.noteCount(inNotebook: notebook.uid, notes: appState.notes),
                        indent: 1,
                        identifier: "notes-scope-notebook-\(notebook.uid)"
                    )
                }
            }
        }
        .accessibilityIdentifier("notes-container-tree")
    }

    /// 一行：图标 + 名字 + 条数，选中态由 `notesScope` 给（比对归一后的值 —— 用户看到的选中
    /// 与状态里的选中必须是同一个）。
    private func row(
        scope: NotesScope,
        systemImage: String,
        title: String,
        count: Int,
        indent: Int,
        identifier: String
    ) -> some View {
        let selected = appState.notesScope == scope
        return Button {
            appState.selectNotesScope(scope)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: systemImage)
                    .font(Theme.font(.caption))
                    .frame(width: 14)
                Text(title)
                    .font(Theme.font(.body))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Spacing.xs)
                Text("\(count)")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            }
            .padding(.vertical, Spacing.hair)
            .padding(.leading, Spacing.s + CGFloat(indent) * 14)
            .padding(.trailing, Spacing.s)
            .contentShape(Rectangle())
            .background(selected ? Theme.surface(.panel) : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// 笔记正文（标题 / 标签 / 正文 / 保存 + 新建）。
struct NotesEditorView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(L(.notesTitle))
                    .font(Theme.font(.title))
                Text("\(appState.notes.count)")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                Spacer()
                Button(L(.notesNew)) { appState.beginNewNote() }
            }
            TextField(L(.notesUntitled), text: $appState.noteEditorTitle)
                .textFieldStyle(.roundedBorder)
            TextField(L(.notesTagsPlaceholder), text: $appState.noteEditorTags)
                .textFieldStyle(.roundedBorder)
                .font(Theme.font(.caption))
            TextEditor(text: $appState.noteEditorBody)
                .font(Theme.font(.mono))
                .editorSurface()
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.surface(.panel), lineWidth: 1)
                )
            HStack(spacing: Spacing.s) {
                Button(L(.notesSave)) {
                    Task { await appState.saveNoteFromEditor() }
                }
                .keyboardShortcut(.defaultAction)
                // 空编辑器上不许「可点却静默无反应」（队列 L-50）：判据属性是**唯一出处**，
                // 与 `saveNoteFromEditor()` 的第一句内容守卫同一条判断（口径 = 灰着）。
                // 许可那一档故意不灰 —— Pro 档点下去要给「本档不含笔记」那句人话。
                .disabled(!appState.noteEditorHasContent)
                Text(L(.notesSourceHint))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                Spacer()
            }
        }
        .padding(Spacing.l)
        .accessibilityIdentifier("notes-editor")
        // 内容底色与工作区内容同一令牌（原来这一屏**没有任何根底色** ⇒ 直接用系统窗口底，
        // 于是「工作区是科技蓝、笔记是系统色」并存）。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface(.content))
    }
}
