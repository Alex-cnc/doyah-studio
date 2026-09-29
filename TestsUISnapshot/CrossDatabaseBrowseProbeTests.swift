import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 跨库浏览：展开**非当前库**的节点时，连接是**按需**建的（`FR-META-10`）。
///
/// 待人工验收清单 §5 那一行 —— B 类第 5 条；队列 `L-89` ㈡ ⑤（开发循环第 99 轮）。
///
/// ## 这一行为什么原先要人点
///
/// 清单里那句人话：「展开非当前库的节点（对象树 / 服务器选择器）」→ 什么算过 =
/// 「**按需建连**；**失败时给可读原因**（不是 `PSQLError(...)` 兜底串）」。
/// 人点这一行，能看出来的只有「展开之后有东西出来」——**看不出建了几条连、什么时候建的、
/// 打到哪个库**。而这一条真正会出的错恰好全在那三处：
/// ① 连上就把 20 多个库**全预连**一遍（服务端立刻多出二十几个后端）；
/// ② 展开别的库时**复用当前库那条连接** ⇒ 树里列出的是**当前库**的表（看着有东西，其实是错的）；
/// ③ 连不上时把驱动原串甩到脸上。
///
/// ## 判法：观测**服务端**，不靠自己记账
///
/// 真跑两条连接（都用产品自己的驱动 `PostgresService`）：
/// ① **被测那条** = 真 `AppState`（与界面同一条路：`loadMetadataChildren(of:)`）；
/// ② **观察者** = 另一条连接查 `pg_stat_activity`。
/// 两条都 `SET application_name` 打上**本进程专属**的标记（`…_<pid>`）⇒
/// 「这个进程往哪个库开了几条后端」是**服务端的事实**，不是我们自己的计数器，
/// 也不会与集群上别的残留会话串味。
///
/// 三个断言（每个都对应上面一处真错）：
/// · **① 不全量预连**：展开服务器节点（= 列库名）之后，非当前库的后端数必须 **0**；
/// · **② 按需且打到对的库**：展开那个非当前库的**库 / schema 两级**，该库后端恰好 **1** 条，
///   且取回的子树里是**它自己的表**、**没有当前库的表**；同一节点再展开一次仍是 1 条（复用不重建）；
///   断开后本进程在该库的后端回到 0；
/// · **③ 失败可读**：展开一个不存在的库，抛出的错经 **`ErrorPresenter.message(for:)`**
///   （对象树显示加载失败的唯一收口点，`App/Views/ObjectTreeView.swift` 的 catch）
///   是人话 + 给方向，而 `String(reflecting:)` 那份确认它**确实是** `PSQLError(...)`
///   —— 反向对照，防「判据空转」。
///
/// ## 边界（如实登记）
///
/// · 要**真集群**：由 `Scripts/run-manual-verification-probes.sh` 起本机档并注入
///   `DOYAH_PROBE_PG*`；没注入时**跳过**（跳过 ≠ 通过 —— 脚本会核对证据文件，
///   探针没真跑就判红）；
/// · 只判 **PostgreSQL** 一侧：MySQL 协议族没有 schema 层（库 = schema），跨库路径形状不同，
///   本轮不假装判过；
/// · 判的是**连接**这一层（谁在什么时候往哪个库开）与**取回的子树来自哪个库**；
///   不判「服务器选择器」控件本身的排版（那属别的行）；
/// · 全程只读 `pg_stat_activity` + 在**探针自建的两个临时库**里建一张标记表；
///   不写用户偏好、不碰用户连接配置。
final class CrossDatabaseBrowseProbeTests: XCTestCase {

    /// 观察者连接打在这个库上（不落在被测的两个库里 ⇒ 不污染计数）。
    private static let observerDatabase = "postgres"
    private static let observerTagPrefix = "doyah_crossdb_observer"

