import Foundation

/// 主动通知（`FR-AGT-UX-CONV-008`）+ 求助通道（`FR-AGT-UX-CONV-009`）。
///
/// 主动通知的口径：**长任务做完 / 出错 / 需要人决定**才叫人，其余时候闭嘴。
/// 人正盯着这一页时不弹（除非这事必须他拍板）——「不让人守着屏幕」不等于「一直闪」。
public enum AgentNotifyReason: Equatable, Sendable {
    case longTaskFinished(elapsedSeconds: Int)
    case failed(summary: String)
    case needsHumanDecision(question: String)
    case approvalRequired(summary: String)

    /// 是否必须打断人（其余可等到手头松）。
    public var isMustInterrupt: Bool {
        switch self {
        case .needsHumanDecision, .approvalRequired: return true
        case .longTaskFinished, .failed: return false
        }
    }
}

public struct AgentNotification: Equatable, Sendable {
    public var title: String
    public var body: String
    public var mustInterrupt: Bool
}

public struct AgentNotifyPolicy: Sendable {
    /// 「长任务」门槛：跑过这么久才值得叫一声（秒）。
    public var longTaskThresholdSeconds: Int

    public init(longTaskThresholdSeconds: Int = 30) {
        self.longTaskThresholdSeconds = max(0, longTaskThresholdSeconds)
    }

    /// - Parameters:
    ///   - reason: 为什么想叫人。
    ///   - userIsLookingAtThisPane: 人此刻正看着这一页（前台 + 当前页签）。
    ///   - userIsIdle: 人已经离开（无输入超过 N 分钟）—— 离开才更该弹系统通知。
    public func decide(_ reason: AgentNotifyReason,
                       userIsLookingAtThisPane: Bool,
                       userIsIdle: Bool = false) -> AgentNotification? {
        // 必须打断的：无论人在不在看都出（看着就不必再弹窗，但仍要有提示条）
        if reason.isMustInterrupt {
            if userIsLookingAtThisPane { return nil }   // 就在眼前，页内已有卡片，别再弹
            return AgentNotification(title: title(for: reason), body: body(for: reason), mustInterrupt: true)
        }
        switch reason {
        case let .longTaskFinished(elapsed):
            guard elapsed >= longTaskThresholdSeconds else { return nil }
            if userIsLookingAtThisPane, !userIsIdle { return nil }
            return AgentNotification(title: "跑完了（\(elapsed) 秒）", body: body(for: reason), mustInterrupt: false)
        case .failed:
            if userIsLookingAtThisPane, !userIsIdle { return nil }
            return AgentNotification(title: title(for: reason), body: body(for: reason), mustInterrupt: false)
        default:
            return nil
        }
    }

    private func title(for reason: AgentNotifyReason) -> String {
        switch reason {
        case .longTaskFinished: return "任务完成"
        case .failed: return "任务失败"
        case .needsHumanDecision: return "等你定一下"
        case .approvalRequired: return "等你批一下"
        }
    }

    private func body(for reason: AgentNotifyReason) -> String {
        switch reason {
        case let .longTaskFinished(elapsed): return "跑了 \(elapsed) 秒，结果在对话页签里。"
        case let .failed(summary): return "失败了：\(summary)"
        case let .needsHumanDecision(question): return question
        case let .approvalRequired(summary): return "要动之前得你批：\(summary)"
        }
    }
}

/// 求助通道：卡住时**明确说「我需要你做一件事」**——是哪种事、要什么、给完怎么接着跑。
public struct AgentHelpRequest: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        /// 要授权（权限 / 路径 / 端点）。
        case grant
        /// 要信息（缺参数、缺口径）。
        case information
        /// 要人亲自动手（界面之外的点击、插设备、登录）。
        case manualAction

        public var label: String {
            switch self {
            case .grant: return "需要你授权"
            case .information: return "需要你给信息"
            case .manualAction: return "需要你亲手做一步"
            }
        }
    }

    public var kind: Kind
    /// 具体要什么（一句话，能照着做）。
    public var ask: String
    /// 为什么非它不可（不说理由的求助等于甩锅）。
    public var why: String
    /// 给完之后我从哪接着跑（可空 = 重跑整段）。
    public var resumeFrom: String?

    public init(kind: Kind, ask: String, why: String, resumeFrom: String? = nil) {
        self.kind = kind
        self.ask = ask
        self.why = why
        self.resumeFrom = resumeFrom
    }

    /// 给用户看的整段（三行：要什么 / 为什么 / 给我之后从哪接）。
    public var rendered: String {
        var lines = ["**\(kind.label)**：\(ask)", "原因：\(why)"]
        if let resumeFrom { lines.append("你给我之后，我从「\(resumeFrom)」接着跑。") }
        else { lines.append("你给我之后，我从头再跑一遍这一步。") }
        return lines.joined(separator: "\n")
    }

    /// 判据用：缺「要什么」或「为什么」= 不合格的求助（不许只说「我卡住了」）。
    public var isActionable: Bool {
        !ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !why.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
