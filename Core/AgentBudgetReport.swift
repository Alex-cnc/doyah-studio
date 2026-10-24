import Foundation

// `FR-AGT-CORE-LOOP-009`（契约 §7「流程」单次任务预算那一行 · 2026-10-24 前是散落在循环里的一句机器码）。
//
// 契约原话两条：
//   ① 逼近与触顶都要**当场说清「停在哪、做完哪些」**；
//   ② 触顶后不许静默截断，也不许把「预算用完」报成「任务完成」。
//
// 此前只有 `stepLimit:150` 这种机器码 —— 界面翻成人话后只剩「到了 150 步」，
// 用户真正想知道的是「做到哪儿了、哪些还没做」。本文件把这半句话补上：
// 用循环自己的读数（跳数 / 已执行工具 / 被拒工具 / 令牌）拼一行**可核对**的收尾话，
// 不引入新计数口径 —— 数字全部来自 `AgentLoopResult`，避免「报的和算的是两笔账」。
//
// 硬口径：
//   · **只由停止方式驱动**：不是预算停的（正常完成 / 取消 / 配额）⇒ 没有这份报告，返回 `nil`；
//   · 令牌数是「进来之前已花 + 这一轮花了」的合计，和上限同一个量纲（否则永远差一截）；
//   · 文案里每条数字后都带 `: 值` 形状（`150/150`、`3 次`），便于判据直接断言，不用解析中文。

/// 预算触顶的收尾读数（「停在哪、做完哪些」的机器形态 + 一行人话）。
public struct AgentBudgetReport: Equatable, Sendable {

    public enum Kind: String, Equatable, Sendable {
        case steps
        case tokens
    }

    public var kind: Kind
    /// 触顶的那条上限值。
    public var limit: Int
    /// 已跑跳数。
    public var steps: Int
    /// 已执行工具调用次数。
    public var executedToolCount: Int
    /// 被拒工具调用次数（未登记 / 参数不合 / 未批准）。
    public var rejectedToolCount: Int
    /// 令牌合计：**进来之前已花 + 这一轮花了**。
    public var tokensSpent: Int
    /// 令牌上限（与 `tokensSpent` 同量纲）。
    public var tokenLimit: Int

    public init(kind: Kind, limit: Int, steps: Int, executedToolCount: Int,
                rejectedToolCount: Int, tokensSpent: Int, tokenLimit: Int) {
        self.kind = kind
        self.limit = limit
        self.steps = steps
        self.executedToolCount = executedToolCount
        self.rejectedToolCount = rejectedToolCount
        self.tokensSpent = tokensSpent
        self.tokenLimit = tokenLimit
    }

    /// 人话一行（**不接管结论**：它只说「停在哪、做完哪些」，不说「任务完成」）。
    ///
    /// 形状固定，判据直接断言子串：
    ///   步数停 → `预算触顶：步数 150/150 —— 已跑 150 跳、完成 12 次工具调用（被拒 0 次），令牌 8,120/262,144`
    ///   令牌停 → `预算触顶：令牌 262,144/262,144 —— 已跑 40 跳、完成 61 次工具调用（被拒 2 次），停在发送下一跳之前`
    public var line: String {
        let tools = "已跑 \(steps) 跳、完成 \(executedToolCount) 次工具调用（被拒 \(rejectedToolCount) 次）"
        switch kind {
        case .steps:
            return "预算触顶：步数 \(steps)/\(limit) —— \(tools)，令牌 \(Self.grouped(tokensSpent))/\(Self.grouped(tokenLimit))"
        case .tokens:
            return "预算触顶：令牌 \(Self.grouped(tokensSpent))/\(Self.grouped(tokenLimit)) —— \(tools)，停在发送下一跳之前"
        }
    }

    /// 抹掉千分位（判据 / 日志里要好搜，界面渲染再补分隔符）。
    /// 一行里两处都抹：`8,120/262,144` → `8120/262144`。
    public var plainLine: String {
        line.replacingOccurrences(of: ",", with: "")
    }

    /// 千分位分组（`262144` → `262,144`）—— 中国人读数字要看位，读数行里不给裸数字。
    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var out: [Character] = []
        for (offset, ch) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (value < 0 ? "-" : "") + String(out.reversed())
    }
}

extension AgentLoopResult {

    /// 这次是不是**预算停的**；是 ⇒ 给出「停在哪、做完哪些」（契约 §7 ①）。
    ///
    /// 三种非预算停（完成 / 取消 / 配额）一律 `nil`：配额有它自己那句可读原因，
    /// 取消是用户主动，正常完成不需要「触顶」话术 —— **不许把别的事故套成预算故事**。
    public func budgetReport(limits: AgentLoopLimits) -> AgentBudgetReport? {
        let kind: AgentBudgetReport.Kind
        let limit: Int
        switch outcome {
        case .stopped(.stepLimit(let value)):
            kind = .steps
            limit = value
        case .stopped(.tokenLimit(let value)):
            kind = .tokens
            limit = value
        default:
            return nil
        }
        return AgentBudgetReport(
            kind: kind,
            limit: limit,
            steps: steps,
            executedToolCount: executedTools.count,
            rejectedToolCount: rejectedTools.count,
            tokensSpent: limits.tokensAlreadySpent + usage.billableTokens,
            tokenLimit: limits.maxTotalTokens
        )
    }
}
