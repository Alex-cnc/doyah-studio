import Foundation

/// 官方 REST 外发（`FR-AGT-LINK-CHAN-003` 的收尾片，2026-10-28 第四十三批）。
///
/// 由头：入站（收下来派活）与握手（拿 token / 取网关）在第四十一 / 四十二批都对齐了官方口径，
/// **回话**却还是本侧约定的一帧 `{"op":"reply",…}` 往 WebSocket 上糊 —— 官方网关根本不认这种帧，
/// 也就是说「手机派活、手机收结论」这条验收链的最后一段其实没通。
///
/// 官方口径（两条端点，一对私聊一对群）：
/// - 私聊：`POST /v2/users/{openid}/messages`
/// - 群聊：`POST /v2/groups/{group_openid}/messages`
/// - 正文：`{"content":…,"msg_type":0}`；**被动回复**再带 `msg_id`（回哪一条派活）与
///   `msg_seq`（同一 `msg_id` 下不可重复 —— 复用序号会被 QQ 当重复消息丢掉）。
///
/// 这一层只做三件事，且都不碰网络：**拼目标**（外部来的 openid 要校验，不许拿它拼出别的端点）、
/// **拼正文**（带不带 `msg_id` / `msg_seq` 在这里定死）、**给结果分档**（401 / 403 / 429 / 5xx /
/// 非 JSON / 其余原样带码 —— 与取 token 那一层同一套分法，界面才说得出「凭据不对」还是「被限流」）。
public struct AgentIMOutboundTarget: Codable, Equatable, Sendable {

    public var kind: AgentIMChatKind
    /// 私聊 = 用户的 `openid`；群聊 = `group_openid`。
    public var openID: String

    public init(kind: AgentIMChatKind, openID: String) {
        self.kind = kind
        self.openID = openID
    }

    public enum Problem: Error, Equatable, Sendable {
        case emptyOpenID
        /// 认不出的写法：里外空白之外的字符、路径分隔符、`..`（**它会被拼进 URL 路径**）。
        case invalidOpenID
    }

    /// 校验并归一（去首尾空白）。
    ///
    /// `openid` 是**外部输入**：它要被拼进 URL 路径 ⇒ 放行集必须窄。放行集之外的一律拒绝，
    /// 而不是「编码一下接着发」—— 编码过之后仍可能被服务端解释成另一个资源。
    public func validated() throws -> AgentIMOutboundTarget {
        let trimmed = openID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Problem.emptyOpenID }
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        allowed.insert(charactersIn: "0123456789")
        allowed.insert(charactersIn: "-_.")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !trimmed.contains("..") else { throw Problem.invalidOpenID }
        return AgentIMOutboundTarget(kind: kind, openID: trimmed)
    }
}

/// 官方消息端点的形状（**只有这一处拼路径**）。
public enum AgentIMQQMessageEndpoint {

    public static func path(for target: AgentIMOutboundTarget) -> String {
        let segment = target.kind == .c2c ? "users" : "groups"
        return "/v2/\(segment)/\(target.openID)/messages"
    }

    /// 完整 URL（`environment.apiBase` = 正式 / 沙箱那条域；target 认不出就 `nil`，
    /// 不许「尽量拼一个」—— 拼错的地址会打到别人的资源上）。
    public static func url(for target: AgentIMOutboundTarget,
                           environment: AgentIMQQEnvironment) -> URL? {
        guard let valid = try? target.validated() else { return nil }
        return URL(string: path(for: valid), relativeTo: environment.apiBase)?.absoluteURL
    }
}

/// 发出去的那一坨正文（`msg_type` = 0 = 纯文本）。
///
/// **被动 vs 主动在这里定死**：有 `msg_id` 才是被动回复（要带 `msg_seq`）；
/// 没有 `msg_id` 就是主动消息（不许多带一个 `msg_seq` —— 官方口径里它跟 `msg_id` 配对）。
public struct AgentIMQQMessageBody: Equatable, Sendable {

    public static let textMessageType = 0

    public var content: String
    public var messageID: String?
    public var sequence: Int?

    public init(content: String, messageID: String? = nil, sequence: Int? = nil) {
        self.content = content
        self.messageID = messageID
        self.sequence = sequence
    }

