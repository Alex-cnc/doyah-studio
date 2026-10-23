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

/// 会话列表的一行（「回看入口」那一层）。
///
/// 为什么另立一个类型而不是直接给 `AgentSessionHeader`：列表要显示的**不只是头一行**
/// （人得看见「这个会话聊了多少跳、最后一次是什么时候」），而 `AgentSessionHeader` 是
/// **盘上格式**（`keyWhitelist` 钉着）—— 往里加字段就等于改存储契约。这里是**派生视图**：
/// 头一行 + 文件里数出来的跳数，改了不影响任何已落盘的文件。
public struct AgentSessionSummary: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var workspace: String
    public var createdAt: Date
    /// 文件里读得出的跳数（坏行不算 —— 与 `AgentSessionLoadResult.skippedLines` 同一口径）。
    public var turnCount: Int
    /// 最后一次跳的时刻；一个跳都没有（只写了头一行）⇒ `nil`。
    public var lastTurnAt: Date?

    public init(id: String, title: String, workspace: String, createdAt: Date,
                turnCount: Int, lastTurnAt: Date?) {
        self.id = id
        self.title = title
        self.workspace = workspace
        self.createdAt = createdAt
        self.turnCount = turnCount
        self.lastTurnAt = lastTurnAt
    }

    /// 排序用的「更新时间」：有跳取最后一跳，没有就取建会话那一刻。
    public var updatedAt: Date { lastTurnAt ?? createdAt }
}

/// 会话列表结果：与 `AgentSessionListResult` 同一口径（坏文件跳过并计数，不让整张列表不可用）。
public struct AgentSessionSummaryResult: Equatable, Sendable {
    public var summaries: [AgentSessionSummary]
    public var skippedFiles: Int

    public init(summaries: [AgentSessionSummary], skippedFiles: Int) {
        self.summaries = summaries
        self.skippedFiles = skippedFiles
    }

    /// 空列表 = 「这个工作区还没有历史会话」。界面据此给空态，不画一张空表。
    public var isEmpty: Bool { summaries.isEmpty }
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

