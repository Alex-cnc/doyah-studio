import Foundation

/// IM 通道的**自检**（主人 2026-10-30：「我配置了，貌似不起作用」）。
///
/// 教训：配置面板只显示「已保存」不够 —— 用户要的是「现在到底缺哪一样」。
/// 所以把「配置面在不在盘上 / 有没有 AppID / 钥匙串里有没有 Secret / 选没选环境」收成一份
/// **有顺序的问题清单**（先修哪个写在最前），界面照着念，不用猜。
public struct AgentIMSelfCheckFacts: Equatable, Sendable {

    public var appID: String
    public var hasSecret: Bool
    public var environment: AgentIMQQEnvironment?
    public var receiveTasks: Bool
    public var configFileExists: Bool

    public init(appID: String, hasSecret: Bool, environment: AgentIMQQEnvironment?,
                receiveTasks: Bool, configFileExists: Bool) {
        self.appID = appID
        self.hasSecret = hasSecret
        self.environment = environment
        self.receiveTasks = receiveTasks
        self.configFileExists = configFileExists
    }
}

public enum AgentIMSelfCheckProblem: String, Equatable, Sendable, CaseIterable {
    /// 配置文件没落盘（点了保存但盘上没有 ⇒ 保存那一步没成）。
    case configFileMissing
    /// 没填 AppID。
    case appIDMissing
    /// AppID 不是纯数字（QQ 的 AppID 一定是数字）。
    case appIDNotNumeric
    /// 钥匙串里没有 Secret。
    case secretMissing
    /// 没选环境（正式 / 沙箱）。
    case environmentMissing
}

public enum AgentIMSelfCheck {

    /// 问题清单，**按该修的先后排**：先让配置落盘，再补字段，最后才是环境。
    public static func problems(_ facts: AgentIMSelfCheckFacts) -> [AgentIMSelfCheckProblem] {
        var found: [AgentIMSelfCheckProblem] = []
        if !facts.configFileExists { found.append(.configFileMissing) }
        let trimmed = facts.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { found.append(.appIDMissing) }
        else if trimmed.contains(where: { !$0.isNumber }) { found.append(.appIDNotNumeric) }
        if !facts.hasSecret { found.append(.secretMissing) }
        if facts.environment == nil { found.append(.environmentMissing) }
        return found
    }

    public static func isReady(_ facts: AgentIMSelfCheckFacts) -> Bool {
        problems(facts).isEmpty
    }

    /// 问题的人话（自检第一条读数用；界面不再自己拼「缺哪个」）。
    public static func line(for problem: AgentIMSelfCheckProblem, language: AppLanguage) -> String {
        switch problem {
        case .configFileMissing:
            return LocalizedStrings.text(.agentIMSelfCheckNoConfig, language: language)
        case .appIDMissing:
            return LocalizedStrings.text(.agentIMSelfCheckNoAppID, language: language)
        case .appIDNotNumeric:
            return LocalizedStrings.text(.agentIMSelfCheckBadAppID, language: language)
        case .secretMissing:
            return LocalizedStrings.text(.agentIMSelfCheckNoSecret, language: language)
        case .environmentMissing:
            return LocalizedStrings.text(.agentIMSelfCheckNoEnvironment, language: language)
        }
    }
}

// MARK: - 五环自检（一键跑通，任一环失败能指到哪一环）

/// 自检的**五环**（顺序固定 = 面板上的排列顺序，也是「先修哪一个」的顺序）。
///
/// 为什么从「一张问题清单」升成「五环」：清单只回答「配置齐不齐」，
/// 而「我配置了、貌似不起作用」这句话可以停在五个不同的地方 —— 配置没落盘、
/// 凭据取不到 token、握手口径不对、收不到帧、发不出去。**每一环都要有自己的读数**，
/// 红了要能指着那一环说「就这里」，而不是笼统一句「连不上」。
public enum AgentIMSelfCheckRing: String, CaseIterable, Equatable, Sendable {
    /// ① 配置完整（配置文件在盘 / AppID / Secret / 环境）。
    case configuration
    /// ② token 可取（拿 AppID + Secret 换 access_token）。
    case token
    /// ③ 握手成功（WebSocket 建连 + Identify + READY）。
    case handshake
    /// ④ 收一帧（网关真的往下发东西）。
    case receive
    /// ⑤ 发一帧（写出成功 —— 发送路径通，不是「对方收到了」）。
    case send