    private var host = "127.0.0.1"
    private var port = 55433
    private var user = "postgres"
    private var currentDatabase = ""
    private var otherDatabase = ""
    private var missingDatabase = ""
    /// 两个库各自独有的标记表名（由证据脚本建好、经环境变量给进来 —— 名字只有一处来源）。
    private var currentMarker = ""
    private var otherMarker = ""
    /// 本进程专属标记：后端计数只认它，与集群上别的会话无关。
    private var appTag = ""
    private var observerTag = ""
    /// `AppState` 会把「选中哪条连接」写进这个偏好；探针记下原值、跑完放回去。
    private static let selectedConnectionDefaultsKey = "settings.selectedConnectionID"
    private var savedSelectedConnection: String?
    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "跨库探针要真连库：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
        let env = ProcessInfo.processInfo.environment
        guard let current = env["DOYAH_PROBE_PGCURRENT"],
              let other = env["DOYAH_PROBE_PGOTHER"],
              let missing = env["DOYAH_PROBE_PGMISSING"],
              let currentMarkerName = env["DOYAH_PROBE_PGMARKER_CURRENT"],
              let otherMarkerName = env["DOYAH_PROBE_PGMARKER_OTHER"] else {
            throw XCTSkip(
                "跨库探针要真集群：请走 Scripts/run-manual-verification-probes.sh"
                    + "（它起本机档并注入 DOYAH_PROBE_PG*）—— 跳过不算通过，脚本会核对证据文件"
            )
        }
        currentDatabase = current
        otherDatabase = other
        missingDatabase = missing
        currentMarker = currentMarkerName
        otherMarker = otherMarkerName
        host = env["DOYAH_PROBE_PGHOST"] ?? host
        port = Int(env["DOYAH_PROBE_PGPORT"] ?? "") ?? port
        user = env["DOYAH_PROBE_PGUSER"] ?? user
        let pid = ProcessInfo.processInfo.processIdentifier
        appTag = "doyah_crossdb_app_\(pid)"
        observerTag = "\(Self.observerTagPrefix)_\(pid)"
        savedSelectedConnection = UserDefaults.standard.string(forKey: Self.selectedConnectionDefaultsKey)
    }

    override func tearDownWithError() throws {
        if let saved = savedSelectedConnection {
            UserDefaults.standard.set(saved, forKey: Self.selectedConnectionDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedConnectionDefaultsKey)
        }
    }

    private func config(database: String, applicationName: String? = nil) -> ConnectionConfig {
        ConnectionConfig(
            name: "跨库探针",
            dbType: .postgresql,
            host: host,
            port: port,
            database: database,
            username: user,
            sslMode: .disable,
            timeout: 5,
            startupSQL: applicationName.map { "SET application_name = '\($0)'" }
        )
    }

    // MARK: - 观察者（查服务端事实）

    /// 起一条观察者连接并打上标记；调用方负责 `disconnect()`。
    private func makeObserver() async throws -> PostgresService {
        let service = PostgresService(
            config: config(database: Self.observerDatabase, applicationName: observerTag),
            password: nil
        )
        _ = try await service.connect()
        return service
    }

    private func rows(_ sql: String, on service: any DatabaseService) async throws -> [[String?]] {
        var out: [[String?]] = []
        for try await event in service.execute(sql, options: .default) {
            if case .resultSet(let result) = event { out = result.rows }
        }
        return out
    }

    /// 本进程往 `database` 开了几条后端（`pg_stat_activity`，这是服务端的事实）。
    private func backends(of database: String, on observer: any DatabaseService) async throws -> Int {
        let sql = """
        SELECT count(*) FROM pg_stat_activity
        WHERE datname = '\(database)' AND application_name = '\(appTag)'
        """
        let value = try await rows(sql, on: observer).first?.first ?? nil
        return Int(value ?? "") ?? -1
    }

    /// 本进程开过后端的**所有**库（用于判「没有全量预连」）。
    private func databasesWithBackends(on observer: any DatabaseService) async throws -> [String] {
        let sql = """
        SELECT datname FROM pg_stat_activity
        WHERE application_name = '\(appTag)' AND datname IS NOT NULL
        GROUP BY datname ORDER BY datname
        """
        return try await rows(sql, on: observer).compactMap { $0.first ?? nil }
    }

    /// 对象树里那个节点（真 `AppState` 的同一条路）。
    private func children(of node: DatabaseObject, in state: AppState) async throws -> [DatabaseObject] {
        try await state.loadMetadataChildren(of: node)
    }

    /// 等「本进程在某个库的后端数」落到期望值（默认等 0 = 那条连接真的断了）。
    ///
    /// **为什么要等**：断开是**异步**的 —— `AppState.invalidateService` 里写的是
    /// `Task { await service.disconnect() }`（发出去就不管了）。于是两件事：
    /// ① 「断开后后端为 0」这个断言必须等它落地，否则是**假红**；
    /// ② 若不等，`AppState` 会先被释放、字典拆掉时那条连接还开着 ⇒ 踩 PostgresNIO 的
    ///    `deinit` 断言（debug 构建直接崩）——本轮实测踩到，栈在 `AppState.deinit` → `services` 字典。
    /// 这是**探针侧的等待**，不是给产品代码开后门。
    private func waitForBackends(
        of database: String,
        to expected: Int,
        on observer: any DatabaseService,
        timeout: TimeInterval = 3
    ) async throws -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var last = -1
        while Date() < deadline {
            last = try await backends(of: database, on: observer)
            if last == expected { return last }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return last
    }

    // MARK: - 证据

    /// 证据文件落在快照目录（`DOYAH_SNAPSHOT_DIR`）；**脚本会核对它** ——
    /// 探针没真跑（跳过 / 编译期漏挂）时文件不存在 ⇒ 脚本判红（跳过 ≠ 通过）。
    private func writeEvidence(_ caseName: String, _ payload: [String: Any]) throws {
        let directory = UISnapshot.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var enriched = payload
        enriched["case"] = caseName
        enriched["currentDatabase"] = currentDatabase
        enriched["otherDatabase"] = otherDatabase
        enriched["missingDatabase"] = missingDatabase
        enriched["appTag"] = appTag
        enriched["host"] = "\(host):\(port)"
        let data = try JSONSerialization.data(
            withJSONObject: enriched,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to: directory.appendingPathComponent("cross-database-evidence-\(caseName).json"),
            options: .atomic
        )
    }

    /// 造一个带标记的连接 + 真 `AppState`（与界面同一条路）。
    ///
    /// **必须先等启动链落地**（`startupChain`）：链上的 `loadConnections()` 会把
    /// **用户真实的连接**读进 `connections`，而 `selectedConnection` 是「在 `connections` 里按 id 找」
    /// —— 不等就赋值，等链跑完那一行被覆盖，选中项指向一条不在列表里的连接 ⇒ `selectedConnection` 变 **nil**，
    /// 之后凡是要「当前连接」的动作（含对象树的断开）都会**静默不做**。
    /// 第 99 轮实测踩到：断开没生效（后端仍 1 条），随后 `AppState` 释放时字典里那条连接还开着 ⇒
    /// 踩 PostgresNIO 的 deinit 断言崩掉。`startupChain` 这个句柄本身就是为「让调用方能等它」留的。
    @MainActor
    private func makeAppState() async -> AppState {
        let state = AppState()
        await state.startupChain?.value
        let cfg = config(database: currentDatabase, applicationName: appTag)
        state.connections = [cfg]
        state.selectedConnectionID = cfg.id
        return state
    }

    private func serverNode(_ state: AppState) -> DatabaseObject {
        DatabaseObject(id: "server", name: "跨库探针", kind: .server)
    }

    // MARK: - ① 展开服务器节点 = 列库名，且**不做全量预连**

    @MainActor
    func testExpandingServerNodeListsDatabasesWithoutPreconnectingThem() async throws {
        let observer = try await makeObserver()
        let state = await makeAppState()

        let databases = try await children(of: serverNode(state), in: state)
        let names = databases.map(\.name)
        XCTAssertTrue(names.contains(currentDatabase), "库列表里没有当前库：\(names.prefix(6))")
        XCTAssertTrue(names.contains(otherDatabase), "库列表里没有非当前库 \(otherDatabase)：\(names.prefix(6))")
        XCTAssertGreaterThan(names.count, 2, "库列表只有 \(names.count) 条 —— 这条判据要的是「有别的库可选」")

        let touched = try await databasesWithBackends(on: observer)
        XCTAssertEqual(
            touched, [currentDatabase],
            "展开服务器节点之后，本进程连过的库应当**只有当前库**（按需），实测：\(touched)"
        )
        let otherCount = try await backends(of: otherDatabase, on: observer)
        XCTAssertEqual(
            otherCount, 0,
            "还没展开 \(otherDatabase)，它那里就已经有 \(otherCount) 条后端（= 把库列表里的库全预连了一遍）"
        )
        let currentCount = try await backends(of: currentDatabase, on: observer)
        XCTAssertEqual(currentCount, 1, "当前库那条连接的条数应当是 1，实测 \(currentCount)")

        try writeEvidence("serverNodeListing", [
            "databaseCount": names.count,
            "databasesWithBackends": touched,
            "currentBackends": currentCount,
            "otherBackends": otherCount,
        ])
        await state.disconnectObjectTree()
        let afterDisconnect = try await waitForBackends(of: currentDatabase, to: 0, on: observer)
        XCTAssertEqual(afterDisconnect, 0, "断开之后当前库那边还留着 \(afterDisconnect) 条后端")
        await observer.disconnect()
    }

    // MARK: - ② 展开**非当前库**：按需建连，且取回的子树来自**那个库**

    @MainActor
    func testExpandingOtherDatabaseConnectsOnDemandAndItsSubtreeComesFromThatDatabase() async throws {
        let observer = try await makeObserver()
        let state = await makeAppState()

        let databases = try await children(of: serverNode(state), in: state)
        guard let otherNode = databases.first(where: { $0.name == otherDatabase }) else {
            return XCTFail("真库列表里没有 \(otherDatabase) —— 证据脚本应当先把它建好")
        }
        guard let currentNode = databases.first(where: { $0.name == currentDatabase }) else {
            return XCTFail("真库列表里没有当前库 \(currentDatabase)")
        }

        // 库这一级：展开非当前库 ⇒ 恰好按需建一条连
        let schemas = try await children(of: otherNode, in: state)
        let schemaNames = schemas.map(\.name)
        XCTAssertTrue(schemaNames.contains("public"), "\(otherDatabase) 的 schema 列表里没有 public：\(schemaNames)")
        let afterListing = try await backends(of: otherDatabase, on: observer)
        XCTAssertEqual(afterListing, 1, "展开非当前库之后该库后端应当恰好 1 条（按需建的那条），实测 \(afterListing)")
        let currentAfter = try await backends(of: currentDatabase, on: observer)
        XCTAssertEqual(currentAfter, 1, "跨库展开把当前库那条连接换掉/重建了，实测当前库后端 \(currentAfter)")

        // schema 这一级：表必须来自**那个库**
        guard let otherPublic = schemas.first(where: { $0.name == "public" }) else {
            return XCTFail("\(otherDatabase) 的 schema 列表里没有 public")
        }
        let otherTables = (try await children(of: otherPublic, in: state)).map(\.name)
        XCTAssertTrue(otherTables.contains(otherMarker), "跨库展开到表这一级没看到该库独有的表 \(otherMarker)：\(otherTables)")
        XCTAssertFalse(otherTables.contains(currentMarker), "跨库展开却列出了**当前库**的表 \(currentMarker) —— 连接用错了库")
        let afterTables = try await backends(of: otherDatabase, on: observer)
        XCTAssertEqual(afterTables, 1, "第二级展开又建了一条连接（同一节点同一库应当复用），实测 \(afterTables)")

        // 同一节点再展开一次：仍 1 条
        _ = try await children(of: otherNode, in: state)
        let afterRepeat = try await backends(of: otherDatabase, on: observer)
        XCTAssertEqual(afterRepeat, 1, "重复展开同一个库节点又建了一条连接，实测 \(afterRepeat)")

        // 当前库那一侧照样能展开，列出的是**当前库**的表
        let currentSchemas = try await children(of: currentNode, in: state)
        guard let currentPublic = currentSchemas.first(where: { $0.name == "public" }) else {
            return XCTFail("当前库 \(currentDatabase) 的 schema 列表里没有 public")
        }
        let currentTables = (try await children(of: currentPublic, in: state)).map(\.name)
        XCTAssertTrue(currentTables.contains(currentMarker), "当前库的表里没看到 \(currentMarker)")
        XCTAssertFalse(currentTables.contains(otherMarker), "当前库那一侧列出了非当前库的表 \(otherMarker)")

        try writeEvidence("crossDatabaseOnDemand", [
            "otherBackendsAfterListingDatabase": afterListing,
            "otherBackendsAfterSchema": afterTables,
            "otherBackendsAfterRepeat": afterRepeat,
            "currentBackends": currentAfter,
            "otherTableMarkerSeen": otherTables.contains(otherMarker),
            "currentMarkerLeakedIntoOther": otherTables.contains(currentMarker),
        ])

        // 断开 ⇒ 本进程在该库不留后端（「含对象树按需建立的其它库连接」，见 `disconnectObjectTree`）
        await state.disconnectObjectTree()
        let afterDisconnect = try await waitForBackends(of: otherDatabase, to: 0, on: observer)
        XCTAssertEqual(afterDisconnect, 0, "断开连接之后 \(otherDatabase) 那边还留着 \(afterDisconnect) 条后端")
        let currentAfterDisconnect = try await waitForBackends(of: currentDatabase, to: 0, on: observer)
        XCTAssertEqual(currentAfterDisconnect, 0, "断开之后当前库那边还留着 \(currentAfterDisconnect) 条后端")
        await observer.disconnect()
    }

    // MARK: - ③ 展开一个不存在的库：**可读原因**，不是 `PSQLError(...)` 兜底串

    @MainActor
    func testExpandingMissingDatabaseSurfacesReadableReason() async throws {
        let state = await makeAppState()
        let node = DatabaseObject(
            id: "db:\(missingDatabase)",
            name: missingDatabase,
            kind: .database,
            database: missingDatabase
        )

        let shown: String
        do {
            let children = try await children(of: node, in: state)
            await state.disconnectObjectTree()
            return XCTFail("展开一个不存在的库居然成了，还拿到 \(children.count) 个子节点")
        } catch {
            let raw = String(reflecting: error)
            // 反向对照（防判据空转）：底层抛的**确实是**驱动那种转储串。
            XCTAssertTrue(
                raw.contains("PSQLError("),
                "反向对照不成立：底层抛的不是驱动错误 ⇒ 下面几条判据会空转。原始串：\(raw.prefix(160))"
            )
            shown = ErrorPresenter.message(for: error)
        }

        // 这些是**对象树显示加载失败**的唯一收口点算出来的那句话（见 ObjectTreeView 的 catch）。
        XCTAssertFalse(shown.contains("PSQLError("), "界面上会给用户看 `PSQLError(...)` 兜底串：\(shown)")
        XCTAssertFalse(shown.contains("serverInfo:"), "界面上会给用户看驱动的反射转储：\(shown)")
        XCTAssertTrue(shown.contains("数据库不存在或无权连接"), "没有给出「是什么事」：\(shown)")
        let lines = shown.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertGreaterThanOrEqual(lines.count, 2, "只说了失败、没给方向（第二行缺失）：\(shown)")
        XCTAssertTrue(shown.contains("确认库名拼写"), "给了方向但方向不对：\(shown)")

        try writeEvidence("missingDatabaseReadable", [
            "shownMessage": shown,
            "rawIsDriverDump": true,
            "shownNamesTheDatabase": shown.contains(missingDatabase),
            "shownLineCount": lines.count,
        ])
        await state.disconnectObjectTree()
    }
}
