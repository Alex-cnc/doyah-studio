import Foundation

/// 入站一条消息 ⇒ 真跑一轮 ⇒ 结论推回原 chat（`FR-AGT-LINK-CHAN-003` 的后半）。
///
/// 这一层把「跑」与「推」做成**两个注入的闭包**：Core 只钉顺序与账，不碰对话循环、
/// 也不碰真实网络 —— 两者都靠宿主（`AppState`）给。于是整条链在单测里能一段不缺地走完，
/// 而真网关那半仍如实缺凭据。
///
/// 三条写死的口径：
/// ① **一条链一处**：策略判定 → 去重 → 建任务 → 跑 → 入队 → 推 → **推成才 ack**。
///    任何一步都不许绕过（绕过一处，「未读不丢」就变成一句口号）；
/// ② **失败也要说话**：任务抛错、起不来、停在审批上，都推一句能读的回去 ——
///    手机那头等的是「到底怎么了」，静默失败是最难查的形态；
/// ③ **不放宽审批**：任务类型仍没有免审字段；这一层遇到「循环停在审批上」只回一句
///    「等你在桌面批准」，**不替人批**、也不假装有结论。
public enum AgentIMTaskRunResult: Equatable, Sendable {
    /// 跑完了，结论原文。
    case answered(String)
    /// 停在桌面审批上（IM 不放宽）：这一轮还没结论。
    case awaitingApproval
    /// 这一轮根本没跑起来（原因码，人话见语言表）。
    case unavailable(code: String)
}

/// 一次入站处理的结局（宿主据此记读数 / 面板）。
public enum AgentIMInboundOutcome: Equatable, Sendable {
    /// 不是消息帧（pong / 不认识的 op）：不跑、不推。
    case ignored
    /// 被策略挡下（没配齐 / 开关关 / 不在线 / 空消息）。
    case dropped(reason: AgentIMInboundDropReason)
    /// 同一条平台消息号已经处理过（QQ 会重投）：不重复跑。
    case duplicate(platformMessageID: String)
    /// 跑完了（结论 / 等审批 / 起不来），有东西推回去了；`delivered == false` = 已入队待补发。
    case replied(delivered: Bool)
    /// 跑的时候抛了（仍推了一句「没跑成」）；`reason` 是技术串，只进日志。
    case failed(reason: String, delivered: Bool)
}

/// 回话的人话。已知原因码翻人话；**不认识的原样贴码**（编一句「出错了」比贴码更误导）。
public enum AgentIMReplyText {

    /// 结论长度上限（字符）。网关对单帧有大小上限，而这一侧不知道它的确切值 ⇒
    /// 取一个偏保守的常数，并把「完整结论在桌面」明说出来 —— 不是静默截断。
    public static let maxAnsweredLength = 1_500

    public static func text(for result: AgentIMTaskRunResult, language: AppLanguage) -> String {
        switch result {
        case .answered(let answer):
            return bounded(answer, language: language)
        case .awaitingApproval:
            return LocalizedStrings.text(.agentIMReplyAwaitingApproval, language: language)
        case .unavailable(let code):
            return LocalizedStrings.format(.agentIMReplyUnavailable, language: language,
                                           reasonLine(code, language: language))
        }
    }

    /// 超长结论：截到上限再补一句「去哪看全文」（截断本身要看得出来）。
    public static func bounded(_ answer: String, language: AppLanguage) -> String {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxAnsweredLength else { return trimmed }
        let cut = String(trimmed.prefix(maxAnsweredLength))
        return cut + "\n\n" + LocalizedStrings.text(.agentIMReplyTruncated, language: language)
    }

    /// 跑的时候抛了：一句能读的话（技术串由调用方记日志，不进这条回话）。
    public static func taskFailed(language: AppLanguage) -> String {
        LocalizedStrings.text(.agentIMReplyTaskFailed, language: language)
    }

