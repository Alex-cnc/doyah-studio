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
    /// 被审批闸挡在**发起侧**（删除 / 对外发送 / 凭据 / 越界那四档）：
    /// 桌面上已经出了审批单，手机那头先收到一句人话（`FR-AGT-LINK-CHAN-003` ⑧）。
    case blockedByApproval(reason: AgentIMGateReason, action: String)
    /// 这一轮根本没跑起来（原因码，人话见语言表）。
    case unavailable(code: String)
    /// **跑到一半、超过等待上限但还在跑**（`stillRunning` = 桌面那边确实还在继续）。
    ///
    /// 2026-11-04 真机：这条以前被压成「这次跑成失败」——一句话把「还在跑」说成「失败了」，
    /// 而手机那头真正的处境是「还要等」，技术串还是那句误导的 `timeout`。
    case timedOut(seconds: Int, stillRunning: Bool)
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
        case .blockedByApproval(let reason, let action):
            // 挡在**发起侧**：这一句要说清三件事 —— 是哪一类操作、为什么这里不批、去哪批。
            let reasonLine = LocalizedStrings.text(reason.textKey, language: language)
            return LocalizedStrings.format(.agentIMReplyNeedsDesktopApproval, language: language,
                                           action.isEmpty ? reasonLine : action)
        case .unavailable(let code):
            return LocalizedStrings.format(.agentIMReplyUnavailable, language: language,
                                           reasonLine(code, language: language))
        case .timedOut(let seconds, let stillRunning):
            // 超时**不是失败**：桌面那边还在跑，人话要说「多久 / 还在跑 / 结论会再发一条」。
            let duration = AgentIMProgressText.durationText(TimeInterval(seconds), language: language)
            let line = LocalizedStrings.format(.agentIMReplyStillRunning, language: language, duration)
            return stillRunning ? line : line + "\n" + LocalizedStrings.text(.agentIMReplyTaskFailed, language: language)
        }
    }

    /// 收到消息**立刻**回的那一条（`FR-AGT-LINK-CHAN-003` 的可见性补齐）。
    ///
    /// 为什么要它：真机上这一轮跑了几分钟，而手机那头从头到尾只有一句结尾的失败文案 ——
    /// 「还在处理」这句话说在前面，比任何日志都更有用（人据此决定要不要继续等）。
    public static func acknowledgement(language: AppLanguage) -> String {
        LocalizedStrings.text(.agentIMAck, language: language)
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
        case "noText": return LocalizedStrings.text(.agentIMReasonNoText, language: language)
        // 「没开跑」那一族：端点两档与其余本地拦下 —— 不再共用一个「没有结论」的码
        // （2026-11-04 真机：手机那头看不出到底是哪一种，查起来只能靠猜）。
        case "notStarted": return LocalizedStrings.text(.agentIMReasonNotStarted, language: language)
        case "endpointNotConfigured":
            return LocalizedStrings.text(.agentChatEndpointNotConfigured, language: language)
        case "endpointUnreachable":
            return LocalizedStrings.text(.agentChatEndpointUnreachable, language: language)
        case "taskFailed": return LocalizedStrings.text(.agentIMReplyTaskFailed, language: language)
        default:
            // 不认识的码原样贴出来（与 `AgentIMStatusText.reasonLine` 同一条纪律）。
            return code
        }
    }
}

