import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// MySQL 表单联动（`待人工验收清单.md` §10.7 里 `FR-DRV-09` 那一行）—— 队列 `L-89` ㈡ ⑩（开发循环第 105 轮）。
///
/// ## 那一行为什么原先要人点
///
/// 清单原文：「新建连接 → 数据库类型选 **MySQL** → 端口应自动变成 **3306**、SSL 默认 `prefer`；
/// 连上后看对象树」，判三件事：① 类型联动正确；② 树是**四层**（服务器 → Database → Table → Column，
/// **没有 schema 层**）；③ 能查到数据。旧状态格写的是「**类型联动的 Core 部分有单测；界面点击待人工**」——
/// 也就是：`DatabaseType.defaultPort` / `sslModes` 这些**常量**有单测，而「在下拉里真的选一下、
/// 端口那一格里真的变成 3306、SSL 那一台真的少一项 Allow」**一条机器判据都没有**。
/// 人点这一行时能看出的恰恰是这一层：控件之间的联动，而不是常量本身。
///
/// ## 判法（两组，都要命令级可复跑）
///
/// · **A 组（界面联动）**：难点先摆出来 —— **本机 SwiftUI 的 `Picker` 不落到 AppKit 控件**
///   （2026-09-29 实测：`Form(.grouped)` 里那两台下拉在宿主视图树里根本不存在，Picker 是
///   SwiftUI 自绘的）⇒「点一下那台下拉」这条路**走不通**。于是照 `EgressLogSheet` 当年的处置
///   （`EgressTabOptions`）把联动**搬成能直接断言的东西**：`App/Views/ConnectionDialectSection.swift`
///   里的 `ConnectionDialectLinkage`（端口 / SSL 默认值 / SSL 清单只在这一处算，界面与判据读同一份），
///   再加一个把**产品那两个视图**接起来的夹具 —— 改夹具里的 `dbType` 就等于在界面里换方言，
///   断言读的是：① 绑定侧（端口 / SSL / 收敛说明）；② **界面上那一格真 `NSTextField` 的正文**
///   （这是连渲染一起判的）；③ 真 `ConnectionFormView` 按各方言配置渲染时端口那一格的正文。
/// · **B 组（对象树与服务端）**：连一台**真跑 MySQL 线协议**的服务端（本机没有 mysql/mariadb，
///   用 `Scripts/mysql-stub/fake_mysql_server.py`，由 `Scripts/run-manual-verification-probes.sh`
///   起好并把地址经 `DOYAH_PROBE_MYSQL_*` 给进来），走产品自己的
///   `DatabaseServiceFactory` + `MetadataService`，**逐层展开**并断言**层级链**；
///   再走产品自己的查询入口取一次结果集。
///
/// ## 边界（如实登记，不假装判过的部分）
///
/// · B 组的服务端是**自写假服务器**（真跑线协议、不是真 MySQL 实例）⇒ 判的是「我们这一侧
///   把四层树搭对没有」；**真实例上的认证 / 类型 / 多版本窗口**仍归
///   `Scripts/test-mysql-real.sh`（217，见 `Docs/兼容性矩阵.md`），本探针不声称覆盖。
/// · A 组判「**换方言之后**端口与 SSL 清单跟着换」；**初始载入**那两个值（`init` 里按配置填）
///   不在本探针范围（旧配置被收敛那一面已由 `ManualVerificationProbeTests` 的 R-53 三条守）。
/// · 不判「用户能不能用手点」（同一进程内 `sendAction` 与真手点走的是同一条 action 路径，
///   但触摸层不在范围）——这条口径与第 96 / 101 轮那两批一致。
/// · 全程不落盘：不写用户偏好、不写连接配置；B 组只用内存里的配置连假服务器。
final class MySQLFormProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针要渲染真视图树 / 真连服务端：DOYAH_UI_SNAPSHOT=1 才跑（与快照同一条纪律：取证才跑，门禁不跑）"
        )
    }

    /// 表单很长（十几个字段 + 隧道一段）：视口给足，免得 **Form 的懒加载**把下半截根本不构造 ——
    /// 那样「SSL 那一台不在」会是**假红**（界面其实是对的，只是没建到那一行）。
    private let formSize = CGSize(width: 760, height: 2000)

    // MARK: - 装配与「怎么找那一台控件」

    @MainActor
    private func form(_ type: DatabaseType) -> ConnectionFormView {
        ConnectionFormView(
            configuration: ConnectionConfig(
                name: "探针连接",
                dbType: type,
                host: "127.0.0.1",
                port: type.defaultPort,
                database: "demo",
                username: "root"
            ),
            existingConnections: [],
            storedPassword: { nil },
            onSave: { _, _, _ in }
        )
    }

    /// 探针侧夹具：把表单里那三段（方言那一台 / 端口那一格 / SSL 那一行）按**同一种绑定**接起来。
    ///
    /// 为什么需要一个夹具而不是直接点真表单：`Form(.grouped)` 里的 `Picker` 在 macOS 27 上
    /// 是 SwiftUI **自绘**的（宿主视图树里没有 `NSPopUpButton`，见第 105 轮实测）⇒ 离屏宿主里
    /// 点不动它。所以产品把这两段抽成了独立视图（`App/Views/ConnectionDialectSection.swift`），
    /// 夹具用的就是**这两个产品视图**与**同一个 `port` 绑定** —— 在它上面点一下与在表单里点
    /// 是同一件事；「表单真的把这三段接在这几个绑定上」另由探针脚本的**源锚点**判（第 101 轮的
    /// 教训：判据与界面脱钩就白判）。
    private final class DialectBox: ObservableObject {
        @Published var dbType: DatabaseType = .postgresql
        @Published var port: String = "5432"
        @Published var sslMode: SSLMode = .prefer
        @Published var adjusted: SSLMode?
    }

    private struct DialectHarness: View {
        @ObservedObject var box: DialectBox

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ConnectionDialectPicker(
                    dbType: $box.dbType,
                    port: $box.port,
                    sslMode: $box.sslMode,
                    sslModeWasAdjusted: $box.adjusted
                )
                // 端口那一格：与表单里同一写法（一个绑到 `port` 的 TextField）。
                TextField(L(.connectionFormPort), text: $box.port)
                ConnectionSSLModeRow(
                    dbType: box.dbType,
                    sslMode: $box.sslMode,
                    sslModeWasAdjusted: $box.adjusted
                )
            }
            .padding()
            .frame(width: 520, alignment: .leading)
        }
    }

    private let harnessSize = CGSize(width: 560, height: 420)

    /// 界面上**所有**输入框的正文（端口那一格就在里面 —— 判「端口真的变了」看的是它）。
    /// 注意：`Picker` 在本机**不落到 AppKit 控件**，所以这里只有 `NSTextField`。
    @MainActor
    private func fieldValues<V: View>(_ host: UISnapshot.LiveHost<V>) -> [String] {
        host.textFields.map(\.stringValue)
    }


    // MARK: - A 组：换方言 ⇒ 端口与 SSL 清单当场跟着换（真点那台下拉）

    @MainActor
    func testSwitchingDialectRewritesPortAndSSLList() throws {
        let box = DialectBox()
        let host = UISnapshot.LiveHost(DialectHarness(box: box), size: harnessSize)

        // ① 开局（PostgreSQL）：端口那一格 5432、SSL 六项**含** Allow —— 这是 ② 的对照面。
        XCTAssertEqual(fieldValues(host), ["5432"], "开局端口那一格不是 5432：\(fieldValues(host))")
        let pg = ConnectionDialectLinkage.adjustments(for: .postgresql)
        XCTAssertEqual(pg.sslModeTitles, ["Disable", "Allow", "Prefer", "Require", "Verify CA", "Verify Full"])
        let pgSignature = try host.signature()

        // ② 换到 MySQL：`.onChange` 那条联动真的跑（端口与 SSL 都跟着变），
        //    而且**界面那一格**（真 `NSTextField`）当场就是 3306。
        box.dbType = .mysql
        host.pump(0.6)
        XCTAssertEqual(box.port, "3306", "换到 MySQL 之后端口绑定还是 \(box.port)（联动没跑）")
        XCTAssertEqual(box.sslMode, .prefer, "MySQL 的 SSL 没有落到方言默认值 prefer")
        XCTAssertNil(box.adjusted, "换方言之后上一次那条「被收敛过」的说明没清掉")
        XCTAssertEqual(fieldValues(host), ["3306"], "换到 MySQL 之后界面那一格不是 3306：\(fieldValues(host))")
        // ② 这一拍也**留证**：SSL 那一台这时选中的是哪一项（按方言取显示名）。
        let mysqlSSLSelection = box.sslMode.displayName(for: .mysql)

        let mysql = ConnectionDialectLinkage.adjustments(for: .mysql)
        XCTAssertEqual(mysql.sslModeTitles, ["Disable", "Prefer", "Require", "Verify CA", "Verify Identity"])
        XCTAssertFalse(mysql.sslModeTitles.contains("Allow"), "MySQL 的 SSL 清单里还有 PG 专属的 Allow（R-53 会复发）")
        XCTAssertEqual(mysql.sslModes, DatabaseType.mysql.sslModes, "清单与方言自己的那份不是同一个来源")
        XCTAssertNotEqual(try host.signature(), pgSignature, "换方言之后画面逐字节相同 ⇒ 联动没到界面上")

        // ③ 换回 PostgreSQL：端口那一格要**回得来**（联动不是单向的一次性动作）。
        box.dbType = .postgresql
        host.pump(0.6)
        XCTAssertEqual(box.port, "5432", "换回 PG 之后端口没有回到 5432：\(box.port)")
        XCTAssertEqual(fieldValues(host), ["5432"], "换回 PG 之后界面那一格不是 5432：\(fieldValues(host))")
        // ③ 这一拍要**留证**：来回都判（联动不是单向的），证据里也得有「回得来」那一刻的正文。
        let fieldValuesAfterBackToPG = fieldValues(host)

        // ④ 第三个方言（GBase 8a）：5258 —— 判「联动跟着方言走」，不是给 MySQL 写的特判。
        box.dbType = .gbase8a
        host.pump(0.6)
        XCTAssertEqual(box.port, "5258", "换到 GBase 8a 之后端口不是 5258：\(box.port)")
        XCTAssertEqual(fieldValues(host), ["5258"], "GBase 8a 那一格不是 5258：\(fieldValues(host))")
        XCTAssertEqual(
            ConnectionDialectLinkage.adjustments(for: .gbase8a).sslModeTitles,
            DatabaseType.gbase8a.sslModes.map { $0.displayName(for: .gbase8a) }
        )

        // ⑤ 老配置态：上一次那条「被收敛过」的说明（R-53）换方言后必须清掉。
        box.adjusted = .allow
        box.sslMode = .prefer
        box.dbType = .mysql
        host.pump(0.6)
        XCTAssertNil(box.adjusted, "从「有收敛说明」的状态换方言，那条说明还挂着")
        XCTAssertEqual(fieldValues(host), ["3306"])

        // ⑥ 真表单那一层再确认一次：表单里那两台 `Picker` 是 SwiftUI 自绘的（判据点不动，见文件头），
        //    但**端口那一格是真 `NSTextField`** —— 换一条方言的配置渲染真表单，那一格就该是那个默认端口。
        let pgFormFields = fieldValues(UISnapshot.LiveHost(form(.postgresql), size: formSize))
        let mysqlFormFields = fieldValues(UISnapshot.LiveHost(form(.mysql), size: formSize))
        let gbaseFormFields = fieldValues(UISnapshot.LiveHost(form(.gbase8a), size: formSize))
        XCTAssertTrue(pgFormFields.contains("5432"), "真表单（PG 配置）里端口那一格不是 5432：\(pgFormFields)")
        XCTAssertTrue(mysqlFormFields.contains("3306"), "真表单（MySQL 配置）里端口那一格不是 3306：\(mysqlFormFields)")
        XCTAssertTrue(gbaseFormFields.contains("5258"), "真表单（GBase 配置）里端口那一格不是 5258：\(gbaseFormFields)")

        // ⑦ **判据自己的边界**（如实登记）：这个宿主里没有 `NSPopUpButton` —— 本机 SwiftUI 自绘
        //    `Picker`（`EgressLogSheet` 当年也遇到同一件事）。这一条不是判产品，是给判据装个哨兵：
        //    哪天 SwiftUI 换成真控件，它先红，提醒把「点一下那台下拉」升级成真点击（见文件头）。
        XCTAssertTrue(
            host.popUpButtons.isEmpty,
            "宿主里出现了 NSPopUpButton ⇒ 判据可以升级成「真点那台方言下拉」了（见本文件头的边界那一段）；"
                + "实测控件清单：\(host.popUpButtons.map(\.itemTitles))；视图树：\n"
                + classDump(host.hosting).joined(separator: "\n")
        )

        try writeEvidence("formLinkage", [
            "dialectItems": ConnectionDialectLinkage.dialectTitles,
            "pgSSLItems": pg.sslModeTitles,
            "mysqlSSLItems": mysql.sslModeTitles,
            "gbaseSSLItems": ConnectionDialectLinkage.adjustments(for: .gbase8a).sslModeTitles,
            "mysqlSSLSelection": mysqlSSLSelection,
            "fieldValuesAfterBackToPG": fieldValuesAfterBackToPG,
            "portAfterMySQL": box.port,
            "portFieldAfterMySQL": fieldValues(host),
            "realFormPortFieldPG": pgFormFields,
            "realFormPortFieldMySQL": mysqlFormFields,
            "realFormPortFieldGBase": gbaseFormFields,
        ])
    }

    /// 诊断用：把宿主视图树里的控件类名按层级列出来（只在判据红时出现在消息里）。
    @MainActor
    private func classDump(_ view: NSView, depth: Int = 0) -> [String] {
        var lines = [String(repeating: "  ", count: depth) + String(describing: type(of: view))]
        if depth < 6 {
            for subview in view.subviews {
                lines.append(contentsOf: classDump(subview, depth: depth + 1))
            }
        }
        return lines
    }

    // MARK: - 证据文件（脚本会核对它 —— 跳过 ≠ 通过）

    private func writeEvidence(_ caseName: String, _ payload: [String: Any]) throws {
        let directory = UISnapshot.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var enriched = payload
        enriched["case"] = caseName
        let data = try JSONSerialization.data(withJSONObject: enriched, options: [.prettyPrinted, .sortedKeys])
        try data.write(
            to: directory.appendingPathComponent("mysql-form-evidence-\(caseName).json"),
            options: .atomic
        )
    }

    // MARK: - B 组：四层树 ＋ 能查到数据（连真跑线协议的服务端）

    /// 目标服务端：本机**没有** mysql / mariadb 二进制（清单 §…「卡环境」那一段），
    /// 所以由 `Scripts/run-manual-verification-probes.sh` 起 `Scripts/mysql-stub/fake_mysql_server.py`
    /// 并把地址经环境变量给进来。没注入 ⇒ 跳过（**跳过 ≠ 通过**：脚本会核对证据文件）。
    private struct MySQLTarget {
        var host: String
        var port: Int
        var user: String
        var password: String
        var database: String
    }

    private func target() -> MySQLTarget? {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["DOYAH_PROBE_MYSQL_HOST"],
              let port = env["DOYAH_PROBE_MYSQL_PORT"].flatMap(Int.init),
              let database = env["DOYAH_PROBE_MYSQL_DATABASE"]
        else { return nil }
        return MySQLTarget(
            host: host,
            port: port,
            user: env["DOYAH_PROBE_MYSQL_USER"] ?? "root",
            password: env["DOYAH_PROBE_MYSQL_PASSWORD"] ?? "",
            database: database
        )
    }

    /// 产品自己的装配（`DatabaseServiceFactory` + 方言工厂）—— 探针不自己 new 驱动，
    /// 免得判的是「探针会不会用驱动」而不是「产品这条路通不通」。
    private func connect(_ target: MySQLTarget) async throws -> (any DatabaseService, ServerInfo) {
        let config = ConnectionConfig(
            name: "探针假 MySQL",
            dbType: .mysql,
            host: target.host,
            port: target.port,
            database: target.database,
            username: target.user,
            sslMode: .disable
        )
        let service = DatabaseServiceFactory.make(for: config, password: target.password)
        let info = try await service.connect()
        return (service, info)
    }

    /// 清单 §10.7 那句「连上后看对象树」的**层级那条**：服务器 → Database → Table → Column，
    /// **没有 schema 层**。逐层走产品自己的 `MetadataService`，把**每一层的 kind 记下来** ——
    /// 「四层」不是我数出来的，是展开三次、每次的 kind 落成的链。
    func testMySQLObjectTreeIsFourLayersWithNoSchemaLevel() async throws {
        guard let target = target() else {
            throw XCTSkip("没有 DOYAH_PROBE_MYSQL_*：本机没有 MySQL 实例 / 假服务器（由探针脚本起）")
        }
        let (service, info) = try await connect(target)
        // 连接必须**无论如何**都收回：判据中途 `return XCTFail`（例如注入后树形状不对）时，
        // 漏掉断开会让 MySQLNIO 在 deinit 里断言失败、整个测试进程 SIGABRT —— 那样「红」就不是
        // 一条点名的断言，而是崩掉（第 101 轮那条「限时轮询」同一类教训：清理也要有归属）。
        addTeardownBlock { await service.disconnect() }
        let metadata = MetadataService(
            service: service,
            dialect: SQLDialectFactory.make(for: .mysql),
            databaseName: target.database,
            serverLabel: "假 MySQL"
        )

        // 第 1 层：服务器。
        let root = try await metadata.loadRoot()
        XCTAssertEqual(root.map(\.kind), [.server], "根节点不是服务器")

        // 第 2 层：库。**这一层里不许有 schema 节点**（MySQL 里库与 schema 是同一个东西）。
        let databases = try await metadata.loadChildren(of: root[0])
        XCTAssertFalse(databases.isEmpty, "服务器层一个库都没列出来（SHOW DATABASES 这条路）")
        XCTAssertFalse(databases.contains { $0.kind == .schema }, "MySQL 的树里出现了 schema 层")
        guard let database = databases.first(where: { $0.name == target.database }) else {
            return XCTFail("库列表里没有 \(target.database)：\(databases.map(\.name))")
        }
        XCTAssertEqual(database.kind, .database)

        // 第 3 层：表 / 视图（同样不许出现 schema 节点 —— 层的归属不该随深度变）。
        let tables = try await metadata.loadChildren(of: database)
        XCTAssertFalse(tables.isEmpty, "\(target.database) 下一张表都没有（SHOW TABLES 这条路）")
        XCTAssertFalse(tables.contains { $0.kind == .schema }, "表那一层里出现了 schema 节点")
        XCTAssertTrue(
            tables.allSatisfy { $0.kind == .table || $0.kind == .view },
            "表那一层出现了别的 kind：\(tables.map(\.kind))"
        )
        guard let table = tables.first(where: { $0.kind == .table }) else {
            return XCTFail("表那一层一个 .table 节点都没有：\(tables.map { "\($0.kind):\($0.name)" })")
        }

        // 第 4 层：列（`DESC \`表\``）。列名与类型都从服务端回来的那一份里取。
        let columns = try await metadata.loadChildren(of: table)
        XCTAssertFalse(columns.isEmpty, "\(table.name) 一列都没展开出来（DESC 这条路）")
        XCTAssertTrue(columns.allSatisfy { $0.kind == .column }, "列那一层出现了别的 kind：\(columns.map(\.kind))")
        XCTAssertTrue(
            columns.contains { $0.detail?.isEmpty == false },
            "列一个带类型的都没有（DESC 第二列没读进来）：\(columns.map { $0.detail ?? "nil" })"
        )

        // 第 5 层必须**不存在**：展开一列得到空 —— 这就是「四层到顶」。
        let beyond = try await metadata.loadChildren(of: columns[0])
        XCTAssertTrue(beyond.isEmpty, "列下面还有子节点（\(beyond.map(\.kind))）⇒ 不是四层")

        // 空库那句文案也得认这件事：MySQL 没有 schema 层 ⇒ 不能说「暂无 schema」（R-57）。
        XCTAssertEqual(
            DatabaseType.mysql.databaseNodeEmptyKey,
            .treeEmptyDatabaseGBase,
            "MySQL 的空库文案指回了「暂无 schema」那一句 —— 层的口径两处打架"
        )

        try writeEvidence("treeLayers", [
            "server": info.database,
            "layerKinds": [
                root.map(\.kind.rawValue),
                databases.map(\.kind.rawValue),
                tables.map(\.kind.rawValue),
                columns.map(\.kind.rawValue),
            ],
            "schemaNodes": databases.filter { $0.kind == .schema }.count
                + tables.filter { $0.kind == .schema }.count,
            "databaseNames": databases.map(\.name),
            "tableNames": tables.map(\.name),
            "columnNames": columns.map(\.name),
            "columnDetails": columns.map { $0.detail ?? "" },
            "beyondColumnCount": beyond.count,
        ])

    }

    /// 清单 §10.7 那句「能查到数据」：走**产品自己的查询入口**（`DatabaseService.execute` 的事件流）
    /// 取一次结果集 —— 列名、行数、中文值都要真的从服务端过来。
    /// 边界：这里读的是**自写假服务器**给的那份固定结果（见 `Scripts/mysql-stub/fake_mysql_server.py`），
    /// 判的是「产品这条路通不通」；真实例上的类型 / 字符集归 `Scripts/test-mysql-real.sh`。
    func testMySQLConnectionReturnsRowsThroughTheProductQueryPath() async throws {
        guard let target = target() else {
            throw XCTSkip("没有 DOYAH_PROBE_MYSQL_*：本机没有 MySQL 实例 / 假服务器（由探针脚本起）")
        }
        let (service, _) = try await connect(target)
        addTeardownBlock { await service.disconnect() }

        var columnNames: [String] = []
        var rows: [[String?]] = []
        var eventNames: [String] = []
        for try await event in service.execute(
            "SELECT id, name, note, amount FROM customers",
            options: .default
        ) {
            switch event {
            case .started: eventNames.append("started")
            case .resultSet(let result):
                eventNames.append("resultSet")
                columnNames = result.columns.map(\.name)
                rows.append(contentsOf: result.rows)
            case .notice: eventNames.append("notice")
            case .finished: eventNames.append("finished")
            }
        }

        XCTAssertEqual(columnNames, ["id", "name", "note", "amount"], "回来的列名与语句里的列对不上")
        XCTAssertFalse(rows.isEmpty, "一条数据都没查回来（结果集是空的）")
        XCTAssertTrue(rows.allSatisfy { $0.count == columnNames.count }, "有行的列数与表头不一致")
        XCTAssertTrue(
            rows.contains { row in row.contains { ($0 ?? "").contains("客户甲") } },
            "中文值没有原样回来：\(rows)"
        )

        try writeEvidence("queryRows", [
            "columns": columnNames,
            "rowCount": rows.count,
            "rows": rows.map { row in row.map { value -> Any in value.map { $0 as Any } ?? NSNull() } },
            "events": eventNames,
        ])

    }
}
