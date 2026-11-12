import XCTest
@testable import DoyahCore

/// **文件投递的 IM 自测通道**（`FR-AGT-LINK-CHAN-003`）。
///
/// 动机（主人 2026-11-11：「这个 IM 通道你自己应该可以测试啊」）：
/// IM 那边的问题一直只能靠人在手机上点一轮才暴露 —— 手机试一轮要另一个人、要等，
/// 而且看不见审计。这条通道把「入站」变成往文件里追加一行，
/// 于是跳数 / 拒因 / 心跳 / 拍板都能在终端里复现。
///
/// 判据：① 只吃增量（同一行不许跑第二遍）；② 只吃整行（半行留到下一轮）；
/// ③ 坏帧记数不静默；④ 文件被截断要能自己复位。
final class AgentIMFileInboxTests: XCTestCase {

    private var dir: URL!
    private var file: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("inbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("inbox.jsonl")
        try Data().write(to: file)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func append(_ line: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
    }

    private func messageLine(_ text: String, id: String = UUID().uuidString) -> String {
        #"{"op":"message","platformMessageID":"\#(id)","chatID":"selftest","senderID":"owner","text":"\#(text)"}"# + "\n"
    }

    func testDrainsOnlyNewLines() throws {
        var inbox = AgentIMFileInbox(url: file)
        try append(messageLine("第一句"))
        XCTAssertEqual(inbox.drain().count, 1)
        XCTAssertEqual(inbox.drain().count, 0, "同一行不许跑第二遍")

        try append(messageLine("第二句"))
        let second = inbox.drain()
        XCTAssertEqual(second.count, 1)
        guard case .message(let message) = second[0] else { return XCTFail("应当解出消息帧") }
        XCTAssertEqual(message.text, "第二句")
    }

    func testHalfLineIsLeftForNextRound() throws {
        var inbox = AgentIMFileInbox(url: file)
        // 只写了半行（没有换行）⇒ 这一轮不许消费
        try append(#"{"op":"message","platformMessageID":"x","chatID":"c""#)
        XCTAssertEqual(inbox.drain().count, 0, "半行可能正在被写，不许当成一帧")

        // 补完剩下的
        try append(#","senderID":"o","text":"补完"}"# + "\n")
        let frames = inbox.drain()
        XCTAssertEqual(frames.count, 1)
        guard case .message(let message) = frames[0] else { return XCTFail("应当解出消息帧") }
        XCTAssertEqual(message.text, "补完")
    }

    func testMalformedLineIsCountedNotSwallowed() throws {
        var inbox = AgentIMFileInbox(url: file)
        try append("{这不是 JSON\n")
        XCTAssertEqual(inbox.drain().count, 0)
        XCTAssertEqual(inbox.malformedCount, 1, "坏帧要留痕，不许静默丢掉")
    }

    func testTruncatedFileResetsOffset() throws {
        var inbox = AgentIMFileInbox(url: file)
        try append(messageLine("一"))
        try append(messageLine("二"))
        XCTAssertEqual(inbox.drain().count, 2)

        // 模拟「文件被清空重写」
        try Data().write(to: file)
        try append(messageLine("重写后"))
        let frames = inbox.drain()
        XCTAssertEqual(frames.count, 1, "截断之后要能重新读，不许卡在旧偏移上")
    }
}
