import Foundation

/// **「上一次是哪条 IM 聊天」的落盘**（一份，随启动还在）。
///
/// 为什么需要它：审批请求可能由**桌面**发起的一轮触发 —— 那一轮没有 IM 入站消息，
/// `agentIMLastInbound` 是空的，于是「等确认」那条推送无处可去，人不在电脑前就卡死了
/// （2026-11-13 真机：确认选项只弹在 PC 端，手机上 20 多分钟没动静）。
///
/// 纪律：
/// ① 只记**一条**（最后一条入站所属的聊天），不做列表 —— 多记就会推错人；
/// ② 只存 `kind` + `openID` 这两个公开标识，**不存消息内容**；
/// ③ 文件坏了/读不出 ⇒ 当作没有（返回 `nil`），绝不猜一个目标出来。
public struct AgentIMLastChatStore: Sendable {

    public struct Chat: Codable, Equatable, Sendable {
        public var kind: AgentIMChatKind
        public var openID: String
        public var updatedAt: Date

        public init(kind: AgentIMChatKind, openID: String, updatedAt: Date = Date()) {
            self.kind = kind
            self.openID = openID
            self.updatedAt = updatedAt
        }

        public var target: AgentIMOutboundTarget {
            AgentIMOutboundTarget(kind: kind, openID: openID)
        }
    }

    public var directory: URL
    public init(directory: URL) { self.directory = directory }

    private var fileURL: URL { directory.appendingPathComponent("im-last-chat.json") }

    /// 记下「这条聊天说过话」。调用点在**入站被接受之后**（不是收到帧就记）。
    public func remember(kind: AgentIMChatKind, openID: String, at: Date = Date()) {
        guard !openID.isEmpty else { return }
        let chat = Chat(kind: kind, openID: openID, updatedAt: at)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(chat).write(to: fileURL, options: .atomic)
        } catch {
            // 记不下来只是降级（下次审批推不出去），不该把入站处理打断。
        }
    }

    public func load() -> Chat? {
        if let chat = loadRecorded() { return chat }
        return loadUniqueSession()
    }

    /// `im-last-chat.json`（本文件记的那一条）。
    private func loadRecorded() -> Chat? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let chat = try? decoder.decode(Chat.self, from: data), !chat.openID.isEmpty else { return nil }
        return chat
    }

    /// **退路：`im-sessions.json`**（通道自己记的「说过话的每条聊天 → 会话 ID」，键形如 `qq:<openID>`）。
    ///
    /// 2026-11-14 真机：桌面发起的一轮停在审批上，日志里 `IM 审批请求 → 手机：码=d18a` 已经打出来了，
    /// 紧接着却是「既没有入站消息、也没有落盘的聊天（跳过）」—— 因为 `im-last-chat.json` 是本版新加的，
    /// 之前说过话的那条聊天只存在于 `im-sessions.json` 里。人不在电脑前，卡片还是出不去。
    ///
    /// 纪律不变：**只认唯一候选**。去掉自测用的 `selftest` 后只剩一条才用；多于一条宁可返回 `nil`，
    /// 绝不按顺序猜一个（推错人比不推更糟）。
    private func loadUniqueSession() -> Chat? {
        let url = directory.appendingPathComponent("im-sessions.json")
        guard let data = try? Data(contentsOf: url),
              let table = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let openIDs = Set(table.keys.compactMap { key -> String? in
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0] == "qq" else { return nil }
            let openID = parts[1]
            guard !openID.isEmpty, openID != "selftest" else { return nil }
            return openID
        })
        guard openIDs.count == 1, let only = openIDs.first else { return nil }
        return Chat(kind: .c2c, openID: only, updatedAt: .distantPast)
    }
}