    public var titleKey: LKey {
        switch self {
        case .configuration: return .agentIMSelfCheckRingConfiguration
        case .token: return .agentIMSelfCheckRingToken
        case .handshake: return .agentIMSelfCheckRingHandshake
        case .receive: return .agentIMSelfCheckRingReceive
        case .send: return .agentIMSelfCheckRingSend
        }
    }
}

/// 一环的结论（**三档**：过 / 红 / 被前一环挡住）。
///
/// 「被挡住」必须与「红」分开：Secret 是空的，后四环根本没跑 ——
/// 把它们一并画红，人就会去查四个并不存在的问题（判据 ⑤ 的反例正是这一条）。
public enum AgentIMSelfCheckVerdict: Equatable, Sendable {
    case passed(detail: String)
    case failed(code: String, detail: String)
    case blocked(by: AgentIMSelfCheckRing, detail: String)

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    public var isPassed: Bool {
        if case .passed = self { return true }
        return false
    }
}

/// 一环的读数（面板逐行念的就是它）。
public struct AgentIMSelfCheckReadout: Equatable, Sendable {
    public var ring: AgentIMSelfCheckRing
    public var title: String
    public var verdict: AgentIMSelfCheckVerdict
    /// 面板那一行（标题 + 结论，已按语言拼好）。
    public var line: String

    public init(ring: AgentIMSelfCheckRing, title: String,
                verdict: AgentIMSelfCheckVerdict, line: String) {
        self.ring = ring
        self.title = title
        self.verdict = verdict
        self.line = line
    }
}

/// 一次自检的完整读数。
public struct AgentIMSelfCheckReport: Equatable, Sendable {
    public var readouts: [AgentIMSelfCheckReadout]

    public init(readouts: [AgentIMSelfCheckReadout]) {
        self.readouts = readouts
    }

    /// 第一环红的（`nil` = 没有红）。
    public var failedRing: AgentIMSelfCheckRing? {
        readouts.first { $0.verdict.isFailed }?.ring
    }

    public var isAllGreen: Bool { readouts.allSatisfy { $0.verdict.isPassed } }

    public var passedCount: Int { readouts.filter { $0.verdict.isPassed }.count }

    /// 面板的一行汇总（逐环读数仍逐条列）。
    public func summary(language: AppLanguage) -> String {
        if let failed = failedRing {
            return LocalizedStrings.format(.agentIMSelfCheckFailedAt, language: language,
                                           Int64(readouts.firstIndex { $0.ring == failed }.map { $0 + 1 } ?? 0))
        }
        return LocalizedStrings.format(.agentIMSelfCheckPassedCount, language: language,
                                       Int64(passedCount), Int64(readouts.count))
    }
}

/// 一环的探针结论（探针只报事实：过 / 不过 + 一句可读读数）。
public struct AgentIMSelfCheckStep: Equatable, Sendable {
    public var ok: Bool
    public var detail: String
    /// 失败时的机器码（`tokenMissing` / `connectFailed`…）；成功可为空。
    public var code: String?

    public init(ok: Bool, detail: String, code: String? = nil) {
        self.ok = ok
        self.detail = detail
        self.code = code
    }

    public static func pass(_ detail: String) -> AgentIMSelfCheckStep {
        AgentIMSelfCheckStep(ok: true, detail: detail)
    }

    public static func fail(_ code: String, _ detail: String) -> AgentIMSelfCheckStep {
        AgentIMSelfCheckStep(ok: false, detail: detail, code: code)
    }
}

