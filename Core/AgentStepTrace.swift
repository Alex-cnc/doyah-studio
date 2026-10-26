import Foundation

/// **过程可见**（`FR-AGT-UX-CONV-006` / 本端计划 P1-7）：循环里每一步都必须在界面上留下**一行**。
///
/// 判据是机械的：声明的跳数 = 记录条数（按 `index` 去重）—— 少一条就是「静默步」。
/// 记录的字段形状固定，界面侧不做二次拼装（否则两处口径会漂）。
public enum AgentStepKind: String, Codable, Sendable, CaseIterable {
    /// 一次工具调用（读文件 / 搜索 / 查询 / 改文件 …）。
    case tool
    /// 一次文件动作（读、写、改 —— 与 tool 分开是为了「改了哪个文件」可单独筛）。
    case file
    /// 一次命令执行（沙箱内 `run_command`）。
    case command
    /// 一次决策（模型自述「接下来做什么」被采纳/被拦住）。
    case decision
    /// 一次审批（发起、批准、拒绝）。
    case approval
}

/// 一步的可见记录。`index` 从 1 开始，与循环跳数同量纲。
public struct AgentStepRecord: Equatable, Sendable, Identifiable {
    public var index: Int
    public var kind: AgentStepKind
    /// 一行摘要（工具名 / 文件名 / 命令首词），**不含正文**。
    public var label: String
    /// 附加信息（如「拒绝：路径越界」），可空。
    public var detail: String?

    public init(index: Int, kind: AgentStepKind, label: String, detail: String? = nil) {
        self.index = index
        self.kind = kind
        self.label = label
        self.detail = detail
    }

    public var id: Int { index }
}

/// 一次运行的步骤轨迹。只有这一处能追加（界面只读）。
public struct AgentStepTrace: Equatable, Sendable {
    public private(set) var records: [AgentStepRecord]

    public init(records: [AgentStepRecord] = []) {
        self.records = records
    }

    /// 追加一步；`index` 自动取「下一条」，调用方不许自己编号（避免重号造成假绿）。
    @discardableResult
    public mutating func record(kind: AgentStepKind, label: String, detail: String? = nil) -> AgentStepRecord {
        let next = (records.map(\.index).max() ?? 0) + 1
        let record = AgentStepRecord(index: next, kind: kind, label: label, detail: detail)
        records.append(record)
        return record
    }

    /// 缺记录的步数：声明的跳数 − 实际出现的**唯一** `index` 数。`> 0` 即存在静默步。
    public func silentSteps(declared: Int) -> Int {
        let seen = Set(records.map(\.index)).count
        return max(0, declared - seen)
    }

    public func isEveryStepVisible(declared: Int) -> Bool {
        silentSteps(declared: declared) == 0
    }

    /// 按类别筛（界面「只看文件动作」这类视图用）。
    public func records(of kind: AgentStepKind) -> [AgentStepRecord] {
        records.filter { $0.kind == kind }
    }
}
