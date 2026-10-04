import AppKit
import DoyahCore
import SwiftUI

/// 笔记区的两块（DOYAH-01 / 03）：**列表**进中栏、**编辑器**进右栏（队列 `L-184` 三栏重排）。
///
/// 三栏的分工（需求提出者 2026-10-04 原话「macOS版界面布局可以借鉴印象笔记PC端布局」）：
///   · **左栏** = 导航（笔记本架 → 笔记本 两级树）—— 由 `MainWindow` 的侧栏承载，可折叠；
///   · **中栏** = 这一条列表（本文件 `NotesListView`：标题 + 摘要 + 相对时间）；
///   · **右栏** = 正文 / 编辑器（`NotesEditorView`，读写同屏）；
///   · **顶栏** = 搜索（作用域 = 当前范围 / 全部笔记本）+ 新建（`NotesAreaView`）。
///
/// 为什么把搜索框从侧栏搬到顶栏：三栏之后侧栏只剩「导航」这一件事（与印象笔记的分工同形），
/// 而搜索在侧栏里只能搜「当前这一栏」，搬上去之后它管的是**整个笔记模块** —— 这也是
/// `L-97` ⑤「搜索范围」那枚开关原先语义最容易被读错的地方（它现在就挂在搜索框旁边。
///
/// 两条刻意的口径（与拆分前一致）：
/// ① **来源与「含数据」必须一眼可见** —— 笔记将来会同步到云端，"这条是哪来的、含不含数据"
///    是用户必须能直接看出来的事实，不能藏在详情里；
/// ② 编辑已有笔记时**保留原来源**（来源是事实，不该因为改了几个字就丢掉）。
struct NotesListView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            // **中栏的栏头**（队列 `L-184`）：两级导航（架 → 笔记本）搬回左栏、搜索框搬去顶栏，
            // 这一栏只剩「看哪一条」—— 栏头写这一屏有多少条 + **排序条**（第二片新加）。
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(L(.notesTitle))
                    .font(Theme.font(.title))
                Text("\(appState.visibleNotes.count)")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                Spacer(minLength: Spacing.xs)
                // **排序**（队列 `L-184` 第二片）：三档名字与总序都在 Core
                // （`NotesSortOrder`）—— 视图只画选择器，不自己写比较函数。
                Picker(L(.notesSortBy), selection: $appState.notesSortOrder) {
                    ForEach(NotesSortOrder.allCases, id: \.self) { order in
                        Text(L(order.key)).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .help(L(.notesSortBy))
                .accessibilityIdentifier("notes-sort")
                // **筛选条**（队列 `L-184` 第三片）：中栏栏头这一枚「只看收藏」。
                // 它不是第二个状态 —— 绑的就是左栏那一行（`AppState.notesFavoriteOnly` 一处判，
                // 两个界面面共用一个变量 ⇒ 不可能出现「开关开着、列表在看全部」）。
                Toggle(isOn: Binding(
                    get: { appState.notesFavoriteOnly },
                    set: { appState.setNotesFavoriteOnly($0) }
                )) {
                    Label(L(.notesFavoriteOnly), systemImage: "star")
                        .font(Theme.font(.caption))
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .fixedSize()
                .help(L(.notesFavoriteOnly))
                .accessibilityIdentifier("notes-favorite-filter")
            }
            .padding(.horizontal, Spacing.s)
            if let hint = appState.noteSearchHint {
                // 这一行是**如实交代**：走的是子串兜底，还是检索压根没跑成 —— 两种都不是
                // 「没找到」，所以不能只给一个空列表了事。
                Text(hint)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .padding(.horizontal, Spacing.s)
            }
            // **多选时的实况**（队列 `L-97` 界面半第五片）：右键「移动选中的 N 条」会带走的就是这些。
            // 只在真的多选（>1）时出现 —— 选一条时这一行是噪音。
            if appState.noteSelectionCount > 1 {
                Text(L(NoteSelectionPrompt.countKey, appState.noteSelectionCount))
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
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Spacing.xs) {
                            Text(note.title)
                                .font(Theme.font(.body))
                                .lineLimit(1)
                            // **置顶的标记**（队列 `L-184` 第四片）：置顶过的行上看得见图钉 ——
                            // 与收藏的星是**两件事**（契约 §2.1：置顶是第一关键字、收藏是第二），
                            // 两个标记各画各的，不合并成一个「标记过」。
                            if note.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(Theme.font(.caption))
                                    .foregroundStyle(Theme.text(.secondary))
                                    .accessibilityLabel(L(.notesPinned))
                            }
                            // **收藏的标记**（队列 `L-184` 第三片）：收藏过的行上看得见星 ——
                            // 否则「收藏了没有」只能靠右键菜单里的措辞反推。
                            if note.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(Theme.font(.caption))
                                    .foregroundStyle(Theme.status(.warning))
                                    .accessibilityLabel(L(.notesFavorites))
                            }
                            if note.containsRowData {
                                Text(L(.notesContainsRowData))
                                    .font(Theme.font(.caption))
                                    .foregroundStyle(Theme.status(.warning))
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                            Text(note.source.kind.displayName + " · " + (note.source.connectionName ?? "—"))
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.text(.secondary))
                            Spacer(minLength: Spacing.xs)
                            // **相对时间**（队列 `L-184` 中栏卡片）：档位由 Core 的
                            // `NotePresentation.relative` 给、句子由语言表给 —— 视图这一层只把
                            // 「哪一档 + 数字」搬成一句话，不自己算 60 / 3600 这类边界。
                            Text(timeText(note.updatedAt))
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.text(.secondary))
                        }
                        // **摘要两行**（队列 `L-184`）：折行与截断都在 Core 一处
                        // （`NotePresentation.excerpt`）—— 视图不自己 `prefix`，否则两处各截一半。
                        if !note.body.isEmpty {
                            Text(NotePresentation.excerpt(note.body))
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.text(.secondary))
                                .lineLimit(2)
                        }
                        // 跨笔记本搜（搜索范围 = 全部笔记本）时如实标出这条属于哪个笔记本 ——
                        // 否则结果里一堆同名笔记，看不出它们不是一回事（队列 `L-97` ⑤）。
                        if appState.showsNotebookInNoteRow, let notebook = appState.notebookName(for: note) {
                            Text(L(.notesRowNotebook, notebook))
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.text(.secondary))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { appState.handleNoteRowClick(note, modifiers: .currentEvent) }
                    .draggable(appState.noteDragPayload(for: note))
                    .help(L(NoteSelectionPrompt.dragHintKey))
                    .contextMenu {
                        pinnedToggle(for: note)
                        favoriteToggle(for: note)
                        Divider()
                        moveMenu(for: note)
                    }
                    .listRowBackground(
                        appState.selectedNoteIDs.contains(note.id) ? Theme.surface(.panel) : Color.clear
                    )
                    .accessibilityIdentifier("note-row-\(note.id.uuidString)")
                }
            }
        }
        .padding(.vertical, Spacing.s)
        .accessibilityIdentifier("notes-list")
        // 侧栏底色与工作区侧栏同一令牌（2026-09-30 实测反馈：笔记界面与工作区配色差很大）。
        .scrollContentBackground(.hidden)
        .background(Theme.surface(.sidebar))
    }

    /// 行右键里的**收藏 / 取消收藏**（队列 `L-184` 第三片）：一个动作两种措辞 —— 当前不是收藏
    /// ⇒ 「收藏」、已是收藏 ⇒ 「取消收藏」（同一件事在两处各写一遍，必然出现「两个都写着『收藏』」
    /// 那种菜单）。写库与重读都在 `AppState.toggleNoteFavorite` 一处。
    @ViewBuilder
    private func favoriteToggle(for note: Note) -> some View {
        Button(L(note.isFavorite ? .notesUnmarkFavorite : .notesMarkFavorite)) {
            Task { await appState.toggleNoteFavorite(note) }
        }
        .accessibilityIdentifier("notes-favorite-toggle-\(note.id.uuidString)")
    }

    /// 行右键里的**置顶 / 取消置顶**（队列 `L-184` 第四片）：与上面那条同一条纪律 ——
    /// 一个动作两种措辞（当前没置顶 ⇒「置顶」、已置顶 ⇒「取消置顶」），写库与重读都在
    /// `AppState.toggleNotePinned` 一处。**它与收藏是两条独立的菜单项**（契约 §2.1 的两档排序）。
    @ViewBuilder
    private func pinnedToggle(for note: Note) -> some View {
        Button(L(note.isPinned ? .notesUnmarkPinned : .notesMarkPinned)) {
            Task { await appState.toggleNotePinned(note) }
        }
        .accessibilityIdentifier("notes-pinned-toggle-\(note.id.uuidString)")
    }

    /// 笔记行右键的「移动到…」（队列 `L-97` ④）：清单 / 顺序 / 当前格都由 Core 给
    /// （`NotebookMovePrompt`），这里只按架分组画出来 —— 分组与左边那棵树的层级一致。
    /// 「一个可去的地方都没有」时那一项**灰着并写明理由**，不是一个空菜单（`L-50` 的口径：
    /// 可点却静默无反应是最坏的一种；空菜单则会被读成「这个功能没做」）。
    @ViewBuilder
    private func moveMenu(for note: Note) -> some View {
        // **批量多选**（队列 `L-97` 界面半第五片）：这一行在选中集合里 ⇒ 整捆一起走
        // （规则在 Core `NoteSelectionRule.draggedNoteIDs`），菜单标题如实写「几条」。
        let noteIDs = appState.noteMoveIDs(for: note)
        let targets = appState.noteMoveTargets(for: noteIDs)
        Menu(noteIDs.count > 1 ? L(NoteSelectionPrompt.moveSelectionKey, noteIDs.count) : L(NotebookMovePrompt.menuTitleKey)) {
            if NotebookMovePrompt.hasDestination(targets) {
                ForEach(appState.notesNavigation.shelves) { shelf in
                    let inShelf = targets.filter { $0.shelfUid == shelf.uid }
                    if !inShelf.isEmpty {
                        Menu(shelf.name) {
                            ForEach(inShelf) { target in
                                Button(moveLabel(for: target)) {
                                    Task { await appState.moveNotes(noteIDs, toNotebook: target.id) }
                                }
                                .disabled(!target.isSelectable)
                                .accessibilityIdentifier("notes-move-to-\(target.id)")
                            }
                        }
                    }
                }
            } else {
                Button(L(NotebookMovePrompt.noTargetKey)) {}
                    .disabled(true)
            }
        }
        .accessibilityIdentifier("notes-move-menu")
    }

    /// 目标那一行的文字：当前格带上「你现在在这儿」的后缀（文字在语言表里，这里只拼接）。
    private func moveLabel(for target: NotebookMoveTarget) -> String {
        target.isCurrent ? target.name + L(NotebookMovePrompt.currentMarkKey) : target.name
    }

    /// **相对时间那一句**（队列 `L-184`）：档位是 Core 的纯逻辑，句子只从语言表来。
    /// 「刚刚」「昨天」两档没有数字槽 ⇒ 不传实参（模板里也没有占位符）。
    private func timeText(_ date: Date) -> String {
        let relative = NotePresentation.relative(date)
        guard let argument = relative.argument else { return L(relative.key) }
        return L(relative.key, argument)
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
/// 未做（如实登记，留给下一片）：**拖拽排序**与**批量多选**（右键菜单那一半已落：新建 / 重命名 /
/// 上移 / 下移 / 删除 / 移动）。
/// **已做**（本片）：右键 → 删除 → 确认框（`ContainerRemovalPrompt` 给动作与顺序，
/// `AppState.pendingContainerRemovalMessage` 给影响面那句）；右键 → 新建 / 重命名 / 上移 / 下移
/// （`NotebookEditPrompt` 给规则，`AppState` 给入口），树顶那个「＋」是新建的第二个入口。
struct NotesContainerTreeView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // **新建笔记本**（队列 `L-97` 界面半第四片）：入口在树顶上（右键某一行的菜单里也有一个，
            // 那个会指定「就建在这一行这个架里」）。`help` 用同一句文案 —— 一个光秃秃的「＋」
            // 在侧栏里是能认出来的，但悬停时要给得出一个词。
            HStack(spacing: Spacing.xs) {
                Spacer()
                Button {
                    appState.beginNewNotebook()
                } label: {
                    Image(systemName: "plus")
                        .font(Theme.font(.caption))
                }
                .buttonStyle(.plain)
                .help(L(NotebookCreation.menuTitleKey))
                .accessibilityIdentifier("notes-new-notebook")
            }
            .padding(.horizontal, Spacing.s)
            row(
                scope: .all,
                systemImage: "tray.full",
                title: L(.notesAllNotes),
                count: appState.notes.count,
                indent: 0,
                identifier: "notes-scope-all"
            )
            // **已收藏**（队列 `L-184` 第三片）：跨全部笔记本的**常驻**入口 —— 与中栏栏头那枚
            // 「只看收藏」开关说的是同一件事（两边绑同一个状态，不是两套判断）。
            // 数字与点进去的行数走同一条判断（`favoriteCount` → `contains(.favorites, ...)`）。
            row(
                scope: .favorites,
                systemImage: "star",
                title: L(.notesFavorites),
                count: appState.notesNavigation.favoriteCount(in: appState.notes),
                indent: 0,
                identifier: "notes-scope-favorites"
            )
            // **最近**（队列 `L-184` 第二片）：跨全部笔记本、**有界**的一屏（条数在 Core 定死 ——
            // 无界的「最近」就等于「全部笔记」，那是一个点了像没点的入口，`L-50` 同族）。
            row(
                scope: .recent,
                systemImage: "clock",
                title: L(.notesRecent),
                count: appState.notesNavigation.filter(appState.notes, scope: .recent).count,
                indent: 0,
                identifier: "notes-scope-recent"
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
                // **架上的编辑菜单**（队列 `L-97` 界面半第四片）：新建（就在这个架里）/ 重命名 / 排序，
                // 最后才是删除。删除那一项**不灰**（默认架点了要给一句「不能删」的人话）。
                .contextMenu {
                    Button(L(NotebookCreation.menuTitleKey)) {
                        appState.beginNewNotebook(inShelf: shelf.uid)
                    }
                    .accessibilityIdentifier("notes-new-notebook-in-\(shelf.uid)")
                    Button(L(ContainerEditPrompt.menuTitleKey)) {
                        appState.beginRenameContainer(
                            kind: .shelf, uid: shelf.uid, name: shelf.name, isDefault: shelf.isDefault
                        )
                    }
                    .accessibilityIdentifier("notes-rename-shelf-\(shelf.uid)")
                    Divider()
                    reorderButtons(kind: .shelf, uid: shelf.uid)
                    Divider()
                    Button(L(ContainerRemovalPrompt.menuTitleKey(for: .shelf))) {
                        appState.requestContainerRemoval(kind: .shelf, uid: shelf.uid, name: shelf.name)
                    }
                    .accessibilityIdentifier("notes-remove-shelf-\(shelf.uid)")
                }
                ForEach(appState.notesNavigation.notebooks(inShelf: shelf.uid)) { notebook in
                    row(
                        scope: .notebook(uid: notebook.uid),
                        systemImage: "book",
                        title: notebook.name,
                        count: appState.notesNavigation.noteCount(inNotebook: notebook.uid, notes: appState.notes),
                        indent: 1,
                        identifier: "notes-scope-notebook-\(notebook.uid)"
                    )
                    .contextMenu {
                        Button(L(ContainerEditPrompt.menuTitleKey)) {
                            appState.beginRenameContainer(
                                kind: .notebook, uid: notebook.uid, name: notebook.name, isDefault: notebook.isDefault
                            )
                        }
                        .accessibilityIdentifier("notes-rename-notebook-\(notebook.uid)")
                        // **跨架移动**（队列 `L-97` 界面半第六片 = 落法 ① 的第四格）：清单 / 顺序 /
                        // 当前架都由 Core 给（`NotebookShelfMovePrompt`），这里只按架画出来。
                        // 当前架那一项**灰着**、仍照实画（`L-50`：可点却静默无反应是最坏的一种）；
                        // 库里只有一个架 ⇒ 给一句人话，而不是一个空菜单（空菜单会被读成「没做」）。
                        Menu(L(NotebookShelfMovePrompt.menuTitleKey)) {
                            let targets = appState.notebookShelfMoveTargets(for: notebook.uid)
                            if NotebookShelfMovePrompt.hasDestination(targets) {
                                ForEach(targets) { target in
                                    shelfMoveButton(for: target, notebookUid: notebook.uid)
                                }
                            } else {
                                Button(L(NotebookShelfMovePrompt.noTargetKey)) {}
                                    .disabled(true)
                            }
                        }
                        .accessibilityIdentifier("notes-move-notebook-menu-\(notebook.uid)")
                        Divider()
                        reorderButtons(kind: .notebook, uid: notebook.uid)
                        Divider()
                        Button(L(ContainerRemovalPrompt.menuTitleKey(for: .notebook))) {
                            appState.requestContainerRemoval(kind: .notebook, uid: notebook.uid, name: notebook.name)
                        }
                        .accessibilityIdentifier("notes-remove-notebook-\(notebook.uid)")
                    }
                    // **落点**（队列 `L-97` 界面半第五片）：只有笔记本行接拖进来的笔记 ——
                    // 架行与「全部」行**不接**（契约 §2.12 第 1 条：笔记不直接属于架；
                    // 接了就表示能挂在架上）。载荷解码与「已在目标里的不写库」都在 AppState 一处。
                    .dropDestination(for: String.self) { items, _ in
                        Task { await appState.handleNoteDrop(payload: items.first, into: notebook.uid) }
                        return true
                    }
                }
            }
            // **标签**（队列 `L-184` 第二片）：一个标签横跨各笔记本，所以它是**跨笔记本的范围**
            // （与印象笔记侧栏的标签栏同形）。清单与条数都由 Core 给
            // （`NotesNavigation.tags(in:)` —— 「一个标签下有多少条」只此一种算法），这里只画。
            // 一条标签都没有时**整段不出现**（不画一个空标题：那会被读成「这个功能没做」）。
            let tags = appState.notesNavigation.tags(in: appState.notes)
            if !tags.isEmpty {
                Divider()
                    .padding(.vertical, Spacing.xs)
                Text(L(.notesTagsSection))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .padding(.horizontal, Spacing.s)
                    .accessibilityIdentifier("notes-tags-section")
                ForEach(tags, id: \.tag) { entry in
                    row(
                        scope: .tag(entry.tag),
                        systemImage: "tag",
                        title: entry.tag,
                        count: entry.count,
                        indent: 0,
                        identifier: "notes-scope-tag-\(entry.tag)"
                    )
                }
            }
        }
        .accessibilityIdentifier("notes-container-tree")
        // **容器编辑弹框**（队列 `L-97` 界面半第四片）：新建与重命名共用这一个框（标题由模型按模式给），
        // 「确定」的灰着读的是 `containerEditNameIsAcceptable` 这**同一个判据**（`L-50`：两处各写一遍必分家）。
        .alert(
            appState.containerEditTitle,
            isPresented: Binding(
                get: { appState.pendingContainerEdit != nil },
                // 按 ESC / 点框外 = 退出口：只收掉请求，库一个字节不动。
                set: { presented in if !presented { appState.cancelContainerEdit() } }
            )
        ) {
            TextField(L(NotebookCreation.namePlaceholderKey), text: $appState.containerEditName)
            Button(L(ContainerEditPrompt.confirmKey)) {
                appState.confirmContainerEdit()
            }
            .disabled(!appState.containerEditNameIsAcceptable)
            Button(L(ContainerEditPrompt.cancelKey), role: .cancel) {
                appState.cancelContainerEdit()
            }
        }
        // **删除确认框**（队列 `L-97` ③）：动作与顺序**由模型给**（`ContainerRemovalPrompt.confirmActions`
        // 是唯一出处），影响面那句也由 `AppState.pendingContainerRemovalMessage` 一处生成 ——
        // 界面只负责画。别自己硬写三个按钮：规则一改就有两处不一致（`L-172` 同一课）。
        .confirmationDialog(
            L(ContainerRemovalPrompt.titleKey, appState.pendingContainerRemoval?.containerName ?? ""),
            isPresented: Binding(
                get: { appState.pendingContainerRemoval != nil },
                // 按 ESC / 点框外 = 「取消」：只收掉请求，库一个字节不动。
                set: { presented in if !presented { appState.cancelContainerRemoval() } }
            ),
            titleVisibility: .visible,
            presenting: appState.pendingContainerRemoval
        ) { request in
            ForEach(request.actions, id: \.self) { action in
                Button(L(ContainerRemovalPrompt.titleKey(for: action, kind: request.kind)), role: role(for: action)) {
                    appState.resolveContainerRemoval(action)
                }
            }
        } message: { _ in
            Text(appState.pendingContainerRemovalMessage ?? "")
        }
    }

    /// 排序（队列 `L-97` 界面半第四片）：两个方向都由 Core 的 `ContainerReorder.canMove` 判
    /// 「这一步走不走得动」—— 已在最前 / 已在最后时那一项**灰着**（`L-50` 的口径：可点却无反应
    /// 是最坏的一种；方向本身就把理由说清了，不必再写一句）。规则与落库共用一个答案。
    @ViewBuilder
    private func reorderButtons(kind: NotebookContainerKind, uid: String) -> some View {
        ForEach(ContainerReorderDirection.allCases, id: \.self) { direction in
            Button(L(direction.titleKey)) {
                Task { await appState.moveContainer(kind: kind, uid: uid, direction: direction) }
            }
            .disabled(!appState.canMoveContainer(kind: kind, uid: uid, direction: direction))
            .accessibilityIdentifier("notes-reorder-\(uid)-\(direction.rawValue)")
        }
    }

    /// 跨架移动的一项（队列 `L-97` 界面半第六片 = 落法 ① 的第四格）：清单由 Core 给
    /// （`NotebookShelfMovePrompt`），这里只画；当前架那一项**灰着**、仍照实画出来
    /// （`L-50`：可点却静默无反应是最坏的一种），后缀「（当前架）」也来自语言表。
    @ViewBuilder
    private func shelfMoveButton(for target: NotebookShelfMoveTarget, notebookUid: String) -> some View {
        Button(target.isCurrent ? target.name + L(NotebookShelfMovePrompt.currentMarkKey) : target.name) {
            Task { await appState.moveNotebook(uid: notebookUid, toShelf: target.id) }
        }
        .disabled(!target.isSelectable)
        .accessibilityIdentifier("notes-move-notebook-to-shelf-\(target.id)")
    }

    /// 动作 → 按钮角色：破坏档给破坏色，「取消」是退出口；默认档（移到默认容器）是**普通**按钮
    /// —— 它不删任何东西，把它画成红色会让用户在两个都像破坏的动作里挑一个。
    private func role(for action: ContainerRemovalAction) -> ButtonRole? {
        switch action {
        case .moveToDefault: return nil
        case .deleteTogether: return .destructive
        case .cancel: return .cancel
        }
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
            // **栏头搬走了**（队列 `L-184` 三栏重排）：「笔记」这个标题与条数进了中栏栏头
            // （`NotesListView`），「新建」进了顶栏（`NotesAreaView`）—— 同一个窗口里不许出现
            // 两处「新建」，否则两个按钮的灰 / 亮迟早各有一套判据（`L-50` 的老毛病）。
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

/// **笔记区 = 顶栏 + 三栏**（队列 `L-184`）：需求提出者 2026-10-04 原话「macOS版界面布局可以
/// 借鉴印象笔记PC端布局」—— **结构借鉴，不抄视觉**（品牌色与既有像素判据一字未动）。
///
/// 四块（左栏由 `MainWindow` 的侧栏承载，可折叠）：
///   · **顶栏** = 搜索框（作用域 = 当前范围 / 全部笔记本）+ 新建；
///   · **中栏** = `NotesListView`（列表：标题 / 摘要两行 / 相对时间）；
///   · **右栏** = `NotesEditorView`（正文 / 编辑器，读写同屏）；
///   · **左栏** = `NotesContainerTreeView`（笔记本架 → 笔记本两级树）。
///
/// 三条口径：
///  ① **搜索只有一处**：搬上来之后侧栏 / 中栏都不再有第二个搜索框 —— 两个框各自绑一个词时，
///     「用户看到的列表到底听谁的」没有答案（`L-44` 那一族的同一个教训）；
///  ② **范围开关跟着搜索框**：`notesSearchScope` 只对检索那条路起作用（`L-97` ⑤），
///     所以它必须画在搜索框旁边，而不是画在导航那一栏里；
///  ③ **中栏 / 右栏宽度可拖**（`HSplitView`）：三栏里最该由用户决定的就是「列表多宽、正文多宽」；
///     左栏的折叠与宽度归 `NavigationSplitView`（`L-184` ①「左栏可折叠」）。
struct NotesAreaView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            // **两屏各是一套三栏**（队列 `L-100` 界面半第一片）：`FR-NOTE-36` 要「各自入口与列表」，
            // 所以待办不塞进笔记列表，而是同一副骨架下的另一屏。**两个 `HSplitView` 各写一遍**
            // 而不是在它内部 `switch`：`HSplitView` 的成员必须是它直接的子视图，
            // 套一层条件视图会把两栏挤成一栏（布局当场坏掉）。
            if appState.notesModule == .todos {
                HSplitView {
                    TodoListView()
                        .frame(minWidth: 220, idealWidth: 300, maxWidth: 520)
                    TodoEditorView()
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    NotesListView()
                        .frame(minWidth: 220, idealWidth: 300, maxWidth: 520)
                    NotesEditorView()
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surface(.content))
        .accessibilityIdentifier("notes-area")
        // **检索走库**（队列 L-44）：搜索框里变一个字就重算一次。`.task(id:)` 在 id 变化时会取消
        // 上一次任务；`AppState.searchNotes()` 里还有一道「结果过期就丢」的守卫，打字比查库快
        // 也不会把旧结果盖上来。挂在**区根**（搜索框现在在顶栏，不在中栏）。
        .task(id: appState.notesQuery) {
            await appState.searchNotes()
        }
    }

    /// 顶栏：**屏切换**（笔记 / 待办）+ 搜索 + 范围 + 新建（`L-184` ④；`L-100` 加了第一枚）。
    ///
    /// 搜索那一档只在笔记屏出现：待办的**本地检索**属 `FR-NOTE-37`，它的口径还在契约半
    /// ⇒ 这一屏现在**不给**一个搜不出东西的搜索框（`L-50` 同族：可点却无反应比没有更糟）。
    /// 「新建」仍是同一个词、同一位置 —— 建的是什么由当前那一屏决定。
    private var topBar: some View {
        HStack(spacing: Spacing.s) {
            Picker(L(.notesTitle), selection: Binding(
                get: { appState.notesModule },
                set: { appState.setNotesModule($0) }
            )) {
                ForEach(NotesModule.allCases, id: \.self) { module in
                    Text(L(module.titleKey)).tag(module)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("notes-module-switch")
            if appState.notesModule == .notes {
                TextField(L(.notesSearchPlaceholder), text: $appState.notesQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .accessibilityIdentifier("notes-search-field")
                Picker(L(.notesSearchScopeTitle), selection: $appState.notesSearchScope) {
                    Text(L(.notesSearchScopeCurrent)).tag(NotesSearchScope.current)
                    Text(L(.notesSearchScopeAll)).tag(NotesSearchScope.all)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("notes-search-scope")
            }
            Spacer(minLength: Spacing.s)
            Button(L(.notesNew)) {
                switch appState.notesModule {
                case .notes: appState.beginNewNote()
                case .todos: appState.beginNewTodo()
                }
            }
            .accessibilityIdentifier("notes-new")
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
    }
}

/// **待办那一屏的左栏**（队列 `L-100` 界面半第一片）。
///
/// 只有一行「全部待办」：**分组与筛选**（今天 / 本周 / 已过期 / 无截止）与**三档排序**属
/// `FR-NOTE-37`，它们的口径在**契约半**（契约层所有者 `bluewhale`，派单 `T-20261004-002` 在办）
/// ⇒ 契约落笔前本侧**不自行发明一套分组**。如实登记：这一栏现在只回答「有没有这一屏、一共几条」。
struct TodoNavigationView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checklist")
                    .font(Theme.font(.caption))
                    .frame(width: 14)
                Text(L(.todoAll))
                    .font(Theme.font(.body))
                    .lineLimit(1)
                Spacer(minLength: Spacing.xs)
                // 条数与清单里两段之和**不是两处判断**：这里数的就是那一屏的分区入口。
                Text("\(appState.todos.count)")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            }
            .padding(.vertical, Spacing.hair)
            .padding(.horizontal, Spacing.s)
            .contentShape(Rectangle())
            .background(Theme.surface(.panel))
            .accessibilityIdentifier("todos-scope-all")
            Spacer()
        }
        .accessibilityIdentifier("todos-navigation")
    }
}

/// **待办清单**（队列 `L-100` 界面半第一片 · `FR-NOTE-36`）：中栏。
///
/// 三条口径：
///  ① **分区 / 段序 / 段内顺序全归 Core**（`TodoPresentation.sections`：未完成在前、已完成在后，
///     **两段恒在** —— 空态与段头计数靠 `count` 一处判）；视图不自己 `filter` 两遍；
///  ② **已完成默认折叠**（`FR-NOTE-36` 原文）：默认值由 Core 给（`isCollapsedByDefault`），
///     这一点是**界面状态**（住 `AppState`），Core 不持有它；
///  ③ **截止档位归 Core**（`dueState`：**逾期 = 截止时刻已经过去**）—— 视图只把「哪一档」
///     翻成一枚颜色 + 语言表里那句话，自己不比 `Date`（否则「今晨那一点算不算逾期」会有两个答案）。
struct TodoListView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(L(.notesModuleTodos))
                    .font(Theme.font(.title))
                Text("\(appState.todos.count)")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                Spacer(minLength: Spacing.xs)
            }
            .padding(.horizontal, Spacing.s)
            if appState.todos.isEmpty {
                Text(L(.todosEmpty))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .padding(Spacing.s)
                Spacer()
            } else {
                List {
                    ForEach(appState.todoSections, id: \.kind) { section in
                        Section {
                            // 已完成那一段折叠着时不画行（顺序与段头都还在 —— 段头就是那个开关）。
                            if section.kind != .completed || appState.todoCompletedExpanded {
                                ForEach(section.todos) { todo in
                                    row(todo)
                                }
                            }
                        } header: {
                            header(section)
                        }
                    }
                }
                .accessibilityIdentifier("todos-list")
            }
        }
        .padding(.vertical, Spacing.s)
        .accessibilityIdentifier("todos-list-pane")
        .scrollContentBackground(.hidden)
        .background(Theme.surface(.sidebar))
    }

    /// 段头：段名 + 条数（空段也照画 —— `FR-NOTE-36` 的分区是**结构**，不是「有没有内容」）；
    /// 已完成那一段的名就是一个**折叠开关**（默认折叠的默认值来自 Core）。
    @ViewBuilder
    private func header(_ section: TodoSection) -> some View {
        HStack(spacing: Spacing.xs) {
            if section.kind == .completed {
                Image(systemName: appState.todoCompletedExpanded ? "chevron.down" : "chevron.right")
                    .font(Theme.font(.caption))
            }
            Text(L(section.kind.titleKey))
                .font(Theme.font(.caption))
            Text("\(section.count)")
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard section.kind == .completed else { return }
            appState.todoCompletedExpanded.toggle()
        }
        .accessibilityIdentifier(section.kind == .completed ? "todos-section-completed" : "todos-section-open")
    }

    /// 一行：完成态那一枚（点它就是完成 / 重开）+ 标题 + 截止档位 + 优先级 + 标签。
    /// 截止档位与标题都**只从 Core 拿**（`dueState` / `title`），颜色与句子在这一层。
    @ViewBuilder
    private func row(_ todo: Todo) -> some View {
        HStack(spacing: Spacing.xs) {
            Button {
                Task { await appState.toggleTodoDone(todo) }
            } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(Theme.font(.body))
                    .foregroundStyle(todo.done ? Theme.status(.success) : Theme.text(.secondary))
            }
            .buttonStyle(.plain)
            .help(L(todo.done ? .todoMarkOpen : .todoMarkDone))
            .accessibilityIdentifier("todo-done-toggle-\(todo.id.uuidString)")
            VStack(alignment: .leading, spacing: 2) {
                Text(TodoPresentation.title(todo) ?? L(.notesUntitled))
                    .font(Theme.font(.body))
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text(L(TodoPresentation.dueState(todo.dueAt).key))
                        .font(Theme.font(.caption))
                        .foregroundStyle(dueTone(todo.dueAt))
                    if todo.priority != .normal {
                        Text(L(todo.priority.key))
                            .font(Theme.font(.caption))
                            .foregroundStyle(todo.priority == .high ? Theme.status(.warning) : Theme.text(.secondary))
                    }
                    if !todo.tags.isEmpty {
                        Text(todo.tags.joined(separator: " "))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: Spacing.xs)
        }
        .contentShape(Rectangle())
        .onTapGesture { appState.edit(todo) }
        .contextMenu {
            // 与那一枚圆点说的是同一件事、两种措辞（当前不是完成 ⇒「标记完成」）——
            // 写库与重读都在 `AppState.toggleTodoDone` 一处。
            Button(L(todo.done ? .todoMarkOpen : .todoMarkDone)) {
                Task { await appState.toggleTodoDone(todo) }
            }
            Divider()
            Button(L(.todoDelete), role: .destructive) {
                Task { await appState.deleteTodo(id: todo.id) }
            }
        }
        .listRowBackground(appState.todoEditingID == todo.id ? Theme.surface(.panel) : Color.clear)
        .accessibilityIdentifier("todo-row-\(todo.id.uuidString)")
    }

    /// 档位 → 颜色：**逾期**是危险色（`FR-NOTE-38` 的「显式标识」），今天最高对比，其余次级。
    private func dueTone(_ dueAt: Date?) -> Color {
        switch TodoPresentation.dueState(dueAt) {
        case .overdue: return Theme.status(.danger)
        case .today: return Theme.text(.primary)
        case .none, .tomorrow, .later: return Theme.text(.secondary)
        }
    }
}

