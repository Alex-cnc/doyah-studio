import XCTest
@testable import DoyahCore

/// `FR-AGT-UX-SESS-001` 界面侧的接线判据（`AgentSessionLifecycleDesk`）。
///
/// 与 `AgentSessionLifecycleTests` 的分工：那一份量 Core 三件本体（归档 / 真删 / 导入的语义），
/// 这一份量**界面接线面**——也就是「界面照着这一层接，会不会漏事」：
/// · ① 续跑旁挂件目录**钉在构造处**：界面不可能忘传（真删时一个文件都不许剩）；
/// · ② 归档面也能出**跳数与最近活动**（列表要跟活跃面同一套字段，否则并排看两套口径）；
/// · ③ 导出只产出数据、导入落到固定工作区 —— 界面不参与拼路径；
/// · ④ 别人的会话拒动、同名拒收、坏载荷不落半个文件（该拒路径）。
final class AgentSessionLifecycleDeskTests: XCTestCase {

    private var base: URL!
    private var sessionDirectory: URL!
    private var sidecarDirectory: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-session-desk-\(UUID().uuidString)", isDirectory: true)
        sessionDirectory = base.appendingPathComponent("sessions", isDirectory: true)
        sidecarDirectory = base.appendingPathComponent("resume", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sidecarDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: - 夹具

    private func makeStore() -> AgentSessionStore { AgentSessionStore(directory: sessionDirectory) }

    private func desk(_ store: AgentSessionStore, workspace: String = "ws-1") -> AgentSessionLifecycleDesk {
        AgentSessionLifecycleDesk(store: store, workspace: workspace, sidecarDirectories: [sidecarDirectory])
    }

    private func turn(_ session: String, _ workspace: String, _ kind: AgentSessionTurn.Kind,
                      _ text: String, seconds: Double, tool: String? = nil) -> AgentSessionTurn {
        AgentSessionTurn(sessionID: session, workspace: workspace, kind: kind, role: "user", text: text,
                         toolName: tool, toolCallID: tool.map { "call-\($0)" }, approval: nil,
                         at: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    /// 一条两跳会话 + 一份续跑旁挂件（**旁挂件是「删干净」这条判据的关键夹具**）。
    private func seed(_ store: AgentSessionStore, id: String, workspace: String, title: String = "会话") throws {
        try store.createSession(workspace: workspace, title: title, sessionID: id)
        try store.append(turn(id, workspace, .model, "看下 users 表", seconds: 10))
        try store.append(turn(id, workspace, .tool, "list_dir 返回 3 项", seconds: 20, tool: "list_dir"))
        let resume = AgentTurnResumeStore(directory: sidecarDirectory)
        try resume.save(AgentTurnResumeHint(sessionID: id, workspace: workspace, prompt: "继续",
                                            record: AgentTurnRecord(turn: 1, lastStep: 2, unfinished: true)))
    }

    // MARK: - ① 旁挂件目录钉在构造处

    func testDeleteThroughDeskRemovesSessionAndResumeSidecarWithoutCallerPassingIt() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")

        let outcome = try desk(store).delete(sessionID: "s-1")

        XCTAssertEqual(outcome.action, .delete)
        XCTAssertEqual(outcome.sessionID, "s-1")
        XCTAssertTrue(outcome.changed)
        // 活跃文件 + 续跑旁挂件 = 2（**界面这一侧没有再传任何目录**）
        XCTAssertEqual(outcome.removedFileCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(sessionID: "s-1").path))
        XCTAssertEqual(AgentTurnResumeStore(directory: sidecarDirectory).load(sessionID: "s-1", workspace: "ws-1"),
                       .absent)
        XCTAssertEqual(store.sessions(workspace: "ws-1").headers.count, 0)
    }

    // MARK: - ② 归档 / 恢复往返 + 归档面的摘要字段

    func testArchiveThenRestoreRoundTripsAndArchivedSummaryCarriesTurnCount() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")
        let desk = desk(store)

        let archived = try desk.archive(sessionID: "s-1")
        XCTAssertTrue(archived.changed)
        XCTAssertTrue(desk.archivedSummaries().summaries.map(\.id) == ["s-1"])
        XCTAssertTrue(store.sessions(workspace: "ws-1").headers.isEmpty)

        // 归档面也要给跳数与最近活动时刻 —— 否则列表里那一格只能写「—」。
        let summary = try XCTUnwrap(desk.archivedSummaries().summaries.first)
        XCTAssertEqual(summary.turnCount, 2)
        XCTAssertEqual(summary.title, "会话")
        XCTAssertNotNil(summary.lastTurnAt)

        let restored = try desk.restore(sessionID: "s-1")
        XCTAssertTrue(restored.changed)
        XCTAssertTrue(desk.archivedSummaries().summaries.isEmpty)
        XCTAssertEqual(store.load(sessionID: "s-1", workspace: "ws-1").session?.turns.count, 2)
    }

    // MARK: - ③ 导出 → 导入（含换工作区）

