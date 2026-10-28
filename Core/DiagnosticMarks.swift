import Foundation

/// 编辑器上要画的诊断标记 —— **检查器与界面之间的唯一一份投影**（`FR-STD-WS-NAV-012`）。
///
/// ## 为什么要有这一层（而不是在视图里 `for diagnostic in diagnostics` 直接画）
///
/// 需求写死了一条口径：「**检查器与界面同源，不许两套判定**」。此前画下划线的代码在
/// `SQLEditorView.apply` 里自己算范围（`max(utf16Length, 1)` + 越界判断），而"鼠标停在哪条诊断上"
/// 若由视图再算一遍，就出现了**两套范围判定** —— 画出来的地方悬浮不出说明、能悬浮出说明的地方没画线，
/// 这类不一致在真机上才看得见，判据抓不到。
///
/// 所以范围口径收到这里：投影是一**纯函数**，编辑器画线、悬浮命中、以及单测都吃同一份输出。
/// 视图只剩"把 `range` 画成虚线"这一件事。
///
/// ## 为什么越界的诊断要**丢掉**而不是挪到最近的可画位置
///
/// 挪位置会让标记落到与问题无关的字符上（例如"未闭合字符串"被画到某个关键字下面），
/// 用户点着它去改，改的是对的地方 —— 比不画更坏。丢掉是诚实的：这篇文本里没有那个位置。
public struct DiagnosticMark: Identifiable, Hashable, Sendable {
    /// 来源诊断的 id：同一条诊断在投影后仍是同一个身份（`ForEach` / 悬浮比对都靠它）。
    public let id: UUID
    /// UTF-16 起点（0-based，与 `NSTextStorage` / `NSRange` 同一坐标系）。
    public let location: Int
    /// UTF-16 长度，恒 ≥ 1。
    public let length: Int
    public let severity: SQLDiagnostic.Severity
    public let message: String
    /// 1-based 行号 / 列号（只用于人话与命中后的定位，不参与画线）。
    public let line: Int
    public let column: Int

    public init(
        id: UUID,
        location: Int,
        length: Int,
        severity: SQLDiagnostic.Severity,
        message: String,
        line: Int,
        column: Int
    ) {
        self.id = id
        self.location = location
        self.length = length
        self.severity = severity
        self.message = message
        self.line = line
        self.column = column
    }

    public var range: NSRange {
        NSRange(location: location, length: length)
    }

    public var locationDescription: String {
        "第 \(line) 行第 \(column) 列"
    }

    /// 悬浮时要说的那一句：**问题本身 + 位置**。
    ///
    /// 只给位置（"第 1 行第 8 列"）等于什么都没说 —— 需求要的是"一句**可读**说明"，
    /// 说明来自检查器（`SQLLinter`），这里只负责拼装，不另写文案。
    public var hoverText: String {
        "\(message) · \(locationDescription)"
    }
}

public enum DiagnosticMarks {

    /// 把一次检查的结论投影成"要画在编辑器上的标记"。
    ///
    /// 规则（每条都有单测，且都能判红）：
    /// 1. **越界丢弃**：起点 < 0 或 ≥ 文本长度 ⇒ 丢（理由见 `DiagnosticMark` 的文档）。
    /// 2. **长度至少 1 且不越过文末**：零长度诊断按 1 个字符画，否则看不见；跨过文末的截到文末。
    /// 3. **同范围同文案去重**：检查器给重复结论时只画一条（否则悬浮只会反复说同一句）。
    /// 4. **顺序确定**：按起点 → 长度 → 严重度（错误在前）→ 文案排序，两次投影逐元素相同。
    public static func project(_ diagnostics: [SQLDiagnostic], textLength: Int) -> [DiagnosticMark] {
        let limit = max(textLength, 0)
        guard limit > 0 else { return [] }

        var seen = Set<String>()
        var marks: [DiagnosticMark] = []
        marks.reserveCapacity(diagnostics.count)

        for diagnostic in diagnostics {
            let start = diagnostic.utf16Location
            guard start >= 0, start < limit else { continue }

            var length = max(diagnostic.utf16Length, 1)
            if start + length > limit {
                length = limit - start
            }
            guard length > 0 else { continue }

            let key = "\(start)|\(length)|\(diagnostic.severity.rawValue)|\(diagnostic.message)"
            guard seen.insert(key).inserted else { continue }

            marks.append(
                DiagnosticMark(
                    id: diagnostic.id,
                    location: start,
                    length: length,
                    severity: diagnostic.severity,
                    message: diagnostic.message,
                    line: diagnostic.line,
                    column: diagnostic.column
                )
            )
        }

        marks.sort { lhs, rhs in
            if lhs.location != rhs.location { return lhs.location < rhs.location }
            if lhs.length != rhs.length { return lhs.length < rhs.length }
            if lhs.severity != rhs.severity { return lhs.severity == .error }
            return lhs.message < rhs.message
        }
        return marks
    }

    /// 鼠标第 `offset` 个 UTF-16 单元落在哪条标记上（`nil` = 落在空白处）。
    ///
    /// **重叠时取最窄的那条**：嵌套诊断（例如整段未闭合注释里又报一处括号）用宽的那条当悬浮答案是
    /// 一句泛话，用户要的通常是更具体的那一句。同样窄时错误优先。
    public static func mark(at offset: Int, in marks: [DiagnosticMark]) -> DiagnosticMark? {
        var best: DiagnosticMark?
        for mark in marks {
            guard offset >= mark.location, offset < mark.location + mark.length else { continue }
            guard let current = best else {
                best = mark
                continue
            }
            if mark.length != current.length {
                if mark.length < current.length { best = mark }
                continue
            }
            if mark.severity != current.severity, mark.severity == .error {
                best = mark
            }
        }
        return best
    }
}