/// **待办详情 / 编辑器**（队列 `L-100` 界面半第一片）：右栏。
///
/// 与笔记编辑器同一条形状（`L-50`）：**「保存」的灰着与 `AppState.saveTodoFromEditor()` 的守卫
/// 读同一句**（`todoEditorHasContent`，唯一出处）。
/// 「有截止时间」那枚开关就是**清截止的显式动作**（关掉 ⇒ `dueAt` 写 `nil`）；
/// 完成态**不在这里**（它只有 `setDone` 一条写路 —— 编辑标题不许把已完成改回未完成）。
struct TodoEditorView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            TextField(L(.todoTitlePlaceholder), text: $appState.todoEditorTitle)
                .textFieldStyle(.roundedBorder)
            Toggle(isOn: $appState.todoEditorHasDue) {
                Text(L(.todoHasDueLabel))
                    .font(Theme.font(.caption))
            }
            .accessibilityIdentifier("todo-has-due")
            if appState.todoEditorHasDue {
                DatePicker(
                    L(.todoDueLabel),
                    selection: $appState.todoEditorDueAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .accessibilityIdentifier("todo-due-picker")
            }
            Picker(L(.todoPriorityLabel), selection: $appState.todoEditorPriority) {
                ForEach(TodoPriority.allCases, id: \.self) { priority in
                    Text(L(priority.key)).tag(priority)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("todo-priority")
            TextField(L(.notesTagsPlaceholder), text: $appState.todoEditorTags)
                .textFieldStyle(.roundedBorder)
                .font(Theme.font(.caption))
            HStack(spacing: Spacing.s) {
                Button(L(.notesSave)) {
                    Task { await appState.saveTodoFromEditor() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!appState.todoEditorHasContent)
                .accessibilityIdentifier("todo-save")
                // 「删除」只在这一条**已经在库里**时才画（新建态没有可删的东西 —— 画一枚按不动的按钮
                // 就是 `L-50` 那一课）。
                if let id = appState.todoEditingID {
                    Button(L(.todoDelete), role: .destructive) {
                        Task { await appState.deleteTodo(id: id) }
                    }
                    .accessibilityIdentifier("todo-delete")
                }
                Spacer()
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface(.content))
        .accessibilityIdentifier("todo-editor")
    }
}

/// **当前事件上的修饰键**（队列 `L-97` 界面半第五片）：Core 不认识 AppKit，这道桥住在视图这侧。
/// 只认两个 —— ⌘（切换）与 ⇧（连选）；⌥ / ⌃ **不参与**，免得把别的快捷键按成多选。
/// 为什么读「当前事件」而不是挂两个手势：普通手势与修饰手势会**同时**触发（⌘ 点既加选、
/// 又在编辑器里换了一条），多选就成了一个用不成的功能。
private extension NoteSelectionModifiers {
    static var currentEvent: NoteSelectionModifiers {
        let flags = NSEvent.modifierFlags
        var modifiers: NoteSelectionModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
