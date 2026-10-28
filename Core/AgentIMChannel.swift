import Foundation

/// IM 通道（`FR-AGT-LINK-CHAN-003`）的**契约层**：把「聊天里发来的一句话」接到桌面同一套会话与审批上。
///
/// 这一层只回答三件在验收里会被追问的事，**不碰网络**（QQ 网关的连/断/重连由传输层做）：
///
/// ① **同一会话**：同一个 chat ⇒ 永远同一个 `sessionID`（映射落盘，重启后仍指同一条，
///    所以桌面上看到的就是那一条，不会每次 IM 发话都新开一条）；
/// ② **审批不放宽**：`AgentIMTask` 这个类型**没有**「已批准 / 免审」字段 —— 想放宽得改类型，
///    改类型会被评审看见。IM 来的任务照原样进 `AgentLoop`，工具审批、护栏、配额一条不少；
/// ③ **未读不丢**：结果先进 `AgentIMResultQueue`（追加落盘），投递成功才 `ack`；
///    断了就重连，没 ack 的还躺着 —— 重启也还在。
///
/// 传输层（QQ 官方机器人网关的 WebSocket、心跳、断线重连、签名）不在这一件里：
/// 它需要 AppID / Secret（走系统凭据存储），且必须**只经这里**出入，不许自己拼会话号。
public enum AgentIMChannelKind: String, Codable, Equatable, Sendable, CaseIterable {
    case qq
}

/// 聊天类型（官方两条消息端点各一对：私聊 / 群）。
///
/// 它决定**回话往哪条端点发**：私聊 `POST /v2/users/{openid}/messages`、
/// 群聊 `POST /v2/groups/{group_openid}/messages`。猜错一档 = 404 或打到别人的会话上，
/// 所以这个字段由解帧那一处按事件名判定（`C2C_…` / `GROUP_AT_…`），不由下游猜。
public enum AgentIMChatKind: String, Codable, Equatable, Sendable, CaseIterable {
    case c2c
    case group
}

/// 从 IM 进来的一条消息（平台原样字段，不做解释）。
public struct AgentIMInboundMessage: Codable, Equatable, Sendable {
    /// 平台消息号（用于去重与回执）。
    public var platformMessageID: String
    /// 平台会话号（QQ：群号 / 私聊的 openid 会话）。
    public var chatID: String
    /// 发送者（QQ：openid）。
    public var senderID: String
    public var text: String
    public var receivedAt: Date
    /// 私聊还是群（回话走哪条端点由它定）。
    public var chatKind: AgentIMChatKind

    public init(platformMessageID: String, chatID: String, senderID: String,
                text: String, receivedAt: Date = Date(), chatKind: AgentIMChatKind = .c2c) {
        self.platformMessageID = platformMessageID
        self.chatID = chatID
        self.senderID = senderID
        self.text = text
        self.receivedAt = receivedAt
        self.chatKind = chatKind
    }
}

/// 落给循环去跑的一条任务（**没有**免审批字段 —— 见类型注释 ②）。
public struct AgentIMTask: Equatable, Sendable {
    public var channel: AgentIMChannelKind
    public var chatID: String
    public var sessionID: String
    public var prompt: String
    public var platformMessageID: String

    /// 永远为真，且**没有 setter**：IM 来的任务一律仍走桌面同一套审批。
    public var alwaysRequiresDesktopApproval: Bool { true }
}

/// `chatID → sessionID` 的落盘映射（同一 chat 永远同一条会话，重启不漂）。
public struct AgentIMSessionMap: Sendable {

    public var directory: URL
    public init(directory: URL) { self.directory = directory }

    private var fileURL: URL { directory.appendingPathComponent("im-sessions.json") }

    /// 取这个 chat 的会话号；第一次见就分配一个并落盘。
    public func sessionID(for chatID: String, channel: AgentIMChannelKind,
                          allocate: () -> String = { UUID().uuidString }) throws -> String {
        var table = load()
        let key = "\(channel.rawValue):\(chatID)"
        if let existing = table[key] { return existing }
        let fresh = allocate()
        table[key] = fresh
        try save(table)
        return fresh
    }

