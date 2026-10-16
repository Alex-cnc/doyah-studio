import Foundation

// MARK: - 定时 agent（FR-AI-27）

/// 定时 agent 的触发目标：到点要起的是**一次会话**或一个 **agent 任务**。
///
/// 这里只描述「起什么」，一行时间计算都没有 —— 排期语义整份沿用 `FR-AI-06` 的
/// `Core/TaskScheduler`（需求原文点名：「调度语义复用 `FR-AI-06` 的 `Core/TaskScheduler`，
/// 不另造一套」）。档位也用 `FR-AI-06` 那五个：`notScheduled` / `disabled` / `waiting` /
/// `due` / `missed`，逐档可断言。
public struct AgentScheduleTarget: Codable, Equatable, Sendable {

    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// 起一次对话会话。
        case conversation
        /// 起一个 agent 任务。
        case agentTask
    }

    public var kind: Kind
    /// 新会话的标题。
    public var title: String
    /// 投给会话的那句话：**原样**存、**原样**投 —— 触发路径不改写用户的字。
    public var prompt: String
    /// 工作区隔离键（会话按工作区持久化 —— 沿用 `AgentSessionStore` 的口径）。
    public var workspace: String

    public init(kind: Kind, title: String, prompt: String, workspace: String) {
        self.kind = kind
        self.title = title
        self.prompt = prompt
        self.workspace = workspace
    }
}

/// 一条定时 agent 的排期（`FR-AI-27` ①）。
///
/// 排期**只存定义**：不持执行状态、不启定时器、不读时钟 —— 判定一律由调用方把
/// `now: Date` 传进来（`Core` 里没有一处读钟，判据才能逐档对拍）。
/// 执行历史另记（⑤，见 `AgentScheduleLedger`）。
public struct AgentScheduleEntry: Codable, Equatable, Sendable, Identifiable {

    public var id: UUID
    public var target: AgentScheduleTarget
    /// 档位与字段整份沿用 `FR-AI-06` 的 `TaskSchedule`（`.manual` / `.once` / `.recurring`，
    /// `runAt` / `intervalSeconds` / `startAt`）—— 需求点名不许另造一套。
    public var schedule: TaskSchedule
    /// 是否启用。**停用后不再排期**（验收要点 ④ 的负例）。
    public var isEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        target: AgentScheduleTarget,
        schedule: TaskSchedule = .manual,
        isEnabled: Bool = true,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.target = target
        self.schedule = schedule
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 触发那一次：动作与处置（验收要点 ③「定时不构成授权」）

/// 审批侧的口径（③）。**门在 `AgentApprovalGate` 那边**，这里只带它的结论：
/// 不重算指纹、不判超时（「超时 = 拒绝」已经在闸门里判完了）。
public struct AgentScheduleApprovals: Equatable, Sendable {

    /// 已经批过、且**还没被兑现**的指纹。审批按**次**（①：同一条决定只能兑现一次）——
    /// 兑现过的指纹不会出现在这里，与 `AgentApprovalGate.grant` 的口径一致。
    public var granted: Set<String>

    public init(granted: Set<String> = []) {
        self.granted = granted
    }

    /// 一张批准都没有（默认档；负例 ③ 的起点）。
    public static let none = AgentScheduleApprovals()
}

/// 一次触发里打算做的一条动作。
///
/// 两半**一律来自既有件**，这里不重判一遍：
/// - `guardVerdict` 由 `AgentGuardrail.evaluate` 给出（语句类动作）；
/// - `approval`（写文件 / 跑命令出的单）由**工具侧**给出 —— 指纹是工具自己算的
///   （同 `AgentApprovalGate` 的纪律：两处各算一个指纹必然对不上、永远兑不了）。
public struct AgentScheduleAction: Equatable, Sendable {

    /// 条目名（工具名 / 能力名）：留痕与界面按它列「这一轮动了哪些条目」。
    public var name: String
    /// 这条动作的护栏判定。
    public var guardVerdict: AgentGuardVerdict
    /// 工具侧出的要审批的动作；只读动作为 `nil`。
    public var approval: AgentApprovalRequest?

