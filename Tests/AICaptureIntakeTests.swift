import XCTest
@testable import DoyahCore

// 队列 `L-134`（`Q14=A`）的机械证据：**同一份 AI 产物再次保存**不许变成两条。
//
// 这条口径最容易被"看起来对"的代码骗过去：调用点**确实算了**同指纹（`duplicate` 变量存在），
// 只是算完照样 `upsert` —— 提示语都写对了，库里却是两条。所以判据落在**库里几条**上，
// 不落在提示语上：同一份产物存两次 ⇒ 读回来 1 条；显式要副本 ⇒ 2 条。
//
// 三条纪律（与 `NoteLibraryTests` 同源）：
//   ① **跑真库文件**（临时目录）—— 判重是在"读现有笔记"这一步起作用的，假库测不出；
//   ② **纯函数那半边也要测**（`decide` 不碰磁盘）—— 于是"指回哪一条"这种细节可以直接断言，
//      不必去凑时序或时间戳；
//   ③ **源树判据不许空转**：读到的文件太短（路径写错 / 换成空文件）当场报红。
final class AICaptureIntakeTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-ai-capture-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func library() -> NoteLibrary {
        NoteLibrary(databaseURL: directory.appendingPathComponent(NoteLibrary.fileName))
    }

    // MARK: - 夹具：同一份诊断产物（指纹由证据与结论算出，不掺时间）

    private func context() -> DiagnosisContext {
        DiagnosisContext(
            question: "这条查询为什么慢？",
            target: "postgres@192.168.5.217:5432/dsh_db（8.4.10）",
            evidence: [
                DiagnosisContextBuilder.makeEvidence(
                    id: "e1", kind: .statement, sql: "SELECT * FROM orders", rows: [],
                    language: .simplifiedChinese
                )
            ]
        )
    }

    private func report() -> DiagnosisAdviceReport {
        DiagnosisAdvice.parse(
            reply: "结论: 全表扫描 [依据: e1]",
            context: context(), language: .simplifiedChinese
        )
    }

    /// 同一份产物 ⇒ 同一个指纹（两条草稿逐字段不同的只有时间，指纹不掺时间）。
    private func draft() -> NoteDraft {
        AICapture.diagnosisNote(
            question: "这条查询为什么慢？",
            target: context().target,
            context: context(),
            report: report(),
            language: .simplifiedChinese
        )
    }

    private func note(
        title: String,
        fingerprint: String?,
        createdAt: Date
    ) -> Note {
        Note(
            title: title,
            body: "正文",
            source: NoteSource(kind: .diagnosis, connectionName: "217", fingerprint: fingerprint),
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    // MARK: - 1) 同一份产物存两次 ⇒ 库里只有一条（本轮的要害）

    func testSameOutputSavedTwiceLeavesOneNote() async throws {
        let store = library()
        let first = try await AICaptureIntake.receive(draft(), into: store)
        XCTAssertEqual(first.outcome, .saved)

        let second = try await AICaptureIntake.receive(draft(), into: store)
        XCTAssertEqual(second.outcome, .reusedExisting, "同指纹默认不重复存（Q14=A）")
        XCTAssertEqual(second.note.id, first.note.id, "指回的就是已存的那一条")

        let stored = try await store.load()
        XCTAssertEqual(stored.count, 1, "两次保存只许留一条 —— 从前这里是 2 条")
    }

    // MARK: - 2) 显式要副本 ⇒ 两条

    func testForceNewStoresACopy() async throws {
        let store = library()
        _ = try await AICaptureIntake.receive(draft(), into: store)
        let copy = try await AICaptureIntake.receive(draft(), into: store, forceNew: true)
        XCTAssertEqual(copy.outcome, .savedCopy)

        let stored = try await store.load()
        XCTAssertEqual(stored.count, 2, "显式要副本时就是要第二条")
        XCTAssertNotEqual(stored[0].id, stored[1].id, "副本是另一条笔记，不是同一行被改了两遍")
        XCTAssertEqual(
            Set(stored.map { $0.source.fingerprint }),
            Set([draft().source.fingerprint]),
            "两条的指纹相同（判重就是靠它认出来的）"
        )
    }

    // MARK: - 3) 没有指纹 ⇒ 没有判重（如实，不靠正文猜）

    func testDraftWithoutFingerprintIsAlwaysSaved() async throws {
        let store = library()
        let manual = NoteDraft(title: "自己写的一条", body: "同样的正文", source: NoteSource(kind: .manual))
        _ = try await AICaptureIntake.receive(manual, into: store)
        let again = try await AICaptureIntake.receive(manual, into: store)
        XCTAssertEqual(again.outcome, .saved)
        let stored = try await store.load()
        XCTAssertEqual(stored.count, 2, "没有指纹就没有判重依据：不许拿正文相似度去猜")
    }

    // MARK: - 4) 纯判定（不碰磁盘）：指回**最早**那条，且答案不随运行漂移

    func testDecisionPointsBackToTheEarliestCapture() throws {
        let fingerprint = "abc123"
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = [
            note(title: "第三次存下的", fingerprint: fingerprint, createdAt: base.addingTimeInterval(200)),
            note(title: "第一次存下的", fingerprint: fingerprint, createdAt: base),
            note(title: "第二次存下的", fingerprint: fingerprint, createdAt: base.addingTimeInterval(100)),
            note(title: "别的产物", fingerprint: "other", createdAt: base.addingTimeInterval(-500))
        ]
        let draft = NoteDraft(
            title: "第四次",
            source: NoteSource(kind: .diagnosis, connectionName: "217", fingerprint: fingerprint)
        )

        let decision = AICaptureIntake.decide(draft: draft, existing: existing, forceNew: false)
        XCTAssertEqual(decision.outcome, .reusedExisting)
        XCTAssertFalse(decision.didWrite, "判定说不写，就不许写")
        XCTAssertEqual(decision.existingNote?.title, "第一次存下的")
        XCTAssertEqual(
            AICaptureIntake.earliest(fingerprint: fingerprint, in: existing)?.title,
            "第一次存下的",
            "两次算必须给同一条（同 `createdAt` 时按 id 定序，不许靠遍历顺序）"
        )
    }

    func testDecisionWithoutMatchOrWithForceNew() throws {
        let draft = NoteDraft(
            title: "第一次",
            source: NoteSource(kind: .diagnosis, connectionName: "217", fingerprint: "abc123")
        )
        XCTAssertEqual(
            AICaptureIntake.decide(draft: draft, existing: [], forceNew: false).outcome, .saved
        )
        XCTAssertEqual(
            AICaptureIntake.decide(draft: draft, existing: [], forceNew: true).outcome, .saved,
            "库里本来就没有同指纹的，`force-new` 也是新建一条（不是另一种行为）"
        )
        let existing = [note(title: "老的", fingerprint: "abc123", createdAt: Date())]
        let forced = AICaptureIntake.decide(draft: draft, existing: existing, forceNew: true)
        XCTAssertEqual(forced.outcome, .savedCopy)
        XCTAssertNil(forced.existingNote, "要副本时没有被指回的那一条")
        XCTAssertTrue(forced.didWrite)
    }

    // MARK: - 5) 调用点不许自己判重（源树判据）

    func testCallSitesGoThroughTheIntake() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let targets = ["App/AppState.swift", "CLI/main.swift"]

        for relative in targets {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            // **判据自己不许空转**：读到的文件太短（路径错了 / 换成空文件）当场报红。
            XCTAssertGreaterThan(text.count, 10_000, "\(relative) 读到的内容太短，这条判据不成立")
            XCTAssertTrue(text.contains("AICaptureIntake"), "\(relative) 该走唯一入口")
            XCTAssertFalse(
                text.contains("source.fingerprint"),
                "\(relative) 里又出现了调用点自己算指纹 —— 判重只许在 `AICaptureIntake` 一处"
            )
        }
    }
}
