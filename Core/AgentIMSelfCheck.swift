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
}
