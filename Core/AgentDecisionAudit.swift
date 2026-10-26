import Foundation

/// **用户可见的自动化决定**落审计的投影（`FR-AGT-GUARD-COST-001` · `FR-AGT-UX-CONV-008` · `-009`）。
///
/// ## 为什么需要这一层
///
/// 这三条能力都已交付，但人类主人点验后都卡在同一处：**看屏上成立，翻日志没有**。
/// 「门控挡下了」「通知弹出去了」「求助卡出来了」都只发生在内存与界面里，
/// `agent-audit.jsonl` 里一条都不留 —— 于是事后没法回答「昨晚它到底叫过我没有」。
/// 判据里的「留痕可查」不是「界面上看得见」，是**导出之后能对上**。
///
/// ## 三条口径（都落在这一个类型里，界面与循环都不另写）
///
/// · **一条决定一条记录**：不合并、不抽样 —— 挡下十次就是十条（省 token 的次数本身就是账）；
/// · **机器码进「语句」列、人话进附注**：`sql` 列放 `gateSkipped chat 1a2b3c4d` 这种 ASCII 形态
///   （导出后可直接 grep），`detail` 放带 `language:` 的人话；
/// · **该安静的那些不写**：短任务两处出口都安静、求助单本身不合格（`isActionable == false`）、
///   通知被判为「什么都不用出」—— 这些返回 `nil`，**不写一条「什么都没做」的记录**
///   （审计里塞满空事件比缺事件更坏：读的人会以为发生过什么）。
public enum AgentDecisionKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// 门控挡下（这一跳一个请求都没发）。
    case gateSkipped
    /// 用户按「仍然发送」强发一次。
    case gateForced
    /// 主动通知（页内提示条 / 系统通知）。
    case notified
    /// 求助卡（要授权 / 要信息 / 要人动手）。
    case helpRequested
}

public enum AgentDecisionAudit {

    /// 指纹只留前 8 位：审计要能对上「哪一次」，不需要把整段提示词的摘要抄进日志。
    public static let digestPrefixLength = 8

    // MARK: - 门控（`FR-AGT-GUARD-COST-001`）

    /// 挡下：这一跳**没有发出任何请求**，但「本来要问什么」与被挡下的理由都要留下。
    public static func gateSkipped(_ recall: AgentGateRecall,
                                   sessionID: String? = nil,
                                   language: AppLanguage = .simplifiedChinese,
                                   at date: Date = Date()) -> AgentActionRecord {
        record(kind: .gateSkipped,
               subject: recall.trigger.source,
               digest: recall.trigger.digest,
               outcome: .denied,
               detail: LocalizedStrings.format(.agentDecisionGateSkippedDetail,
                                               language: language, recall.reason),
               sessionID: sessionID,
               at: date)
    }

    /// 「仍然发送」：人被挡下之后强发的那一次 —— 留痕与挡下**成对**，才看得出「挡了几次、几次硬发」。
    public static func gateForced(_ recall: AgentGateRecall,
                                  sessionID: String? = nil,
                                  language: AppLanguage = .simplifiedChinese,
                                  at date: Date = Date()) -> AgentActionRecord {
        record(kind: .gateForced,
               subject: recall.trigger.source,
               digest: recall.trigger.digest,
               outcome: .executed,
               detail: LocalizedStrings.format(.agentDecisionGateForcedDetail,
                                               language: language, recall.reason),
               sessionID: sessionID,
               at: date)
    }

    // MARK: - 主动通知（`FR-AGT-UX-CONV-008`）

    /// 通知：把「判成什么」与「两处出口各自出没出」写进一条。
    ///
    /// 返回 `nil` = 这一档本来就该安静（短任务 / 判定为不必叫）—— 没发生的事不留账。
    public static func notification(_ reason: AgentNotifyReason,
                                    plan: AgentNotifyPlan,
                                    sessionID: String? = nil,
                                    language: AppLanguage = .simplifiedChinese,
                                    at date: Date = Date()) -> AgentActionRecord? {
        guard !plan.isEmpty else { return nil }
        let headline = plan.banner?.title ?? plan.system?.title ?? reason.code
        let yes = LocalizedStrings.text(.agentDecisionYes, language: language)
        let no = LocalizedStrings.text(.agentDecisionNo, language: language)
        return record(kind: .notified,
                      subject: reason.code,
                      digest: headline,
                      outcome: .executed,
                      detail: LocalizedStrings.format(.agentDecisionNotifyDetail, language: language,
                                                     headline,
                                                     plan.banner == nil ? no : yes,
                                                     plan.system == nil ? no : yes),
                      sessionID: sessionID,
                      at: date)
    }

    // MARK: - 求助卡（`FR-AGT-UX-CONV-009`）

    /// 求助卡：卡上那句「要什么」要进账 —— 事后能回答「它到底要我去办哪件事」。
    ///
    /// 不合格的求助单（缺「要什么」或「为什么」）返回 `nil`：那种卡本来就不该出（`isActionable` 判过）。
    public static func helpRequested(_ help: AgentHelpRequest,
                                     sessionID: String? = nil,
                                     language: AppLanguage = .simplifiedChinese,
                                     at date: Date = Date()) -> AgentActionRecord? {
        guard help.isActionable else { return nil }
        return record(kind: .helpRequested,
                      subject: help.kind.rawValue,
                      digest: help.ask,
                      outcome: .pendingApproval,
                      detail: LocalizedStrings.format(.agentDecisionHelpDetail, language: language,
                                                     help.kind.label(language: language), help.ask),
                      sessionID: sessionID,
                      at: date)
    }

    // MARK: - 记录形状

    /// 统一的记录形状：`sql` 列 = `种类 主语 指纹前 8 位`（ASCII，可 grep），`detail` = 人话。
    ///
    /// 构造本身走 `AgentActionRecord.makeDecision`（记录构造点只许一处，见 `Core/AgentAudit.swift` 的说明）；
    /// `origin` 由那个工厂标 `.notice`：审计面板据此把来源列写成「用户可见决定」，
    /// 而不是照 `statementKind` 显示成「无法识别的语句」（那会让人以为 SQL 解析失败）。
    static func record(kind: AgentDecisionKind,
                       subject: String,
                       digest: String,
                       outcome: AgentActionRecord.Outcome,
                       detail: String,
                       sessionID: String?,
                       at date: Date) -> AgentActionRecord {
        AgentActionRecord.makeDecision(kind: kind.rawValue,
                                       subject: subject,
                                       digest: digest,
                                       digestPrefixLength: digestPrefixLength,
                                       outcome: outcome,
                                       detail: detail,
                                       sessionID: sessionID,
                                       at: date)
    }

    /// 指纹前 N 位（不足则原样）。
    public static func shortDigest(_ digest: String, limit: Int = AgentDecisionAudit.digestPrefixLength) -> String {
        guard limit > 0, digest.count > limit else { return digest }
        return String(digest.prefix(limit))
    }
}
