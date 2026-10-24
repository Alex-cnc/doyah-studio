import Foundation

// `FR-AGT-QUAL-VERIFY-001`（契约「结果自验」：产出前自查 —— 能跑跑一遍、能对对一遍）。
//
// 与 `AgentCompletionVerifier` 的分工（**两个问题，别混**）：
//   · 完成判据（`FR-AI-31` ②）回答「**模型说做完了**，这话有没有可复核的证据」——证据来自模型 `EVIDENCE:` 引用；
//   · 结果自验（本文件）回答「**这一轮实际动过的东西**，交付前有没有自查过」——证据来自工具层自己产的账，
//     不看模型说什么。模型可以不引用，但**动过文件 / 跑过命令就该有自验记录**。
//
// 三条硬口径：
//   ① **有动作就要有记录**：写过 / 改过 / 跑过命令 ⇒ 逐条给出 `passed` 或 `failed`，一条都不许漏；
//   ② **跳过要判红**：这一轮确实动过东西，却拿不出任何自验结论 ⇒ `selfCheckSkipped:<原因>`（不是「通过」）；
//   ③ **只读不算动作**：`read_file` 一类不能当「我改好了」的自验，也不进分母（否则分母虚胖、通过率失真）。

/// 一条自验记录（**机器形态**；人话由界面语言表翻）。
public struct AgentSelfCheckItem: Equatable, Sendable {

    public enum Kind: String, Equatable, Sendable {
        /// 写盘 / 定点改 —— 自验方式是「此刻盘上仍是这份内容」（复核由完成判据那边做，这里只记结论）。
        case file
        /// 跑过命令 —— 自验方式是**退出码**（0 = 通过）。
        case command
    }

    public var kind: Kind
    public var toolName: String
    public var target: String
    public var passed: Bool
    /// 失败原因（机器码：`exitNonZero:2` / `digestMismatch` / `unverified`）；通过时为空串。
    public var reason: String
    public var step: Int

    public init(kind: Kind, toolName: String, target: String, passed: Bool,
                reason: String = "", step: Int) {
        self.kind = kind
        self.toolName = toolName
        self.target = target
        self.passed = passed
        self.reason = reason
        self.step = step
    }
}

/// 一轮的自验结论。
public struct AgentSelfCheckReport: Equatable, Sendable {

    public enum Status: String, Equatable, Sendable {
        /// 逐条都过了。
        case passed
        /// 有没过 / 没法验的条目。
        case failed
        /// 这一轮动过东西却一条自验都拿不出来 —— **判红**，不当通过。
        case skipped
        /// 这一轮没动任何东西（纯问答）—— 不报错，也不显示「已自验」。
        case nothingToCheck
    }

    public var status: Status
    public var items: [AgentSelfCheckItem]
    /// 跳过 / 失败的原因（机器码；`passed` / `nothingToCheck` 时为空串）。
    public var reason: String

    public init(status: Status, items: [AgentSelfCheckItem] = [], reason: String = "") {
        self.status = status
        self.items = items
        self.reason = reason
    }

    public var passedCount: Int { items.filter(\.passed).count }

    /// 过程面 / 审计读的那一格（`R-63` ③：不许静默）。
    /// 形状：`selfCheck:2/3` / `selfCheckFailed:exitNonZero:2` / `selfCheckSkipped:noEvidence` / `selfCheck:none`。
    public var code: String {
        switch status {
        case .passed: return "selfCheck:\(passedCount)/\(items.count)"
        case .failed: return "selfCheckFailed:\(reason)"
        case .skipped: return "selfCheckSkipped:\(reason)"
        case .nothingToCheck: return "selfCheck:none"
        }
    }

    public var isClean: Bool { status == .passed || status == .nothingToCheck }
}

/// 结果自验（**纯函数**：输入是这一轮的工具账，输出是结论；不读盘、不跑命令）。
///
/// 为什么不在这里再读一遍盘：盘上复核在完成判据那边已经做过一次，两处各读一次会出现
/// 「自验说对、完成判据说不对」的两套标准。这里只把**那一份结论**与命令退出码折成一张表。
public enum AgentSelfCheck {

    /// 折出本轮的自验报告。
    /// - Parameters:
    ///   - evidence: 这一轮工具层真的产出的账（写 / 改 / 命令 / 读）。
    ///   - verifiedPaths: 完成判据复核**通过**的路径（写 / 改类；没引用或对不上的不在此列）。
    ///   - failedCommandSteps: 本次复核判定**退出码对不上**的命令跳号。
    public static func report(evidence: [AgentCompletionEvidence],
                              verifiedPaths: Set<String> = [],
                              failedCommandSteps: Set<Int> = []) -> AgentSelfCheckReport {
        var items: [AgentSelfCheckItem] = []
        for entry in evidence {
            switch entry.kind {
            case .read:
                continue          // ③ 只读不算动作
            case .write, .edit:
                let ok = verifiedPaths.isEmpty ? false : verifiedPaths.contains(entry.path)
                items.append(AgentSelfCheckItem(
                    kind: .file, toolName: entry.toolName, target: entry.path,
                    passed: ok, reason: ok ? "" : "unverified", step: entry.step))
            case .command:
                if failedCommandSteps.contains(entry.step) {
                    items.append(AgentSelfCheckItem(
                        kind: .command, toolName: entry.toolName, target: "exit=\(entry.exitCode.map(String.init) ?? "?")",
                        passed: false, reason: "exitNonZero:\(entry.exitCode.map(String.init) ?? "?")",
                        step: entry.step))
                } else if let code = entry.exitCode {
                    items.append(AgentSelfCheckItem(
                        kind: .command, toolName: entry.toolName, target: "exit=\(entry.exitCode.map(String.init) ?? "?")",
                        passed: code == 0, reason: code == 0 ? "" : "exitNonZero:\(code)",
                        step: entry.step))
                } else {
                    // 命令没能报出退出码 ⇒ 没法验（**不许当通过**）。
                    items.append(AgentSelfCheckItem(
                        kind: .command, toolName: entry.toolName, target: "exit=\(entry.exitCode.map(String.init) ?? "?")",
                        passed: false, reason: "unverified", step: entry.step))
                }
            }
        }
        if items.isEmpty {
            return AgentSelfCheckReport(status: .nothingToCheck)
        }
        if let firstBad = items.first(where: { !$0.passed }) {
            return AgentSelfCheckReport(status: .failed, items: items, reason: firstBad.reason)
        }
        return AgentSelfCheckReport(status: .passed, items: items)
    }

    /// 「动过东西却没有自验结论」的判红口：工具账里有写 / 改 / 命令，报告却是空的 ⇒ 判 `skipped`。
    ///
    /// 为什么单独留这一口：`report(evidence:)` 在拿到空账时会如实说 `nothingToCheck`；
    /// 但如果账其实有、只是调用方漏接了（**接线错误**），那就必须**判红**而不是静默通过。
    public static func audit(evidence: [AgentCompletionEvidence],
                             report: AgentSelfCheckReport) -> AgentSelfCheckReport {
        let acted = evidence.contains { $0.kind != .read }
        guard acted, report.items.isEmpty else { return report }
        return AgentSelfCheckReport(status: .skipped, reason: "noEvidence")
    }
}