/// 自建中继那条路的帧形状（**本侧约定**）。
///
/// 2026-10-28 第四十三批之后它**只服务自建中继**：官方路径的回话走 REST
/// `POST /v2/{users|groups}/{openid}/messages`（见 `AgentIMOutboundSend.swift`），
/// 不再往官方 WebSocket 上写这种帧 —— 官方网关不认它。
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
        return base.appendingPathComponent(DoyahIdentity.applicationSupportDirectoryName, isDirectory: true)
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
    ///
    /// 第二个参数是**过程播报口**：宿主每跳 / 每个工具调一次 `report`，节流与串行都在
    /// `AgentIMProgressReporter` 里，宿主不用管「多久推一条」。给 `nil` = 这一路不播报。
    public var run: (AgentIMTask, AgentIMProgressReporter?) async throws -> AgentIMTaskRunResult
    /// 推一条已入队的结果（宿主给：`AgentIMTransport.send` + ack；返回是否推出去了）。
    public var deliver: (AgentIMResultQueue.Entry) async -> Bool
    /// 进度行的节流参数（默认 25 秒 / 3 跳 / 封顶 6 条）。
    public var cadence: AgentIMProgressCadence
    /// 被判为重复（没执行）时通知宿主 —— 状态页的「去重丢弃」读数就是它记的。
    /// `nil` = 不记（判据里的裸 runner 用得上）。
    public var onDuplicate: (@Sendable (String) -> Void)?

    public init(channel: AgentIMChannelKind = .qq,
                sessionMap: AgentIMSessionMap,
                resultQueue: AgentIMResultQueue,
                ledger: AgentIMInboundLedger,
                cadence: AgentIMProgressCadence = AgentIMProgressCadence(),
                onDuplicate: (@Sendable (String) -> Void)? = nil,
                run: @escaping (AgentIMTask, AgentIMProgressReporter?) async throws -> AgentIMTaskRunResult,
                deliver: @escaping (AgentIMResultQueue.Entry) async -> Bool) {
        self.channel = channel
        self.sessionMap = sessionMap
        self.resultQueue = resultQueue
        self.ledger = ledger
        self.cadence = cadence
        self.onDuplicate = onDuplicate
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
            onDuplicate?(message.platformMessageID)
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
                                                               receivedAt: message.receivedAt,
                                                               chatKind: message.chatKind))
        } catch {
            // 会话映射写不进去 ⇒ 这一轮不跑（宁可如实说，也不许另起一条会话号把上下文劈开）。
            let delivered = await push(AgentIMReplyText.text(for: .unavailable(code: "taskFailed"),
                                                             language: language),
                                       message: message, now: now)
            return .failed(reason: "sessionMap: \(error)", delivered: delivered)
        }

        // ④ 收到即回一条 ack（**在跑之前**）：手机那头先拿到「活着」，再等结论。
        //    推不出去不算这一轮失败 —— 结论那一推还会再报一次，aker 只是「先让人安心」。
        let acknowledged = await push(AgentIMReplyText.acknowledgement(language: language),
                                      message: message, now: now)

        // ⑤ 进度播报口（节流 + 串行都在这一个类型里；发送走同一条 `push`）。
        let reporter = AgentIMProgressReporter(cadence: cadence, language: language) { line in
            await self.push(line, message: message, now: now)
        }

        // ⑥ 跑 + ⑦ 回话。
        do {
            let result = try await run(task, reporter)
            // **收尾先关播报口**（2026-11-11 真机：结论之后还在往外冒「第 N 步」，QQ 那头刷屏）：
            // 未发出的进度行丢弃，先等泵停，再推结论 —— 先后顺序因此是「关键节点 … 结论」。
            await reporter.finish()
            let delivered = await push(AgentIMReplyText.text(for: result, language: language),
                                       message: message, now: now)
            return .replied(delivered: delivered)
        } catch {
            await reporter.finish()
            let delivered = await push(AgentIMReplyText.taskFailed(language: language),
                                       message: message, now: now)
            _ = acknowledged
            return .failed(reason: "run: \(error)", delivered: delivered)
        }
    }

    /// 入队 + 推 + **推成才 ack**（推不出去就留在队列里，重连补发）。
    ///
    /// 入队的是**正文**（不是帧）：官方 REST 把它放进 `content`；自建中继由投递那一层现拼帧。
    /// 同时把「回哪个 chat、私聊还是群、回哪一条消息（`msg_id`）」一并落进条目 ——
    /// 断线后补发时这些信息已经不在内存里了，只认队列里这一份。
    private func push(_ text: String, message: AgentIMInboundMessage, now: Date) async -> Bool {
        let entry: AgentIMResultQueue.Entry
        do {
            entry = try resultQueue.enqueue(chatID: message.chatID,
                                            text: text,
                                            at: now,
                                            target: AgentIMOutboundTarget(kind: message.chatKind,
                                                                          openID: message.chatID),
                                            replyToMessageID: message.platformMessageID)
        } catch {
            // 连账都落不下去 ⇒ 没推成（不许回 true）。
            return false
        }
        let delivered = await deliver(entry)
        if delivered {
            // **ack 盖的是真实推送时刻**（不是消息到达时刻）：队列里 `createdAt → ackedAt`
            // 的差就是「这条让人等了多久」。2026-11-04 真机上这两个字段一直被写成同一个
            // 秒（`at: now` 传的是到达时间），于是「等了几分钟」在账上完全看不出来。
            try? resultQueue.ack(id: entry.id, at: Date())
        }
        return delivered
    }
}
