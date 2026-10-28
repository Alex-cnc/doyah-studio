import XCTest
@testable import DoyahCore

/// `FR-STD-WS-NAV-012`（静态检查结果上屏）的判据。
///
/// 这一组守的是需求里那四条：① 结论以范围落在编辑器上；② 悬浮那句说明**来自检查器**；
/// ③ **界面与检查器同源**（投影吃的就是 `SQLLinter` 的输出，检出集合一致）；④ 无诊断时不留残留。
final class DiagnosticMarksTests: XCTestCase {

    /// ① + ③：投影的条数 / 范围 / 文案与检查器逐条一致（同源）。
    func testProjectionMatchesLinterOutput() {
        let sql = "SELECT 'abc"
        let diagnostics = SQLLinter(databaseType: .postgresql).analyze(sql)
        XCTAssertEqual(diagnostics.count, 1, "前提：这段 SQL 恰好一条诊断")

        let marks = DiagnosticMarks.project(diagnostics, textLength: (sql as NSString).length)
        XCTAssertEqual(marks.count, diagnostics.count)
        XCTAssertEqual(marks[0].location, diagnostics[0].utf16Location)
        XCTAssertEqual(marks[0].length, max(diagnostics[0].utf16Length, 1))
        XCTAssertEqual(marks[0].message, diagnostics[0].message)
        XCTAssertEqual(marks[0].severity, diagnostics[0].severity)
        XCTAssertEqual(marks[0].id, diagnostics[0].id, "同一条诊断在投影后仍是同一身份")
    }

    /// ②：悬浮那句说明 = 检查器的文案 + 位置（不许在视图里另编一句）。
    func testHoverTextComesFromLinterMessage() {
        let sql = "SELECT 1 /* 注释没结束"
        let diagnostics = SQLLinter(databaseType: .postgresql).analyze(sql)
        let marks = DiagnosticMarks.project(diagnostics, textLength: (sql as NSString).length)
        guard let mark = marks.first else { return XCTFail("应有一条诊断") }

        XCTAssertTrue(mark.hoverText.contains(mark.message))
        XCTAssertTrue(mark.hoverText.contains(mark.locationDescription))
        XCTAssertTrue(mark.hoverText.contains("第 1 行"), "位置要写成人话：\(mark.hoverText)")
    }

    /// ①：越界的诊断**丢掉**，而挪到别处（挪位置会把标记画到无关字符上）。
    func testOutOfBoundsDiagnosticsAreDropped() {
        let diagnostic = SQLDiagnostic(
            severity: .error,
            message: "越界",
            line: 9,
            column: 9,
            utf16Location: 40,
            utf16Length: 3
        )
        XCTAssertTrue(DiagnosticMarks.project([diagnostic], textLength: 10).isEmpty)
        XCTAssertTrue(DiagnosticMarks.project([diagnostic], textLength: 0).isEmpty)
        XCTAssertTrue(DiagnosticMarks.project([], textLength: 100).isEmpty)
    }

    /// ①：零长度按 1 个字符画；跨过文末的截到文末（否则 `NSRange` 越界 ⇒ 画不出来）。
    func testZeroAndOverrunLengthsAreClamped() {
        let zero = SQLDiagnostic(severity: .warning, message: "零长", line: 1, column: 1, utf16Location: 2, utf16Length: 0)
        let overrun = SQLDiagnostic(severity: .error, message: "越过文末", line: 1, column: 9, utf16Location: 8, utf16Length: 50)

        let marks = DiagnosticMarks.project([zero, overrun], textLength: 10)
        XCTAssertEqual(marks.count, 2)
        XCTAssertEqual(marks[0].length, 1)
        XCTAssertEqual(marks[1].location, 8)
        XCTAssertEqual(marks[1].length, 2, "8 + 50 截到文本长度 10")
    }

