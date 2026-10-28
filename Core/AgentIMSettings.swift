import Foundation

/// IM 通道的**非敏感配置面**（`FR-AGT-LINK-CHAN-003`）：网关端点 / 机器人标识 / 接收任务开关。
///
/// 与凭据分家的理由：这三样**可以明文进配置文件**（面板要回显、用户要能核对），
/// 而 AppID 只说「配没配」、Secret 只在钥匙串里。合成一份 `AgentIMChannelSettings`
/// 是为了让「配齐了没」只有一个判定处 —— 面板、连接按钮、测试按钮读同一份答复。
public struct AgentIMChannelSettings: Codable, Equatable, Sendable {

    /// 网关端点（`ws://` / `wss://`）。空串 = 没配（不是「用默认值」—— 本侧不替 QQ 网关编默认地址）。
    public var gatewayURL: String
    /// 机器人标识（网关侧认得出的那一个；不打成数字 —— 官方口径一变不至于把人挡在门外）。
    public var botIdentifier: String
    /// 接收任务开关：关掉 = 不收聊天里派来的活（已排队的结果仍留在结果队列里等补发）。
    public var receiveTasks: Bool

    public init(gatewayURL: String = "", botIdentifier: String = "", receiveTasks: Bool = false) {
        self.gatewayURL = gatewayURL
        self.botIdentifier = botIdentifier
        self.receiveTasks = receiveTasks
    }

    /// 一份全空的配置（判据与「从没配过」同义）。
    public static let empty = AgentIMChannelSettings()

    public var isEmpty: Bool {
        gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && botIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 配置面的拒绝原因（机器码；人话在语言表）。
///
/// 为什么不并进 `AgentIMCredentialProblem`：凭据那几条讲的是 AppID / Secret，
/// 这几条讲的是地址与标识 —— 混成一个枚举后，面板一处 `switch` 就会把
/// 「AppID 不是数字」说成「网关地址不对」。两族分开，文案才说得准。
public enum AgentIMSettingsProblem: String, Error, Equatable, Sendable, CaseIterable {
    case gatewayURLMissing
    case gatewayURLMalformed
    case gatewayURLNotWebSocket
    case gatewayURLMissingHost
    case gatewayURLHasWhitespace
    case botIdentifierEmpty
    case botIdentifierHasWhitespace
    case botIdentifierTooLong
}

/// 配置面的规范化与校验。
///
/// 两条口径：
/// ① **只挡明显粘错**（把 URL 粘进标识、写成 `http://`、内部带空格），
///    不假装知道 QQ 网关的地址形状与标识位数 —— 真正的对错由「测试连接」真发一帧说了算；
/// ② 校验与规范化是**同一个函数**：存进盘的是规范化之后的写法，判据与面板读到的是同一份
///    （两处各归一一次，就会出现「面板说已配齐、落盘那份仍然带尾随空格」）。
public enum AgentIMSettingsValidator {

    /// 标识位数上限：防粘错（把整段 URL 粘进标识那一格），不是官方规定。
    public static let maxBotIdentifierLength = 64

    public static func normalizedGatewayURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AgentIMSettingsProblem.gatewayURLMissing }
        guard !trimmed.contains(where: { $0.isWhitespace }) else {
            throw AgentIMSettingsProblem.gatewayURLHasWhitespace
        }
        guard let components = URLComponents(string: trimmed) else {
            throw AgentIMSettingsProblem.gatewayURLMalformed
        }
        let scheme = (components.scheme ?? "").lowercased()
        // 只说 ws / wss：写成 http(s) 的人以为能连，实际建的是另一条会话 —— 这一格当场说清。
        guard scheme == "ws" || scheme == "wss" else {
            throw AgentIMSettingsProblem.gatewayURLNotWebSocket
        }
        guard let host = components.host, !host.isEmpty else {
            throw AgentIMSettingsProblem.gatewayURLMissingHost
        }
        guard let url = components.url else { throw AgentIMSettingsProblem.gatewayURLMalformed }
        return url
    }

