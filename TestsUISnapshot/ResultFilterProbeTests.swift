import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「客户端筛选：每列可加条件」的 **App 侧探针**（`FR-STD-DB-RES-008`）—— v0.3.0 数据库运维面第三跳。
///
/// ## 这一行为什么原来停在 🟡
/// 台账备注原文是「界面点击待人工点验」。`Core/ResultView` 的筛选规则本来就有单测
/// （包含 / 不包含 / 等于 / 大于 / 小于 / 为空 / 大小写），但那些**一个控件都没碰过**：
/// 结果区顶部那条「客户端视图条」可以根本不渲染、筛选条件可以是死的、值输入框可以把编辑会话
/// 弄没 —— 上面那些单测照样全绿。
///
/// ## 这条探针怎么量（不靠人点，也不靠「看着对」）
/// 挂**真** `ResultTableView`（生产里自己持有 `ResultGridState` 的视图）进离屏真窗口 →
/// 从视图树里取真 `NSTableView` 与条上的真控件 →
/// 点按钮用 `NSButton.performClick(nil)`、换列 / 换运算符用
/// `NSPopUpButton.selectItem + sendAction`（与手选同一条 action 路径）、
/// 打字走**字段编辑器**（`makeFirstResponder` → `currentEditor().insertText`，与手打同一条路）。
/// 判据读的是**表格里真的显示成什么**（逐行 `NSTableCellView.textField.stringValue`），
/// 不是「回调被调用了」。
///
/// ## 本批实测抓到并修掉的两个真缺陷
/// 1. **筛选条只在 `isClientViewActive` 时才渲染**，而唯一的「+ 加条件」入口就在条里 ⇒
///    没排过序的用户永远加不了第一个筛选条件（和 2026-09-23 分页条那次是同一个形状的死路）。
///    现在只要结果有列就渲染条；「仅对已加载的 N 行生效」那句提示改成按状态出现。
/// 2. **点「+」当场把整张表清空**：新条件默认 `contains ""`，而 Foundation 里
///    `"abc".contains("") == false`、`range(of: "") == nil` ⇒ 一条还没填值的条件筛掉了所有行。
///    现在 `ResultFilter.isPending`（要值但还没值）不参与筛选，也进不了生成的 WHERE。
///
/// ## 边界（如实登记）
/// · 证得住：条默认在场、「+」真的能点、加条件不丢行、列 / 运算符换得动并且**表格跟着变**、
///   值输入框逐字打进状态且编辑会话不丢、大小写开关、删单条条件、多条件 AND、删完回到服务端顺序；
/// · **证不住**：真鼠标在真屏幕上的手感（点开菜单时的弹出动画、拖选文本）—— 输入设备行为，
///   与本条验收要点无关；条右侧「清空全部条件 / 生成 WHERE」两颗仍是 SwiftUI `.plain` 按钮
///   （`ToolbarIconButton` 不落成 `NSButton`，量不到点击），这两条留给 009 那一批一起搬；
/// · **不连数据库**：数据是本文件造的合成结果；默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）。
final class ResultFilterProbeTests: XCTestCase {

    // MARK: - 合成结果

    private let columns = [
        ColumnMeta(id: 0, name: "id", typeName: "int4"),
        ColumnMeta(id: 1, name: "note", typeName: "text"),
    ]

    /// 五行，刻意带上判据要用的东西：
    /// · `note` 同时有 `beta` 与 `BETA`（大小写开关才量得出差别）；
    /// · 一个 NULL（第 3 行）与一个空串（第 5 行）—— 「为空」要同时命中两者；
    /// · `id` 是 1…5，任何「包含 a」在 id 列上都命中 0 行（换列才量得出差别）。
    private let rows: [[String?]] = [
        ["1", "beta"],
        ["2", "BETA"],
        ["3", nil],
        ["4", "gamma"],
        ["5", ""],
    ]

    private var serverOrder: [String] { rows.map { $0[0] ?? "NULL" } }