    public init(name: String, guardVerdict: AgentGuardVerdict, approval: AgentApprovalRequest? = nil) {
        self.name = name
        self.guardVerdict = guardVerdict
        self.approval = approval
    }

    /// 这一条在「已经有的批准」下怎么处置 —— **③ 的落点**。
    ///
    /// 「定时不构成授权」这句在代码里就是这个函数的形状：到点这件事本身**不产生任何授权**，
    /// 判定只看**逐次**批准。出了单的执行类（写文件 / 跑命令）**只看这张单** ——
    /// 护栏放过**不解除**审批（两道闸门互相独立，同 `AgentGuardPolicy` 的口径）。
    public func disposition(approvals: AgentScheduleApprovals) -> AgentScheduleActionDisposition {
        // 策略拒绝**最先**判：只读模式下拿到一张批准也不执行（同 `AgentGuardrail` 的优先级
        // —— 拒绝 > 需批准 > 放行，批准不能突破只读模式）。
        if case .deny(let denial) = guardVerdict { return .refused(denial) }

        if let approval {
            return approvals.granted.contains(approval.fingerprint)
                ? .execute
                : .heldForApproval(fingerprint: approval.fingerprint)
        }
        switch guardVerdict {
        case .allow:
            return .execute
        case .deny(let denial):
            return .refused(denial)
        case .requireApproval:
            // 护栏说要批、而**还没有单**（工具侧还没出单）⇒ 扣下，不执行。
            return .heldForApproval(fingerprint: nil)
        }
    }
}

/// 一条动作在这一轮里的处置。
public enum AgentScheduleActionDisposition: Equatable, Sendable {
    /// 只读 / 已按次批准 ⇒ 执行。
    case execute
    /// 需要逐次审批而没有批准 ⇒ **不执行**（指纹带上，方便去审批队列找那一张单）。
    case heldForApproval(fingerprint: String?)
    /// 策略拒绝（只读模式 / 高危）⇒ 不执行，原因原样带回。
    case refused(AgentGuardDenial)

    public var isExecuted: Bool { self == .execute }
}

/// 计划里的一条动作（名字 + 处置 + 工具侧给的事实）。
public struct AgentSchedulePlannedAction: Equatable, Sendable {
    public var name: String
    public var disposition: AgentScheduleActionDisposition
    /// 工具侧给的可读事实（差异预览 / 命令原文）；只读动作可为 `nil`。
    public var payload: String?

    public init(name: String, disposition: AgentScheduleActionDisposition, payload: String? = nil) {
        self.name = name
        self.disposition = disposition
        self.payload = payload
    }

    public var isExecuted: Bool { disposition.isExecuted }
}

// MARK: - 一轮 tick 的结论（①②④）

/// 客户端跑着的时候，按自己的节拍问一次「这一轮该不该起一次会话」。
public enum AgentScheduleRunPlan: Equatable, Sendable {

    /// **不起会话**：附上为什么 —— 直接就是 `FR-AI-06` 的判定档（含它那句可读提示，
    /// `ScheduleDecision.message`），不另写一套文案。
    case idle(reason: ScheduleDecision)

    /// 起一次会话。`plannedAt` 是**计划时刻**（不是「现在」）—— 错过由用户确认后才跑的那一次，
    /// 写进来的仍是原计划时刻，留痕里一眼能看出这一跑是晚的。
    case run(plannedAt: Date, actions: [AgentSchedulePlannedAction])

    public var runs: Bool {
        if case .run = self { return true }
        return false
    }

    /// 这一轮**真会执行**的条目（③ 的读数：未审批的写类不在这里）。
    public var executableActions: [AgentSchedulePlannedAction] {
        guard case .run(_, let actions) = self else { return [] }
        return actions.filter(\.isExecuted)
    }

    /// 这一轮**被扣下 / 被拒**的条目。
    public var withheldActions: [AgentSchedulePlannedAction] {
        guard case .run(_, let actions) = self else { return [] }
        return actions.filter { !$0.isExecuted }
    }

    /// 不起会话时的判定档（起会话时为 `nil`）—— 界面拿它的 `message` 做人话。
    public var idleReason: ScheduleDecision? {
        if case .idle(let reason) = self { return reason }
        return nil
    }

