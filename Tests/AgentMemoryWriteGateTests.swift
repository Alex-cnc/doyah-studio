import XCTest
@testable import DoyahCore

/// 记忆写入过闸（`FR-AGT-KNOW-MEM-006`）与同键覆盖（`FR-AGT-KNOW-MEM-008`）的机械判据。
///
/// 三条最容易被做松的地方，用例里逐条钉住：
/// 1. **自发写入不落盘**：模型自己觉得该记的，只许转候选 —— 盘上多一行就是错的；
/// 2. **来源可指回**：每条带来源轮次与触发方式，缺了等于「不知道它是怎么进来的」；
/// 3. **新者生效、旧值可查**：覆盖不许把旧值抹掉（否则「为什么改了记忆」永远查不出来）。
final class AgentMemoryWriteGateTests: XCTestCase {

    private var directory: URL!
    private var store: AgentMemoryStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-memory-gate-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = AgentMemoryStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func draft(_ note: String,
                       kind: MemoryKind = .routine,
                       workspace: String = "ws-1",
                       connection: String = "prod") -> AgentMemoryDraft {
        AgentMemoryDraft(workspace: workspace, connection: connection, kind: kind, note: note)
    }

    // MARK: - 判据 ①：触发方式

    func testSpontaneousWriteIsTurnedIntoCandidateNotPersisted() throws {
        let decision = AgentMemoryWriteGate.decide(trigger: .modelSpontaneous,
                                                   draft: draft("这个项目的迁移要先跑对账"))
        XCTAssertEqual(decision, .needsConfirmation)

        let result = try store.record(draft("这个项目的迁移要先跑对账"),
                                      trigger: .modelSpontaneous,
                                      round: 7,
                                      at: now)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.rejections, [.needsUserConfirmation])
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.count, 0, "自发写入不许落盘")
    }

    func testUserInstructionIsRecordedWithItsSourceRound() throws {
        let result = try store.record(draft("发布前先跑 verify-core"),
                                      trigger: .userInstruction,
                                      round: 3,
                                      at: now)
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.entry?.sourceRound, 3)
        XCTAssertEqual(result.entry?.sourceTrigger, AgentMemoryTrigger.userInstruction.rawValue)

        let readBack = store.entries(workspace: "ws-1").entries
        XCTAssertEqual(readBack.count, 1)
        XCTAssertEqual(readBack.first?.sourceRound, 3, "来源轮次要能指回去")
    }

    func testHumanConfirmationIsRecorded() throws {
        let result = try store.record(draft("这台机器的 Postgres 在 217"),
                                      trigger: .userConfirmation,
                                      round: 5,
                                      at: now)
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.entry?.sourceTrigger, AgentMemoryTrigger.userConfirmation.rawValue)
    }

    // MARK: - 判据 ②：内容不过闸，谁要写都拒

    func testEmptyNoteIsRefusedEvenForTheUser() throws {
        let result = try store.record(draft("   "), trigger: .userInstruction, at: now)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.rejections, [.emptyNote])
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.count, 0)
    }

    func testSecretFragmentIsRefusedBeforeAnyTriggerCheck() throws {
        let result = try store.record(draft("api key sk-abcdefghijklmnopqrstuvwxyz012345"),
                                      trigger: .userConfirmation, at: now)
        XCTAssertFalse(result.accepted)
        XCTAssertTrue(result.rejections.contains { if case .secretFragment = $0 { return true }; return false })
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.count, 0)
    }

    // MARK: - 判据 ③：同键覆盖 —— 新者生效、旧值可查

    func testOverwritingKeepsTheOldValueReadable() throws {
        _ = try store.record(draft("发布前先跑 verify-core"), trigger: .userInstruction, round: 1, at: now)
        let second = try store.record(draft("发布前先跑 verify-core"), trigger: .userInstruction, round: 4, at: now)

        XCTAssertTrue(second.accepted)
        XCTAssertTrue(second.merged, "同键二次写入是覆盖，不是又长一条")
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.count, 1)
        XCTAssertEqual(second.entry?.sourceRound, 4, "来源轮次跟到最新那次")

        // 换了正文 = 新指纹 ⇒ 按既有口径**另立一条**（聚类键是粗指纹，不是工作区）；
        // 旧条目的正文不许被改写 —— 「新者生效」只作用于同一键，不作用于别的记忆。
        let existing = second.entry ?? store.entries(workspace: "ws-1").entries[0]
        let third = try store.record(draft("发布前先跑 verify-core 与三个 doc 门"),
                                     trigger: .userInstruction, round: 6, at: now)
        XCTAssertTrue(third.accepted)
        let entries = store.entries(workspace: "ws-1").entries
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains { $0.note == existing.note }, "旧正文仍在")
    }

    func testSupersedingHelperAppendsHistoryAndBumpsSource() throws {
        var entry = AgentMemoryEntry(id: "m1", workspace: "ws-1", connection: "prod",
                                     kind: MemoryKind.routine.rawValue, note: "旧说法",
                                     fingerprint: "fp", firstSeenAt: now, lastUsedAt: now, useCount: 1)
        let updated = AgentMemoryWriteGate.superseding(entry,
                                                       with: "新说法",
                                                       at: now.addingTimeInterval(60),
                                                       trigger: .userConfirmation,
                                                       round: 9)
        XCTAssertEqual(updated.note, "新说法")
        XCTAssertEqual(updated.supersededNotes, ["旧说法"])
        XCTAssertEqual(updated.useCount, 2)
        XCTAssertEqual(updated.sourceRound, 9)
        XCTAssertEqual(updated.sourceTrigger, AgentMemoryTrigger.userConfirmation.rawValue)

        entry = updated
        let again = AgentMemoryWriteGate.superseding(entry, with: "更新说法", at: now, trigger: .userInstruction, round: 10)
        XCTAssertEqual(again.supersededNotes, ["旧说法", "新说法"], "旧值按先后累积，不覆盖历史")
    }

    func testHistoryIsCappedAndSaysNothingElse() throws {
        var entry = AgentMemoryEntry(id: "m1", workspace: "ws-1", connection: "prod",
                                     kind: MemoryKind.routine.rawValue, note: "v0",
                                     fingerprint: "fp", firstSeenAt: now, lastUsedAt: now, useCount: 1)
        for i in 1...25 {
            entry = AgentMemoryWriteGate.superseding(entry, with: "v\(i)", at: now,
                                                     trigger: .userInstruction, round: i, historyLimit: 5)
        }
        XCTAssertEqual(entry.supersededNotes?.count, 5, "历史按上限裁剪，不无限长")
        XCTAssertEqual(entry.supersededNotes?.last, "v24")
    }

    // MARK: - 判据 ④：旧数据照样读得回来（加字段不改旧文件）

    func testOldFileWithoutTheNewKeysStillLoads() throws {
        // 先正常写一条，再把新加的三键从那一行里删掉 —— 模拟「上个版本写的旧文件」。
        _ = try store.record(draft("老的一条"), trigger: .userInstruction, round: 2, at: now)
        let url = store.factFileURL(workspace: "ws-1")
        var lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        lines = lines.map { line in
            guard var object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object.keys.count > 1 else { return line }
            object.removeValue(forKey: "sourceRound")
            object.removeValue(forKey: "sourceTrigger")
            object.removeValue(forKey: "supersededNotes")
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? line
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)

        let loaded = store.entries(workspace: "ws-1")
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries.first?.note, "老的一条")
        XCTAssertNil(loaded.entries.first?.sourceRound, "旧数据没有来源轮次 = nil，不是 0")
        XCTAssertEqual(loaded.skippedLines, 0, "少了新键不该让旧行被判成坏行")
    }

    // MARK: - 判据 ⑤：显式键（同键改说法也是同一件事）

    func testSameKeyOverwritesEvenWhenWordingChanges() throws {
        let first = try store.record(AgentMemoryDraft(workspace: "ws-1", connection: "prod",
                                                      kind: .routine, note: "发布前先跑 verify-core",
                                                      key: "release-gate"),
                                     trigger: .userInstruction, round: 1, at: now)
        XCTAssertTrue(first.accepted)

        let second = try store.record(AgentMemoryDraft(workspace: "ws-1", connection: "prod",
                                                       kind: .routine, note: "发布前先跑 verify-core 与三门",
                                                       key: "release-gate"),
                                      trigger: .userInstruction, round: 2, at: now)
        XCTAssertTrue(second.accepted)
        XCTAssertTrue(second.merged, "同键改说法 = 同一件事，不是新记忆")
        let entries = store.entries(workspace: "ws-1").entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].note, "发布前先跑 verify-core 与三门", "新值生效")
        XCTAssertEqual(entries[0].supersededNotes, ["发布前先跑 verify-core"], "旧值仍可查")
        XCTAssertEqual(entries[0].key, "release-gate", "键要跟着落盘")
    }

    func testDifferentKeysStaySeparate() throws {
        _ = try store.record(AgentMemoryDraft(workspace: "ws-1", connection: "prod",
                                              kind: .routine, note: "同样一句话", key: "k1"),
                             trigger: .userInstruction, at: now)
        _ = try store.record(AgentMemoryDraft(workspace: "ws-1", connection: "prod",
                                              kind: .routine, note: "同样一句话", key: "k2"),
                             trigger: .userInstruction, at: now)
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.count, 2, "不同键就是两件事，哪怕正文一样")
    }

    func testWithoutKeyTheFingerprintStillDecides() throws {
        _ = try store.record(draft("迁移前先对账"), trigger: .userInstruction, at: now)
        let again = try store.record(draft("迁移前先对账"), trigger: .userInstruction, at: now)
        XCTAssertTrue(again.merged, "没给键 ⇒ 沿用粗指纹，行为不变")
        XCTAssertEqual(store.entries(workspace: "ws-1").entries.count, 1)
    }

    func testKeyedEntrySurvivesReload() throws {
        _ = try store.record(AgentMemoryDraft(workspace: "ws-1", connection: "prod",
                                              kind: .routine, note: "规矩", key: "release-gate"),
                             trigger: .userConfirmation, round: 3, at: now)
        let reloaded = store.entries(workspace: "ws-1").entries
        XCTAssertEqual(reloaded.first?.key, "release-gate")
        XCTAssertEqual(reloaded.first?.sourceRound, 3)
    }
}
