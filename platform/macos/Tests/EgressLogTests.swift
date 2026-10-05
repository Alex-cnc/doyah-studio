import XCTest
@testable import DoyahCore

/// 统一外发日志（NFR-SEC-08）的回归测试。
///
/// 这份日志要支撑的是一句对外承诺：**默认零外发、最小外发**。所以测试盯住四件事：
///   ① 出网必留痕（含"发出前先记"与"失败也记"）；
///   ② 被拦下的请求也留痕（`denied`）；
///   ③ **日志自身不能成为泄漏源**（目标去掉 query/fragment，正文统一脱敏）；
///   ④ 零外发时可验证（没有任何出网 → 日志为空）。
final class EgressLogTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EgressLogTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    private func makeLog() -> EgressLog {
        EgressLog(directoryURL: directory)
    }

    // MARK: - 目标净化

    /// query 与 fragment 里最常见地带着密钥，必须被去掉。
    func testSanitizeStripsQueryFragmentAndCredential() {
        let raw = "https://api.openai.com/v1/chat/completions?api_key=sk-secret123#access_token=abc"
        let sanitized = EgressTarget.sanitize(raw)

        XCTAssertEqual(sanitized, "https://api.openai.com/v1/chat/completions")
        XCTAssertFalse(sanitized.contains("sk-secret123"))
        XCTAssertFalse(sanitized.contains("access_token"))
    }

    /// 外部程序名这类非 URL 目标原样保留（但同样过一遍脱敏）。
    func testSanitizeKeepsProgramNames() {
        XCTAssertEqual(EgressTarget.sanitize("pg_dump"), "pg_dump")
        XCTAssertEqual(EgressTarget.sanitize("  ssh  "), "ssh")
    }

    // MARK: - 记录与读取

    func testRecordAppendsAndReadsBackNewestFirst() async throws {
        let log = makeLog()
        let older = EgressEntry(
            timestamp: Date(timeIntervalSince1970: 1_000),
            kind: .agentModel, target: "https://a.example", origin: "智能体 · 生成 SQL",
            outcome: .allowed
        )
        let newer = EgressEntry(
            timestamp: Date(timeIntervalSince1970: 2_000),
            kind: .browser, target: "https://b.example", origin: "浏览器 · 页签 1",
            outcome: .allowed
        )
        await log.append(older)
        await log.append(newer)

        let entries = try await log.entries()
        let count = try await log.count()
        let path = await log.fileLocation().path
        XCTAssertEqual(entries.map(\.target), ["https://b.example", "https://a.example"])
        XCTAssertEqual(count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    /// 零外发可验证：什么都没发生 → 日志为空，且**连文件都不该存在**。
    func testNoEgressMeansEmptyLog() async throws {
        let log = makeLog()
        let entries = try await log.entries()
        let path = await log.fileLocation().path
        XCTAssertEqual(entries.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    /// 被拦下的请求也要留痕（与"没想发"区分开）。
    func testDeniedRequestsAreRecorded() async throws {
        let log = makeLog()
        await log.record(
            kind: .agentModel,
            target: "https://api.example/v1/chat",
            origin: "智能体 · 生成 SQL",
            outcome: .denied,
            detail: "智能体总开关关闭"
        )
        let entries = try await log.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outcome, .denied)
    }

    // MARK: - 日志自身不得泄漏

    func testLogFileAndExportsNeverContainSecrets() async throws {
        let log = makeLog()
        await log.record(
            kind: .agentModel,
            target: "https://api.example/v1/chat?api_key=sk-shouldnotappear",
            origin: "智能体 · 生成 SQL",
            outcome: .failed,
            detail: "请求头 Authorization: Bearer sk-shouldnotappear"
        )

        let location = await log.fileLocation()
        let raw = try String(contentsOf: location, encoding: .utf8)
        XCTAssertFalse(raw.contains("sk-shouldnotappear"), "落盘内容不得含密钥")
        XCTAssertFalse(raw.contains("Bearer"), "落盘的失败原因也要脱敏")

        let json = try String(data: try await log.exportJSON(), encoding: .utf8) ?? ""
        let csv = try await log.exportCSV()
        XCTAssertFalse(json.contains("sk-shouldnotappear"))
        XCTAssertFalse(csv.contains("sk-shouldnotappear"))
    }

    // MARK: - 导出与清空

    func testExportCSVHasHeaderAndEscapesFields() async throws {
        let log = makeLog()
        await log.record(
            kind: .externalProgram,
            target: "pg_dump",
            origin: "导出 · 连接 A",
            outcome: .allowed,
            detail: "带,逗号 与\"引号\""
        )
        let csv = try await log.exportCSV()
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "时间,类别,目标,触发来源,结果,补充")
        XCTAssertTrue(csv.contains("\"带,逗号"), "含逗号的字段必须被引号包住")
        XCTAssertTrue(lines.count >= 2)
    }

    func testClearRemovesEverything() async throws {
        let log = makeLog()
        await log.record(kind: .updateCheck, target: "https://update.example", origin: "更新检查", outcome: .allowed)
        try await log.clear()

        let count = try await log.count()
        let path = await log.fileLocation().path
        XCTAssertEqual(count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - HTTP 装饰器（唯一出网缝）

    /// 成功：**发出前先记一条**（进程若中途被杀，记录已在），且包裹的传输只被调用一次。
    func testRecordingTransportRecordsBeforeSending() async throws {
        let log = makeLog()
        let recorder = CountingTransport()
        let transport = EgressRecordingTransport(
            origin: "智能体 · 生成 SQL",
            wrapped: recorder,
            log: log
        )

        var request = URLRequest(url: URL(string: "https://api.example/v1/chat?api_key=sk-x")!)
        request.httpMethod = "POST"
        _ = try await transport.send(request)

        let entries = try await log.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outcome, .allowed)
        XCTAssertEqual(entries.first?.target, "https://api.example/v1/chat")
        XCTAssertEqual(entries.first?.kind, .agentModel)
        let calls = await recorder.callCount
        XCTAssertEqual(calls, 1, "装饰器不得重复发送请求")
    }

    /// 失败：已发出的记录 + 一条失败记录（**不能只有失败、也不能只有发出**）。
    func testRecordingTransportRecordsFailureAndRethrows() async throws {
        struct FailingTransport: HTTPTransport {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                throw AppError.queryFailed("网络不可达")
            }
        }
        let log = makeLog()
        let transport = EgressRecordingTransport(
            origin: "智能体 · 生成 SQL",
            wrapped: FailingTransport(),
            log: log
        )

        do {
            _ = try await transport.send(URLRequest(url: URL(string: "https://api.example/v1/chat")!))
            XCTFail("应当把错误继续抛出，不能吞掉")
        } catch {
            // 预期：错误原样上抛
        }

        let entries = try await log.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.outcome)), [.allowed, .failed])
        XCTAssertTrue(entries.contains { ($0.detail ?? "").contains("网络不可达") })
    }

    // MARK: - 落盘的那份是「脱敏后的副本」（第 103 轮实测的真缺陷）

    /// **真缺陷（2026-09-29 第 103 轮）**：`append` 落盘的不是传进来那个对象，而是
    /// **脱敏重造的一份副本** —— 那次重建漏了 `tabID` / `tabTitle`，于是盘上每条浏览器记录
    /// 都没有页签身份，「按页签筛」那台下拉永远空、永远灰（人手上点就是这个现象）。
    ///
    /// 上面那条编解码往返**摸不到这个重建**（它自己 encode / decode，不经过 `append`）
    /// ⇒ 判据必须**从 `append` 进、从盘上出**，而且换一个实例读，别读内存。
    func testAppendKeepsTabIdentityOnDisk() async throws {
        let tab = UUID()
        let log = makeLog()
        await log.append(
            EgressEntry(
                kind: .browser,
                target: "https://docs.example/a",
                origin: "浏览器 · 页签",
                outcome: .allowed,
                detail: nil,
                tabID: tab,
                tabTitle: "文档"
            )
        )

        let reread = try await makeLog().entries()   // 换一个实例：判据看盘，不看内存
        XCTAssertEqual(reread.count, 1)
        XCTAssertEqual(reread.first?.tabID, tab, "盘上那条没有页签 id ⇒ 按页签筛永远查不到它")
        XCTAssertEqual(reread.first?.tabTitle, "文档", "盘上那条没有页签标题")
    }

    /// 脱敏**不许**把页签身份脱掉，同时**该脱的照脱**：目标仍要去 query、正文仍要脱敏。
    func testAppendStillRedactsWhileKeepingTabIdentity() async throws {
        let tab = UUID()
        let log = makeLog()
        await log.append(
            EgressEntry(
                kind: .browser,
                target: "https://docs.example/a?token=sk-secret123",
                origin: "浏览器 · 页签",
                outcome: .allowed,
                detail: "Authorization: Bearer sk-secret123",
                tabID: tab,
                tabTitle: "文档"
            )
        )

        let entries = try await makeLog().entries()
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.tabID, tab)
        XCTAssertFalse(entry.target.contains("sk-secret123"), "目标里的 query 必须去掉")
        XCTAssertFalse((entry.detail ?? "").contains("sk-secret123"), "正文里的密钥必须脱敏")
    }
}

