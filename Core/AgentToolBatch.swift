import Foundation

/// **工具并行与保序**（概设 §18.1 第 13 条 / `FR-AGT-CORE-LOOP-012`）。
///
/// 契约原文：同一次响应里的多个调用，**只读工具并行、写类与审批类串行**；并行结果按**调用原序**
/// 回灌，审计为同批调用盖同一个**批号**（batch id）以保因果。
///
/// 这里只放**判据能直接判的东西**：怎么切段、怎么并发、怎么收回顺序。
/// 「哪条调用算只读」不在这里决定 —— 那是注册表的 `AgentToolLevel`，由调用方传入。
public enum AgentToolBatchSegment: Equatable, Sendable {
    /// 一条走原串行路径（写类 / 审批类 / 未登记 / 重复到顶）。
    case serial(AgentToolInvocation)
    /// 同批并发（≥2 条只读）。
    case parallel([AgentToolInvocation])
}

public enum AgentToolBatchPlanner {
    /// 从队首切出**连续**的可并行前缀；不足 2 条返回空数组（交回串行路径，行为逐字不变）。
    ///
    /// 为什么只切「连续」前缀：`[读, 写, 读]` 里第二段的读如果与第一段的读并到一起，
    /// 它就能越过中间那次写看到**写之后**的状态 —— 因果会被打乱。批内并发、批间串行，
    /// 就是为了让「读到的世界」与「调用写的顺序」一致。
    public static func parallelPrefix(_ invocations: [AgentToolInvocation],
                                      isParallelizable: (AgentToolInvocation) -> Bool) -> [AgentToolInvocation] {
        var run: [AgentToolInvocation] = []
        for invocation in invocations {
            guard isParallelizable(invocation) else { break }
            run.append(invocation)
        }
        return run.count >= 2 ? run : []
    }
}

public enum AgentToolBatchRunner {
    public struct Result: Sendable {
        public let index: Int
        public let outcome: AgentToolOutcome
        public init(index: Int, outcome: AgentToolOutcome) {
            self.index = index
            self.outcome = outcome
        }
    }

    /// 并发跑同一批，**返回顺序 = 输入顺序**（不是完成先后）。
    ///
    /// 判据 ③ 就落在这里：先收齐再按 `index` 排 —— 谁先跑完不影响回灌顺序。
    public static func run(_ invocations: [AgentToolInvocation],
                           execute: @Sendable @escaping (AgentToolInvocation) async -> AgentToolOutcome)
    async -> [Result] {
        guard invocations.count > 1 else {
            guard let only = invocations.first else { return [] }
            let outcome = await execute(only)
            return [Result(index: 0, outcome: outcome)]
        }
        return await withTaskGroup(of: Result.self) { group in
            for (index, invocation) in invocations.enumerated() {
                group.addTask { Result(index: index, outcome: await execute(invocation)) }
            }
            var collected: [Result] = []
            collected.reserveCapacity(invocations.count)
            for await result in group { collected.append(result) }
            return collected.sorted { $0.index < $1.index }
        }
    }
}

/// 批号：同批调用共用一个，批间不同。审计靠它还原「批内并发、批间串行」。
public enum AgentToolBatchID {
    public static func make() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    /// 审计里的写法：`batch:<id>#<第几条>/<共几条>`。单条串行也盖号（`#1/1`），
    /// 这样「有没有批号」可以整体判，不用分两条路径。
    public static func token(batch: String, index: Int, count: Int) -> String {
        "batch:\(batch)#\(index)/\(count)"
    }
}