    /// 已登记的映射（判据与界面读数用）。
    public func all() -> [String: String] { load() }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let table = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return table
    }

    private func save(_ table: [String: String]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(table).write(to: fileURL, options: .atomic)
    }
}

/// 待投递结果队列（追加式 JSONL）：**没 ack 的永不丢**，重启也还在。
public struct AgentIMResultQueue: Sendable {

    public struct Entry: Codable, Equatable, Sendable {
        public var id: String
        public var chatID: String
        /// 要说的话（**正文**，不是帧：官方 REST 走 `content` 字段，自建中继才现拼成帧）。
        public var text: String
        public var createdAt: Date
        public var ackedAt: Date?
        /// 官方 REST 的收件目标。`nil` = 这一条是**自建中继 / 第四十二批及以前的老条目**，
        /// 走 WebSocket 那条路（老条目的 `text` 里存的就是那一帧，不许当正文发出去）。
        public var target: AgentIMOutboundTarget?
        /// 被动回复要带的 `msg_id`：这条结果是回哪一句派活。
        public var replyToMessageID: String?

        public init(id: String, chatID: String, text: String, createdAt: Date,
                    ackedAt: Date? = nil, target: AgentIMOutboundTarget? = nil,
                    replyToMessageID: String? = nil) {
            self.id = id
            self.chatID = chatID
            self.text = text
            self.createdAt = createdAt
            self.ackedAt = ackedAt
            self.target = target
            self.replyToMessageID = replyToMessageID
        }
    }

    public var directory: URL
    public init(directory: URL) { self.directory = directory }

    private var fileURL: URL { directory.appendingPathComponent("im-results.jsonl") }

    @discardableResult
    public func enqueue(chatID: String, text: String,
                        id: String = UUID().uuidString, at: Date = Date(),
                        target: AgentIMOutboundTarget? = nil,
                        replyToMessageID: String? = nil) throws -> Entry {
        let entry = Entry(id: id, chatID: chatID, text: text, createdAt: at,
                          target: target, replyToMessageID: replyToMessageID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(entry)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL, options: .atomic)
        }
        return entry
    }

    /// 投递成功才 ack（重连后按 `id` 幂等）。
    public func ack(id: String, at: Date = Date()) throws {
        var entries = all()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].ackedAt = at
        try rewrite(entries)
    }

    /// 还没投递出去的（重连后要补发的就是这些）。
    public func pending() -> [Entry] { all().filter { $0.ackedAt == nil } }

    /// 走 WebSocket 帧那条路的未投递条目（自建中继 / 第四十二批及以前的老条目）。
    ///
    /// 传输层补发只许用这一份：官方条目（`target != nil`）走 REST，
    /// 把它们也往 WebSocket 上糊一遍 = 网关收到一堆它不认的帧（真连上时就是「一堆坏帧」）。
    public func relayPending() -> [Entry] {
        all().filter { $0.ackedAt == nil && $0.target == nil }
    }

    public func all() -> [Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { line in
            try? decoder.decode(Entry.self, from: Data(line.utf8))
        }
    }

    private func rewrite(_ entries: [Entry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let body = entries.compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
        try Data((body.isEmpty ? "" : body + "\n").utf8).write(to: fileURL, options: .atomic)
    }
}

/// 入口：一条 IM 消息 ⇒ 一条能直接交给既有循环的任务（**不新开会话号、不带免审旗**）。
public struct AgentIMTaskBridge: Sendable {
    public var channel: AgentIMChannelKind
    public var sessionMap: AgentIMSessionMap

    public init(channel: AgentIMChannelKind = .qq, sessionMap: AgentIMSessionMap) {
        self.channel = channel
        self.sessionMap = sessionMap
    }

    public func task(from message: AgentIMInboundMessage,
                     allocateSessionID: () -> String = { UUID().uuidString }) throws -> AgentIMTask {
        let sessionID = try sessionMap.sessionID(for: message.chatID, channel: channel,
                                                 allocate: allocateSessionID)
        return AgentIMTask(channel: channel, chatID: message.chatID, sessionID: sessionID,
                           prompt: message.text, platformMessageID: message.platformMessageID)
    }
}
