import Crypto
import Foundation

// `FR-RT-11` 的**一次性迁移**：把 v1 存量笔记的正文（Markdown 文本、`spans` 列还是 `NULL`）搬成
// v2 的权威源（span 树 JSON）。片 `WY-2b`，服务锚点 `T-20261008-050`。
//
// **依据**（逐条核过，不改写）：人类主人 2026-10-08 拍板 `DR-09` 第三次改判 —— 笔记正文权威源 =
// 所见即所得富文本 `spans`（三书已改：SRS 新增 `FR-RT-10` / `FR-RT-11` · 概设 `ADR-11`）。
// `FR-RT-11` 的原文判据三条 = ① 迁移前后 `toPlainText` 一致；② 二次迁移无 diff；③ 备份文件在盘。
// 本文件就按这三条自证；口径与安卓侧同形（`NoteBodyMigrationRunner.kt` · 片 `W-WYS-02b-core`：
// 只写变化行 + 幂等 / 可复跑 + 只写一次备份且是迁移前全量）。
//
// **三条纪律**（照抄 `NoteLibraryMigration` 的失败模式分析 —— 这一类代码只有一种坏法：
// 把用户唯一的笔记正文弄丢）：
//   1. **备份先于回写**：本次有变化 ⇒ 先把「迁移前**全量**逐字快照」落到盘上，再逐条回写。
//      回写中途出事时，盘上已经有一份迁移前的原文；
//   2. **备份绝不覆盖既有备份**：同名已有 ⇒ 顺延 `-2` / `-3`（与 `notes.json.migrated` 同法）——
//      「迁移前」的那一份任何情况下都不许被后来的一次迁移顶掉；
//   3. **逐条失败不阻断整批**：某条写不进去只记进 `failures`（如实报），其余照写 ——
//      半途整体回滚会把已经迁移好的行也退掉，反而更难收拾。
//
// **绝不自造第二套解析**：一条正文的迁移一律经既有 `NoteBody(version:markdown:sidecar:)` +
// `migrated()`（其内部又只经既有 `NoteBodyProjection`）；本文件自己不解析任何 Markdown。

/// 迁移的落库面（**存储无关**）：底层是 SQLite / 文件 / 内存一概不问 —— 与安卓侧 `NoteBodyStore`
/// 同形。端侧那一层负责把它接到 `NoteDatabase`（见 `NoteLibrary.migrateLegacyBodies`）。
public protocol NoteBodyMigrationStore {
    /// 读**待迁移面**的全量行（macOS 侧 = `spans IS NULL` 的笔记；见 `NoteDatabase.legacyBodyRows`）。
    func legacyRows() throws -> [NoteBodyMigrationRunner.Row]
    /// 读一行**当前已落库**的 `spans`（`nil` = 还没有 v2 权威源）。
    func storedSpans(id: UUID) throws -> String?
    /// 库里**已经有 v2 权威源**的行数（`spans IS NOT NULL`）。
    ///
    /// 只为一件事：把「这库本来就没得迁（空库 / 没有笔记）」与「都已经迁过了 ⇒ `skipped`」分开
    /// （`FR-RT-11` 判据 ② 点名的就是后者的字面结论）。别拿它做别的判断。
    func alreadyMigratedCount() throws -> Int
    /// 把迁移后的 `spans` + 它的 `body` 投影写回该行（只对判定为「要改」的行走这里）。
    @discardableResult func writeSpans(_ spans: String, body: String, id: UUID) throws -> Int
}

/// 备份落地面：执行器把「迁移前全量」载荷（文件名 + 逐字内容）交给它。
public protocol NoteBodyMigrationSink {
    func write(fileName: String, payload: String) throws -> URL
}

/// 落盘版备份面：写到指定目录；**同名已有则顺延 `-2` / `-3`**，绝不覆盖既有备份。
public struct FileNoteBodyMigrationSink: NoteBodyMigrationSink {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func write(fileName: String, payload: String) throws -> URL {
        let url = Self.availableURL(directory: directory, fileName: fileName)
        try Data(payload.utf8).write(to: url, options: .atomic)
        return url
    }

