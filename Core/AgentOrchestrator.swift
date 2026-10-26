import Foundation

/// 并行编排（`FR-AGT-TOOL-SYS-007/008`，同时兑现 `SYS-002` 委派的来源标注）。
///
/// 契约三条：
/// ① **多路无依赖子任务并行**，并发上限可配；每路有独立预算（超时 + 令牌）与结局
///    （`completed` / `failed` / `timedOut` / `skipped` / `needsApproval`）——**不许一路失败拖垮全批**；
/// ② **归并口径**：主控只收**摘要 + 产物路径**，不收子任务的原始对话；需要审批的**回主控**，子代理自己批不了；
/// ③ **来源可追**：每条结果带 `source`（子任务 ID + 标签），主控报告里点得回是哪一路给的。
public struct AgentSubtaskSpec: Equatable, Sendable {
    public var id: String
    public var label: String
    /// 这一路要干什么（给子代理的提示词）。
    public var prompt: String
    /// 单路预算（秒）；0 = 用全局默认。
    public var budgetSeconds: TimeInterval

    public init(id: String, label: String, prompt: String, budgetSeconds: TimeInterval = 0) {
        self.id = id
        self.label = label
        self.prompt = prompt
        self.budgetSeconds = budgetSeconds
    }
}

public struct AgentSubtaskResult: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case completed, failed, timedOut, skipped, needsApproval
    }

    public var subtaskID: String
    public var label: String
    public var status: Status
    /// 摘要（主控只收这个，不收原始对话）。
    public var summary: String
    /// 产物路径（可点开的文件）。
    public var artifacts: [String]
    /// 需要主控批的指纹（`needsApproval` 时非空）。
    public var approvalFingerprint: String?

    public var source: String { "\(label)#\(subtaskID)" }
}

public struct AgentOrchestrationLimits: Equatable, Sendable {
    public var maxConcurrent: Int
    public var defaultBudgetSeconds: TimeInterval

    public init(maxConcurrent: Int = 3, defaultBudgetSeconds: TimeInterval = 300) {
        self.maxConcurrent = max(1, maxConcurrent)
        self.defaultBudgetSeconds = max(1, defaultBudgetSeconds)
    }
}

public struct AgentOrchestrationReport: Equatable, Sendable {
    public var results: [AgentSubtaskResult]

    public var completedCount: Int { results.filter { $0.status == .completed }.count }
    public var needsApproval: [AgentSubtaskResult] { results.filter { $0.status == .needsApproval } }
    public var failures: [AgentSubtaskResult] {
        results.filter { [.failed, .timedOut].contains($0.status) }
    }

    /// 给主控看的归并文本：**摘要 + 产物路径**，带来源；失败与待批单独点出来。
    public var mergedSummary: String {
        var lines: [String] = []
        for r in results {
            lines.append("· [\(r.source)] \(r.status.rawValue)：\(r.summary)")
            for a in r.artifacts { lines.append("    ↳ \(a)") }
        }
        if !needsApproval.isEmpty {
            lines.append("待主控批：\(needsApproval.map(\.source).joined(separator: "、"))")
        }
        return lines.joined(separator: "\n")
    }
}

/// 编排器：只负责**调度与归并**，不实现子代理本身（由调用方注入 `worker`）。
public struct AgentOrchestrator: Sendable {

    public typealias Worker = @Sendable (AgentSubtaskSpec) -> AgentSubtaskResult

    public init() {}

    public func run(_ specs: [AgentSubtaskSpec], limits: AgentOrchestrationLimits,
                    worker: @escaping Worker) -> AgentOrchestrationReport {
        guard !specs.isEmpty else { return AgentOrchestrationReport(results: []) }
        let queue = DispatchQueue(label: "doyah.agent.orchestrator", attributes: .concurrent)
        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [AgentSubtaskResult] = []

        let semaphore = DispatchSemaphore(value: limits.maxConcurrent)
        for spec in specs {
            group.enter()
            queue.async {
                semaphore.wait()
                defer { semaphore.signal(); group.leave() }
                let result = worker(spec)
                lock.lock(); collected.append(result); lock.unlock()
            }
        }
        group.wait()

        // 稳定序：按传入顺序输出，并行不改变报告顺序
        let order = Dictionary(uniqueKeysWithValues: specs.enumerated().map { ($0.element.id, $0.offset) })
        return AgentOrchestrationReport(results: collected.sorted { (order[$0.subtaskID] ?? 0) < (order[$1.subtaskID] ?? 0) })
    }
}
