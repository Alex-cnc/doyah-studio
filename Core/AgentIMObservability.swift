import Foundation

/// IM 通道的**可观测面**（`FR-AGT-LINK-CHAN-003` ⑥）：状态页要能回答四个问题。
///
/// 由头（主人 2026-11-08：「beta1.2.x 主要是两个功能的完善：多 provider 支持、IM 通道功能」）：
/// 面板此前只有一行「已连接 / 未接通 + 原因」，而真正要问的四件事答不全 ——
/// **现在连上没有**、**上次成功收 / 发是什么时候**、**还有几条没发出去**、
/// **最近一次失败到底为什么**（人话，不是原始 JSON）。
///
/// 这一层只做**记账与读数**，不碰网络、也不猜状态：
/// · 连接状态**只认传输层发出来的那一档**（`AgentIMConnectionState`，界面不许自己画绿）；
/// · 收发时刻由**真的发生**那一刻写入（收到一帧 / 投递成功才写，计划 / 尝试都不算）；
/// · 待发条数**现读队列**（不是另记一个计数器 —— 两份账迟早对不上）；
/// · 失败原因存**机器码 + 阶段**，人话在读取时按当前语言翻（`AgentIMStatusText.reasonLine`）。
public struct AgentIMStatusReading: Equatable, Sendable {

    /// 四读数各有固定的身份（判据按身份逐条断言，不按数组下标）。
    public enum Kind: String, CaseIterable, Equatable, Sendable {
        /// 当前连接状态。
        case connection
        /// 上次成功收发时间。
        case delivery
        /// 待发队列条数。
        case queue
        /// 最近一次失败原因（人话）。
        case failure
    }

    public var kind: Kind
    /// 标题（语言表给，界面不自己拼）。
    public var title: String
    /// 读数正文（真实值；占位符一律视为未通过判据）。
    public var value: String
    /// 这一条是不是在报「红的」（界面据此上色；读数本身仍要能读）。
    public var isFault: Bool

    public init(kind: Kind, title: String, value: String, isFault: Bool = false) {
        self.kind = kind
        self.title = title
        self.value = value
        self.isFault = isFault
    }
}

/// 一次失败的留痕（**阶段 + 机器码**；人话在读取时翻，避免记账时把语言钉死）。
public struct AgentIMFailureNote: Equatable, Sendable {

    /// 失败发生在哪一环 —— 自检五环与状态页共用同一套名字，读起来才对得上。
    public enum Stage: String, CaseIterable, Equatable, Sendable {
        case configuration
        case connect
        case receive
        case send
        case run

        public var textKey: LKey {
            switch self {
            case .configuration: return .agentIMStageConfiguration
            case .connect: return .agentIMStageConnect
            case .receive: return .agentIMStageReceive
            case .send: return .agentIMStageSend
            case .run: return .agentIMStageRun
            }
        }
    }

    public var stage: Stage
    /// 机器码（`connectFailed` / `unauthorized` / `heartbeatLost`…）。不认识的码原样贴出来。
    public var code: String
    public var at: Date

    public init(stage: Stage, code: String, at: Date = Date()) {
        self.stage = stage
        self.code = code
        self.at = at
    }
}

/// 通道状态账本（宿主持有一份；`@Published` 友好，值类型）。
///
/// 为什么是值类型而不是 actor：它只在主线程被写（入站处理、投递回执、状态回调都在
/// `@MainActor` 上收尾），读的时候要**同步**给界面 —— 放进 actor 只会让面板每次刷新都异步一跳。
public struct AgentIMChannelStatusBoard: Equatable, Sendable {

    public private(set) var lastInboundAt: Date?
    public private(set) var lastOutboundAt: Date?
    /// 被判为重复而**没有执行**的平台消息条数（判据 ① 的读数：重投 3 次 ⇒ 这里记 2）。
    public private(set) var duplicatesDropped: Int = 0
    public private(set) var lastFailure: AgentIMFailureNote?

