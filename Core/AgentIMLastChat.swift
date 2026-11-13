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
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let chat = try? decoder.decode(Chat.self, from: data), !chat.openID.isEmpty else { return nil }
        return chat
    }
}
