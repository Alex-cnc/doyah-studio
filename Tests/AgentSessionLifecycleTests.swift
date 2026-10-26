import XCTest
@testable import DoyahCore

/// `FR-AGT-UX-SESS-001`（会话生命周期：新建 / 归档 / 恢复 / 删除 / 导出 / 重新导入）的机械判据。
///
/// 三条验收要点逐条落：① 归档可恢复；② 删除后磁盘上不再有该会话数据；③ 导出文件可被重新导入。
/// 每条都带负例（别人的工作区拒动、同名拒收、形状不对不落半个文件）。
final class AgentSessionLifecycleTests: XCTestCase {

    private var directory: URL!
    private var sidecarDirectory: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-session-lifecycle-\(UUID().uuidString)", isDirectory: true)
        directory = base.appendingPathComponent("sessions", isDirectory: true)
        sidecarDirectory = base.appendingPathComponent("resume", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sidecarDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    private func makeStore() -> AgentSessionStore { AgentSessionStore(directory: directory) }

    private func turn(_ session: String, _ workspace: String, _ kind: AgentSessionTurn.Kind,
                      _ role: String, _ text: String, seconds: Double,
                      tool: String? = nil, approval: String? = nil) -> AgentSessionTurn {
        AgentSessionTurn(sessionID: session, workspace: workspace, kind: kind, role: role, text: text,
                         toolName: tool, toolCallID: tool == nil ? nil : "call-\(tool!)",
                         approval: approval, at: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    /// 造一条三跳的会话（模型 / 工具 / 审批各一跳）。
    private func seed(_ store: AgentSessionStore, id: String, workspace: String, title: String = "会话") throws {
        try store.createSession(workspace: workspace, title: title, sessionID: id)
        try store.append(turn(id, workspace, .model, "user", "看下 users 表", seconds: 10))
        try store.append(turn(id, workspace, .tool, "tool", "list_dir 返回 3 项", seconds: 20, tool: "list_dir"))
        try store.append(turn(id, workspace, .approval, "tool", "要不要执行", seconds: 30, approval: "approved"))
    }

    // MARK: - ① 归档可恢复

    func testArchiveMovesSessionOutOfActiveListAndRestoreBringsItBack() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")

        XCTAssertTrue(try store.archive(sessionID: "s-1", workspace: "ws-1"))
        // 活跃列表看不到它（归档 = 挪走，不是打标记）
        XCTAssertEqual(store.sessions(workspace: "ws-1").headers.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(sessionID: "s-1").path))
        // 归档面看得到
        let archived = store.archivedSessions(workspace: "ws-1")
        XCTAssertEqual(archived.headers.map(\.id), ["s-1"])
        XCTAssertEqual(archived.skippedFiles, 0)

        XCTAssertTrue(try store.restore(sessionID: "s-1", workspace: "ws-1"))
        // 恢复后内容一条不少、顺序不变
        let reloaded = makeStore().load(sessionID: "s-1", workspace: "ws-1")
        XCTAssertEqual(reloaded.skippedLines, 0)
        XCTAssertEqual(reloaded.session?.turns.count, 3)
        XCTAssertEqual(reloaded.session?.turns.map(\.kind), [.model, .tool, .approval])
        XCTAssertEqual(reloaded.session?.turns.last?.approval, "approved")
        XCTAssertEqual(store.sessions(workspace: "ws-1").headers.map(\.id), ["s-1"])
    }

    func testArchiveIsIdempotentAndRestoreOnActiveSessionIsNoOp() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")

        // 活跃态上恢复 = 本来就在，回 false（不当成错误）
        XCTAssertFalse(try store.restore(sessionID: "s-1", workspace: "ws-1"))
        XCTAssertTrue(try store.archive(sessionID: "s-1", workspace: "ws-1"))
        // 再归档一次 = 已在归档态，回 false（重复点不该报错、也不该删掉归档那份）
        XCTAssertFalse(try store.archive(sessionID: "s-1", workspace: "ws-1"))
        XCTAssertEqual(store.archivedSessions(workspace: "ws-1").headers.count, 1)
    }

    func testArchiveAndRestoreRefuseForeignWorkspaceAndMissingSession() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")

