import XCTest
@testable import DoyahCore

/// `FR-AGT-LINK-CHAN-003` 的契约面判据（①同一会话 ②审批不放宽 ③未读不丢）。
///
/// 传输层（QQ 网关）不在这里判 —— 那要真 AppID/Secret 才能跑；这里钉的是**无论传输怎么接、
/// 这三条都得成立**的部分。
final class AgentIMChannelTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-im-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func makeBridge() -> AgentIMTaskBridge {
        AgentIMTaskBridge(sessionMap: AgentIMSessionMap(directory: root))
    }

    // ① 同一 chat 的两条消息 ⇒ 同一条会话（桌面上看到的是同一条）
    func testSameChatMapsToSameSession() throws {
        let bridge = makeBridge()
        let first = try bridge.task(from: .init(platformMessageID: "m1", chatID: "chat-A", senderID: "u1", text: "跑一下统计"))
        let second = try bridge.task(from: .init(platformMessageID: "m2", chatID: "chat-A", senderID: "u1", text: "再跑一次"))
        XCTAssertEqual(first.sessionID, second.sessionID)

        // 另一个 chat 不许串号
        let other = try bridge.task(from: .init(platformMessageID: "m3", chatID: "chat-B", senderID: "u2", text: "你好"))
        XCTAssertNotEqual(other.sessionID, first.sessionID)
    }

    // ① 映射落盘：换一个进程（重新构造）仍指同一条
    func testMappingSurvivesReload() throws {
        let bridge = makeBridge()
        let first = try bridge.task(from: .init(platformMessageID: "m1", chatID: "chat-A", senderID: "u1", text: "第一次"))
        let reloaded = AgentIMTaskBridge(sessionMap: AgentIMSessionMap(directory: root))
        let again = try reloaded.task(from: .init(platformMessageID: "m9", chatID: "chat-A", senderID: "u1", text: "重启后"))
        XCTAssertEqual(again.sessionID, first.sessionID)
    }

    // ② 任务类型不带免审旗：入口恒定要求走桌面同一套审批
    func testTaskAlwaysRequiresDesktopApproval() throws {
        let task = try makeBridge().task(from: .init(platformMessageID: "m1", chatID: "chat-A", senderID: "u1",
                                                     text: "drop table users"))
        XCTAssertTrue(task.alwaysRequiresDesktopApproval, "IM 来的任务一律仍走桌面审批；放宽只能改类型，改类型会被看见")
    }

    // ③ 未读：入队后、没 ack 之前，重连（重新读盘）仍在待投递里
    func testPendingSurvivesRestartUntilAcked() throws {
        let queue = AgentIMResultQueue(directory: root)
        let entry = try queue.enqueue(chatID: "chat-A", text: "任务结论：完成")
        XCTAssertEqual(AgentIMResultQueue(directory: root).pending().map(\.id), [entry.id])

        try queue.ack(id: entry.id)
        XCTAssertTrue(AgentIMResultQueue(directory: root).pending().isEmpty, "ack 过的不该再补发")
        XCTAssertEqual(AgentIMResultQueue(directory: root).all().count, 1, "留痕不删（只是不再补发）")
    }

    // ③ ack 幂等：重复 ack 不炸、不重复改
    func testAckIsIdempotent() throws {
        let queue = AgentIMResultQueue(directory: root)
        let entry = try queue.enqueue(chatID: "chat-A", text: "结论")
        try queue.ack(id: entry.id)
        XCTAssertNoThrow(try queue.ack(id: entry.id))
        XCTAssertNoThrow(try queue.ack(id: "不存在的"))
        XCTAssertTrue(queue.pending().isEmpty)
    }
}
