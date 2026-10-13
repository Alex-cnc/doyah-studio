import Foundation

/// 行级差异（`FR-AI-20` ③「应用前先给出差异」）。
///
/// **口径如实**：用的是「公共前缀 + 公共后缀 + 中间整段替换」，**不是最小编辑距离** ——
/// 好处是 O(n)、不会在长文件上炸内存，且**每一行都真实来自原文或新文**（不发明内容）。
/// 中间只要有一行相同就少显示一行，这类「不够最小」的地方在注释里说明，不假装是最优 diff。
public enum AgentTextDiff {

    public struct Line: Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable {
            case context
            case added
            case removed
        }

        public var kind: Kind
        public var text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// 行级差异（含公共前后缀上下文）。
    public static func lines(before: String, after: String) -> [Line] {
        let old = splitLines(before)
        let new = splitLines(after)

        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }

        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }

        var result: [Line] = []
        for index in 0..<prefix { result.append(Line(kind: .context, text: old[index])) }
        for index in prefix..<(old.count - suffix) { result.append(Line(kind: .removed, text: old[index])) }
        for index in prefix..<(new.count - suffix) { result.append(Line(kind: .added, text: new[index])) }
        for offset in 0..<suffix { result.append(Line(kind: .context, text: old[old.count - suffix + offset])) }
        return result
    }

    /// 供审批单读的差异预览：首行是路径，其后每行带 `+` / `-` / 空格前缀。
    public static func preview(before: String, after: String, path: String) -> String {
        var output = path
        for line in lines(before: before, after: after) {
            switch line.kind {
            case .context: output += "\n " + line.text
            case .added: output += "\n+" + line.text
            case .removed: output += "\n-" + line.text
            }
        }
        return output
    }

    /// 差异里增删各几行（判据用；也方便渲染层写「+3 ×2」）。
    public static func summary(before: String, after: String) -> (added: Int, removed: Int, unchanged: Bool) {
        let all = lines(before: before, after: after)
        let added = all.filter { $0.kind == .added }.count
        let removed = all.filter { $0.kind == .removed }.count
        return (added, removed, added == 0 && removed == 0)
    }

    /// 按行切（**保留空行**：空行是内容的一部分，丢了会让差异对不上）。
    private static func splitLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
