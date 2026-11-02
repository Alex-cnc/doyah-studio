import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// `FR-NTS-ALL-HOME-001`（首页可配置 · 默认落页）的机器判据 —— 需求 §3.5.18 五条 + 概设 §15.17 六条不变量。
///
/// 为什么钉在这里而不是去点设置面板：面板点一遍只证明「这一台这一次」；本条要求的是
/// **五条规则**（只有两个取值 / 未设置落待办 / 冷启动读偏好 / 页内切换不回写 / 不动数据）。
/// 规则判不住，面板点绿也没意义（`LanguagePreferenceTests` 同一条思路）。
///
/// **覆盖范围（如实声明）**：
///   · ① 二选一 + 键名 —— 纯值 + 真 `UserDefaults`；
///   · ② 未设置 ⇒ 待办 —— 纯值（`resolve`）**与** 真 `AppState` 冷启动两处都判（只判纯值会让
///     「AppState 里还写死着 `.notes`」这种实现过关）；
///   · ③ 改默认页不动数据 —— 真库：改前改后库文件**逐字节相同**、笔记与待办读回来逐项一致；
///   · ④ 不牵连提醒 / 同步 / 私密 —— **源锚点**（`setNoteLandingPage` 的函数体里没有那三条链路的符号）；
///     真正的到点提醒未实测（要真通知中心，`swift test` 宿主里会崩，见 `TodoCalendarEntriesProbeTests` 头注）；
///   · ⑤ 页内切换不回写 —— 真 `AppState`：`setNotesModule(.notes)` 之后偏好键仍是空的；
///   · **未覆盖**：整个 App 的首屏仍是 Studio 自己的活动栏记忆（`ui.activityBarItem`，属 `FR-EDIT-32`），
///     本条只管**笔记区首屏**；真鼠标点设置面板那枚二选一未点。
@MainActor
final class NoteLandingPageTests: XCTestCase {

    private var savedRaw: String?

    override func setUp() {
        super.setUp()
        // 用户的真偏好不碰：存一份、清空（「未设置过」的那种机器形态），跑完原样放回。
        savedRaw = UserDefaults.standard.string(forKey: NoteLandingPage.storageKey)
        UserDefaults.standard.removeObject(forKey: NoteLandingPage.storageKey)
    }

