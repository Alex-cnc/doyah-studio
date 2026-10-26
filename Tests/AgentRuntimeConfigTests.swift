import XCTest
@testable import DoyahCore

/// `FR-AGT-OPS-OBS-002` 可配置面的机械判据：**改完立即生效、有据可查、非法拒收**。
///
/// 三条验收要点逐条落：
/// ① 每项配置有默认值与影响说明 —— 默认值在 `AgentConfigSnapshot()` 里，判据钉住它；
/// ② 配置变更留痕（改前改后）—— `applyBatch` 落下的每条 `AgentConfigChange` 都对拍；
/// ③ 非法配置拒绝保存并说明 —— 越界 / 未知键 / 缺理由三种都拒，且**批量原子**（一条都没落）。
/// 生效面单独判：工具白名单真改注册表可见性、通知开关只关系统那一格、日配额真拦住。
final class AgentRuntimeConfigTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-runtime-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - ① 默认值

    func testDefaultsAreWhatThePanelShows() {
        let snapshot = AgentConfigSnapshot()
        XCTAssertEqual(snapshot.maxConcurrentSubtasks, 3)
        XCTAssertEqual(snapshot.commandTimeoutSeconds, 60)
        XCTAssertEqual(snapshot.dailyTokenQuota, 200_000)
        XCTAssertTrue(snapshot.notificationsEnabled)
        XCTAssertEqual(snapshot.toolWhitelist, [], "空白名单 = 不限制（默认放开全部已注册工具）")

        // 草稿从默认快照回填：一个字段都不能空（空白保存一次就等于清掉用户设置）
        let draft = AgentRuntimeConfigDraft(snapshot: snapshot)
        XCTAssertEqual(draft.edits(against: snapshot), [], "原样回填不算改动")
    }

    // MARK: - ② 差异口径

    func testEditsListOnlyWhatChanged() {
        let snapshot = AgentConfigSnapshot()
        var draft = AgentRuntimeConfigDraft(snapshot: snapshot)

        draft.commandTimeoutSeconds = "120"
        draft.notificationsEnabled = false
        let edits = draft.edits(against: snapshot)
        XCTAssertEqual(edits.map(\.key), ["commandTimeoutSeconds", "notificationsEnabled"])
        XCTAssertEqual(edits.map(\.value), ["120", "false"])

        // 空白与格式差异不算改动（数字按数值比）
        draft.commandTimeoutSeconds = " 200000 "
        draft.notificationsEnabled = true
        let whitespace = AgentRuntimeConfigDraft(maxConcurrentSubtasks: " 3 ",
                                                 commandTimeoutSeconds: " 60 ",
                                                 dailyTokenQuota: "200000",
                                                 notificationsEnabled: true,
                                                 toolWhitelist: " read_file , list_dir ")
        XCTAssertEqual(whitespace.edits(against: AgentConfigSnapshot(toolWhitelist: ["read_file", "list_dir"])), [])

        // 白名单去空白保序；改了顺序算改动（顺序是用户心里的优先级）
        draft = AgentRuntimeConfigDraft(snapshot: snapshot)
        draft.toolWhitelist = " list_dir , read_file ,, "
        XCTAssertEqual(AgentRuntimeConfigDraft.toolNames(draft.toolWhitelist), ["list_dir", "read_file"])
        XCTAssertEqual(draft.edits(against: snapshot).map(\.key), ["toolWhitelist"])
    }

    func testIllegalNumberIsAnEditNotASilentDrop() {
        var draft = AgentRuntimeConfigDraft(snapshot: AgentConfigSnapshot())
        draft.dailyTokenQuota = "abc"
        let edits = draft.edits(against: AgentConfigSnapshot())
        // 解不出来也必须进名单：由 store 拒收并给允许范围，界面层不许悄悄丢掉
        XCTAssertEqual(edits.map(\.key), ["dailyTokenQuota"])
        var store = AgentConfigStore()
        XCTAssertThrowsError(try store.applyBatch(edits, reason: "改配额")) { error in
            XCTAssertEqual(error as? AgentConfigError,
                           .outOfRange(key: "dailyTokenQuota", value: "abc", allowed: "1000–1 亿"))
        }
    }

    // MARK: - ③ 批量原子 + 留痕

    func testApplyBatchIsAtomicAndKeepsBeforeAfter() throws {
        var store = AgentConfigStore()
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let applied = try store.applyBatch([.init(key: "commandTimeoutSeconds", value: "120"),
                                            .init(key: "dailyTokenQuota", value: "500000")],
                                           reason: "长任务要更久、配额加一档", at: at)
        XCTAssertEqual(applied.map(\.key), ["commandTimeoutSeconds", "dailyTokenQuota"])
        XCTAssertEqual(applied.map(\.oldValue), ["60", "200000"])
        XCTAssertEqual(applied.map(\.newValue), ["120", "500000"])
        XCTAssertEqual(store.snapshot.commandTimeoutSeconds, 120)
        XCTAssertEqual(store.changes.count, 2)
        XCTAssertEqual(applied.first?.reason, "长任务要更久、配额加一档")

        // 中途非法 ⇒ 整批不落：快照与留痕都停在上一次的样子
        let before = store
        XCTAssertThrowsError(try store.applyBatch([.init(key: "maxConcurrentSubtasks", value: "4"),
                                                   .init(key: "commandTimeoutSeconds", value: "999999")],
                                                  reason: "试试")) { error in
            XCTAssertEqual(error as? AgentConfigError,
                           .outOfRange(key: "commandTimeoutSeconds", value: "999999", allowed: "1–3600 秒"))
        }
        XCTAssertEqual(store.snapshot, before.snapshot, "第二条非法，第一条也不许留下")
        XCTAssertEqual(store.changes.count, before.changes.count)

        // 缺理由整批不落
        XCTAssertThrowsError(try store.applyBatch([.init(key: "maxConcurrentSubtasks", value: "4")], reason: "  ")) {
            XCTAssertEqual($0 as? AgentConfigError, .missingReason)
        }
        XCTAssertEqual(store.snapshot, before.snapshot)
    }

    func testUnknownKeyIsRejected() {
        var store = AgentConfigStore()
        XCTAssertThrowsError(try store.apply(key: "approvalPolicy", value: "always", reason: "想加一项")) {
            XCTAssertEqual($0 as? AgentConfigError, .unknownKey("approvalPolicy"))
        }
        XCTAssertEqual(store.changes.count, 0)
    }

    // MARK: - 文件往返 / 降级

    func testFileRoundTripsSnapshotAndHistory() throws {
        let file = AgentRuntimeConfigFile(directory: directory)
        XCTAssertEqual(file.load().state, .fresh, "没有文件 = 全新安装，不是坏了")

        var store = AgentConfigStore()
        try store.applyBatch([.init(key: "dailyTokenQuota", value: "300000"),
                              .init(key: "toolWhitelist", value: "read_file,search")],
                             reason: "先只放开两个只读工具", at: Date(timeIntervalSince1970: 1_700_000_100))
        try file.save(store)

        let reloaded = file.load()
        XCTAssertEqual(reloaded.state, .loaded)
        XCTAssertEqual(reloaded.store.snapshot.dailyTokenQuota, 300_000)
        XCTAssertEqual(reloaded.store.snapshot.toolWhitelist, ["read_file", "search"])
        XCTAssertEqual(reloaded.store.changes.count, 2)
        XCTAssertEqual(reloaded.store.changes.first?.reason, "先只放开两个只读工具")
        XCTAssertEqual(reloaded.store.changes.first?.oldValue, "200000")
    }

    func testCorruptFileAndHandEditedIllegalValueDegradeInsteadOfBeingTrusted() throws {
        let file = AgentRuntimeConfigFile(directory: directory)
        try Data("not json".utf8).write(to: file.fileURL)
        let corrupt = file.load()
        XCTAssertEqual(corrupt.state, .degraded(reason: "parseFailed"))
        XCTAssertEqual(corrupt.store.snapshot, AgentConfigSnapshot(), "坏文件回落默认值")

        // 手改出一个非法值（配额 0）：不静默采信，点名是哪一项、允许什么
        let illegal = """
        {"snapshot":{"dailyTokenQuota":0,"commandTimeoutSeconds":60,"maxConcurrentSubtasks":3,\
        "model":"默认","notificationsEnabled":true,"toolWhitelist":[]},"changes":[]}
        """
        try Data(illegal.utf8).write(to: file.fileURL)
        let degraded = file.load()
        XCTAssertEqual(degraded.state, .degraded(reason: "outOfRange:dailyTokenQuota=0 allowed 1000–1 亿"))
        XCTAssertEqual(degraded.store.snapshot, AgentConfigSnapshot())
    }

    // MARK: - 生效面（改完立即生效）

    func testToolWhitelistActuallyHidesOtherTools() {
        let registry = AgentToolRegistry.standard
        let all = registry.enabledDefinitions.map(\.name)
        XCTAssertGreaterThan(all.count, 1, "标准注册表不该只有一个工具")

        let allowed = Array(all.prefix(2))
        let applied = registry.applyingWhitelist(allowed)
        XCTAssertEqual(applied.registry.enabledDefinitions.map(\.name).sorted(), allowed.sorted())
        XCTAssertEqual(applied.hidden.sorted(), all.filter { !allowed.contains($0) }.sorted())
        XCTAssertTrue(applied.unknown.isEmpty)

        // 空名单 = 不限制（返回自己，不隐藏任何东西）
        let unrestricted = registry.applyingWhitelist([])
        XCTAssertEqual(unrestricted.registry.enabledDefinitions.count, registry.enabledDefinitions.count)
        XCTAssertTrue(unrestricted.hidden.isEmpty)

        // 写了不存在的工具名 ⇒ 如实点名，不静默忽略
        let typo = registry.applyingWhitelist(["read_file", "read_fil"])
        XCTAssertEqual(typo.unknown, ["read_fil"])
    }

    func testNotificationsSwitchOnlySilencesSystemPopup() {
        let policy = AgentNotifyPolicy()
        let on = policy.plan(.failed(summary: "读取连接失败"), userIsLookingAtThisPane: false, userIsIdle: true)
        XCTAssertNotNil(on.system)

        let off = policy.plan(.failed(summary: "读取连接失败"), userIsLookingAtThisPane: false, userIsIdle: true,
                              systemNotificationsEnabled: false)
        XCTAssertNil(off.system, "关掉通知规则 ⇒ 系统那一格不出")
        XCTAssertNotNil(off.banner, "但页内提示条照出（否则界面上根本看不见这件事）")
    }

    func testDailyQuotaLedgerBlocksWhenExhaustedAndRollsOver() {
        let ledger = AgentDailyUsageLedger(directory: directory)
        let calendar = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_793_000_000)      // 2026-10-26 前后，判据只比日号
        let tomorrow = today.addingTimeInterval(86_400 * 2)

        XCTAssertEqual(ledger.verdict(quota: 1000, at: today, calendar: calendar), .allowed(remaining: 1000))
        XCTAssertEqual(ledger.record(tokens: 600, at: today, calendar: calendar).tokens, 600)
        XCTAssertEqual(ledger.record(tokens: 400, at: today, calendar: calendar).tokens, 1000)
        // 正好用满即拦住（边界：`used >= quota`）
        XCTAssertEqual(ledger.verdict(quota: 1000, at: today, calendar: calendar), .exhausted(used: 1000, quota: 1000))
        // 跨日归零
        XCTAssertEqual(ledger.reading(at: tomorrow, calendar: calendar).tokens, 0)
        XCTAssertEqual(ledger.verdict(quota: 1000, at: tomorrow, calendar: calendar), .allowed(remaining: 1000))

        // 账本坏了 ⇒ 按 0 计但如实标降级（不把「读不出来」说成「今天没用过」）
        try? Data("broken".utf8).write(to: ledger.fileURL)
        let degraded = ledger.reading(at: today, calendar: calendar)
        XCTAssertEqual(degraded.tokens, 0)
        XCTAssertTrue(degraded.degraded)
    }
}
