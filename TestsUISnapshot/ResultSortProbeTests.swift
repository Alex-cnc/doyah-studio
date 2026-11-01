import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「客户端排序」的 **App 侧探针**（`FR-STD-DB-RES-007`）—— v0.3.0 数据库运维面第二跳。
///
/// ## 这一行为什么原来停在 🟡
/// 台账备注写的是「界面点击待人工点验」。`Core/ResultView` 的排序规则本来就有单测
/// （数值序 / 自然序 / 多列 / 稳定 / NULL 先后），但那些**没有一处碰过表头**：
/// 表头可以没有 `sortDescriptorPrototype`（AppKit 于是不画指示器、也不派发任何变化，
/// 点上去等于点一块死木头）、派发时可以把列号认错（Shift 加次要键时第一个描述符还是老主键）、
/// 第三下可以取消不掉 —— 上面那些单测照样全绿。
///
/// ## 这条探针怎么量（不靠人点，也不靠「看着对」）
/// 挂**真** `ResultTableView`（生产里那个自己持有 `ResultGridState` 的视图）进离屏真窗口
/// → 从视图树里取出真 `NSTableView` → 取**真表头**（`tableView.headerView`）
/// → 用截图上那一列的中间点造 `NSEvent`，把 `mouseUp` 投进 `NSApplication` 的事件队列，
/// 再把 `mouseDown` **直接交给表头自己的 `mouseDown(with:)`** —— 这与用户点一下走的是
/// 同一条 AppKit 路径（跟踪循环、指示器、`sortDescriptorsDidChange` 都在里面），
/// 不是「直接改状态再断言状态」。
/// 判据是**表格里真的显示成什么**（逐行读 `NSTableCellView.textField.stringValue`），
/// 外加表头指示器（`tableView.sortDescriptors`）。
///
/// ## 边界（如实登记）
/// · 证得住：表头每一列都带排序原型、点击点落在哪一列、升 / 降 / 取消三档、
///   数值按数值比（9 排在 10 前）、NULL 在两种方向下都留在末尾、Shift 加 / 翻 / 删次要键、
///   点表头空白处与列分界线不排序、排序不改列宽、原始结果集不被改写（取消后回到服务端顺序）；
/// · **证不住**：真鼠标在真屏幕上的手感（双击节奏、拖拽超过几像素才算拖列）—— 那是输入设备
///   行为，与 `FR-STD-DB-RES-009` 的分页条同理，不在本行验收要点里；
/// · **不连数据库**：数据是本文件造的合成结果；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 与其他端上探针同一条纪律：取证才跑。
final class ResultSortProbeTests: XCTestCase {

    // MARK: - 合成结果

    private let columns = [
        ColumnMeta(id: 0, name: "id", typeName: "int4"),
        ColumnMeta(id: 1, name: "note", typeName: "text"),
        ColumnMeta(id: 2, name: "amount", typeName: "int4"),
    ]

    /// 七行，刻意带上判据要用的四种东西：
    /// · `amount` 同时有 **9 与 10**（字符串序会把 10 排前面，数值序才是 9 在前）；
    /// · `amount` 有**两行 NULL**（第 4、6 行，一个在 b 组一个在 a 组）—— 用来判「NULL 位置固定」；
    /// · `note` 只有 a / b 两个值，且与 `amount` 的大小序**相反**（多列排序才看得出差别）。
    private let rows: [[String?]] = [
        ["1", "b", "30"],
        ["2", "a", "30"],
        ["3", "b", "10"],
        ["4", "a", "10"],
        ["5", "b", nil],
        ["6", "a", "9"],
        ["7", "a", nil],
    ]

    /// 服务端返回的原始顺序（取消排序后必须回到这个）。
    private var serverOrder: [String] { rows.map { $0[0] ?? "NULL" } }