    public static func reasonLine(_ code: String, language: AppLanguage) -> String {
        switch code {
        case "busy": return LocalizedStrings.text(.agentIMReasonBusy, language: language)
        case "noWorkspace": return LocalizedStrings.text(.agentIMReasonNoWorkspace, language: language)
        case "noAnswer": return LocalizedStrings.text(.agentIMReasonNoAnswer, language: language)
        case "noRunner": return LocalizedStrings.text(.agentIMReasonNoRunner, language: language)
        case "taskFailed": return LocalizedStrings.text(.agentIMReplyTaskFailed, language: language)
        default:
            // 不认识的码原样贴出来（与 `AgentIMStatusText.reasonLine` 同一条纪律）。
            return code
        }
    }
}

/// 外发帧的形状（**本侧约定**：`op` 名与字段名要等真网关口径才能定。
/// 真 op 码未对齐这件事如实登记在台账备注里 —— 不假装它就是 QQ 官方的形状）。
public enum AgentIMOutboundFrame {

    public static let op = "reply"

    public static func reply(chatID: String, text: String) -> String {
        let payload: [String: Any] = ["op": op, "chatID": chatID, "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                    options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            // 走不到这里（三个字符串字段不会序列化失败）；真到了也要有个可读形态，
            // 不许返回空串让下游把「推了一条空帧」当成推成功。
            return #"{"op":"\#(op)","text":""}"#
        }
        return line
    }
}

/// 平台消息号去重台账（追加式 JSON，保最近 `maxEntries` 条）。
///
/// 为什么必须要它：QQ 在客户端没回 ack 时会**重投同一条消息**。没有去重，
/// 一句「把测试库重建一下」被投两次就是跑两遍 —— 这类重复执行是最贵的缺陷。
public struct AgentIMInboundLedger: Sendable {

    public static let maxEntries = 500

    public var directory: URL
    public init(directory: URL) { self.directory = directory }

    private var fileURL: URL { directory.appendingPathComponent("im-inbound-seen.json") }

