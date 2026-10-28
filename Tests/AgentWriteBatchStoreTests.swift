import XCTest
@testable import DoyahCore

/// 写入批次采集端 + 真磁盘撤回（`FR-STD-WS-EDIT-015` 的端到端面）。
final class AgentWriteBatchStoreTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-write-batch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }
    private func read(_ relative: String) -> String? { try? String(contentsOf: url(relative), encoding: .utf8) }
    private func write(_ relative: String, _ text: String) throws {
        try text.write(to: url(relative), atomically: true, encoding: .utf8)
    }

    /// 真的按计划落盘（与界面将来那个按钮走同一条路）。
    private func apply(_ steps: [AgentRevertStep]) {
        _ = try? AgentWriteBatchRevert.apply(steps) { path, text in
            let target = self.url(path)
            if let text {
                try text.write(to: target, atomically: true, encoding: .utf8)
            } else if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
        }
    }

    func testRecordAndRevertRestoresTheFileOnDisk() throws {
        try write("a.swift", "旧内容")
        let store = AgentWriteBatchStore(runID: "r1")
        store.record(path: "a.swift", previousText: "旧内容", writtenText: "Agent 改的")
        try write("a.swift", "Agent 改的")

        let steps = store.plan { self.read($0) }
        XCTAssertEqual(steps, [.restore(path: "a.swift", text: "旧内容")])
        apply(steps)
        XCTAssertEqual(read("a.swift"), "旧内容")
    }

    func testHumanEditAfterAgentWriteIsLeftAlone() throws {
        try write("a.swift", "旧内容")
        let store = AgentWriteBatchStore(runID: "r1")
        store.record(path: "a.swift", previousText: "旧内容", writtenText: "Agent 改的")
        try write("a.swift", "人又改的")

        let steps = store.plan { self.read($0) }
        XCTAssertEqual(steps, [.conflict(path: "a.swift", reason: .changedSinceWrite)])
        apply(steps)
        XCTAssertEqual(read("a.swift"), "人又改的", "人写的版本必须留着")
    }

    func testCreatedFileIsRemovedOnRevert() throws {
        let store = AgentWriteBatchStore(runID: "r1")
        store.record(path: "new.swift", previousText: nil, writtenText: "新建的")
        try write("new.swift", "新建的")

        apply(store.plan { self.read($0) })
        XCTAssertNil(read("new.swift"), "本来不存在的文件，撤回就是删掉")
    }

    func testNothingRecordedMeansNothingToRevert() {
        let store = AgentWriteBatchStore(runID: "r1")
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(store.plan { _ in nil }.isEmpty, "没写成就不许有撤回项")
    }
}
