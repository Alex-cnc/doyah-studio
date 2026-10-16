import Foundation

/// 定时 agent 面板用到的**纯逻辑**（`FR-AI-27` 的界面半）。
///
/// 放在 Core 而不是视图里，理由与 `DataTaskPresentation` 逐字相同：
/// 「调度判定 → 界面状态」「执行记录 → 展示文本」都是纯函数，抽出来才能在 `DoyahCoreTests`
/// 里有单测，视图里只剩摆放。
///
/// **整份复用 `FR-AI-06` 的两处既有件**（「不另造一套」）：
///   · 档位与时间口径 → `DataTaskPresentation`（`status` / `plannedAt` / `overdueMinutes`）；
///   · 时间文本 → `AgentAuditPresentation.timestampText`（`DataTaskPresentation.nextRunText` 用的也是它）。
/// 本件只补 agent 侧独有的三样：**目标档位**（会话 / agent 任务）、**错过提示**（验收要点 ②）、
/// **执行历史行**（⑤，含「被扣下几条」= 未审批不执行的读数）。
///
/// 本件不含一处汉字字面量 —— 人话一律走语言表（`LocalizedStrings`），语言由调用方给。
public enum AgentSchedulePresentation {

    // MARK: - 调度判定 → 界面（① 的界面投影，整份复用 FR-AI-06）

    /// 界面上的调度状态档位 —— 与数据任务**同一档**（同一台判定机投影出来的）。
    public static func status(for decision: ScheduleDecision) -> DataTaskPresentation.ScheduleStatus {
        DataTaskPresentation.status(for: decision)
    }

    /// 计划执行时刻（等待 / 到点 / 错过三态才有）。
    public static func plannedAt(_ decision: ScheduleDecision) -> Date? {
        DataTaskPresentation.plannedAt(decision)
    }

    /// 错过窗口「晚了约 N 分钟」里的 N（不足 1 分钟按 1 分钟算，与数据任务同口径）。
    public static func overdueMinutes(_ decision: ScheduleDecision) -> Int? {
        DataTaskPresentation.overdueMinutes(decision)
    }

    /// 状态档位的展示文本（复用数据任务那五条键，语义完全相同）。
    public static func statusText(
        _ status: DataTaskPresentation.ScheduleStatus,
        language: AppLanguage
    ) -> String {
        switch status {
        case .notScheduled: return LocalizedStrings.text(.dataTaskStatusNotScheduled, language: language)
        case .disabled: return LocalizedStrings.text(.dataTaskStatusDisabled, language: language)
        case .waiting: return LocalizedStrings.text(.dataTaskStatusWaiting, language: language)
        case .due: return LocalizedStrings.text(.dataTaskStatusDue, language: language)
        case .missed: return LocalizedStrings.text(.dataTaskStatusMissed, language: language)
        }
    }

    /// 执行结果档位的展示文本（复用数据任务那四条键；词表本来就是同一套）。
    public static func runStatusText(_ status: TaskRunRecord.Status, language: AppLanguage) -> String {
        switch status {
        case .running: return LocalizedStrings.text(.dataTaskRunStatusRunning, language: language)
        case .succeeded: return LocalizedStrings.text(.dataTaskRunStatusSucceeded, language: language)
        case .failed: return LocalizedStrings.text(.dataTaskRunStatusFailed, language: language)
        case .skipped: return LocalizedStrings.text(.dataTaskRunStatusSkipped, language: language)
        }
    }

    /// 目标档位的展示文本（**agent 侧独有**：定时 agent 可以定时「一次会话」或「一个 agent 任务」）。
    public static func targetKindText(
        _ kind: AgentScheduleTarget.Kind,
        language: AppLanguage
    ) -> String {
        switch kind {
        case .conversation: return LocalizedStrings.text(.agentScheduleTargetConversation, language: language)
        case .agentTask: return LocalizedStrings.text(.agentScheduleTargetAgentTask, language: language)
        }
    }

    /// 调度方式一行（一次性给时刻、周期给间隔；与数据任务同一套键与口径）。
    public static func scheduleText(
        _ schedule: TaskSchedule,
        language: AppLanguage
    ) -> String {
        switch schedule.kind {
        case .manual:
            return LocalizedStrings.text(.dataTaskScheduleKindManual, language: language)
        case .once:
            let at = AgentAuditPresentation.timestampText(schedule.runAt ?? Date(timeIntervalSince1970: 0))
            return LocalizedStrings.text(.dataTaskScheduleKindOnce, language: language)
                + " · " + LocalizedStrings.text(.dataTaskRunAt, language: language)
                + " " + at
        case .recurring:
            let seconds = Int(schedule.intervalSeconds ?? 0)
            return LocalizedStrings.text(.dataTaskScheduleKindRecurring, language: language)
                + " · " + LocalizedStrings.text(.dataTaskIntervalSeconds, language: language)
                + " \(seconds)"
        }
    }