    public var isPassive: Bool { messageID != nil }

    /// 键序固定（判据按串比时不至于今天一样明天不一样）。
    public func jsonString() -> String {
        var object: [String: Any] = ["content": content, "msg_type": Self.textMessageType]
        if let messageID, !messageID.isEmpty { object["msg_id"] = messageID }
        if let sequence, messageID != nil { object["msg_seq"] = sequence }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            // 走不到这里（两个字符串 + 两个整数不会序列化失败）；真到了也要有可读形态，
            // 不许返回空串让下游把「发了一坨空」当成功。
            return "{}"
        }
        return text
    }
}

/// `msg_seq` 的**唯一分配处**（落盘 `im-reply-seq.json`）。
///
/// 两条纪律，各自都对应一个真实缺陷：
/// ① **同一条结果重发必须复用同一个序号** —— 换号 = 官方当新消息 = 手机上出现两条一样的结论
///    （投递成功但 ack 没落下去时，重连补发就是这条路径）；
/// ② **同一个 `msg_id` 下的不同结果序号必须递增且不重复** —— 复用会被 QQ 直接丢掉，
///    于是「跑完了但手机没动静」。
public struct AgentIMReplySeqLedger: Sendable {

    public static let maxEntries = 500

    public struct Record: Codable, Equatable, Sendable {
        public var sequence: Int
        public var messageID: String?
        public var at: Date

        public init(sequence: Int, messageID: String?, at: Date) {
            self.sequence = sequence
            self.messageID = messageID
            self.at = at
        }
    }

    struct Counter: Codable, Equatable, Sendable {
        var value: Int
        var at: Date
    }

