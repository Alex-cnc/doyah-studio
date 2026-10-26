import Foundation

/// 多端一致性（`FR-AGT-UX-SYNC-001`）的**契约层**：同一会话在桌面与手机上看到的消息、
/// 审批与结论一致 —— **壳不同，内容同**。
///
/// 这一层只回答三件在验收里会被追问的事，**不碰网络**（桌面 ↔ 手机的传输、鉴权、心跳
/// 由传输层做，本端没有第二端可连）：
///
/// ① **同一份内容**：消息以**中性载荷**（角色 + 正文 + 来源端 + 序号）存在一条共享日志里，
///    两个端读的是同一批记录 ⇒ 任一端发出的话，另一端按游标取就能看到；合并按
///    `(序号, id, 正文)` 全序，**幂等且可交换**（`merged(a,b) == merged(b,a)`），
///    所以两个端各自合并出来的顺序不会一处一样一处不一样。
/// ② **审批只需一次**：决定按 `requestID` 落一条账，谁先决谁生效；另一端再来一次
///    ⇒ 回 `alreadyDecided`（**不覆盖、不改时间、不改决定人**），且它的待问清单里
///    这个 request 已经不在 ⇒ 另一端不会重复问同一个人同一件事。
/// ③ **断线重连按游标补齐，坏游标只许全量重同步**：`batch(since:)` 给「游标之后的新消息」；
///    游标为负或大于日志末序号 ⇒ 回 `fullResync` 并**给原因**，绝不当成「没有新消息」
///    静默返回空批 —— 那是最坏的一种丢消息。
///
/// 边界（**本轮没做的那一半，如实登记**）：没有第二端、也没有服务端转发 ⇒ 这里钉的是
/// 「传输怎么接都得成立」的语义；真跨设备联调只能人工点验。

/// 端的身份（只用来判「这条是谁发的 / 谁决的」，不参与内容投影）。
public enum AgentSyncEnd: String, Codable, Equatable, Sendable, CaseIterable {
    case desktop
    case mobile
}

/// 消息角色（中性词，两端同一套）。
public enum AgentSyncRole: String, Codable, Equatable, Sendable, CaseIterable {
    case user
    case assistant
}

/// 共享会话日志里的一条消息。
public struct AgentSyncMessage: Codable, Equatable, Sendable, Identifiable {
    /// 全局唯一消息 id（端侧生成后带上；去重键）。
    public var id: String
    public var sessionID: String
    /// 会话内单调序号，**由日志分配**（1 起连续）。`0` = 还没进日志（端侧刚造出来）。
    public var sequence: Int
    public var origin: AgentSyncEnd
    public var role: AgentSyncRole
    public var text: String
    public var createdAt: Date

