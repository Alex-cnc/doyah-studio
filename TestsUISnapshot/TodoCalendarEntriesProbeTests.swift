import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **待办日历「选中日」那两枚入口**的 App 侧探针（片 `TD-CAL-1` · 派单 `T-20261009-026`）。
///
/// ## 判的是什么
///
/// 派单上那两条现场验：
///   ① **选中日直接新建** ⇒ 编辑面的截止 = **该日 09:00**（不是「今天」、也不是空）；
///   ② **选中日 →「写笔记」** ⇒ 新开一篇（切面那一半见下面的边界）。
///
/// 前门核验（`T-20261009-026` 的 C5 / E1）只判到「源码里有没有这两个词」（改前都是**零命中**）；
/// 「有」不等于「点下去真的是这个结果」。本探针把这两条在**真视图树**上跑成断言，并各留一张图
/// 给人判（`UISnapshot.writeBothLanguages` 落 `.build/ui-snapshots/`）。
///
/// ## 判据（可机械跑 · 每组都印读数）
///
/// · **甲 两枚入口在界面上**：渲染待办那一屏时这一遍 `L(...)` 取到的文案里**必须**有
///   「新建待办」/「写笔记」（中英各一遍）；把选中日撤掉再拍一遍，同两句**一条都不许出现** ——
///   正反两面由**渲染记录**判，不靠读源码；
/// · **乙 预填 = 选中日 09:00**：`newTodoOn(selectedDay:)` 之后读 `AppState` 那几格；同一支上带一枚
///   **对照件**（先走既有的 `beginNewTodo()` ⇒ 截止开关必须是关的），证明「带了日期」是这一片新加的；
/// · **丙 写笔记 ⇒ 新开一篇**：`notesModule` 在 `.notes`、三个编辑器字段全空、无内容、模式 `.edit`；
/// · **丁 源锚点**：`App/Views/TodoCalendarView.swift` 那两枚按钮的动作**就是**上面调的两个方法，
///   且这一屏**不出现 `NoteLibrary`**（第二枚也不许自己开一条写路）；
///   `App/AppState.swift` 里能逐字找到 `writeNote()` / `setNotesModule(.notes)` / `beginNewNote()`。
///
/// ## 边界（如实登记 · 先实测再写）
///
/// · **「切到待办那一屏」这一格在本探针里做不到**：`AppState.setNotesModule(.todos)` 会拉起
///   `reloadReminders()` / `refreshReminderPermission()`，而后者走 `SystemReminderDeliverer` →
///   `UNUserNotificationCenter.current()` —— 在 `swift test` 的宿主里 `mainBundle` 是
///   `…/usr/bin/xctest`（`bundleProxyForCurrentProcess` 为 nil）⇒ **ObjC 断言 · signal 6**
///   （本片实测两次：`App/ReminderNotifier.swift:95`；与 `NotesLayoutProbeTests` 头注释那条同族）。
///   所以待办那一屏按**它与生产同源的两栏**（`TodoPaneView` + `TodoEditorView`，即
///   `NotesAreaView` 在模块 = 待办时画的那两件）在探针里合起来拍；`writeNote()` 那一半在
///   `notesModule == .notes` 上跑（`setNotesModule` 的同值守卫让它成为空操作）——
///   **「切面」这一跳由源锚点（判据丁）判**：能逐字找到那两句，真手点归人工点验；
/// · **不判真鼠标点击**：SwiftUI 的图标按钮在离屏宿主里不落到 `NSView`，合成事件也不触发
///   SwiftUI 手势（`NotesLayoutProbeTests` 头注释那三条实测）。所以这里调的是**按钮接到的
///   同一个方法**，另用判据丁把「按钮 ⟷ 方法」那一环钉住；
/// · 不碰用户数据：笔记库由 `DOYAH_NOTES_DIR` 指到每轮清空的临时目录（没设就跳过）；
/// · 产物**不进快照清单**：图落 `.build/ui-snapshots/`（共享产物），`Scripts/check-doc-numbers.py`
///   读的是**全量跑凭证** `.build/ui-snapshots/full-run/` ⇒ 本探针不会搅动「张 / 组」那两条计数。
///
/// 跑法：`DOYAH_UI_SNAPSHOT=1 DOYAH_NOTES_DIR=<临时目录> swift test --filter TodoCalendarEntriesProbeTests`。
final class TodoCalendarEntriesProbeTests: XCTestCase {

