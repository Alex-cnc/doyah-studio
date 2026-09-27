import Foundation

// `FR-PLUG-08` 的**一次性迁移**：把旧格式的笔记库（`notes.json`）搬进 SQLite。
//
// 纪律照抄 L-03 那一套（`NoteStoreMigration`，搬数据家时演练过一遍），因为这一类代码的失败模式
// 只有一个：**把用户唯一的笔记库弄丢**。五条口径：
//   1. **只搬一次、幂等**：目标库已存在就**一个字节都不动**，如实报 `skippedTargetExists`
//      —— 那是更新的那一份（判断"要不要搬"靠文件名不同：`notes.json` vs `notes.sqlite3`）；
//   2. **先建后换名（原子）**：在 `notes.sqlite3.incoming` 上把新库**建完整**（schema + 全部笔记 + 读回核对），
//      全部核对过了才 `moveItem` 换名 —— 中途崩了，目标位置**没有**任何东西，不会留一个半截库；
//   3. **坏文件回退并报告**：旧文件读不出来时**原地保留**、目标不建，如实报 `legacyUnreadable`
//      （读不懂就别搬）；
//   4. **旧文件不删**：搬完移到 `notes.json.migrated`（同名顺延 `-2`），留一份可回溯的备份；
//   5. **有 `DOYAH_NOTES_DIR` 覆盖时不迁**：那是脚本把数据挪到临时目录用的，而"旧位置"仍是真实用户目录，
//      照迁就会把真实笔记搬进临时目录 —— 宁可不动。
//
// 一条**有意为之的规范化**：标签在表里是集合语义（主键 `(note_id, tag)` 本来就禁止重复），
// 所以迁移会把标签**去重并排序**；读回核对时两边都按同一口径规范化后再比 —— 否则「JSON 里标签写重了一次」
// 会被报成迁移失败，而它其实不是数据丢失。

/// `notes.json` → `notes.sqlite3` 的一次性迁移。
public enum NoteLibraryMigration {

    public enum Outcome: String, Equatable, Sendable {
        /// 旧文件不存在（或两边指到同一个文件）：没有要搬的东西。
        case nothingToMigrate
        /// 目标库已存在 —— 不动任何一个字节。
        case skippedTargetExists
        /// 生效的 `DOYAH_NOTES_DIR` 覆盖把数据指到了别处，迁移主动让路。
        case skippedOverridden
        case migrated
        /// 旧文件读不出来：原地保留、目标不建。
        case legacyUnreadable
        /// 建新库失败（或写后核对不一致）：目标位置什么都没有，旧文件仍在原处。
        case writeFailed
    }

    public struct Report: Equatable, Sendable {
        public var outcome: Outcome
        public var jsonURL: URL
        public var databaseURL: URL
        /// 搬过去的条数（只有 `migrated` 非零；旧库里本来就是 0 条时也是 0）。
        public var noteCount: Int
        /// 旧文件搬完后的落点（没能搬走时为 nil）。
        public var backupURL: URL?
        /// 未能迁移的原因（**机器可读原文，不翻译** —— 界面文案由语言表按 `outcome` 组织）。
        public var failure: String?

        public var didMigrate: Bool { outcome == .migrated }

        /// 需要如实告诉用户：旧文件读不出来 / 新库建不起来。
        public var needsAttention: Bool {
            outcome == .legacyUnreadable || outcome == .writeFailed
        }
    }

    /// 建库时的中间文件名（同目录内换名，因此是**同卷重命名**：原子、不会跨设备拷贝失败）。
    public static let incomingSuffix = ".incoming"

    /// 搬完后的旧文件在新数据家里的名字。
    public static var backupFileName: String { NoteStore.fileName + ".migrated" }

