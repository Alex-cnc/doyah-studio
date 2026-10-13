import Foundation

/// 一次审批判定的结果（`FR-AI-23` ④⑤）。
public enum AgentApprovalVerdict: Equatable, Sendable {
    /// 批准且**已经在这一刻被消耗掉**（同一条决定再问一次就是拒绝 —— 审批按**次**）。
    case approved(requestID: String)
    case denied(requestID: String)
    /// 还没人做决定。
    case pending(requestID: String)
    /// 超时 ⇒ **按拒绝处理**（沿用既有口径）。
    case expired(requestID: String)
    /// 队列里没有这个指纹的请求（**连单都没建**）。
    case missing

    public var isApproved: Bool {
        if case .approved = self { return true }
        return false
    }

    public var requestID: String? {
        switch self {
        case .approved(let id), .denied(let id), .pending(let id), .expired(let id): return id
        case .missing: return nil
        }
    }
}

/// 已消耗的记账（**队列可以被清理，消耗这件事不能跟着丢**）。
public struct AgentApprovalConsumption: Codable, Equatable, Sendable {
    public var requestID: String
    public var at: Date

    public init(requestID: String, at: Date) {
        self.requestID = requestID
        self.at = at
    }
}

/// 审批闸门（`FR-AI-23`）：**复用既有 `MCPApprovalStore`**（队列 / 决定 / 指纹都在那里），
/// 本类型只补三件它没有的语义：
///
/// 1. **按次**（④）：一条批准只能兑现一次 —— 兑现过就记消耗，再问就是拒绝；
/// 2. **超时 = 拒绝**（⑤）：决定的时刻晚于 `timeout` ⇒ 判超时，不执行；
/// 3. **连单都没有**（⑥的方向）：只读模式下工具侧**根本不该入队**（那条在工具自己的判定里，
///    这里如实报 `.missing` 而不是"待审批"）。
public struct AgentApprovalGate: Sendable {

    public var store: MCPApprovalStore
    /// 超过这个秒数还没决定 ⇒ 超时（按拒绝处理）。
    public var timeout: TimeInterval

    public init(store: MCPApprovalStore, timeout: TimeInterval = 300) {
        self.store = store
        self.timeout = timeout
    }

    public var consumedURL: URL { store.directory.appendingPathComponent("consumed.jsonl") }

    // MARK: - 写

    /// 入队一次请求。`fingerprint` 由**工具侧**算（工具名 + 参数），这里不重算 —— 免得两处口径漂移。
    @discardableResult
    public func request(tool: AgentToolDefinition, argumentsSummary: String,
                        payload: String, fingerprint: String, at: Date) throws -> MCPApprovalRequest {
        try store.enqueue(client: "agent", tool: tool.name,
                          argumentsSummary: argumentsSummary, fingerprint: fingerprint,
                          sql: nil, reason: payload, now: at)
    }

    /// 判定并**消耗**：批准且未用过、且没超时 ⇒ `.approved`（同时记消耗）；其余各档如实返回。
    ///
    /// 顺序很重要：**先找活着的单，再看它的决定** —— 否则「连单都没建」与「建了但没人决定」
    /// 会被混成同一档（判据当场抓过这个混淆：`latestDecision` 在没有决定时返回 `nil`）。
    public func grant(fingerprint: String, at: Date) throws -> AgentApprovalVerdict {
        guard let request = try store.requests().last(where: { $0.fingerprint == fingerprint }) else {
            return .missing
        }
        guard let approved = try store.decision(for: request.id) else { return .pending(requestID: request.id) }
        guard approved else { return .denied(requestID: request.id) }
        guard at.timeIntervalSince(request.at) <= timeout else { return .expired(requestID: request.id) }
        guard !(try consumedRequestIDs().contains(request.id)) else { return .denied(requestID: request.id) }

        try ensureDirectory()
        let record = AgentApprovalConsumption(requestID: request.id, at: at)
        try append(try Self.encoder.encode(record), to: consumedURL)
        return .approved(requestID: request.id)
    }

    // MARK: - 读

    public func consumedRequestIDs() throws -> Set<String> {
        Set(try read().map(\.requestID))
    }

    public func consumptions() throws -> [AgentApprovalConsumption] { try read() }

    public func pendingCount() throws -> Int { try store.pending().count }

    /// 某指纹当前能不能直接兑现（**不消耗**，给界面显示用）。同一套顺序：先找单，再看决定。
    public func peek(fingerprint: String, at: Date) throws -> AgentApprovalVerdict {
        guard let request = try store.requests().last(where: { $0.fingerprint == fingerprint }) else {
            return .missing
        }
        guard let approved = try store.decision(for: request.id) else { return .pending(requestID: request.id) }
        guard approved else { return .denied(requestID: request.id) }
        guard at.timeIntervalSince(request.at) <= timeout else { return .expired(requestID: request.id) }
        guard !(try consumedRequestIDs().contains(request.id)) else { return .denied(requestID: request.id) }
        return .approved(requestID: request.id)
    }

    // MARK: - 内部

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = AgentStoredDate.encoding
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = AgentStoredDate.decoding
        return decoder
    }()

    private func read() throws -> [AgentApprovalConsumption] {
        guard let text = try? String(contentsOf: consumedURL, encoding: .utf8) else { return [] }
        var items: [AgentApprovalConsumption] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let record = try? Self.decoder.decode(AgentApprovalConsumption.self, from: data) else { continue }
            items.append(record)
        }
        return items
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
    }

    private func append(_ data: Data, to url: URL) throws {
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
