import Foundation

/// 可配置（`FR-AGT-OPS-OBS-002`）：模型 / 工具白名单 / 审批策略 / 配额 / 通知规则都可改，
/// **改完立即生效**且**有据可查**（谁、什么时候、从什么改成什么、为什么）。
///
/// 判据三条：
/// ① 越界值**拒收并说清理由**（配额 ≤0、并发 ≤0、超时超过 1 小时 …），不许悄悄夹到边界；
/// ② 每次改动落一条 `AgentConfigChange`（旧值 / 新值 / 理由 / 时间），日志只追加；
/// ③ `effectiveImmediately` 的改动必须**在下一跳就生效** —— 实现上由「配置只读快照 + 每次循环取最新快照」保证，
///    这里钉住语义：`appliedSnapshot` 返回的就是改动后的快照，不允许"下次启动才生效"。
public struct AgentConfigChange: Equatable, Sendable {
    public var key: String
    public var oldValue: String?
    public var newValue: String
    public var reason: String
    public var at: Date

    public var summaryLine: String {
        "\(key): \(oldValue ?? "（未设）") → \(newValue)" + (reason.isEmpty ? "" : "（因为\(reason)）")
    }
}

public enum AgentConfigError: Error, Equatable, Sendable {
    case unknownKey(String)
    case outOfRange(key: String, value: String, allowed: String)
    /// 改配置不给理由 —— 和"改计划不说为什么"同一类，拒绝。
    case missingReason
}

public struct AgentConfigSnapshot: Equatable, Sendable {
    public var model: String
    public var maxConcurrentSubtasks: Int
    public var commandTimeoutSeconds: Int
    public var dailyTokenQuota: Int
    public var notificationsEnabled: Bool
    public var toolWhitelist: [String]
    /// **审批策略的基线**（`FR-AGT-OPS-OBS-002` 的「审批策略可配置」）。
    ///
    /// 语义只有一句：**工具调用之前先按这一档判**，插件钩子只能在它之上收紧
    /// （`AgentPolicyCombiner` 只许升档）。三档含义：
    /// · `.allow` = 旧行为（默认，不放宽也不收紧）；
    /// · `.requiresApproval` = 每件工具都先要人批（谨慎模式）；
    /// · `.deny` = 一律不执行（只读巡航 / 托管时的急停档）。
    /// 它不是「审批队列的替代」：基线到 `.requiresApproval` 之后，审批本身仍走既有队列，
    /// 这一档只决定「要不要先去排队」。
    public var approvalPolicy: AgentPolicyLevel

    public init(model: String = "默认", maxConcurrentSubtasks: Int = 3, commandTimeoutSeconds: Int = 60,
                dailyTokenQuota: Int = 200_000, notificationsEnabled: Bool = true,
                toolWhitelist: [String] = [], approvalPolicy: AgentPolicyLevel = .allow) {
        self.model = model
        self.maxConcurrentSubtasks = maxConcurrentSubtasks
        self.commandTimeoutSeconds = commandTimeoutSeconds
        self.dailyTokenQuota = dailyTokenQuota
        self.notificationsEnabled = notificationsEnabled
        self.toolWhitelist = toolWhitelist
        self.approvalPolicy = approvalPolicy
    }
}

/// 审批策略在**配置面**的三种写法（配置是文本进文本出，词表与解析只此一处）。
///
/// 为什么不接受 `requiresApproval` 这种内部枚举名：面板上那一格是给人填 / 给人读的，
/// 词表越短越不会写错；内部名改了也不该把盘上旧配置写坏。
public extension AgentPolicyLevel {
    /// 配置面词表（顺序 = 面板下拉的顺序，从宽到严）。
    static let configTokens: [String] = ["allow", "ask", "deny"]

    var configToken: String {
        switch self {
        case .allow: return "allow"
        case .requiresApproval: return "ask"
        case .deny: return "deny"
        }
    }

