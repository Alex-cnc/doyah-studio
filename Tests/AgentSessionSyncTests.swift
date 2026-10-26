import XCTest
@testable import DoyahCore

/// `FR-AGT-UX-SYNC-001` 多端一致性的契约面判据（①任一端发的话另一端可见
/// ②审批只需一次、另一端不重复问 ③断线重连按游标补齐、坏游标只许全量重同步）。
///
/// 传输层（桌面 ↔ 手机的转发、鉴权、心跳）不在这一族的射程内：这里钉的是
/// **无论传输怎么接，这三条都得成立**的部分。
final class AgentSessionSyncTests: XCTestCase {

    private var root: URL!
    private var journal: AgentSyncJournal!
    private var ledger: AgentSyncApprovalLedger!

    private let session = "S-1"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        journal = AgentSyncJournal(directory: root)
        ledger = AgentSyncApprovalLedger(directory: root)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        journal = nil
        ledger = nil
    }

    private func append(_ id: String, _ text: String, from end: AgentSyncEnd,
                        role: AgentSyncRole = .user, session: String? = nil) throws -> AgentSyncAppendOutcome {
        try journal.append(id: id, sessionID: session ?? self.session, origin: end,
                           role: role, text: text, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - ① 任一端发出的话，另一端可见（内容同，壳不同）

    func testMessageFromEitherEndIsVisibleOnTheOther() throws {
        try append("m1", "删掉测试库里的临时表", from: .desktop)
        try append("m2", "已经删完了", from: .mobile, role: .assistant)

        let seen = journal.messages(sessionID: session)
        XCTAssertEqual(seen.map(\.id), ["m1", "m2"])
        // 来源端如实记着（壳能区分是谁说的），正文与角色不因端而变（内容同）。
        XCTAssertEqual(seen.map(\.origin), [.desktop, .mobile])
        XCTAssertEqual(seen.map(\.text), ["删掉测试库里的临时表", "已经删完了"])
        XCTAssertEqual(seen.map(\.role), [.user, .assistant])
    }

    func testSequenceIsAssignedByJournalNotByCaller() throws {
        try journal.append(AgentSyncMessage(id: "m1", sessionID: session, sequence: 99,
                                            origin: .mobile, role: .user, text: "a"))
        let seen = journal.messages(sessionID: session)
        XCTAssertEqual(seen.map(\.sequence), [1])
    }

    func testMergeIsIdempotentAndCommutative() throws {
        try append("m1", "第一句", from: .desktop)
        try append("m2", "第二句", from: .mobile)
        try append("m3", "第三句", from: .desktop)

        let all = journal.messages(sessionID: session)
        let mobileSide = [all[1]]                 // 手机只先拿到中间一条
        let desktopSide = [all[0], all[2]]

        let one = AgentSyncMerge.merged(desktopSide, mobileSide)
        let two = AgentSyncMerge.merged(mobileSide, desktopSide)
        XCTAssertEqual(one.messages, two.messages, "先收到哪一批，合并结果必须一样")
        XCTAssertEqual(one.messages.map(\.id), ["m1", "m2", "m3"])
        XCTAssertTrue(one.conflicts.isEmpty)

        // 幂等：把已经合过的再合一次，什么都不变。
        let again = AgentSyncMerge.merged(one.messages, mobileSide)
        XCTAssertEqual(again.messages, one.messages)
    }

    func testConflictingContentIsNamedNotSilentlyPicked() throws {
        let a = AgentSyncMessage(id: "m1", sessionID: session, sequence: 1,
                                 origin: .desktop, role: .assistant, text: "结论 A")
        let b = AgentSyncMessage(id: "m1", sessionID: session, sequence: 1,
                                 origin: .mobile, role: .assistant, text: "结论 B")
        let merged = AgentSyncMerge.merged([a], [b])
        XCTAssertEqual(merged.messages.count, 1)
        XCTAssertEqual(merged.conflicts, ["m1"], "同 id 两种正文必须点名")
    }

    // MARK: - ① 重复投递与改历史

    func testDuplicateAppendDoesNotCreateSecondRow() throws {
        let first = try append("m1", "重连补发同一条", from: .mobile)
        let second = try append("m1", "重连补发同一条", from: .mobile)

        guard case .appended(let stored) = first else { return XCTFail("首投应当是新增") }
        guard case .duplicate(let again) = second else { return XCTFail("重投应当判重复") }
        XCTAssertEqual(again.sequence, stored.sequence)
        XCTAssertEqual(journal.messages(sessionID: session).count, 1)
    }

    func testRewritingHistoryIsReportedAndFirstWriteWins() throws {
        let first = try append("m1", "原话", from: .desktop)
        let second = try append("m1", "改过的话", from: .desktop)

        guard case .appended(let stored) = first else { return XCTFail("首投应当是新增") }
        guard case .conflict(let existing) = second else { return XCTFail("改内容应当判冲突") }
        XCTAssertEqual(existing.text, stored.text)
        XCTAssertEqual(journal.messages(sessionID: session).map(\.text), ["原话"])
    }

    // MARK: - ② 审批只需一次，另一端不重复问

    func testSecondEndDecisionDoesNotOverrideFirst() throws {
        let at = Date(timeIntervalSince1970: 1_700_000_100)
        let first = try ledger.decide(requestID: "r1", sessionID: session, approved: true,
                                      by: .desktop, at: at)
        guard case .recorded(let recorded) = first else { return XCTFail("首决应当落账") }
        XCTAssertEqual(recorded.decidedBy, .desktop)

        let second = try ledger.decide(requestID: "r1", sessionID: session, approved: false,
                                       by: .mobile, at: at.addingTimeInterval(30))
        guard case .alreadyDecided(let kept) = second else { return XCTFail("二次决定必须被挡下") }
        XCTAssertTrue(kept.approved, "先决的批准不许被后到的拒绝翻掉")
        XCTAssertEqual(kept.decidedBy, .desktop)
        XCTAssertEqual(kept.decidedAt, at, "决定时刻也不许被改写")
        XCTAssertEqual(ledger.all().count, 1)
    }

    func testDecidedRequestLeavesNoOpenQuestionOnEitherEnd() throws {
        try ledger.decide(requestID: "r1", sessionID: session, approved: true, by: .desktop)
        let candidates = ["r1", "r2"]
        XCTAssertEqual(ledger.openRequestIDs(candidates, for: .mobile), ["r2"])
        XCTAssertEqual(ledger.openRequestIDs(candidates, for: .desktop), ["r2"],
                       "决过的那条在决定人这一侧也不再问（审批按次）")
    }

    func testUndecidedRequestIsOpenOnBothEnds() throws {
        XCTAssertEqual(ledger.openRequestIDs(["r1"], for: .desktop), ["r1"])
        XCTAssertEqual(ledger.openRequestIDs(["r1"], for: .mobile), ["r1"])
        XCTAssertNil(ledger.decision(requestID: "r1"))
    }

    func testDecisionSurvivesReload() throws {
        try ledger.decide(requestID: "r1", sessionID: session, approved: true, by: .mobile)
        let reloaded = AgentSyncApprovalLedger(directory: root)
        XCTAssertEqual(reloaded.decision(requestID: "r1")?.decidedBy, .mobile)
        let again = try reloaded.decide(requestID: "r1", sessionID: session,
                                        approved: false, by: .desktop)
        guard case .alreadyDecided = again else { return XCTFail("重启后仍须认得出已决") }
    }

    // MARK: - ③ 断线重连按游标补齐

    func testBatchSinceCursorReturnsOnlyTheNewMessages() throws {
        try append("m1", "一", from: .desktop)
        try append("m2", "二", from: .mobile)
        try append("m3", "三", from: .desktop)

        let batch = journal.batch(sessionID: session, since: 1)
        XCTAssertEqual(batch.messages.map(\.id), ["m2", "m3"])
        XCTAssertEqual(batch.cursor, 3)
        XCTAssertFalse(batch.fullResync)
        XCTAssertNil(batch.reason)
    }

    func testCursorAtLatestYieldsEmptyBatchWithoutResync() throws {
        try append("m1", "一", from: .desktop)
        let batch = journal.batch(sessionID: session, since: journal.cursor(sessionID: session))
        XCTAssertTrue(batch.messages.isEmpty)
        XCTAssertFalse(batch.fullResync, "「没有新消息」不等于「游标坏了」")
    }

    func testEmptyLogWithZeroCursorIsNotAResync() throws {
        let batch = journal.batch(sessionID: session, since: 0)
        XCTAssertTrue(batch.messages.isEmpty)
        XCTAssertFalse(batch.fullResync)
        XCTAssertEqual(batch.cursor, 0)
    }

    func testNegativeCursorForcesFullResyncWithReason() throws {
        try append("m1", "一", from: .desktop)
        try append("m2", "二", from: .mobile)
        let batch = journal.batch(sessionID: session, since: -3)
        XCTAssertTrue(batch.fullResync)
        XCTAssertEqual(batch.reason, .unknownCursor)
        XCTAssertEqual(batch.messages.map(\.id), ["m1", "m2"], "坏游标只能全量补齐，不许丢")
        XCTAssertEqual(batch.cursor, 2)
    }

    func testCursorAheadOfLogForcesFullResyncWithReason() throws {
        try append("m1", "一", from: .desktop)
        let batch = journal.batch(sessionID: session, since: 7)
        XCTAssertTrue(batch.fullResync)
        XCTAssertEqual(batch.reason, .aheadOfLog)
        XCTAssertEqual(batch.messages.map(\.id), ["m1"])
        XCTAssertEqual(batch.cursor, 1)
    }

    func testCursorBeyondEmptyLogForcesFullResync() throws {
        let batch = journal.batch(sessionID: session, since: 1)
        XCTAssertTrue(batch.fullResync)
        XCTAssertEqual(batch.reason, .aheadOfLog)
        XCTAssertTrue(batch.messages.isEmpty)
    }

    // MARK: - 边界：会话隔离与文件名

    func testSessionsDoNotBleedIntoEachOther() throws {
        try append("m1", "会话一", from: .desktop, session: "S-1")
        try append("m1", "会话二", from: .mobile, session: "S-2")
        XCTAssertEqual(journal.messages(sessionID: "S-1").map(\.text), ["会话一"])
        XCTAssertEqual(journal.messages(sessionID: "S-2").map(\.text), ["会话二"])
        XCTAssertEqual(journal.cursor(sessionID: "S-1"), 1)
    }

    func testSessionIDCannotEscapeTheDirectory() throws {
        let hostile = "../../etc/S-9"
        try append("m1", "越界试试", from: .mobile, session: hostile)
        // 落在 root 之下（文件名里的分隔符被换掉），而不是跑到上级目录去。
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(files.filter { $0.hasPrefix("sync-") }.count, 1)
        XCTAssertEqual(journal.messages(sessionID: hostile).map(\.text), ["越界试试"])
    }

    func testJournalSurvivesReload() throws {
        try append("m1", "一", from: .mobile)
        let reloaded = AgentSyncJournal(directory: root)
        XCTAssertEqual(reloaded.messages(sessionID: session).map(\.id), ["m1"])
        let next = try reloaded.append(id: "m2", sessionID: session, origin: .desktop,
                                       role: .assistant, text: "二")
        guard case .appended(let stored) = next else { return XCTFail("应当接着往后排") }
        XCTAssertEqual(stored.sequence, 2, "重启后序号接着数，不回退")
    }
}