    /// 这一轮要不要留痕、留成哪一档（⑤）。
    ///
    /// 记账口径（有意写死在这里，免得各调用点各记一套）：
    /// - `.run` ⇒ 一条 `running`（调用方跑完用 `AgentScheduleLedger.finish` 收成终态）；
    /// - `.idle(.missed)` ⇒ 一条 `skipped` —— 它正是「**错过窗口没补跑**」的证据；
    /// - 其余三档（未排期 / 停用 / 还没到）⇒ `nil`：**不记账**。
    ///   每一跳都记一条会把账淹掉，而这三档本来就没有「发生过的触发」可言
    ///   （验收要点 ④ 的负例正是「一次都没有」）。
    public func record(
        entryID: UUID,
        startedAt: Date,
        detail: String? = nil
    ) -> AgentScheduleRunRecord? {
        switch self {
        case .run(let plannedAt, let actions):
            return AgentScheduleRunRecord(
                entryID: entryID,
                plannedAt: plannedAt,
                startedAt: startedAt,
                status: .running,
                executedActions: actions.filter(\.isExecuted).map(\.name),
                withheldActions: actions.filter { !$0.isExecuted }.map(\.name),
                detail: detail
            )

        case .idle(let reason):
            guard case .missed(let plannedAt, _) = reason else { return nil }
            return AgentScheduleRunRecord(
                entryID: entryID,
                plannedAt: plannedAt,
                startedAt: startedAt,
                status: .skipped,
                executedActions: [],
                withheldActions: [],
                detail: detail
            )
        }
    }
}

// MARK: - 执行历史与失败记录（⑤）

/// 一次触发（或一次「错过未补跑」）的留痕：**时间 / 条目 / 结果状态**三样都在（⑤）。
///
/// 档位沿用 `FR-AI-06` 执行历史的词表 `TaskRunRecord.Status`
/// （`running` / `succeeded` / `failed` / `skipped`）—— 两处历史用同一套词，界面只写一遍渲染。
public struct AgentScheduleRunRecord: Codable, Equatable, Sendable, Identifiable {

    public var id: UUID
    public var entryID: UUID
    /// 计划时刻（错过后由用户确认才跑的那一次，这里仍是**原**计划时刻）。
    public var plannedAt: Date?
    public var startedAt: Date
    public var finishedAt: Date?
    public var status: TaskRunRecord.Status
    /// 这一轮**真执行**的条目（按计划里的次序）。
    public var executedActions: [String]
    /// 这一轮**被扣下 / 被拒**的条目 —— 未审批的写类在这里，不静默（③⑤）。
    public var withheldActions: [String]
    /// 失败 / 跳过的可读原因。**由调用方从语言表给**（Core 不写死人话，同既有口径）。
    public var detail: String?

    public init(
        id: UUID = UUID(),
        entryID: UUID,
        plannedAt: Date? = nil,
        startedAt: Date,
        finishedAt: Date? = nil,
        status: TaskRunRecord.Status = .running,
        executedActions: [String] = [],
        withheldActions: [String] = [],
        detail: String? = nil
    ) {
        self.id = id
        self.entryID = entryID
        self.plannedAt = plannedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.executedActions = executedActions
        self.withheldActions = withheldActions
        self.detail = detail
    }

    /// 耗时（秒）；未结束为 `nil`（与 `TaskRunRecord.duration` 同口径）。
    public var duration: TimeInterval? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    /// 这一跑比计划晚（错过由用户确认后的那一次）。
    public var isLate: Bool {
        guard let plannedAt else { return false }
        return startedAt > plannedAt
    }

