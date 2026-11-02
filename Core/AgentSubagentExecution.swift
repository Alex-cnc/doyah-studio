import Foundation

/// **子代理执行器**（`FR-AGT-TOOL-SYS-002` 的执行面）+ **并发上限的执行面**（`FR-AGT-OPS-OBS-002`）。
///
/// 与 `AgentOrchestrator` 的分工：那一件只负责「调度与归并」的口径，**worker 由调用方注入**；
/// 这一件把 worker 接上去，并把三条验收要点落成机器可判的东西：
///
/// ① **独立上下文与独立留痕**：每一路跑在自己的子会话号上（`childSessionID`），
///    留痕按子会话落盘 —— 主控只收摘要，不收子任务的原始对话；
/// ② **来源标注**：结果沿用 `AgentSubtaskResult.source`（`标签#子任务ID`），汇总里逐条带；
/// ③ **失败隔离**：一路超时 / 失败 / 跳过都不影响其余各路 —— 批完照出报告。
///
/// 并发上限**只有一个来源**：`AgentConfigSnapshot.maxConcurrentSubtasks`（改完立即生效），
/// 这一件不另存一份配置，也不许调用方自己传一个「更宽松」的数。
public protocol AgentSubtaskRunner: Sendable {
    /// 跑一路子任务。`budgetSeconds` 是这一路的预算（超时由执行器判，见 `AgentSubagentExecutor`）。
    func run(_ spec: AgentSubtaskSpec, budgetSeconds: TimeInterval) async -> AgentSubtaskResult
}

/// 执行策略：**从配置快照来**（`FR-AGT-OPS-OBS-002` ①「每项配置有默认值与影响说明」）。
public struct AgentSubagentPolicy: Equatable, Sendable {

    /// 同时跑几路（1…16，与 `AgentConfigSnapshot` 的区间同一份）。
    public var maxConcurrent: Int
    /// 单路默认预算（秒）；子任务自己写了 `budgetSeconds` 就用它自己的。
    public var defaultBudgetSeconds: TimeInterval

    public init(maxConcurrent: Int, defaultBudgetSeconds: TimeInterval = 300) {
        self.maxConcurrent = min(16, max(1, maxConcurrent))
        self.defaultBudgetSeconds = max(1, defaultBudgetSeconds)
    }

    /// 配置是唯一来源：面板 / `/config` 改 `maxConcurrentSubtasks` ⇒ 下一次派活就按新值跑。
    public init(snapshot: AgentConfigSnapshot, defaultBudgetSeconds: TimeInterval = 300) {
        self.init(maxConcurrent: snapshot.maxConcurrentSubtasks,
                  defaultBudgetSeconds: defaultBudgetSeconds)
    }

    public var limits: AgentOrchestrationLimits {
        AgentOrchestrationLimits(maxConcurrent: maxConcurrent,
                                 defaultBudgetSeconds: defaultBudgetSeconds)
    }
}

/// 执行器：把 worker 接上，按策略派活、判超时、隔离失败、按输入序出报告。
public struct AgentSubagentExecutor: Sendable {

    public var policy: AgentSubagentPolicy
    public var runner: any AgentSubtaskRunner

    public init(policy: AgentSubagentPolicy, runner: any AgentSubtaskRunner) {
        self.policy = policy
        self.runner = runner
    }

    /// 派活。**同一批里重复的 id 不跑**（来源标注会乱）：后出现的记 `.skipped`，前一个照跑。
    public func run(_ specs: [AgentSubtaskSpec]) async -> AgentOrchestrationReport {
        var seen = Set<String>()
        var runnable: [AgentSubtaskSpec] = []
        var duplicates: [AgentSubtaskResult] = []
        for spec in specs {
            if seen.contains(spec.id) {
                duplicates.append(AgentSubtaskResult(subtaskID: spec.id, label: spec.label,
                                                     status: .skipped, summary: "duplicate-id",
                                                     artifacts: [], approvalFingerprint: nil))
            } else {
                seen.insert(spec.id)
                runnable.append(spec)
            }
        }

        var results: [AgentSubtaskResult] = []
        if !runnable.isEmpty {
            results = await runBounded(runnable)
        }
        results.append(contentsOf: duplicates)
        return AgentOrchestrationReport(results: Self.inInputOrder(results, specs: specs))
    }

