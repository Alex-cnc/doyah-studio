import Foundation
import XCTest
@testable import DoyahCore

// `FR-RT-11`（旧正文迁移）的机械证据 —— 片 `WY-2b`，服务锚点 `T-20261008-050`。
//
// 判据照抄需求原文三条，**逐条落到断言上**（不是纸面讨论）：
//   ① 迁移前后 `toPlainText` 一致 ⇒ `Report.mismatches` 为空；真库那一条还逐字比回 `note.body`；
//   ② 二次迁移无 diff ⇒ 第二跑 `written == 0`、`backupName == nil`、盘上那次写回的 `spans` 逐字不变；
//   ③ 备份文件在盘 ⇒ `Report.backupURL` 可读，且载荷 = **迁移前全量逐字**。
//
// 另有一条**反例**（`testMismatchIsReportedWhenWriteLosesText`）：落库面故意吞字 ⇒ 复跑校验必须当场
// 点名。这是「判据没空转」的自检 —— 没有它，`mismatches` 恒空也看不出来。
final class NoteBodyMigrationTests: XCTestCase {

    // MARK: - 夹具

    /// 内存落库面：只认「一份正文 → 一份正文」，不碰盘 —— 与执行器的 `NoteBodyMigrationStore` 同形。
    private final class MemoryStore: NoteBodyMigrationStore {
        private var records: [UUID: (body: String, spans: String?)]
        private let order: [UUID]
        private(set) var writes: [UUID] = []
        /// 反例用：落库时故意改坏内容。
        var corrupt: ((UUID, String) -> String)?

        init(rows: [(UUID, String)], spans: [UUID: String] = [:]) {
            order = rows.map { $0.0 }
            records = [:]
            for (id, body) in rows { records[id] = (body, spans[id]) }
        }

        func legacyRows() throws -> [NoteBodyMigrationRunner.Row] {
            order.compactMap { id in records[id].map { NoteBodyMigrationRunner.Row(id: id, body: $0.body) } }
        }

        func storedSpans(id: UUID) throws -> String? { records[id]?.spans }

        func alreadyMigratedCount() throws -> Int {
            records.values.filter { $0.spans != nil }.count
        }

        @discardableResult
        func writeSpans(_ spans: String, body: String, id: UUID) throws -> Int {
            writes.append(id)
            records[id] = (body, corrupt?(id, spans) ?? spans)
            return 1
        }

        func spans(id: UUID) -> String? { records[id]?.spans }
    }

    private final class MemorySink: NoteBodyMigrationSink {
        private(set) var writes: [(fileName: String, payload: String)] = []

        func write(fileName: String, payload: String) throws -> URL {
            writes.append((fileName, payload))
            return URL(fileURLWithPath: "/tmp/doyah-migration-test").appendingPathComponent(fileName)
        }
    }

    private let legacyA = "普通 **加粗** 与 *斜体* 混排\n第二行纯文本"
    private let legacyB = "只有纯文本，没有任何标记"

    private func target(_ body: String) throws -> String {
        try NoteBodyMigrationRunner.migrate(body: body).spans
    }

    /// 备份载荷 → `[(id, body)]`（测试侧只按自己的口径解一次，不碰产品代码）。
    private func backupBodies(_ payload: String) throws -> [(id: String, body: String)] {
        struct Snapshot: Codable {
            var id: String
            var body: String
        }
        return try JSONDecoder().decode([Snapshot].self, from: Data(payload.utf8)).map { ($0.id, $0.body) }
    }

    // MARK: - 执行器：一次搬完 / 幂等 / 只写变化行 / 备份

    /// 判据 ①③：全量搬完、逐行回写、复跑校验为空、备份只写一次且是迁移前全量。
    func testRunMigratesEveryLegacyRowAndWritesBackupOnce() throws {
        let ids = (UUID(), UUID())
        let store = MemoryStore(rows: [(ids.0, legacyA), (ids.1, legacyB)])
        let sink = MemorySink()

        let report = try NoteBodyMigrationRunner.run(store: store, sink: sink)

        XCTAssertEqual(report.total, 2, "待迁移面读的是全量")
        XCTAssertEqual(report.changed, 2)
        XCTAssertEqual(report.written, 2)
        XCTAssertEqual(report.mismatches, [], "判据 ①：迁移前后投影一致")
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual(report.backupName, NoteBodyMigrationRunner.backupFileName, "判据 ③：备份文件在盘")
        XCTAssertEqual(sink.writes.count, 1, "备份只写一次")
        XCTAssertEqual(store.writes, [ids.0, ids.1], "逐行回写，顺序与读入一致")
        XCTAssertEqual(store.spans(id: ids.0), try target(legacyA), "落库的是迁移后的 spans")
        XCTAssertEqual(store.spans(id: ids.1), try target(legacyB))

        let payload = try XCTUnwrap(sink.writes.first?.payload)
        XCTAssertEqual(report.backupSHA256, NoteBodyMigrationRunner.sha256Hex(payload), "备份 sha256 与回执对得上")
        let snapshot = try backupBodies(payload)
        XCTAssertEqual(snapshot.map(\.body), [legacyA, legacyB], "备份载荷 = 迁移前**全量逐字**")
        XCTAssertEqual(snapshot.map(\.id), [ids.0.uuidString, ids.1.uuidString])
    }