/// 五个探针（宿主给：真实现走 provisioner / socket；判据给假的）。
public struct AgentIMSelfCheckProbes: Sendable {
    public var facts: AgentIMSelfCheckFacts
    /// ② 取 token：成功时 `detail` 里写「尾 4 位 / 还剩多久」。
    public var token: @Sendable () async -> AgentIMSelfCheckStep
    /// ③ 握手：建连 + Identify + 等到 READY。
    public var handshake: @Sendable () async -> AgentIMSelfCheckStep
    /// ④ 收一帧。
    public var receive: @Sendable () async -> AgentIMSelfCheckStep
    /// ⑤ 发一帧（写出成功即可：这一环量的是发送路径，不是对方是否收到）。
    public var send: @Sendable () async -> AgentIMSelfCheckStep

    public init(facts: AgentIMSelfCheckFacts,
                token: @escaping @Sendable () async -> AgentIMSelfCheckStep,
                handshake: @escaping @Sendable () async -> AgentIMSelfCheckStep,
                receive: @escaping @Sendable () async -> AgentIMSelfCheckStep,
                send: @escaping @Sendable () async -> AgentIMSelfCheckStep) {
        self.facts = facts
        self.token = token
        self.handshake = handshake
        self.receive = receive
        self.send = send
    }
}

/// 五环的跑法：**顺序执行，第一环红了就停**（后面四环记「被前一环挡住」，不记红）。
public enum AgentIMSelfCheckRunner {

    public static func run(_ probes: AgentIMSelfCheckProbes,
                           language: AppLanguage) async -> AgentIMSelfCheckReport {
        var readouts: [AgentIMSelfCheckReadout] = []
        var blocker: AgentIMSelfCheckRing?

        // ① 配置：只读事实，不碰网络。
        let problems = AgentIMSelfCheck.problems(probes.facts)
        if problems.isEmpty {
            let tail = String(probes.facts.appID.suffix(4))
            let detail = LocalizedStrings.format(.agentIMSelfCheckConfigDetail, language: language,
                                                 tail.isEmpty ? "—" : tail)
            readouts.append(readout(.configuration, verdict: .passed(detail: detail),
                                    language: language))
        } else {
            let detail = problems.map { AgentIMSelfCheck.line(for: $0, language: language) }
                .joined(separator: language == .english ? "; " : "；")
            readouts.append(readout(.configuration,
                                    verdict: .failed(code: problems.first?.rawValue ?? "config",
                                                     detail: detail),
                                    language: language))
            blocker = .configuration
        }

        // ②–⑤ 依次跑；被挡住的那几环**一条都不跑**（跑也没意义，读数会是假的）。
        let stages: [(AgentIMSelfCheckRing, @Sendable () async -> AgentIMSelfCheckStep)] = [
            (.token, probes.token),
            (.handshake, probes.handshake),
            (.receive, probes.receive),
            (.send, probes.send),
        ]
        for (ring, probe) in stages {
            if let blocker {
                readouts.append(readout(ring, verdict: .blocked(by: blocker, detail: ""),
                                        language: language))
                continue
            }
            let step = await probe()
            if step.ok {
                readouts.append(readout(ring, verdict: .passed(detail: step.detail),
                                        language: language))
            } else {
                readouts.append(readout(ring,
                                        verdict: .failed(code: step.code ?? "failed", detail: step.detail),
                                        language: language))
                blocker = ring
            }
        }
        return AgentIMSelfCheckReport(readouts: readouts)
    }

    /// 一环 → 面板那一行（标题 + 结论；三档各有各的说法）。
    static func readout(_ ring: AgentIMSelfCheckRing,
                        verdict: AgentIMSelfCheckVerdict,
                        language: AppLanguage) -> AgentIMSelfCheckReadout {
        let title = LocalizedStrings.text(ring.titleKey, language: language)
        let line: String
        switch verdict {
        case .passed(let detail):
            line = LocalizedStrings.format(.agentIMSelfCheckRingPassed, language: language,
                                           title, detail)
        case .failed(_, let detail):
            line = LocalizedStrings.format(.agentIMSelfCheckRingFailed, language: language,
                                           title, detail)
        case .blocked(let by, _):
            line = LocalizedStrings.format(.agentIMSelfCheckRingBlocked, language: language,
                                           title, LocalizedStrings.text(by.titleKey, language: language))
        }
        return AgentIMSelfCheckReadout(ring: ring, title: title, verdict: verdict, line: line)
    }
}