    public static func normalizedBotIdentifier(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AgentIMSettingsProblem.botIdentifierEmpty }
        guard !trimmed.contains(where: { $0.isWhitespace }) else {
            throw AgentIMSettingsProblem.botIdentifierHasWhitespace
        }
        guard trimmed.count <= maxBotIdentifierLength else {
            throw AgentIMSettingsProblem.botIdentifierTooLong
        }
        return trimmed
    }

    /// 一次列出**全部**问题（面板一次把人要改的地方都点出来，不让人改一处再点一次）。
    /// 顺序固定：先地址后标识 —— 顺序会漂的清单在界面上一闪就换位置。
    public static func problems(in settings: AgentIMChannelSettings) -> [AgentIMSettingsProblem] {
        var found: [AgentIMSettingsProblem] = []
        do {
            _ = try normalizedGatewayURL(settings.gatewayURL)
        } catch let problem as AgentIMSettingsProblem {
            found.append(problem)
        } catch {
            found.append(.gatewayURLMalformed)
        }
        do {
            _ = try normalizedBotIdentifier(settings.botIdentifier)
        } catch let problem as AgentIMSettingsProblem {
            found.append(problem)
        } catch {
            found.append(.botIdentifierEmpty)
        }
        return found
    }

    /// 规范化整份配置（保存前调用一次；不合法就抛第一条问题）。
    public static func normalized(_ settings: AgentIMChannelSettings) throws -> AgentIMChannelSettings {
        let url = try normalizedGatewayURL(settings.gatewayURL)
        let identifier = try normalizedBotIdentifier(settings.botIdentifier)
        return AgentIMChannelSettings(
            gatewayURL: url.absoluteString,
            botIdentifier: identifier,
            receiveTasks: settings.receiveTasks
        )
    }
}

/// 通道要连起来需要的四样（顺序固定 = 面板上的排列顺序）。
public enum AgentIMConfigField: String, CaseIterable, Equatable, Sendable {
    case gatewayURL
    case botIdentifier
    case appID
    case secret
}

/// 「配齐了没」的唯一答复（面板 / 连接按钮 / 测试按钮读同一份）。
public struct AgentIMReadiness: Equatable, Sendable {

    /// 还缺哪几样（有序；空 = 配齐）。
    public var missing: [AgentIMConfigField]

    public init(missing: [AgentIMConfigField]) {
        self.missing = missing
    }

    public var isReady: Bool { missing.isEmpty }

    /// 「配过一点」与「一样没配」在面板上要说不同的话：前者是「还缺什么」，后者是「从哪开始」。
    public var isConfigured: Bool { missing.count < AgentIMConfigField.allCases.count }

    /// 四样的判定 —— **一处**（界面上不许再自己拼一遍「有没有 AppID」）。
    public static func evaluate(settings: AgentIMChannelSettings,
                               appID: String?,
                               secretConfigured: Bool) -> AgentIMReadiness {
        var missing: [AgentIMConfigField] = []
        if (try? AgentIMSettingsValidator.normalizedGatewayURL(settings.gatewayURL)) == nil {
            missing.append(.gatewayURL)
        }
        if (try? AgentIMSettingsValidator.normalizedBotIdentifier(settings.botIdentifier)) == nil {
            missing.append(.botIdentifier)
        }
        if (appID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append(.appID)
        }
        if !secretConfigured { missing.append(.secret) }
        return AgentIMReadiness(missing: missing)
    }
}

/// 状态行的机器形态：把「配置齐不齐」与「传输层状态」合成**一档**。
///
/// 为什么要合成：面板只有一行位置。分成两行迟早出现「上面写未配置、下面写已连接」这种
/// 自相矛盾的假绿 —— 合成一处判定，矛盾就写不出来。
public enum AgentIMStatusKind: Equatable, Sendable {
    case unconfigured([AgentIMConfigField])
    case readyToConnect
    case connecting(attempt: Int)
    case online(attempt: Int)
    case waiting(reason: String, retryIn: TimeInterval)
    case stopped(reason: String)

    public var isOnline: Bool {
        if case .online = self { return true }
        return false
    }

    public static func of(readiness: AgentIMReadiness,
                          connection: AgentIMConnectionState) -> AgentIMStatusKind {
        guard readiness.isReady else { return .unconfigured(readiness.missing) }
        switch connection {
        case .idle: return .readyToConnect
        case .connecting(let attempt): return .connecting(attempt: attempt)
        case .online(let attempt): return .online(attempt: attempt)
        case .waiting(let reason, _, let retryIn): return .waiting(reason: reason, retryIn: retryIn)
        case .stopped(let reason): return .stopped(reason: reason)
        }
    }
}