    /// 记一条；返回 `true` = 头一次见（该跑），`false` = 已经见过（不重复跑）。
    ///
    /// 落盘失败时返回 `true`：宁可多跑一条（且结论仍要写结果队列，那时磁盘问题会立刻暴露），
    /// 也不静默吞掉一条用户明确派下来的任务。
    @discardableResult
    public func remember(_ platformMessageID: String, at: Date = Date()) -> Bool {
        guard !platformMessageID.isEmpty else { return true }
        var table = load()
        guard table[platformMessageID] == nil else { return false }
        table[platformMessageID] = at
        if table.count > Self.maxEntries {
            let keep = table.sorted { $0.value > $1.value }.prefix(Self.maxEntries)
            table = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        try? save(table)
        return true
    }

    public func hasSeen(_ platformMessageID: String) -> Bool {
        load()[platformMessageID] != nil
    }

    public func count() -> Int { load().count }

    private func load() -> [String: Date] {
        guard let data = try? Data(contentsOf: fileURL),
              let table = try? Self.decoder.decode([String: Date].self, from: data) else { return [:] }
        return table
    }

    private func save(_ table: [String: Date]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(table).write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public extension AgentIMResultQueue {
    /// 默认目录：与其余本机数据同一处（不另开文件体系）。
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("DoyahStudio", isDirectory: true)
            .appendingPathComponent("agent-im", isDirectory: true)
    }
}

/// 入站一条消息的完整处理（**顺序在这个类型里定死，宿主只给两个闭包**）。
public struct AgentIMInboundRunner {

    public var channel: AgentIMChannelKind
    public var sessionMap: AgentIMSessionMap
    public var resultQueue: AgentIMResultQueue
    public var ledger: AgentIMInboundLedger

    /// 跑一轮（宿主给：接进既有的对话循环；**审批不放宽**由那条路自己保证）。
    public var run: (AgentIMTask) async throws -> AgentIMTaskRunResult
    /// 推一条已入队的结果（宿主给：`AgentIMTransport.send` + ack；返回是否推出去了）。
    public var deliver: (AgentIMResultQueue.Entry) async -> Bool

    public init(channel: AgentIMChannelKind = .qq,
                sessionMap: AgentIMSessionMap,
                resultQueue: AgentIMResultQueue,
                ledger: AgentIMInboundLedger,
                run: @escaping (AgentIMTask) async throws -> AgentIMTaskRunResult,
                deliver: @escaping (AgentIMResultQueue.Entry) async -> Bool) {
        self.channel = channel
        self.sessionMap = sessionMap
        self.resultQueue = resultQueue
        self.ledger = ledger
        self.run = run
        self.deliver = deliver
    }

    /// 处理一帧。**只有这一条路**：策略 → 去重 → 建任务 → 跑 → 入队 → 推 → ack。
    public func handle(_ frame: AgentIMInboundFrame,
                       receiveTasks: Bool,
                       readiness: AgentIMReadiness,
                       connection: AgentIMConnectionState,
                       language: AppLanguage,
                       now: Date = Date()) async -> AgentIMInboundOutcome {
        guard case .message(let message) = frame else { return .ignored }

        // ① 策略三档（没配齐 / 开关关 / 不在线）—— 关掉开关时**一条都不进**，
        //    连去重台账都不记：用户之后打开开关，重投的那条仍该跑。
        if let drop = AgentIMInboundPolicy.decide(receiveTasks: receiveTasks,
                                                  readiness: readiness,
                                                  connection: connection) {
            return .dropped(reason: drop)
        }

        // 空白消息不起一轮（模型那边只会白烧一跳）。
        let prompt = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return .dropped(reason: .emptyText) }

        // ② 去重（先认领再跑：宁可少跑一条，也不许同一条跑两遍）。
        guard ledger.remember(message.platformMessageID, at: now) else {
            return .duplicate(platformMessageID: message.platformMessageID)
        }

        // ③ 建任务（同一 chat 永远同一条会话号 —— 映射落盘，重启不漂）。
        let task: AgentIMTask
        do {
            let bridge = AgentIMTaskBridge(channel: channel, sessionMap: sessionMap)
            task = try bridge.task(from: AgentIMInboundMessage(platformMessageID: message.platformMessageID,
                                                               chatID: message.chatID,
                                                               senderID: message.senderID,
                                                               text: prompt,
                                                               receivedAt: message.receivedAt))
        } catch {
            // 会话映射写不进去 ⇒ 这一轮不跑（宁可如实说，也不许另起一条会话号把上下文劈开）。
            let delivered = await push(AgentIMReplyText.text(for: .unavailable(code: "taskFailed"),
                                                             language: language),
                                       chatID: message.chatID, now: now)
            return .failed(reason: "sessionMap: \(error)", delivered: delivered)
        }

        // ④ 跑 + ⑤ 回话。
        do {
            let result = try await run(task)
            let delivered = await push(AgentIMReplyText.text(for: result, language: language),
                                       chatID: message.chatID, now: now)
            return .replied(delivered: delivered)
        } catch {
            let delivered = await push(AgentIMReplyText.taskFailed(language: language),
                                       chatID: message.chatID, now: now)
            return .failed(reason: "run: \(error)", delivered: delivered)
        }
    }

    /// 入队 + 推 + **推成才 ack**（推不出去就留在队列里，重连补发）。
    private func push(_ text: String, chatID: String, now: Date) async -> Bool {
        let entry: AgentIMResultQueue.Entry
        do {
            entry = try resultQueue.enqueue(chatID: chatID,
                                            text: AgentIMOutboundFrame.reply(chatID: chatID, text: text),
                                            at: now)
        } catch {
            // 连账都落不下去 ⇒ 没推成（不许回 true）。
            return false
        }
        let delivered = await deliver(entry)
        if delivered {
            try? resultQueue.ack(id: entry.id, at: now)
        }
        return delivered
    }
}