    /// 宿主面积：与 `NotesLayoutProbeTests.areaSize` 同一个（三栏骨架里「中栏 + 右栏」那两栏）。
    private static let areaSize = CGSize(width: 1100, height: 700)

    /// 待办那一屏里**中栏**的三档宽度（照抄 `NotesAreaView.listPaneMin/Ideal/MaxWidth` 那三个值 ——
    /// 它们是 `private`，测试这边取不到；写在这儿只为说明「探针拍的还是那一栏的宽度」）。
    private static let todoPaneMinWidth: CGFloat = 132
    private static let todoPaneIdealWidth: CGFloat = 180
    private static let todoPaneMaxWidth: CGFloat = 300

    /// 选中那一天 = **2026-10-15**（固定日期）：它与「今天」（跑这一轮那天）分得开 ——
    /// 预填若错成「今天 09:00」，乙那一组当场红。
    private static let selectedYear = 2026
    private static let selectedMonth = 10
    private static let selectedDom = 15

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏渲染要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
        try XCTSkipIf(
            (ProcessInfo.processInfo.environment["DOYAH_NOTES_DIR"] ?? "").isEmpty,
            "本用例要碰笔记库（笔记那一屏读库）⇒ 必须在临时数据家里跑：`DOYAH_NOTES_DIR` 没设就跳过"
                + "（绝不允许往真实用户数据目录里写测试夹具）"
        )
    }

    // MARK: - 装配

    private typealias Host = (
        state: AppState, workspace: WorkspaceStore, tabs: WorkspaceTabsModel, terminal: TerminalModel
    )

    private func record(_ line: String) { print("🧪 TD-CAL-1 \(line)") }

    @MainActor
    private func makeHost() -> Host {
        let scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        return (
            state,
            WorkspaceStore.shared,
            WorkspaceTabsModel(
                store: WorkspaceHistoryStore(
                    fileURL: scratch.appendingPathComponent("td-cal-1-\(UUID().uuidString).json")
                )
            ),
            TerminalModel()
        )
    }

    /// 泵运行循环（`.task` / 异步续体都得让它们落地 —— 与 `NotesLayoutProbeTests.makeLive` 同一口径）。
    @MainActor
    private func pump(_ seconds: TimeInterval = 0.5) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    @MainActor
    private func environment<V: View>(_ view: V, _ host: Host) -> some View {
        view.snapshotEnvironment(
            state: host.state, workspace: host.workspace, tabs: host.tabs, terminal: host.terminal
        )
    }

    /// 待办那一屏（`NotesAreaView` 在模块 = 待办时画的那两栏：中栏 = 清单 / 日历，右栏 = 编辑器）。
    @MainActor
    @discardableResult
    private func renderTodoScreen(_ name: String, host: Host) throws -> UISnapshot.LanguagePair {
        try UISnapshot.writeBothLanguages(name, size: Self.areaSize) {
            environment(
                HSplitView {
                    TodoPaneView()
                        .frame(
                            minWidth: Self.todoPaneMinWidth,
                            idealWidth: Self.todoPaneIdealWidth,
                            maxWidth: Self.todoPaneMaxWidth
                        )
                    TodoEditorView()
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity),
                host
            )
        }
    }

    /// 笔记那一屏（真的 `NotesAreaView`，模块 = 笔记 —— 就是 `writeNote()` 之后落在的那一屏）。
    @MainActor
    @discardableResult
    private func renderNotesScreen(_ name: String, host: Host) throws -> UISnapshot.LanguagePair {
        try UISnapshot.writeBothLanguages(name, size: Self.areaSize) {
            environment(NotesAreaView(), host)
        }
    }

    /// 判据里拿「这一句应该长什么样」—— 与渲染那一遍**同一条路**（`beginHostLanguage` 包住）。
    @MainActor
    private func zh(_ key: LKey) -> String { UISnapshot.localizedText(.simplifiedChinese) { L(key) } }
    @MainActor
    private func en(_ key: LKey) -> String { UISnapshot.localizedText(.english) { L(key) } }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: - 判据

    /// 甲 / 乙 / 丙 / 丁（同一条状态链上依次走：撤选中 → 选中 10-15 → 新建待办 → 写笔记）。
    @MainActor
    func testCalendarSelectedDayEntriesPrefillNineAndOpenANewNote() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let load = try UISnapshot.applyLicense(.standard, to: host.state)
        XCTAssertEqual(load.entitlements.basis, .licensed, "临时许可证没落地 ⇒ 笔记那一屏读不到库")
        XCTAssertTrue(host.state.notesEnabled, "Standard 档必须带笔记能力（capabilities.notes）")

        // 夹具：选中那天挂两条任务（图上那格要有「有任务」的点，选中的是那一天才有内容可看）。
        let calendar = Calendar.current
        let selectedDay = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: Self.selectedYear, month: Self.selectedMonth, day: Self.selectedDom)
            ),
            "构造不出 \(Self.selectedYear)-\(Self.selectedMonth)-\(Self.selectedDom)"
        )
        let monthStart = try XCTUnwrap(
            calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDay))
        )
        host.state.todos = [
            Todo(title: "交季度报表", dueAt: selectedDay, priority: .high, tags: ["财务"]),
            Todo(title: "给骑友回消息", dueAt: selectedDay)
        ]
        host.state.todoPane = .calendar
        host.state.todoCalendarView = .month
        host.state.todoCalendarAnchor = monthStart
        XCTAssertNil(host.state.todoCalendarSelectedDay, "新宿主不该有选中日")
        XCTAssertEqual(host.state.notesModule, .notes, "模块初值该是笔记（切待办那一屏在本宿主里进不去，见头注释边界）")

        // ── 甲（反面）：**没选中任何一天** ⇒ 两枚入口一条都不画（这一区是「选中日」的地盘）。
        let withoutDay = try renderTodoScreen("probe-td-cal-1-entries-no-day", host: host)
        for (index, language) in UISnapshot.coverageLanguages.enumerated() {
            let seen = Set(withoutDay.records[index].localizedStrings)
            let expected = language == .simplifiedChinese
                ? [zh(.todoCalendarNewTodo), zh(.todoCalendarWriteNote)]
                : [en(.todoCalendarNewTodo), en(.todoCalendarWriteNote)]
            let leaked = expected.filter { seen.contains($0) }
            XCTAssertTrue(
                leaked.isEmpty,
                "没选中日却画出了 \(leaked) —— 这一区不该替用户认下某一天（\(language.rawValue) 那遍）"
            )
            record("🕳 无选中日（\(language.rawValue)）：\(expected.map { "「\($0)」" }.joined(separator: " / ")) 均未出现")
        }

        // ── 对照件：既有的「新建」不带截止（`beginNewTodo()` 那一支）—— 乙那组不是原本就有的行为。
        host.state.beginNewTodo()
        XCTAssertFalse(host.state.todoEditorHasDue, "既有「新建」不该带截止 —— 这一格是乙的对照件")
        record("🧷 对照件：既有「新建」的截止开关 = \(host.state.todoEditorHasDue)")

        // ── 点某一天（真入口：`selectTodoCalendarDay`）。
        host.state.selectTodoCalendarDay(selectedDay)
        pump(0.2)
        XCTAssertEqual(host.state.todoCalendarSelectedDay, calendar.startOfDay(for: selectedDay))

        // ── 甲（正面）：两枚入口真的画出来了（渲染记录里取到那两句）。图 ①。
        let withDay = try renderTodoScreen("probe-td-cal-1-entries-day-selected", host: host)
        for (index, language) in UISnapshot.coverageLanguages.enumerated() {
            let seen = Set(withDay.records[index].localizedStrings)
            let expected = language == .simplifiedChinese
                ? [zh(.todoCalendarNewTodo), zh(.todoCalendarWriteNote)]
                : [en(.todoCalendarNewTodo), en(.todoCalendarWriteNote)]
            let missing = expected.filter { !seen.contains($0) }
            XCTAssertTrue(
                missing.isEmpty,
                "选中 10-15 之后这两句没进渲染记录：\(missing)（\(language.rawValue) 那遍）"
            )
            record("🧩 选中日那两枚（\(language.rawValue)）：\(expected.map { "「\($0)」" }.joined(separator: " / ")) 都在")
        }

        // ── 乙 ① 新建待办：截止 = 选中日 09:00。图 ②。
        host.state.newTodoOn(selectedDay: host.state.todoCalendarSelectedDay)
        pump(0.2)
        let due = host.state.todoEditorDueAt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        XCTAssertTrue(host.state.todoEditorHasDue, "截止开关没打开 ⇒ 编辑面上看不到那个日期框")
        XCTAssertEqual(parts.year, Self.selectedYear)
        XCTAssertEqual(parts.month, Self.selectedMonth)
        XCTAssertEqual(parts.day, Self.selectedDom)
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertNotEqual(
            calendar.startOfDay(for: due), calendar.startOfDay(for: Date()),
            "预填的是「今天」—— 那不是「选中日」"
        )
        XCTAssertNil(host.state.todoEditingID, "新建态：还不该有 id（落库是编辑器那一条写路的事）")
        XCTAssertTrue(host.state.todoEditorTitle.isEmpty, "新建态标题该是空的")
        record(
            "🗓 ① 新建待办：截止 = " + String(
                format: "%04d-%02d-%02d %02d:%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                parts.hour ?? 0, parts.minute ?? 0
            ) + "（选中日 10-15；今天 = \(Calendar.current.component(.day, from: Date())) 号 —— 分得开）"
        )
        try renderTodoScreen("probe-td-cal-1-after-new-todo", host: host)

        // ── 丙 ② 写笔记：新开一篇（切面那一跳的边界见头注释）。图 ③。
        XCTAssertEqual(host.state.notesModule, .notes, "走之前该在笔记那一档")
        host.state.writeNote()
        pump()
        XCTAssertEqual(host.state.notesModule, .notes, "模块被挪走了")
        XCTAssertTrue(host.state.noteEditorTitle.isEmpty, "新开那一篇标题该是空的")
        XCTAssertTrue(host.state.noteEditorBody.isEmpty, "新开那一篇正文该是空的")
        XCTAssertTrue(host.state.noteEditorTags.isEmpty, "新开那一篇标签该是空的")
        XCTAssertFalse(host.state.noteEditorHasContent, "新开那一篇没有内容（保存键该是灰的）")
        XCTAssertEqual(host.state.editorMode, .edit, "新开那一篇要能写（编辑态）")
        record("📝 ② 写笔记：模块 \(host.state.notesModule.rawValue) · 三个字段都空 = "
            + "\(host.state.noteEditorTitle.isEmpty && host.state.noteEditorBody.isEmpty && host.state.noteEditorTags.isEmpty)"
            + " · 模式 = edit")
        let noteScreen = try renderNotesScreen("probe-td-cal-1-after-write-note", host: host)
        XCTAssertTrue(
            Set(noteScreen.records[0].localizedStrings).contains(zh(.notesTitle)),
            "笔记那一屏的「\(zh(.notesTitle))」没进渲染记录 —— 这张图拍的不是笔记面"
        )

        // ── 丁 源锚点。
        let calendarSource = try source("App/Views/TodoCalendarView.swift")
        for anchor in [
            "todo-calendar-new-todo", "todo-calendar-write-note",
            "appState.newTodoOn(selectedDay: day)", "appState.writeNote()"
        ] {
            XCTAssertTrue(
                calendarSource.contains(anchor),
                "`App/Views/TodoCalendarView.swift` 里找不到锚点 `\(anchor)` —— 判据与产品那条线脱钩了"
            )
        }
        XCTAssertFalse(
            calendarSource.contains("NoteLibrary"),
            "日历这一屏出现了 `NoteLibrary` —— 这两枚入口自己开了一条写路（该走 AppState 的既有入口）"
        )
        let stateSource = try source("App/AppState.swift")
        for anchor in [
            "func newTodoOn(selectedDay day: Date?)", "func writeNote()",
            "TodoCalendar.moment(", "setNotesModule(.notes)", "beginNewNote()"
        ] {
            XCTAssertTrue(
                stateSource.contains(anchor),
                "`App/AppState.swift` 里找不到锚点 `\(anchor)` —— 唯一写入口那一半没落地"
            )
        }
        record("📄 源锚点 4 + 1（视图）/ 5（AppState）逐条命中；`TodoCalendarView.swift` 不含 `NoteLibrary`")
        record("🖼 三张图（中英各一）落 \(UISnapshot.outputDirectory.path)")
    }

    /// 戊 语言表两句话中英都在（缺一语言 = 死键）。
    @MainActor
    func testEntriesCopyExistsInBothLanguages() throws {
        for key in [LKey.todoCalendarNewTodo, .todoCalendarWriteNote] {
            for language in [AppLanguage.simplifiedChinese, .english] {
                let line = UISnapshot.localizedText(language) { L(key) }
                XCTAssertFalse(
                    line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "文案是空串：\(key.rawValue) / \(language.rawValue)"
                )
            }
            record("🔤 \(key.rawValue)：zh=「\(zh(key))」 / en=「\(en(key))」")
        }
    }
}