    /// 判据 ②：二次迁移无 diff —— 不再回写、不再写备份，落库的 `spans` 逐字不变。
    func testSecondRunIsIdempotentAndWritesNoBackup() throws {
        let ids = (UUID(), UUID())
        let store = MemoryStore(rows: [(ids.0, legacyA), (ids.1, legacyB)])
        let sink = MemorySink()

        _ = try NoteBodyMigrationRunner.run(store: store, sink: sink)
        let afterFirst = store.spans(id: ids.0)

        let second = try NoteBodyMigrationRunner.run(store: store, sink: sink)

        XCTAssertEqual(second.outcome, .skipped, "判据 ②：二次迁移 = skipped")
        XCTAssertEqual(second.changed, 0, "第二跑没有要改的行")
        XCTAssertEqual(second.written, 0, "第二跑不写库")
        XCTAssertNil(second.backupName, "无变化 ⇒ 不写备份")
        XCTAssertEqual(sink.writes.count, 1, "盘上仍只有第一跑那一份备份")
        XCTAssertEqual(store.writes.count, 2, "第二跑没有再回写")
        XCTAssertEqual(store.spans(id: ids.0), afterFirst, "两跑之间 spans 逐字无 diff")
        XCTAssertEqual(second.mismatches, [])
    }

    /// 「只写变化行」：已经落了同一份 `spans` 的行不动（复跑与「迁到一半被打断」都走这条）。
    func testAlreadyMigratedRowIsNotWritten() throws {
        let migratedID = UUID()
        let legacyID = UUID()
        let store = MemoryStore(
            rows: [(migratedID, legacyA), (legacyID, legacyB)],
            spans: [migratedID: try target(legacyA)]
        )

        let report = try NoteBodyMigrationRunner.run(store: store, sink: MemorySink())

        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual(report.total, 2)
        XCTAssertEqual(report.changed, 1)
        XCTAssertEqual(report.written, 1)
        XCTAssertEqual(store.writes, [legacyID], "已迁移那一行没被碰")
    }

    /// **反例（判据没空转）**：落库面吞掉一段正文 ⇒ 复跑校验当场点名那一行。
    func testMismatchIsReportedWhenWriteLosesText() throws {
        let ids = (UUID(), UUID())
        let store = MemoryStore(rows: [(ids.0, legacyA), (ids.1, legacyB)])
        store.corrupt = { id, spans in
            id == ids.0 ? spans.replacingOccurrences(of: "第二行纯文本", with: "") : spans
        }

        let report = try NoteBodyMigrationRunner.run(store: store, sink: MemorySink())

        XCTAssertEqual(report.outcome, .partial, "有行对不上 ⇒ 不冒充成功")
        XCTAssertEqual(report.written, 2, "两条都写了")
        XCTAssertEqual(report.mismatches.count, 1, "吞字的那一行被点名（不是恒真判定）")
        XCTAssertTrue(report.mismatches[0].hasPrefix(ids.0.uuidString), "点的是吞字那行：\(report.mismatches)")
    }

    // MARK: - 落盘备份面

    /// 备份**绝不覆盖既有备份**：同名在盘 ⇒ 顺延 `-2` / `-3`（与 `notes.json.migrated` 同法）。
    func testFileSinkNeverOverwritesAnExistingBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-migration-sink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sink = FileNoteBodyMigrationSink(directory: directory)
        let first = try sink.write(fileName: NoteBodyMigrationRunner.backupFileName, payload: "第一份")
        let second = try sink.write(fileName: NoteBodyMigrationRunner.backupFileName, payload: "第二份")