/// 统计被调用次数的假传输。
private actor CountingTransport: HTTPTransport {
    private(set) var callCount = 0

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data("{}".utf8), response)
    }
}

/// 筛选条件（NFR-SEC-08）：面板 / 导出将来共用同一份实现，所以它必须自己先被测住。
final class EgressFilterTests: XCTestCase {

    private func entry(
        _ kind: EgressKind,
        _ outcome: EgressOutcome,
        target: String = "https://api.example/v1",
        origin: String = "智能体 · 生成 SQL",
        detail: String? = nil
    ) -> EgressEntry {
        EgressEntry(kind: kind, target: target, origin: origin, outcome: outcome, detail: detail)
    }

    private var sample: [EgressEntry] {
        [
            entry(.agentModel, .allowed),
            entry(.agentModel, .denied, detail: "总开关关闭"),
            entry(.browser, .allowed, target: "https://docs.example/page", origin: "浏览器 · 页签"),
            entry(.externalProgram, .failed, target: "pg_dump", origin: "导出", detail: "退出码 1")
        ]
    }

    func testEmptyFilterKeepsEverything() {
        let filter = EgressFilter()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.apply(to: sample).count, 4)
    }

    /// 浏览器与智能体共用一份日志：能按类别分开看，才不会互相淹没。
    func testKindFilter() {
        XCTAssertEqual(EgressFilter(kind: .browser).apply(to: sample).count, 1)
        XCTAssertEqual(EgressFilter(kind: .agentModel).apply(to: sample).count, 2)
    }

    /// 「只看被拦下的」是最常用的一档：它回答"有没有想发但没发出去的"。
    func testOutcomeFilterFindsDenied() {
        let denied = EgressFilter(outcome: .denied).apply(to: sample)
        XCTAssertEqual(denied.count, 1)
        XCTAssertEqual(denied.first?.detail, "总开关关闭")
    }

    func testKeywordMatchesTargetOriginAndDetail() {
        XCTAssertEqual(EgressFilter(keyword: "docs.example").apply(to: sample).count, 1)
        XCTAssertEqual(EgressFilter(keyword: "浏览器").apply(to: sample).count, 1)
        XCTAssertEqual(EgressFilter(keyword: "退出码").apply(to: sample).count, 1)
        XCTAssertEqual(EgressFilter(keyword: "PG_DUMP").apply(to: sample).count, 1, "关键词不区分大小写")
    }

    func testCombinedFilter() {
        let filtered = EgressFilter(kind: .agentModel, outcome: .allowed).apply(to: sample)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.outcome, .allowed)
    }

    // MARK: - 按浏览器页签筛选（FR-EDIT-34）

    private func tabEntry(_ tabID: UUID, title: String, target: String) -> EgressEntry {
        EgressEntry(
            kind: .browser,
            target: target,
            origin: "浏览器 · 页签",
            outcome: .allowed,
            detail: nil,
            tabID: tabID,
            tabTitle: title
        )
    }

    func testTabFilterKeepsOnlyThatTab() {
        let first = UUID()
        let second = UUID()
        let entries = [
            tabEntry(first, title: "文档", target: "https://docs.example/a"),
            tabEntry(second, title: "工单", target: "https://tickets.example/b"),
            tabEntry(first, title: "文档", target: "https://docs.example/c"),
        ]
        let filter = EgressFilter(tabID: first)
        XCTAssertTrue(filter.isActive)
        let filtered = filter.apply(to: entries)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.tabID == first })
    }

    /// 非浏览器来源（tabID 为 nil）不该被"某个页签"的筛选带出来。
    func testTabFilterExcludesEntriesWithoutTab() {
        let tab = UUID()
        let entries = [entry(.agentModel, .allowed), tabEntry(tab, title: "文档", target: "https://docs.example")]
        XCTAssertEqual(EgressFilter(tabID: tab).apply(to: entries).count, 1)
    }

    /// **向后兼容**：老日志文件里没有 `tabID` / `tabTitle` 这两个键，必须还能解码
    /// （否则升级后整个外发日志读不出来，历史审计记录等于丢了）。
    func testEntriesDecodeWithoutTabFields() throws {
        let legacy = """
        {"id":"6B29FC40-CA47-1067-B31D-00DD010662DA","timestamp":760000000,"kind":"browser",
         "target":"https://docs.example/page","origin":"浏览器 · 页签","outcome":"allowed"}
        """
        let entry = try JSONDecoder().decode(EgressEntry.self, from: Data(legacy.utf8))
        XCTAssertNil(entry.tabID)
        XCTAssertNil(entry.tabTitle)
        XCTAssertEqual(entry.target, "https://docs.example/page")
    }

    func testEntriesRoundTripWithTabFields() throws {
        let tab = UUID()
        let original = tabEntry(tab, title: "文档", target: "https://docs.example/a")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EgressEntry.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

/// 「按浏览器页签筛」那台下拉的选项推导（FR-EDIT-34）——**第 103 轮从 `EgressLogSheet` 搬出来的**。
///
/// 为什么值得单独测：它从前是视图里的一个 `private var`，于是「日志里出现过的页签」
/// **只有渲染出来才看得见** —— 而本机 SwiftUI 的 `Picker` 不落到 AppKit 控件（同轮实测：
/// 离屏宿主里一个 `NSPopUpButton` 都没有），判据连控件都摸不到 ⇒ 搬成纯函数之后，
/// 判据可以拿**盘上读回来的真记录**直接判它。
final class EgressTabOptionsTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EgressTabOptionsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    private func tabEntry(_ tabID: UUID?, title: String?, target: String) -> EgressEntry {
        EgressEntry(
            kind: .browser,
            target: target,
            origin: "浏览器 · 页签",
            outcome: .allowed,
            detail: nil,
            tabID: tabID,
            tabTitle: title
        )
    }

    /// 顺序 = 日志里**首次出现的顺序**（`entries()` 新的在前）；一个页签只出一个选项。
    func testOptionsFollowLogOrderAndCollapseToOnePerTab() {
        let first = UUID()
        let second = UUID()
        let entries = [
            tabEntry(first, title: "文档", target: "https://docs.example/c"),
            tabEntry(second, title: "工单", target: "https://tickets.example/b"),
            tabEntry(first, title: "文档", target: "https://docs.example/a")
        ]

        let options = EgressTabOptions.options(from: entries)
        XCTAssertEqual(options.map(\.id), [first, second])
        XCTAssertEqual(options.map(\.label), ["文档", "工单"])
    }

    /// **这条就是那个真缺陷的行为面**：记录没有页签身份 ⇒ 下拉里一个选项都没有
    /// （而脱敏重建漏字段时，盘上每条浏览器记录都长这样）。
    func testEntriesWithoutTabIdentityProduceNoOptions() {
        let entries = [
            tabEntry(nil, title: nil, target: "https://docs.example/a"),
            EgressEntry(kind: .agentModel, target: "https://api.example/v1", origin: "智能体 · 生成 SQL", outcome: .allowed)
        ]
        XCTAssertTrue(
            EgressTabOptions.options(from: entries).isEmpty,
            "没有页签身份的记录不该产出选项（下拉会永远空、永远灰）"
        )
    }

    /// 缺标题时退回 id 前 8 位 —— 至少让人认得出「是同一个页签」，而不是给一个空标签。
    func testLabelFallsBackToShortIDWhenTitleMissing() {
        let tab = UUID()
        let options = EgressTabOptions.options(from: [tabEntry(tab, title: nil, target: "https://docs.example/a")])
        XCTAssertEqual(options.map(\.label), [String(tab.uuidString.prefix(8))])
    }

    /// 标题可能**先是「新页签」、后来才成真标题**：短标签允许被后来的标题替换；够长的就钉住。
    /// （`entries()` 新的在前 ⇒ 数组里**索引越小越新**。）
    func testShortPlaceholderLabelIsReplacedByLaterTitle() {
        let tab = UUID()
        let pinned = EgressTabOptions.options(from: [
            tabEntry(tab, title: "文档仓库（很长的一个标题）", target: "https://docs.example/b"),
            tabEntry(tab, title: "新页签", target: "https://docs.example/a")
        ])
        XCTAssertEqual(
            pinned.map(\.label),
            ["文档仓库（很长的一个标题）"],
            "最新的标签够长（≥ \(EgressTabOptions.replaceableLabelLength) 字）⇒ 钉住，别被更早的占位标题顶掉"
        )

        let replaced = EgressTabOptions.options(from: [
            tabEntry(tab, title: "新页签", target: "https://docs.example/a"),
            tabEntry(tab, title: "文档", target: "https://docs.example/b")
        ])
        XCTAssertEqual(replaced.map(\.label), ["文档"], "最新那条还是占位标题（「新页签」）⇒ 允许被更早的真标题替换")
    }

    /// 端到端：**从 `append` 进、从盘上出**再算选项 —— 这是探针那条判据的单测版。
    func testOptionsDerivedFromEntriesReadBackFromDisk() async throws {
        let tab = UUID()
        let log = EgressLog(directoryURL: directory)
        await log.append(tabEntry(tab, title: "文档", target: "https://docs.example/a"))
        await log.append(
            EgressEntry(
                kind: .browser,
                target: "https://cdn.example/report.zip",
                origin: "浏览器 · 下载",
                outcome: .allowed,
                detail: nil,
                tabID: tab,
                tabTitle: "文档"
            )
        )

        let onDisk = try await EgressLog(directoryURL: directory).entries()
        XCTAssertEqual(onDisk.count, 2)
        XCTAssertEqual(EgressTabOptions.options(from: onDisk).map(\.id), [tab])
        XCTAssertEqual(EgressTabOptions.options(from: onDisk).map(\.label), ["文档"])
    }
}
