import Foundation

// `FR-AGT-CORE-SESS-001` ①「会话可保存、可恢复 —— 关掉应用再打开，能接着上次的对话与进度往下走」的**跨启动续跑落账**
// （契约 §5.1 会话条目；详设 §4.6 / §5）。
//
// 现状与缺口（2026-10-23 核查）：
//   · 会话本身已落盘（`AgentSessionStore`：一会话一文件，跳里带工具名与审批结论）；
//   · 跳级检查点也已落盘（`agent-checkpoints.jsonl`，键 = `<会话号>#turn-<N>`）；
//   · **但「这一轮跑到哪、还能不能续」只活在内存里**（`AgentChatModel.lastTurn` / `lastPrompt`）——
//     重启后 `canContinue` 恒为 `false`，检查点明明在，用户却看不到「继续上次」。
//
// 本文件补的就是那一格：一轮结束时把「提问原话 + 轮次 + 落账」写进会话目录旁的小文件，
// 重新打开会话时读回来 —— 续跑判定仍是 `AgentTurnPlanner` 那一个纯函数，这里只负责存取，不另立规矩。
//
// 硬口径：
//   · **一会话一文件**（`resume-<会话号>.json`），不合并、不追加日志 —— 覆盖写，末次为准；
//   · **身份校验**：会话号或工作区对不上 ⇒ 当没有（返回 nil），不跨会话串味；
//   · **坏文件不算致命**：解析失败返回 nil 并给原因，界面照旧可读会话本身；
//   · 不存正文、不存工具输出 —— 只存续跑需要的四个值（提问原话 + 轮次 + 跳数 + 未完标记）。

/// 一轮的续跑提示（落盘形状）：重新打开会话时用它把 `lastPrompt` / `lastTurn` 填回去。
public struct AgentTurnResumeHint: Codable, Equatable, Sendable {

    public static let keyWhitelist: Set<String> = ["sessionID", "workspace", "prompt", "turn", "lastStep", "unfinished", "at"]

    public var sessionID: String
    public var workspace: String
    /// 这一轮的提问原话（「继续上次」沿用它，不让用户重打）。
    public var prompt: String
    public var turn: Int
    public var lastStep: Int
    public var unfinished: Bool
    public var at: Date

    public init(sessionID: String, workspace: String, prompt: String,
                record: AgentTurnRecord, at: Date = Date()) {
        self.sessionID = sessionID
        self.workspace = workspace
        self.prompt = prompt
        self.turn = record.turn
        self.lastStep = record.lastStep
        self.unfinished = record.unfinished
        self.at = at
    }

    /// 折算成 Core 的落账类型（续跑判定的输入）。
    public var record: AgentTurnRecord {
        AgentTurnRecord(turn: turn, lastStep: lastStep, unfinished: unfinished)
    }
}

/// 续跑提示的存储（会话目录旁，一会话一文件）。
public struct AgentTurnResumeStore: Sendable {

    public enum LoadOutcome: Equatable, Sendable {
        case found(AgentTurnResumeHint)
        /// 没有这一格（新会话 / 从没跑过 / 已清掉）。
        case absent
        /// 有文件但不认（坏 JSON / 会话号或工作区对不上）—— **不冒充有**。
        case unusable(reason: String)

        /// 只有真的读回来了才给值；其余两种一律 `nil`（不许把 unusable 当「有」）。
        public var foundHint: AgentTurnResumeHint? {
            if case let .found(hint) = self { return hint }
            return nil
        }
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 文件名：`resume-<会话号>.json`（会话号里的路径分隔符不做替换 —— 会话号由生成侧保证是单段）。
    public func url(for sessionID: String) -> URL {
        directory.appendingPathComponent("resume-\(sessionID).json", isDirectory: false)
    }

    /// 覆盖写（原子）。写失败如实抛错，**不静默吞**。
    public func save(_ hint: AgentTurnResumeHint) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(hint).write(to: url(for: hint.sessionID), options: .atomic)
    }

    /// 读回并校验身份。
    public func load(sessionID: String, workspace: String) -> LoadOutcome {
        let file = url(for: sessionID)
        guard FileManager.default.fileExists(atPath: file.path) else { return .absent }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let hint = try decoder.decode(AgentTurnResumeHint.self, from: Data(contentsOf: file))
            guard hint.sessionID == sessionID else {
                return .unusable(reason: "sessionMismatch:file=\(hint.sessionID) current=\(sessionID)")
            }
            guard hint.workspace == workspace else {
                return .unusable(reason: "workspaceMismatch:file=\(hint.workspace) current=\(workspace)")
            }
            return .found(hint)
        } catch {
            return .unusable(reason: "parseFailed:\(error.localizedDescription)")
        }
    }

    /// 清掉（会话被删 / 用户主动「新开」时不带旧进度）。
    public func clear(sessionID: String) {
        try? FileManager.default.removeItem(at: url(for: sessionID))
    }
}
