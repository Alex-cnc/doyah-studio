import Foundation

/// 许愿式编程（`FR-STD-WS-AI-002`）的**交付面**：把「这一轮 Agent 已经落盘的改动 + 验证读数」
/// 拼成一张清单（改了哪些文件 + 逐行差异 + **没跑通就说没跑通**）。
///
/// 为什么不另造一种清单类型：`WishProposal` 已经是这个形状（暂存面 `WishStaging` 用它），
/// 交付面再用同一份 —— 两个类型各写一遍差异与计数，界面与判据迟早各说一套，
/// 而「清单上写的」和「审批单上看到的」必须是同一份 `AgentTextDiff` 切分。
/// 这里只补暂存面没有的两件事：
/// 1. **从已落盘的账反推清单**（`AgentEditJournal.undoable` → `WishProposal`）；
/// 2. **判定这一轮跑没跑通**（验收要点 ③：未通过验证的产出必须标明「没跑通」）。
///
/// 三条口径：
/// · **同一路径多次改只出一条**：前像取**最早**、后像取**最新**、差异按「最早前像 → 最新后像」算
///   （与 `WishStaging.upsert` 同一口径）。取最后一次前像会把中间态当成起点，差异就少一段。
/// · **净效果为零不算改动**：改完又改回盘上原文 ⇒ 不进清单（不为了清单好看编工作量）。
/// · **删除型改动不在这个账上**：`AgentAppliedEdit.after` 非可选，账上记的都是「写成的正文」，
///   所以交付清单今天只会出 `created` / `modified` 两类；`WishFileChange.Kind.deleted`
///   留给暂存面。这是如实边界，不是遗漏。
public enum WishDelivery {

    /// 这一轮交付的判定。**只有四种，且互斥** —— 界面按它选一句话，不自己拼。
    public enum Verdict: String, Equatable, Sendable {
        /// 一个改动都没有：如实说「没改」，不是「交付成功」。
        case noChanges
        /// 有改动、但这一轮没有记下任何验证读数 ⇒ **不许当成跑通了**。
        case unverified
        /// 最后一条已落盘的命令退出码为 0。
        case passed
        /// 最后一条已落盘的命令非零退出 ⇒ 交付面必须标「没跑通」。
        case failed
    }

    /// 从已落盘的账拼交付清单。
    ///
    /// - Parameters:
    ///   - edits: **还能撤的那些**（`AgentEditJournal.undoable`）—— 已撤的不该出现在「这一轮交付了什么」里。
    ///   - validation: 这一轮的验证读数；`nil` ⇒ 未验证。
    public static func proposal(runID: String,
                                root: String,
                                edits: [AgentAppliedEdit],
                                validation: WishValidation?) -> WishProposal {
        // 同一路径：前像取最早、后像取最新（顺序按首次出现，最后再按路径排，读数才稳定可比）。
        var firstBefore: [String: String?] = [:]
        var lastAfter: [String: String] = [:]
        var order: [String] = []
        var seen = Set<String>()
        for edit in edits {
            if !seen.contains(edit.path) {
                seen.insert(edit.path)
                order.append(edit.path)
                firstBefore[edit.path] = edit.before
            }
            lastAfter[edit.path] = edit.after
        }

        var changes: [WishFileChange] = []
        for path in order.sorted() {
            guard let after = lastAfter[path] else { continue }
            let before = firstBefore[path] ?? nil
            // 净效果为零：改完又改回原文 ⇒ 不算改动。
            if let before, before == after { continue }
            let kind: WishFileChange.Kind = before == nil ? .created : .modified
            var diff = AgentTextDiff.lines(before: before ?? "", after: after)
            // 与暂存面同一条：新建文件的「空前像」不是「删掉了一行」。
            if kind == .created {
                diff = diff.filter { $0.kind != .removed }
            }
            changes.append(WishFileChange(path: path,
                                          kind: kind,
                                          diff: diff,
                                          addedLines: diff.filter { $0.kind == .added }.count,
                                          removedLines: diff.filter { $0.kind == .removed }.count,
                                          beforeDigest: before.map(AgentWriteSnapshot.digest),
                                          afterDigest: AgentWriteSnapshot.digest(after)))
        }

        let state: WishProposal.State
        if changes.isEmpty {
            state = .noChanges
        } else if let validation, !validation.passed {
            state = .validationFailed
        } else {
            state = .awaitingAcceptance
        }
        return WishProposal(runID: runID,
                            root: root,
                            changes: changes,
                            rejections: [],
                            validation: validation,
                            state: state)
    }

    /// 交付判定。**改动为空优先**：什么都没改时，验证通过也不叫「交付成功」。
    public static func verdict(of proposal: WishProposal) -> Verdict {
        guard !proposal.changes.isEmpty else { return .noChanges }
        guard let validation = proposal.validation else { return .unverified }
        return validation.passed ? .passed : .failed
    }
}