    struct Table: Codable, Equatable, Sendable {
        var entries: [String: Record] = [:]
        var counters: [String: Counter] = [:]
    }

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent("im-reply-seq.json") }

    /// 给一条待投递结果分配序号；主动消息（没有 `msg_id`）返回 `nil`（不带 `msg_seq`）。
    public func sequence(forEntry entryID: String, replyTo messageID: String?, at: Date = Date()) -> Int? {
        guard let messageID, !messageID.isEmpty else { return nil }
        var table = load()
        if let existing = table.entries[entryID], existing.messageID == messageID {
            return existing.sequence
        }
        let next = (table.counters[messageID]?.value ?? 0) + 1
        table.counters[messageID] = Counter(value: next, at: at)
        table.entries[entryID] = Record(sequence: next, messageID: messageID, at: at)
        prune(&table)
        try? save(table)
        return next
    }

    public func stored(forEntry entryID: String) -> Record? { load().entries[entryID] }

    public func count() -> Int { load().entries.count }

    private func prune(_ table: inout Table) {
        guard table.entries.count > Self.maxEntries else { return }
        let keep = table.entries.sorted { $0.value.at > $1.value.at }.prefix(Self.maxEntries)
        table.entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        // 计数器只留还在用到的那些 + 最近的（丢了计数器 = 下一条又从 1 开始 = 复用序号）。
        let live = Set(table.entries.values.compactMap { $0.messageID })
        table.counters = table.counters.filter { live.contains($0.key) }
    }

    private func load() -> Table {
        guard let data = try? Data(contentsOf: fileURL),
              let table = try? Self.decoder.decode(Table.self, from: data) else { return Table() }
        return table
    }

    private func save(_ table: Table) throws {
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

/// 发送用的 REST 出口（**正文是已经拼好的 JSON 串**：`msg_type` / `msg_seq` 是数字，
/// 走 `[String: String]` 那一版会被迫写成 `"0"` / `"1"` —— 服务端按类型校验会直接拒）。
public protocol AgentIMOutboundHTTPClient: Sendable {
    func post(_ url: URL, payload: String, headers: [String: String]) async throws -> AgentIMHTTPResponse
}

/// 一次外发的结局（**每一档都要说得清**：面板要能告诉用户是凭据不对、限流，还是真的发出去了）。
public enum AgentIMSendOutcome: Equatable, Sendable {

    /// 2xx：官方收下了。`messageID` = 它回执里的那条消息号（它没给就是 `nil`，仍算发出去了）。
    case delivered(messageID: String?)
    /// 没到发的那一步（没目标 / 空正文 / 取不到 token…）：`code` 是机器码。
    case notReady(code: String)
    /// 401：AppID / Secret 不对。
    case unauthorized
    /// 403：凭据对但这个机器人没权限（没开消息权限 / 没被拉进目标群）。
    case forbidden
    case rateLimited
    case serverFailed
    /// 2xx 了但正文不是 JSON（多半被代理/网关拦回来一页 HTML）。**仍算发出去** —— 2xx 是官方状态码。
    case responseNotJSON
    /// 其余非 2xx：状态与它给的码原样带出去（不替它编原因）。
    case rejected(status: Int, code: String?)
    case networkFailed

    public var isDelivered: Bool {
        switch self {
        case .delivered, .responseNotJSON: return true
        default: return false
        }
    }

    /// 机器码（日志与面板的稳定标识；人话由 `AgentIMSendText` 翻）。
    public var code: String {
        switch self {
        case .delivered: return "delivered"
        case .notReady(let code): return "notReady:\\(code)"
        case .unauthorized: return "unauthorized"
        case .forbidden: return "forbidden"
        case .rateLimited: return "rateLimited"
        case .serverFailed: return "serverFailed"
        case .responseNotJSON: return "responseNotJSON"
        case .rejected(let status, let code): return "rejected:\(status):\(code ?? "-")"
        case .networkFailed: return "networkFailed"
        }
    }
}

/// 一条结果 ⇒ 一次官方外发。**不带状态**：重试由调用方决定（结果队列里没 ack 的会重来）。
public struct AgentIMOutboundSender: Sendable {

    public var client: any AgentIMOutboundHTTPClient
    public var environment: AgentIMQQEnvironment
    public var sequences: AgentIMReplySeqLedger
    /// 现取 token（到期前换、单飞都由 `AgentIMQQTokenVault` 保证；这里只管用）。
    public var token: @Sendable () async throws -> AgentIMQQToken

    public init(client: any AgentIMOutboundHTTPClient,
                environment: AgentIMQQEnvironment,
                sequences: AgentIMReplySeqLedger,
                token: @escaping @Sendable () async throws -> AgentIMQQToken) {
        self.client = client
        self.environment = environment
        self.sequences = sequences
        self.token = token
    }

    public func send(entry: AgentIMResultQueue.Entry) async -> AgentIMSendOutcome {
        guard let target = entry.target else { return .notReady(code: "noTarget") }
        return await send(text: entry.text, target: target,
                          entryID: entry.id, replyTo: entry.replyToMessageID)
    }

    public func send(text: String,
                     target: AgentIMOutboundTarget,
                     entryID: String,
                     replyTo messageID: String?,
                     at: Date = Date()) async -> AgentIMSendOutcome {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return .notReady(code: "emptyContent") }
        guard let valid = try? target.validated(),
              let url = AgentIMQQMessageEndpoint.url(for: valid, environment: environment) else {
            return .notReady(code: "badTarget")
        }

        let tokenValue: AgentIMQQToken
        do {
            tokenValue = try await token()
        } catch let problem as AgentIMQQProvisionProblem {
            return Self.outcome(for: problem)
        } catch {
            return .notReady(code: "tokenUnavailable")
        }

        let replyTo = (messageID?.isEmpty == false) ? messageID : nil
        let body = AgentIMQQMessageBody(content: content,
                                        messageID: replyTo,
                                        sequence: sequences.sequence(forEntry: entryID,
                                                                     replyTo: replyTo,
                                                                     at: at))
        let response: AgentIMHTTPResponse
        do {
            response = try await client.post(url, payload: body.jsonString(),
                                             headers: tokenValue.authorizationHeaders)
        } catch {
            return .networkFailed
        }
        return Self.outcome(for: response)
    }

    /// 响应 → 结局。认识的码给可读原因，**不认识的把状态与它自己的码原样带出去**。
    static func outcome(for response: AgentIMHTTPResponse) -> AgentIMSendOutcome {
        if response.isSuccess {
            let id = ProvisionerSupport.jsonObject(response.body)?["id"] as? String
            // 2xx 但正文认不出：**仍算发出去**（状态码是官方的，正文格式不是我们能要求的）。
            return id == nil ? .responseNotJSON : .delivered(messageID: id)
        }
        switch response.status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 429: return .rateLimited
        case 500..<600: return .serverFailed
        default: return .rejected(status: response.status,
                                  code: AgentIMQQProvisioner.errorCode(in: response.body))
        }
    }

    /// 取 token 那一步的失败 → 外发这一层的分档（同一套语义，面板才不会两种说法）。
    static func outcome(for problem: AgentIMQQProvisionProblem) -> AgentIMSendOutcome {
        switch problem {
        case .credentialsRejected: return .unauthorized
        case .permissionDenied: return .forbidden
        case .rateLimited: return .rateLimited
        case .serverFailed: return .serverFailed
        case .responseNotJSON: return .responseNotJSON
        case .networkFailed: return .networkFailed
        case .rejected(let status, let code): return .rejected(status: status, code: code)
        case .environmentMissing: return .notReady(code: "environmentMissing")
        case .appIDMissing: return .notReady(code: "appIDMissing")
        case .secretMissing: return .notReady(code: "secretMissing")
        case .tokenMissing: return .notReady(code: "tokenMissing")
        }
    }
}