    override func tearDown() {
        if let savedRaw {
            UserDefaults.standard.set(savedRaw, forKey: NoteLandingPage.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: NoteLandingPage.storageKey)
        }
        super.tearDown()
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        // 只剥 `//` 行注释：判据不该被注释里的词命中（同族判据既有做法）。
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - ① 设置项只有两个取值（契约 §15.17「显式二选一」）

    func testOnlyTwoLandingPagesAndTheyCarryTheContractValues() {
        XCTAssertEqual(
            Set(NoteLandingPage.allCases.map(\.rawValue)), ["todo", "notes"],
            "取值必须**只有两个**，且原值就是契约钉的 `todo` / `notes` —— 多出第三档（比如「上次所在的页」）就是越界"
        )
        XCTAssertEqual(NoteLandingPage.storageKey, "notes.home", "键名由契约钉死，一端改名就是「两端各读一份」")
        // 两个取值的名字复用笔记区那一枚切换器（同一个概念不另起说法）。
        XCTAssertEqual(NoteLandingPage.todos.module.titleKey, .notesModuleTodos)
        XCTAssertEqual(NoteLandingPage.notes.module.titleKey, .notesTitle)
    }

    // MARK: - ② 未设置 ⇒ 待办（默认值不随版本漂移）

    func testUnsetOrUnreadableAlwaysLandsOnTodos() throws {
        XCTAssertEqual(NoteLandingPage.defaultPage, .todos, "默认档只有这一处常量，且必须是待办")
        XCTAssertEqual(NoteLandingPage.resolve(stored: nil), .todos, "没存过 ⇒ 待办")
        XCTAssertEqual(NoteLandingPage.resolve(stored: ""), .todos, "空串（老版本清过键）⇒ 待办")
        XCTAssertEqual(NoteLandingPage.resolve(stored: "lastPage"), .todos, "认不出 ⇒ 待办，不落第三处")
        XCTAssertEqual(NoteLandingPage.resolve(stored: "Todos"), .todos, "大小写变了就不是那个取值了 ⇒ 待办")

        let suite = "doyah.tests.note-landing-empty"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(NoteLandingPage.load(from: defaults), .todos, "全新的偏好域 ⇒ 待办（新装用户那一条）")
    }

    // MARK: - ① 存过就按存的来；③ 重启保持（同一个键写进去读回来）

    func testStoredChoiceWinsAndRoundTripsThroughTheSameKey() throws {
        let suite = "doyah.tests.note-landing"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        NoteLandingPage.store(.notes, in: defaults)
        XCTAssertEqual(defaults.string(forKey: "notes.home"), "notes", "写进去的是键 `notes.home` 与值 `notes`")
        XCTAssertEqual(NoteLandingPage.load(from: defaults), .notes, "读回来必须是同一档（重启保持的机器形态）")

        NoteLandingPage.store(.todos, in: defaults)
        XCTAssertEqual(NoteLandingPage.load(from: defaults), .todos, "改回待办也得读得回来（只判一档会让恒笔记的实现过关）")
    }

    // MARK: - ② 冷启动真的落在那所选页（真 AppState，不是纯值）

    func testColdStartLandsOnTheChosenScreen() {
        XCTAssertEqual(
            AppState().notesModule, .todos,
            "未设置过的人（新装 + 老用户）冷启动必须落待办 —— 落笔记就是「打开先看到笔记，以为待办丢了」"
        )

        UserDefaults.standard.set(NoteLandingPage.notes.rawValue, forKey: NoteLandingPage.storageKey)
        XCTAssertEqual(AppState().notesModule, .notes, "设置里选了笔记 ⇒ 下一次冷启动落笔记")

        UserDefaults.standard.set("garbage", forKey: NoteLandingPage.storageKey)
        XCTAssertEqual(AppState().notesModule, .todos, "坏值不锁死、不落第三处 —— 回默认待办")
    }

    // MARK: - ⑤ 页内切换不回写偏好（需求 §3.5.18「不做」那一条）

    func testInPageSwitchNeverWritesBackToThePreference() {
        let state = AppState()
        XCTAssertEqual(state.noteLandingPage, .todos, "新宿主的偏好 = 默认待办")

        state.setNotesModule(.notes)
        XCTAssertEqual(state.notesModule, .notes, "页内切到笔记（会话状态）")
        XCTAssertEqual(state.noteLandingPage, .todos, "**切屏不改偏好** —— 偏好还是待办")
        XCTAssertNil(
            UserDefaults.standard.string(forKey: NoteLandingPage.storageKey),
            "切屏不许往盘上写 `notes.home` —— 写了就成了「记住上次所在页」（明写不做）"
        )

        // 反向：偏好设成笔记之后，页内切回待办也不改偏好（这里只切 `.notes` 方向 ——
        // 往 `.todos` 切会拉起 `reloadReminders()` / `UNUserNotificationCenter`，在 xctest 宿主里会崩，
        // 边界见 `TodoCalendarEntriesProbeTests` 头注；那半边由下面这条源锚点补上）。
        state.setNoteLandingPage(.notes)
        XCTAssertEqual(UserDefaults.standard.string(forKey: NoteLandingPage.storageKey), "notes")
        XCTAssertEqual(state.noteLandingPage, .notes, "设置入口改了 ⇒ 偏好跟着变")
        XCTAssertEqual(state.notesModule, .notes, "但改偏好**不跳页**（生效在下一次冷启动）")
    }

    // MARK: - ③ 改默认页不动任何数据（真库逐字节）

    func testChangingThePreferenceTouchesNoData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("note-landing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        setenv("DOYAH_NOTES_DIR", directory.path, 1)
        defer {
            unsetenv("DOYAH_NOTES_DIR")
            try? FileManager.default.removeItem(at: directory)
        }

        // 先落一家真实的库：一条笔记 + 一条带截止时间的任务（「改前改后逐项一致」要有东西可比）。
        let library = NoteLibrary.defaultLibrary()
        let note = try await library.save(
            NoteDraft(title: "别被设置改掉", body: "正文", tags: ["证据"], source: NoteSource(kind: .manual))
        )
        let dueAt = Date(timeIntervalSince1970: 1_800_000_000)
        let todo = try await library.upsert(Todo(title: "提醒时间别动", dueAt: dueAt, priority: .high))

        let bytesBefore = try Data(contentsOf: library.fileURL)
        let notesBefore = try await library.load()
        let todosBefore = try await library.todos()

        let state = AppState()
        state.setNoteLandingPage(.notes)
        XCTAssertEqual(state.noteLandingPage, .notes, "设置确实改了（不然下面「没动」就没有意义）")

        let bytesAfter = try Data(contentsOf: library.fileURL)
        XCTAssertEqual(bytesBefore, bytesAfter, "改默认页不许动库 —— 库文件逐字节相同")
        let notesAfter = try await library.load()
        XCTAssertEqual(notesAfter.map(\.id), notesBefore.map(\.id), "笔记条数与次序都不变")
        XCTAssertEqual(notesAfter.first?.id, note.id)
        let todosAfter = try await library.todos()
        XCTAssertEqual(todosAfter.map(\.id), todosBefore.map(\.id), "待办条数不变")
        let fetched = try await library.todo(id: todo.id)
        let reloadedTodo = try XCTUnwrap(fetched)
        XCTAssertEqual(reloadedTodo.done, false, "完成态不变")
        XCTAssertEqual(reloadedTodo.completedAt, nil, "完成时刻不变")
        XCTAssertEqual(reloadedTodo.dueAt, dueAt, "提醒时间逐项一致")
    }

    // MARK: - ④ 不牵连提醒 / 同步 / 私密（源锚点 · 接线级）

    /// 这一段只能判**接线**：函数体里没有那三条链路的符号。
    /// 真通知是否照常弹、同步是否照常跑属人工点验（`swift test` 宿主里没有真通知中心）。
    func testChangingThePreferenceTouchesNoOtherChain() throws {
        let appState = try source("App/AppState.swift")
        let start = try XCTUnwrap(appState.range(of: "func setNoteLandingPage"))
        let tail = appState[start.lowerBound...]
        let end = try XCTUnwrap(tail.range(of: "\n    }"), "找不到 `setNoteLandingPage` 的函数体边界")
        let body = String(tail[..<end.upperBound])

        XCTAssertTrue(body.contains("NoteLandingPage.store"), "写偏好必须走那一处写入口")
        for forbidden in ["Reminder", "Notification", "CloudSync", "Sync", "Privacy", "NoteLibrary", "save(", "delete"] {
            XCTAssertFalse(
                body.contains(forbidden),
                "`setNoteLandingPage` 里出现了 `\(forbidden)` —— 落页只管偏好，提醒 / 同步 / 私密与数据都不许被牵连"
            )
        }
    }
}