        XCTAssertThrowsError(try store.archive(sessionID: "s-1", workspace: "ws-2")) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "workspaceMismatch")
        }
        XCTAssertThrowsError(try store.archive(sessionID: "nope", workspace: "ws-1")) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "sessionNotFound")
        }
        XCTAssertThrowsError(try store.restore(sessionID: "nope", workspace: "ws-1")) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "sessionNotFound")
        }
        // 拒过之后原文件还在（拒动不是删掉）
        XCTAssertEqual(store.sessions(workspace: "ws-1").headers.count, 1)
    }

    func testRestoreRefusesWhenActiveCopyAlreadyExists() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")
        // 手工做一份归档副本（同一会话号在两个面都在 = 不该静默覆盖）
        try FileManager.default.createDirectory(at: store.archiveDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: store.fileURL(sessionID: "s-1"),
                                         to: store.archivedFileURL(sessionID: "s-1"))

        XCTAssertThrowsError(try store.restore(sessionID: "s-1", workspace: "ws-1")) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "conflictingSessionExists:s-1")
        }
        // 活跃那份没被动过
        XCTAssertEqual(store.load(sessionID: "s-1", workspace: "ws-1").session?.turns.count, 3)
    }

    // MARK: - ② 删除即真删

    func testDeleteRemovesActiveFileArchivedCopyAndResumeSidecar() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")
        try store.archive(sessionID: "s-1", workspace: "ws-1")
        try store.restore(sessionID: "s-1", workspace: "ws-1")
        try store.archive(sessionID: "s-1", workspace: "ws-1")     // 归档面留一份
        // 再来一条活跃副本 + 续跑旁挂件
        try seed(store, id: "s-2", workspace: "ws-1")
        let resumeStore = AgentTurnResumeStore(directory: sidecarDirectory)
        try resumeStore.save(AgentTurnResumeHint(sessionID: "s-2", workspace: "ws-1", prompt: "继续",
                                                record: AgentTurnRecord(turn: 1, lastStep: 2, unfinished: true)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resumeStore.url(for: "s-2").path))

        let removed = try store.delete(sessionID: "s-2", workspace: "ws-1",
                                       sidecarDirectories: [sidecarDirectory])
        XCTAssertEqual(removed, 2, "活跃文件 + 续跑旁挂件一起删")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(sessionID: "s-2").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: resumeStore.url(for: "s-2").path))
        XCTAssertEqual(store.sessions(workspace: "ws-1").headers.count, 0)
        // 旁挂件读回来必须是 absent（不是 unusable、更不是 found）
        XCTAssertEqual(resumeStore.load(sessionID: "s-2", workspace: "ws-1"), .absent)

        // 归档面那份也要能删掉
        let archivedRemoved = try store.delete(sessionID: "s-1", workspace: "ws-1",
                                               sidecarDirectories: [sidecarDirectory])
        XCTAssertEqual(archivedRemoved, 1)
        XCTAssertEqual(store.archivedSessions(workspace: "ws-1").headers.count, 0)
    }

    func testDeleteRefusesForeignWorkspaceAndMissingSession() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")

        XCTAssertThrowsError(try store.delete(sessionID: "s-1", workspace: "ws-2")) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "workspaceMismatch")
        }
        XCTAssertThrowsError(try store.delete(sessionID: "nope", workspace: "ws-1")) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "sessionNotFound")
        }
        // 拒删之后数据必须还在（最危险的一种「以为删掉了」）
        XCTAssertEqual(store.load(sessionID: "s-1", workspace: "ws-1").session?.turns.count, 3)
    }

    // MARK: - ③ 导出可重新导入

    private func exportedData(_ store: AgentSessionStore, id: String, workspace: String) throws -> Data {
        let loaded = store.load(sessionID: id, workspace: workspace)
        let session = try XCTUnwrap(loaded.session)
        return try store.export(session)
    }

    func testExportThenImportIntoSameWorkspaceRoundTripsTurns() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")
        let data = try exportedData(store, id: "s-1", workspace: "ws-1")

        // 先删掉，再从导出数据装回来（「带得走」的正例）
        _ = try store.delete(sessionID: "s-1", workspace: "ws-1")
        let header = try store.importSession(from: data, workspace: "ws-1")
        XCTAssertEqual(header.id, "s-1")
        XCTAssertEqual(header.title, "会话")

        let reloaded = store.load(sessionID: "s-1", workspace: "ws-1")
        XCTAssertEqual(reloaded.skippedLines, 0)
        XCTAssertEqual(reloaded.session?.turns.count, 3)
        XCTAssertEqual(reloaded.session?.turns.map(\.kind), [.model, .tool, .approval])
        XCTAssertEqual(reloaded.session?.turns.first?.text, "看下 users 表")
        XCTAssertEqual(reloaded.session?.turns.last?.approval, "approved")
        // 时刻也对得上（导出走 ISO8601，秒级往返）
        XCTAssertEqual(reloaded.session?.turns.last?.at.timeIntervalSince1970, 1_700_000_030)
    }

    func testImportCanLandInAnotherWorkspace() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")
        let data = try exportedData(store, id: "s-1", workspace: "ws-1")

        let header = try store.importSession(from: data, workspace: "ws-9", sessionID: "carried")
        XCTAssertEqual(header.workspace, "ws-9")
        XCTAssertEqual(header.id, "carried")
        // 原工作区那份不受影响；新工作区看得到这条
        XCTAssertEqual(store.sessions(workspace: "ws-1").headers.map(\.id), ["s-1"])
        XCTAssertEqual(store.sessions(workspace: "ws-9").headers.map(\.id), ["carried"])
        XCTAssertEqual(store.load(sessionID: "carried", workspace: "ws-9").session?.turns.count, 3)
        // 跨工作区读别人的会话仍然看不到（导入不改变隔离口径）
        XCTAssertNil(store.load(sessionID: "carried", workspace: "ws-1").session)
    }

    func testImportRejectsDuplicateIDByDefaultAndCanAssignNewID() throws {
        let store = makeStore()
        try seed(store, id: "s-1", workspace: "ws-1")
        let data = try exportedData(store, id: "s-1", workspace: "ws-1")

        // 默认拒收：不静默覆盖已有会话
        XCTAssertThrowsError(try store.importSession(from: data, workspace: "ws-1")) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "conflictingSessionExists:s-1")
        }
        XCTAssertEqual(store.load(sessionID: "s-1", workspace: "ws-1").session?.turns.count, 3)

        // 显式选换号：两条并存，旧的不动
        let fresh = try store.importSession(from: data, workspace: "ws-1", conflict: .assignNewID)
        XCTAssertNotEqual(fresh.id, "s-1")
        XCTAssertEqual(store.sessions(workspace: "ws-1").headers.count, 2)
        XCTAssertEqual(store.load(sessionID: fresh.id, workspace: "ws-1").session?.turns.count, 3)
        XCTAssertEqual(store.load(sessionID: "s-1", workspace: "ws-1").session?.turns.count, 3)
    }

    func testImportMalformedPayloadWritesNothing() throws {
        let store = makeStore()
        // 非 JSON
        XCTAssertThrowsError(try store.importSession(from: Data("not json".utf8), workspace: "ws-1")) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "malformedPayload:notJSONObject")
        }
        // 缺 turns
        let noTurns = Data(#"{"id":"x","title":"t"}"#.utf8)
        XCTAssertThrowsError(try store.importSession(from: noTurns, workspace: "ws-1")) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "malformedPayload:noTurns")
        }
        // 坏跳（kind 不认识）
        let badTurn = Data(#"{"id":"x","title":"t","turns":[{"kind":"nope","role":"user","text":"a"}]}"#.utf8)
        XCTAssertThrowsError(try store.importSession(from: badTurn, workspace: "ws-1")) { error in
            XCTAssertEqual((error as? AgentSessionLifecycleError)?.code, "malformedPayload:badTurn")
        }
        // 三次都失败之后磁盘上不许留下半个文件
        XCTAssertEqual(store.sessions(workspace: "ws-1").headers.count, 0)
        XCTAssertNil(store.load(sessionID: "x", workspace: "ws-1").session)
    }
}
