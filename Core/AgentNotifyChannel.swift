import Foundation

/// 主动通知（`FR-AGT-UX-CONV-008`）+ 求助通道（`FR-AGT-UX-CONV-009`）。
///
/// 主动通知的口径：**长任务做完 / 出错 / 需要人决定**才叫人，其余时候闭嘴。
/// 人正盯着这一页时不弹（除非这事必须他拍板）——「不让人守着屏幕」不等于「一直闪」。
///
/// ## 两处出口（2026-10-26 接线时定）
///
/// 同一个判定要落到两个地方：**页内提示条**（人就在这页，看得见）与**系统通知**
/// （人走开了，得靠系统叫他）。两处**共用同一份文案**（语言表里的
/// `agentNotify*Title/Body`）—— 一份判定不许写成两套话，否则「谁说了什么」会当场分叉。
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

    /// 机器码（审计的「语句」列用；ASCII，导出后可直接 grep）。
    /// 人话一律由语言表给 —— 这里只回答「是哪一档」。
    public var code: String {
        switch self {
        case .longTaskFinished: return "longTaskFinished"
        case .failed: return "failed"
        case .needsHumanDecision: return "needsHumanDecision"
        case .approvalRequired: return "approvalRequired"
        }
    }
}

public struct AgentNotification: Equatable, Sendable {
    public var title: String
    public var body: String
    public var mustInterrupt: Bool
}

/// 一次判定的**两处出口**（`FR-AGT-UX-CONV-008` 的界面接线）。
///
/// · `banner` = 页内提示条。**必须打断的那两档即使人就在这页也要出**（页内卡片是他唯一能操作的地方，
///   只在系统通知里出现等于「看着屏幕却什么都没看见」）；
/// · `system` = 系统通知。走 `AgentNotifyPolicy.decide` 的同一条判定（不另写一套阈值）。
public struct AgentNotifyPlan: Equatable, Sendable {
    public var banner: AgentNotification?
    public var system: AgentNotification?

    public init(banner: AgentNotification? = nil, system: AgentNotification? = nil) {
        self.banner = banner
        self.system = system
    }

    /// 什么都不用出（安静那一档）。
    public var isEmpty: Bool { banner == nil && system == nil }
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
    ///   - systemNotificationsEnabled: 配置里的「通知规则」开关（`FR-AGT-OPS-OBS-002`）。
    ///     关掉它 **只关系统通知那一格，页内提示条照出** —— 把两处一起关掉等于让人
    ///     「在界面上也看不见这件事」，那不是「少打扰」，是丢信息。
    ///   - language: 文案语言（缺省简体中文；界面传当前语言）。
    public func decide(_ reason: AgentNotifyReason,
                       userIsLookingAtThisPane: Bool,
                       userIsIdle: Bool = false,
                       systemNotificationsEnabled: Bool = true,
                       language: AppLanguage = .simplifiedChinese) -> AgentNotification? {
        guard systemNotificationsEnabled else { return nil }
        // 必须打断的：无论人在不在看都出（看着就不必再弹窗，但仍要有提示条）
        if reason.isMustInterrupt {
            if userIsLookingAtThisPane { return nil }   // 就在眼前，页内已有卡片，别再弹
            return AgentNotification(title: title(for: reason, language: language),
                                     body: body(for: reason, language: language),
                                     mustInterrupt: true)
        }
        switch reason {
        case let .longTaskFinished(elapsed):
            guard elapsed >= longTaskThresholdSeconds else { return nil }
            if userIsLookingAtThisPane, !userIsIdle { return nil }
            return AgentNotification(title: title(for: reason, language: language),
                                     body: body(for: reason, language: language),
                                     mustInterrupt: false)
        case .failed:
            if userIsLookingAtThisPane, !userIsIdle { return nil }
            return AgentNotification(title: title(for: reason, language: language),
                                     body: body(for: reason, language: language),
                                     mustInterrupt: false)
        default:
            return nil
        }
    }

    /// 页内提示条 + 系统通知**一次算齐**。
    ///
    /// 页内那一格的规则与系统那一格**不同**（这是本条的重点）：
    /// · 必须打断的两档 ⇒ 页内**总是**出（人就在这页时，系统通知按 `decide` 判为 nil，
    ///   若页内也不出，就成了「这件事在界面上根本看不见」）；
    /// · 长任务完成 ⇒ 过了门槛才出（短任务在界面上本来就看得到结果，不必再来一条）；
    /// · 失败 ⇒ 总是出（失败是最该被看见的一类，且提示条可以就地收起）；
    /// · 其余（`default` 分支）⇒ 不出。
    public func plan(_ reason: AgentNotifyReason,
                     userIsLookingAtThisPane: Bool,
                     userIsIdle: Bool = false,
                     systemNotificationsEnabled: Bool = true,
                     language: AppLanguage = .simplifiedChinese) -> AgentNotifyPlan {
        let system = decide(reason, userIsLookingAtThisPane: userIsLookingAtThisPane,
                           userIsIdle: userIsIdle,
                           systemNotificationsEnabled: systemNotificationsEnabled,
                           language: language)
        let note = AgentNotification(title: title(for: reason, language: language),
                                     body: body(for: reason, language: language),
                                     mustInterrupt: reason.isMustInterrupt)
        let banner: AgentNotification?
        switch reason {
        case .needsHumanDecision, .approvalRequired, .failed:
            banner = note
        case let .longTaskFinished(elapsed):
            banner = elapsed >= longTaskThresholdSeconds ? note : nil
        }
        return AgentNotifyPlan(banner: banner, system: system)
    }