    /// 按**默认位置**迁移（界面打开笔记时调一次）。
    ///
    /// 生效的 `DOYAH_NOTES_DIR` 覆盖会让本方法**主动让路**（见文件头第 5 条）。
    public static func migrateIfNeeded(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Report {
        let jsonURL = NoteStore.defaultFileURL(environment: environment)
        let databaseURL = NoteDatabase.defaultFileURL(environment: environment)
        if let override = environment["DOYAH_NOTES_DIR"], !override.isEmpty {
            return Report(
                outcome: .skippedOverridden,
                jsonURL: jsonURL,
                databaseURL: databaseURL,
                noteCount: 0
            )
        }
        return migrateIfNeeded(jsonURL: jsonURL, databaseURL: databaseURL)
    }

    /// 指定位置迁移（探针与单测走这一条，免得在真实数据目录里留下痕迹）。
    public static func migrateIfNeeded(
        jsonURL: URL,
        databaseURL: URL,
        fileManager: FileManager = .default
    ) -> Report {
        var report = Report(
            outcome: .nothingToMigrate,
            jsonURL: jsonURL,
            databaseURL: databaseURL,
            noteCount: 0
        )

        // 两边指到同一个文件（环境变量拼出来的情形）：没有"搬"这回事。
        guard jsonURL.standardizedFileURL != databaseURL.standardizedFileURL else { return report }
        // 目标库已存在：那是更新的那一份，**一个字节都不动**（幂等的落点）。
        guard !fileManager.fileExists(atPath: databaseURL.path) else {
            report.outcome = .skippedTargetExists
            return report
        }
        // 旧文件不存在：第一次用，没有要搬的东西。
        guard fileManager.fileExists(atPath: jsonURL.path) else { return report }

        // 读旧文件：直接解 JSON —— **不经** `NoteStore`（它是 actor，`loadOutcome()` 要 `await`，
        // 而迁移是"打开笔记时同步跑一次"的动作）。日期策略必须与 `NoteStore.save` **成对**
        // （两边都是 `.iso8601`），否则会静默解不出来 —— 这正是 L-03 那轮实测踩到的坑。
        guard let data = try? Data(contentsOf: jsonURL) else {
            report.outcome = .legacyUnreadable
            report.failure = "the legacy notes file exists but cannot be read"
            return report
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let expected: [Note]
        do {
            expected = try decoder.decode([Note].self, from: data)
        } catch {
            report.outcome = .legacyUnreadable
            report.failure = String(describing: error)
            return report
        }

        let incomingURL = URL(fileURLWithPath: databaseURL.path + incomingSuffix)
        // `.incoming` 是我们自己的中间件（上次失败留下的），删掉不涉及用户数据。
        try? fileManager.removeItem(at: incomingURL)
        do {
            try fileManager.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let database = try NoteDatabase(path: incomingURL.path)
            // 中间库切成**单文件日志**：换名只搬主库文件，WAL 的 `-wal` / `-shm` 侧车会留在原地，
            // 那样交出去的就是"少半份"的库。交付之后 `NoteDatabase` 打开时会再切成 WAL。
            try database.switchToSingleFileJournal()
            for note in expected {
                try database.upsert(note)
            }
            // 读回核对：**逐字段**比（时间也按存进去的 REAL 秒比回来），不比就不知道搬全了没有。
            let written = try database.notes()
            try database.close()
            guard Self.normalized(written) == Self.normalized(expected) else {
                throw NoteStorageFailure.snapshotMismatch(
                    "read back \(written.count) note(s) that do not match the \(expected.count) migrated"
                )
            }
        } catch {
            // 建库失败：清掉中间件（目标位置没有东西），旧文件**原地不动**，数据不丢。
            try? fileManager.removeItem(at: incomingURL)
            report.outcome = .writeFailed
            report.failure = String(describing: error)
            return report
        }

        do {
            try fileManager.moveItem(at: incomingURL, to: databaseURL)
        } catch {
            try? fileManager.removeItem(at: incomingURL)
            report.outcome = .writeFailed
            report.failure = String(describing: error)
            return report
        }

        report.outcome = .migrated
        report.noteCount = expected.count
        // 旧文件移到新数据家留一份备份（**不删**）：搬不动就如实说 —— 新库已经好了，数据不丢。
        report.backupURL = try? NoteStoreMigration.moveAside(
            jsonURL,
            into: databaseURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        return report
    }

    /// 读回核对前的规范化：标签按**集合**口径（去重 + 排序 + 去空），其余字段原样。
    static func normalized(_ notes: [Note]) -> [Note] {
        notes.map { note in
            var copy = note
            copy.tags = Array(Set(note.tags.filter { !$0.isEmpty })).sorted()
            return copy
        }
        .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

extension NoteDatabase {

    /// 笔记库的**默认位置**：与旧格式同一个数据家（`FR-PLUG-04` 已把数据家搬到独立目录），
    /// 只是文件名不同。覆盖变量与 `NoteStore.defaultDirectory` 同一路数。
    public static func defaultDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        NoteStore.defaultDirectory(environment: environment)
    }

    public static func defaultFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        defaultDirectory(environment: environment)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    public static func defaultStore(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> NoteDatabase {
        try NoteDatabase(path: defaultFileURL(environment: environment).path)
    }

    /// 快照的默认落点（与库同目录的 `snapshots/` 子目录）。
    public static func defaultSnapshotURL(
        at date: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        defaultDirectory(environment: environment)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(snapshotFileName(at: date), isDirectory: false)
    }
}
