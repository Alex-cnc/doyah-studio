import XCTest
@testable import DoyahCore

/// `NFR-AI-08` + `FR-AI-30` ③（检查点存储半）—— 提案 `0009` C 片的四条机械判据。
final class AgentCheckpointTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-checkpoint-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> AgentCheckpointStore { AgentCheckpointStore(directory: directory) }

    private func checkpoint(_ step: Int, session: String = "s-1") -> AgentCheckpoint {
        AgentCheckpoint(sessionID: session,
                        stepIndex: step,
                        completedSteps: ["step-\(step)"],
                        pendingMessagesDigest: "digest-\(step)",
                        at: Date(timeIntervalSince1970: 1_700_000_000 + Double(step)))
    }

    /// 直接改盘上的 JSONL（判据要造坏行 / 删最后一条）。
    private func rewriteLines(_ lines: [String]) throws {
        try lines.joined(separator: "\n").appending("\n").write(to: makeStore().fileURL,
                                                               atomically: true, encoding: .utf8)
    }

    private func readLines() throws -> [String] {
        let text = try String(contentsOf: makeStore().fileURL, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    // MARK: - 判据 1：往返（写 N 个 ⇒ 读回最后一个，字段逐项一致）

    func testRoundTripReturnsTheLastCheckpointVerbatim() throws {
        let store = makeStore()
        let writes = (0...2).map { checkpoint($0) }
        for item in writes { try store.record(item) }

        let recovery = store.recover(sessionID: "s-1", requestedStep: 2)
        XCTAssertEqual(recovery.checkpoint, writes[2], "字段要逐项一致（含时刻）")
        XCTAssertEqual(recovery.skippedSteps, 0)
        XCTAssertEqual(recovery.skippedLines, 0)
        XCTAssertEqual(try readLines().count, 3)
    }

    // MARK: - 判据 2：坏行 ⇒ 跳过并计数，仍能读回最后一个可用点

    func testBadLinesAreSkippedAndCounted() throws {
        let store = makeStore()
        for step in 0...2 { try store.record(checkpoint(step)) }

        var lines = try readLines()
        lines.insert("{\"sessionID\": \"s-1\", \"stepIndex\":", at: 1)   // 截断行
        lines.insert("这不是 JSON", at: 3)                               // 完全不是 JSON
        try rewriteLines(lines)

        let recovery = store.recover(sessionID: "s-1", requestedStep: 2)
        XCTAssertEqual(recovery.checkpoint?.stepIndex, 2, "坏行不该让整份存储不可用")
        XCTAssertEqual(recovery.skippedLines, 2, "跳过了几行要如实报")
        XCTAssertEqual(recovery.skippedSteps, 0)
    }

    // MARK: - 判据 3：丢了最后一条 ⇒ 落到上一可用点并「如实报数」（不静默从头）

    func testMissingLastRecordFallsBackAndReportsHowManyStepsWereLost() throws {
        let store = makeStore()
        for step in 0...2 { try store.record(checkpoint(step)) }

        var lines = try readLines()
        lines.removeLast()          // 最后一条丢了
        try rewriteLines(lines)

        let recovery = store.recover(sessionID: "s-1", requestedStep: 2)
        XCTAssertEqual(recovery.checkpoint?.stepIndex, 1, "要落到上一可用点")
        XCTAssertEqual(recovery.skippedSteps, 1, "回退了几跳要如实报（不是 0、也不是从头）")
        XCTAssertEqual(recovery.skippedLines, 0)

        // 负例的方向：整份存储都没了 ⇒ 如实报「等于从头」的跳数，而不是假装有检查点
        try FileManager.default.removeItem(at: store.fileURL)
        let empty = store.recover(sessionID: "s-1", requestedStep: 2)
        XCTAssertNil(empty.checkpoint)
        XCTAssertEqual(empty.skippedSteps, 2, "一个可用点都没有 ⇒ 回退跳数 = 请求的那一跳")
    }

    // MARK: - 判据 4：键白名单（结构上没有行数据与密钥的落点）

    func testKeySetIsExactlyTheDeclaredWhitelist() throws {
        let data = try AgentCheckpointStore.encoder.encode(checkpoint(7))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys = Set((object ?? [:]).keys)

        XCTAssertEqual(keys, AgentCheckpoint.keyWhitelist, "键集合必须**恰等于**白名单")
        for forbidden in ["rows", "data", "apiKey", "token", "result"] {
            XCTAssertFalse(keys.contains(forbidden), "不该出现 `\(forbidden)` 这类字段")
        }
    }

    // MARK: - 回归：**分数秒**也要精确往返（`.iso8601` / `.secondsSince1970` 都丢低位 —— 本族判据抓过两次）

    func testFractionalTimestampsRoundTripExactly() throws {
        let store = makeStore()
        let fractional = AgentCheckpoint(sessionID: "s-f", stepIndex: 1, at: Date())
        try store.record(fractional)
        XCTAssertEqual(store.recover(sessionID: "s-f", requestedStep: 1).checkpoint, fractional,
                       "盘上存储要精确往返，不许悄悄截断到秒")
    }

    // MARK: - 附带取证：按会话隔离（别的会话的记录不许被当成自己的）

    func testRecordsAreScopedBySession() throws {
        let store = makeStore()
        try store.record(checkpoint(0, session: "s-1"))
        try store.record(checkpoint(1, session: "s-2"))
        try store.record(checkpoint(2, session: "s-1"))

        XCTAssertEqual(store.recover(sessionID: "s-1", requestedStep: 2).checkpoint?.stepIndex, 2)
        XCTAssertEqual(store.recover(sessionID: "s-2", requestedStep: 1).checkpoint?.stepIndex, 1)
        XCTAssertNil(store.recover(sessionID: "s-3", requestedStep: 0).checkpoint)
    }
}
