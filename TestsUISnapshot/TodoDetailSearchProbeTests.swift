import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **待办清单那两件**的 App 侧探针（片 `TD-LIST-1` · 派单 `T-20261009-026`）。
///
/// ## 判的是什么
///
/// 派单上那两条现场验：
///   ① **点清单里的一行 ⇒ 右栏出只读详情**（标题 / 截止 / 优先级 / 标签；**无编辑控件**）；
///   ② **`TodoQueryBar` 里的关键字检索** ⇒ 清单只剩按标题命中的行。
///
/// 前门核验（`T-20261009-026` 的 A6 / B4）只判到「源码里有没有这两个词」（改前都是**零命中**）；
/// 「有」不等于「点下去真的是这个结果」。本探针把这两条在**真视图树**上跑成断言，并各留图给人判
/// （`UISnapshot.writeBothLanguages` 落 `DOYAH_SNAPSHOT_DIR` / `.build/ui-snapshots/`）。
///
/// ## 两条观测口径（先说清「怎么看得见」—— 判据不许空转）
///
/// ① **活宿主里的控件事实**（`UISnapshot.LiveHost`）：SwiftUI 的 `List` 在这台机器上落到
///    `NSTableView`（`NotesLayoutProbeTests` 量笔记列表那条同源）⇒ **屏上现在有几行**是一个
///    可数的整数；`TextField` 落到真 `NSTextField`（`MySQLFormProbeTests` 读端口那一格同源）⇒
///    「**右栏有没有可编辑控件**」也是可数的（`只读 ≠ 编辑` 的机械形状就是这么判的）；
/// ② **这一遍 `L(...)` 取到过的文案**（`UISnapshot` 的记录）：判得动语言表里那些句子，
///    **判不了用户数据**（任务标题 / 标签不走 `L(...)`），也**判不了定形文本**（片 `TD-DUE` 之后
///    详情那一行的截止是与安卓同形的具体时刻 `MM-DD HH:mm`，它不是语言表里的句子 ⇒ 不进这份记录）。
///    所以「右栏画的是哪一条」由**只有右栏会印、且不与任何下拉的条目撞车**的读数来判：夹具 A 的
///    优先级是「高」（`todoPriorityHigh`；B / C 分别是「低」/「普通」），而分带词里**只有「以后」
///    （`todoDueLater`）不与筛选下拉那五档撞车**（另外四句逐字相同 ⇒ 在本屏判不动），它现在
///    **不再上详情** —— 这正是片 `TD-DUE` 的成对读数：改前 `todoDueLater`（「以后」）就落在这一份
///    记录里（那时只有详情会印它），改后不在。另外四句由末尾那条「只装右栏那一件」的用例判。
///
/// ## 判据（可机械跑 · 每组都印读数）
///
/// · **甲 点一行 ⇒ 只读详情（且那一屏没有编辑控件）**：走产品那一条线（`AppState.showTodoDetail(_:)`
///   → `AppState.todoDetailTodo` → `TodoRightPaneView`）。为了让「右栏画的是哪一条」**不被左侧清单
///   污染**，这一遍把清单用「只存在于标签里的那个词」搜空（它同时就是 乙③ 的反向对照）：
///   ① 正面：活宿主里**清单 0 行**；文案里有两条轴名（`todoDueLabel` / `todoPriorityLabel`）与
///      A 的优先级（`todoPriorityHigh`），而分带词「以后」（`todoDueLater`）**不在** —— 清单是空的 ⇒
///      这些读数**只可能来自右栏**（片 `TD-DUE`：详情那一行的截止已是与安卓同形的**具体时刻**，
///      改前「以后」正是详情印的；其余四句与筛选下拉撞车，在本屏判不动）；
///   ② 反面（这一片的关键）：**一条都不许出现**编辑器那三句（`todoTitlePlaceholder`「待办标题」/
///      `todoHasDueLabel`「有截止时间」/ `notesSave`「保存」）—— **只读 ≠ 编辑**；
///   ③ 对照：`beginNewTodo()` 之后**同一个件**渲染出来**必须**有那三句，否则 ② 的「没有」
///      分不清是「只读」还是「读不到文案」；
///   ④ 清单那半边同时是 **乙③**：库里明明有任务、只是这个词只在标签里 ⇒ 该说 `todosEmptyFiltered`
///      （「这一档没有任务」）而**不是** `todosEmpty`（「还没有待办」）。
/// · **甲′ 右栏那一件在真视图树上没有可编辑控件**（单独一条用例）：把 `TodoRightPaneView` 单独装进
///   活宿主 —— 详情态 `NSTextField` / `NSTextView` **各 0 个**；反向对照 = 进编辑态之后**必须 ≥ 1 个**
///   （否则「0 个」可能只是「这一棵没渲染」）。这一条**不看文案**，是 甲 ② 的独立第二只眼。
/// · **乙 检索 ⇒ 清单只剩命中项**：真 `AppState` + 真 `TodoListView`：空词那一遍活宿主里 **3 行**；
///   敲一个只配得上其中一条的子串 ⇒ **1 行**，且那一条的读数在、另两条的读数（`todoPriorityLow`「低」）
///   不在；反向对照：同一个量法下「只在标签里的词」⇒ Core 读数 **0**、活宿主里 **0 行**（**只看标题**）。
/// · **丙 源锚点**：行点击接的是 `appState.showTodoDetail(todo)`（**不再**是 `appState.edit(todo)`）、
///   右键那一枚「编辑」接的是 `appState.edit(todo)`、检索格绑的是 `$appState.todoSearchText`、
///   右栏那一件读的是 `appState.todoDetailTodo`。
///
/// ## 边界（如实登记 · 先实测再写）
///
/// · **「切到待办那一屏」这一格在本探针里做不到**（与 `TodoCalendarEntriesProbeTests` 同一条）：
///   `AppState.setNotesModule(.todos)` 会拉起通知中心那一套，在 `swift test` 宿主里 **signal 6**。
///   所以待办那一屏按**它与生产同源的两栏**（`TodoPaneView` + `TodoRightPaneView`，即
///   `NotesAreaView` 在模块 = 待办时画的那两件）在探针里合起来拍；
/// · **不判真鼠标点击**：调的是**按钮 / 行接到的那个方法**（`showTodoDetail`），
///   「行 ⟷ 方法」那一环由判据丙的源锚点钉住（与 `TodoCalendarEntriesProbeTests` 同一条纪律）；
/// · **行内文字读不出来**（SwiftUI 的行 `Text` 不落在 `NSTextField` / `NSTextView`）：所以**标题一类的
///   用户数据不进判据**（见上面观测口径 ②），判的是「几行」与走语言表的那些读数；
/// · 不碰用户数据：笔记库由 `DOYAH_NOTES_DIR` 指到每轮清空的临时目录（没设就跳过）；
/// · 产物**不进快照清单**：图落 `DOYAH_SNAPSHOT_DIR`（共享产物）。
///
/// 跑法：`DOYAH_UI_SNAPSHOT=1 DOYAH_NOTES_DIR=<临时目录> swift test --filter TodoDetailSearchProbeTests`。
final class TodoDetailSearchProbeTests: XCTestCase {

