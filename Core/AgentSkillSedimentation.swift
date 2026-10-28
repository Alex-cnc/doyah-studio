import Foundation

/// 一次已发生的任务（技能沉淀的**输入事实**，由调用方给；本层不读会话、不猜）。
public struct AgentTaskOutcome: Equatable, Sendable {
    public var taskID: String
    /// 这一类活的标识（同一类才有「重复出现」可言 —— 例如「跑 doc 三门」「改 swift 测试」）。
    public var category: String
    /// 关键词（触发条件的最小单位，取自这次实际做的事）。
    public var keywords: [String]
    /// 这次做成功的步骤（按顺序；空 = 没东西可抽）。
    public var steps: [String]
    public var succeeded: Bool
    /// **人确认过**（不是「模型觉得自己做对了」）。
    public var confirmedByUser: Bool
    public var at: Date

    public init(taskID: String, category: String, keywords: [String], steps: [String],
                succeeded: Bool, confirmedByUser: Bool, at: Date = Date()) {
        self.taskID = taskID
        self.category = category
        self.keywords = keywords
        self.steps = steps
        self.succeeded = succeeded
        self.confirmedByUser = confirmedByUser
        self.at = at
    }
}

/// 抽出来的一条技能候选（还没落库；落不落由调用方决定，理由一律给全）。
public struct AgentSkillCandidate: Equatable, Sendable {
    public var category: String
    /// 触发条件（关键词去重保序）。
    public var triggers: [String]
    /// 做法（来自**成功且被确认**的那几次；按出现顺序合并去重）。
    public var steps: [String]
    /// 证据：这几条是从哪几次任务抽的（可回溯）。
    public var evidenceTaskIDs: [String]

    public init(category: String, triggers: [String], steps: [String], evidenceTaskIDs: [String]) {
        self.category = category
        self.triggers = triggers
        self.steps = steps
        self.evidenceTaskIDs = evidenceTaskIDs
    }
}

/// 技能沉淀（`FR-AGT-KNOW-MEM-010`）。
///
/// 三条口径，每条都对着一种「抽出一堆垃圾技能」的现实错法：
/// 1. **只从成功且被确认的任务抽** —— 失败的做法、模型自认对的，一律不抽；
/// 2. **偶发不抽**：同类活至少出现 `minimumOccurrences` 次（默认 2）才算「一类」；
/// 3. **抽不出就说为什么**（理由枚举，不是一句“暂不支持”）。
public enum AgentSkillSedimentation {

    public struct Policy: Equatable, Sendable {
        /// 同类活至少出现几次才抽。
        public var minimumOccurrences: Int
        /// 一条技能最多带几个步骤（超出截断并如实标注）。
        public var maximumSteps: Int

        public init(minimumOccurrences: Int = 2, maximumSteps: Int = 12) {
            self.minimumOccurrences = minimumOccurrences
            self.maximumSteps = maximumSteps
        }

        public static let standard = Policy()
    }

    public enum Refusal: Equatable, Sendable {
        /// 这次没成功。
        case notSuccessful(taskID: String)
        /// 这次没人确认过。
        case notConfirmed(taskID: String)
        /// 没有步骤可抽。
        case emptySteps(taskID: String)
        /// 同类活只出现过 N 次（< 门槛）⇒ 偶发，不抽。
        case notRecurring(category: String, seen: Int, required: Int)
    }

    public struct Result: Equatable, Sendable {
        public var candidates: [AgentSkillCandidate]
        public var refusals: [Refusal]
        public var truncatedSteps: Int
    }

    /// 从一批任务里抽技能候选。**纯函数**（不读盘、不看时钟）。
    public static func distill(_ tasks: [AgentTaskOutcome],
                               policy: Policy = .standard) -> Result {
        var refusals: [Refusal] = []

        // ① 单条筛：成功 + 人确认 + 有步骤；不合格的逐条点名。
        var usable: [AgentTaskOutcome] = []
        for task in tasks {
            guard task.succeeded else { refusals.append(.notSuccessful(taskID: task.taskID)); continue }
            guard task.confirmedByUser else { refusals.append(.notConfirmed(taskID: task.taskID)); continue }
            guard !task.steps.isEmpty else { refusals.append(.emptySteps(taskID: task.taskID)); continue }
            usable.append(task)
        }

        // ② 分类：同类活要到门槛才算「一类」。
        var candidates: [AgentSkillCandidate] = []
        var truncated = 0
        let grouped = Dictionary(grouping: usable, by: \.category)
        for (category, group) in grouped.sorted(by: { $0.key < $1.key }) {
            guard group.count >= policy.minimumOccurrences else {
                refusals.append(.notRecurring(category: category,
                                              seen: group.count,
                                              required: policy.minimumOccurrences))
                continue
            }
            let ordered = group.sorted { $0.at < $1.at }
            var triggers: [String] = []
            var seenTriggers = Set<String>()
            for task in ordered {
                for keyword in task.keywords where seenTriggers.insert(keyword).inserted {
                    triggers.append(keyword)
                }
            }
            var steps: [String] = []
            var seenSteps = Set<String>()
            for task in ordered {
                for step in task.steps where seenSteps.insert(step).inserted {
                    steps.append(step)
                }
            }
            if steps.count > policy.maximumSteps {
                truncated += steps.count - policy.maximumSteps
                steps = Array(steps.prefix(policy.maximumSteps))
            }
            candidates.append(AgentSkillCandidate(category: category,
                                                  triggers: triggers,
                                                  steps: steps,
                                                  evidenceTaskIDs: ordered.map(\.taskID)))
        }

        return Result(candidates: candidates, refusals: refusals, truncatedSteps: truncated)
    }
}
