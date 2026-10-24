import XCTest
@testable import DoyahCore

/// 详设 `T-4.4-08`：未保存关闭经确认后 **进快照**（不是直接丢内容）。
final class UnsavedCloseTests: XCTestCase {

    func testConfirmCapturesSnapshotWithContent() {
        let id = UUID()
        var store = ClosedTabSnapshotStore()
        let snapshot = ClosedTabSnapshot(id: id, title: "未命名 3", sql: "UPDATE orders SET total = 0 WHERE id = 3;")

        store.push(snapshot)

        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.latest?.id, id)
        XCTAssertEqual(store.latest?.sql, snapshot.sql, "确认关闭后 SQL 必须留在快照里，不许丢")
        XCTAssertEqual(store.latest?.title, "未命名 3")
    }

    func testStoreIsBoundedAndDropsOldest() {
        var store = ClosedTabSnapshotStore()
        for index in 0..<(ClosedTabSnapshotStore.capacity + 5) {
            store.push(ClosedTabSnapshot(id: UUID(), title: "t\(index)", sql: "SELECT \(index);"))
        }
        XCTAssertEqual(store.snapshots.count, ClosedTabSnapshotStore.capacity, "快照栈必须有界")
        XCTAssertEqual(store.latest?.title, "t\(ClosedTabSnapshotStore.capacity + 4)",
                       "有界策略丢最旧的，保留最新的")
    }

    func testRefusedCloseLeavesNoSnapshot() {
        // 反例：执行中被拒 ⇒ 不产生快照（拒绝不等于关闭）
        let decision = TabClosePolicy.decide(isExecuting: true, isDirty: true, tabCount: 2)
        XCTAssertEqual(decision, .refuseExecuting)

        var store = ClosedTabSnapshotStore()
        if decision == .needsConfirmation || decision == .close {
            store.push(ClosedTabSnapshot(id: UUID(), title: "x", sql: "SELECT 1;"))
        }
        XCTAssertTrue(store.snapshots.isEmpty, "被拒的关闭不得留下快照")
    }
}
