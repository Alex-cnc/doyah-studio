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
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("todo-calendar-view-switch")
            Spacer(minLength: Spacing.xs)
            Button {
                appState.shiftTodoCalendar(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .help(L(.todoCalendarPrevious))
            .accessibilityIdentifier("todo-calendar-previous")
            Text(periodTitle)
                .font(Theme.font(.caption))
                .lineLimit(1)
                .accessibilityIdentifier("todo-calendar-period")
            Button {
                appState.shiftTodoCalendar(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .help(L(.todoCalendarNext))
            .accessibilityIdentifier("todo-calendar-next")
            Button(L(.todoCalendarToday)) {
                appState.todoCalendarGoToday()
            }
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

    /// 一格：日号 + 任务点（逾期那些天画告警色）。选中 / 今天是两种**不同的**标记
    /// （选中 = 一块底色、今天 = 日号加粗对比），两件事各画各的，不互相顶掉。
    @ViewBuilder
    private func cellView(_ cell: TodoCalendarCell) -> some View {
        let day = appState.todoCalendarDays[cell.date]
        let isSelected = appState.isTodoCalendarSelected(cell)
        let isToday = appState.isTodoCalendarToday(cell)
        VStack(spacing: Spacing.hair) {
            Text("\(cell.dayOfMonth)")
                .font(isToday ? Theme.font(.bodyStrong) : Theme.font(.caption))
                .foregroundStyle(cell.inMonth ? Theme.text(.primary) : Theme.text(.tertiary))
            taskDots(day)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .top)
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
            }
            .padding(.horizontal, Spacing.s)
            if appState.todoCalendarSelectedDayHasTasks {
                // **与清单那一屏同一个渲染件**（段头 / 分区 / 行都只有一处）——
                // 于是「改期后清单同步」这件事在形状上就成立。
                TodoSectionListView(sections: appState.todoCalendarSelectedDaySections)
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

    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            ForEach(sections, id: \.kind) { section in
                Section {
                    // 已完成那一段折叠着时不画行（顺序与段头都还在 —— 段头就是那个开关）。
                    if section.kind != .completed || appState.todoCompletedExpanded {
                        ForEach(section.todos) { todo in
                            TodoRowView(todo: todo)
                        }
                    }
                } header: {
                    header(section)
                }
            }
        }
        .accessibilityIdentifier("todos-list")
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
}

/// 一行待办（清单与日历共用的那一行）：完成态那一枚（点它就是完成 / 重开）+ 标题 + 截止档位
/// + 优先级 + 标签；右键 = 标记完成 / **改期** / 删除。
///
/// 截止档位与标题都**只从 Core 拿**（`dueState` / `title`），颜色与句子在这一层。
struct TodoRowView: View {

    let todo: Todo

    @EnvironmentObject private var appState: AppState

    var body: some View {
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
            Button(L(.todoReschedule)) { appState.beginReschedule(todo) }
            Divider()
            Button(L(.todoDelete), role: .destructive) {
                Task { await appState.deleteTodo(id: todo.id) }
            }
        }
        // 在 `List` 里才生效（日历那一屏的当天任务也是一个 `List`）——
        // 换个滚动容器时它是空操作，不是「另一种行」。
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

/// **改期弹框**（队列 `L-100` 界面半第二片 · `FR-NOTE-38` 的「日历上直接改期」）。
///
/// 只说一件事：改到哪一刻。落库由 `AppState.applyReschedule()` 走既有的 `upsert` 写路
/// （`dueAt` 换新值、`updatedAt` 刷新），完成态不在这里碰 —— 它只有 `setDone` 一条写路。
struct TodoRescheduleSheet: View {

    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L(.todoReschedule))
                .font(Theme.font(.title))
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
                Button(L(.commonCancel)) { appState.cancelReschedule() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("todo-reschedule-cancel")
                Button(L(.commonSave)) {
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
