import Foundation

/// 定时 agent 的落盘（`FR-AI-27` ⑤「每次触发与结果留痕」的存储半）。
///
/// **与 `FR-AI-06` 的数据任务同一套形状**（「不另造一套」是条文原话，也是这份文件的全部理由）：
///   · 条目存 `agent-schedules.json` —— 全量重写、`prettyPrinted` + `sortedKeys` + atomic；
///   · 执行历史追加到 `agent-schedule-runs.jsonl` —— 只追加、写入频繁，避免每次重写整份文件；
///   · 目录 = `DoyahIdentity.applicationSupportDirectoryName`（与其余本机数据同一处，不另开文件体系）。
///
/// **失败不静默**在存储这一层也是形状问题：`appendRun` 收一条 `failed` 而给不出原因 ⇒ **抛错、一个字不落盘**
/// （判据读回来的账才有意义 —— 一条「悄悄失败」的记录在盘上根本写不进去）。
public actor AgentScheduleStore {

    /// 与 `DataTaskStore.shared` 同款：App 侧直接用这一份，测试传 `directoryURL` 走临时目录。
    public static let shared = AgentScheduleStore()

    private let entriesURL: URL
    private let runsURL: URL
    private let encoder: JSONEncoder
    /// **JSONL 专用**：一行必须真的是一行 —— 条目那份 `encoder` 带 `prettyPrinted`，
    /// 拿它写历史会让每条记录被折成多行，读回来时逐行解码全失败（本文件的第一版判据就是这么被咬住的）。
    private let lineEncoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL? = nil) {
        let baseURL: URL
        if let directoryURL {
            baseURL = directoryURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            baseURL = applicationSupport.appendingPathComponent(
                DoyahIdentity.applicationSupportDirectoryName,
                isDirectory: true
            )
        }

        self.entriesURL = baseURL.appendingPathComponent("agent-schedules.json", isDirectory: false)
        self.runsURL = baseURL.appendingPathComponent("agent-schedule-runs.jsonl", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let lineEncoder = JSONEncoder()
        lineEncoder.dateEncodingStrategy = .iso8601
        self.lineEncoder = lineEncoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func entriesFileLocation() -> URL { entriesURL }
    public func runsFileLocation() -> URL { runsURL }

    // MARK: - 条目

    public func entries() throws -> [AgentScheduleEntry] {
        guard FileManager.default.fileExists(atPath: entriesURL.path) else { return [] }
        do {
            return try decoder.decode([AgentScheduleEntry].self, from: Data(contentsOf: entriesURL))
        } catch {
            throw AppError.persistence(error.localizedDescription)
        }
    }

    /// 新增或替换（按 `id` 匹配）一条。`updatedAt` 由这里统一改写 —— 调用方不必各记一次。
    @discardableResult
    public func save(_ entry: AgentScheduleEntry) throws -> AgentScheduleEntry {
        var stored = entry
        stored.updatedAt = Date()
        var all = try entries()
        if let index = all.firstIndex(where: { $0.id == entry.id }) {
            all[index] = stored
        } else {
            all.append(stored)
        }
        try write(all)
        return stored
    }

    /// 停用 / 启用（`FR-AI-27` 验收要点 ④「停用后不再排期」的那一个开关）。
    ///
    /// 只翻 `isEnabled` 一格，**碰不到** `createdAt`（周期格点由「创建时刻」推，翻开关不该让格点漂）。
    @discardableResult
    public func setEnabled(_ isEnabled: Bool, id: UUID) throws -> AgentScheduleEntry? {
        var all = try entries()
        guard let index = all.firstIndex(where: { $0.id == id }) else { return nil }
        all[index].isEnabled = isEnabled
        all[index].updatedAt = Date()
        try write(all)
        return all[index]
    }

    /// 删条目。**执行历史跟着删** —— 留下的历史指向一个不存在的条目，界面只能显示「未知条目」。
    public func delete(id: UUID) throws {
        var all = try entries()
        guard all.contains(where: { $0.id == id }) else { return }
        all.removeAll { $0.id == id }
        try write(all)
        let remaining = try runs().filter { $0.entryID != id }
        try writeRuns(remaining)
    }

    // MARK: - 执行历史（⑤）

    /// 追加一条留痕。`failed` 而无原因 ⇒ 抛 `AgentScheduleLedgerError.failureWithoutDetail`，**盘上不动**。
    public func appendRun(_ record: AgentScheduleRunRecord) throws {
        var ledger = AgentScheduleLedger(records: try runs())
        try ledger.record(record)
        try append(record)
    }

    /// 把一条 `running` 收成终态（成功 / 失败 / 跳过）。同样要求失败带原因。
    /// 收尾是**重写整份 JSONL**（历史是「追加」语义，但终态收尾必须改中间那一条）。
    @discardableResult
    public func finishRun(
        id: UUID,
        status: TaskRunRecord.Status,
        at: Date,
        detail: String? = nil,
        executedActions: [String]? = nil,
        withheldActions: [String]? = nil
    ) throws -> AgentScheduleRunRecord {
        var ledger = AgentScheduleLedger(records: try runs())
        let updated = try ledger.finish(
            id: id,
            status: status,
            at: at,
            detail: detail,
            executedActions: executedActions,
            withheldActions: withheldActions
        )
        try writeRuns(ledger.records)
        return updated
    }

    public func runs() throws -> [AgentScheduleRunRecord] {
        guard FileManager.default.fileExists(atPath: runsURL.path) else { return [] }
        let text = try String(contentsOf: runsURL, encoding: .utf8)
        var records: [AgentScheduleRunRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8) else { continue }
            // 认不出的行**跳过而不是整份读失败**：历史是追加文件，一行坏掉不该让整本账读不出来。
            if let record = try? decoder.decode(AgentScheduleRunRecord.self, from: data) {
                records.append(record)
            }
        }
        return records
    }

    public func ledger() throws -> AgentScheduleLedger {
        AgentScheduleLedger(records: try runs())
    }

    /// 最近一次**成功**触发的时刻 —— 喂给 `AgentSchedulePlanner.decision(..., lastRun:)`。
    public func lastSuccessfulRun(for entryID: UUID) throws -> Date? {
        try ledger().lastSuccessfulRun(for: entryID)
    }

    // MARK: - 内部

    private func write(_ entries: [AgentScheduleEntry]) throws {
        do {
            try FileManager.default.createDirectory(
                at: entriesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(entries).write(to: entriesURL, options: [.atomic])
        } catch {
            throw AppError.persistence(error.localizedDescription)
        }
    }

    private func append(_ record: AgentScheduleRunRecord) throws {
        do {
            try FileManager.default.createDirectory(
                at: runsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var line = try lineEncoder.encode(record)
            line.append(0x0A)
            if FileManager.default.fileExists(atPath: runsURL.path) {
                let handle = try FileHandle(forWritingTo: runsURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: runsURL, options: [.atomic])
            }
        } catch {
            throw AppError.persistence(error.localizedDescription)
        }
    }

    private func writeRuns(_ records: [AgentScheduleRunRecord]) throws {
        do {
            try FileManager.default.createDirectory(
                at: runsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            var text = ""
            for record in records {
                var line = try lineEncoder.encode(record)
                line.append(0x0A)
                text += String(decoding: line, as: UTF8.self)
            }
            try text.write(to: runsURL, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.persistence(error.localizedDescription)
        }
    }
}