    private func skipUnlessProbeEnabled() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("排序探针要真 AppKit 表头与真表格：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）")
        }
    }

    // MARK: - 离屏宿主

    private struct Host {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>
        let table: NSTableView

        var header: NSTableHeaderView? { table.headerView }

        func tearDown() {
            window.contentView = nil
        }
    }

    /// 把**真** `ResultTableView`（生产里持有 `ResultGridState` 的那个视图）挂进离屏窗口。
    ///
    /// 为什么挂它而不是直接挂 `ResultGrid`：表头点击的全部意义是「点了之后显示的行变了」，
    /// 而「该显示哪些行」正是这个视图里的 `ResultGridState` 算出来的 —— 绕过它，
    /// 判据就只剩「回调被调用了」，那与用户看到的东西不是一回事。
    @MainActor
    private func mount() throws -> Host {
        let result = QueryResult(columns: columns, rows: rows, executionTime: 0.01)
        let root = AnyView(
            ResultTableView(result: result, resultCount: 1, selectedIndex: 0, isExecuting: false)
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

        let table = try XCTUnwrap(Self.firstTableView(in: hosting), "离屏宿主里没有 NSTableView —— 挂载路径坏了")
        XCTAssertEqual(table.numberOfRows, rows.count, "表格没把六行装进来（后续判据会量到假值）")
        XCTAssertNotNil(table.headerView, "表格没有表头 —— 没有可点的排序入口")
        return Host(window: window, hosting: hosting, table: table)
    }

    @MainActor
    private func pump(_ seconds: TimeInterval = 0.12) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
    }

    @MainActor
    private static func firstTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews {
            if let found = firstTableView(in: child) { return found }
        }
        return nil
    }

    // MARK: - 点表头（走 AppKit 自己那条路）

    /// 点第 `columnIndex` 列的表头。
    ///
    /// 事件构造照 AppKit 的要求来：`locationInWindow` 用**表头自己换算出来**的窗口坐标
    /// （表头挂在滚动视图的 header clip 上，不是表格坐标系），`mouseUp` 先投进事件队列 ——
    /// 表头的 `mouseDown` 里有一个跟踪循环在等它，不投就会卡住（本轮实测：投了就正常返回）。
    @MainActor
    @discardableResult
    private func clickHeader(
        _ columnIndex: Int,
        shift: Bool = false,
        in host: Host,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSPoint {
        let header = try XCTUnwrap(host.header, "表头不见了", file: file, line: line)
        let rect = host.table.rect(ofColumn: columnIndex)
        XCTAssertGreaterThan(rect.width, 4, "第 \(columnIndex) 列宽度异常，点不到中间", file: file, line: line)
        // 表头挂在**它自己的** header clip 上（与表格不是同一个父视图、翻转方向也不同），
        // 所以点要从表头自己的坐标系换算出去，不能拿表格坐标硬转（实测会转到窗口外、columnAt = -1）。
        let point = header.convert(NSPoint(x: rect.midX, y: header.bounds.midY), to: nil)
        let flags: NSEvent.ModifierFlags = shift ? [.shift] : []
        try click(at: point, flags: flags, in: host, file: file, line: line)
        pump()
        return point
    }

    /// 在表头坐标 `point`（已换成窗口坐标）按下一次。
    @MainActor
    private func click(
        at windowPoint: NSPoint,
        flags: NSEvent.ModifierFlags,
        in host: Host,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let header = try XCTUnwrap(host.header, "表头不见了", file: file, line: line)
        let now = ProcessInfo.processInfo.systemUptime
        let down = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: flags,
            timestamp: now,
            windowNumber: host.window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ), "造不出 mouseDown ⇒ 这条判据的输入没了", file: file, line: line)
        let up = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: flags,
            timestamp: now + 0.01,
            windowNumber: host.window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        ), "造不出 mouseUp", file: file, line: line)
        // 跟踪循环在 `mouseDown` 里等这一条；不投进去，`mouseDown` 会一直等下去。
        NSApplication.shared.postEvent(up, atStart: false)
        header.mouseDown(with: down)
    }

    // MARK: - 读数

    /// 表格此刻**真的显示**的行（按第 0 列 `id` 读，逐格从控件里取）。
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

    /// 表头指示器（AppKit 那一侧）现在是什么排序键。
    @MainActor
    private func indicator(_ host: Host) -> [(key: String, ascending: Bool)] {
        host.table.sortDescriptors.compactMap { descriptor in
            guard let key = descriptor.key else { return nil }
            return (key, descriptor.ascending)
        }
    }

    @MainActor
    private func columnWidths(_ host: Host) -> [CGFloat] {
        host.table.tableColumns.map(\.width)
    }

    // MARK: - 用例

    /// ① 表头每一列都**真的能点**：带排序原型（AppKit 靠它画指示器、派发变化），
    ///    而且点这一列的中间点，命中的就是这一列（点 A 排 B 的那种错行最难看）。
    @MainActor
    func testEveryHeaderCellIsSortableAndAClickLandsOnItsOwnColumn() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        let header = try XCTUnwrap(host.header)
        for (index, column) in host.table.tableColumns.enumerated() {
            let prototype = try XCTUnwrap(
                column.sortDescriptorPrototype,
                "第 \(index) 列没有排序原型 —— AppKit 不会画指示器、也不会派发 sortDescriptorsDidChange，点上去等于点一块死木头"
            )
            XCTAssertEqual(prototype.key, "\(index)", "第 \(index) 列的排序原型键不是列号（派发时会认错列）")
            XCTAssertTrue(prototype.ascending, "第 \(index) 列的排序原型默认不是升序（第一下点击会出反序）")

            let local = NSPoint(x: host.table.rect(ofColumn: index).midX, y: header.bounds.midY)
            XCTAssertEqual(
                header.column(at: local), index,
                "点第 \(index) 列的中间点，表头认成了别的列（点 A 排 B）"
            )
        }
    }

    /// ② 点一下升序、再点降序、第三下取消回到服务端顺序；指示器跟着走；列宽一动不动。
    @MainActor
    func testClickingTheHeaderCyclesAscendingDescendingAndBackToServerOrder() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        XCTAssertEqual(displayedIDs(host), serverOrder, "初始就该是服务端顺序")
        let widthsBefore = columnWidths(host)

        // 第 2 列 = amount。数值序：9 < 10 < 10 < 30 < 30 < NULL(NULL 在末尾)
        try clickHeader(2, in: host)
        XCTAssertEqual(displayedIDs(host), ["6", "3", "4", "1", "2", "5", "7"],
                       "升序不是「数值 9 在最前、NULL 在最后」—— 字符串序或 NULL 位置错了")
        XCTAssertEqual(indicator(host).map(\.key), ["2"], "表头指示器没落在被点的列上")
        XCTAssertEqual(indicator(host).map(\.ascending), [true], "第一下应当是升序")

        try clickHeader(2, in: host)
        XCTAssertEqual(displayedIDs(host), ["1", "2", "3", "4", "6", "5", "7"], "第二下应当是降序")
        XCTAssertEqual(indicator(host).map(\.ascending), [false], "表头指示器没翻成降序")

        try clickHeader(2, in: host)
        XCTAssertEqual(displayedIDs(host), serverOrder, "第三下应当取消排序、回到服务端原始顺序")
        XCTAssertTrue(indicator(host).isEmpty, "取消了排序，表头指示器还留着 —— 用户会以为还在排序")

        XCTAssertEqual(columnWidths(host), widthsBefore, "点表头把列宽改了（排序点击不许动列宽）")
    }

    /// ③ NULL 位置固定：升序在末尾，**降序也还在末尾**（这条是早期实现把整段比较结果按方向
    ///    取反、于是降序时 NULL 跑到最前面那次事故的回归钉）。
    @MainActor
    func testNullsStayAtTheEndInBothDirections() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        try clickHeader(2, in: host)
        // 9、10、10、30、30、NULL、NULL（两个 NULL 是两个不同的行，稳定的服务端顺序是 5 再 7）
        XCTAssertEqual(displayedIDs(host), ["6", "3", "4", "1", "2", "5", "7"], "升序时 NULL 没留在末尾")

        try clickHeader(2, in: host)
        // 降序：30、30、10、10、9、NULL、NULL —— **NULL 还在末尾**（不跟着方向翻到最前）
        XCTAssertEqual(displayedIDs(host), ["1", "2", "3", "4", "6", "5", "7"], "降序时 NULL 跑到前面去了")
    }

    /// ④ Shift 点第二列 = **追加次要键**，主键不许丢。
    ///
    /// 这一条钉的是本轮修掉的真缺陷：以前派发时读 `sortDescriptors.first`，而 Shift 点击
    /// 把新列追加在后面，第一个仍是被点的老主键 ⇒ 多列排序永远加不上新列。
    @MainActor
    func testShiftClickAddsASecondaryKeyWithoutLosingThePrimary() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        // 第 1 列 = note：a 组 [2,4,6]、b 组 [1,3,5]（稳定，按服务端顺序）
        try clickHeader(1, in: host)
        XCTAssertEqual(displayedIDs(host), ["2", "4", "6", "7", "1", "3", "5"], "按 note 升序的起点不对")

        // Shift 点 amount：先按 note，再在每组内按 amount 升序（NULL 留在该组末尾）
        try clickHeader(2, shift: true, in: host)
        XCTAssertEqual(displayedIDs(host), ["6", "4", "2", "7", "3", "1", "5"],
                       "Shift 点第二列没加上次要键（多列排序的入口失效）")
        XCTAssertEqual(indicator(host).map(\.key), ["1", "2"], "表头指示器里没有两个排序键")
        XCTAssertEqual(indicator(host).map(\.ascending), [true, true], "两个键都该是升序")
    }

    /// ⑤ Shift 再点同一个次要键：先翻方向，再点一下把它**只删这一键**（主键留着）。
    @MainActor
    func testShiftClickOnTheSecondaryKeyFlipsThenRemovesOnlyThatKey() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        try clickHeader(1, in: host)
        try clickHeader(2, shift: true, in: host)
        XCTAssertEqual(displayedIDs(host), ["6", "4", "2", "7", "3", "1", "5"])

        try clickHeader(2, shift: true, in: host)
        XCTAssertEqual(displayedIDs(host), ["2", "4", "6", "7", "1", "3", "5"], "次要键没翻成降序")
        XCTAssertEqual(indicator(host).map(\.ascending), [true, false], "指示器没跟着翻")

        try clickHeader(2, shift: true, in: host)
        XCTAssertEqual(indicator(host).map(\.key), ["1"], "次要键没被删掉（主键该留着）")
        XCTAssertEqual(displayedIDs(host), ["2", "4", "6", "7", "1", "3", "5"], "删掉次要键后顺序不对")
    }

    /// ⑥ 负例：点表头**空白处**（最后一列右边）什么都不发生 —— 不许凭空清掉排序、也不许排成别的。
    @MainActor
    func testClickingTheEmptyHeaderAreaChangesNothing() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        try clickHeader(1, in: host)
        let sorted = displayedIDs(host)
        let keys = indicator(host).map(\.key)

        let header = try XCTUnwrap(host.header)
        let lastRect = host.table.rect(ofColumn: host.table.numberOfColumns - 1)
        let emptyX = max(lastRect.maxX + 40, header.bounds.maxX - 4)
        XCTAssertEqual(header.column(at: NSPoint(x: emptyX, y: header.bounds.midY)), -1, "这个点其实还在某一列上（负例的前提不成立）")
        let point = header.convert(NSPoint(x: emptyX, y: header.bounds.midY), to: nil)
        try click(at: point, flags: [], in: host)
        pump()

        XCTAssertEqual(indicator(host).map(\.key), keys, "点空白处把排序键改了")
        XCTAssertEqual(displayedIDs(host), sorted, "点空白处把显示顺序改了")
    }
}
