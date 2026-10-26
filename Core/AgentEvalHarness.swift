import Foundation

/// 可评测（`FR-AGT-OPS-OBS-003`）：拿一组固定任务回归「它有没有变笨」，输出**可对比的通过率**。
///
/// 口径：
/// ① 用例是**固定**的（写进仓库，不临时造）—— 否则两次跑的不是同一把尺；
/// ② 每条只看**可判的期望**（包含子串 / 精确相等 / 退出码），不看观感；
/// ③ 报告带 `passRate` 与失败用例清单，`diff(against:)` 直接给出「哪几条这次掉了」；
/// ④ 失败**不抛异常**（回归跑的是全量，一条挂不该中断整批），异常只留 `error` 字段。
public struct AgentEvalCase: Equatable, Sendable {
    public enum Expectation: Equatable, Sendable {
        case contains(String)
        case equals(String)
        /// 期望执行失败（用来钉住"该拒就拒"）。
        case fails
    }

    public var id: String
    public var prompt: String
    public var expectation: Expectation

    public init(id: String, prompt: String, expectation: Expectation) {
        self.id = id
        self.prompt = prompt
        self.expectation = expectation
    }
}

public struct AgentEvalCaseResult: Equatable, Sendable {
    public var caseID: String
    public var passed: Bool
    public var output: String
    /// 判词（为什么算过 / 为什么挂）—— 报告里要能一眼看出差别。
    public var verdict: String
}

public struct AgentEvalReport: Equatable, Sendable {
    public var results: [AgentEvalCaseResult]
    public var durationMilliseconds: Int

    public var total: Int { results.count }
    public var passedCount: Int { results.filter(\.passed).count }
    public var failedIDs: [String] { results.filter { !$0.passed }.map(\.caseID) }
    public var passRate: Double { total == 0 ? 0 : Double(passedCount) / Double(total) }

    /// 一行读数（日报/聊天里贴这一行就够）。
    public var headline: String {
        String(format: "pass %d/%d (%.0f%%)", passedCount, total, passRate * 100)
    }

    /// 与另一次跑对比：返回这次新掉的用例 ID（上次过、这次挂）。
    public func regressions(against previous: AgentEvalReport) -> [String] {
        let before = Dictionary(uniqueKeysWithValues: previous.results.map { ($0.caseID, $0.passed) })
        return results.filter { $0.passed == false && before[$0.caseID] == true }.map(\.caseID)
    }
}

public struct AgentEvalRunner: Sendable {
    /// 被测的那一侧：给 prompt，回 (输出文本, 是否成功)。
    public typealias Subject = @Sendable (String) -> (output: String, ok: Bool)

    public init() {}

    public func run(_ cases: [AgentEvalCase], subject: Subject) -> AgentEvalReport {
        let started = Date()
        var results: [AgentEvalCaseResult] = []
        for evalCase in cases {
            let produced = subject(evalCase.prompt)
            let (passed, verdict) = judge(evalCase.expectation, output: produced.output, ok: produced.ok)
            results.append(.init(caseID: evalCase.id, passed: passed, output: produced.output, verdict: verdict))
        }
        return AgentEvalReport(results: results,
                               durationMilliseconds: Int(Date().timeIntervalSince(started) * 1000))
    }

    private func judge(_ expectation: AgentEvalCase.Expectation, output: String, ok: Bool) -> (Bool, String) {
        switch expectation {
        case let .contains(needle):
            if case let .some(found) = output.range(of: needle) {
                return (true, "含「\(output[found])」")
            }
            return (false, "缺「\(needle)」")
        case let .equals(expected):
            return (output == expected, output == expected ? "完全相等" : "不等（实际 \(preview(output))）")
        case .fails:
            return (!ok, ok ? "本该失败却成功了" : "按预期失败")
        }
    }

    private func preview(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: "⏎")
        return flat.count <= 40 ? flat : String(flat.prefix(40)) + "…"
    }
}