/// 连上之后把**官方那条路的**未投递结果补发一遍（自建中继 / 老条目由传输层自己补）。
///
/// 为什么要单独一件：官方结果走 REST，传输层的 `replayPending` 只会往 WebSocket 上写帧 ⇒
/// 断线期间攒下的官方结果**没有人补发**（结果队列里躺着，永远不会出去）。
public struct AgentIMOutboundDrain: Sendable {

    public struct Report: Equatable, Sendable {
        public var delivered: Int
        public var failed: Int
        public var lastFailure: AgentIMSendOutcome?

        public init(delivered: Int = 0, failed: Int = 0, lastFailure: AgentIMSendOutcome? = nil) {
            self.delivered = delivered
            self.failed = failed
            self.lastFailure = lastFailure
        }
    }

    public var queue: AgentIMResultQueue
    public var send: @Sendable (AgentIMResultQueue.Entry) async -> AgentIMSendOutcome

    public init(queue: AgentIMResultQueue,
                send: @escaping @Sendable (AgentIMResultQueue.Entry) async -> AgentIMSendOutcome) {
        self.queue = queue
        self.send = send
    }

    /// 逐条发；**发成才 ack**。一条失败不挡后面的（别让一条坏目标把整队堵住），
    /// 但会如实记 `lastFailure`。
    public func run() async -> Report {
        var report = Report()
        for entry in queue.pending() where entry.target != nil {
            let outcome = await send(entry)
            if outcome.isDelivered {
                try? queue.ack(id: entry.id)
                report.delivered += 1
            } else {
                report.failed += 1
                report.lastFailure = outcome
            }
        }
        return report
    }
}

/// 结局的人话（句子拼法收在 Core：界面只搬结论）。
public enum AgentIMSendText {

    public static func line(for outcome: AgentIMSendOutcome, language: AppLanguage) -> String {
        switch outcome {
        case .delivered: return LocalizedStrings.text(.agentIMSendDelivered, language: language)
        case .notReady(let code):
            return LocalizedStrings.format(.agentIMSendNotReady, language: language, code)
        case .unauthorized:
            return LocalizedStrings.text(.agentIMSendUnauthorized, language: language)
        case .forbidden:
            return LocalizedStrings.text(.agentIMSendForbidden, language: language)
        case .rateLimited:
            return LocalizedStrings.text(.agentIMSendRateLimited, language: language)
        case .serverFailed:
            return LocalizedStrings.text(.agentIMSendServerFailed, language: language)
        case .responseNotJSON:
            return LocalizedStrings.text(.agentIMSendNotJSON, language: language)
        case .rejected(let status, let code):
            return LocalizedStrings.format(.agentIMSendRejected, language: language,
                                          Int64(status), code ?? "—")
        case .networkFailed:
            return LocalizedStrings.text(.agentIMSendNetworkFailed, language: language)
        }
    }
}
