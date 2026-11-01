import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「复制为多种格式」的 **App 侧探针**（`FR-STD-DB-RES-006`）—— v0.3.0 数据库运维面第一跳。
///
/// ## 这一行为什么原来停在 🟡
/// 台账备注写的是「界面粘贴待人工点验」。核盘之后要分开说两件事：
///   · `Core/ResultClipboard` 的**渲染**早有 13 例单测（`Tests/ResultClipboardTests`）——
///     但那测的是「把行拼成文本」，**没有一处碰过 `NSPasteboard`**；
///   · 真正交付给用户的是「右键菜单 → 选中行 → 系统剪贴板里到底是些什么字」，
///     这一段（菜单项存在 / 默认 ⌘C 是 TSV / 表头在 / 只含选中的行 / 转义对 / 不落文件）
///     **一次都没人量过**：菜单可以少一项、`copyAs` 可以把 `representedObject` 丢掉、
///     选中行可以取错——上面 13 例照样全绿。
///
/// ## 这条探针怎么量（不靠人点，也不靠「看着对」）
/// 挂**真** `ResultGrid`（`NSViewRepresentable`）进离屏真窗口 → 从视图树里取出真 `NSTableView`
/// → 用产品自己那份 `tableView.menu`（右键菜单就是它）取出菜单项 → **按菜单项自己的
/// `action` / `target` 派发**（与 AppKit 点菜单走同一个 ObjC 出口，不改道）
/// → 读 `NSPasteboard.general` 里真实的字符串。判据是**字节**，不是截图。
///
/// ## 边界（如实登记）
/// · 证得住：四种格式各自进剪贴板的**全部文本内容**（表头 / 只含选中行 / 制表符与换行被换掉 /
///   Markdown 转义 / CSV 引号 / INSERT 的表名与列清单）、默认 ⌘C = TSV、空选中不动剪贴板、
///   剪贴板里只有文本（没有文件 URL ⇒ 不落文件）；
/// · **证不住**：把这段文本真的粘进 Excel / 飞书 / 工单系统之后长什么样（那是外部软件的行为，
///   与 `FR-STD-DB-RES-014`「Excel 打开需人工」同一类边界，不在本行验收要点里）；
/// · **不连数据库**：数据是本文件造的合成结果；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 与其它端上探针同一条纪律：取证才跑，每轮门禁不跑。
final class ResultCopyProbeTests: XCTestCase {

    // MARK: - 合成结果

    private let columns = [
        ColumnMeta(id: 0, name: "id", typeName: "int4"),
        ColumnMeta(id: 1, name: "note", typeName: "text"),
        ColumnMeta(id: 2, name: "amount", typeName: "numeric"),
    ]

    /// 四行，刻意各带一种「贴进去会错位」的东西：
    /// 第 0 行是**没选中的**（证明「只复制选中的行」）；第 2 行带竖线；第 3 行带真制表符与换行。
    private let rows: [[String?]] = [
        ["0", "skipped-row", "0"],
        ["1", "alpha", "10.5"],
        ["2", "be|ta", nil],
        ["3", "tab\there\nnew", "30"],
    ]

    /// 选中的行（显示下标）：跳开第 0 行。
    private let selected: IndexSet = [1, 2, 3]

