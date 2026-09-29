import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「待人工验收清单」B 类第 6 条：**分组视图**那一行 —— 队列 `L-89` ㈡ 第 6 条（开发循环第 101 轮）。
///
/// ## 清单里那句人话
///
/// `FR-META-15 分组视图`：对象树顶部在「层级视图 / 按类型分组」之间切换 →
/// 什么算过 = 「**两种视图都能用**；**切换后选中项不丢**」。那一行的「机器已验」列写着
/// 「单测 + 人工一眼」—— 而 Core 那侧的单测（`Tests/ObjectTreeGroupingTests.swift`）判的是
/// **聚合函数**；「顶部那台开关在不在、两档都到不到、切完选中项还在不在」三件事，
/// **一件都没被机器判过**。
///
/// ## 本轮把哪几件事变成机器判据
///
/// ① **两种视图都能用**：可见行模型（`App/Views/ObjectTreeRows.swift` —— 本轮从视图里搬出来的
///    **纯函数**）在两种模式下各摊平一遍，输入是**真库读回来的对象**：层级面无表头、分组面表头齐、
///    计数与真库对象数逐个相符，且**非表头行两面逐条相同**（不漏不重、顺序也一致）；
/// ② **顶部那台开关真的在、两档都到得了**：活宿主（`UISnapshot.LiveHost`）里**真点一下**
///    `NSSegmentedControl`（SwiftUI 的 `.pickerStyle(.segmented)` 在 macOS 上就是它）——
///    点完绑定真的翻、两档画出来不是一个样子、标签用当前界面语言（中文 + 英文）；
/// ③ **切换后选中项不丢**：选中项是**树里的同一个 id** 才能在两种视图里都画到 —— 本轮判到这一层
///    （`hierarchy` 与 `grouped` 两种行集合里都找得到那一行）；「切换动作本身不丢选中」的**界面点击**
///    那一半见下面的边界。
///
/// ## 边界（如实登记）
///
/// · 要**真集群**：`Scripts/run-manual-verification-probes.sh` 第八批起本机档、建一个带标记对象的
///   临时库并注入 `DOYAH_PROBE_PG*`；没注入时**跳过**（跳过 ≠ 通过 —— 脚本会核对证据文件）。
/// · PG 的 schema 子节点**只有表与视图两类**（`Core/MetadataService.swift` 的 `loadTables` 走
///   `information_schema.tables`，里面只有 BASE TABLE / VIEW）⇒ 真库那面覆盖 表 / 视图 两个桶；
///   序列 / 函数 / 「其他」三个桶由**合成夹具**补（本文件第二个用例，输入来源写在用例头）。
/// · **「整棵树 + 真库 + 真点击」这条更狠的路本轮做不到**（详见第三个用例头部的实测记录）：
///   真对象树在离屏宿主里**始终停在加载分支**（画面近空白、工具条不在视图树里），而 `.task` 的
///   异步本身是好的（`AppState` 那条路、临时诊断都绿）。⇒「**在真树上点一下、看选中高亮不丢**」
///   连同「切换不重新查库」暂时只到**模型 + 工具栏**这一层；`L-89` ㈡ 已如实登记这一格。
/// · 「切换不重新查库」不做服务端计数：它由**结构**保证（行模型是纯函数、不 import 驱动、
///   不碰 `AppState`、不调 `loadMetadata*`），源锚点判据在探针脚本第八批里。
final class GroupedViewProbeTests: XCTestCase {

