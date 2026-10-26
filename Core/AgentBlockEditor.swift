import Foundation

/// **编辑工具**（`FR-AGT-TOOL-EDIT-001` / 本端计划 P4-编辑）：按行/块改，给差异，**不整文件重写**。
///
/// 「不整文件重写」是可判的：一次编辑必须是**唯一锚点替换**或**行区间替换**；
/// 整篇覆盖要显式说明理由（`wholeFile: true`），否则拒绝。
public enum AgentEditError: Error, Equatable, Sendable {
    case anchorNotFound
    case anchorNotUnique(count: Int)
    case rangeOutOfBounds(requested: ClosedRange<Int>, lines: Int)
    case wholeFileRewriteNotAllowed
    case emptyNewText
}

public struct AgentEditResult: Equatable, Sendable {
    public var updated: String
    /// 差异行（`-` 旧 / `+` 新 / 空格 上下文），只含变动窗口。
    public var diff: [String]
    public var changedLines: Int

    public init(updated: String, diff: [String], changedLines: Int) {
        self.updated = updated
        self.diff = diff
        self.changedLines = changedLines
    }
}

public enum AgentBlockEditor {

    /// 唯一锚点替换（`edit_file` 的语义）。
    public static func replaceAnchor(in text: String, anchor: String, with replacement: String) -> Result<AgentEditResult, AgentEditError> {
        guard !replacement.isEmpty else { return .failure(.emptyNewText) }
        let occurrences = ranges(of: anchor, in: text)
        guard !occurrences.isEmpty else { return .failure(.anchorNotFound) }
        guard occurrences.count == 1 else { return .failure(.anchorNotUnique(count: occurrences.count)) }
        let range = occurrences[0]
        let updated = text.replacingCharacters(in: range, with: replacement)
        return .success(AgentEditResult(updated: updated,
                                        diff: diffLines(old: text, new: updated),
                                        changedLines: changedLineCount(old: text, new: updated)))
    }

    /// 行区间替换（1 基闭区间）。
    public static func replaceLines(in text: String, range: ClosedRange<Int>, with replacement: [String]) -> Result<AgentEditResult, AgentEditError> {
        var lines = text.components(separatedBy: "\n")
        guard range.lowerBound >= 1, range.upperBound <= lines.count else {
            return .failure(.rangeOutOfBounds(requested: range, lines: lines.count))
        }
        lines.replaceSubrange((range.lowerBound - 1)...(range.upperBound - 1), with: replacement)
        let updated = lines.joined(separator: "\n")
        return .success(AgentEditResult(updated: updated,
                                        diff: diffLines(old: text, new: updated),
                                        changedLines: changedLineCount(old: text, new: updated)))
    }

    /// 整篇覆盖：默认拒（要求走审批 + 说明）；`wholeFile: true` 才放行。
    public static func rewrite(in text: String, with replacement: String, wholeFile: Bool) -> Result<AgentEditResult, AgentEditError> {
        guard wholeFile else { return .failure(.wholeFileRewriteNotAllowed) }
        return .success(AgentEditResult(updated: replacement,
                                        diff: diffLines(old: text, new: replacement),
                                        changedLines: changedLineCount(old: text, new: replacement)))
    }

    // MARK: 差异

    static func ranges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        guard !needle.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var searchStart = haystack.startIndex
        while let found = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            result.append(found)
            searchStart = found.upperBound
            if searchStart >= haystack.endIndex { break }
        }
        return result
    }

    /// 极简行差异：公共前缀/后缀之外的行全算变更（够判「改了什么」，不追最小编辑距离）。
    public static func diffLines(old: String, new: String) -> [String] {
        let a = old.components(separatedBy: "\n")
        let b = new.components(separatedBy: "\n")
        var prefix = 0
        while prefix < min(a.count, b.count) && a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix &&
              a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let removed = a[prefix..<(a.count - suffix)]
        let added = b[prefix..<(b.count - suffix)]
        if removed.isEmpty && added.isEmpty { return [] }
        var out = removed.map { "-" + $0 }
        out.append(contentsOf: added.map { "+" + $0 })
        return out
    }

    public static func changedLineCount(old: String, new: String) -> Int {
        diffLines(old: old, new: new).count
    }
}
