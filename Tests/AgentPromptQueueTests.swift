import XCTest
@testable import DoyahCore

/// 提问队列（`/queue` 的同义物）。
///
/// 为什么值得钉：这一条的价值全在「**一轮跑着的时候提交的东西不丢**」。
/// 队列错了不会崩，只会**悄悄少问一句** —— 那是最难被发现的错。
final class AgentPromptQueueTests: XCTestCase {

    func testFIFOOrderIsPreserved() {
        var queue = AgentPromptQueue()
        queue.enqueue("一")
        queue.enqueue("二")
        queue.enqueue("三")
        XCTAssertEqual(queue.dequeue()?.text, "一")
        XCTAssertEqual(queue.dequeue()?.text, "二")
        XCTAssertEqual(queue.dequeue()?.text, "三")
        XCTAssertNil(queue.dequeue())
    }

    func testBlankPromptIsNotQueued() {
        var queue = AgentPromptQueue()
        XCTAssertNil(queue.enqueue("   \n "))
        XCTAssertTrue(queue.isEmpty)
        // 前后空白被剪掉再入队（否则会以空行开头跑一轮）
        queue.enqueue("  有内容  ")
        XCTAssertEqual(queue.items.first?.text, "有内容")
    }

    func testRemoveByOneBasedIndex() {
        var queue = AgentPromptQueue()
        queue.enqueue("一"); queue.enqueue("二"); queue.enqueue("三")
        queue.remove(at: 2)
        XCTAssertEqual(queue.items.map(\.text), ["一", "三"])
        queue.remove(at: 0)          // 越界：静默不动
        queue.remove(at: 9)
        XCTAssertEqual(queue.count, 2)
    }

    func testRemoveByIDAndEdit() {
        var queue = AgentPromptQueue()
        let first = queue.enqueue("原话")!
        queue.enqueue("另一条")
        queue.edit(id: first.id, text: "  改过  ")
        XCTAssertEqual(queue.items.first?.text, "改过")
        queue.edit(id: first.id, text: "   ")        // 改成空白：拒绝，保持原样
        XCTAssertEqual(queue.items.first?.text, "改过")
        queue.remove(id: first.id)
        XCTAssertEqual(queue.items.map(\.text), ["另一条"])
    }

    func testMoveReordersAndIgnoresOutOfRange() {
        var queue = AgentPromptQueue()
        queue.enqueue("一"); queue.enqueue("二"); queue.enqueue("三")
        queue.move(from: 3, to: 1)
        XCTAssertEqual(queue.items.map(\.text), ["三", "一", "二"])
        queue.move(from: 1, to: 9)                   // 越界：不变
        queue.move(from: 2, to: 2)                   // 原地：不变
        XCTAssertEqual(queue.items.map(\.text), ["三", "一", "二"])
    }

    /// 预览：多行折成一行、超长截断（否则列表里一行会被撑成好几行）。
    func testPreviewCollapsesNewlinesAndTruncates() {
        XCTAssertEqual(AgentPromptQueue.preview("第一行\n第二行"), "第一行 第二行")
        XCTAssertEqual(AgentPromptQueue.preview("a\tb"), "a b")
        let long = String(repeating: "字", count: 100)
        let preview = AgentPromptQueue.preview(long, limit: 10)
        XCTAssertEqual(preview.count, 11, "10 个字 + 一个省略号")
        XCTAssertTrue(preview.hasSuffix("…"))
        XCTAssertEqual(AgentPromptQueue.preview("短"), "短")
    }

    func testClearEmptiesQueue() {
        var queue = AgentPromptQueue()
        queue.enqueue("一"); queue.enqueue("二")
        queue.clear()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.dequeue())
    }
}