        XCTAssertEqual(first.lastPathComponent, "note-bodies-backup.json")
        XCTAssertEqual(second.lastPathComponent, "note-bodies-backup-2.json")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "第一份", "既有备份没被顶掉")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "第二份")
    }

    // MARK: - 真库接线（`NoteLibrary` → `NoteDatabase`）

    private func makeDirectory(_ tag: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-migration-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 库不在盘 ⇒ 空读数，且**不顺手建库**（与 `load()` / `todos()` 同一条纪律）。
    func testMissingDatabaseIsANoOp() async throws {
        let directory = try makeDirectory("absent")
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent(NoteLibrary.fileName)

        let report = try await NoteLibrary(databaseURL: databaseURL)
            .migrateLegacyBodiesIfNeeded(backupDirectory: directory)

        XCTAssertEqual(report.outcome, .nothingToMigrate)
        XCTAssertTrue(report.nothingToDo)
        XCTAssertEqual(report.written, 0)
        XCTAssertNil(report.backupName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path), "缺库不该被建出来")
    }

    /// **端到端**（三条判据一次取证）：真库里的 v1 存量笔记（`upsert` 只写 `body` ⇒ `spans` 为 `NULL`）
    /// 迁移后 —— ① 正文逐字不变、`spans` 与迁移口径逐字一致、`mismatches` 空；② 第二跑 `written == 0`
    /// 且盘上仍只有一份备份；③ 备份在盘且载荷 = 迁移前原文。
    func testLibraryMigratesLegacyNotesEndToEnd() async throws {
        let directory = try makeDirectory("library")
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = NoteLibrary(databaseURL: directory.appendingPathComponent(NoteLibrary.fileName))

        let first = try await library.upsert(NoteDraft(title: "第一条", body: legacyA))
        let second = try await library.upsert(NoteDraft(title: "第二条", body: legacyB))

        // 迁移前的形状：两条都没有 v2 权威源（`upsert` 只写 `body` —— 这正是 v1 存量）
        let spansBeforeFirst = try await library.noteSpans(id: first.id)
        let spansBeforeSecond = try await library.noteSpans(id: second.id)
        XCTAssertNil(spansBeforeFirst)
        XCTAssertNil(spansBeforeSecond)

        let report = try await library.migrateLegacyBodiesIfNeeded(backupDirectory: directory)

        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual([report.total, report.changed, report.written], [2, 2, 2])
        XCTAssertEqual(report.mismatches, [], "判据 ①：迁移前后投影一致")
        XCTAssertEqual(report.failures, [])
        let backupURL = try XCTUnwrap(report.backupURL, "判据 ③：备份文件在盘")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        // 判据 ①：正文逐字没变；权威源换成 spans 且与迁移口径逐字一致
        let bodies = try await library.load().map(\.body).sorted()
        XCTAssertEqual(bodies, [legacyA, legacyB].sorted(), "迁移不许改正文")
        let storedFirst = try await library.noteSpans(id: first.id)
        let storedSecond = try await library.noteSpans(id: second.id)
        XCTAssertEqual(storedFirst, try target(legacyA), "第一条的权威源 = 迁移口径")
        XCTAssertEqual(storedSecond, try target(legacyB), "第二条的权威源 = 迁移口径")

        let backupText = try String(contentsOf: backupURL, encoding: .utf8)
        XCTAssertEqual(report.backupSHA256, NoteBodyMigrationRunner.sha256Hex(backupText), "回执 sha256 = 盘上那一份")
        let snapshot = try backupBodies(backupText)
        XCTAssertEqual(Set(snapshot.map(\.body)), Set([legacyA, legacyB]), "备份是迁移前的原文")

        // 判据 ②：二次迁移无 diff
        let secondRun = try await library.migrateLegacyBodiesIfNeeded(backupDirectory: directory)
        XCTAssertEqual(secondRun.outcome, .skipped, "判据 ②：二次迁移 = skipped")
        XCTAssertEqual(secondRun.total, 0, "已迁移的行不再落在待迁移面上")
        XCTAssertEqual(secondRun.written, 0)
        XCTAssertNil(secondRun.backupName, "无变化 ⇒ 不写第二份备份")
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("note-bodies-backup") }
        XCTAssertEqual(backups, ["note-bodies-backup.json"], "盘上只有那一份迁移前备份")
    }

    /// 生效的 `DOYAH_NOTES_DIR` 覆盖 ⇒ **主动让路**（一个字不写），与既有引擎迁移同一条纪律。
    func testEnvironmentOverrideMakesWay() async throws {
        let directory = try makeDirectory("override")
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = NoteLibrary(databaseURL: directory.appendingPathComponent(NoteLibrary.fileName))
        let note = try await library.upsert(NoteDraft(title: "存量", body: legacyA))

        let report = try await library.migrateLegacyBodiesIfNeeded(
            environment: ["DOYAH_NOTES_DIR": directory.path]
        )

        XCTAssertEqual(report.outcome, .skippedOverridden)
        XCTAssertEqual(report.written, 0)
        XCTAssertNil(report.backupName)
        let spansAfter = try await library.noteSpans(id: note.id)
        XCTAssertNil(spansAfter, "让路 ⇒ 权威源一个字没动")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(files.contains { $0.hasPrefix("note-bodies-backup") }, "让路 ⇒ 没有备份落盘")
    }
}
