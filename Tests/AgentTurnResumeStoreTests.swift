import XCTest
@testable import DoyahCore

// `FR-AGT-CORE-SESS-001` ① 跨启动续跑的机械证据（契约 §5.1 / 详设 §4.6）。
//
// 六条点名判据：
//   ① 写了能读回（四个值逐字一致）· ② 身份不符当没有（会话号 / 工作区）·
//   ③ 坏文件不冒充（返回 unusable，不返回空 hint）· ④ 没跑过 = absent（不是失败）·
//   ⑤ 覆盖写不追加（末次为准）· ⑥ 清掉之后不残留。
//
// 一律真目录真文件（临时目录），纯内存测不出现场。

final class AgentTurnResumeStoreTests: XCTestCase {

    private var directory: URL!
    private var store: AgentTurnResumeStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-resume-\(UUID().uuidString)", isDirectory: true)
        store = AgentTurnResumeStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func hint(session: String = "chat-1", workspace: String = "/w/a",
                      prompt: String = "把 t 表加一列", turn: Int = 3,
                      lastStep: Int = 7, unfinished: Bool = true) -> AgentTurnResumeHint {
        AgentTurnResumeHint(
            sessionID: session, workspace: workspace, prompt: prompt,
            record: AgentTurnRecord(turn: turn, lastStep: lastStep, unfinished: unfinished),
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    /// ① 写了能读回：提问原话 + 轮次 + 跳数 + 未完标记四处逐字一致。
    func testRoundTripKeepsAllFourValues() throws {
        let written = hint()
        try store.save(written)
        guard case let .found(read) = store.load(sessionID: "chat-1", workspace: "/w/a") else {
            return XCTFail("应当读回")
        }
        XCTAssertEqual(read, written)
        XCTAssertEqual(read.turn, 3)
        XCTAssertEqual(read.lastStep, 7)
        XCTAssertTrue(read.unfinished)
        XCTAssertEqual(read.record, AgentTurnRecord(turn: 3, lastStep: 7, unfinished: true))
    }

    /// ② 会话号不符 ⇒ 当没有（不跨会话串味）。
    ///
    /// 现场是「文件被改名 / 被复制成别的会话号」：路径找得到，内容里却写着另一个会话 ——
    /// 这种必须判不可用；**路径本身不存在时是 `absent`**（见 ④），两者不许混。
    func testMismatchedSessionIsUnusable() throws {
        try store.save(hint(session: "chat-1"))
        let copied = store.url(for: "chat-2")
        try FileManager.default.copyItem(at: store.url(for: "chat-1"), to: copied)
        guard case let .unusable(reason) = store.load(sessionID: "chat-2", workspace: "/w/a") else {
            return XCTFail("文件内容里的会话号不符必须判为不可用")
        }
        XCTAssertTrue(reason.contains("会话号"), reason)
    }

    /// ② 补充：会话号换名字但内容对得上时，工作区不符仍要拦（两条校验各自独立）。
    func testSessionMatchesButWorkspaceDiffersStillBlocks() throws {
        try store.save(hint(session: "chat-1", workspace: "/w/a"))
        guard case .unusable = store.load(sessionID: "chat-1", workspace: "/w/other") else {
            return XCTFail("工作区不符必须判不可用")
        }
    }

    /// ② 工作区不符 ⇒ 当没有。
    func testMismatchedWorkspaceIsUnusable() throws {
        try store.save(hint(workspace: "/w/a"))
        guard case let .unusable(reason) = store.load(sessionID: "chat-1", workspace: "/w/b") else {
            return XCTFail("工作区不符必须判为不可用")
        }
        XCTAssertTrue(reason.contains("工作区"), reason)
    }

    /// ③ 坏文件不冒充：写一坨非 JSON，加载返回 unusable 而不是空 hint。
    func testCorruptFileIsUnusableNotSilent() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json at all".utf8).write(to: store.url(for: "chat-1"))
        guard case .unusable = store.load(sessionID: "chat-1", workspace: "/w/a") else {
            return XCTFail("坏文件必须报不可用")
        }
    }

    /// ④ 从没跑过 ⇒ absent（不是失败，也不是 usable）。
    func testAbsentWhenNeverSaved() {
        XCTAssertEqual(store.load(sessionID: "chat-9", workspace: "/w/a"), .absent)
    }

    /// ⑤ 覆盖写不追加：同一会话连写三次，读到的是最后一次。
    func testOverwriteKeepsLastWriteOnly() throws {
        try store.save(hint(prompt: "第一次", lastStep: 1))
        try store.save(hint(prompt: "第二次", lastStep: 4))
        try store.save(hint(prompt: "第三次", lastStep: 9))
        guard case let .found(read) = store.load(sessionID: "chat-1", workspace: "/w/a") else {
            return XCTFail("应当读回")
        }
        XCTAssertEqual(read.prompt, "第三次")
        XCTAssertEqual(read.lastStep, 9)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1, "一会话一文件，不许追加出第二份")
    }

    /// ⑥ 清掉之后不残留（删除会话 / 主动新开时用）。
    func testClearRemovesFile() throws {
        try store.save(hint())
        store.clear(sessionID: "chat-1")
        XCTAssertEqual(store.load(sessionID: "chat-1", workspace: "/w/a"), .absent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: "chat-1").path))
    }

    /// 文件名固定形状：`resume-<会话号>.json`（换实现不许悄悄改约定）。
    func testFileNameShape() {
        XCTAssertEqual(store.url(for: "chat-1").lastPathComponent, "resume-chat-1.json")
    }
}