    /// 宿主面积：与 `NotesLayoutProbeTests.areaSize` 同一个（三栏骨架里「中栏 + 右栏」那两栏）。
    private static let areaSize = CGSize(width: 1100, height: 700)

    /// 待办那一屏里**中栏**的三档宽度（照抄 `NotesAreaView.listPaneMin/Ideal/MaxWidth` 那三个值 ——
    /// 它们是 `private`，测试这边取不到；写在这儿只为说明「探针拍的还是那一栏的宽度」）。
    private static let todoPaneMinWidth: CGFloat = 132
    private static let todoPaneIdealWidth: CGFloat = 180
    private static let todoPaneMaxWidth: CGFloat = 300

    /// 夹具里那三条的标题（**用户数据**：不参与文案判据，见头注释观测口径 ②）。
    private static let hitTitle = "交季度报表"    // 30 天后 · 高 · 标签「财务」「季度」
    private static let missTitle = "给骑友回消息"  // 无截止 · 低
    private static let otherTitle = "买咖啡豆"     // 无截止 · 普通（这一档不画优先级文字）

    /// **只在标签里**的那个词（标题里没有）—— 甲那一遍用它把清单搜空，同时就是「只看标题」的反向对照。
    private static let labelOnlyWord = "财务"
    /// **只在命中那条标题里**的那个词 —— 乙那一遍用它。
    private static let titleWord = "季度"

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏渲染要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
        try XCTSkipIf(
            (ProcessInfo.processInfo.environment["DOYAH_NOTES_DIR"] ?? "").isEmpty,
            "本探针要起真 `AppState`（它读笔记库）⇒ 必须在临时数据家里跑：`DOYAH_NOTES_DIR` 没设就跳过"
                + "（绝不允许往真实用户数据目录里写测试夹具）"
        )
    }

    // MARK: - 装配

    private typealias Host = (
        state: AppState, workspace: WorkspaceStore, tabs: WorkspaceTabsModel, terminal: TerminalModel
    )

    private func record(_ line: String) { print("🧪 TD-LIST-1 \(line)") }

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
                    fileURL: scratch.appendingPathComponent("td-list-1-\(UUID().uuidString).json")
                )
            ),
            TerminalModel()
        )
    }

    /// 起夹具：三条任务（带 / 优先级两两分得开 —— 判据与「今天」是星期几无关）+ 三格界面状态清回默认。
    @MainActor
    private func populate(_ host: Host) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // A 的截止落在「更晚」那一带（30 天后，稳）：这一句**只有带那一栏会印**（筛选下拉的五档里没有它），
        // 于是它成了「右栏 / 清单画的是 A」的干净读数（见头注释观测口径 ②）。
        let later = calendar.date(byAdding: .day, value: 30, to: today) ?? today
        host.state.todos = [
            Todo(title: Self.hitTitle, dueAt: later, priority: .high, tags: ["财务", "季度"]),
            Todo(title: Self.missTitle, priority: .low),
            Todo(title: Self.otherTitle),
        ]
        host.state.todoFilter = .all
        host.state.todoPane = .list
        host.state.todoSearchText = ""
        host.state.beginNewTodo()
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

    /// 待办那一屏（`NotesAreaView` 在模块 = 待办时画的那两栏：中栏 = 清单 / 日历，右栏 = `TodoRightPaneView`）。
    @MainActor
    private func todoScreen(_ host: Host) -> AnyView {
        AnyView(
            environment(
                HSplitView {
                    TodoPaneView()
                        .frame(
                            minWidth: Self.todoPaneMinWidth,
                            idealWidth: Self.todoPaneIdealWidth,
                            maxWidth: Self.todoPaneMaxWidth
                        )
                    TodoRightPaneView()
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity),
                host
            )
        )
    }

    @MainActor
    @discardableResult
    private func renderTodoScreen(_ name: String, host: Host) throws -> UISnapshot.LanguagePair {
        try UISnapshot.writeBothLanguages(name, size: Self.areaSize) { todoScreen(host) }
    }

    /// 把同一棵真视图树装进**活宿主**（`NSWindow` + `NSHostingView`），量清单区那张 `NSTableView` 的行数。
    ///
    /// 为什么要有这一条：文案记录里判不出「剩了几行」（标题是用户数据、档位名与下拉条目会撞车），
    /// 而 `List` 落到 `NSTableView` ⇒ 行数是**界面上的事实**（`NotesLayoutProbeTests` 同源量法）。
    ///
    /// **行数里含段头**：`List` 的每个 `Section` 在这一层也占一行（实测：三条待办 + 「未完成 / 已完成」
    /// 两个段头 = 5 行）—— 所以判据一律用**差值 / 不变量**，不写死行数（写死就等于把一个排版细节
    /// 铸进判据）。**空表返回空数组**：`board.total == 0` 时清单那一支被空态那句话替换掉了，
    /// 「没有表格」本身就是读数（不是空跑）。
    @MainActor
    private func todoScreenTableRows(_ host: Host, _ why: String) -> [Int] {
        let live = UISnapshot.LiveHost(todoScreen(host), size: Self.areaSize)
        live.pump(0.35)
        let tables = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSTableView.self, in: live.hosting)
        let rows = tables.map(\.numberOfRows)
        print("🧪 TD-LIST-1 🔢 \(why)：NSTableView \(tables.count) 张 / 行数 \(rows)")
        return rows
    }

    /// 判据里拿「这一句应该长什么样」—— 与渲染那一遍**同一条路**（`beginHostLanguage` 包住）。
    @MainActor
    private func zh(_ key: LKey) -> String { UISnapshot.localizedText(.simplifiedChinese) { L(key) } }
    @MainActor
    private func en(_ key: LKey) -> String { UISnapshot.localizedText(.english) { L(key) } }

    /// 这一遍渲染取到的文案集合（中英各一份，与 `coverageLanguages` 同序）。
    private func seen(_ pair: UISnapshot.LanguagePair, _ index: Int) -> Set<String> {
        Set(pair.records[index].localizedStrings)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: - 判据

    /// 甲 / 乙 / 丙（同一条状态链上依次走：起点 → 点一行 → 搜空 → 进编辑（对照）→ 敲词）。
    @MainActor
    func testRowClickShowsReadOnlyDetailAndSearchFiltersTheList() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        let load = try UISnapshot.applyLicense(.standard, to: host.state)
        XCTAssertEqual(load.entitlements.basis, .licensed, "临时许可证没落地 ⇒ 笔记那一屏读不到库")
        XCTAssertTrue(host.state.notesEnabled, "Standard 档必须带笔记能力（capabilities.notes）")

        populate(host)
        XCTAssertEqual(host.state.todoBoard.total, 3, "三条都该在（空词不筛）")
        XCTAssertNil(host.state.todoDetailID, "新宿主不该有详情目标")
        XCTAssertNil(host.state.todoDetailTodo, "新宿主不该有详情目标")
        XCTAssertNil(host.state.todoEditingID, "新宿主不该在编辑态")
        XCTAssertEqual(host.state.notesModule, .notes, "模块初值该是笔记（切待办那一屏在本宿主里进不去，见头注释边界）")

        // ── 起点：三条都在（活宿主：三行 + 两个段头），右栏那一件画的是**编辑器**（对照件）。
        let startRows = todoScreenTableRows(host, "起点").reduce(0, +)
        let startHeaders = startRows - host.state.todoBoard.total
        let start = try renderTodoScreen("probe-td-list-1-before-row-click", host: host)
        for (index, language) in UISnapshot.coverageLanguages.enumerated() {
            let texts = seen(start, index)
            let editorCopy = language == .simplifiedChinese
                ? [zh(.todoTitlePlaceholder), zh(.todoHasDueLabel), zh(.notesSave)]
                : [en(.todoTitlePlaceholder), en(.todoHasDueLabel), en(.notesSave)]
            let missing = editorCopy.filter { !texts.contains($0) }
            XCTAssertTrue(
                missing.isEmpty,
                "对照件不成立：起点（新建态）右栏该是编辑器（缺 \(missing)）⇒ 甲 ② 的「没有那几句」判不准"
            )
            record("🧷 起点（\(language.rawValue)）：活宿主 \(startRows) 行（\(host.state.todoBoard.total) 条 + \(startHeaders) 个段头）；"
                + "编辑器 " + editorCopy.map { "「\($0)」" }.joined(separator: " / ") + " 都在")
        }
        XCTAssertGreaterThan(startRows, 0, "起点那一遍清单没落地成有行的 NSTableView —— 行数判据量不到东西")

        // ── 真入口：点清单里的一行（`TodoRowView` 的 `.onTapGesture` 接的就是它）。
        host.state.showTodoDetail(host.state.todos[0])
        pump(0.2)
        let hitID = host.state.todos[0].id
        XCTAssertEqual(host.state.todoDetailID, hitID, "点一行之后详情目标就是那一条")
        XCTAssertEqual(host.state.todoDetailTodo?.id, hitID, "右栏那一件读到的该是它")
        XCTAssertNil(host.state.todoEditingID, "点一下**不许**进编辑态（只读 ≠ 编辑）")

        // 图 ①（给人判）：点一行之后**清单还在**、右栏是只读详情。
        let clickedRows = todoScreenTableRows(host, "点一行之后").reduce(0, +)
        XCTAssertEqual(clickedRows, startRows, "点一行不该把清单里的行弄丢（\(startRows) → \(clickedRows)）")
        try renderTodoScreen("probe-td-list-1-detail-with-list", host: host)
        record("🖱 点一行：活宿主仍是 \(clickedRows) 行（清单没动），右栏换成只读详情")

        // ── 甲 ①②④ / 乙③：把清单用「只存在于标签里的那个词」搜空（库里仍有三条）。
        host.state.todoSearchText = Self.labelOnlyWord
        pump(0.2)
        XCTAssertEqual(
            host.state.todoBoard.total, 0,
            "「\(Self.labelOnlyWord)」只在某条的**标签**里 ⇒ 一条都不许留（只看标题）"
        )
        let emptyRows = todoScreenTableRows(host, "搜空之后")
        XCTAssertTrue(
            emptyRows.isEmpty,
            "搜空之后清单那一支该被空态那句话替换掉（不该还有 NSTableView），实测 \(emptyRows)"
        )
        let detail = try renderTodoScreen("probe-td-list-1-detail", host: host)
        for (index, language) in UISnapshot.coverageLanguages.enumerated() {
            let texts = seen(detail, index)
            let wanted = language == .simplifiedChinese
                ? [zh(.todoDueLabel), zh(.todoPriorityLabel), zh(.todoPriorityHigh)]
                : [en(.todoDueLabel), en(.todoPriorityLabel), en(.todoPriorityHigh)]
            let missing = wanted.filter { !texts.contains($0) }
            XCTAssertTrue(
                missing.isEmpty,
                "右栏只读详情上缺 \(missing)（清单这一遍是 0 行 ⇒ 这些读数只可能来自右栏）—— \(language.rawValue) 那遍"
            )
            // 片 `TD-DUE`（派单 `T-20261009-042` ④）：详情那一行的截止改成**具体时刻**（`TodoDueText.text`）
            // 之后，详情上不再印分带词。这一遍能当**干净读数**的只有「以后」（`todoDueLater`）—— 另外四句
            // （今天 / 本周 / 已过期 / 无截止）与**筛选下拉那五档**逐字相同（`todoFilter*`：语言表里两组
            // 中文、英文都一字不差），在这一屏上撞车，判不动。成对读数：**改前本探针正是拿「以后」判的**
            // （夹具 A 的截止落在那一带 ⇒ 那时只有详情会印它），改后它不再出现。
            let laterGhost = language == .simplifiedChinese ? zh(.todoDueLater) : en(.todoDueLater)
            XCTAssertFalse(
                texts.contains(laterGhost),
                "详情那一行的截止该是与安卓同形的具体时刻了，却仍印着分带词「\(laterGhost)」—— \(language.rawValue) 那遍"
            )
            // 分带五句里那四句与筛选档撞车的，改由「**只装右栏那一件**」的那一遍判（本文件末尾
            // `testDetailDueShowsConcreteMomentLikeAndroid`：不带清单、不带检索格 ⇒ 没有撞车面）。
            let forbidden = language == .simplifiedChinese
                ? [zh(.todoTitlePlaceholder), zh(.todoHasDueLabel), zh(.notesSave)]
                : [en(.todoTitlePlaceholder), en(.todoHasDueLabel), en(.notesSave)]
            let leaked = forbidden.filter { texts.contains($0) }
            XCTAssertTrue(
                leaked.isEmpty,
                "只读详情上出现了编辑控件那几句 \(leaked) —— 只读 ≠ 编辑（\(language.rawValue) 那遍）"
            )
            let ghosts = (language == .simplifiedChinese ? [zh(.todoPriorityLow)] : [en(.todoPriorityLow)])
                .filter { texts.contains($0) }
            XCTAssertTrue(
                ghosts.isEmpty,
                "清单已经搜空，画面上却还有另一条的读数 \(ghosts)（\(language.rawValue) 那遍）—— 右栏画错了那一条？"
            )
            let filtered = language == .simplifiedChinese ? zh(.todosEmptyFiltered) : en(.todosEmptyFiltered)
            let empty = language == .simplifiedChinese ? zh(.todosEmpty) : en(.todosEmpty)
            XCTAssertTrue(texts.contains(filtered), "空态那句该是「\(filtered)」（\(language.rawValue) 那遍）")
            XCTAssertFalse(
                texts.contains(empty),
                "空态说成了「\(empty)」—— 库里明明有任务，这是一句假话（\(language.rawValue) 那遍）"
            )
            record("🔒 甲（\(language.rawValue)）：清单那一支已被空态替换（NSTableView \(emptyRows.count) 张）；右栏读数 "
                + wanted.map { "「\($0)」" }.joined(separator: " / ") + " 都在；分带词「\(laterGhost)」不在；编辑器 "
                + forbidden.map { "「\($0)」" }.joined(separator: " / ") + " 一句都没有；空态 = 「\(filtered)」")
        }

        // ── 甲 ③ 反向对照：显式「编辑」之后，**同一个件**必须画得出编辑器那三句。
        host.state.todoSearchText = ""
        host.state.edit(host.state.todos[0])
        pump(0.2)
        XCTAssertNil(host.state.todoDetailTodo, "进编辑态之后不该再给详情（两态互斥）")
        let editing = try renderTodoScreen("probe-td-list-1-editing", host: host)
        for (index, language) in UISnapshot.coverageLanguages.enumerated() {
            let texts = seen(editing, index)
            let expected = language == .simplifiedChinese
                ? [zh(.todoTitlePlaceholder), zh(.todoHasDueLabel), zh(.notesSave)]
                : [en(.todoTitlePlaceholder), en(.todoHasDueLabel), en(.notesSave)]
            let missing = expected.filter { !texts.contains($0) }
            XCTAssertTrue(
                missing.isEmpty,
                "反向对照不成立：进编辑态之后那几句仍没画出来（缺 \(missing)）—— 甲 ② 的判据在空转"
            )
            record("🧷 反向对照（\(language.rawValue)）：编辑态里 \(expected.map { "「\($0)」" }.joined(separator: " / ")) 都在")
        }

        // ── 乙 检索：敲一个只在命中那条**标题**里的子串 ⇒ 清单只剩它。图 ②。
        host.state.beginNewTodo()
        host.state.showTodoDetail(host.state.todos[0])
        host.state.todoSearchText = Self.titleWord
        pump(0.2)
        XCTAssertEqual(host.state.todoBoard.total, 1, "Core 那一层只该留一条")
        let oneRowTables = todoScreenTableRows(host, "检索之后")
        let oneRow = oneRowTables.reduce(0, +)
        XCTAssertFalse(oneRowTables.isEmpty, "检索之后清单仍在 ⇒ 该有一张 NSTableView")
        XCTAssertEqual(
            startRows - oneRow, 3 - 1,
            "活宿主行数之差该等于条数之差（\(startRows) → \(oneRow)，段头那两行两遍都在）"
        )
        let filtered = try renderTodoScreen("probe-td-list-1-search", host: host)
        for (index, language) in UISnapshot.coverageLanguages.enumerated() {
            let texts = seen(filtered, index)
            let kept = language == .simplifiedChinese
                ? [zh(.todoDueLater), zh(.todoPriorityHigh)]
                : [en(.todoDueLater), en(.todoPriorityHigh)]
            let gone = language == .simplifiedChinese ? [zh(.todoPriorityLow)] : [en(.todoPriorityLow)]
            let missingKept = kept.filter { !texts.contains($0) }
            let leaked = gone.filter { texts.contains($0) }
            XCTAssertTrue(missingKept.isEmpty, "命中的那一条没画出来（缺 \(missingKept)）—— \(language.rawValue) 那遍")
            XCTAssertTrue(
                leaked.isEmpty,
                "没命中的那条还在画面上（\(leaked)）—— 检索没把行筛掉（\(language.rawValue) 那遍）"
            )
            record("🔎 乙（\(language.rawValue)）：词「\(Self.titleWord)」⇒ Core \(host.state.todoBoard.total) 条 / 活宿主 \(oneRow) 行；"
                + "命中的读数在、另两条的读数不在")
        }
        // 反向对照：同一个量法下「标题里有的词」与「只在标签里的词」必须给出不同结果。
        host.state.todoSearchText = "骑友"
        pump(0.1)
        XCTAssertEqual(host.state.todoBoard.total, 1, "「骑友」只在标题「\(Self.missTitle)」里 ⇒ 1 条")
        XCTAssertEqual(
            todoScreenTableRows(host, "词「骑友」").reduce(0, +), oneRow,
            "同一个量法下该量到同一张数（都是 1 条待办）"
        )
        host.state.todoSearchText = Self.labelOnlyWord
        pump(0.1)
        XCTAssertEqual(host.state.todoBoard.total, 0, "同一个量法下「\(Self.labelOnlyWord)」（只在标签里）⇒ 0 条")
        XCTAssertTrue(
            todoScreenTableRows(host, "词「\(Self.labelOnlyWord)」").isEmpty,
            "同一个量法下该量不到表格（空态那一支）"
        )
        record("🧷 乙 反向对照：词「骑友」（标题里）⇒ 1 条 / \(oneRow) 行；"
            + "词「\(Self.labelOnlyWord)」（只在标签里）⇒ 0 条 / 无表格")

        // ── 丙 源锚点。
        let calendarSource = try source("App/Views/TodoCalendarView.swift")
        for anchor in [
            "appState.showTodoDetail(todo)", "Button(L(.commonEdit)) { appState.edit(todo) }",
            "$appState.todoSearchText", "todo-search-field", "TodoQuery.band(of:",
        ] {
            XCTAssertTrue(
                calendarSource.contains(anchor),
                "`App/Views/TodoCalendarView.swift` 里找不到锚点 `\(anchor)` —— 判据与产品那条线脱钩了"
            )
        }
        XCTAssertFalse(
            calendarSource.contains(".onTapGesture { appState.edit(todo) }"),
            "行点击又变回「点一下直接进编辑器」了 —— 那正是 A6 要清掉的形状"
        )
        XCTAssertFalse(
            calendarSource.contains("localizedCaseInsensitiveContains"),
            "视图里出现了检索谓词 —— 判定必须只在 Core（`TodoSearch`）"
        )
        let panelSource = try source("App/Views/NotesPanel.swift")
        for anchor in ["struct TodoDetailView", "struct TodoRightPaneView", "appState.todoDetailTodo"] {
            XCTAssertTrue(panelSource.contains(anchor), "`App/Views/NotesPanel.swift` 里找不到锚点 `\(anchor)`")
        }
        let stateSource = try source("App/AppState.swift")
        for anchor in [
            "func showTodoDetail(_ todo: Todo)", "var todoDetailTodo: Todo?", "@Published var todoSearchText",
        ] {
            XCTAssertTrue(stateSource.contains(anchor), "`App/AppState.swift` 里找不到锚点 `\(anchor)`")
        }
        record("📄 源锚点：行点击 → `showTodoDetail` + 右键「编辑」→ `edit`；检索格绑 `$appState.todoSearchText`；"
            + "右栏读 `appState.todoDetailTodo`；视图里没有第二份匹配谓词")
        record("🖼 五张图（中英各一）落 \(UISnapshot.outputDirectory.path)")
    }

    /// 甲′：**右栏那一件在真视图树上没有可编辑控件** —— 不看文案的第二只眼（判据甲 ② 的独立复核）。
    ///
    /// 量法：把 `TodoRightPaneView` **单独**装进活宿主（不带左侧清单，免得左边那格检索输入框混进来），
    /// 数视图树里的 `NSTextField` / `NSTextView`。
    /// **反向对照**：进编辑态之后同一棵树里**必须**数得到（否则「0 个」可能只是「这一棵没渲染」）。
    @MainActor
    func testDetailPaneRealViewTreeHasNoEditableControls() throws {
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        _ = try UISnapshot.applyLicense(.standard, to: host.state)
        populate(host)

        func textControlCount(_ why: String) -> Int {
            let live = UISnapshot.LiveHost(
                AnyView(environment(TodoRightPaneView(), host)),
                size: CGSize(width: 640, height: 600)
            )
            live.pump(0.35)
            let fields = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSTextField.self, in: live.hosting)
            let views = UISnapshot.LiveHost<AnyView>.findViews(ofType: NSTextView.self, in: live.hosting)
            print("🧪 TD-LIST-1 🔢 \(why)：NSTextField \(fields.count) 个 / NSTextView \(views.count) 个")
            return fields.count + views.count
        }

        host.state.showTodoDetail(host.state.todos[0])
        pump(0.1)
        XCTAssertNotNil(host.state.todoDetailTodo, "前置：这一遍右栏该是只读详情")
        XCTAssertEqual(
            textControlCount("只读详情那一屏"), 0,
            "只读详情那一屏上出现了可编辑文本控件 —— 只读 ≠ 编辑"
        )

        host.state.edit(host.state.todos[0])
        pump(0.1)
        XCTAssertNil(host.state.todoDetailTodo, "前置：进编辑态之后不该再给详情")
        let editing = textControlCount("编辑器那一屏（对照）")
        XCTAssertGreaterThan(
            editing, 0,
            "反向对照不成立：编辑器那一屏也数不到可编辑文本控件 ⇒ 上面那个「0」是假绿"
        )
        record("🔒 甲′：只读详情 0 个可编辑文本控件；编辑器（对照）\(editing) 个 —— 判据判得动")
    }

    /// 丁 语言表那两句轴名中英都在（缺一语言 = 死键）；顺带把检索格的占位那句也判一遍。
    @MainActor
    func testDetailCopyExistsInBothLanguages() throws {
        for key in [LKey.todoDueLabel, .todoPriorityLabel, .windowSearchPlaceholder] {
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

    /// 片 `TD-DUE`（派单 `T-20261009-042` ④）：详情「截止」那一行 = **与安卓同形的具体时刻**。
    ///
    /// 口径出处（对侧实读）：安卓详情那一格是 `todo.dueAt?.let { TimeText.dueText(it) } ?: 「无截止」`
    /// （`DoyahNotes/platform/android/app/src/main/java/studio/doyah/notes/android/ui/TodoDetailDialog.kt`），
    /// `TimeText.dueText`（同目录 `TimeText.kt`）= 两位月 - 两位日 + 24 小时制分钟（例 `10-09 09:00`）。
    ///
    /// 四组读数：
    ///   ① **同形**：`TodoDueText.text(<2026-10-09 09:00>)` == `10-09 09:00`，夹具里那一刻（「30 天后」）
    ///      也落在同一个形状上（正则判形状，不写死字面量），零点那一档另判一遍（免得被 12 小时制换掉）；
    ///   ② **无截止走既有键**：`TodoDueText.text(nil)` == 语言表里那两句「无截止」（中英各判一遍，
    ///      取值在语言窗口内算）—— 不新造文案；
    ///   ③ **成对读数**（同一份源码里的计数，改前 → 改后）：`App/Views/NotesPanel.swift` 里
    ///      `TodoQuery.band(of:` **1 ⇒ 0**、`TodoDueText.text(` **0 ⇒ 1**；而清单行 / 分组那一侧
    ///      （`App/Views/TodoCalendarView.swift`）仍是 **2**、`Core/TodoQuery.swift` 的分带本体仍在
    ///      —— **分带读数不许被动**；
    ///   ④ **只装右栏那一件**（不带清单 / 检索格 / 筛选下拉 ⇒ 没有「与筛选档逐字撞车」那层混淆面）：
    ///      分带五句**一句都不许在**，而轴名 + 优先级仍在（反向对照，否则「没有带词」是空跑）。
    @MainActor
    func testDetailDueShowsConcreteMomentLikeAndroid() throws {
        // ① 同形：样例时刻 ⇒ 与安卓 `TimeText.dueText` 同一个形状。
        let sample = try XCTUnwrap(
            DateComponents(calendar: .current, year: 2026, month: 10, day: 9, hour: 9, minute: 0).date,
            "构造不出样例时刻（2026-10-09 09:00）"
        )
        XCTAssertEqual(
            TodoDueText.text(sample), "10-09 09:00",
            "详情那一行的截止形状变了 —— 安卓侧 `TimeText.dueText` 是 `MM-DD HH:mm`（例 `10-09 09:00`）"
        )
        XCTAssertEqual(
            TodoDueText.format, "MM-dd HH:mm",
            "形状常量被动过（`dd` = 月内第几天、`HH` = 24 小时制 —— 换成 `DD` 就成了「一年里的第几天」）"
        )
        let shape = #"^[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$"#
        let later = Calendar.current.date(
            byAdding: .day, value: 30, to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        let rendered = TodoDueText.text(later)
        XCTAssertNotNil(
            rendered.range(of: shape, options: .regularExpression),
            "夹具那一刻（30 天后）没落在 `MM-DD HH:mm` 这个形状上：实测「\(rendered)」"
        )
        let midnight = try XCTUnwrap(
            DateComponents(calendar: .current, year: 2026, month: 1, day: 1, hour: 0, minute: 5).date,
            "构造不出零点样例（2026-01-01 00:05）"
        )
        XCTAssertEqual(TodoDueText.text(midnight), "01-01 00:05", "零点这一档被换成 12 小时制了？")
        record("🕘 同形：2026-10-09 09:00 ⇒ 「\(TodoDueText.text(sample))」；30 天后 ⇒ 「\(rendered)」；"
            + "2026-01-01 00:05 ⇒ 「\(TodoDueText.text(midnight))」")

        // ② 无截止 ⇒ 语言表里既有那一句（不新造文案），中英各判一遍。
        //    ⚠ 取值必须在**语言窗口内**算：`TodoDueText.text(nil)` 走 `L(...)`，在窗口外算拿的是本机
        //    偏好语言（本机是英文）—— 与「期望值那一遍」不同一条路就比不出东西（本用例第一版就是这么错的）。
        for language in UISnapshot.coverageLanguages {
            let none = UISnapshot.localizedText(language) { L(.todoDueNone) }
            let renderedNone = UISnapshot.localizedText(language) { TodoDueText.text(nil) }
            XCTAssertEqual(
                renderedNone, none,
                "无截止该走语言表里既有的那一句（\(language.rawValue)）"
            )
            record("🕘 无截止（\(language.rawValue)）⇒ 「\(renderedNone)」（既有键，未新造）")
        }

        // ④ **只装右栏那一件**（不带清单、不带检索格 / 筛选下拉）：没有「与筛选档逐字撞车」那层混淆面，
        //    分带五句**一句都不许在**（撞不动的东西才判得动 —— 甲那一遍只能判「以后」一句）。
        //    反向对照 = 两条轴名与 A 的优先级「高」必须在（否则「一句带词都没有」可能只是「这一棵没渲染」）。
        let host = makeHost()
        defer { UISnapshot.clearLicense(from: host.state) }
        _ = try UISnapshot.applyLicense(.standard, to: host.state)
        populate(host)
        host.state.todoSearchText = ""
        host.state.showTodoDetail(host.state.todos[0])
        pump(0.2)
        XCTAssertNotNil(host.state.todoDetailTodo, "前置：这一遍右栏该是只读详情（不是编辑器）")
        let pane = try UISnapshot.writeBothLanguages("probe-td-due-detail-pane", size: Self.areaSize) {
            AnyView(environment(TodoRightPaneView(), host))
        }
        let bandKeys: [LKey] = [.todoDueOverdue, .todoDueToday, .todoDueThisWeek, .todoDueLater, .todoDueNone]
        for (index, language) in UISnapshot.coverageLanguages.enumerated() {
            let texts = seen(pane, index)
            let bandWords = bandKeys.map { language == .simplifiedChinese ? zh($0) : en($0) }
            let leaks = bandWords.filter { texts.contains($0) }
            XCTAssertTrue(
                leaks.isEmpty,
                "只读详情那一件上出现了分带词 \(leaks) —— 这一棵没有筛选下拉（片 `TD-DUE` 之后）"
                    + "带词只可能来自详情本身（\(language.rawValue) 那遍）"
            )
            let anchors = [LKey.todoDueLabel, .todoPriorityLabel, .todoPriorityHigh]
                .map { language == .simplifiedChinese ? zh($0) : en($0) }
            let missing = anchors.filter { !texts.contains($0) }
            XCTAssertTrue(
                missing.isEmpty,
                "反向对照不成立：只读详情那一件上缺 \(missing) ⇒ 上面那句「没有分带词」是空跑（\(language.rawValue) 那遍）"
            )
            record("🕘 右栏单独那一遍（\(language.rawValue)）：分带五句 "
                + bandWords.map { "「\($0)」" }.joined(separator: " / ") + " 一句都不在；轴名 / 优先级 "
                + anchors.map { "「\($0)」" }.joined(separator: " / ") + " 都在")
        }

        // ③ 成对读数 + 源锚点：详情那一行换了取值来源，清单行 / 分组与 Core 的分带本体一字未动。
        func occurrences(_ needle: String, in text: String) -> Int {
            text.components(separatedBy: needle).count - 1
        }
        let panel = try source("App/Views/NotesPanel.swift")
        let calendar = try source("App/Views/TodoCalendarView.swift")
        let query = try source("Core/TodoQuery.swift")
        XCTAssertEqual(
            occurrences("TodoQuery.band(of:", in: panel), 0,
            "`App/Views/NotesPanel.swift` 里还有分带取值 —— 成对读数：改前 1（详情那一行）⇒ 改后 0"
        )
        XCTAssertEqual(
            occurrences("TodoDueText.text(", in: panel), 1,
            "详情那一行的取值来源该恰好一处（`TodoDueText.text(`）"
        )
        XCTAssertEqual(
            occurrences("TodoQuery.band(of:", in: calendar), 2,
            "清单行 / 分组的分带读数不许被动 —— `App/Views/TodoCalendarView.swift` 该仍是两处"
                + "（行上那句 + 色档那支 switch）"
        )
        XCTAssertTrue(
            query.contains("public static func band(of todo: Todo, window: TodoWindow) -> TodoBand {"),
            "`Core/TodoQuery.swift` 的分带本体不见了 / 签名被动过 —— 清单行 / 分组还读它（分带的唯一出处不许动）"
        )
        record("📄 成对读数：`NotesPanel.swift` 里 `TodoQuery.band(of:` "
            + "\(occurrences("TodoQuery.band(of:", in: panel)) 处、`TodoDueText.text(` "
            + "\(occurrences("TodoDueText.text(", in: panel)) 处；`TodoCalendarView.swift` "
            + "\(occurrences("TodoQuery.band(of:", in: calendar)) 处；`Core/TodoQuery.swift` 的分带本体仍在")
    }
}