    /// 下一次计划执行时刻的展示文本；没有下一次（未排期 / 停用 / 一次性已过）时为 `nil`。
    public static func nextRunText(
        for entry: AgentScheduleEntry,
        lastRun: Date?,
        now: Date = Date()
    ) -> String? {
        guard let next = AgentSchedulePlanner.nextRun(for: entry, after: now, lastRun: lastRun) else {
            return nil
        }
        return AgentAuditPresentation.timestampText(next)
    }

    // MARK: - ② 错过窗口：界面要摆出「是否现在执行」

    /// 一条「错过了，要不要现在跑」的提示。
    ///
    /// 默认**不补跑**（`AgentSchedulePlanner.plan` 里 `.missed` 只有在 `confirmedMissed` 为真时才起会话），
    /// 界面拿这一条把选择权交回用户 —— 这正是验收要点 ② 的界面半。
    public struct MissedPrompt: Equatable, Sendable, Identifiable {
        public var entryID: UUID
        /// 偏掉的那一次的原计划时刻（确认后跑起来也记它）。
        public var plannedAt: Date
        /// 晚了约多少分钟（不足 1 分钟按 1 分钟算）。
        public var overdueMinutes: Int
        /// 现成人话（「晚了约 N 分钟，请确认是否现在执行。」，与数据任务同一条键）。
        public var text: String

        public var id: UUID { entryID }

        public init(entryID: UUID, plannedAt: Date, overdueMinutes: Int, text: String) {
            self.entryID = entryID
            self.plannedAt = plannedAt
            self.overdueMinutes = overdueMinutes
            self.text = text
        }
    }

    /// 只有判定落在 `.missed` 上才给提示；其余四档一律 `nil`（`disabled` ⇒ 连提示都不该有）。
    public static func missedPrompt(
        for entry: AgentScheduleEntry,
        now: Date,
        lastRun: Date? = nil,
        grace: TimeInterval = 0,
        language: AppLanguage
    ) -> MissedPrompt? {
        missedPrompt(
            for: AgentSchedulePlanner.decision(for: entry, now: now, lastRun: lastRun, grace: grace),
            entryID: entry.id,
            language: language
        )
    }

    /// 从一条已算好的判定出发（App 侧的 tick 已经算过一次，不必重算）。
    public static func missedPrompt(
        for decision: ScheduleDecision,
        entryID: UUID,
        language: AppLanguage
    ) -> MissedPrompt? {
        guard case .missed(let plannedAt, _) = decision else { return nil }
        let minutes = overdueMinutes(decision) ?? 1
        return MissedPrompt(
            entryID: entryID,
            plannedAt: plannedAt,
            overdueMinutes: minutes,
            text: LocalizedStrings.format(.dataTaskMissedNotice, language: language, minutes)
        )
    }

    // MARK: - 列表行

    /// 列表里的一行（视图只把字段摆上去，一个字都不再算）。
    public struct Row: Equatable, Sendable, Identifiable {
        public var entryID: UUID
        /// 条目标题。
        public var title: String
        /// 目标一行：档位（会话 / agent 任务）+ 工作区。
        public var targetText: String
        /// 提示词（列表里截断显示由视图决定，这一份是原文）。
        public var prompt: String
        /// 调度方式一行。
        public var scheduleText: String
        /// 状态档位的展示文本。
        public var statusText: String
        /// 「下次执行：…」；没有下一次时为 `nil`。
        public var nextRunText: String?
        public var isEnabled: Bool
        /// 最近一跑：状态 + 时刻 +（有扣下时）扣下几条。
        public var lastRunText: String?
        /// 停用时的说明（复用数据任务那条键）。
        public var disabledHint: String?

        public var id: UUID { entryID }
    }