    public init(id: String, sessionID: String, sequence: Int = 0,
                origin: AgentSyncEnd, role: AgentSyncRole, text: String,
                createdAt: Date = Date()) {
        self.id = id
        self.sessionID = sessionID
        self.sequence = sequence
        self.origin = origin
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

/// 一次追加的结果。三种都要能被调用方区分 —— 尤其 `conflict`：同一个 id 带着不同正文
/// 回来了，说明有一端在改历史，**不许静默覆盖**。
public enum AgentSyncAppendOutcome: Equatable, Sendable {
    /// 新消息，已分配序号。
    case appended(AgentSyncMessage)
    /// 同 id 同内容，重复投递（重连补发的常态）⇒ 不新增、原样返回已落的那条。
    case duplicate(AgentSyncMessage)
    /// 同 id **不同内容** ⇒ 保留先落的那条，并把冲突如实报出来。
    case conflict(existing: AgentSyncMessage)

    public var message: AgentSyncMessage {
        switch self {
        case .appended(let m), .duplicate(let m): return m
        case .conflict(let m): return m
        }
    }
}

/// 增量批为什么要全量重同步（**原因必须给**，不许只说「重新同步一下」）。
public enum AgentSyncResyncReason: String, Codable, Equatable, Sendable {
    /// 游标为负 —— 不是本条日志发出来的东西。
    case unknownCursor
    /// 游标大于本端日志末序号 —— 对端把别的日志的游标拿过来了（或本端日志被回退过）。
    case aheadOfLog
}

/// 一次增量同步的结果。
public struct AgentSyncBatch: Equatable, Sendable {
    public var sessionID: String
    public var messages: [AgentSyncMessage]
    /// 批后游标（补完就到这儿；下次 `since:` 传它）。
    public var cursor: Int
    /// `true` ⇒ 调用方**必须**丢掉本地增量缓存、按本批全量重建。
    public var fullResync: Bool
    public var reason: AgentSyncResyncReason?

    public init(sessionID: String, messages: [AgentSyncMessage], cursor: Int,
                fullResync: Bool = false, reason: AgentSyncResyncReason? = nil) {
        self.sessionID = sessionID
        self.messages = messages
        self.cursor = cursor
        self.fullResync = fullResync
        self.reason = reason
    }
}

/// 共享会话日志（每条会话一个追加式 JSONL）。**序号只由这里分配**，端侧不自增。
public struct AgentSyncJournal: Sendable {

    public var directory: URL
    public init(directory: URL) { self.directory = directory }

    /// 会话号会进文件名 ⇒ 只留字母数字与短横，其余换下划线（不会拼出跨目录路径）。
    private func fileURL(sessionID: String) -> URL {
        let safe = String(sessionID.map { ch in
            (ch.isLetter || ch.isNumber || ch == "-") ? ch : "_"
        })
        return directory.appendingPathComponent("sync-\(safe).jsonl")
    }

    public func messages(sessionID: String) -> [AgentSyncMessage] { load(sessionID: sessionID) }

    /// 本端已知的末序号（空日志 = 0）。
    public func cursor(sessionID: String) -> Int {
        load(sessionID: sessionID).last?.sequence ?? 0
    }

    // MARK: - 写

    /// 追加一条（序号由日志给：末序号 + 1）。同一 id 重复投递不新增。
    @discardableResult
    public func append(id: String, sessionID: String, origin: AgentSyncEnd,
                       role: AgentSyncRole, text: String,
                       createdAt: Date = Date()) throws -> AgentSyncAppendOutcome {
        try append(AgentSyncMessage(id: id, sessionID: sessionID, origin: origin,
                                    role: role, text: text, createdAt: createdAt))
    }

    @discardableResult
    public func append(_ message: AgentSyncMessage) throws -> AgentSyncAppendOutcome {
        var all = load(sessionID: message.sessionID)
        if let existing = all.first(where: { $0.id == message.id }) {
            let sameContent = existing.role == message.role && existing.text == message.text
            return sameContent ? .duplicate(existing) : .conflict(existing: existing)
        }
        var stored = message
        stored.sequence = (all.last?.sequence ?? 0) + 1
        all.append(stored)
        try save(all, sessionID: message.sessionID)
        return .appended(stored)
    }

    // MARK: - 读（增量 / 重同步）

    /// 游标之后的增量；游标不可信 ⇒ **全量 + 具名原因**（绝不当成「没有新消息」）。
    public func batch(sessionID: String, since cursor: Int) -> AgentSyncBatch {
        let all = load(sessionID: sessionID)
        let last = all.last?.sequence ?? 0
        if cursor < 0 {
            return AgentSyncBatch(sessionID: sessionID, messages: all, cursor: last,
                                  fullResync: true, reason: .unknownCursor)
        }
        if cursor > last {
            return AgentSyncBatch(sessionID: sessionID, messages: all, cursor: last,
                                  fullResync: true, reason: .aheadOfLog)
        }
        return AgentSyncBatch(sessionID: sessionID,
                              messages: all.filter { $0.sequence > cursor },
                              cursor: last, fullResync: false, reason: nil)
    }

    private func load(sessionID: String) -> [AgentSyncMessage] {
        guard let data = try? Data(contentsOf: fileURL(sessionID: sessionID)),
              let body = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return body.split(separator: "\n").compactMap { line in
            try? decoder.decode(AgentSyncMessage.self, from: Data(line.utf8))
        }
    }

    private func save(_ messages: [AgentSyncMessage], sessionID: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let body = messages.compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
        try Data((body.isEmpty ? "" : body + "\n").utf8)
            .write(to: fileURL(sessionID: sessionID), options: .atomic)
    }
}

/// 审批决定的一条账（按 `requestID` 唯一；**谁先决谁生效**）。
public struct AgentSyncApprovalRecord: Codable, Equatable, Sendable {
    public var requestID: String
    public var sessionID: String
    public var approved: Bool
    public var decidedBy: AgentSyncEnd
    public var decidedAt: Date

    public init(requestID: String, sessionID: String, approved: Bool,
                decidedBy: AgentSyncEnd, decidedAt: Date) {
        self.requestID = requestID
        self.sessionID = sessionID
        self.approved = approved
        self.decidedBy = decidedBy
        self.decidedAt = decidedAt
    }
}

/// 一次决定尝试的结果。
public enum AgentSyncApprovalOutcome: Equatable, Sendable {
    case recorded(AgentSyncApprovalRecord)
    /// 已经有人决过了（**本次不生效**）：返回的是**先落的那条**，调用方据此收掉自己的提问。
    case alreadyDecided(AgentSyncApprovalRecord)
}

/// 跨端审批账：一条请求只允许一个决定，另一端不再问。
public struct AgentSyncApprovalLedger: Sendable {

    public var directory: URL
    public init(directory: URL) { self.directory = directory }

    private var fileURL: URL { directory.appendingPathComponent("sync-approvals.jsonl") }

    /// 落一次决定。已决 ⇒ `alreadyDecided`（不改决定、不改时间、不改决定人）。
    @discardableResult
    public func decide(requestID: String, sessionID: String, approved: Bool,
                       by end: AgentSyncEnd, at: Date = Date()) throws -> AgentSyncApprovalOutcome {
        if let existing = decision(requestID: requestID) { return .alreadyDecided(existing) }
        let record = AgentSyncApprovalRecord(requestID: requestID, sessionID: sessionID,
                                             approved: approved, decidedBy: end, decidedAt: at)
        try appendLine(record)
        return .recorded(record)
    }

    public func decision(requestID: String) -> AgentSyncApprovalRecord? {
        all().last { $0.requestID == requestID }
    }

    /// 这个端**还需要问人**的请求：只留下一个决定都没有的那些。参数是本端手上的候选清单。
    public func openRequestIDs(_ candidates: [String], for end: AgentSyncEnd) -> [String] {
        let decided = Set(all().map(\.requestID))
        return candidates.filter { !decided.contains($0) }
    }

    public func all() -> [AgentSyncApprovalRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let body = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return body.split(separator: "\n").compactMap { line in
            try? decoder.decode(AgentSyncApprovalRecord.self, from: Data(line.utf8))
        }
    }

    private func appendLine(_ record: AgentSyncApprovalRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(record)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL, options: .atomic)
        }
    }
}

