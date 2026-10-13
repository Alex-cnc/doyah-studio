import Foundation

/// `NFR-AI-08` + `FR-AI-30` ③（检查点续跑的**存储半**）—— 提案 `0009` C 片。
///
/// 形状抄 `Core/MCPApprovalQueue.swift`：**追加式 JSONL**，一行一条；坏行**跳过并计数**，
/// 按 `sessionID` 回查**最后一条可用**；**丢 / 坏时落到上一可用点并如实报数**，
/// 不许「静默从头重来」（`R-63` ③）。
///
/// 键集合是**白名单**：结构上没有结果集行数据、也没有密钥的落点（同 `NFR-AI-01` / `FR-AI-17` 口径）。
public struct AgentCheckpoint: Codable, Equatable, Sendable {

    /// 允许出现的键（判据按这一份对账；加字段必须同时改这里 —— 不是注释，是断言面）。
    public static let keyWhitelist: Set<String> = [
        "sessionID", "stepIndex", "completedSteps", "pendingMessagesDigest", "at",
    ]

    /// 会话标识（按会话回查最后一条可用）。
    public var sessionID: String
    /// 已完成到第几跳（0 起；**这一跳已经跑完并落盘**）。
    public var stepIndex: Int
    /// 已完成步骤的**摘要**（一句话 / 一个标识，**不是**结果本身）。
    public var completedSteps: [String]
    /// 待发消息的**摘要**（指纹一类，不是消息正文）。
    public var pendingMessagesDigest: String
    /// 时刻（注入，不读钟）。
    public var at: Date

    public init(sessionID: String,
                stepIndex: Int,
                completedSteps: [String] = [],
                pendingMessagesDigest: String = "",
                at: Date = Date()) {
        self.sessionID = sessionID
        self.stepIndex = stepIndex
        self.completedSteps = completedSteps
        self.pendingMessagesDigest = pendingMessagesDigest
        self.at = at
    }
}

/// 一次恢复的结果 —— 三个数都要能报出来（落到了哪一跳 / 回退了几跳 / 跳过了几个坏行）。
public struct AgentCheckpointRecovery: Equatable, Sendable {
    /// 可用的检查点（`nil` = 该会话一个可用点都没有）。
    public var checkpoint: AgentCheckpoint?
    /// 相对调用方以为自己停的那一跳，**实际回退了几跳**（`R-63` ③ 的“如实报数”）。
    public var skippedSteps: Int
    /// 跳过了几个**坏行**（解析不出来的行）。
    public var skippedLines: Int

    public init(checkpoint: AgentCheckpoint?, skippedSteps: Int, skippedLines: Int) {
        self.checkpoint = checkpoint
        self.skippedSteps = skippedSteps
        self.skippedLines = skippedLines
    }
}

/// 检查点存储：按工作区存放（与将来的会话存储同一处，不另开文件体系）。**不落盘任何行数据。**
public struct AgentCheckpointStore: Sendable {

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 默认目录：与其余本机数据同一处。
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("DoyahStudio", isDirectory: true)
    }

    /// 存储文件（追加式 JSONL）。
    public var fileURL: URL {
        directory.appendingPathComponent("agent-checkpoints.jsonl")
    }

    // MARK: - 写

    /// 追加一个检查点。
    public func record(_ checkpoint: AgentCheckpoint) throws {
        try ensureDirectory()
        let data = try Self.encoder.encode(checkpoint)
        try append(data, to: fileURL)
    }

    // MARK: - 读

    /// 按会话回查**最后一条可用**的检查点。
    ///
    /// - Parameter requestedStep: 调用方以为自己停在第几跳。
    ///   返回的 `skippedSteps` = `requestedStep - 可用点的 stepIndex`（一个可用点都没有 ⇒ = `requestedStep`）——
    ///   于是「落了上一可用点」与「其实是从头跑」在读数上**分得开**，不会静默从头。
    public func recover(sessionID: String, requestedStep: Int) -> AgentCheckpointRecovery {
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        var last: AgentCheckpoint?
        var skippedLines = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let checkpoint = try? Self.decoder.decode(AgentCheckpoint.self, from: data) else {
                // 坏行 / 截断行：跳过并**计数**（不静默丢）。
                skippedLines += 1
                continue
            }
            guard checkpoint.sessionID == sessionID else { continue }
            if let current = last {
                if checkpoint.stepIndex >= current.stepIndex { last = checkpoint }
            } else {
                last = checkpoint
            }
        }

        let skippedSteps: Int
        if let last {
            skippedSteps = max(0, requestedStep - last.stepIndex)
        } else {
            skippedSteps = max(0, requestedStep)
        }
        return AgentCheckpointRecovery(checkpoint: last, skippedSteps: skippedSteps, skippedLines: skippedLines)
    }

    // MARK: - 内部

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // 与 `AgentSessionStore` **同一处口径**（`AgentStoredDate`）：日期精确往返，不许丢低位。
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