    /// 顺延规则：`x.json` 在盘 ⇒ `x-2.json` ⇒ `x-3.json` …（与 `notes.json.migrated` 同法）。
    static func availableURL(directory: URL, fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"
            candidate = directory.appendingPathComponent(name)
            n += 1
        }
        return candidate
    }
}

/// 正文迁移落库执行器：读待迁移面 → 逐条迁移 → 只回写改过的 → 先落备份 → 复跑校验。
public enum NoteBodyMigrationRunner {

    /// 备份文件名（确定性：一次迁移写一份；第二跑无 diff 便不再写）。
    public static let backupFileName = "note-bodies-backup.json"

    /// 一条待迁移的正文行：`id` = 笔记 uuid，`body` = 落库的正文文本（v1 形态：Markdown）。
    public struct Row: Equatable, Sendable {
        public var id: UUID
        public var body: String

        public init(id: UUID, body: String) {
            self.id = id
            self.body = body
        }
    }

    /// 一次迁移的**结论**（与 `NoteLibraryMigration.Outcome` 同形：调用点按它分支，不去读计数）。
    public enum Outcome: String, Equatable, Sendable {
        /// 待迁移面空的（库里没有 `spans` 为 `NULL` 的笔记 / 库还不存在）：没有要搬的东西。
        case nothingToMigrate
        /// 面非空但**一行都不用改**（都已迁过）—— 这就是复跑的第二跑（`FR-RT-11` 判据 ②）。
        case skipped
        /// 真搬了（`written > 0`）。
        case migrated
        /// 搬了但有行没成功 / 迁移前后投影对不上（`failures` / `mismatches` 非空）—— 如实报，别当成功。
        case partial
        /// 生效的 `DOYAH_NOTES_DIR` 覆盖把数据指到了别处，迁移主动让路（见文件头「纪律」）。
        case skippedOverridden
    }

    /// 一次迁移的读数（一次搬完的形状 = `total == changed == written`）。
    public struct Report: Equatable, Sendable {
        /// 结论（调用点按它分支）。
        public var outcome: Outcome
        /// 待迁移面上读到的行数（全量）。
        public var total: Int
        /// 判定为「要改」的行数（已落 `spans` 且与目标逐字相同的行不算）。
        public var changed: Int
        /// 实际回写成功的行数。
        public var written: Int
        /// 本次写的备份文件名（无变化 ⇒ 未写备份 ⇒ nil）。
        public var backupName: String?
        /// 备份落点。
        public var backupURL: URL?
        /// 备份内容的 `sha256`（回执里要能对得上；未写备份时为 nil）。
        public var backupSHA256: String?
        /// **复跑校验读数**：回写后读回权威源、其投影与迁移前原文不一致的行（判据 ①；应为空）。
        public var mismatches: [String]
        /// 逐条失败原因（读不懂 / 写不进去的行；不阻断整批）。
        public var failures: [String]

        public var nothingToDo: Bool { total == 0 }
    }

    /// 一条正文的迁移：legacy Markdown → v2 `spans`（JSON）。
    ///
    /// 只走既有面：`NoteBody(version: 1, markdown:)`（v1 兼容构造，当场投影成 spans）→ `migrated()`
    /// （版本号落 `currentVersion`）→ `JSONEncoder`（编的是 `NoteBody` 自己的 `CodingKeys`：
    /// `version` / `spans`）。`sortedKeys` 是为了判据 ②：同一个 span 树在任何一次迁移里都编出
    /// **同一串字节**，两次迁移的 diff 才可比。
    public static func migrate(body: String) throws -> (spans: String, body: String) {
        let migrated = try NoteBody(version: 1, markdown: body, sidecar: []).migrated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (spans: String(decoding: try encoder.encode(migrated), as: UTF8.self), body: migrated.body)
    }

