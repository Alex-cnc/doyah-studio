import XCTest
@testable import DoyahCore

// `FR-NTS-NOTE-VERSION-001`（历史版本）的机械证据：**每次保存留版本 / 可查看与回滚 / 回滚本身也生成新版本**。
//
// 三条纪律（与 `NoteStoreSQLiteTests` 同源）：
//   ① 都跑**真库文件**（临时目录）：版本表在 `:memory:` 里不验证 WAL / 升级链；
//   ② 判据**成对**：每条「应该记一版」都配一条「不该记第二版」的对照，否则「每次写都记」也能骗过去；
//   ③ 题面里的「不是」也要盯着：需求写「不是 Git」⇒ 不做分支、不做提交信息，这里逐条判「没有多余概念」。
final class NoteVersionTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-note-version-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func url(_ name: String = NoteLibrary.fileName) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    private func library() -> NoteLibrary {
        NoteLibrary(databaseURL: url())
    }

    private func draft(title: String, body: String, tags: [String] = []) -> NoteDraft {
        NoteDraft(title: title, body: body, tags: tags)
    }

    // MARK: - ① 每次保存留一版（含时间与摘要）

    func testEverySaveLeavesAVersionWithTimeAndSummary() async throws {
        let library = library()
        let first = try await library.save(
            draft(title: "骑行计划", body: "环洞庭湖第一段\n备注"),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = try await library.save(
            draft(title: "骑行计划", body: "环洞庭湖第二段\n改过了"),
            id: first.id,
            now: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let versions = try await library.versions(of: first.id)
        XCTAssertEqual(versions.count, 2, "两次保存 = 两版")
        // 最新在前：界面列表与判据读数都认这个顺序（不各排一遍）。
        XCTAssertEqual(versions.first?.version, 2)
        XCTAssertEqual(versions.last?.version, 1)
        // 判据①「版本列表含时间与摘要」：每版都有时间与摘要，且摘要是正文首个非空行。
        XCTAssertEqual(versions.first?.summary, "环洞庭湖第二段")
        XCTAssertEqual(versions.last?.summary, "环洞庭湖第一段")
        XCTAssertEqual(versions.first?.savedAt, Date(timeIntervalSince1970: 1_700_000_100))
        XCTAssertEqual(versions.last?.savedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(versions.allSatisfy { !$0.summary.isEmpty })
        let count = try await library.versionCount(of: first.id)
        XCTAssertEqual(count, 2)
    }

    /// **负例**：内容没变的保存**不记第二版** —— 否则自动保存的停顿窗口会把同一份内容记成几十版。
    func testUnchangedContentIsNotRecordedAgain() async throws {
        let library = library()
        let note = try await library.save(draft(title: "同一条", body: "一模一样"), now: Date(timeIntervalSince1970: 1_700_000_000))
        _ = try await library.save(draft(title: "同一条", body: "一模一样"), id: note.id, now: Date(timeIntervalSince1970: 1_700_000_100))
        _ = try await library.save(draft(title: "同一条", body: "一模一样"), id: note.id, now: Date(timeIntervalSince1970: 1_700_000_200))
        let count = try await library.versionCount(of: note.id)
        XCTAssertEqual(count, 1, "内容全等 ⇒ 一版都不多记")
    }

    // MARK: - ② 回滚后原文仍可取回 / ③ 回滚本身也生成新版本

    func testRollbackRestoresTheOriginalAndItselfCreatesANewVersion() async throws {
        let library = library()
        let note = try await library.save(
            draft(title: "初稿", body: "第一版正文", tags: ["a"]),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = try await library.save(
            draft(title: "改坏了", body: "第二版正文", tags: ["b"]),
            id: note.id,
            now: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let restored = try await library.rollback(id: note.id, to: 1, now: Date(timeIntervalSince1970: 1_700_000_200))
        XCTAssertEqual(restored?.title, "初稿")
        XCTAssertEqual(restored?.body, "第一版正文")
        XCTAssertEqual(restored?.tags, ["a"], "标签也回滚（回滚的是那一版的完整内容）")

        let versions = try await library.versions(of: note.id)
        XCTAssertEqual(versions.count, 3, "回滚本身也生成新版本（判据③）")
        XCTAssertEqual(versions.first?.reason, .rollback)
        XCTAssertEqual(versions.first?.body, "第一版正文")
        // 判据②「回滚后原文仍可取回」：被回滚掉的那一版（第二版）还在。
        XCTAssertTrue(versions.contains { $0.version == 2 && $0.body == "第二版正文" })
    }

    /// **负例**：回滚到不存在的版本号 ⇒ `nil`，**不许静默当成成功**（否则界面会拿「什么都没变」当回滚完成）。
    func testRollbackToAMissingVersionReturnsNilAndTouchesNothing() async throws {
        let library = library()
        let note = try await library.save(draft(title: "只有一版", body: "正文"), now: Date(timeIntervalSince1970: 1_700_000_000))
        let outcome = try await library.rollback(id: note.id, to: 99)
        XCTAssertNil(outcome)
        let count = try await library.versionCount(of: note.id)
        XCTAssertEqual(count, 1, "没命中就不许记新版本")
        let loaded = try await library.load()
        XCTAssertEqual(loaded.first?.body, "正文")
    }

    // MARK: - ④ 保留策略有上限、可配置

    func testRetentionKeepsOnlyTheConfiguredNumberOfVersions() async throws {
        let library = library()
        let retention = NoteVersionRetention(maxCount: 3)
        var id: UUID?
        for index in 1...6 {
            let saved = try await library.save(
                draft(title: "第 \(index) 版", body: "正文 \(index)"),
                id: id,
                now: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                retention: retention
            )
            id = saved.id
        }
        let versions = try await library.versions(of: try XCTUnwrap(id))
        XCTAssertEqual(versions.count, 3, "上限 3 ⇒ 只留最新 3 版（判据③「有上限」）")
        XCTAssertEqual(versions.map(\.version), [6, 5, 4], "按最旧的先丢")
        XCTAssertEqual(versions.first?.body, "正文 6")
        // 默认档的说明就在类型上，判据读它而不是各处各写一个数字。
        XCTAssertEqual(NoteVersionRetention.defaultLimit, 50)
        XCTAssertEqual(NoteVersionRetention.default.maxCount, 50)
    }

    /// **`spans` 与正文一起进版本、一起回滚**（富文本权威源不能回滚成空）。
    func testRollbackRestoresSpansNotOnlyTheProjection() async throws {
        let library = library()
        let body = NoteBody(spans: [NoteSpan(text: "权威源甲")])
        let encoded = String(data: try JSONEncoder().encode(body), encoding: .utf8)!
        let note = try await library.save(draft(title: "T", body: body.body), spans: encoded, now: Date(timeIntervalSince1970: 1_700_000_000))
        let spansAfterFirst = try await library.noteSpans(id: note.id)
        XCTAssertEqual(spansAfterFirst, encoded)

        let body2 = NoteBody(spans: [NoteSpan(text: "权威源乙")])
        let encoded2 = String(data: try JSONEncoder().encode(body2), encoding: .utf8)!
        _ = try await library.save(draft(title: "T", body: body2.body), spans: encoded2, id: note.id, now: Date(timeIntervalSince1970: 1_700_000_100))

        _ = try await library.rollback(id: note.id, to: 1, now: Date(timeIntervalSince1970: 1_700_000_200))
        let spansAfterRollback = try await library.noteSpans(id: note.id)
        XCTAssertEqual(spansAfterRollback, encoded, "spans 回到第一版")
    }
}