    /// 解析（大小写不敏感、去空白）。认不出的**必须返回 nil** —— 由调用方拒收并给理由，
    /// 不许在这里悄悄回落 `allow`（那是把「填错了」变成「放行了」）。
    init?(configToken: String) {
        switch configToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "allow": self = .allow
        case "ask": self = .requiresApproval
        case "deny": self = .deny
        default: return nil
        }
    }
}

public struct AgentConfigStore: Sendable {
    private(set) public var snapshot: AgentConfigSnapshot
    private(set) public var changes: [AgentConfigChange] = []

    public init(snapshot: AgentConfigSnapshot = AgentConfigSnapshot()) {
        self.snapshot = snapshot
    }

    /// 改一项：校验 → 落快照 → 落审计。失败时**快照与日志都不动**。
    public mutating func apply(key: String, value: String, reason: String, at: Date = Date()) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentConfigError.missingReason
        }
        var next = snapshot
        let old: String?
        switch key {
        case "model":
            old = snapshot.model
            guard !value.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw AgentConfigError.outOfRange(key: key, value: value, allowed: "非空模型名")
            }
            next.model = value
        case "maxConcurrentSubtasks":
            old = "\(snapshot.maxConcurrentSubtasks)"
            let n = try integer(key: key, value: value, range: 1...16, allowed: "1–16")
            next.maxConcurrentSubtasks = n
        case "commandTimeoutSeconds":
            old = "\(snapshot.commandTimeoutSeconds)"
            let n = try integer(key: key, value: value, range: 1...3600, allowed: "1–3600 秒")
            next.commandTimeoutSeconds = n
        case "dailyTokenQuota":
            old = "\(snapshot.dailyTokenQuota)"
            let n = try integer(key: key, value: value, range: 1_000...100_000_000, allowed: "1000–1 亿")
            next.dailyTokenQuota = n
        case "notificationsEnabled":
            old = "\(snapshot.notificationsEnabled)"
            guard ["true", "false"].contains(value.lowercased()) else {
                throw AgentConfigError.outOfRange(key: key, value: value, allowed: "true / false")
            }
            next.notificationsEnabled = (value.lowercased() == "true")
        case "toolWhitelist":
            old = snapshot.toolWhitelist.joined(separator: ",")
            next.toolWhitelist = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        case "approvalPolicy":
            old = snapshot.approvalPolicy.configToken
            guard let level = AgentPolicyLevel(configToken: value) else {
                throw AgentConfigError.outOfRange(key: key, value: value,
                                                 allowed: AgentPolicyLevel.configTokens.joined(separator: " / "))
            }
            next.approvalPolicy = level
        default:
            throw AgentConfigError.unknownKey(key)
        }
        snapshot = next
        changes.append(.init(key: key, oldValue: old, newValue: value, reason: reason, at: at))
    }

    /// 下一跳要用的快照（就是改动后的那一个 —— 立即生效，不许等重启）。
    public var appliedSnapshot: AgentConfigSnapshot { snapshot }

    /// 盘上那份留痕接回来（`AgentRuntimeConfigFile.load` 用；它不是「新改动」，所以不经 `apply`）。
    ///
    /// 落在这里而不是扩展里：`changes` 的 setter 是**文件私有**的，别处的扩展动不了它。
    public mutating func adoptHistory(_ history: [AgentConfigChange]) {
        for change in history where !changes.contains(change) {
            changes.append(change)
        }
    }

    /// **整份替换**留痕（载入路径专用）。
    ///
    /// 为什么需要它：`AgentRuntimeConfigFile.load` 会把盘上那六项过一遍 `apply` 去校验
    /// （范围规则只有一处），那六条带 `load-validation` 理由的记录是**临时脚手架** ——
    /// 留在留痕里就成了「每开一次 App 就多六条假改动」，用户看到的审计是假的。
    public mutating func replaceHistory(with history: [AgentConfigChange]) {
        changes = history
    }

    private func integer(key: String, value: String, range: ClosedRange<Int>, allowed: String) throws -> Int {
        guard let n = Int(value), range.contains(n) else {
            throw AgentConfigError.outOfRange(key: key, value: value, allowed: allowed)
        }
        return n
    }
}