    /// 会话列表（**带跳数与最近活动时刻**）—— 界面的「会话列表与切换」那一层用它。
    ///
    /// 与 `sessions(workspace:)` 的分工：那个只读头一行（够用来判断「有哪些会话」）；
    /// 这个**多读一遍正文**数跳数 —— 列表里「3 跳 · 10:42」那一格不是装饰，它是
    /// 「这条会话值不值得点进去」的唯一依据。文件都是本机小文本（一条会话几十 KB 量级），
    /// 目录扫描本来就是 IO 主导，多读一遍不改变量级。
    ///
    /// 排序 = **最近活动的在前**（`updatedAt` 降序；同刻按 id 排，保证每次打开顺序一致）。
    public func summaryList(workspace: String) -> AgentSessionSummaryResult {
        let listed = sessions(workspace: workspace)
        var summaries: [AgentSessionSummary] = []
        for header in listed.headers {
            let loaded = load(sessionID: header.id, workspace: workspace)
            guard let session = loaded.session else { continue }   // 头读得出、正文读不出 ⇒ 不进列表（也不编一条空的）
            summaries.append(AgentSessionSummary(id: session.header.id,
                                                 title: session.header.title,
                                                 workspace: session.header.workspace,
                                                 createdAt: session.header.createdAt,
                                                 turnCount: session.turns.count,
                                                 lastTurnAt: session.turns.last?.at))
        }
        summaries.sort { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.id < right.id
        }
        return AgentSessionSummaryResult(summaries: summaries, skippedFiles: listed.skippedFiles)
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

/// 把一条**已落盘**的会话摊回消息流（回看用）。
///
/// 为什么要有这一层：会话文件里的跳是**审计形状**（模型跳 / 工具跳 / 审批跳），
/// 界面要的是消息流。两边的映射必须收在一处 —— 界面自己写一遍，就会出现
/// 「导出看得到三跳、回看只看到两跳」这种同一份数据两个答案的事。
///
/// **口径**：
/// · 只搬 `text`（盘上就是摘要，不在这里补内容）；
/// · 空文本的跳不生成空行（流式中间态写进盘里的空段，回看时不该是一条空白）；
/// · 审批跳带上结论（`approved` / `denied` …），没有结论就不加后缀 —— 不猜。
public enum AgentSessionReplay {

    public static func messages(from session: AgentSession) -> [AgentChatMessage] {
        session.turns.compactMap { turn in
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            switch turn.kind {
            case .model:
                switch turn.role {
                case "user": return AgentChatMessage(role: .user, text: text)
                case "assistant": return AgentChatMessage(role: .assistant, text: text)
                // 系统提示一类：回看时当时间线事件（`◈`），不当成助手说的话。
                default: return AgentChatMessage(role: .notice, text: text)
                }
            case .tool:
                return AgentChatMessage(role: .tool, text: text)
            case .approval:
                guard let verdict = turn.approval, !verdict.isEmpty else {
                    return AgentChatMessage(role: .tool, text: text)
                }
                return AgentChatMessage(role: .tool, text: text + " · " + verdict)
            }
        }
    }
}

/// 会话内搜索（**定位 + 高亮**，一个算法两处共用）。
///
/// 为什么算法在 Core：界面要「高亮哪几段」，判据要「命中几条、第一条在哪」——
/// 两处各写一遍 `range(of:)` 循环，迟早出现「界面亮了 2 段、判据说 1 条命中」。
/// 这里只给**字符偏移**（`Range<Int>`，按 `Character` 计），界面拿同一份偏移去染
/// 它实际渲染的那段富文本：偏移是从**渲染出来的那串字**上取的，不是从原文取的。
public enum AgentTranscriptSearch {

    /// 一条消息的命中情况。
    public struct Hit: Equatable, Sendable {
        public var messageID: UUID
        public var occurrences: Int

        public init(messageID: UUID, occurrences: Int) {
            self.messageID = messageID
            self.occurrences = occurrences
        }
    }

    /// 空查询 ⇒ **零命中**（不是「全部命中」：空串匹配一切的话，一打开搜索器满屏都在亮）。
    public static func occurrences(of needle: String, in text: String) -> [Range<Int>] {
        let query = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !text.isEmpty else { return [] }
        var out: [Range<Int>] = []
        var cursor = text.startIndex
        while cursor < text.endIndex,
              let found = text.range(of: query, options: [.caseInsensitive], range: cursor..<text.endIndex) {
            let start = text.distance(from: text.startIndex, to: found.lowerBound)
            let end = text.distance(from: text.startIndex, to: found.upperBound)
            if end > start { out.append(start..<end) }
            cursor = found.upperBound > found.lowerBound ? found.upperBound : text.index(after: found.lowerBound)
        }
        return out
    }

    /// 逐条消息的命中（**空命中不进结果**，界面据此画「哪几条亮着」）。
    public static func hits(_ needle: String, in messages: [AgentChatMessage]) -> [Hit] {
        messages.compactMap { message in
            let count = occurrences(of: needle, in: message.text).count
            return count > 0 ? Hit(messageID: message.id, occurrences: count) : nil
        }
    }

    /// 总命中数（状态行那一格「N 命中」/「0 命中」用它）。
    public static func total(_ needle: String, in messages: [AgentChatMessage]) -> Int {
        hits(needle, in: messages).reduce(0) { $0 + $1.occurrences }
    }

    /// 第一条命中的消息（界面据此滚过去 —— **只定位一条**：一屏里滚来滚去比不定位更烦）。
    public static func firstMatchID(_ needle: String, in messages: [AgentChatMessage]) -> UUID? {
        hits(needle, in: messages).first?.messageID
    }
}
