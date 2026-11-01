import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「分页控制条」与「大结果集分页」的 **App 侧探针**（`FR-STD-DB-RES-009` / `FR-STD-DB-RES-011`）
/// —— v0.3.0 数据库运维面 B2 批次。
///
/// ## 这两行为什么原来停在 🟡
/// 台账备注原文是「界面点击待人工点验」（009）与「大表实测待人工」（011）。
/// `Core/ResultGridState` 的分页与夹取本来就有单测，但那些**一个控件都没碰过**：
/// 下拉可以摆错档位（少一档「全部」用户就切不回来）、箭头可以点不动、换档位可以停在「第 3 页 ×
/// 新档位」、页码那句话可以写成「第 3 / 1 页」—— 上面那些单测照样全绿。
///
/// ## 这一片怎么量（不靠人点，也不靠「看着对」）
/// 挂**真** `ResultTableView`（生产里自己持有 `ResultGridState` 的那个视图）进离屏真窗口 →
/// 从视图树里取出分页条那枚真 `NSView`（本片把整条从 SwiftUI 换成 AppKit：`NSPopUpButton` +
/// 四枚 `NSButton` + 两句 `NSTextField`）→
/// 点箭头用 `NSButton.performClick(nil)`、换档位用 `NSPopUpButton.selectItem + sendAction`
/// （与手选同一条 action 路径）。判据读两处**用户真的看得见的东西**：
/// 表格里显示成哪几行（逐行 `NSTableCellView.textField.stringValue`）与页码那句话的**字面**。
///
/// ## 边界（如实登记）
/// · 证得住：六档都在下拉里、页码字面与总行数、换档位回第 1 页、四枚箭头各自到得了头、
///   越界页码被夹取（不出现「第 10 / 3 页」）、分页后 ⌘C 只复制当前页的行、
///   十万行结果的分页只物化一页且翻页开销与总行数无关、「仅对已加载的 N 行分页」这句标注；
/// · **证不住**：真鼠标在真屏幕上的手感与掉帧（输入设备 / 观感，归人工点验）；
///   服务端真库上的 `LIMIT` / `OFFSET` 语义（本行是**客户端**分页，压根不发语句）；
/// · **不连数据库**：数据是本文件造的合成结果；默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）。
final class ResultPagingProbeTests: XCTestCase {

    // MARK: - 合成结果

    private let columns = [
        ColumnMeta(id: 0, name: "id", typeName: "int4"),
        ColumnMeta(id: 1, name: "note", typeName: "text"),
    ]

    /// `count` 行：id 从 1 起，note 记着同一个号（判「翻到哪一页」只需看 id）。
    private func rows(_ count: Int) -> [[String?]] {
        (1...max(count, 1)).prefix(count).map { number in
            ["\(number)", "note-\(number)"]
        }
    }