    public init(lastInboundAt: Date? = nil,
                lastOutboundAt: Date? = nil,
                duplicatesDropped: Int = 0,
                lastFailure: AgentIMFailureNote? = nil) {
        self.lastInboundAt = lastInboundAt
        self.lastOutboundAt = lastOutboundAt
        self.duplicatesDropped = duplicatesDropped
        self.lastFailure = lastFailure
    }

    public mutating func recordInbound(at: Date = Date()) { lastInboundAt = at }

    public mutating func recordOutbound(at: Date = Date()) {
        lastOutboundAt = at
        // 成功一次就清掉旧失败：否则上一条红字会一直挂着，像「现在还在失败」。
        lastFailure = nil
    }

    public mutating func recordDuplicate() { duplicatesDropped += 1 }

    public mutating func recordFailure(_ note: AgentIMFailureNote) { lastFailure = note }

    public mutating func recordFailure(stage: AgentIMFailureNote.Stage, code: String,
                                       at: Date = Date()) {
        lastFailure = AgentIMFailureNote(stage: stage, code: code, at: at)
    }

    public mutating func clearFailure() { lastFailure = nil }

    /// 四个读数 —— **每一条都给真值**（没发生过就说「还没」，不拿占位符凑）。
    ///
    /// `pending` 由调用方现读结果队列（`AgentIMResultQueue.pending().count`）传进来：
    /// 这一层不持有队列，也不自己再记一个数（两份账迟早对不上）。
    public func readings(connection: AgentIMConnectionState,
                         readiness: AgentIMReadiness,
                         pending: Int,
                         now: Date = Date(),
                         language: AppLanguage) -> [AgentIMStatusReading] {
        [
            AgentIMStatusReading(
                kind: .connection,
                title: LocalizedStrings.text(.agentIMReadingConnection, language: language),
                value: AgentIMStatusText.line(for: AgentIMStatusKind.of(readiness: readiness,
                                                                        connection: connection),
                                              language: language),
                isFault: !connection.isOnline),
            AgentIMStatusReading(
                kind: .delivery,
                title: LocalizedStrings.text(.agentIMReadingDelivery, language: language),
                value: deliveryLine(now: now, language: language)),
            AgentIMStatusReading(
                kind: .queue,
                title: LocalizedStrings.text(.agentIMReadingQueue, language: language),
                value: LocalizedStrings.format(.agentIMReadingPending, language: language,
                                               Int64(max(0, pending))),
                isFault: pending > 0),
            AgentIMStatusReading(
                kind: .failure,
                title: LocalizedStrings.text(.agentIMReadingFailure, language: language),
                value: failureLine(language: language),
                isFault: lastFailure != nil),
        ]
    }

    /// 「收 12:03:44 · 发 12:05:10」；一次都没成就说「还没成功收发过」（不写 `--` 糊过去）。
    func deliveryLine(now: Date, language: AppLanguage) -> String {
        guard lastInboundAt != nil || lastOutboundAt != nil else {
            return LocalizedStrings.text(.agentIMReadingNoTraffic, language: language)
        }
        let inbound = lastInboundAt.map(Self.clock) ?? "—"
        let outbound = lastOutboundAt.map(Self.clock) ?? "—"
        return LocalizedStrings.format(.agentIMReadingTimes, language: language, inbound, outbound)
    }

    /// 「收消息：连接失败（connectFailed）」这种 —— **先说是哪一环，再说是为什么**。
    func failureLine(language: AppLanguage) -> String {
        guard let failure = lastFailure else {
            return LocalizedStrings.text(.agentIMReadingNoFailure, language: language)
        }
        let stage = LocalizedStrings.text(failure.stage.textKey, language: language)
        let reason = AgentIMStatusText.reasonLine(failure.code, language: language)
        return LocalizedStrings.format(.agentIMReadingFailureLine, language: language, stage, reason)
    }

    /// 固定 24 小时制（跨语言同一口径；不跟系统区域设置漂）。
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
