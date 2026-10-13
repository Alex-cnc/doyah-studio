import Foundation

/// 一次会话的一跳（`FR-AI-17`）：模型跳 / 工具跳 / 审批跳。
///
/// 键集合是**白名单**（断言面）：结构上**没有承载结果集行数据的字段**（同 `NFR-AI-01` 口径），
/// 也不放密钥 —— 会话要能被审计导出，就不能顺手把不该外发的东西记进来。
public struct AgentSessionTurn: Codable, Equatable, Sendable {

    public static let keyWhitelist: Set<String> = [
        "sessionID", "workspace", "kind", "role", "text", "toolName", "toolCallID", "approval", "at",
    ]

    /// 跳的类型：模型跳 / 工具跳 / 审批跳（`FR-AI-17` 验收要点 ③ 要三类都在）。
    public enum Kind: String, Codable, Sendable {
        case model
        case tool
        case approval
    }

    public var sessionID: String
    public var workspace: String
    public var kind: Kind
    /// `user` / `assistant` / `tool` / `system`。
    public var role: String
    /// 该跳的**文本摘要**（不是结果集内容）。
    public var text: String
    public var toolName: String?
    public var toolCallID: String?
    /// 审批结论（`approved` / `denied` / `timeout` …）；非审批跳为 `nil`。
    public var approval: String?
    /// 时刻（**注入**，不读钟 —— 否则判据无法逐项对拍）。
    public var at: Date

    public init(sessionID: String,
                workspace: String,
                kind: Kind,
                role: String,
                text: String,
                toolName: String? = nil,
                toolCallID: String? = nil,
                approval: String? = nil,
                at: Date = Date()) {
        self.sessionID = sessionID
        self.workspace = workspace
        self.kind = kind
        self.role = role
        self.text = text
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.approval = approval
        self.at = at
    }
}

/// 会话文件的第一行：会话是谁的、叫什么（**工作区隔离**就落在这里）。
public struct AgentSessionHeader: Codable, Equatable, Sendable {

    public static let keyWhitelist: Set<String> = ["id", "workspace", "title", "createdAt"]

    public var id: String
    public var workspace: String
    public var title: String
    public var createdAt: Date

    public init(id: String, workspace: String, title: String, createdAt: Date = Date()) {
        self.id = id
        self.workspace = workspace
        self.title = title
        self.createdAt = createdAt
    }
}

/// 一个会话（头 + 按时间顺序的跳）。
public struct AgentSession: Equatable, Sendable {
    public var header: AgentSessionHeader
    public var turns: [AgentSessionTurn]

    public init(header: AgentSessionHeader, turns: [AgentSessionTurn]) {
        self.header = header
        self.turns = turns
    }
}

/// 读回结果：**跳过与坏掉都要报数**（不许静默丢）。
public struct AgentSessionLoadResult: Equatable, Sendable {
    public var session: AgentSession?
    /// 解析不出来被跳过的行数。
    public var skippedLines: Int
    /// 该文件的头一行声明的工作区与请求的不符（⇒ 当作**看不到**，不当作「空会话」）。
    public var workspaceMismatch: Bool

    public init(session: AgentSession?, skippedLines: Int, workspaceMismatch: Bool) {
        self.session = session
        self.skippedLines = skippedLines
        self.workspaceMismatch = workspaceMismatch
    }
}

/// 会话列表结果：坏文件**跳过并计数**，但不让整张列表不可用（验收要点 ⑤）。
public struct AgentSessionListResult: Equatable, Sendable {
    public var headers: [AgentSessionHeader]
    /// 读不出头一行的文件数（坏文件 / 非本会话格式）。
    public var skippedFiles: Int

    public init(headers: [AgentSessionHeader], skippedFiles: Int) {
        self.headers = headers
        self.skippedFiles = skippedFiles
    }
}