    private var host = "127.0.0.1"
    private var port = 55433
    private var user = "postgres"
    /// 探针的临时库（脚本建好、经环境变量给进来 —— 名字只有一处来源）。
    private var database = ""
    private var markerTables: [String] = []
    private var markerView = ""
    /// `AppState` 会把「选中哪条连接」写进这个偏好；探针记下原值、跑完放回去。
    private static let selectedConnectionDefaultsKey = "settings.selectedConnectionID"
    private var savedSelectedConnection: String?

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "分组视图探针要真库 + 真渲染：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
        let env = ProcessInfo.processInfo.environment
        guard let scratchDatabase = env["DOYAH_PROBE_PGGROUP"],
              let tableA = env["DOYAH_PROBE_PGTABLE_A"],
              let tableB = env["DOYAH_PROBE_PGTABLE_B"],
              let view = env["DOYAH_PROBE_PGVIEW"] else {
            throw XCTSkip(
                "分组视图探针要真集群：请走 Scripts/run-manual-verification-probes.sh"
                    + "（它起本机档并注入 DOYAH_PROBE_PG*）—— 跳过不算通过，脚本会核对证据文件"
            )
        }
        database = scratchDatabase
        markerTables = [tableA, tableB]
        markerView = view
        host = env["DOYAH_PROBE_PGHOST"] ?? host
        port = Int(env["DOYAH_PROBE_PGPORT"] ?? "") ?? port
        user = env["DOYAH_PROBE_PGUSER"] ?? user
        savedSelectedConnection = UserDefaults.standard.string(forKey: Self.selectedConnectionDefaultsKey)
    }

    override func tearDownWithError() throws {
        if let saved = savedSelectedConnection {
            UserDefaults.standard.set(saved, forKey: Self.selectedConnectionDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedConnectionDefaultsKey)
        }
    }

    // MARK: - 宿主与真库

    private func config() -> ConnectionConfig {
        ConnectionConfig(
            name: "分组视图探针",
            dbType: .postgresql,
            host: host,
            port: port,
            database: database,
            username: user,
            sslMode: .disable,
            timeout: 5
        )
    }

    /// 真 `AppState`（与界面同一条路）。
    ///
    /// **必须先等启动链落地**（`startupChain`）：链上的 `loadConnections()` 会把用户真实的连接读进
    /// `connections`，而 `selectedConnection` 是「在 `connections` 里按 id 找」—— 不等就赋值，
    /// 等链跑完那一行被覆盖 ⇒ `selectedConnection` 变 `nil`，对象树永远停在「请先选择连接」。
    /// （第 99 轮实测踩过；`startupChain` 这个句柄本身就是为「让调用方能等它」留的。）
    @MainActor
    private func makeAppState() async -> AppState {
        let state = AppState()
        await state.startupChain?.value
        let cfg = config()
        state.connections = [cfg]
        state.selectedConnectionID = cfg.id
        return state
    }

    /// 真库那条链：服务器 → 探针库 → `public` → 子对象（走**产品自己的路**：`AppState.loadMetadata*`）。
    private struct Chain {
        var server: DatabaseObject
        var database: DatabaseObject
        var schema: DatabaseObject
        var objects: [DatabaseObject]
    }

    @MainActor
    private func realChain(in state: AppState) async throws -> Chain {
        guard let server = try await state.loadMetadataRoot().first else {
            throw XCTSkip("对象树根节点为空（真集群没起来？）")
        }
        let databases = try await state.loadMetadataChildren(of: server)
        guard let db = databases.first(where: { $0.name == database }) else {
            throw XCTSkip("真库里没有探针临时库 \(database)：\(databases.map(\.name).prefix(8))")
        }
        let schemas = try await state.loadMetadataChildren(of: db)
        guard let publicSchema = schemas.first(where: { $0.name == "public" }) else {
            throw XCTSkip("探针库里没有 public schema：\(schemas.map(\.name).prefix(8))")
        }
        let objects = try await state.loadMetadataChildren(of: publicSchema)
        return Chain(server: server, database: db, schema: publicSchema, objects: objects)
    }

    /// 把这条链喂给**可见行模型**（生产路径上喂的是视图自己攒的缓存 —— 同一份纯函数）。
    private func rows(_ chain: Chain, groupByType: Bool, language: AppLanguage) -> [ObjectTreeVisibleRow] {
        ObjectTreeRows.visibleRows(
            roots: [chain.server],
            expandedIDs: [chain.server.id, chain.database.id, chain.schema.id],
            childrenCache: [
                chain.server.id: [chain.database],
                chain.database.id: [chain.schema],
                chain.schema.id: chain.objects,
            ],
            groupByType: groupByType,
            language: language
        )
    }

    /// 断开对象树并**等它落地**。
    ///
    /// 为什么必须等：`AppState` 里的「断开」是 `Task { await service.disconnect() }` —— 发出去就不管了
    /// （第 99 轮实测）。不等就结束用例，`AppState` 被释放、字典拆掉时那条连接还开着 ⇒ 踩
    /// PostgresNIO 的 `deinit` 断言（`PostgresConnection deinitialized before being closed.`
    /// → **整个测试进程被信号 5 干掉**，后面的用例一个都跑不到：本轮首跑就踩到了）。
    /// 这是**探针侧的等待**，不是给产品代码开后门。
    @MainActor
    private func disconnectAndSettle(_ state: AppState) async {
        await state.disconnectObjectTree()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// 分组表头文案 —— 语言表是唯一来源（判据里不许手抄「表」这种字面量，否则改文案时判据会假绿）。
    private func titles(
        _ language: AppLanguage
    ) -> (table: String, view: String, sequence: String, function: String, other: String) {
        (
            LocalizedStrings.text(.treeGroupTable, language: language),
            LocalizedStrings.text(.treeGroupView, language: language),
            LocalizedStrings.text(.treeGroupSequence, language: language),
            LocalizedStrings.text(.treeGroupFunction, language: language),
            LocalizedStrings.text(.treeGroupOther, language: language)
        )
    }

    /// 证据文件落在快照目录（`DOYAH_SNAPSHOT_DIR`）；**脚本会核对它** ——
    /// 探针没真跑（跳过 / 过滤没挂上）时文件不存在 ⇒ 脚本判红（跳过 ≠ 通过）。
    private func writeEvidence(_ caseName: String, _ payload: [String: Any]) throws {
        let directory = UISnapshot.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var enriched = payload
        enriched["case"] = caseName
        enriched["database"] = database
        enriched["markerTables"] = markerTables
        enriched["markerView"] = markerView
        enriched["host"] = "\(host):\(port)"
        let data = try JSONSerialization.data(
            withJSONObject: enriched,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to: directory.appendingPathComponent("grouped-view-evidence-\(caseName).json"),
            options: .atomic
        )
    }

    // MARK: - ① 两种视图都能用（真库对象喂可见行模型）

    @MainActor
    func testBothModesOverRealDatabaseObjects() async throws {
        let state = await makeAppState()
        let chain = try await realChain(in: state)

        // 夹具自检：真库里必须真有那两个标记表与那个标记视图（否则判据是在空集上"通过"）
        let names = chain.objects.map(\.name)
        for marker in markerTables {
            XCTAssertTrue(names.contains(marker), "真库子对象里没有标记表 \(marker)：\(names.prefix(10))")
        }
        XCTAssertTrue(names.contains(markerView), "真库子对象里没有标记视图 \(markerView)：\(names.prefix(10))")

        let language = LocalizationManager.shared.effectiveLanguage
        let title = titles(language)
        let hierarchy = rows(chain, groupByType: false, language: language)
        let grouped = rows(chain, groupByType: true, language: language)

        // ① 层级面：一条表头都没有，深度逐层加一（服务器 0 → 库 1 → schema 2 → 子对象 3）
        XCTAssertFalse(hierarchy.contains { $0.isGroupHeader }, "层级视图里出现了分组表头")
        XCTAssertEqual(hierarchy.map(\.depth), [0, 1, 2, 3, 3, 3])
        XCTAssertEqual(
            hierarchy.map(\.object.name),
            [chain.server.name, chain.database.name, chain.schema.name] + names
        )

        // ② 分组面：**每一层展开的容器**都会被分组（这一条是探针实测出来的形状，不是猜的）——
        //    服务器那一层的库、库那一层的 schema 都不是首选类型 ⇒ 各自落进一个「其他」组；
        //    schema 那一层的表与视图各成一个组，条数与真库对象数逐个相符。
        let headers = grouped.filter { $0.isGroupHeader }
        XCTAssertEqual(
            headers.map(\.object.name),
            [title.other, title.other, title.table, title.view],
            "分组面的表头与真库对象的类型对不上"
        )
        let tableCount = chain.objects.filter { $0.kind == .table }.count
        let viewCount = chain.objects.filter { $0.kind == .view }.count
        XCTAssertEqual(tableCount, markerTables.count, "真库里表数与标记不符（夹具没建齐？）")
        XCTAssertEqual(viewCount, 1, "真库里视图数与标记不符（夹具没建齐？）")
        XCTAssertEqual(
            headers.map { $0.object.detail ?? "" },
            ["1", "1", "\(tableCount)", "\(viewCount)"],
            "表头上的条数是错的"
        )
        // 容器层的「其他」组收的是**非首选类型**（库 / schema），不是空组
        let containerHeaders = headers.prefix(2).map(\.object.name)
        XCTAssertTrue(
            containerHeaders.allSatisfy { $0 == title.other },
            "库与 schema 这两个容器应当落在「\(title.other)」组里：\(containerHeaders)"
        )
        // 表头在子对象的上一层、组内对象再下一层（分组是**插一层**，不是把对象摊平）
        XCTAssertEqual(headers.map(\.depth), [1, 3, 5, 5])
        XCTAssertEqual(grouped.map(\.depth), [0, 1, 2, 3, 4, 5, 6, 6, 5, 6])

        // ③ 非表头行两面**逐条相同**：不漏、不重、顺序也一致（切换只是对同一份缓存重新聚合）
        XCTAssertEqual(
            grouped.filter { !$0.isGroupHeader }.map(\.object.id),
            hierarchy.map(\.object.id),
            "两种视图列出的对象不是同一批"
        )

        // ④ 每个对象都落在**对的**组里：首选类型进自己的组，其余进「其他」
        //    （根节点那一行没有表头，跳过 —— 分组只发生在**展开的容器**下面）
        var currentHeader: ObjectTreeVisibleRow?
        for row in grouped {
            if row.isGroupHeader {
                currentHeader = row
                continue
            }
            if row.depth == 0 { continue }
            guard let header = currentHeader else {
                XCTFail("\(row.object.name) 出现在任何表头之前")
                continue
            }
            if ObjectTreeGrouping.preferredKinds.contains(row.object.kind) {
                XCTAssertEqual(
                    header.object.kind, row.object.kind,
                    "\(row.object.name) 落在了「\(header.object.name)」组里"
                )
            } else {
                XCTAssertEqual(
                    header.object.name, title.other,
                    "\(row.object.name)（\(row.object.kind.rawValue)）应当落在「\(title.other)」组里"
                )
            }
        }

        // ⑤ 选中项：两面都有那一行 ⇒ 切换后高亮画得出来（像素那一半在第三个用例里）
        let selected = try XCTUnwrap(chain.objects.first { $0.kind == .table }, "真库里没有表可选")
        state.selectedTreeObject = selected
        XCTAssertTrue(hierarchy.contains { $0.object.id == selected.id }, "层级面里没有选中项那一行")
        XCTAssertTrue(grouped.contains { $0.object.id == selected.id }, "分组面里没有选中项那一行")
        XCTAssertEqual(state.selectedTreeObject?.id, selected.id)
        // 反向对照：树以外的 id 两面都找不到（防「contains 恒真」这类空转判据）
        XCTAssertFalse(hierarchy.contains { $0.object.id == "db:不在树里|table:不在树里" })
        XCTAssertFalse(grouped.contains { $0.object.id == "db:不在树里|table:不在树里" })

        try writeEvidence("realObjects", [
            "realObjectNames": names,
            "tableCount": tableCount,
            "viewCount": viewCount,
            "headerTitles": headers.map(\.object.name),
            "headerCounts": headers.map { $0.object.detail ?? "" },
            "hierarchyDepths": hierarchy.map(\.depth),
            "groupedDepths": grouped.map(\.depth),
            "selectedID": selected.id,
        ])
        await disconnectAndSettle(state)
    }

    // MARK: - ①′ 其余三个桶：序列 / 函数 / 「其他」（合成夹具）

    /// 输入来源：**合成对象**（不连库）。为什么必须补这一条 —— PG 的 schema 子节点只有表与视图两类
    /// （`Core/MetadataService.loadTables` 走 `information_schema.tables`），序列 / 函数这两个桶在
    /// 真库那条路上**走不到**，而分组视图的顺序与文案正是为五个桶写的。
    /// 合成夹具喂的是**同一个纯函数**（与真库那条同一个入口），不碰任何产品状态。
    @MainActor
    func testEveryBucketWithSyntheticFixture() throws {
        let language = AppLanguage.simplifiedChinese
        let title = titles(language)
        let parent = DatabaseObject(id: "db:合成|schema:public", name: "public", kind: .schema)

        func object(_ kind: DatabaseObject.Kind, _ name: String) -> DatabaseObject {
            DatabaseObject(
                id: "db:合成|schema:public|\(kind.rawValue):\(name)",
                name: name,
                kind: kind,
                database: "合成",
                schema: "public"
            )
        }

        let objects = [
            object(.table, "orders"),
            object(.table, "customers"),
            object(.view, "v_orders"),
            object(.sequence, "orders_seq"),
            object(.function, "fn_total"),
            object(.column, "别的类型"),   // 非首选类型 ⇒ 落「其他」桶
        ]
        let grouped = ObjectTreeRows.visibleRows(
            roots: [parent],
            expandedIDs: [parent.id],
            childrenCache: [parent.id: objects],
            groupByType: true,
            language: language
        )
        let headers = grouped.filter { $0.isGroupHeader }
        XCTAssertEqual(
            headers.map(\.object.name),
            [title.table, title.view, title.sequence, title.function, title.other],
            "五个桶的表头不齐（顺序也要对：常见类型优先、其余兜底）"
        )
        XCTAssertEqual(headers.map { $0.object.detail ?? "" }, ["2", "1", "1", "1", "1"], "桶里的条数是错的")
        // 「其他」桶真的收了那个非首选类型的对象（不是画了一个空表头）
        // （`grouped` 里第一行是根节点，取组内对象时按 depth > 0 摘掉它）
        XCTAssertEqual(
            grouped.filter { !$0.isGroupHeader && $0.depth > 0 }.map(\.object.name),
            ["orders", "customers", "v_orders", "orders_seq", "fn_total", "别的类型"]
        )
        // 同一份输入走层级面 ⇒ 一条表头都没有、六个对象平铺在同一层
        let hierarchy = ObjectTreeRows.visibleRows(
            roots: [parent],
            expandedIDs: [parent.id],
            childrenCache: [parent.id: objects],
            groupByType: false,
            language: language
        )
        XCTAssertEqual(hierarchy.map(\.depth), [0, 1, 1, 1, 1, 1, 1])
        XCTAssertFalse(hierarchy.contains { $0.isGroupHeader })

        // 边界：空子节点 ⇒ 一条表头都不产出（不做空表头）；只有一条也必须成组
        let empty = ObjectTreeRows.visibleRows(
            roots: [parent],
            expandedIDs: [parent.id],
            childrenCache: [parent.id: []],
            groupByType: true,
            language: language
        )
        XCTAssertEqual(empty.count, 1, "空子节点不该产出任何行（只该有父节点那一行）")
        XCTAssertFalse(empty.contains { $0.isGroupHeader }, "空子节点不该产出表头")
        let single = ObjectTreeRows.visibleRows(
            roots: [parent],
            expandedIDs: [parent.id],
            childrenCache: [parent.id: [object(.sequence, "only_seq")]],
            groupByType: true,
            language: language
        )
        XCTAssertEqual(
            single.filter { $0.isGroupHeader }.map(\.object.name),
            [title.sequence],
            "只有一条也必须成组"
        )
        XCTAssertEqual(single.filter { $0.isGroupHeader }.map { $0.object.detail ?? "" }, ["1"])

        try writeEvidence("syntheticBuckets", [
            "headerTitles": headers.map(\.object.name),
            "headerCounts": headers.map { $0.object.detail ?? "" },
            "objectsShown": grouped.filter { !$0.isGroupHeader }.map(\.object.name),
            "emptyChildrenRowCount": empty.count,
            "singleObjectHeaders": single.filter { $0.isGroupHeader }.map(\.object.name),
        ])
    }
    // MARK: - ② 顶部那台开关：真点击（工具栏粒度）

    /// 那台「层级视图 / 按类型分组」的开关，就是 `App/Views/ObjectTreeToolbar.swift` 里那个
    /// `Picker("", selection: $groupByType).pickerStyle(.segmented)` —— 它在 macOS 上落成
    /// `NSSegmentedControl`，所以「点一下」在**同进程内**做得到（`selectedSegment` + `sendAction`
    /// 就是真点击；合成事件只有跨进程才要辅助功能授权）。
    ///
    /// 判三件事：① 控件真在、恰好两档；② 两档**都真的到得了**（点完绑定跟着翻，不是个摆设）；
    /// ③ 两档画出来**不是一个样子**，且标签用当前界面语言（中文一遍、英文一遍）。
    ///
    /// ## 为什么只做到工具栏粒度（如实登记）
    ///
    /// 本轮先试了更狠的一条：「整棵 `ObjectTreeView` 放在活宿主里 + 连真库 + 真点击」。
    /// **做不到**，实测记录（临时诊断两条 + 日志，细节留在本轮开发记录里）：
    /// · 离屏宿主里 `.task` 的异步**本身没问题**：`.task` 里 `sleep` 之后改 `@State`，画面真的重画了；
    /// · 但真对象树在这个宿主里**始终停在加载分支**：`AppState` 那条路是好的（`StartupLog` 记着
    ///   `loadMetadataRoot()` 回了 1 个根），而拍出来的画面近空白（内容占比 0.002）、工具条
    ///   **根本不在视图树里**（工具条只存在于"已加载"那个分支）⇒ 视图状态没进到已加载态；
    /// · 日志里同时看到**同一份 `RefreshKey` 之下 `reloadRoot` 被连着唤起两次、第二次挂在
    ///   建库权限探测上不返回** —— 这条是产品侧也该看一眼的现象，登记为后续课题（`L-89` ㈡）。
    @MainActor
    func testToolbarSwitchReachesBothModes() throws {
        // ① 控件真在、恰好两档；② 两档都到得了（点完绑定翻）
        let box = ModeSwitch()
        // 工具栏只吃一个 `Binding` —— 不需要任何环境对象（比整棵对象树少一层注入 = 少一处可能崩的地方）
        let host = UISnapshot.LiveHost(ToolbarHarness(box: box), size: CGSize(width: 320, height: 48))
        let switcher = try XCTUnwrap(
            host.firstSegmentedControl,
            "工具栏里没找到分段选择器（那台「层级视图 / 按类型分组」的开关）"
        )
        XCTAssertEqual(switcher.segmentCount, 2, "分段选择器应当恰好两档：层级视图 / 按类型分组")
        XCTAssertEqual(box.value, false, "开局应当停在层级视图那一档")

        switcher.selectedSegment = 1
        switcher.sendAction(switcher.action, to: switcher.target)
        XCTAssertEqual(box.history, [true], "点第二档没有把绑定翻到「按类型分组」——那台开关是个摆设")
        switcher.selectedSegment = 0
        switcher.sendAction(switcher.action, to: switcher.target)
        XCTAssertEqual(box.history, [true, false], "点回第一档没有把绑定翻回「层级视图」")
        XCTAssertEqual(box.value, false)

        // ③ 两档画出来不是一个样子：同一份视图、只把开关拨到另一档，逐像素必须有差异
        let zhHierarchy = try renderToolbar(grouped: false, language: .simplifiedChinese)
        let zhGrouped = try renderToolbar(grouped: true, language: .simplifiedChinese)
        let enHierarchy = try renderToolbar(grouped: false, language: .english)

        // 两档的**标签都在画面上**（都是当前界面语言那一套）
        for label in [
            LocalizedStrings.text(.treeGroupHierarchy, language: .simplifiedChinese),
            LocalizedStrings.text(.treeGroupByType, language: .simplifiedChinese),
        ] {
            XCTAssertTrue(zhHierarchy.strings.contains(label), "中文界面上没有那台开关的档位文案「\(label)」")
        }
        // 反向对照：英文那一遍必须换成英文文案（语言作用域真生效，不是两边抄同一套）
        XCTAssertNotEqual(
            zhHierarchy.strings, enHierarchy.strings,
            "中英两遍渲染出来的文案一模一样 —— 语言那一遍没起作用"
        )
        XCTAssertTrue(
            enHierarchy.strings.contains(LocalizedStrings.text(.treeGroupHierarchy, language: .english)),
            "英文界面上没有那台开关的档位文案"
        )

        let hierarchyPixels = try XCTUnwrap(region(zhHierarchy.shot))
        let groupedPixels = try XCTUnwrap(region(zhGrouped.shot))
        let toolbarDiff = try XCTUnwrap(UISnapshot.differingPixels(hierarchyPixels, groupedPixels))
        XCTAssertGreaterThan(toolbarDiff, 0, "两档画出来逐像素相同 —— 那一档看不出区别")

        try writeEvidence("toolbarSwitch", [
            "segmentCount": switcher.segmentCount,
            "history": box.history.map { $0 ? "grouped" : "hierarchy" },
            "zhStrings": zhHierarchy.strings.sorted(),
            "enStrings": enHierarchy.strings.sorted(),
            "zhHierarchy": LocalizedStrings.text(.treeGroupHierarchy, language: .simplifiedChinese),
            "zhGrouped": LocalizedStrings.text(.treeGroupByType, language: .simplifiedChinese),
            "enHierarchy": LocalizedStrings.text(.treeGroupHierarchy, language: .english),
            "enGrouped": LocalizedStrings.text(.treeGroupByType, language: .english),
            "toolbarDiffPixels": toolbarDiff,
            "hierarchyScreenshot": zhHierarchy.shot.file,
            "groupedScreenshot": zhGrouped.shot.file,
        ])
    }

    /// 把工具栏在某一档 / 某一语言下渲染一遍，取回**这一遍渲染出来的文案**与那张图。
    ///
    /// 语言窗口必须在**建宿主之前**开：`LiveHost.init` 里的第一次 `settle()` 就会把这一行画出来，
    /// 窗口开晚了就什么都读不到（第 101 轮实测：晚开 → 两遍都是空集，判据静默变成 `[] == []`）。
    @MainActor
    private func renderToolbar(
        grouped: Bool,
        language: AppLanguage
    ) throws -> (strings: Set<String>, shot: UISnapshot.Record) {
        let box = ModeSwitch()
        box.value = grouped
        let scope = LocalizationManager.beginHostLanguage(language)
        defer { LocalizationManager.endHostLanguage() }
        let host = UISnapshot.LiveHost(ToolbarHarness(box: box), size: CGSize(width: 320, height: 48))
        host.settle()
        let shot = try host.capture(
            name: "grouped-view-toolbar-\(grouped ? "grouped" : "hierarchy")-\(language.rawValue)",
            language: language,
            observed: scope.observed
        )
        return (scope.observed, shot)
    }

    /// 一张快照的**整幅像素**（用于逐像素比较；尺寸取自记录，避免手抄档位）。
    private func region(_ record: UISnapshot.Record) -> UISnapshot.Band? {
        UISnapshot.region(ofPNGAt: record.file, leading: 0, top: 0, width: record.width, height: record.height)
    }
}

/// 探针用的「两档开关」状态盒：`Binding` 读写它，测试从外面看它翻没翻、翻了几次。
@MainActor
private final class ModeSwitch {
    var value = false
    var history: [Bool] = []
}

/// 工具栏 + 一行「当前是哪一档」的文案（用语言表，于是文案窗口看得见它）。
private struct ToolbarHarness: View {
    let box: ModeSwitch

    var body: some View {
        VStack(spacing: 0) {
            ObjectTreeToolbar(
                groupByType: Binding(
                    get: { box.value },
                    set: { box.value = $0; box.history.append($0) }
                ),
                isRefreshing: false,
                onSearch: {},
                onRefresh: {}
            )
            Text(L(box.value ? .treeGroupByType : .treeGroupHierarchy))
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.s)
        }
    }
}