    /// 迁移前**全量逐字**快照：`[{"id":"…","body":"…"}, …]` —— 每条的 `body` 与入参逐字相同。
    public static func backupPayload(rows: [Row]) throws -> String {
        struct Snapshot: Codable {
            var id: String
            var body: String
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let payload = rows.map { Snapshot(id: $0.id.uuidString, body: $0.body) }
        return String(decoding: try encoder.encode(payload), as: UTF8.self)
    }

    /// 跑一遍全量迁移。**任何一条坏了都只记账**（`failures` / `mismatches`），不抛、不整体回滚。
    public static func run(store: NoteBodyMigrationStore, sink: NoteBodyMigrationSink) throws -> Report {
        let rows = try store.legacyRows()
        var failures: [String] = []
        var pending: [(row: Row, target: (spans: String, body: String))] = []

        for row in rows {
            do {
                let target = try migrate(body: row.body)
                // 只写变化行：已落 `spans` 且与目标逐字相同 ⇒ 这一行不动（复跑的第二跑走这里）。
                if try store.storedSpans(id: row.id) == target.spans { continue }
                pending.append((row, target))
            } catch {
                failures.append("\(row.id.uuidString): 迁移失败 \(error)")
            }
        }

        var backupName: String?
        var backupURL: URL?
        var backupSHA256: String?
        if !pending.isEmpty {
            // 顺序硬要求：**先落备份，再回写**（反过来的话，回写中途出事就没有迁移前的原文了）。
            let payload = try backupPayload(rows: rows)
            let url = try sink.write(fileName: backupFileName, payload: payload)
            backupName = url.lastPathComponent
            backupURL = url
            backupSHA256 = Self.sha256Hex(payload)
        }

        var written = 0
        var mismatches: [String] = []
        for (row, target) in pending {
            do {
                try store.writeSpans(target.spans, body: target.body, id: row.id)
                written += 1
            } catch {
                failures.append("\(row.id.uuidString): 回写失败 \(error)")
                continue
            }
            // **复跑校验（判据 ①）**：不拿迁移器的自述当真 —— 读回盘上的权威源，把它的投影与
            // **迁移前的原文**逐字比；不一致的行如实点名，不静默。
            guard let stored = try? store.storedSpans(id: row.id),
                  let projected = projectedBody(spansJSON: stored) else {
                mismatches.append("\(row.id.uuidString): 回写后读不回 spans")
                continue
            }
            if projected != row.body {
                mismatches.append("\(row.id.uuidString): 迁移前后投影不一致（原文 \(row.body.count) 字 / 投影 \(projected.count) 字）")
            }
        }

        let outcome: Outcome
        if !failures.isEmpty || !mismatches.isEmpty {
            outcome = .partial
        } else if rows.isEmpty {
            // 面空：库本来就没有待迁的正文 = `nothingToMigrate`；都迁过了 = `skipped`（判据 ②）。
            outcome = ((try? store.alreadyMigratedCount()) ?? 0) > 0 ? .skipped : .nothingToMigrate
        } else if pending.isEmpty {
            outcome = .skipped
        } else {
            outcome = .migrated
        }

        return Report(
            outcome: outcome,
            total: rows.count,
            changed: pending.count,
            written: written,
            backupName: backupName,
            backupURL: backupURL,
            backupSHA256: backupSHA256,
            mismatches: mismatches,
            failures: failures
        )
    }

    /// 一串 `spans` JSON → 它的投影（读不回来时为 nil，由调用方如实记账）。
    public static func projectedBody(spansJSON: String) -> String? {
        guard let data = spansJSON.data(using: .utf8),
              let body = try? JSONDecoder().decode(NoteBody.self, from: data) else { return nil }
        return body.body
    }

    /// 没搬任何东西的那两种结论的读数（`nothingToMigrate` / `skippedOverridden`）。
    public static func emptyReport(outcome: Outcome) -> Report {
        Report(
            outcome: outcome, total: 0, changed: 0, written: 0,
            backupName: nil, backupURL: nil, backupSHA256: nil, mismatches: [], failures: []
        )
    }

    /// 备份载荷的 `sha256`（十六进制小写）。回执里要能对得上，所以不靠调用方另算一遍。
    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