    /// ②：命中——落在范围内给那条说明，落在范围外给 nil（不许"模糊命中"）。
    func testHitTestOnlyInsideRange() {
        let sql = "SELECT 'abc"
        let marks = DiagnosticMarks.project(
            SQLLinter(databaseType: .postgresql).analyze(sql),
            textLength: (sql as NSString).length
        )
        guard let mark = marks.first else { return XCTFail("应有一条诊断") }

        XCTAssertEqual(DiagnosticMarks.mark(at: mark.location, in: marks)?.id, mark.id)
        XCTAssertEqual(DiagnosticMarks.mark(at: mark.location + mark.length - 1, in: marks)?.id, mark.id)
        XCTAssertNil(DiagnosticMarks.mark(at: mark.location + mark.length, in: marks), "右端是开区间")
        XCTAssertNil(DiagnosticMarks.mark(at: 0, in: marks), "行首不在标记里")
    }

    /// ②：重叠时取**最窄**的那条（宽的那条是一句泛话），同样窄时错误优先。
    func testOverlappingMarksPreferNarrowestThenError() {
        let wide = SQLDiagnostic(severity: .warning, message: "整段", line: 1, column: 1, utf16Location: 0, utf16Length: 20)
        let narrow = SQLDiagnostic(severity: .warning, message: "局部", line: 1, column: 5, utf16Location: 4, utf16Length: 3)
        let narrowError = SQLDiagnostic(severity: .error, message: "局部错误", line: 1, column: 5, utf16Location: 4, utf16Length: 3)

        let two = DiagnosticMarks.project([wide, narrow], textLength: 30)
        XCTAssertEqual(DiagnosticMarks.mark(at: 5, in: two)?.message, "局部")
        XCTAssertEqual(DiagnosticMarks.mark(at: 15, in: two)?.message, "整段")

        let three = DiagnosticMarks.project([wide, narrow, narrowError], textLength: 30)
        XCTAssertEqual(DiagnosticMarks.mark(at: 5, in: three)?.severity, .error)
        XCTAssertEqual(DiagnosticMarks.mark(at: 5, in: three)?.message, "局部错误")
    }

    /// ④：无诊断 ⇒ 空投影（编辑器据此清掉旧下划线，不留残留）。
    func testNoDiagnosticsLeavesNothingBehind() {
        let sql = "SELECT 1;"
        let diagnostics = SQLLinter(databaseType: .postgresql).analyze(sql)
        XCTAssertTrue(diagnostics.isEmpty, "前提：这段 SQL 是干净的")
        XCTAssertTrue(DiagnosticMarks.project(diagnostics, textLength: (sql as NSString).length).isEmpty)
    }

    /// 同一输入两次投影逐元素相同（顺序确定，不靠字典遍历序）。
    func testProjectionIsDeterministic() {
        let diagnostics = [
            SQLDiagnostic(severity: .warning, message: "B", line: 1, column: 1, utf16Location: 5, utf16Length: 2),
            SQLDiagnostic(severity: .error, message: "A", line: 1, column: 1, utf16Location: 5, utf16Length: 2),
            SQLDiagnostic(severity: .error, message: "C", line: 1, column: 1, utf16Location: 1, utf16Length: 1)
        ]
        let first = DiagnosticMarks.project(diagnostics, textLength: 40)
        let second = DiagnosticMarks.project(diagnostics.shuffled(), textLength: 40)
        XCTAssertEqual(first, second, "顺序与输入顺序无关")
        XCTAssertEqual(first.map(\.message), ["C", "A", "B"])
    }

    /// 同范围同文案的重复结论只画一条。
    func testDuplicateConclusionsAreMerged() {
        let diagnostics = [
            SQLDiagnostic(severity: .error, message: "重复", line: 1, column: 1, utf16Location: 3, utf16Length: 2),
            SQLDiagnostic(severity: .error, message: "重复", line: 1, column: 1, utf16Location: 3, utf16Length: 2)
        ]
        XCTAssertEqual(DiagnosticMarks.project(diagnostics, textLength: 20).count, 1)
    }
}