    private func skipUnlessProbeEnabled() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("复制探针要真 AppKit 表格与真系统剪贴板：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）")
        }
    }

    // MARK: - 离屏宿主

    private struct Host {
        let window: NSWindow
        let hosting: NSHostingView<ResultGrid>
        let table: NSTableView

        func tearDown() {
            window.contentView = nil
        }
    }

    /// 把**真** `ResultGrid` 挂进离屏窗口（不上屏：无人值守的机器不该闪一下）。
    @MainActor
    private func mount(sourceTable: DatabaseObjectRef? = nil) throws -> Host {
        let result = QueryResult(columns: columns, rows: rows, executionTime: 0.01)
        let grid = ResultGrid(
            result: result,
            displayedRows: rows,
            copySourceTable: sourceTable
        )
        let hosting = NSHostingView(rootView: grid)
        hosting.frame = CGRect(x: 0, y: 0, width: 640, height: 320)

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 320),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let scroll = try XCTUnwrap(Self.firstScrollView(in: hosting), "离屏宿主里没有 NSScrollView —— 挂载路径坏了")
        let table = try XCTUnwrap(scroll.documentView as? NSTableView, "滚动视图的 documentView 不是 NSTableView")
        XCTAssertEqual(table.numberOfRows, rows.count, "表格没把四行装进来（后续判据会量到假值）")

        table.selectRowIndexes(selected, byExtendingSelection: false)
        XCTAssertEqual(table.selectedRowIndexes, selected, "选中态没设上")
        return Host(window: window, hosting: hosting, table: table)
    }

    @MainActor
    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let found = firstScrollView(in: child) { return found }
        }
        return nil
    }

    // MARK: - 派发（走产品自己那份菜单）

    /// 右键菜单里「复制为…」那一项（它带子菜单）。
    ///
    /// 认它的方式是**它子菜单里装着格式项**（`representedObject` = 格式 rawValue）——
    /// 不按「`action == nil`」找：AppKit 一给菜单项挂上 `submenu` 就会把它的 action 改成
    /// `submenuAction:`，按 nil 找一条都找不到（本探针第一版就是这么空手的）。
    @MainActor
    private func copyAsItem(in table: NSTableView) throws -> NSMenuItem {
        let menu = try XCTUnwrap(table.menu, "表格没挂右键菜单 —— 用户根本点不到「复制为…」")
        let formats = Set(ResultClipboard.Format.allCases.map(\.rawValue))
        let item = try XCTUnwrap(
            menu.items.first { item in
                guard let submenu = item.submenu else { return false }
                return submenu.items.contains { formats.contains($0.representedObject as? String ?? "") }
            },
            "右键菜单里没有「复制为…」那一项（子菜单里没有任何格式项）"
        )
        return item
    }

    /// 子菜单里某个格式对应的菜单项。**按 `representedObject` 找，不按标题找**：
    /// 标题会本地化，用标题当分派键的那天，中文环境下就再也找不到这一项了。
    @MainActor
    private func menuItem(for format: ResultClipboard.Format, in table: NSTableView) throws -> NSMenuItem {
        let submenu = try XCTUnwrap(copyAsItem(in: table).submenu, "「复制为…」没有子菜单")
        let item = try XCTUnwrap(
            submenu.items.first { ($0.representedObject as? String) == format.rawValue },
            "子菜单里没有 \(format.rawValue) 这一项"
        )
        XCTAssertNotNil(item.target, "\(format.rawValue) 菜单项没有 target（点了不会发生任何事）")
        return item
    }

    /// 按菜单项**自己的** action / target 派发 —— 与 AppKit 真的点一下菜单走同一个 ObjC 出口。
    @MainActor
    @discardableResult
    private func invoke(_ item: NSMenuItem) throws -> String? {
        let target = try XCTUnwrap(item.target, "菜单项没有 target")
        let action = try XCTUnwrap(item.action, "菜单项没有 action")
        _ = target.perform(action, with: item)
        return NSPasteboard.general.string(forType: .string)
    }

    /// 剪贴板先放一个哨兵：这样「没写进去」与「写进去的是空串」分得开。
    private func seedPasteboard(_ sentinel: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sentinel, forType: .string)
    }

    /// 各格式应当出现的表头（需求 ②：复制即带表头）。
    private func expectedHeader(_ format: ResultClipboard.Format) -> String {
        switch format {
        case .tsv: return "id\tnote\tamount"
        case .markdown: return "| id | note | amount |"
        case .csv: return "id,note,amount"
        case .insert: return "INSERT INTO"
        }
    }

    // MARK: - ① 四档都在菜单里、都能真的写进剪贴板

    @MainActor
    func testEveryFormatIsOnTheMenuAndReachesTheRealPasteboard() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        let submenu = try XCTUnwrap(copyAsItem(in: host.table).submenu)
        XCTAssertEqual(
            submenu.items.compactMap { $0.representedObject as? String }.sorted(),
            ResultClipboard.Format.allCases.map(\.rawValue).sorted(),
            "「复制为…」子菜单的格式集合与 `ResultClipboard.Format` 不一致（少一项 = 用户点不到，多一项 = 点了没反应）"
        )

        for format in ResultClipboard.Format.allCases {
            let item = try menuItem(for: format, in: host.table)
            seedPasteboard("SENTINEL-\(format.rawValue)")
            let text = try XCTUnwrap(try invoke(item), "\(format.rawValue) 没有写进系统剪贴板")
            XCTAssertNotEqual(text, "SENTINEL-\(format.rawValue)", "\(format.rawValue) 根本没执行复制（剪贴板还是哨兵）")
            XCTAssertTrue(
                text.contains(expectedHeader(format)),
                "\(format.rawValue) 复制出来的文本里没有表头：\(text)"
            )
            // 只复制选中的行：没选的第 0 行不许出现在剪贴板里。
            XCTAssertFalse(text.contains("skipped-row"), "\(format.rawValue) 把没选中的行也复制走了：\(text)")
            XCTAssertTrue(text.contains("alpha"), "\(format.rawValue) 漏了选中的第 1 行：\(text)")
        }
    }

    // MARK: - ② 默认 ⌘C = TSV，且逐字节正确

    @MainActor
    func testDefaultCopyIsTSVWithHeaderWithoutAnyEscapingDamage() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        let menu = try XCTUnwrap(host.table.menu)
        // `copy(_:)` 是本仓 `CopyableTableView` 上自建的那个动作（`NSTableView` 自己没有），
        // 所以按选择器名找，而不是按类型找。
        let copySelector = NSSelectorFromString("copy:")
        let copyItem = try XCTUnwrap(
            menu.items.first { $0.action == copySelector },
            "右键菜单里没有「复制」（⌘C 那一项）"
        )
        XCTAssertEqual(copyItem.keyEquivalent, "c", "「复制」没有挂 ⌘C")
        XCTAssertEqual(ResultClipboard.defaultFormat, .tsv, "默认格式不是 TSV（需求 ②）")

        seedPasteboard("SENTINEL")
        let text = try XCTUnwrap(try invoke(copyItem), "⌘C 没有写进系统剪贴板")

        // 表头 + 三行选中行；制表符与换行在 TSV 里被换成空格（否则一行会被拆成两行）。
        let expected = "id\tnote\tamount\n"
            + "1\talpha\t10.5\n"
            + "2\tbe|ta\t\n"
            + "3\ttab here new\t30\n"
        XCTAssertEqual(text, expected, "默认 ⌘C 复制出来的 TSV 与需求口径不一致")
        XCTAssertEqual(text.split(separator: "\n").count, 4, "行数被值里的换行撑破了")
    }

    // MARK: - ③ 转义：Markdown 的竖线与换行、CSV 的引号

    @MainActor
    func testEscapingSurvivesTheRealCopyPath() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        seedPasteboard("SENTINEL")
        let markdown = try XCTUnwrap(try invoke(try menuItem(for: .markdown, in: host.table)))
        XCTAssertTrue(markdown.contains("| 2 | be\\|ta | NULL |"), "Markdown 没转义竖线（贴进文档会多出一列）：\(markdown)")
        XCTAssertTrue(markdown.contains("tab\there<br>new"), "Markdown 没把换行写成 <br>：\(markdown)")
        XCTAssertTrue(markdown.contains("| --- | --- | --- |"), "Markdown 少了分隔行：\(markdown)")

        seedPasteboard("SENTINEL")
        let csv = try XCTUnwrap(try invoke(try menuItem(for: .csv, in: host.table)))
        XCTAssertTrue(csv.hasPrefix("id,note,amount\r\n"), "CSV 表头不对：\(csv)")
        XCTAssertTrue(csv.contains("\"tab\there\nnew\""), "CSV 里含换行的字段没有加引号（贴进表格会错行）：\(csv)")
    }

    // MARK: - ④ INSERT 指向哪张表（有来源表 / 没有来源表两档）

    @MainActor
    func testInsertCopyPointsAtTheTableBeingBrowsed() throws {
        try skipUnlessProbeEnabled()
        let host = try mount(sourceTable: DatabaseObjectRef(schema: "public", name: "orders"))
        defer { host.tearDown() }

        seedPasteboard("SENTINEL")
        let insert = try XCTUnwrap(try invoke(try menuItem(for: .insert, in: host.table)))

        XCTAssertTrue(
            insert.hasPrefix("INSERT INTO \"public\".\"orders\" (\"id\", \"note\", \"amount\") VALUES (1, 'alpha', 10.5);"),
            "复制出来的 INSERT 没有指向正在浏览的表：\(insert)"
        )
        XCTAssertFalse(insert.contains("table_name"), "有来源表时还落占位表名：\(insert)")
        // 按语句数（不是按物理行数）：值里那个真换行留在字符串字面量里，一条语句可以占两行 ——
        // 这正是「复制出去的 SQL 与库里的值逐字节一致」的表现，不是错。
        XCTAssertEqual(
            insert.components(separatedBy: "INSERT INTO").count - 1, 3,
            "只该复制选中的三行：\(insert)"
        )
        XCTAssertTrue(insert.contains("NULL"), "空值没写成 NULL：\(insert)")
    }

    @MainActor
    func testInsertCopyWithoutASourceTableSaysPlaceholderInsteadOfGuessing() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()  // 手写 SQL 的结果：没有 `QueryTab.sourceTable`
        defer { host.tearDown() }

        seedPasteboard("SENTINEL")
        let insert = try XCTUnwrap(try invoke(try menuItem(for: .insert, in: host.table)))
        XCTAssertTrue(
            insert.hasPrefix("INSERT INTO \"\(ResultClipboard.placeholderTableName)\""),
            "没有来源表时既没有真表名也没有明写占位：\(insert)"
        )
    }

    // MARK: - ⑤ 负例：没有选中行时一个字节都不许动剪贴板

    @MainActor
    func testEmptySelectionLeavesThePasteboardUntouched() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        host.table.deselectAll(nil)
        XCTAssertTrue(host.table.selectedRowIndexes.isEmpty, "清空选中失败")

        for format in ResultClipboard.Format.allCases {
            seedPasteboard("SENTINEL-\(format.rawValue)")
            let text = try invoke(try menuItem(for: format, in: host.table))
            XCTAssertEqual(
                text, "SENTINEL-\(format.rawValue)",
                "没有选中行时 \(format.rawValue) 仍然改写了剪贴板（等于把用户剪贴板里的东西悄悄换掉）"
            )
        }
    }

    // MARK: - ⑥ 只进剪贴板，不落文件

    @MainActor
    func testCopyNeverLeavesAFileOnDisk() throws {
        try skipUnlessProbeEnabled()
        let host = try mount()
        defer { host.tearDown() }

        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
        let before = try Set(FileManager.default.contentsOfDirectory(atPath: scratch.path))

        seedPasteboard("SENTINEL")
        let text = try XCTUnwrap(try invoke(try menuItem(for: .markdown, in: host.table)))
        XCTAssertFalse(text.isEmpty)

        let after = try Set(FileManager.default.contentsOfDirectory(atPath: scratch.path))
        XCTAssertEqual(after.subtracting(before), [], "复制在临时目录里留下了文件（需求 ④：只进剪贴板）")

        // 剪贴板里只该是文本：出现文件 URL 就等于「复制成了文件」而不是「复制文本」。
        let types = NSPasteboard.general.types ?? []
        XCTAssertFalse(types.contains(.fileURL), "剪贴板里塞了文件 URL：\(types)")
    }
}
