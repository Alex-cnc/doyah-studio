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

    public init(model: String = "默认", maxConcurrentSubtasks: Int = 3, commandTimeoutSeconds: Int = 60,
                dailyTokenQuota: Int = 200_000, notificationsEnabled: Bool = true,
                toolWhitelist: [String] = []) {
        self.model = model
        self.maxConcurrentSubtasks = maxConcurrentSubtasks
        self.commandTimeoutSeconds = commandTimeoutSeconds
        self.dailyTokenQuota = dailyTokenQuota
        self.notificationsEnabled = notificationsEnabled
        self.toolWhitelist = toolWhitelist
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
        default:
            throw AgentConfigError.unknownKey(key)
        }
        snapshot = next
        changes.append(.init(key: key, oldValue: old, newValue: value, reason: reason, at: at))
    }

    /// 下一跳要用的快照（就是改动后的那一个 —— 立即生效，不许等重启）。
    public var appliedSnapshot: AgentConfigSnapshot { snapshot }

    private func integer(key: String, value: String, range: ClosedRange<Int>, allowed: String) throws -> Int {
        guard let n = Int(value), range.contains(n) else {
            throw AgentConfigError.outOfRange(key: key, value: value, allowed: allowed)
        }
        return n
    }
}