    private func title(for reason: AgentNotifyReason, language: AppLanguage) -> String {
        switch reason {
        case let .longTaskFinished(elapsed):
            return LocalizedStrings.format(.agentNotifyDoneTitle, language: language, elapsed)
        case .failed:
            return LocalizedStrings.text(.agentNotifyFailedTitle, language: language)
        case .needsHumanDecision:
            return LocalizedStrings.text(.agentNotifyDecisionTitle, language: language)
        case .approvalRequired:
            return LocalizedStrings.text(.agentNotifyApprovalTitle, language: language)
        }
    }

    private func body(for reason: AgentNotifyReason, language: AppLanguage) -> String {
        switch reason {
        case .longTaskFinished:
            return LocalizedStrings.text(.agentNotifyDoneBody, language: language)
        case let .failed(summary):
            return LocalizedStrings.format(.agentNotifyFailedBody, language: language, summary)
        case let .needsHumanDecision(question):
            // 这一档的正文就是**那句问题本身**（原样），不套模板 —— 套一层「要不要…」会把它改成另一句话。
            return question
        case let .approvalRequired(summary):
            return LocalizedStrings.format(.agentNotifyApprovalBody, language: language, summary)
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

        /// 抬头（缺省简体中文；旧调用点与既有判据都走这一格）。
        public var label: String { label(language: .simplifiedChinese) }

        public func label(language: AppLanguage) -> String {
            switch self {
            case .grant: return LocalizedStrings.text(.agentHelpKindGrant, language: language)
            case .information: return LocalizedStrings.text(.agentHelpKindInformation, language: language)
            case .manualAction: return LocalizedStrings.text(.agentHelpKindManualAction, language: language)
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

    /// 给用户看的整段（三行：要什么 / 为什么 / 给我之后从哪接）。缺省简体中文。
    public var rendered: String { rendered(language: .simplifiedChinese) }

    /// 「为什么」那一行（求助卡的第二行）。**格式化留在 Core**：界面只拿成品串，
    /// 于是模板与实参永远对得上（`check-format-arguments` 那一族在界面上也就没有第二处出处）。
    public func whyLine(language: AppLanguage = .simplifiedChinese) -> String {
        LocalizedStrings.format(.agentHelpWhyPrefix, language: language, why)
    }

    /// 「给完之后从哪接着跑」那一行（第三行）。没有落脚点就如实说「从头再跑一遍这一步」。
    public func resumeLine(language: AppLanguage = .simplifiedChinese) -> String {
        if let resumeFrom {
            return LocalizedStrings.format(.agentHelpResumeWith, language: language, resumeFrom)
        }
        return LocalizedStrings.text(.agentHelpResumeWhole, language: language)
    }

    public func rendered(language: AppLanguage) -> String {
        var lines = ["**\(kind.label(language: language))**：\(ask)",
                     whyLine(language: language),
                     resumeLine(language: language)]
        return lines.joined(separator: "\n")
    }

    /// 判据用：缺「要什么」或「为什么」= 不合格的求助（不许只说「我卡住了」）。
    public var isActionable: Bool {
        !ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !why.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 求助卡的**出处**（`FR-AGT-UX-CONV-009` 的接线）。
///
/// 为什么需要这一层：求助单有好几个来源 —— 循环里的失败分级（`AgentFailureTriage.help`）、
/// 宿主没接装配、端点没配。若各处自己造一句「我卡住了」，用户拿到的就是五种说法；
/// 这里把**这一端自己产生的那两种**集中成两格，措辞只写在语言表里。
public enum AgentHelpCatalogue {

    /// 宿主没接装配（`makeLoop` 为空）：这一轮连循环都没造出来。
    public static func missingLoop(language: AppLanguage = .simplifiedChinese) -> AgentHelpRequest {
        AgentHelpRequest(kind: .information,
                         ask: LocalizedStrings.text(.agentHelpAskMissingLoop, language: language),
                         why: LocalizedStrings.text(.agentHelpWhyMissingLoop, language: language),
                         resumeFrom: LocalizedStrings.text(.agentHelpResumeMissingLoop, language: language))
    }

    /// 端点没配：一个请求都发不出去。
    public static func missingEndpoint(language: AppLanguage = .simplifiedChinese) -> AgentHelpRequest {
        AgentHelpRequest(kind: .information,
                         ask: LocalizedStrings.text(.agentHelpAskMissingEndpoint, language: language),
                         why: LocalizedStrings.text(.agentHelpWhyMissingEndpoint, language: language),
                         resumeFrom: LocalizedStrings.text(.agentHelpResumeMissingEndpoint, language: language))
    }
}