    /// 组装一行。`latestRecord` 传该条目最近一次留痕（界面从账里取，Core 不读盘）。
    public static func row(
        for entry: AgentScheduleEntry,
        decision: ScheduleDecision,
        lastRun: Date? = nil,
        latestRecord: AgentScheduleRunRecord? = nil,
        now: Date = Date(),
        language: AppLanguage
    ) -> Row {
        let status = status(for: decision)
        var target = targetKindText(entry.target.kind, language: language)
        let workspace = entry.target.workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        if !workspace.isEmpty {
            target += " · " + workspace
        }
        return Row(
            entryID: entry.id,
            title: entry.target.title,
            targetText: target,
            prompt: entry.target.prompt,
            scheduleText: scheduleText(entry.schedule, language: language),
            statusText: statusText(status, language: language),
            nextRunText: nextRunText(for: entry, lastRun: lastRun, now: now),
            isEnabled: entry.isEnabled,
            lastRunText: latestRecord.map { runSummaryText($0, language: language) },
            disabledHint: entry.isEnabled
                ? nil
                : LocalizedStrings.text(.dataTaskDisabledHint, language: language)
        )
    }

    /// 最近一跑的三样（状态 / 时刻 / 扣下几条）—— 列表行与历史行的**同一处**拼法。
    public static func runSummaryText(
        _ record: AgentScheduleRunRecord,
        language: AppLanguage
    ) -> String {
        var parts = [
            runStatusText(record.status, language: language),
            AgentAuditPresentation.timestampText(record.startedAt)
        ]
        if !record.withheldActions.isEmpty {
            parts.append(LocalizedStrings.format(.agentScheduleWithheld, language: language, record.withheldActions.count))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - ⑤ 执行历史

    /// 历史里的一行：**时间 / 结果状态**必在，扣下与失败原因按需带出。
    public struct HistoryRow: Equatable, Sendable, Identifiable {
        public var id: UUID
        /// 计划时刻（错过了才补跑的那一次，这里仍是原计划时刻）；未排期为 `nil`。
        public var plannedAtText: String?
        public var startedAtText: String
        public var statusText: String
        /// 失败 / 跳过的可读原因（**由调用方从语言表给**，Core 不写死人话）。
        public var detailText: String?
        /// 这一跑真执行了几条。
        public var executedText: String?
        /// 被扣下几条（未审批不执行 —— 不静默）。
        public var withheldText: String?
        /// 比计划晚（错过由用户确认后跑的那一次）。
        public var isLate: Bool
        public var durationText: String
    }

    /// 某条目（`entryID` 为 `nil` 时是全部条目）的历史行，**按开始时刻升序**（与盘上追加次序一致）。
    public static func historyRows(
        _ records: [AgentScheduleRunRecord],
        for entryID: UUID? = nil,
        language: AppLanguage
    ) -> [HistoryRow] {
        records
            .filter { entryID == nil || $0.entryID == entryID }
            .map { record in
                HistoryRow(
                    id: record.id,
                    plannedAtText: record.plannedAt.map { AgentAuditPresentation.timestampText($0) },
                    startedAtText: AgentAuditPresentation.timestampText(record.startedAt),
                    statusText: runStatusText(record.status, language: language),
                    detailText: record.hasFailureDetail ? record.detail : nil,
                    executedText: record.executedActions.isEmpty
                        ? nil
                        : LocalizedStrings.format(.agentScheduleExecuted, language: language, record.executedActions.count),
                    withheldText: record.withheldActions.isEmpty
                        ? nil
                        : LocalizedStrings.format(.agentScheduleWithheld, language: language, record.withheldActions.count),
                    isLate: record.isLate,
                    durationText: DataTaskPresentation.durationText(record.duration)
                )
            }
            .sorted { $0.startedAtText < $1.startedAtText }
    }

    /// 从盘上读回来的账里「判失败却给不出原因」的那些（判据用；正常写入路径下写不进去）。
    public static func silentFailures(_ ledger: AgentScheduleLedger) -> [AgentScheduleRunRecord] {
        ledger.silentFailures
    }

    // MARK: - 计数（列表头一行：几条启用 / 几条停用）

    public struct Counts: Equatable, Sendable {
        public var total: Int
        public var enabled: Int
        public var due: Int
        public var missed: Int

        public var disabled: Int { total - enabled }
    }

    /// 按条目 + 判定算一次计数（界面顶部那一行用）。
    public static func counts(
        entries: [AgentScheduleEntry],
        decisions: [UUID: ScheduleDecision]
    ) -> Counts {
        var counts = Counts(
            total: entries.count,
            enabled: entries.filter(\.isEnabled).count,
            due: 0,
            missed: 0
        )
        for entry in entries {
            guard let decision = decisions[entry.id] else { continue }
            switch decision {
            case .due: counts.due += 1
            case .missed: counts.missed += 1
            case .notScheduled, .disabled, .waiting: break
            }
        }
        return counts
    }
}
