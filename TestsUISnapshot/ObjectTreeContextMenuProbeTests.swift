import Crypto
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 对象树「**逐行右键**」（清单 `FR-META-14` 那一行 · 队列 `L-90` ㈡ 第 2 条 · 开发循环第 110 轮）。
///
/// ## 判什么（清单那一行的人话）
///
/// 「依次右键：**表 / 视图 / 列 / 服务器 / 数据库 / schema / 函数**」→
/// ① 每一行弹出来的都是**它自己**的菜单（旧版：整棵树是一个 `List` 行，点数据库弹的是**服务器**菜单）；
/// ② 数据库 / schema 上有「**新建表**」；③ 函数上有「查看 DDL」；④ 列上有「复制列名」；
/// ⑤ 鼠标停在树上不动时，界面不该自己闪。
///
/// ## 怎么判（App 内探针 + 自渲染快照，零权限 —— 与 `L-90` ㈠ 同路线）
///
/// 菜单**内容**与**作用在哪一行**两件事都住在 `App/Views/ObjectTreeContextMenu.swift`：
/// 前者是一个真 `View`（`ObjectTreeContextMenu`），后者是一个纯函数（`ObjectTreeMenuTarget.resolve`）。
/// 于是不需要任何鼠标 / 键盘事件，也不需要任何系统授权：
///
///   · 内容 —— 每类节点渲染一遍，把这一遍 `L(...)` 取到的**文案集合**与
///     `ObjectTreeActions.isAvailable` 的规则**双向**对账（少一项 / 多一项都判红）；
///   · 作用行 —— 拿**产品自己摊平出来的**行数组（`ObjectTreeRows.visibleRows`）喂那个纯函数，
///     判「悬停命中 ⇒ 就是那一行」「盒子空 ⇒ 退回选中项（点完立刻右键那条）」「都不成立 ⇒ `nil`」。
///
/// ## 判不到的（如实登记）
///
/// · **按钮点下去之后面板真的开了**这一层不在这里：菜单与 ⌘K 命令面板读的是同一个
///   `AppState` 字段（`selectedTreeObject` / `createTableTarget` / `isBrowseRowsCommandPresented` /
///   `isSyntheticCommandPresented` / `alterTableTarget`），落点由 `PaletteWiringProbeTests` 那批覆盖；
///   本轮只把「菜单项集合」与「作用行」钉住（SwiftUI 的 `Button` 在离屏宿主里不是 AppKit 控件，
///   点不到 —— 与 `L-89` ㈡ 第 8 条那次「整棵 ObjectTreeView + 真点击」同一个边界）。
/// · ⑤「鼠标停着不动界面不该闪」是**结构**判据：悬停行存在无观察者的 `HoverBox` 里、菜单**无条件**挂
///   （两条源锚点写在 `Scripts/verify-ui-interactions.sh`），不是行为判据。
/// · 这一族图**只拍中文一面**：判的是「哪一行 / 有哪些项」，语言成对由 `make-ui-snapshots` 的注册表管
///   （探针直接落 `.build/ui-snapshots/`，不进那张注册表）。
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`），跑法 `./Scripts/verify-ui-interactions.sh`。
final class ObjectTreeContextMenuProbeTests: XCTestCase {

    // MARK: - 夹具

    private static let server = DatabaseObject(id: "server:pg217", name: "pg-217", kind: .server)
    private static let database = DatabaseObject(
        id: "db:zxvmax", name: "zxvmax", kind: .database, database: "zxvmax"
    )
    private static let otherDatabase = DatabaseObject(
        id: "db:other", name: "other_db", kind: .database, database: "other_db"
    )
    private static let schema = DatabaseObject(
        id: "schema:zxvmax.public", name: "public", kind: .schema,
        database: "zxvmax", schema: "public"
    )
    private static let table = DatabaseObject(
        id: "table:zxvmax.public.orders", name: "orders", kind: .table,
        database: "zxvmax", schema: "public"
    )
    private static let view = DatabaseObject(
        id: "view:zxvmax.public.v_orders", name: "v_orders", kind: .view,
        database: "zxvmax", schema: "public"
    )
    private static let function = DatabaseObject(
        id: "function:zxvmax.public.f_total", name: "f_total", kind: .function,
        database: "zxvmax", schema: "public"
    )
    private static let sequence = DatabaseObject(
        id: "sequence:zxvmax.public.orders_id_seq", name: "orders_id_seq", kind: .sequence,
        database: "zxvmax", schema: "public"
    )
    private static let column = DatabaseObject(
        id: "column:zxvmax.public.orders.id", name: "id", kind: .column,
        database: "zxvmax", schema: "public"
    )

    /// 清单那一行点名的七类节点（`server` 也有它自己的整套菜单）。
    private static let menuObjects: [DatabaseObject] = [
        server, database, schema, table, view, function, column,
    ]

    /// 菜单那一行**属于哪一类节点**也要判：与 `menuObjects` 一一对应（顺序即产物顺序）。
    private static let menuKinds: [DatabaseObject.Kind] = [
        .server, .database, .schema, .table, .view, .function, .column,
    ]

    /// 画的尺寸：按最长的那份菜单（表 = 10 项 + 6 条分隔线）留够高度，宽度够「浏览前 200 行」一行放得下。
    /// 此前 280×300 装不下表那一行 ⇒ 判据自己看不出来（文案集合照样齐），**图上是叠着的** ——
    /// 本轮读图才发现（第 110 轮）。
    private static let menuSize = CGSize(width: 240, height: 420)

    /// 可见行取**产品自己摊平出来的**那一份（不是测试里手写的行数组）。
    private static func rows(groupByType: Bool = false) -> [ObjectTreeVisibleRow] {
        ObjectTreeRows.visibleRows(
            roots: [server, otherDatabase],
            expandedIDs: [server.id, database.id, schema.id, table.id],
            childrenCache: [
                server.id: [database, otherDatabase],
                database.id: [schema],
                schema.id: [table, view, function, sequence],
                table.id: [column],
            ],
            groupByType: groupByType,
            language: .simplifiedChinese
        )
    }

    // MARK: - 期望值（都走宿主语境取，不拿用户偏好当期望）

    /// 在指定语言的**宿主语境**里算一段值（`L(...)` 在语境外按用户偏好出文案，期望值会错位）。
    @MainActor
    private static func inHostLanguage<T>(_ language: AppLanguage, _ body: () -> T) -> T {
        _ = LocalizationManager.beginHostLanguage(language)
        defer { LocalizationManager.endHostLanguage() }
        return body()
    }

    @MainActor
    private static func actionLabels(_ language: AppLanguage) -> [ObjectTreeAction: String] {
        inHostLanguage(language) { () -> [ObjectTreeAction: String] in
            let labels: [ObjectTreeAction: String] = [
                .browseRows: L(.treeActionBrowseRows, ObjectTreeActions.defaultBrowseLimit),
                .selectTemplate: L(.treeActionSelectTemplate),
                .insertTemplate: L(.treeActionInsertTemplate),
                .copyQualifiedName: L(.treeActionCopyQualifiedName),
                .copyColumnName: L(.treeActionCopyColumnName),
                .viewDDL: L(.treeActionViewDDL),
                .truncateTable: L(.treeActionTruncate),
                .dropTable: L(.treeActionDrop),
            ]
            return labels
        }
    }

    /// 服务器那一行的八个常驻项（新建数据库那一条另有权限条件，单独判）。
    @MainActor
    private static func serverMenuBase(_ language: AppLanguage) -> [String] {
        inHostLanguage(language) { () -> [String] in
            let labels: [String] = [
                L(.objectTreeMenuConnect), L(.objectTreeMenuDisconnect),
                L(.objectTreeMenuEditConnection), L(.objectTreeMenuDatabaseProperties),
                L(.objectTreeMenuDropDatabase), L(.objectTreeMenuPrivileges),
                L(.objectTreeMenuLocks), L(.sessionTitle),
            ]
            return labels
        }
    }

    @MainActor
    private static func text(_ language: AppLanguage, _ body: () -> String) -> String {
        inHostLanguage(language, body)
    }

    // MARK: - 宿主

    private struct Host {
        let state: AppState
        let workspace: WorkspaceStore
        let tabs: WorkspaceTabsModel
        let terminal: TerminalModel
    }

    private func requireSnapshotMode() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1",
            "要 DOYAH_UI_SNAPSHOT=1（跑法 ./Scripts/verify-ui-interactions.sh）"
        )
    }

    @MainActor
    private func makeHost() -> Host {
        let scratch = UISnapshot.outputDirectory.deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        return Host(
            state: state,
            workspace: .shared,
            tabs: WorkspaceTabsModel(
                store: WorkspaceHistoryStore(
                    fileURL: scratch.appendingPathComponent("tree-menu-history-\(UUID().uuidString).json")
                )
            ),
            terminal: TerminalModel()
        )
    }

    /// 把菜单内容渲染一遍并落一张图（判据要的文案集合就在返回的记录里）。
    ///
    /// **容器由这里加**（`VStack` + 内边距）：生产路径交给 `.contextMenu { … }` 的是**兄弟节点**
    /// （AppKit 的菜单项要的就是这个形状），而一张图必须有排布 —— 内容本身两边同源，
    /// 差别只在外面这层壳，如实登记在探针头注的边界里。
    @MainActor
    @discardableResult
    private func renderMenu(
        _ object: DatabaseObject?,
        name: String,
        host: Host
    ) throws -> UISnapshot.Record {
        try UISnapshot.write(name, size: Self.menuSize, language: .simplifiedChinese) {
            VStack(alignment: .leading, spacing: 6) {
                ObjectTreeContextMenu.items(object: object, appState: host.state)
            }
            .padding(16)
            .snapshotEnvironment(
                state: host.state,
                workspace: host.workspace,
                tabs: host.tabs,
                terminal: host.terminal
            )
        }
    }

    // MARK: - ① 每一行都是它自己的菜单（七类各一张图）+ 动作项与 Core 双向对账

    @MainActor
    func testEachRowKindGetsItsOwnMenuNotTheServersMenu() throws {
        try requireSnapshotMode()
        let host = makeHost()
        let labels = Self.actionLabels(.simplifiedChinese)
        let browseWithCondition = Self.text(.simplifiedChinese) { L(.treeActionBrowseWithCondition) }
        let allActionLabels = Set(labels.values).union([browseWithCondition])
        let serverBase = Set(Self.serverMenuBase(.simplifiedChinese))
        let createDatabase = Self.text(.simplifiedChinese) { L(.objectTreeMenuCreateDatabase) }

        for (object, kind) in zip(Self.menuObjects, Self.menuKinds) {
            XCTAssertEqual(object.kind, kind, "夹具与类别表要对得上（顺序即产物顺序）")
            let record = try renderMenu(
                object, name: "interaction-tree-menu-\(kind.rawValue)", host: host
            )
            let observed = Set(record.localizedStrings)
            XCTAssertFalse(observed.isEmpty, "「\(kind.rawValue)」那一行一个文案都没有 —— 菜单没渲染出来")

            // 甲、**动作项**必须与 Core 的规则逐条对上（少一项 / 多一项都判红）
            var expected = Set(
                ObjectTreeAction.allCases
                    .filter { ObjectTreeActions.isAvailable($0, for: kind) }
                    .compactMap { labels[$0] }
            )
            // 「按条件浏览…」没有自己的 `ObjectTreeAction`：它挂在 `browseRows` 那一支里（表 / 视图才有）。
            if ObjectTreeActions.isAvailable(.browseRows, for: kind) {
                expected.insert(browseWithCondition)
            }
            XCTAssertEqual(
                observed.intersection(allActionLabels), expected,
                "「\(kind.rawValue)」那一行的动作项与 ObjectTreeActions 的规则不一致"
            )

            // 乙、**服务器菜单不许漏到别的行上**（那条老缺陷的回归钉：点数据库弹服务器菜单）
            if kind == .server {
                XCTAssertTrue(
                    serverBase.isSubset(of: observed),
                    "服务器那一行少了服务器菜单项：\(serverBase.subtracting(observed))"
                )
                XCTAssertEqual(
                    observed.contains(createDatabase), host.state.canCreateDatabase == true,
                    "「新建数据库」的出现必须与登录用户有建库权限一致（未知 / 无权限时不给必然失败的按钮）"
                )
            } else {
                XCTAssertTrue(
                    observed.intersection(serverBase).isEmpty,
                    "「\(kind.rawValue)」那一行弹出了服务器菜单项 "
                        + "\(observed.intersection(serverBase)) —— 这就是「点数据库弹服务器菜单」那条老毛病"
                )
                XCTAssertFalse(
                    observed.contains(createDatabase),
                    "「新建数据库」只属于服务器那一行"
                )
            }
            Self.assertSignatureItems(kind: kind, observed: observed, labels: labels)
        }
    }

    /// 清单那一行点名的三条签名项（②新建表 / ③查看 DDL / ④复制列名）+ 每类节点**不该有**的项。
    @MainActor
    private static func assertSignatureItems(
        kind: DatabaseObject.Kind,
        observed: Set<String>,
        labels: [ObjectTreeAction: String]
    ) {
        let newTable = text(.simplifiedChinese) { L(.tableDesignTitle) }
        let alterTable = text(.simplifiedChinese) { L(.tableDesignAlterTitle) }
        let synthetic = text(.simplifiedChinese) { L(.syntheticGenerate) }
        let has: (ObjectTreeAction) -> Bool = { action in
            guard let label = labels[action] else { return false }
            return observed.contains(label)
        }

        switch kind {
        case .database, .schema:
            XCTAssertTrue(observed.contains(newTable), "「\(kind.rawValue)」那一行必须有「新建表」（FR-DDL-03）")
            XCTAssertFalse(has(.truncateTable) || has(.dropTable), "清空 / 删除只对表提供")
        case .table:
            XCTAssertTrue(observed.contains(alterTable), "表那一行必须有「编辑表结构」")
            XCTAssertTrue(observed.contains(synthetic), "表那一行必须有生成合成数据的入口")
            XCTAssertTrue(has(.truncateTable) && has(.dropTable), "清空 / 删除只在表那一行")
        case .view:
            XCTAssertTrue(has(.viewDDL), "视图那一行必须有「查看 DDL」（FR-META-13）")
            XCTAssertFalse(has(.truncateTable) || has(.dropTable), "视图不可清空 / 删除 ⇒ 这两项不许出现")
            XCTAssertFalse(observed.contains(alterTable), "视图没有「编辑表结构」")
        case .function:
            XCTAssertTrue(has(.viewDDL), "函数那一行必须有「查看 DDL」（FR-META-13，新补的入口）")
            XCTAssertFalse(has(.dropTable), "函数没有 DROP TABLE 这条动作")
        case .column:
            XCTAssertTrue(has(.copyColumnName), "列那一行必须有「复制列名」")
            XCTAssertFalse(has(.browseRows), "列上没有「浏览前 N 行」")
        case .server, .sequence:
            break
        }
    }

    // MARK: - ② 菜单作用在**哪一行**上（悬停优先 / 盒子空时退回选中项 / 都不成立 ⇒ 空菜单）

    @MainActor
    func testMenuTargetFollowsTheRowUnderTheMouse() throws {
        try requireSnapshotMode()
        let rows = Self.rows()
        let grouped = Self.rows(groupByType: true)

        // 甲、悬停命中 ⇒ 就是那一行（老缺陷的回归钉：右键**数据库**那一行，目标必须是数据库、不是服务器）
        XCTAssertEqual(
            ObjectTreeMenuTarget.resolve(hoveredRowID: Self.database.id, selected: Self.server, rows: rows),
            Self.database,
            "悬停在哪一行，菜单就是哪一行的"
        )
        XCTAssertEqual(
            ObjectTreeMenuTarget.resolve(hoveredRowID: Self.table.id, selected: Self.server, rows: rows),
            Self.table
        )
        XCTAssertEqual(
            ObjectTreeMenuTarget.resolve(hoveredRowID: Self.column.id, selected: Self.table, rows: rows),
            Self.column,
            "列那一行也有它自己的菜单（复制列名）"
        )
        XCTAssertEqual(
            ObjectTreeMenuTarget.resolve(hoveredRowID: Self.function.id, selected: nil, rows: rows),
            Self.function,
            "函数那一行有「查看 DDL」"
        )

        // 乙、盒子空 ⇒ 退回选中项（2026-09-28 需求提出者实测那条：点完立刻右键）
        XCTAssertEqual(
            ObjectTreeMenuTarget.resolve(hoveredRowID: nil, selected: Self.table, rows: rows),
            Self.table,
            "悬停盒子空时要退回「刚点中的那一行」—— 否则手快的人看到的是空菜单"
        )
        XCTAssertEqual(
            ObjectTreeMenuTarget.resolve(hoveredRowID: Self.sequence.id, selected: Self.view, rows: rows),
            Self.view,
            "悬停在没有菜单的节点（序列）上 ⇒ 退回选中项"
        )

        // 丙、分组视图下的**类型表头**不是可作用行 ⇒ 退回选中项；选中项也没有 ⇒ nil
        let headerID = try XCTUnwrap(
            grouped.first(where: { $0.isGroupHeader })?.object.id,
            "分组视图里应当有类型表头（夹具前提）"
        )
        XCTAssertEqual(
            ObjectTreeMenuTarget.resolve(hoveredRowID: headerID, selected: Self.table, rows: grouped),
            Self.table
        )
        XCTAssertNil(
            ObjectTreeMenuTarget.resolve(hoveredRowID: headerID, selected: nil, rows: grouped),
            "悬停在表头上 + 没有选中项 ⇒ 没有可作用的行"
        )

        // 丁、都不成立 ⇒ nil（界面弹「这一行没有可用的操作」，而不是一个空菜单）
        XCTAssertNil(ObjectTreeMenuTarget.resolve(hoveredRowID: nil, selected: nil, rows: rows))
        XCTAssertNil(
            ObjectTreeMenuTarget.resolve(hoveredRowID: nil, selected: Self.sequence, rows: rows),
            "序列没有菜单（也不在 menuKinds 里）⇒ nil"
        )
        XCTAssertNil(ObjectTreeMenuTarget.resolve(hoveredRowID: "不存在的行", selected: nil, rows: rows))

        let empty = try renderMenu(nil, name: "interaction-tree-menu-no-target", host: makeHost())
        XCTAssertEqual(
            empty.localizedStrings,
            [Self.text(.simplifiedChinese) { L(.treeMenuEmpty) }],
            "没有可作用行时只该有那一句说明（空菜单比没有菜单更让人困惑）"
        )
    }

    // MARK: - ③ 同一行两次渲染逐字节一致；不同行必须画成两个样子

    @MainActor
    func testMenuIsDeterministicAndFollowsTheRow() throws {
        try requireSnapshotMode()
        let host = makeHost()
        let a = try renderMenu(Self.table, name: "interaction-tree-menu-same-row-a", host: host)
        let b = try renderMenu(Self.table, name: "interaction-tree-menu-same-row-b", host: host)
        let other = try renderMenu(Self.database, name: "interaction-tree-menu-other-row", host: host)

        let first = try Self.sha256(ofPNGAt: a.file)
        XCTAssertEqual(
            first, try Self.sha256(ofPNGAt: b.file),
            "同一行的菜单两次渲染必须逐字节一致（否则「跟着那一行变」这件事判不出来）"
        )
        XCTAssertNotEqual(
            first, try Self.sha256(ofPNGAt: other.file),
            "不同行的菜单必须画成两个样子 —— 否则判据可能盯着一张固定图"
        )
        XCTAssertNotEqual(a.localizedStrings, other.localizedStrings, "两行的文案集合也必须不同")
    }

    private static func sha256(ofPNGAt path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