    func testExportThroughDeskProducesDataThatImportsBack() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")

        let exported = try desk(store).export(sessionID: "s-1")
        XCTAssertEqual(exported.outcome.action, .export)
        XCTAssertGreaterThan(exported.outcome.byteCount, 0)
        XCTAssertEqual(exported.outcome.byteCount, exported.data.count)
        XCTAssertFalse(exported.outcome.changed, "导出不改盘上任何东西")

        // 删掉原会话再导回来 —— 真删之后「导出可带走」才算数。
        _ = try desk(store).delete(sessionID: "s-1")
        let receipt = try desk(store).importSession(exported.data)
        XCTAssertEqual(receipt.header.id, "s-1")
        XCTAssertEqual(receipt.outcome.action, .importSession)
        XCTAssertEqual(store.load(sessionID: "s-1", workspace: "ws-1").session?.turns.count, 2)
    }

    func testImportCanLandInAnotherWorkspaceWhenNewIDIsChosen() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")
        let exported = try desk(store, workspace: "ws-1").export(sessionID: "s-1")

        // 同一个存储目录里**会话号是唯一键**（文件名就是会话号）⇒ 拿原号往别的工作区落会撞同名；
        // 界面对「带走的导出文件」应选换新号（这一步由界面按钮决定，本层只如实执行）。
        let receipt = try desk(store, workspace: "ws-2").importSession(exported.data, conflict: .assignNewID)
        XCTAssertNotEqual(receipt.header.id, "s-1")
        XCTAssertEqual(receipt.header.workspace, "ws-2")
        XCTAssertEqual(store.load(sessionID: receipt.header.id, workspace: "ws-2").session?.turns.count, 2)
        // 原工作区那条不受影响（导入是新增，不是搬移）
        XCTAssertEqual(store.sessions(workspace: "ws-1").headers.map(\.id), ["s-1"])
        XCTAssertEqual(store.load(sessionID: "s-1", workspace: "ws-1").session?.turns.count, 2)
    }

    // MARK: - ④ 该拒的三种

    func testDeskRefusesForeignWorkspaceForEveryAction() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")
        let foreign = desk(store, workspace: "ws-2")

        for operation in ["archive", "restore", "export", "delete"] {
            XCTAssertThrowsError(try {
                switch operation {
                case "archive": _ = try foreign.archive(sessionID: "s-1")
                case "restore": _ = try foreign.restore(sessionID: "s-1")
                case "export": _ = try foreign.export(sessionID: "s-1")
                default: _ = try foreign.delete(sessionID: "s-1")
                }
            }(), "\(operation) 必须拒动别人的工作区") { error in
                XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "workspaceMismatch")
            }
        }
        // 拒得干净：那条会话与它的旁挂件都还在
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(sessionID: "s-1").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sidecarDirectory.appendingPathComponent(AgentTurnResumeStore.sidecarFileName(sessionID: "s-1")).path))
    }

    func testImportRejectsDuplicateSessionIDByDefault() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")
        let data = try desk(store).export(sessionID: "s-1").data

        XCTAssertThrowsError(try desk(store).importSession(data)) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "conflictingSessionExists:s-1")
        }
        // 默认拒收不许改动已有那份（跳数还是 2，没被导进来的覆写）
        XCTAssertEqual(store.load(sessionID: "s-1", workspace: "ws-1").session?.turns.count, 2)

        // 显式选「换新号」才落第二条
        let receipt = try desk(store).importSession(data, conflict: .assignNewID)
        XCTAssertNotEqual(receipt.header.id, "s-1")
        XCTAssertEqual(store.sessions(workspace: "ws-1").headers.count, 2)
    }

    func testImportMalformedPayloadLeavesNothingOnDisk() throws {
        let store = makeStore()
        let before = try FileManager.default.contentsOfDirectory(atPath: sessionDirectory.path).sorted()

        XCTAssertThrowsError(try desk(store).importSession(Data("{\"title\":\"x\"}".utf8))) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "malformedPayload:noTurns")
        }
        let after = try FileManager.default.contentsOfDirectory(atPath: sessionDirectory.path).sorted()
        XCTAssertEqual(before, after, "形状不对不许落半个文件")
    }

    // MARK: - 边界：幂等动作 `changed=false`

    func testIdempotentActionsReportUnchanged() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")
        let desk = desk(store)

        // 归档两次：第二次没动盘
        XCTAssertTrue(try desk.archive(sessionID: "s-1").changed)
        XCTAssertFalse(try desk.archive(sessionID: "s-1").changed)
        // 恢复两次：第二次没动盘
        XCTAssertTrue(try desk.restore(sessionID: "s-1").changed)
        XCTAssertFalse(try desk.restore(sessionID: "s-1").changed)
        // 一次都没归档过的东西恢复 ⇒ 不是「没关系」，是查不到
        XCTAssertThrowsError(try desk.restore(sessionID: "s-404")) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "sessionNotFound")
        }
    }
}