/// 把本端已有的一份与刚取回的一批合起来（**幂等 + 可交换**）。
public enum AgentSyncMerge {

    public struct Result: Equatable, Sendable {
        public var messages: [AgentSyncMessage]
        /// 同 id 但正文 / 角色不同的那些 id（**点名，不静默择一**）。
        public var conflicts: [String]

        public init(messages: [AgentSyncMessage], conflicts: [String]) {
            self.messages = messages
            self.conflicts = conflicts
        }
    }

    /// 全序 `(序号, id, 角色, 正文)` ⇒ 两个端不管先收到哪一批，合并出来的顺序都一样。
    public static func merged(_ lhs: [AgentSyncMessage], _ rhs: [AgentSyncMessage]) -> Result {
        let all = (lhs + rhs).sorted { a, b in
            if a.sequence != b.sequence { return a.sequence < b.sequence }
            if a.id != b.id { return a.id < b.id }
            if a.role.rawValue != b.role.rawValue { return a.role.rawValue < b.role.rawValue }
            return a.text < b.text
        }
        var kept: [AgentSyncMessage] = []
        var seen: [String: AgentSyncMessage] = [:]
        var conflicts: [String] = []
        for message in all {
            if let first = seen[message.id] {
                if first.role != message.role || first.text != message.text,
                   !conflicts.contains(message.id) {
                    conflicts.append(message.id)
                }
                continue
            }
            seen[message.id] = message
            kept.append(message)
        }
        return Result(messages: kept, conflicts: conflicts)
    }
}