/// 配置问题的人话（`language` 由调用方给：语言只有一个来源）。
public enum AgentIMSettingsProblemText {

    public static func line(for problem: AgentIMSettingsProblem, language: AppLanguage) -> String {
        switch problem {
        case .gatewayURLMissing: return LocalizedStrings.text(.agentIMGatewayURLMissing, language: language)
        case .gatewayURLMalformed: return LocalizedStrings.text(.agentIMGatewayURLMalformed, language: language)
        case .gatewayURLNotWebSocket: return LocalizedStrings.text(.agentIMGatewayURLNotWebSocket, language: language)
        case .gatewayURLMissingHost: return LocalizedStrings.text(.agentIMGatewayURLMissingHost, language: language)
        case .gatewayURLHasWhitespace: return LocalizedStrings.text(.agentIMGatewayURLHasWhitespace, language: language)
        case .botIdentifierEmpty: return LocalizedStrings.text(.agentIMBotIdentifierEmpty, language: language)
        case .botIdentifierHasWhitespace: return LocalizedStrings.text(.agentIMBotIdentifierHasWhitespace, language: language)
        case .botIdentifierTooLong: return LocalizedStrings.text(.agentIMBotIdentifierTooLong, language: language)
        }
    }
}

/// 字段名与状态行的人话（**界面不自己拼句子**：同一句话出现两处就会漂成两种说法）。
public enum AgentIMStatusText {

    public static func fieldName(_ field: AgentIMConfigField, language: AppLanguage) -> String {
        switch field {
        case .gatewayURL: return LocalizedStrings.text(.agentIMFieldGatewayURL, language: language)
        case .botIdentifier: return LocalizedStrings.text(.agentIMFieldBotIdentifier, language: language)
        case .appID: return LocalizedStrings.text(.agentIMFieldAppID, language: language)
        case .secret: return LocalizedStrings.text(.agentIMFieldSecret, language: language)
        }
    }

    /// 「还缺 A / B」里的那一段（分隔符用 ASCII，避免多语言标点各写一份）。
    public static func fieldList(_ fields: [AgentIMConfigField], language: AppLanguage) -> String {
        fields.map { fieldName($0, language: language) }.joined(separator: " / ")
    }

    public static func line(for kind: AgentIMStatusKind, language: AppLanguage) -> String {
        switch kind {
        case .unconfigured(let missing):
            return LocalizedStrings.format(.agentIMStatusUnconfigured, language: language,
                                          fieldList(missing, language: language))
        case .readyToConnect:
            return LocalizedStrings.text(.agentIMStatusReady, language: language)
        case .connecting(let attempt):
            return LocalizedStrings.format(.agentIMStatusConnecting, language: language, Int64(attempt))
        case .online(let attempt):
            return LocalizedStrings.format(.agentIMStatusOnline, language: language, Int64(attempt))
        case .waiting(let reason, let retryIn):
            let seconds = Int64(max(0, retryIn.rounded(.up)))
            return LocalizedStrings.format(.agentIMStatusWaiting, language: language,
                                          reasonLine(reason, language: language), seconds)
        case .stopped(let reason):
            return LocalizedStrings.format(.agentIMStatusStopped, language: language,
                                          reasonLine(reason, language: language))
        }
    }

    /// 传输层给的是**机器码**（`connectFailed` / `receiveFailed` / `heartbeatLost` …）。
    /// 认识的翻人话；**不认识的原样把码贴出来**（编一句「网络错误」比贴码更误导）。
    public static func reasonLine(_ code: String, language: AppLanguage) -> String {
        switch code {
        case "connectFailed": return LocalizedStrings.text(.agentIMReasonConnectFailed, language: language)
        case "receiveFailed": return LocalizedStrings.text(.agentIMReasonReceiveFailed, language: language)
        case "heartbeatLost": return LocalizedStrings.text(.agentIMReasonHeartbeatLost, language: language)
        case "sendFailed": return LocalizedStrings.text(.agentIMReasonSendFailed, language: language)
        case "stopped": return LocalizedStrings.text(.agentIMReasonStopped, language: language)
        case "receiveDisabled": return LocalizedStrings.text(.agentIMReasonReceiveDisabled, language: language)
        default:
            return LocalizedStrings.format(.agentIMReasonUnknown, language: language, code)
        }
    }
}