/// 会话存储：**按工作区持久化**，一会话一文件（追加式 JSONL，形状同 `AgentCheckpoint` / `MCPApprovalStore`）。
public struct AgentSessionStore: Sendable {

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 默认目录：与其余本机数据同一处（不另开文件体系）。
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("DoyahStudio", isDirectory: true)
            .appendingPathComponent("agent-sessions", isDirectory: true)
    }

    public func fileURL(sessionID: String) -> URL {
        directory.appendingPathComponent("\(AgentSessionStore.sanitized(sessionID)).jsonl")
    }

    // MARK: - 写

    /// 建一个会话（写头一行）。
    @discardableResult
    public func createSession(workspace: String, title: String, sessionID: String = UUID().uuidString,
                              createdAt: Date = Date()) throws -> AgentSessionHeader {
        let header = AgentSessionHeader(id: sessionID, workspace: workspace, title: title, createdAt: createdAt)
        try ensureDirectory()
        try appendLine(try Self.encoder.encode(header), to: fileURL(sessionID: sessionID))
        return header
    }

    /// 追加一跳。**先核会话归属**：不是这个工作区的会话，写不进去（返回 `false`，不静默落到别人家）。
    @discardableResult
    public func append(_ turn: AgentSessionTurn) throws -> Bool {
        let loaded = load(sessionID: turn.sessionID, workspace: turn.workspace)
        guard let session = loaded.session, !loaded.workspaceMismatch else { return false }
        _ = session
        try appendLine(try Self.encoder.encode(turn), to: fileURL(sessionID: turn.sessionID))
        return true
    }

    // MARK: - 读

    /// 读回一个会话（同一工作区**重启后**读回同一条 —— 验收要点 ①）。
    public func load(sessionID: String, workspace: String) -> AgentSessionLoadResult {
        let url = fileURL(sessionID: sessionID)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return AgentSessionLoadResult(session: nil, skippedLines: 0, workspaceMismatch: false)
        }

        var header: AgentSessionHeader?
        var turns: [AgentSessionTurn] = []
        var skippedLines = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8) else { skippedLines += 1; continue }
            if let parsed = try? Self.decoder.decode(AgentSessionHeader.self, from: data) {
                if header == nil { header = parsed }
                continue
            }
            if let turn = try? Self.decoder.decode(AgentSessionTurn.self, from: data) {
                turns.append(turn)
                continue
            }
            skippedLines += 1
        }

        guard let header else {
            return AgentSessionLoadResult(session: nil, skippedLines: skippedLines, workspaceMismatch: false)
        }
        guard header.workspace == workspace else {
            // 别人的会话 ⇒ **看不到**（不是「空会话」）—— 验收要点 ② 的负例方向。
            return AgentSessionLoadResult(session: nil, skippedLines: skippedLines, workspaceMismatch: true)
        }
        return AgentSessionLoadResult(session: AgentSession(header: header, turns: ordered(turns)),
                                      skippedLines: skippedLines, workspaceMismatch: false)
    }

    /// 某个工作区看得到哪些会话（坏文件跳过并计数 ⇒ 列表仍可用 —— 验收要点 ⑤）。
    public func sessions(workspace: String) -> AgentSessionListResult {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                    includingPropertiesForKeys: nil)) ?? []
        var headers: [AgentSessionHeader] = []
        var skippedFiles = 0

        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard url.pathExtension == "jsonl" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { skippedFiles += 1; continue }
            var found: AgentSessionHeader?
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = line.data(using: .utf8),
                      let header = try? Self.decoder.decode(AgentSessionHeader.self, from: data) else { continue }
                found = header
                break
            }
            guard let header = found else { skippedFiles += 1; continue }      // 坏文件：跳过并计数
            guard header.workspace == workspace else { continue }              // 别的工作区：不是「跳过」，是看不到
            headers.append(header)
        }
        return AgentSessionListResult(headers: headers.sorted { $0.createdAt < $1.createdAt },
                                      skippedFiles: skippedFiles)
    }

    /// 导出（按**时间顺序**回放：模型跳 / 工具跳 / 审批跳都在 —— 验收要点 ③）。
    public func export(_ session: AgentSession) throws -> Data {
        let ordered = self.ordered(session.turns)
        let payload: [String: Any] = [
            "id": session.header.id,
            "workspace": session.header.workspace,
            "title": session.header.title,
            "createdAt": Self.iso8601(session.header.createdAt),
            "turns": ordered.map { turn -> [String: Any] in
                var object: [String: Any] = [
                    "kind": turn.kind.rawValue,
                    "role": turn.role,
                    "text": turn.text,
                    "at": Self.iso8601(turn.at),
                ]
                if let toolName = turn.toolName { object["toolName"] = toolName }
                if let toolCallID = turn.toolCallID { object["toolCallID"] = toolCallID }
                if let approval = turn.approval { object["approval"] = approval }
                return object
            },
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted])
    }

    // MARK: - 内部

    /// **稳定**顺序：先按时刻，再按写入次序（同一时刻不许被重排成随机序）。
    private func ordered(_ turns: [AgentSessionTurn]) -> [AgentSessionTurn] {
        turns.enumerated()
            .sorted { left, right in
                if left.element.at == right.element.at { return left.offset < right.offset }
                return left.element.at < right.element.at
            }
            .map(\.element)
    }

    static func sanitized(_ sessionID: String) -> String {
        sessionID.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }.reduce(into: "") { $0.append($1) }
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // **精确往返**：`.iso8601` 会丢亚秒（实测抓过：`Date()` 写的头一行读回来不再相等 ——
        // 「重启后读回同一条」这条判据当场判红），`.secondsSince1970` 走 JSON 数字格式化同样丢低位。
        // 口径收在 `AgentStoredDate` 一处：存最短可往返字符串 ⇒ 落盘再读回**逐位一致**。
        encoder.dateEncodingStrategy = AgentStoredDate.encoding
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = AgentStoredDate.decoding
        return decoder
    }()

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func appendLine(_ data: Data, to url: URL) throws {
        var payload = data
        payload.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } else {
            try payload.write(to: url, options: .atomic)
        }
    }
}