    /// 有界并发：窗口 = `policy.maxConcurrent`，一路结束才放下一路进（**并发数不会被冲高**）。
    private func runBounded(_ specs: [AgentSubtaskSpec]) async -> [AgentSubtaskResult] {
        await withTaskGroup(of: AgentSubtaskResult.self) { group in
            var next = 0
            let window = min(policy.maxConcurrent, specs.count)
            while next < window {
                let spec = specs[next]
                group.addTask { await self.runOne(spec) }
                next += 1
            }
            var collected: [AgentSubtaskResult] = []
            while let result = await group.next() {
                collected.append(result)
                if next < specs.count {
                    let spec = specs[next]
                    group.addTask { await self.runOne(spec) }
                    next += 1
                }
            }
            return collected
        }
    }

    /// 一路跑完或到点。预算到点 ⇒ `.timedOut`（**这一路失败不牵连别路**）。
    ///
    /// 边界如实写：worker 若无视取消，`withTaskGroup` 会在退出前等它 —— 报告因此可能晚于预算，
    /// 但**不会**把这一路当成完成（状态已经是 `.timedOut`）。
    private func runOne(_ spec: AgentSubtaskSpec) async -> AgentSubtaskResult {
        let budget = spec.budgetSeconds > 0 ? spec.budgetSeconds : policy.defaultBudgetSeconds
        let runner = self.runner
        let outcome = await withTaskGroup(of: AgentSubtaskResult?.self) { group -> AgentSubtaskResult? in
            group.addTask { await runner.run(spec, budgetSeconds: budget) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(budget * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let outcome { return outcome }
        return AgentSubtaskResult(subtaskID: spec.id, label: spec.label, status: .timedOut,
                                  summary: "timeout", artifacts: [], approvalFingerprint: nil)
    }

    /// 报告顺序 = 传入顺序（并行不改变主控看到的次序）。
    static func inInputOrder(_ results: [AgentSubtaskResult],
                             specs: [AgentSubtaskSpec]) -> [AgentSubtaskResult] {
        let order = Dictionary(specs.enumerated().map { ($0.element.id, $0.offset) },
                               uniquingKeysWith: { first, _ in first })
        return results.sorted { (order[$0.subtaskID] ?? Int.max) < (order[$1.subtaskID] ?? Int.max) }
    }

    /// 子任务的**子会话号**：独立上下文 + 独立留痕的落点（主控只看摘要，不混进子任务的对话）。
    public static func childSessionID(parent: String, subtaskID: String) -> String {
        let safe = subtaskID.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "#", with: "-")
        return "\(parent)#sub-\(safe)"
    }
}

/// **真子代理**：把一路子任务跑成一次真正的 `AgentLoop`（不是假 worker）。
///
/// 三件事按契约落：
/// ① **独立上下文**：子任务的提示词替掉 `userPrompt`，会话号换成 `childSessionID`
///    ⇒ 留痕（`FR-AI-17`）与审计各落各的文件，主控的会话里只留摘要；
/// ② **预算**：执行器判超时（这一层不重复判），跳数 / 令牌沿用主控那一轮的限额；
/// ③ **结局如实映射**：`finished` ⇒ `completed`；`failed` ⇒ `failed`；
///    `stopped(.cancelled)` ⇒ `skipped`；其余停（步数 / 令牌 / 配额）⇒ `failed` 带机器码。
public struct AgentLoopSubtaskRunner: AgentSubtaskRunner {

    public var loop: AgentLoop
    /// 主控这一轮的上下文模板（提示词、请求模板、工作区都从它来）。
    public var template: AgentLoopContext
    /// 派活那一刻**主控已经用掉多少**（`NFR-ALL-GATE-AI-004` 判据 ①）。
    ///
    /// 子循环从这里起算 ⇒ ① 主控用过的量也压着子代理（配额不会被「派出去」绕过）；
    /// ② 收尾时「末 − 始」正好是**这一路自己花的**，不会把主控早先那几跳算第二遍。
    public var baseLedger: AgentQuotaLedger

    public init(loop: AgentLoop, template: AgentLoopContext,
                baseLedger: AgentQuotaLedger = .empty) {
        self.loop = loop
        self.template = template
        self.baseLedger = baseLedger
    }

    public func run(_ spec: AgentSubtaskSpec, budgetSeconds: TimeInterval) async -> AgentSubtaskResult {
        let childSession = AgentSubagentExecutor.childSessionID(parent: template.sessionID,
                                                                subtaskID: spec.id)
        let child = AgentLoopContext(systemPrompt: template.systemPrompt,
                                     userPrompt: spec.prompt,
                                     baseRequest: template.baseRequest,
                                     sessionID: childSession,
                                     workspace: template.workspace,
                                     chainID: "chain:\(childSession)",
                                     checkpointScopeID: childSession)
        // 子循环从**主控当前账本**起算（不是从循环被造出来时的那个数）——
        // 少了这一句，主控前面跑过的跳在子代理那边等于没花。
        var childLoop = loop
        childLoop.quotaLedger = baseLedger
        let result = await childLoop.run(context: child)
        var mapped = Self.map(result, spec: spec, budgetSeconds: budgetSeconds)
        // 这一路自己花掉的 = 末 − 始（主控要把它计进主账，见调用处）。
        if let end = result.quotaLedger {
            mapped.quotaUsage = end.delta(since: baseLedger)
        }
        return mapped
    }

    /// 循环结局 → 子任务结局（机器码进 `summary`，人话由渲染入口给）。
    public static func map(_ result: AgentLoopResult, spec: AgentSubtaskSpec,
                           budgetSeconds: TimeInterval) -> AgentSubtaskResult {
        switch result.outcome {
        case .finished(let text):
            return AgentSubtaskResult(subtaskID: spec.id, label: spec.label, status: .completed,
                                      summary: summarized(text), artifacts: [], approvalFingerprint: nil)
        case .failed(let reason):
            return AgentSubtaskResult(subtaskID: spec.id, label: spec.label, status: .failed,
                                      summary: reason, artifacts: [], approvalFingerprint: nil)
        case .stopped(let stop):
            let status: AgentSubtaskResult.Status = stop == .cancelled ? .skipped : .failed
            return AgentSubtaskResult(subtaskID: spec.id, label: spec.label, status: status,
                                      summary: "stopped:\(stop.reason)", artifacts: [],
                                      approvalFingerprint: nil)
        }
    }

    /// 主控只收摘要：取首段、封顶 400 字（**不收原始对话**，与编排契约一致）。
    static func summarized(_ text: String) -> String {
        let firstBlock = text.split(separator: "\n\n", maxSplits: 1,
                                    omittingEmptySubsequences: true).first.map(String.init) ?? text
        let trimmed = firstBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 400 ? trimmed : String(trimmed.prefix(400)) + "…"
    }
}

/// 模型发来的 `dispatch_subtasks` 参数解析（`tasks` = JSON 数组字符串）。
///
/// 形状只认这一种：`[{"id":"…","label":"…","prompt":"…","budgetSeconds":120?}]`。
/// **解析不出来就如实拒**（返回机器码），不猜、不补默认提示词 —— 替模型编一条 prompt，
/// 等于让它一句话派出一路没人认领的活。
public enum AgentSubtaskSpecList {

    public enum Problem: String, Error, Equatable, Sendable {
        case argumentsNotObject
        case tasksNotString
        case tasksNotArray
        case entryNotObject
        case idMissing
        case promptMissing
    }

    public static func parse(argumentsJSON: String) -> Result<[AgentSubtaskSpec], Problem> {
        guard let data = argumentsJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.argumentsNotObject)
        }
        guard let raw = root["tasks"] as? String else { return .failure(.tasksNotString) }
        guard let arrayData = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: arrayData) as? [Any] else {
            return .failure(.tasksNotArray)
        }
        var specs: [AgentSubtaskSpec] = []
        for entry in array {
            guard let item = entry as? [String: Any] else { return .failure(.entryNotObject) }
            guard let id = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty else { return .failure(.idMissing) }
            guard let prompt = (item["prompt"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty else {
                return .failure(.promptMissing)
            }
            let label = (item["label"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? id
            let budget = (item["budgetSeconds"] as? Double) ?? 0
            specs.append(AgentSubtaskSpec(id: id, label: label.isEmpty ? id : label,
                                          prompt: prompt, budgetSeconds: budget))
        }
        return .success(specs)
    }
}