/// 入站任务被拦下的原因（**不是异常**：关掉接收是正常状态，要能说清是哪一种）。
public enum AgentIMInboundDropReason: String, Equatable, Sendable {
    case notConfigured
    case notEnabled
    case notConnected
    /// 空白消息（一个空格 / 空串）：不起一轮，也不算跑过 —— 模型那边只会白烧一跳。
    case emptyText
}

/// 「这一帧进来的任务要不要接」的**唯一**判定处。
///
/// 三条都必须过：配置齐（否则连都没连上，谈不上守约）、开关开（用户明确关掉就一条都不收）、
/// 在线（离线时收到的帧本来就不可信）。三档原因分开，日志里才看得出是「用户关的」还是「掉线了」。
public enum AgentIMInboundPolicy {

    public static func decide(receiveTasks: Bool,
                              readiness: AgentIMReadiness,
                              connection: AgentIMConnectionState) -> AgentIMInboundDropReason? {
        guard readiness.isReady else { return .notConfigured }
        guard receiveTasks else { return .notEnabled }
        guard connection.isOnline else { return .notConnected }
        return nil
    }
}

/// 「测试连接」的结论（**四档**：连不上 / 发不出 / 连上但没应答 / 有应答）。
///
/// 为什么不是布尔：`open` 成功在 WebSocket 里几乎不说明什么（`resume()` 立刻返回），
/// 只说「连上了」会把「地址对但握手口径错」画成绿。四档里只有「收到一帧」算通。
public enum AgentIMProbeOutcome: Equatable, Sendable {
    case reachable
    case openFailed
    case sendFailed
    /// 连上了、也发出去了，但 `receiveTimeout` 内没等到任何一帧。
    case noResponse

    public var isReachable: Bool { self == .reachable }
}

/// 一次性收口（超时与真应答谁先到就用谁，第二次到达一律丢弃 —— 否则 continuation 会崩）。
private final class AgentIMProbeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func finish(_ body: () -> Void) {
        lock.lock()
        if finished { lock.unlock(); return }
        finished = true
        lock.unlock()
        body()
    }
}

/// 真发一帧看网关答不答（**只读探测**：进来什么样、出去什么样，不改任何配置）。
public enum AgentIMConnectivityProbe {

    /// 缺省等 6 秒：握手类不快，但也不让人以为卡死。
    public static let defaultReceiveTimeout: TimeInterval = 6

    public static func run(makeSocket: AgentIMSocketFactory,
                           url: URL,
                           headers: [String: String],
                           receiveTimeout: TimeInterval = defaultReceiveTimeout) async -> AgentIMProbeOutcome {
        let socket = makeSocket(url, headers)
        do {
            try await socket.open()
        } catch {
            await socket.close()
            return .openFailed
        }
        do {
            try await socket.send(AgentIMTransport.pingFrame)
        } catch {
            await socket.close()
            return .sendFailed
        }
        let outcome = await awaitFrame(socket, seconds: receiveTimeout)
        await socket.close()
        return outcome
    }

    /// 收一帧 vs 到点 —— 两个都起，先到的那个记账，另一个作废。
    private static func awaitFrame(_ socket: any AgentIMSocket, seconds: TimeInterval) async -> AgentIMProbeOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<AgentIMProbeOutcome, Never>) in
            let gate = AgentIMProbeGate()
            Task {
                do {
                    _ = try await socket.receive()
                    gate.finish { continuation.resume(returning: .reachable) }
                } catch {
                    gate.finish { continuation.resume(returning: .noResponse) }
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                gate.finish { continuation.resume(returning: .noResponse) }
            }
        }
    }

    /// 结论的人话（面板那一行）。
    public static func line(for outcome: AgentIMProbeOutcome, receiveTimeout: TimeInterval,
                            language: AppLanguage) -> String {
        switch outcome {
        case .reachable:
            return LocalizedStrings.text(.agentIMTestReachable, language: language)
        case .openFailed:
            return LocalizedStrings.text(.agentIMTestOpenFailed, language: language)
        case .sendFailed:
            return LocalizedStrings.text(.agentIMTestSendFailed, language: language)
        case .noResponse:
            let seconds = Int64(max(0, receiveTimeout.rounded(.up)))
            return LocalizedStrings.format(.agentIMTestNoResponse, language: language, seconds)
        }
    }
}
