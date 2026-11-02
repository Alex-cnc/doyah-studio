import SwiftUI
import DoyahCore

/// **待办那一屏的中栏**（队列 `L-100` 界面半第二片；`L-184` ⑤「中栏在清单 / 日历间切」）。
///
/// 三条口径：
///  ① **两档看的是同一份 `todos`**（`FR-NOTE-39`：清单是唯一写入面、日历只是视图）——
///     切档只换画法，不重读库、也不同步任何东西；两档各持一份内存态就是「日历上有、清单上没有」；
///  ② **切档条在最上面**：清单屏的标题（`TodoListView`）与日历屏的工具条各自留在自己那一屏里，
///     这一根只管「看哪一种」；
///  ③ **改期弹框挂在这一层**：清单与日历两条路上的「改期…」共用同一张弹框（`AppState` 里那份草稿
///     只有一处写入口），不至于出现「从日历改期能弹、从清单改期没反应」。
struct TodoPaneView: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            modeBar
            Divider()
            if appState.todoPane == .calendar {
                TodoCalendarPane()
            } else {
                TodoListView()
            }
        }
        .accessibilityIdentifier("todo-pane")
        .sheet(item: $appState.todoRescheduleDraft) { _ in
            TodoRescheduleSheet()
        }
    }

    /// 清单 / 日历切换器（档位空间与名字都来自 Core：`TodoPane`）。
    ///
    /// **本片保留的 1 处分段条**（判据①「3 → ≤2」里留下的那一档，理由写在这儿）：
    /// 它答的是「**看哪一屏**」——模式，不是取值；与笔记屏行末那一枚「笔记 / 待办」
    /// （`NotesAreaView.moduleSwitch`）是同一种东西。同一屏里「选一个值」的选择器
    /// （月 / 周、筛选）本片一律改**下拉菜单**（片 `N2-2`「与 SQL 编辑区同一设计语言」）。
    private var modeBar: some View {
        HStack(spacing: Spacing.xs) {
            Picker(L(.notesModuleTodos), selection: Binding(
                get: { appState.todoPane },
                set: { appState.setTodoPane($0) }
            )) {
                ForEach(TodoPane.allCases, id: \.self) { pane in
                    Text(L(pane.key)).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("todo-pane-switch")
            Spacer(minLength: Spacing.xs)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
    }
}

/// **日历那一屏**（队列 `L-100` 界面半第二片 · `FR-NOTE-38`）：中栏。
///
/// 三条口径：
///  ① **一格是哪一天、哪些天有任务，全归 Core**（`TodoCalendar`）—— 本文件只把格子画出来、
///     把点翻成颜色；自己排一遍日历就会出现「月视图有、周视图没有」（那一课写在 `TodoCalendar` 头上）；
///  ② **日历不写库**：这一屏只读 `AppState.todos`（同一份清单）。完成 / 重开走 `setDone`、
///     改期走 `upsert` —— 两条既有写路，日历**不新开第三条**；
///  ③ **点某天看当天任务**：当天任务用**清单那一屏同一个** `TodoSectionListView`（同一行、
///     同一分区），所以「改期后清单同步」在形状上就成立（两处读的是同一份数据）。
struct TodoCalendarPane: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            toolbar
            grid
            Divider()
            selectedDay
        }
        .padding(.vertical, Spacing.s)
        .accessibilityIdentifier("todo-calendar-pane")
        .background(Theme.surface(.sidebar))
    }

    // MARK: - 工具条（月 / 周 + 翻页 + 回来 + 今天）

    /// **日历那一屏的工具条**（片 `N2-2`「与 SQL 编辑区同一设计语言」）：
    ///   · 「月 / 周」由**分段条**改**下拉**（判据①：TodoCalendarView 的分段条 3 → 1）——
    ///     它答的是「这一屏怎么画」这个**取值**，不是「看哪一屏」那个模式（模式那一条留在 `modeBar`）；
    ///   · 翻页两枚走**唯一出处**的 `ToolbarIconButton`（图标 + 固定 28 × 22 命中区 + 悬停提示），
    ///     与 SQL 编辑区工具条 / 笔记面操作栏是**同一个**它；
    ///   · 「今天」是带字的一枚（它是个**动作 + 目标**，纯图标说不清是"回到哪一天"）——
    ///     原样保留文字，另补一句与它同一句的悬停提示（判据②：图标 / 按钮都要说得出自己干什么）。
    private var toolbar: some View {
        HStack(spacing: Spacing.xs) {
            Picker(L(.todoPaneCalendar), selection: Binding(
                get: { appState.todoCalendarView },
                set: { appState.setTodoCalendarView($0) }
            )) {
                ForEach(TodoCalendarView.allCases, id: \.self) { view in
                    Text(L(view.key)).tag(view)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help(L(.todoPaneCalendar))
            .accessibilityIdentifier("todo-calendar-view-switch")
            Spacer(minLength: Spacing.xs)
            ToolbarIconButton(systemName: "chevron.left", help: L(.todoCalendarPrevious)) {
                appState.shiftTodoCalendar(-1)
            }
            .accessibilityIdentifier("todo-calendar-previous")
            Text(periodTitle)
                .font(Theme.font(.caption))
                .lineLimit(1)
                .accessibilityIdentifier("todo-calendar-period")
            ToolbarIconButton(systemName: "chevron.right", help: L(.todoCalendarNext)) {
                appState.shiftTodoCalendar(1)
            }
            .accessibilityIdentifier("todo-calendar-next")
            ToolbarIconButton(systemName: "calendar", help: L(.todoCalendarToday)) {
                appState.todoCalendarGoToday()
            }
            .help(L(.todoCalendarToday))
            .accessibilityIdentifier("todo-calendar-today")
        }
        .padding(.horizontal, Spacing.s)
    }

    /// 当前这一页的名字：月视图 = 年月；周视图 = 那一周周一那天。
    /// 文本由 `DateFormatter` 按**当前有效语言**排版（与 `L(...)` 同一条纪律：语言从同一处取，
    /// 不写死 —— 所以中文出「2026年10月」、英文出「October 2026」）。
    private var periodTitle: String {
        switch appState.todoCalendarView {
        case .month:
            return localizedDateText(appState.todoCalendarAnchor, template: "yMMMM")
        case .week:
            let anchor = appState.todoCalendarCells.first?.date ?? appState.todoCalendarAnchor
            return localizedDateText(anchor, template: "yMMMMd")
        }
    }

    // MARK: - 格子

    private var grid: some View {
        VStack(spacing: Spacing.hair) {
            weekdayHeader
            // 列数取 Core 的 `columns`（表头与格子同一个数 —— 各写一个 7 就会出现错位）。
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Spacing.hair),
                    count: TodoCalendar.columns
                ),
                spacing: Spacing.hair
            ) {
                ForEach(appState.todoCalendarCells, id: \.date) { cell in
                    cellView(cell)
                }
            }
        }
        .padding(.horizontal, Spacing.s)
    }

    /// 表头七列（键与列序都来自 `TodoCalendar.weekdayHeaderKeys`）。
    private var weekdayHeader: some View {
        HStack(spacing: Spacing.hair) {
            ForEach(Array(TodoCalendar.weekdayHeaderKeys.indices), id: \.self) { index in
                Text(L(TodoCalendar.weekdayHeaderKeys[index]))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 一格：日号 + **副条**（农历日 / 节气，片 `TD-CAL-2`）+ 任务点（逾期那些天画告警色）。
    /// 选中 / 今天是两种**不同的**标记（选中 = 一块底色、今天 = 日号加粗对比），
    /// 两件事各画各的，不互相顶掉。
    ///
    /// 副条两行的口径（`FR-NOTE-40` / `FR-NOTE-41`）：
    ///   · **农历日**每格都有（`LunarCalendar.dayInfo` 一处出；表外回 `nil` ⇒ 那一行不画，
    ///     不猜一个日子出来）；
    ///   · **节气**只有**交节那一天**那一行才出现（其余日子不画）—— 于是副条正是
    ///     「农历日 +（有则）当日节气」。
    ///
    /// 为什么拼装在这一层而不在 Core：Core 只出「哪个键」（`LunarDate` 的月名 / 日名键、
    /// `SolarTerm.key`），句子与拼法都在语言表里 —— 与 `TodoCalendar.weekdayHeaderKeys`
    /// 同一条纪律（Core 里出现中文，`check-core-localization` 那条棘轮会当场红）。
    @ViewBuilder
    private func cellView(_ cell: TodoCalendarCell) -> some View {
        let day = appState.todoCalendarDays[cell.date]
        let isSelected = appState.isTodoCalendarSelected(cell)
        let isToday = appState.isTodoCalendarToday(cell)
        let lunar = LunarCalendar.dayInfo(for: cell.date, calendar: .current)
        VStack(spacing: Spacing.hair) {
            Text("\(cell.dayOfMonth)")
                .font(isToday ? Theme.font(.bodyStrong) : Theme.font(.caption))
                .foregroundStyle(cell.inMonth ? Theme.text(.primary) : Theme.text(.tertiary))
            if let lunar {
                // 月名 / 日名各自一枚键，拼法由模板给（中文挨着写「八月廿八」、英文用「8/28」）。
                Text(L(.lunarDateTemplate, L(lunar.lunar.monthNameKey), L(lunar.lunar.dayNameKey)))
                    .font(Theme.font(.caption))
                    .foregroundStyle(cell.inMonth ? Theme.text(.secondary) : Theme.text(.tertiary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("todo-calendar-lunar-\(calendarDayIdentifier(cell.date))")
            }
            if let term = lunar?.term {
                Text(L(term.key))
                    .font(Theme.font(.caption))
                    .foregroundStyle(cell.inMonth ? Theme.accentColor : Theme.text(.tertiary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("todo-calendar-term-\(calendarDayIdentifier(cell.date))")
            }
            taskDots(day)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .top)
        .padding(.vertical, Spacing.hair)
        .background(
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(isSelected ? Theme.surface(.raised) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { appState.selectTodoCalendarDay(cell.date) }
        .help(cellHelp(day))
        .accessibilityIdentifier("todo-calendar-cell-\(calendarDayIdentifier(cell.date))")
    }

    /// 一天最多画三个点（再多也只是「很多」，具体几条在下面那一天里看）：
    /// **逾期**的那些天画危险色 —— 这就是 `FR-NOTE-38` 的「逾期显式标识」。
    @ViewBuilder
    private func taskDots(_ day: TodoDayTasks?) -> some View {
        HStack(spacing: Spacing.hair) {
            if let day, day.total > 0 {
                ForEach(Array(0..<min(day.total, 3)), id: \.self) { _ in
                    Image(systemName: "circle.fill")
                        .font(Theme.font(.caption))
                        .foregroundStyle(day.overdue > 0 ? Theme.status(.danger) : Theme.text(.secondary))
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 悬浮提示：这一天几条（句子里有数字槽，槽位与实参由语言表那一侧对账）。
    private func cellHelp(_ day: TodoDayTasks?) -> String {
        L(.todoCalendarDayCount, "\(day?.total ?? 0)")
    }

    // MARK: - 点中那一天的任务

    private var selectedDay: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(selectedDayTitle)
                    .font(Theme.font(.title))
                    .lineLimit(1)
                Spacer(minLength: Spacing.xs)
                // **「选中日」那两枚入口**（片 `TD-CAL-1` · 派单 `T-20261009-026`）：
                //   ① 新建待办 —— 截止预填**选中日 09:00**（摆草稿走 `AppState.newTodoOn(selectedDay:)`）；
                //   ② 写笔记   —— 切到笔记面并新开一篇（走 `AppState.writeNote()`）。
                // 形态与这一屏工具条那两枚**同族**（`ToolbarIconButton`：图标 + 悬停提示），
                // 于是这两枚也不必自己画第二套按钮。两枚都**只在选中了某一天时才画**：
                // 这一区是「选中日」的地盘，没选那天就没有「哪一天」可预填（日历的口径是
                // 「不替用户选一天」——`todoCalendarSelectedDay` 头注释），也就不该在这儿凭空给一个日子。
                if let day = appState.todoCalendarSelectedDay {
                    ToolbarIconButton(systemName: "plus", help: L(.todoCalendarNewTodo)) {
                        appState.newTodoOn(selectedDay: day)
                    }
                    .accessibilityIdentifier("todo-calendar-new-todo")
                    ToolbarIconButton(systemName: "square.and.pencil", help: L(.todoCalendarWriteNote)) {
                        appState.writeNote()
                    }
                    .accessibilityIdentifier("todo-calendar-write-note")
                }
            }
            .padding(.horizontal, Spacing.s)
            if appState.todoCalendarSelectedDayHasTasks {
                // **与清单那一屏同一个渲染件**（段头 / 分区 / 行都只有一处）——
                // 于是「改期后清单同步」这件事在形状上就成立。
                TodoSectionListView(
                    sections: appState.todoCalendarSelectedDaySections,
                    occurrenceDay: appState.todoCalendarSelectedDay
                )
            } else {
                Text(L(.todoCalendarNoDay))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .padding(Spacing.s)
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("todo-calendar-day")
    }

    /// 选中那一天的名字（本地化排版 —— 与工具条同一处口径）。
    private var selectedDayTitle: String {
        guard let day = appState.todoCalendarSelectedDay else { return "" }
        return localizedDateText(day, template: "MMMdEEE")
    }
}

/// **分段 + 段头 + 行**：清单那一屏与日历的「当天任务」共用的**同一个**渲染处。
///
/// 为什么抽出来：两处各画一遍行，迟早出现「行上多了个标记、另一处没有」——
/// 而两处各自的界面都是对的，只有用户会发现不一致。
struct TodoSectionListView: View {

    let sections: [TodoSection]

    /// 这些行是从**日历的某一天**画出来的（那一回的发生日）；清单那一屏 ⇒ `nil`。
    ///
    /// 为什么要传：重复任务的「改期」在日历上问的是「只改这一天还是整串」，而在清单里只有整串
    /// 那一条路 —— 两处问的不是同一件事，靠这一格区分，不在行里再判一次「我现在在哪一屏」。
    var occurrenceDay: Date? = nil

    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            ForEach(sections, id: \.kind) { section in
                Section {
                    // 已完成那一段折叠着时不画行（顺序与段头都还在 —— 段头就是那个开关）。
                    if section.kind != .completed || appState.todoCompletedExpanded {
                        ForEach(section.todos) { todo in
                            TodoRowView(todo: todo, occurrenceDay: occurrenceDay)
                        }
                    }
                } header: {
                    header(section)
                }
            }
        }
        .accessibilityIdentifier("todos-list")
    }

    /// 段头（→ `TodoRegionHeader`：与分组那一屏**共用同一份渲染** —— 各画一份就会出现
    /// 「折叠箭头只在一个屏上」）。
    @ViewBuilder
    private func header(_ section: TodoSection) -> some View {
        TodoRegionHeader(section: section)
    }
}

/// **分区段头**（一处渲染，两处用）：段名 + 条数（空段也照画 —— `FR-NOTE-36` 的分区是**结构**，
/// 不是「有没有内容」）；已完成那一段的名就是一个**折叠开关**（默认折叠的默认值来自 Core）。
///
/// 两处用 = 清单那一屏（`Section` 的 header）与**分组那一屏**（组内的**行**）：`Section` 不能嵌套，
/// 所以组内两区的段头只能当一行画。`identifierSuffix` 让两处的可访问性标识不撞车
/// （分组屏上会同时存在好几个段头）。
struct TodoRegionHeader: View {

    let section: TodoSection
    var identifierSuffix: String = ""

    @EnvironmentObject private var appState: AppState

    var body: some View {
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
        .accessibilityIdentifier(
            section.kind == .completed
                ? "todos-section-completed\(identifierSuffix)"
                : "todos-section-open\(identifierSuffix)"
        )
    }
}

/// 一行待办（清单与日历共用的那一行）：完成态那一枚（点它就是完成 / 重开）+ 标题 + 截止档位
/// + 优先级 + 标签；右键 = 标记完成 / **改期** / 删除。
///
/// 截止带与标题都**只从 Core 拿**（`TodoQuery.band` / `todo.title`），颜色与句子在这一层。
/// **逾期标识**（那枚危险色）另走 `TodoDue.isOverdue`（= 未完成 且 早于今天零点，契约 §3.13 第四条）
/// —— 分带不看完成态，标识只看未完成。
struct TodoRowView: View {

    let todo: Todo

    /// 这一行画在日历的**哪一天**（那一回的发生日）；清单那一屏 ⇒ `nil`。
    var occurrenceDay: Date? = nil

    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.todoInlineEditingID == todo.id {
            inlineEditor
        } else {
            readRow
        }
    }

    /// **只读那一行**（`FR-NTS-TODO-LIST-002` 判据①：五列都显示）。
    /// 五列 = 标题 / 截止 / 完成态 / 优先级 / 标签；**空值也有话说**（「无截止」「无标签」），
    /// 否则那一列在行上凭空消失，读的人会以为没有这一列。
    private var readRow: some View {
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
            VStack(alignment: .leading, spacing: Spacing.hair) {
                Text(TodoPresentation.title(todo) ?? L(.notesUntitled))
                    .font(Theme.font(.body))
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    // ② 截止时间（分带词；空 = 「无截止」）：点它 ⇒ 改期那张既有弹框
                    // —— 改期是一条**既有写路**，这里不新开第三条。
                    Button {
                        appState.beginReschedule(todo, on: occurrenceDay)
                    } label: {
                        Text(columnText(.dueAt))
                            .font(Theme.font(.caption))
                            .foregroundStyle(dueTone(todo))
                    }
                    .buttonStyle(.plain)
                    .help(L(.todoReschedule))
                    .accessibilityIdentifier("todo-cell-due-\(todo.id.uuidString)")
                    // ④ 优先级：点它 ⇒ 三档菜单 ⇒ 只改这一格（一次 `upsert`，不经过编辑面）。
                    Menu {
                        ForEach(TodoPriority.allCases, id: \.self) { priority in
                            Button {
                                Task { await appState.setTodoPriorityInline(todo, priority) }
                            } label: {
                                if priority == todo.priority {
                                    Label(L(priority.key), systemImage: "checkmark")
                                } else {
                                    Text(L(priority.key))
                                }
                            }
                        }
                    } label: {
                        Text(columnText(.priority))
                            .font(Theme.font(.caption))
                            .foregroundStyle(
                                todo.priority == .high ? Theme.status(.warning) : Theme.text(.secondary)
                            )
                    }
                    .menuStyle(.borderlessButton)
                    .help(L(.todoPriorityLabel))
                    .accessibilityIdentifier("todo-cell-priority-\(todo.id.uuidString)")
                    // ⑤ 标签：点它 ⇒ 就地改（那一行里有一个输入框）。
                    Button {
                        appState.beginTodoInlineEdit(todo)
                    } label: {
                        Text(columnText(.tags))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help(L(.todoInlineEditHint))
                    .accessibilityIdentifier("todo-cell-tags-\(todo.id.uuidString)")
                    // **重复标记**（`FR-NTS-TODO-LIST-001` 判据①的第四个字段）：只在真有规则时画，
                    // 名字交给悬停提示（一句话由 `TodoRepeatPresentation` 一处出）。
                    if let repeatRule = todo.repeatRule,
                       let repeatText = TodoRepeatPresentation.summary(
                           repeatRule, language: LocalizationManager.shared.effectiveLanguage
                       ) {
                        Image(systemName: "repeat")
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                            .help(repeatText)
                            .accessibilityLabel(Text(repeatText))
                            .accessibilityIdentifier("todo-repeat-badge-\(todo.id.uuidString)")
                    }
                }
            }
            Spacer(minLength: Spacing.xs)
            // 那一枚小铃铛（队列 `L-100` 落法 ④ 的界面入口半）：库里挂着提醒才画。
            // 一枚只回答「有没有」，**不回答「几点响」**（那件事在提醒区与到点那条通知里）。
            if appState.todoReminders[todo.id] != nil {
                Image(systemName: "bell.fill")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .help(L(.reminderRowBadge))
                    .accessibilityIdentifier("todo-reminder-badge-\(todo.id.uuidString)")
            }
        }
        .contentShape(Rectangle())
        // **点一行 ⇒ 只读详情**（片 `TD-LIST-1` · 派单 `T-20261009-026` 的 A6）：只把「看哪一条」
        // 记下来（`showTodoDetail`），**不进编辑态** —— 只读 ≠ 编辑。
        // **双击 ⇒ 就地改**（`FR-NTS-TODO-LIST-002` 判据①：五列都可改）：不离开清单、不换右栏。
        // 双击先注册：单击仍是「看」。
        .onTapGesture(count: 2) { appState.beginTodoInlineEdit(todo) }
        .onTapGesture { appState.showTodoDetail(todo) }
        .contextMenu {
            // 「编辑」是**进写入面**的那条路（片 `TD-LIST-1`）：详情那一屏自己不带编辑控件，
            // 所以改这一件事必须在这儿留一个入口，否则「点开只剩看」就成了功能缺失。
            Button(L(.commonEdit)) { appState.edit(todo) }
            // 「就地改」= 不换右栏的那条路（判据①）；与上面那条说的是同一件事的两种做法。
            Button(L(.todoInlineEditHint)) { appState.beginTodoInlineEdit(todo) }
            Divider()
            // 与那一枚圆点说的是同一件事、两种措辞（当前不是完成 ⇒「标记完成」）——
            // 写库与重读都在 `AppState.toggleTodoDone` 一处。
            Button(L(todo.done ? .todoMarkOpen : .todoMarkDone)) {
                Task { await appState.toggleTodoDone(todo) }
            }
            Button(L(.todoReschedule)) { appState.beginReschedule(todo, on: occurrenceDay) }
            Divider()
            // **先确认再删**（片 `A5-DEL` · 派单 `T-20261009-038`）：这里只挂请求（与编辑面 / 左区顶部
            // 那两枚走**同一个**确认框），确认框那一头（`confirmNoteRemoval`）才是 `deleteTodo`。
            // 判据：点删除后条目数不变，直到确认（`TestsUISnapshot/NotesLayoutProbeTests.swift`）。
            // 改动前这里直连 `appState.deleteTodo(id:)` ⇒ 右键一下就落库。
            Button(L(.todoDelete), role: .destructive) {
                appState.requestTodoRemoval(id: todo.id)
            }
        }
        // 在 `List` 里才生效（日历那一屏的当天任务也是一个 `List`）——
        // 换个滚动容器时它是空操作，不是「另一种行」。
        // 编辑态与「右栏正显示的那一条」都点亮：用户总要知道**右边那份是在说哪一行**。
        .listRowBackground(
            appState.todoEditingID == todo.id || appState.todoDetailID == todo.id
                ? Theme.surface(.panel)
                : Color.clear
        )
        .accessibilityIdentifier("todo-row-\(todo.id.uuidString)")
    }

    /// 某一列的显示文本 —— **只走 Core 那一处**（`TodoInlinePresentation`）：分带词、优先级名字、
    /// 「无截止 / 无标签」两句都在那里，行上不自己拼第二套。
    private func columnText(_ field: TodoInlineField) -> String {
        TodoInlinePresentation.text(
            field, of: todo, window: appState.todoWindow,
            language: LocalizationManager.shared.effectiveLanguage
        )
    }

    /// **就地改那一行**（判据①的可改面）：五列在同一行里改完，提交时**一次写入**。
    ///
    /// 完成态不在这里面：它本来就是行首那一枚开关（一按即写 —— 那是 `setDone` 那一条写路），
    /// 再画一个同样的开关就是两个入口说同一件事。这里的四格 + 行首那一枚 = 五列都可改。
    private var inlineEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // ① 标题
            TextField(L(.todoTitlePlaceholder), text: $appState.todoInlineTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await appState.commitTodoInlineEdit() } }
                .accessibilityIdentifier("todo-inline-title")
            HStack(spacing: Spacing.xs) {
                // ② 截止时间（关掉 = **显式清掉**，与编辑面那枚开关同口径）
                Toggle(L(.todoDueLabel), isOn: $appState.todoInlineHasDue)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("todo-inline-due-toggle")
                if appState.todoInlineHasDue {
                    DatePicker("", selection: $appState.todoInlineDueAt, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .accessibilityIdentifier("todo-inline-due-picker")
                }
                // ④ 优先级
                Picker(L(.todoPriorityLabel), selection: $appState.todoInlinePriority) {
                    ForEach(TodoPriority.allCases, id: \.self) { priority in
                        Text(L(priority.key)).tag(priority)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityIdentifier("todo-inline-priority")
                Spacer(minLength: 0)
            }
            // ⑤ 标签（空格 / 逗号分隔，切分在 Core）
            TextField(L(.todoTagsNone), text: $appState.todoInlineTags)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("todo-inline-tags")
            HStack(spacing: Spacing.xs) {
                Button {
                    Task { await appState.commitTodoInlineEdit() }
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.plain)
                .help(L(.commonSave))
                .accessibilityLabel(Text(L(.commonSave)))
                .accessibilityIdentifier("todo-inline-commit")
                Button {
                    appState.cancelTodoInlineEdit()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help(L(.commonCancel))
                .accessibilityLabel(Text(L(.commonCancel)))
                .accessibilityIdentifier("todo-inline-cancel")
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Spacing.hair)
        .accessibilityIdentifier("todo-inline-editor-\(todo.id.uuidString)")
    }

    /// 带 → 颜色：**逾期**（未完成 且 早于今天零点）是危险色（`FR-NOTE-38` 的「显式标识」），
    /// 今天最高对比，其余次级 —— 判定只调 Core（`TodoDue` / `TodoQuery.band`），视图不比 `Date`。
    private func dueTone(_ todo: Todo) -> Color {
        let window = appState.todoWindow
        if TodoDue.isOverdue(todo, window: window) { return Theme.status(.danger) }
        switch TodoQuery.band(of: todo, window: window) {
        case .today: return Theme.text(.primary)
        case .overdue, .thisWeek, .later, .noDue: return Theme.text(.secondary)
        }
    }
}

/// **改期弹框**（队列 `L-100` 界面半第二片 · `FR-NOTE-38` 的「日历上直接改期」）。
///
/// 只说一件事：改到哪一刻。落库由 `AppState.applyReschedule()` 走既有的 `upsert` 写路
/// （`dueAt` 换新值、`updatedAt` 刷新），完成态不在这里碰 —— 它只有 `setDone` 一条写路。
struct TodoRescheduleSheet: View {

    @EnvironmentObject private var appState: AppState

    /// 这一条是**重复任务**、而且是从日历的某一天进的 ⇒ 必须先把「这一条 / 这一串」问清楚。
    ///
    /// 判据是「有没有那一回」（`draft.day`）而不是「有没有重复规则」：没有具体哪一天，
    /// 「只改这一天」这个选项就无从成立（`TodoOccurrenceEditor` 那时会如实退成整串）。
    private var showsScopeChoice: Bool {
        guard let draft = appState.todoRescheduleDraft, draft.day != nil else { return false }
        return appState.todos.first { $0.id == draft.id }?.repeatRule != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L(.todoReschedule))
                .font(Theme.font(.title))
            if showsScopeChoice {
                Text(L(.todoScopePrompt))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                Picker("", selection: Binding(
                    get: { appState.todoRescheduleDraft?.scope ?? .initial },
                    set: { appState.todoRescheduleDraft?.scope = $0 }
                )) {
                    ForEach(TodoRepeatEditScope.allCases, id: \.self) { scope in
                        Text(L(scope.key)).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("todo-reschedule-scope")
            }
            DatePicker(
                L(.todoDueLabel),
                selection: Binding(
                    get: { appState.todoRescheduleDraft?.dueAt ?? Date() },
                    set: { appState.todoRescheduleDraft?.dueAt = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .accessibilityIdentifier("todo-reschedule-picker")
            HStack(spacing: Spacing.s) {
                DialogActionButton(systemName: "xmark.circle", title: L(.commonCancel)) { appState.cancelReschedule() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("todo-reschedule-cancel")
                DialogActionButton(systemName: "square.and.arrow.down", title: L(.commonSave)) {
                    Task { await appState.applyReschedule() }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("todo-reschedule-save")
            }
        }
        .padding(Spacing.l)
        .frame(minWidth: 320, alignment: .leading)
        .accessibilityIdentifier("todo-reschedule-sheet")
    }
}

// MARK: - 日期文本（一处出处）

/// 本地化日期文本：`DateFormatter` 的 locale 取**当前有效语言**
/// （`LocalizationManager.shared.effectiveLanguage` —— 与 `L(...)` 同一处，不写死语言），
/// 模板交给 Foundation 排（中文出「2026年10月」、英文出「October 2026」，两边的年月次序不同）。
///
/// 为什么不塞进语言表：`2026年10月` 与 `October 2026` 的**次序**与**月名**都不同，
/// 一个带槽位的模板表达不了；让它按语言排版反而只有一处出处。
/// 探针要认这一句时，认的是 `todo-calendar-period` / `todo-calendar-day` 这两个标识。
private func localizedDateText(_ date: Date, template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = LocalizationManager.shared.effectiveLanguage.locale
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
}

/// 格子的标识后缀（`YYYY-MM-DD`）：**只给界面探针用**，不参与任何业务判断
/// （日期比较一律走 `TodoCalendar.calendarDay`）。
private func calendarDayIdentifier(_ date: Date) -> String {
    let calendar = Calendar.current
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
}

// MARK: - 清单的「组织与检索」（队列 `L-100` 组织与检索界面半）

/// **清单那一屏的工具条**：四条输入 —— **关键字检索**（本地，只看标题）/ 筛选（五档）/ 排序（三档）/
/// 分组（四档）。
///
/// 三条口径：
///  ① **档位空间全部来自 Core**（`TodoFilter.allCases` / `TodoSort.Order.allCases` /
///     `TodoGroupBy.allCases`）—— 界面里没有第二份「有哪几档」的清单（新增档位只改 Core 与语言表）；
///  ② **切档不碰数据**：三处都只改 `AppState` 上的**界面状态**，不重读库、不写库、不改任何一条任务
///     （`FR-NOTE-39` 的唯一事实源：清单与日历看的是同一份）—— 也正因如此，「切档」这件事
///     在盘上没有第二个可写之处；
///  ③ **句子只在语言表里**（`L(档位.key)`）：Core 出「哪一档」，界面出「那句话」。
struct TodoQueryBar: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // 筛选决定「有哪些行」，最常切 ⇒ 常驻一排。
            // **五档筛选改下拉**（片 `N2-2`）：它答的是「这一屏留哪些行」这个**取值** ——
            // 五档一排的分段条是工具条上最占宽的一件（本片把它收成下拉，判据①：
            // TodoCalendarView 的分段条 3 → 1）。档位空间仍全部来自 Core（`TodoFilter.allCases`）。
            Picker(L(.todoFilterLabel), selection: Binding(
                get: { appState.todoFilter },
                set: { appState.setTodoFilter($0) }
            )) {
                ForEach(TodoFilter.allCases, id: \.self) { filter in
                    Text(L(filter.key)).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .help(L(.todoFilterLabel))
            .accessibilityIdentifier("todo-filter-switch")
            // **本地关键字检索**（片 `TD-LIST-1` · 派单 `T-20261009-026` 的 B4）：与上面那一档筛选、
            // 下面那一排排序 / 分组**同一层** —— 它答的也是「这一屏留哪些行」，只是那个词由用户敲。
            // 判定在 Core（`TodoSearch`：只看标题、大小写不敏感、空词不过滤），本视图只把词绑上去；
            // **不新开屏、不加按钮**（与 `L-44`「搜索只有一处」同一条纪律：这一屏的检索入口就是这一格）。
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                TextField(L(.windowSearchPlaceholder), text: $appState.todoSearchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("todo-search-field")
            }
            // 排序 / 分组决定「这一屏怎么画」，各给一个下拉（标签可见 —— 少了标签就只剩
            // 「截止时间」这种答不出「这是哪条轴」的当前值，那一课写在 `L-166`）。
            HStack(spacing: Spacing.xs) {
                Picker(L(.todoSortLabel), selection: Binding(
                    get: { appState.todoSortOrder },
                    set: { appState.setTodoSortOrder($0) }
                )) {
                    ForEach(TodoSort.Order.allCases, id: \.self) { order in
                        Text(L(order.key)).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityIdentifier("todo-sort-switch")
                Picker(L(.todoGroupLabel), selection: Binding(
                    get: { appState.todoGroupBy },
                    set: { appState.setTodoGroupBy($0) }
                )) {
                    ForEach(TodoGroupBy.allCases, id: \.self) { groupBy in
                        Text(L(groupBy.key)).tag(groupBy)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityIdentifier("todo-group-switch")
                Spacer(minLength: Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.s)
        .accessibilityIdentifier("todo-query-bar")
    }
}

/// **归好堆的清单**（分组档 ≠ 不分组时那一屏）：一组一个 `Section`。
///
/// 三条口径：
///  ① **组的名字与条数来自 Core**（`TodoGroupKey.headerText` / `TodoGroup.total`）——
///     标签组显示标签本身（那是**用户数据**），其余去语言表；界面**不 `switch` 组键**
///     （新增一类组键时，改一处的人不会想到另一处）；
///  ② **组内仍是「未完成 / 已完成」两区**（`TodoGroup.sections` → 仍只有 `TodoPresentation.sections`
///     一处分区）：`Section` 不能嵌套，段头在这一屏是**组内的一行**（`TodoRegionHeader`，折叠开关仍在），
///     空的那一区连段头都不画（组头已经说了这个组有几条）；
///  ③ **界面不筛不排**：进来的是 `TodoQuery.board` 算好的一屏，本视图照着画
///     （自己 `filter` 一遍就是第二套口径）。
struct TodoGroupListView: View {

    let board: TodoBoard

    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            ForEach(board.groups, id: \.key) { group in
                Section {
                    rows(of: group)
                } header: {
                    header(group)
                }
            }
        }
        .accessibilityIdentifier("todos-group-list")
    }

    /// 组头：组的名字 + 组内条数。
    private func header(_ group: TodoGroup) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(group.key.headerText { L($0) })
                .font(Theme.font(.caption))
            Text("\(group.total)")
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
        }
        .accessibilityIdentifier("todos-group-header")
    }

    /// 组内：两区（未完成 / 已完成）的段头 + 行。
    @ViewBuilder
    private func rows(of group: TodoGroup) -> some View {
        ForEach(group.sections, id: \.kind) { section in
            if section.count > 0 {
                TodoRegionHeader(section: section, identifierSuffix: "-group")
                    .listRowBackground(Color.clear)
            }
            // 已完成折叠着时不画行 —— 判定与清单那一屏同源（那一枚总开关住 `AppState`）。
            if section.kind != .completed || appState.todoCompletedExpanded {
                ForEach(section.todos) { todo in
                    TodoRowView(todo: todo)
                }
            }
        }
    }
}
