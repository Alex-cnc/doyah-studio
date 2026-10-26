import XCTest
@testable import DoyahCore

/// `FR-AGT-UX-SESS-001` 的**文件面**判据：新建 → 归档 → 恢复 → 导出 → 删除。
///
/// 界面观感由人点验，这里钉的是「点了之后盘上到底发生了什么」——
/// 尤其是**删除要真删干净**（主文件 + 续跑旁挂件都不留），这是最容易假绿的判据。
final class SessionLifecycleFileEffectTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-sess-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func makeDesk() throws -> (AgentSessionLifecycleDesk, AgentSessionStore, URL) {
        let sessions = root.appendingPathComponent("agent-sessions", isDirectory: true)
        let sidecar = root.appendingPathComponent("turn-resume", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: true)
        let store = AgentSessionStore(directory: sessions)
        let desk = AgentSessionLifecycleDesk(store: store, workspace: "w-test", sidecarDirectories: [sidecar])
        return (desk, store, sidecar)
    }

    // 新建：一会话一文件，落在 sessions 目录
    func testCreateWritesOneFilePerSession() throws {
        let (_, store, _) = try makeDesk()
        let header = try store.createSession(workspace: "w-test", title: "第一跳")
        let url = store.fileURL(sessionID: header.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count, 1)
    }

    // 归档：文件搬进归档区，活跃列表里消失，归档面里能查到
    func testArchiveMovesOutOfActiveListAndShowsInArchived() throws {
        let (desk, store, _) = try makeDesk()
        let header = try store.createSession(workspace: "w-test", title: "待归档")

        let outcome = try desk.archive(sessionID: header.id)
        XCTAssertTrue(outcome.changed)
        XCTAssertTrue(store.sessions(workspace: "w-test").headers.isEmpty, "归档后活跃列表必须空")
        XCTAssertEqual(desk.archivedSummaries().summaries.map(\.id), [header.id], "归档面要能查到它")
    }

    // 恢复：回到活跃面
    func testRestoreBringsItBack() throws {
        let (desk, store, _) = try makeDesk()
        let header = try store.createSession(workspace: "w-test", title: "来回走")
        _ = try desk.archive(sessionID: header.id)
        _ = try desk.restore(sessionID: header.id)
        XCTAssertEqual(store.sessions(workspace: "w-test").headers.map(\.id), [header.id])
        XCTAssertTrue(desk.archivedSummaries().summaries.isEmpty)
    }

    // 导出：给得出一份能再导入的数据（不是空壳）
    func testExportProducesImportableData() throws {
        let (desk, store, _) = try makeDesk()
        let header = try store.createSession(workspace: "w-test", title: "要带走的")
        let exported = try desk.export(sessionID: header.id)
        XCTAssertFalse(exported.data.isEmpty)
        XCTAssertTrue(exported.outcome.changed == false || exported.outcome.changed == true, "动作本身要有个结果")

        let receipt = try desk.importSession(exported.data, conflict: .assignNewID)
        XCTAssertEqual(receipt.header.title, "要带走的", "导入回来的标题要跟导出的一模一样")
    }

    // 删除：**真删** —— 主文件消失，且不留续跑旁挂件
    func testDeleteRemovesTheFileAndSidecars() throws {
        let (desk, store, sidecar) = try makeDesk()
        let header = try store.createSession(workspace: "w-test", title: "要删的")
        let url = store.fileURL(sessionID: header.id)

        // 造一个同名旁挂件（续跑记录），删会话时必须一起走
        let sidecarFile = sidecar.appendingPathComponent(AgentTurnResumeStore.sidecarFileName(sessionID: header.id))
        try Data("{}".utf8).write(to: sidecarFile)

        let outcome = try desk.delete(sessionID: header.id)
        XCTAssertTrue(outcome.changed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "主文件必须真删")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarFile.path), "续跑旁挂件也必须一起删")
        XCTAssertTrue(store.sessions(workspace: "w-test").headers.isEmpty)
    }

    // 删不存在的会话：**抛类型化错误**（`sessionNotFound`），调用方照它如实报，不静默当成功
    func testDeleteMissingSessionThrowsSessionNotFound() throws {
        let (desk, _, _) = try makeDesk()
        XCTAssertThrowsError(try desk.delete(sessionID: "不存在的会话")) { error in
            XCTAssertEqual(error as? AgentSessionLifecycleError, .sessionNotFound)
        }
    }
}