    private func skipUnlessProbeEnabled() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("分页探针要真 AppKit 控件与真表格：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）")
        }
    }

    // MARK: - 离屏宿主

    private struct Host {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>
        let table: NSTableView
        let pager: ResultPagerControlsView

        func tearDown() { window.contentView = nil }
    }

    @MainActor
    private func mount(
        rowCount: Int = 421,
        pageSize: Int = 200,
        pageIndex: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Host {
        var grid = ResultGridState()
        grid.pageSize = pageSize
        grid.pageIndex = pageIndex
        let result = QueryResult(columns: columns, rows: rows(rowCount), executionTime: 0.01)
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
        hosting.frame = CGRect(x: 0, y: 0, width: 1000, height: 480)

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1000, height: 480),
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
        let pager = try XCTUnwrap(
            Self.allViews(in: hosting).compactMap { $0 as? ResultPagerControlsView }.first,
            "分页条不在场或不再是 AppKit 控件 —— 那这一整片判据都量不到（又只剩人点）",
            file: file, line: line
        )
        return Host(window: window, hosting: hosting, table: table, pager: pager)
    }

    @MainActor
    private func pump(_ seconds: TimeInterval = 0.2) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
    }

    @MainActor
    private static func allViews(in view: NSView) -> [NSView] {
        view.subviews.reduce([view]) { $0 + allViews(in: $1) }
    }

    // MARK: - 读数与动作

    /// 表格此刻**真的显示**的行（第 0 列 id）。
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

    /// 四枚箭头按**各自的提示**认（提示本身就是用户分辨它们的唯一依据）。
    @MainActor
    private func arrow(_ host: Host, _ help: String, file: StaticString = #filePath, line: UInt = #line) throws -> NSButton {
        try XCTUnwrap(
            Self.allViews(in: host.pager).compactMap { $0 as? NSButton }.first { $0.toolTip == help },
            "分页条上没有提示为「\(help)」的按钮",
            file: file, line: line
        )
    }

    @MainActor
    private func click(_ button: NSButton) {
        button.performClick(nil)
        pump()
    }

    @MainActor
    private func selectPageSize(_ host: Host, _ title: String) throws {
        let popup = host.pager.sizePopup
        XCTAssertTrue(popup.itemTitles.contains(title), "档位下拉里没有「\(title)」（有：\(popup.itemTitles)）")
        popup.selectItem(withTitle: title)
        popup.sendAction(popup.action, to: popup.target)
        pump()
    }

    // MARK: - ① 档位齐备 · 页码字面

    @MainActor
    func testPagerOffersEveryPageSizeAndSaysWhichPageOfHowMany() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(rowCount: 421, pageSize: 200)
        defer { host.tearDown() }

        let popup = host.pager.sizePopup
        XCTAssertEqual(
            popup.itemTitles,
            ["50", "100", "200", "500", "1000", L(.resultPageAll)],
            "每页行数档位不是需求写的五档 + 「全部」（少一档用户就选不到，多一档就是没定义的值）"
        )
        XCTAssertEqual(popup.titleOfSelectedItem, "200", "下拉没停在实际生效的档位上（用户看到 100、实际按 200 切）")

        XCTAssertEqual(
            host.pager.indicator.stringValue,
            L(.resultPageIndicator, 1, 3, 421),
            "页码那句话与「421 行 / 每页 200」对不上"
        )
        XCTAssertEqual(host.table.numberOfRows, 200, "第 1 页没显示满 200 行")
        XCTAssertEqual(displayedIDs(host).first, "1")
        print("🧪 分页条读数：档位 \(popup.itemTitles) / 页码「\(host.pager.indicator.stringValue)」")
    }

    // MARK: - ② 换档位回第 1 页

    @MainActor
    func testChangingPageSizeGoesBackToTheFirstPage() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(rowCount: 421, pageSize: 200)
        defer { host.tearDown() }

        click(try arrow(host, L(.resultPageNext)))
        XCTAssertEqual(
            host.pager.indicator.stringValue, L(.resultPageIndicator, 2, 3, 421),
            "点「下一页」没到第 2 页"
        )

        try selectPageSize(host, "50")
        XCTAssertEqual(
            host.pager.indicator.stringValue, L(.resultPageIndicator, 1, 9, 421),
            "换了每页行数却停在第 2 页 —— 用户会落在「第 2 页 × 新档位」这种没人预期的地方"
        )
        XCTAssertEqual(host.table.numberOfRows, 50, "换到 50 之后一页不是 50 行")
        XCTAssertEqual(displayedIDs(host).first, "1", "换档位之后第一行不是第 1 行")
        let afterResize = host.pager.indicator.stringValue

        // 「全部」这一档：一页装下所有行，箭头全灰（点了也没得更远）。
        try selectPageSize(host, L(.resultPageAll))
        XCTAssertEqual(host.table.numberOfRows, 421, "选「全部」之后表格不是整段显示")
        XCTAssertFalse(try arrow(host, L(.resultPageLast)).isEnabled, "「全部」档下「最后一页」还能点")
        print("🧪 换档位读数：50 档 → 「\(afterResize)」；全部档 → \(host.table.numberOfRows) 行")
    }

    // MARK: - ③ 四枚箭头各自到得了头

    @MainActor
    func testFirstPreviousNextAndLastEachLandOnTheirPage() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(rowCount: 421, pageSize: 200)
        defer { host.tearDown() }

        let first = try arrow(host, L(.resultPageFirst))
        let previous = try arrow(host, L(.resultPagePrevious))
        let next = try arrow(host, L(.resultPageNext))
        let last = try arrow(host, L(.resultPageLast))

        // 站在第 1 页时「往回」的两枚是灰的（点不动 = 走到头了，不是点了没反应）。
        XCTAssertFalse(first.isEnabled, "第 1 页上「第一页」还能点")
        XCTAssertFalse(previous.isEnabled, "第 1 页上「上一页」还能点")

        click(next)
        XCTAssertEqual(host.pager.indicator.stringValue, L(.resultPageIndicator, 2, 3, 421))
        XCTAssertEqual(displayedIDs(host).first, "201", "第 2 页第一行不是第 201 行")

        click(last)
        XCTAssertEqual(host.pager.indicator.stringValue, L(.resultPageIndicator, 3, 3, 421))
        XCTAssertEqual(host.table.numberOfRows, 21, "最后一页只有 21 行（421 = 200 + 200 + 21）")
        let lastPageRows = host.table.numberOfRows
        let lastPageLastID = displayedIDs(host).last ?? "nil"
        XCTAssertEqual(displayedIDs(host).last, "421")
        XCTAssertFalse(next.isEnabled, "最后一页上「下一页」还能点")
        XCTAssertFalse(last.isEnabled, "最后一页上「最后一页」还能点")

        click(previous)
        XCTAssertEqual(host.pager.indicator.stringValue, L(.resultPageIndicator, 2, 3, 421))

        click(first)
        XCTAssertEqual(host.pager.indicator.stringValue, L(.resultPageIndicator, 1, 3, 421))
        XCTAssertEqual(displayedIDs(host).first, "1")
        print("🧪 四箭头读数：末页 \(lastPageRows) 行 / 末行 \(lastPageLastID)")
    }

    // MARK: - ④ 越界页码被夹取（不出现「第 10 / 3 页」）

    @MainActor
    func testOutOfRangePageIndexIsClampedNotShownAsPageTenOfThree() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(rowCount: 421, pageSize: 200, pageIndex: 9)
        defer { host.tearDown() }

        XCTAssertEqual(
            host.pager.indicator.stringValue, L(.resultPageIndicator, 3, 3, 421),
            "页码越界时那句话照抄了状态里的 9 ⇒ 界面上出现「第 10 / 3 页」"
        )
        XCTAssertEqual(displayedIDs(host).last, "421", "越界页码没被夹到最后一页（会显示一页空白）")
        XCTAssertFalse(try arrow(host, L(.resultPageNext)).isEnabled, "夹取后的页码上「下一页」仍可点")
        print("🧪 夹取读数：「\(host.pager.indicator.stringValue)」/ 末行 \(displayedIDs(host).last ?? "nil")")
    }

    // MARK: - ⑤ 分页后复制取的是当前页的行

    @MainActor
    func testCopyAfterPagingTakesOnlyTheRowsOnTheCurrentPage() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(rowCount: 421, pageSize: 200)
        defer { host.tearDown() }

        click(try arrow(host, L(.resultPageNext)))
        host.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertEqual(host.table.selectedRowIndexes, IndexSet(integer: 0), "选中态没设上（前提不成立）")

        let menu = try XCTUnwrap(host.table.menu, "表格没挂右键菜单 —— ⌘C 那条路不在")
        let copyItem = try XCTUnwrap(
            menu.items.first { $0.action == NSSelectorFromString("copy:") },
            "右键菜单里没有「复制」（⌘C 那一项）"
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("SENTINEL", forType: .string)
        _ = copyItem.target?.perform(copyItem.action, with: copyItem)

        let copied = NSPasteboard.general.string(forType: .string) ?? ""
        let lines = copied.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.first, "id\tnote", "复制没有带表头：\(copied)")
        XCTAssertEqual(lines.count, 2, "复制了 \(lines.count - 1) 行 —— 第 2 页上只选了一行，却复制了别的页的行：\(copied)")
        XCTAssertEqual(lines.last, "201\tnote-201", "复制到的不是当前页的第 1 行：\(copied)")
        XCTAssertFalse(copied.contains("1\tnote-1"), "复制把第 1 页的行也带上了（分页内下标的映射错了）")
        print("🧪 分页复制读数：\(lines.count - 1) 行 / 「\(lines.last ?? "nil")」")
    }

    // MARK: - ⑥ 十万行：只物化一页，翻页开销与总行数无关（RES-011 ① / ③）

    @MainActor
    func testLargeResultPagesOnePageAtATimeAndStaysResponsive() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(rowCount: 100_000, pageSize: 200)
        defer { host.tearDown() }

        XCTAssertEqual(
            host.pager.indicator.stringValue, L(.resultPageIndicator, 1, 500, 100_000),
            "十万行 / 每页 200 应当是 500 页"
        )
        XCTAssertEqual(host.table.numberOfRows, 200, "一页只该物化 200 行，实际 \(host.table.numberOfRows) 行")

        let started = Date()
        click(try arrow(host, L(.resultPageLast)))
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(
            host.pager.indicator.stringValue, L(.resultPageIndicator, 500, 500, 100_000),
            "十万行直接跳末页没落到第 500 页"
        )
        XCTAssertEqual(host.table.numberOfRows, 200, "末页也只该物化 200 行")
        XCTAssertLessThan(elapsed, 2.0, "跳到末页花了 \(elapsed) 秒 —— 分页没起作用（一次把十万行都摆出来了）")

        // ③ 换档位回第 1 页（大结果集这一档同样成立）。
        try selectPageSize(host, "1000")
        XCTAssertEqual(
            host.pager.indicator.stringValue, L(.resultPageIndicator, 1, 100, 100_000),
            "十万行换到 1000 档应当是 100 页且回到第 1 页"
        )
        XCTAssertEqual(host.table.numberOfRows, 1_000, "1000 档一页不是 1000 行")
        print("🧪 十万行读数：\(host.table.numberOfRows) 行/页 · 跳末页 \(String(format: "%.0f", elapsed * 1000)) ms")
    }

    // MARK: - ⑦ 界面标注「仅对已加载的 N 行分页」（RES-011 ② / R-21）

    @MainActor
    func testPagerSaysItOnlyPagesTheLoadedRows() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(rowCount: 421, pageSize: 200)
        defer { host.tearDown() }

        XCTAssertFalse(host.pager.loadedNote.isHidden, "分页时没有那句「仅对已加载的 N 行分页」—— 用户会以为翻页是在查服务端")
        XCTAssertEqual(
            host.pager.loadedNote.stringValue,
            L(.resultPageClientOnlyNote, 421),
            "标注里的行数不是「已取回的行数」"
        )

        try selectPageSize(host, L(.resultPageAll))
        XCTAssertTrue(host.pager.loadedNote.isHidden, "选「全部」之后还挂着「分页」的标注（这时压根没分页）")
        XCTAssertTrue(host.pager.loadedNote.stringValue.isEmpty, "收起的标注里还留着旧文案")
        print("🧪 标注读数：「\(L(.resultPageClientOnlyNote, 421))」")
    }
}