    /// 失败该有的原因有没有（空串算没有）。
    public var hasFailureDetail: Bool {
        !(detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 记账被拒的原因。
public enum AgentScheduleLedgerError: Error, Equatable, Sendable {
    /// 判 `failed` 却给不出原因 ⇒ 拒收这一条（**失败不静默**）。
    case failureWithoutDetail
    /// 收尾时找不到那一条（id 不认）⇒ 如实报，不悄悄新建一条。
    case unknownRecord(UUID)
}

/// 执行历史（⑤）。
///
/// 纯值类型：**不落盘**。落盘按 `FR-AI-06` 既有的 JSONL 形状由调用方追加
/// （`DataTaskStore.appendRun` 那一路），这里只管「怎么算一条合格的留痕」。
public struct AgentScheduleLedger: Equatable, Sendable {

    public private(set) var records: [AgentScheduleRunRecord]

    /// 从盘上读回来的账也能装进来 —— 于是「读回来的一批里有静默失败」是**可判**的。
    public init(records: [AgentScheduleRunRecord] = []) {
        self.records = records
    }

    /// 记一条。**失败不静默**：判 `failed` 而不给原因 ⇒ 抛错，账上一个字都不动
    /// （形状上做不到「悄悄失败」）。
    public mutating func record(_ record: AgentScheduleRunRecord) throws {
        guard record.status != .failed || record.hasFailureDetail else {
            throw AgentScheduleLedgerError.failureWithoutDetail
        }
        records.append(record)
    }

    /// 把一条 `running` 收成终态（成功 / 失败 / 跳过）。失败同样必须给原因。
    @discardableResult
    public mutating func finish(
        id: UUID,
        status: TaskRunRecord.Status,
        at: Date,
        detail: String? = nil,
        executedActions: [String]? = nil,
        withheldActions: [String]? = nil
    ) throws -> AgentScheduleRunRecord {
        guard let index = records.lastIndex(where: { $0.id == id }) else {
            throw AgentScheduleLedgerError.unknownRecord(id)
        }
        var updated = records[index]
        updated.status = status
        updated.finishedAt = at
        if let detail { updated.detail = detail }
        if let executedActions { updated.executedActions = executedActions }
        if let withheldActions { updated.withheldActions = withheldActions }
        guard status != .failed || updated.hasFailureDetail else {
            throw AgentScheduleLedgerError.failureWithoutDetail
        }
        records[index] = updated
        return updated
    }

    // MARK: 读

    public func runs(for entryID: UUID) -> [AgentScheduleRunRecord] {
        records.filter { $0.entryID == entryID }
    }

    /// 失败都留下来了（⑤：失败不静默）—— 正常写入路径下，记账时就已经拒掉没有原因的失败。
    /// 但**从盘上读回来的账**可能被人手改过 / 是旧版本写的 ⇒ 这里如实报出来。
    public var silentFailures: [AgentScheduleRunRecord] {
        records.filter { $0.status == .failed && !$0.hasFailureDetail }
    }

    public func failures(for entryID: UUID) -> [AgentScheduleRunRecord] {
        records.filter { $0.entryID == entryID && $0.status == .failed }
    }

    /// 最近一次**成功**触发的时刻 —— 喂给 `AgentSchedulePlanner.decision(..., lastRun:)`。
    /// 取 `startedAt`（与 `DataTaskStore.lastSuccessfulRun` 同口径）。
    public func lastSuccessfulRun(for entryID: UUID) -> Date? {
        records
            .filter { $0.entryID == entryID && $0.status == .succeeded }
            .map(\.startedAt)
            .max()
    }
}

// MARK: - 判定与计划（①④ 的落点：判定整份沿用 FR-AI-06）

/// 定时 agent 的调度判定与计划。
///
/// **不另造一套时间计算**：三个判定口（`decision` / `nextRun` / `missedRuns`）
/// 逐个转交给 `FR-AI-06` 的 `TaskScheduler`（档位、宽限、错过口径、周期格点的算法都在那里）。
/// 本件只多做两件 `TaskScheduler` 不该管的事：
/// ① 把「排期」翻译成「这一轮起不起会话」（`plan`）；
/// ② 把触发路径上的动作**交回既有的审批闸门**（`AgentScheduleAction.disposition`）。
///
/// 时间**一律由调用方传入**（本件里没有一处读钟）—— 判据才能把每一档钉在一个确定的 `Date` 上。
public enum AgentSchedulePlanner {

    /// 现在这一档是什么（`.notScheduled` / `.disabled` / `.waiting` / `.due` / `.missed`）。
    public static func decision(
        for entry: AgentScheduleEntry,
        now: Date,
        lastRun: Date? = nil,
        grace: TimeInterval = 0
    ) -> ScheduleDecision {
        TaskScheduler.decision(for: projected(entry), now: now, lastRun: lastRun, grace: grace)
    }

    /// 严格晚于 `date` 的下一次计划时刻（一次性任务已到期时为 `nil`）。
    public static func nextRun(
        for entry: AgentScheduleEntry,
        after date: Date,
        lastRun: Date? = nil
    ) -> Date? {
        TaskScheduler.nextRun(for: projected(entry), after: date, lastRun: lastRun)
    }

    /// `[from, to)` 里被错过的计划时刻（界面提示「错过了哪几次」用）。
    public static func missedRuns(
        for entry: AgentScheduleEntry,
        from: Date,
        to: Date,
        lastRun: Date? = nil,
        limit: Int = 100
    ) -> [Date] {
        TaskScheduler.missedRuns(for: projected(entry), from: from, to: to, lastRun: lastRun, limit: limit)
    }

    /// 这一轮该不该起一次会话（①②③④ 在这一处收口）。
    ///
    /// - Parameters:
    ///   - actions: 这一轮**打算做**的动作（判定与指纹来自既有件，见 `AgentScheduleAction`）。
    ///     只读档传空数组即「只起会话、不动任何有副作用的条目」。
    ///   - approvals: 审批侧的口径（`AgentApprovalGate` 的结论）。
    ///   - confirmedMissed: 用户是否在界面上确认了「现在就执行那一次错过的」。
    public static func plan(
        for entry: AgentScheduleEntry,
        now: Date,
        lastRun: Date? = nil,
        actions: [AgentScheduleAction] = [],
        approvals: AgentScheduleApprovals = .none,
        confirmedMissed: Bool = false,
        grace: TimeInterval = 0
    ) -> AgentScheduleRunPlan {
        let decision = decision(for: entry, now: now, lastRun: lastRun, grace: grace)

        switch decision {
        case .due(let plannedAt):
            return .run(plannedAt: plannedAt, actions: planned(actions, approvals: approvals))

        case .missed(let plannedAt, _):
            // ② 错过窗口**默认不补跑**：错过就是错过 —— 界面拿 `decision.message` 提示
            //    （「为免意外补跑，请确认是否现在执行」），只有用户**显式确认**才起这一次会话；
            //    记下来的仍是**原**计划时刻（留痕里一眼看得出这一跑是晚的）。
            guard confirmedMissed else { return .idle(reason: decision) }
            return .run(plannedAt: plannedAt, actions: planned(actions, approvals: approvals))

        case .notScheduled, .disabled, .waiting:
            // ④ 停用（以及未排期 / 还没到）⇒ **一次会话都不起**：动作一条都不会执行。
            return .idle(reason: decision)
        }
    }

    // MARK: 内部

    /// 把定时 agent 的排期**投影**成 `FR-AI-06` 的定义形状，交给同一台 `TaskScheduler`。
    ///
    /// 调度判定只读 `schedule` / `isEnabled` / `createdAt` 三格（`TaskScheduler` 的实现里
    /// 只碰这三处），所以这里把这三格逐字带过去，其余字段留空 —— 「起什么会话」是
    /// `AgentScheduleTarget` 的事，与时间计算无关。
    static func projected(_ entry: AgentScheduleEntry) -> DataTaskDefinition {
        DataTaskDefinition(
            id: entry.id,
            name: entry.target.title,
            specs: entry.target.prompt,
            source: .init(table: ""),
            target: .init(table: ""),
            schedule: entry.schedule,
            output: nil,
            isEnabled: entry.isEnabled,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt
        )
    }

    static func planned(
        _ actions: [AgentScheduleAction],
        approvals: AgentScheduleApprovals
    ) -> [AgentSchedulePlannedAction] {
        actions.map { action in
            AgentSchedulePlannedAction(
                name: action.name,
                disposition: action.disposition(approvals: approvals),
                payload: action.approval?.payload
            )
        }
    }
}
