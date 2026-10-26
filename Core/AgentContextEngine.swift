import Foundation

/// **引擎生命周期钩子**（详设 §3.23 · `FR-AGT-CORE-CTX-001` / `FR-AGT-OPS-OBS-001` · 本端计划 P1-11）。
///
/// 五钩子，**封闭集合**（加第六个要走版本与矩阵）：
/// `onSessionStart` → 每响应 `updateFromResponse` → 每轮 `shouldCompress` / `compress` → `onSessionEnd`。
///
/// 三条硬约束：
/// ① 任何钩子失败都**不得中断会话主循环**（记降级日志后继续）；
/// ② `onSessionEnd` 每次**真实**会话结束恰好一次（不重复、不遗漏）；
/// ③ 回合内调 `onSessionEnd` 直接拒 —— 边界判定权在会话层，不在调用方。
public enum AgentHookOutcome: Equatable, Sendable {
    case ok
    case degraded(reason: String)
    case failed(code: String)
    /// 引擎未注册：如实报「没有引擎」，不假装跑过。
    case skipped(reason: String)

    public var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

public enum AgentSessionEndReason: String, Codable, Sendable, CaseIterable {
    case cliExit
    case sessionReset
    case gatewayExpiry
}

public enum AgentHookRefusal: Error, Equatable, Sendable {
    /// 回合内被调 end：边界判定权不在调用方。
    case notASessionBoundary
}

/// 钩子集（顺序即执行顺序）。
public enum AgentContextHook: String, CaseIterable, Sendable {
    case onSessionStart
    case updateFromResponse
    case shouldCompress
    case compress
    case onSessionEnd
}

public struct AgentHookLogEntry: Equatable, Sendable {
    public var hook: AgentContextHook
    public var sessionID: String
    public var outcome: AgentHookOutcome
    /// 只有 `onSessionEnd` 带。
    public var boundaryKind: AgentSessionEndReason?

    public init(hook: AgentContextHook, sessionID: String, outcome: AgentHookOutcome,
                boundaryKind: AgentSessionEndReason? = nil) {
        self.hook = hook
        self.sessionID = sessionID
        self.outcome = outcome
        self.boundaryKind = boundaryKind
    }
}

/// 引擎协议：方法**可抛错** —— 宿主负责把抛错折成 `.failed(code:)` 并继续会话。
public protocol AgentContextEngine: Sendable {
    func onSessionStart() throws -> AgentHookOutcome
    func updateFromResponse(_ text: String) throws -> AgentHookOutcome
    func shouldCompress() throws -> AgentHookOutcome
    func compress() throws -> AgentHookOutcome
    func onSessionEnd() throws -> AgentHookOutcome
}

public extension AgentContextEngine {
    func onSessionStart() throws -> AgentHookOutcome { .ok }
    func updateFromResponse(_ text: String) throws -> AgentHookOutcome { .ok }
    func shouldCompress() throws -> AgentHookOutcome { .ok }
    func compress() throws -> AgentHookOutcome { .ok }
    func onSessionEnd() throws -> AgentHookOutcome { .ok }
}

/// 钩子宿主：串行执行、记日志、管边界与幂等。
public struct AgentContextEngineHost: Sendable {
    public let sessionID: String
    private let engine: (any AgentContextEngine)?
    public private(set) var log: [AgentHookLogEntry] = []
    /// 首次 `onSessionEnd` 的结局（幂等返回它）。
    public private(set) var endOutcome: Result<AgentHookOutcome, AgentHookRefusal>?
    public private(set) var isSessionOpen: Bool = true

    public init(sessionID: String, engine: (any AgentContextEngine)?) {
        self.sessionID = sessionID
        self.engine = engine
    }

    private mutating func run(_ hook: AgentContextHook,
                              boundary: AgentSessionEndReason? = nil,
                              _ body: (any AgentContextEngine) throws -> AgentHookOutcome) -> AgentHookOutcome {
        guard let engine else {
            let outcome = AgentHookOutcome.skipped(reason: "noEngine")
            log.append(AgentHookLogEntry(hook: hook, sessionID: sessionID, outcome: outcome, boundaryKind: boundary))
            return outcome
        }
        let outcome: AgentHookOutcome
        do {
            outcome = try body(engine)
        } catch {
            // 钩子抛错 ⇒ 折成 failed，**不中断会话**。
            outcome = .failed(code: "thrown")
        }
        log.append(AgentHookLogEntry(hook: hook, sessionID: sessionID, outcome: outcome, boundaryKind: boundary))
        return outcome
    }

    @discardableResult
    public mutating func startSession() -> AgentHookOutcome {
        run(.onSessionStart) { try $0.onSessionStart() }
    }

    @discardableResult
    public mutating func update(_ text: String) -> AgentHookOutcome {
        run(.updateFromResponse) { try $0.updateFromResponse(text) }
    }

    @discardableResult
    public mutating func shouldCompress() -> AgentHookOutcome {
        run(.shouldCompress) { try $0.shouldCompress() }
    }

    @discardableResult
    public mutating func compress() -> AgentHookOutcome {
        run(.compress) { try $0.compress() }
    }

    /// 会话结束。`sessionOpen: false` 表示这是**回合内**调用（没有真实边界）⇒ 直接拒，且**不触发**引擎钩子。
    @discardableResult
    public mutating func endSession(at reason: AgentSessionEndReason,
                                    sessionOpen: Bool = true) -> Result<AgentHookOutcome, AgentHookRefusal> {
        guard sessionOpen else {
            return .failure(.notASessionBoundary)
        }
        if let first = endOutcome { return first }   // 幂等：网关过期与 CLI 退出可能同时到
        isSessionOpen = false
        let outcome = run(.onSessionEnd, boundary: reason) { try $0.onSessionEnd() }
        let result = Result<AgentHookOutcome, AgentHookRefusal>.success(outcome)
        endOutcome = result
        return result
    }

    /// 某钩子被真正调用过几次（判据 T-3.23-01 直接断言它 == 1）。
    public func callCount(of hook: AgentContextHook) -> Int {
        log.filter { $0.hook == hook }.count
    }
}