    private func skipUnlessProbeEnabled() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("筛选探针要真 AppKit 控件与真表格：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）")
        }
    }

    // MARK: - 离屏宿主

    private struct Host {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>
        let table: NSTableView

        func tearDown() { window.contentView = nil }
    }

    /// 挂**真** `ResultTableView`。`filters` / `sortDescriptors` 走产品的 `initialState` 入参
    /// （与快照基建同一条路），不额外给测试开后门。
    @MainActor
    private func mount(
        filters: [ResultFilter] = [],
        sortDescriptors: [ResultSortDescriptor] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Host {
        var grid = ResultGridState()
        grid.filters = filters
        grid.sortDescriptors = sortDescriptors
        let result = QueryResult(columns: columns, rows: rows, executionTime: 0.01)
        let root = AnyView(
            ResultTableView(
                result: result,
                resultCount: 1,
                selectedIndex: 0,
                isExecuting: false,
                initialState: ResultViewState(grid: grid)
            )
            .environmentObject(AppState())
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(x: 0, y: 0, width: 900, height: 420)

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        pump()

        let table = try XCTUnwrap(
            Self.allViews(in: hosting).compactMap { $0 as? NSTableView }.first,
            "离屏宿主里没有 NSTableView —— 挂载路径坏了",
            file: file, line: line
        )
        return Host(window: window, hosting: hosting, table: table)
    }

    @MainActor
    private func pump(_ seconds: TimeInterval = 0.15) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
    }

    @MainActor
    private static func allViews(in view: NSView) -> [NSView] {
        view.subviews.reduce([view]) { $0 + allViews(in: $1) }
    }

    // MARK: - 读数

    /// 表格此刻**真的显示**的行（按第 0 列 `id` 逐格从控件里取）。
    @MainActor
    private func displayedIDs(_ host: Host, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        (0..<host.table.numberOfRows).compactMap { row in
            guard let cell = host.table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView else {
                XCTFail("第 \(row) 行取不到单元格", file: file, line: line)
                return nil
            }
            return cell.textField?.stringValue
        }
    }

    /// 条上所有「按钮」（排除弹出按钮，它也在 NSButton 家族里）。
    @MainActor
    private func plainButtons(_ host: Host) -> [NSButton] {
        Self.allViews(in: host.hosting)
            .compactMap { $0 as? NSButton }
            .filter { !($0 is NSPopUpButton) }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// 条上所有弹出按钮，按 x 从左到右：每个条件「先列后运算符」。
    @MainActor
    private func popups(_ host: Host) -> [NSPopUpButton] {
        Self.allViews(in: host.hosting)
            .compactMap { $0 as? NSPopUpButton }
            .filter { !$0.itemTitles.isEmpty }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    @MainActor
    private func columnPopups(_ host: Host) -> [NSPopUpButton] {
        let names = columns.map(\.name)
        return popups(host).filter { $0.itemTitles == names }
    }

    @MainActor
    private func operatorPopups(_ host: Host) -> [NSPopUpButton] {
        let labels = ResultFilterOperator.allCases.map(filterOperatorLabel)
        return popups(host).filter { $0.itemTitles == labels }
    }

    /// 值输入框（可编辑的那些，按 x 排序）。
    @MainActor
    private func valueFields(_ host: Host) -> [NSTextField] {
        Self.allViews(in: host.hosting)
            .compactMap { $0 as? NSTextField }
            .filter { $0.isEditable }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    /// 「+ 加条件」：它是条上最后一颗无标题图标按钮（条件的 `×` 都在它左边）。
    @MainActor
    private func addFilterButton(_ host: Host) throws -> NSButton {
        let buttons = plainButtons(host)
        return try XCTUnwrap(buttons.last, "条上没有按钮 —— 「+ 加条件」入口不在场")
    }

    // MARK: - 动作（走真控件那条路）

    @MainActor
    private func click(_ button: NSButton) {
        button.performClick(nil)
        pump()
    }

    @MainActor
    private func select(_ popup: NSPopUpButton, _ title: String) throws {
        XCTAssertTrue(popup.itemTitles.contains(title), "弹出按钮里没有「\(title)」（有：\(popup.itemTitles)）")
        popup.selectItem(withTitle: title)
        popup.sendAction(popup.action, to: popup.target)
        pump()
    }

    /// 在输入框里逐字打（作者手打走的就是字段编辑器这条）。
    @MainActor
    @discardableResult
    private func type(_ text: String, into field: NSTextField, in host: Host) throws -> NSTextView {
        host.window.makeFirstResponder(field)
        pump(0.2)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView,
                                   "输入框没能起字段编辑器（编辑会话都没起来，这条判据测不到东西）")
        editor.selectAll(nil)
        for character in text {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
            pump(0.12)
            XCTAssertNotNil(field.currentEditor(),
                            "打字把编辑会话收掉了（`currentEditor()` 没了）—— 用户只能一个字一个字地重新点进去")
        }
        pump()
        return editor
    }

    // MARK: - 用例

    /// ① 死路回归钉：**没做过任何客户端操作**时条也在场，「+」点得动，
    ///    而且加出来的条件**不参与筛选**（表格一行不少）。
    @MainActor
    func testBarIsAlwaysPresentAndAddingAWaitingConditionKeepsEveryRow() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        XCTAssertEqual(displayedIDs(host), serverOrder, "初始就该是服务端顺序")
        XCTAssertTrue(popups(host).isEmpty, "还没加条件就有条件了（前提不成立）")

        let add = try addFilterButton(host)
        XCTAssertEqual(displayedIDs(host), serverOrder, "初始顺序不该被动过")

        click(add)

        XCTAssertEqual(
            displayedIDs(host), serverOrder,
            "点了「+」表格就少行了 —— 新条件（还没填值）被当成「匹配零行」，用户还没输入就先丢了全部行"
        )
        XCTAssertEqual(columnPopups(host).count, 1, "点「+」之后没有出现「选列」的弹出按钮（条件没加成）")
        XCTAssertEqual(operatorPopups(host).count, 1, "点「+」之后没有出现「选运算符」的弹出按钮")
        XCTAssertEqual(valueFields(host).count, 1, "点「+」之后没有出现值输入框")
    }

    /// ② 换列：条件看的是**哪一列**，表格跟着变。
    @MainActor
    func testTheColumnPopupChangesWhichColumnIsFiltered() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(filters: [ResultFilter(columnIndex: 1, op: .contains, value: "a")])
        defer { host.tearDown() }

        // note 列含 a（不分大小写）：beta / BETA / gamma
        XCTAssertEqual(displayedIDs(host), ["1", "2", "4"], "按 note 筛 a 的起点不对")

        let column = try XCTUnwrap(columnPopups(host).first, "没有「选列」的弹出按钮")
        try select(column, "id")
        XCTAssertEqual(displayedIDs(host), [], "换到 id 列之后还在按 note 筛（换列没生效）")

        try select(column, "note")
        XCTAssertEqual(displayedIDs(host), ["1", "2", "4"], "换回 note 列后结果不对（换列没真的换回去）")
    }

    /// ③ 换运算符：包含 / 不包含 / 为空 三档都要真的改到显示的行。
    ///    「为空」那一档还必须把值输入框收掉（它不需要值）。
    @MainActor
    func testTheOperatorPopupSwitchesContainsNotContainsAndEmptiness() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(filters: [ResultFilter(columnIndex: 1, op: .contains, value: "a")])
        defer { host.tearDown() }

        XCTAssertEqual(displayedIDs(host), ["1", "2", "4"])
        let op = try XCTUnwrap(operatorPopups(host).first, "没有「选运算符」的弹出按钮")

        try select(op, filterOperatorLabel(.notContains))
        // 不含 a：空串那一行符合；NULL 在任何运算符下都不匹配（与 SQL 一致）
        XCTAssertEqual(displayedIDs(host), ["5"], "「不包含」没生效（NULL 也不该被算进来）")

        try select(op, filterOperatorLabel(.contains))
        XCTAssertEqual(displayedIDs(host), ["1", "2", "4"], "换回「包含」后结果不对")

        try select(op, filterOperatorLabel(.isEmpty))
        // 为空 = SQL NULL 或空串
        XCTAssertEqual(displayedIDs(host), ["3", "5"], "「为空」没同时命中 NULL 与空串")
        XCTAssertTrue(valueFields(host).isEmpty, "「为空」这一档还留着值输入框（它不需要值，留着等于让人白填）")

        try select(op, filterOperatorLabel(.contains))
        XCTAssertEqual(valueFields(host).count, 1, "换回「包含」之后值输入框没回来")
    }

    /// ④ 打字：逐字打进输入框，表格**当场**跟着变，且编辑会话一直在。
    ///
    /// 这条钉的是 `TitleBarSearchField` 那次事故的同一类风险：每敲一个字都写 SwiftUI 状态 ⇒
    /// 视图重排 ⇒ AppKit 的编辑会话被收掉（表现就是「字只进得去一个」）。
    @MainActor
    func testTypedValueFiltersLiveAndKeepsTheEditingSession() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(filters: [ResultFilter(columnIndex: 1, op: .contains, value: "")])
        defer { host.tearDown() }

        XCTAssertEqual(displayedIDs(host), serverOrder, "空值条件一开始就参与了筛选（点「+」那一刻的先丢行）")
        let field = try XCTUnwrap(valueFields(host).first, "没有值输入框")

        try type("gam", into: field, in: host)

        XCTAssertEqual(field.stringValue, "gam", "三个字没都打进去（只看得到 \(field.stringValue)）")
        XCTAssertEqual(displayedIDs(host), ["4"], "打了字表格没跟着筛（或筛错了列）")
    }

    /// ⑤ 大小写开关：同一份数据，开关一按命中的行就变。
    @MainActor
    func testCaseSensitiveToggleChangesWhichRowsMatch() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(filters: [ResultFilter(columnIndex: 1, op: .contains, value: "A")])
        defer { host.tearDown() }

        XCTAssertEqual(displayedIDs(host), ["1", "2", "4"], "不分大小写时 a/A 该命中 beta、BETA、gamma")

        // 条上的按钮从左到右：条件的「大小写」→ 条件的「×」→「+」
        let buttons = plainButtons(host)
        XCTAssertGreaterThanOrEqual(buttons.count, 3, "条上的按钮不够（大小写 / 删条件 / 加条件）")
        click(buttons[0])
        XCTAssertEqual(displayedIDs(host), ["2"], "按了大小写开关，区分大小写没生效（beta / gamma 里的小写 a 也算命中了）")

        click(buttons[0])
        XCTAssertEqual(displayedIDs(host), ["1", "2", "4"], "再按一次没回到不分大小写")
    }

    /// ⑥ 多条件 AND + 删单条条件 + 删完条还在（不是「删完入口也一起没了」）。
    @MainActor
    func testMultipleConditionsAreAndedAndRemovingThemRestoresServerOrder() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(filters: [ResultFilter(columnIndex: 1, op: .contains, value: "a")])
        defer { host.tearDown() }

        XCTAssertEqual(displayedIDs(host), ["1", "2", "4"])

        click(try addFilterButton(host))
        XCTAssertEqual(displayedIDs(host), ["1", "2", "4"], "加了第二条（还没填值）表格就变了")

        // 新条件的默认列是第 0 列（id）—— 填 "1" 之后两条是 AND 关系
        let fields = valueFields(host)
        XCTAssertEqual(fields.count, 2, "两条条件该有两个值输入框（现在 \(fields.count) 个）")
        try type("1", into: fields[1], in: host)
        XCTAssertEqual(displayedIDs(host), ["1"], "两条条件不是 AND（note 含 a 且 id 含 1 只该剩第 1 行）")

        // 删掉第一条：只剩 id 含 1
        let buttons = plainButtons(host)
        XCTAssertGreaterThanOrEqual(buttons.count, 5, "两条条件时按钮数不对：\(buttons.count)")
        // 结构：chip0[大小写, ×] chip1[大小写, ×] +
        click(buttons[1])
        XCTAssertEqual(displayedIDs(host), ["1"], "删掉 note 那条之后结果不对（id 含 1 仍该剩第 1 行）")

        // 再删掉剩下的那条：回到服务端顺序，且**条还在**（入口不许跟着消失）
        click(try XCTUnwrap(plainButtons(host).dropLast().last, "剩一条条件时找不到它的 × "))
        XCTAssertEqual(displayedIDs(host), serverOrder, "条件全删了却没回到服务端顺序")
        XCTAssertFalse(plainButtons(host).isEmpty, "条件删光之后整条没了 —— 「+」入口跟着消失就是死路")
        XCTAssertTrue(popups(host).isEmpty, "条件删光了还留着弹出按钮")
        XCTAssertTrue(valueFields(host).isEmpty, "条件删光了还留着值输入框")

        // 死路再确认：删光之后还能再加一条
        click(try addFilterButton(host))
        XCTAssertEqual(displayedIDs(host), serverOrder, "删光再加一条（还没填值）又把行弄丢了")
        XCTAssertEqual(popups(host).count, 2, "删光之后加不回条件")
    }
}
