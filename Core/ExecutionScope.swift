import Foundation

/// 执行目标的判定（FR-EXEC-14）：**这次到底跑哪一段**。
///
/// 口径（2026-09-27 需求提出者拍板）：
/// - 编辑器里有选区 → **就跑选中的那一段**；
/// - 没有选区 → **跑整篇**。
///
/// **没有「运行范围」这个开关** —— 原来那三档（整篇 / 光标所在语句 / 选中片段）要用户先设一次，
/// 需求提出者原话：「我期望的是，用户没有选择某条 SQL 时就执行编辑框里所有 SQL，否则就是执行
/// 用户选择，并不需要用户还去设置一下是执行整个脚本还是只执行选择，这是多此一举」。
/// `选中就跑选中、没选就跑全部` 本身就是所有 SQL 客户端的习惯，再挂一个开关只会多出
/// 一个「设错了自己不知道」的失败面。
///
/// **不静默放大**：选中的内容全是空白时**不**退回跑整篇 —— 那等于把一次小操作放大成整篇脚本，
/// 风险方向是错的；此时如实报「没有可执行的内容」。
///
/// 选区由调用方给（编辑器里**显示中**那一段，见 `EditorCommandCenter.selectionForExecution`）。
public enum ExecutionScope {

    /// 这次实际跑了哪一段（写进 Output，让「跑了什么」有据可查）。
    public enum Source: String, Codable, Sendable, CaseIterable {
        /// 编辑器里选了 → 只跑选中的那段。
        case selection
        /// 没选 → 跑整个编辑器。
        case wholeScript
    }

    /// 解析结果。
    public struct Resolution: Equatable, Sendable {
        /// 将要执行的 SQL；为空表示**没有可执行内容**（见 `issue`）。
        public var sql: String
        /// 这一段的来源（选中片段 / 整篇）。
        public var source: Source
        /// 没有可执行内容时的可读原因。
        public var issue: Issue?

        public init(sql: String, source: Source, issue: Issue? = nil) {
            self.sql = sql
            self.source = source
            self.issue = issue
        }
    }

    /// 没有可执行内容的原因。
    public enum Issue: String, Equatable, Sendable {
        /// 选中的内容（去掉空白后）是空的。
        case emptySelection
        /// 编辑器里没有内容。
        case emptyText
    }

    /// 解析出将要执行的 SQL。
    ///
    /// - Parameter selection: 编辑器的选区（UTF-16，`NSRange` 语义）；`length == 0` 视为「没有选区」。
    ///   越界（理论上不该发生：它来自显示中的 `NSTextView`）按「没有选区」处理 ——
    ///   宁可跑整篇，也不去猜一段可能的旧偏移。
    public static func resolve(
        text: String,
        selection: NSRange? = nil
    ) -> Resolution {
        if let selection, selection.length > 0, let range = clamp(selection, to: text) {
            let selected = substring(text, range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selected.isEmpty else {
                // 选中的全是空白：**不**退回整篇（那是一次静默放大），如实报。
                return Resolution(sql: "", source: .selection, issue: .emptySelection)
            }
            return Resolution(sql: selected, source: .selection)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Resolution(sql: "", source: .wholeScript, issue: .emptyText)
        }
        return Resolution(sql: text, source: .wholeScript)
    }

    // MARK: - 内部

    static func clamp(_ range: NSRange, to text: String) -> NSRange? {
        let length = (text as NSString).length
        guard range.location >= 0, range.location <= length else { return nil }
        let usable = min(range.length, length - range.location)
        guard usable > 0 else { return nil }
        return NSRange(location: range.location, length: usable)
    }

    static func substring(_ text: String, _ range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }
}
