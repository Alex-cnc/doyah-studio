import XCTest
@testable import DoyahCore

/// **代码编辑器行号口径**（FR-EDIT-36 的「编辑器行号列」，队列 L-64）。
///
/// 为什么值得单独钉：行号错一位，界面上只是"看着有点怪"，但用户按行号定位（编译器报的行号、
/// 同事说的"看第 137 行"）时会**读错那一行** —— 这类错最难被随手发现，所以逐条写死。
final class CodeLinesTests: XCTestCase {

    // MARK: - 基本形态

    func testEmptyDocumentStillHasAFirstLine() {
        XCTAssertEqual(CodeLines.lineStarts(in: ""), [0], "空文档也是第 1 行（光标能落上去）")
        XCTAssertEqual(CodeLines.count(in: ""), 1)
        XCTAssertEqual(CodeLines.gutterDigits(in: ""), 1)
    }

    func testSingleLineWithoutTerminator() {
        XCTAssertEqual(CodeLines.lineStarts(in: "select 1"), [0])
        XCTAssertEqual(CodeLines.count(in: "select 1"), 1)
    }

    // MARK: - 行终止符（口径来自 NSString.getLineStart，与 AppKit 同源）

    func testLineFeed() {
        XCTAssertEqual(CodeLines.lineStarts(in: "a\nb"), [0, 2])
        XCTAssertEqual(CodeLines.count(in: "a\nb"), 2)
    }

    func testCarriageReturnLineFeedCountsAsOneTerminator() {
        // 红例留档：按 `\n` 切会把它当**一个**终止符（恰好也对），但按 `\r` 切会数成两行 ——
        // 两种手写口径都不对，只有"问一问 AppKit"才对。这里钉的是**结果**：CRLF 是一行结束。
        XCTAssertEqual(CodeLines.lineStarts(in: "a\r\nb"), [0, 3])
    }

    func testLoneCarriageReturnIsATerminator() {
        // 这个是"按 `\n` 切"的口径**必然算错**的例子：老式 Mac 换行（`\r`）没有 `\n`，
        // 手写实现会把两行数成一行，行号从此整体偏 1。
        XCTAssertEqual(CodeLines.lineStarts(in: "a\rb"), [0, 2])
        XCTAssertEqual(CodeLines.count(in: "a\rb"), 2, "`\\r` 也是行终止符（AppKit 认它）")
        XCTAssertEqual(
            "a\rb".components(separatedBy: "\n").count, 1,
            "对照：按 `\\n` 切只有 1 段 —— 这就是不许手写行切分的原因"
        )
    }

    func testUnicodeLineSeparatorsAreTerminators() {
        // `U+2028` / `U+2029` / `U+0085` 都可能从粘贴内容里溜进来（JSON、Word、网页）。
        XCTAssertEqual(CodeLines.lineStarts(in: "a\u{2028}b"), [0, 2])
        XCTAssertEqual(CodeLines.lineStarts(in: "a\u{2029}b"), [0, 2])
        XCTAssertEqual(CodeLines.lineStarts(in: "a\u{0085}b"), [0, 2])
        XCTAssertEqual(
            "a\u{2028}b".components(separatedBy: "\n").count, 1,
            "对照：它们都不含 `\\n` —— 手写实现同样会数成一行"
        )
    }

    // MARK: - 末尾终止符（口径 ②：多一个空行）

    func testTrailingTerminatorAddsAnEmptyLine() {
        // 光标真的能停在末尾那一行上（`NSTextView` 的 extra line fragment）⇒ 那里必须有号，
        // 否则出现"光标在这一行、左边没有行号"的错位。
        XCTAssertEqual(CodeLines.lineStarts(in: "a\n"), [0, 2])
        XCTAssertEqual(CodeLines.count(in: "a\n"), 2)
        XCTAssertEqual(CodeLines.lineStarts(in: "a\nb\n"), [0, 2, 4])
        XCTAssertEqual(CodeLines.count(in: "a\nb\n"), 3)
        XCTAssertEqual(CodeLines.lineStarts(in: "\n"), [0, 1])
        XCTAssertEqual(CodeLines.count(in: "\n\n"), 3)
    }

    func testNoTrailingTerminatorMeansNoExtraLine() {
        XCTAssertEqual(CodeLines.count(in: "a\nb"), 2)
        XCTAssertEqual(CodeLines.count(in: "a\r\nb"), 2)
    }

    // MARK: - 单位 = UTF-16（口径 ①）

    func testOffsetUnitIsUTF16NotCharacter() {
        // emoji 是 2 个 UTF-16 单元 / 1 个字符 —— 按字符数就得到 `[0, 2]`，
        // 而 2 落在那个 emoji 的代理对**中间**，行号列会整体偏。
        XCTAssertEqual(CodeLines.lineStarts(in: "😀\n"), [0, 3], "单位必须是 UTF-16 单元（与 NSRange 一致）")
        XCTAssertEqual(CodeLines.lineStarts(in: "中\n文"), [0, 2], "中文是 1 个单元：中英混排才不会偏")
        XCTAssertEqual(CodeLines.lineStarts(in: "中😀\n文"), [0, 4])
    }

    // MARK: - 列宽

    func testGutterDigitsGrowsAtPowersOfTen() {
        XCTAssertEqual(CodeLines.digits(of: 1), 1)
        XCTAssertEqual(CodeLines.digits(of: 9), 1)
        XCTAssertEqual(CodeLines.digits(of: 10), 2, "第 10 行要多一位 —— 列宽写死就会把数字挤掉")
        XCTAssertEqual(CodeLines.digits(of: 99), 2)
        XCTAssertEqual(CodeLines.digits(of: 100), 3)
        XCTAssertEqual(CodeLines.digits(of: 9999), 4)
        XCTAssertEqual(CodeLines.digits(of: 0), 1, "行数不可能小于 1，传 0 也只给一位（不返回 0 位）")

        let hundredLines = Array(repeating: "x", count: 100).joined(separator: "\n")
        XCTAssertEqual(CodeLines.count(in: hundredLines), 100)
        XCTAssertEqual(CodeLines.gutterDigits(in: hundredLines), 3, "100 行 ⇒ 3 位（末行是第 100 行）")
    }

    // MARK: - 位置 → 行号

    func testLineNumberAtOffsetBoundaries() {
        let text = "a\nbb\n\nccc"   // 4 行：0 / 2 / 5 / 6
        XCTAssertEqual(CodeLines.lineStarts(in: text), [0, 2, 5, 6])

        XCTAssertEqual(CodeLines.lineNumber(at: 0, in: text), 1)
        XCTAssertEqual(CodeLines.lineNumber(at: 1, in: text), 1, "第 1 行的行终止符仍算第 1 行")
        XCTAssertEqual(CodeLines.lineNumber(at: 2, in: text), 2, "行起点就是下一行")
        XCTAssertEqual(CodeLines.lineNumber(at: 4, in: text), 2)
        XCTAssertEqual(CodeLines.lineNumber(at: 5, in: text), 3, "空行自己是一行")
        XCTAssertEqual(CodeLines.lineNumber(at: 6, in: text), 4)
        XCTAssertEqual(CodeLines.lineNumber(at: 9, in: text), 4)
    }

    func testLineNumberClampsOutOfRange() {
        let text = "a\nb"
        XCTAssertEqual(CodeLines.lineNumber(at: -5, in: text), 1, "越界夹到第 1 行（不崩、也不返回 0）")
        XCTAssertEqual(CodeLines.lineNumber(at: 999, in: text), 2, "越界夹到最后一行")
        XCTAssertEqual(CodeLines.lineNumber(at: 0, in: ""), 1, "空文档只有第 1 行")
    }

    func testTrailingEmptyLineIsAddressable() {
        // 视图里"末尾空行"那一格的查询正是 `offset == length` —— 必须答"最后一行"，
        // 否则末尾那格没有号（口径 ② 在位置查询这一侧的对应断言）。
        let text = "a\n"
        XCTAssertEqual(CodeLines.lineNumber(at: text.utf16.count, in: text), 2)
        XCTAssertEqual(CodeLines.lineNumber(at: text.utf16.count, lineStarts: CodeLines.lineStarts(in: text)), 2)
    }

    // MARK: - 二分与线性扫描必须同解（视图每次重绘都走二分）

    func testBinarySearchAgreesWithLinearScanOnALargeDocument() {
        var lines: [String] = []
        for index in 0..<5000 {
            lines.append(index % 7 == 0 ? "// 第 \(index) 行" : "let v\(index) = \(index)")
        }
        let text = lines.joined(separator: "\n")
        let starts = CodeLines.lineStarts(in: text)

        XCTAssertEqual(starts.count, 5000)
        XCTAssertEqual(CodeLines.count(in: text), 5000)
        XCTAssertEqual(CodeLines.gutterDigits(in: text), 4, "5000 行 ⇒ 4 位")

        let utf16 = text as NSString
        for index in stride(from: 0, to: utf16.length, by: 97) {
            let linear = starts.lastIndex(where: { $0 <= index }).map { $0 + 1 } ?? 1
            XCTAssertEqual(
                CodeLines.lineNumber(at: index, lineStarts: starts), linear,
                "二分与线性扫描在第 \(index) 个单元上不一致"
            )
        }
        XCTAssertEqual(
            CodeLines.lineNumber(at: utf16.length, lineStarts: starts), 5000,
            "末尾（无终止符）落在最后一行"
        )
    }

    func testLineStartsAreStrictlyIncreasing() {
        let samples = [
            "", "\n", "a", "a\n", "\n\n\n", "a\r\nb\r\n", "中😀\u{2028}x\ny",
            "let a = 1\r\n// 注释\n\nfunc f() {}\r",
        ]
        for text in samples {
            let starts = CodeLines.lineStarts(in: text)
            XCTAssertFalse(starts.isEmpty, "至少一行：\(text.debugDescription)")
            XCTAssertEqual(starts.first, 0, "第一行从 0 起：\(text.debugDescription)")
            for (previous, next) in zip(starts, starts.dropFirst()) {
                XCTAssertLessThan(previous, next, "行起点必须严格递增：\(text.debugDescription)")
            }
            XCTAssertLessThanOrEqual(
                starts.last ?? 0, (text as NSString).length,
                "行起点不许越过文本末尾：\(text.debugDescription)"
            )
        }
    }

    // MARK: - 行号 → 位置（`range(ofLine:in:)`，队列 L-117：跳到命中行）

    /// 互逆：每一行的范围起点换回行号必须还是那一行；范围里的原文必须真的是那一行。
    func testLineRangeRoundTripsWithLineNumber() {
        let samples = [
            "", "\n", "a", "a\n", "\n\n\n", "a\r\nb\r\n", "中😀\u{2028}x\ny",
            "let a = 1\r\n// 注释\n\nfunc f() {}\r",
        ]
        for text in samples {
            let ns = text as NSString
            let count = CodeLines.count(in: text)
            for line in 1...count {
                guard let range = CodeLines.range(ofLine: line, in: text) else {
                    XCTFail("第 \(line) 行（共 \(count) 行）换不出位置：\(text.debugDescription)")
                    continue
                }
                XCTAssertEqual(CodeLines.lineNumber(at: range.location, in: text), line,
                               "换回位置再换回来必须同号：\(text.debugDescription)")
                XCTAssertLessThanOrEqual(range.location + range.length, ns.length,
                                         "范围不许越过文本末尾")
            }
        }
    }

    /// 越界一律 `nil`：宁可让调用方看见"没有这一行"，也不要夹到别的行上去。
    func testLineRangeReturnsNilWhenOutOfBounds() {
        let text = "a\nb\n"
        XCTAssertNil(CodeLines.range(ofLine: 0, in: text))
        XCTAssertNil(CodeLines.range(ofLine: -3, in: text))
        XCTAssertNil(CodeLines.range(ofLine: CodeLines.count(in: text) + 1, in: text))
        XCTAssertNotNil(CodeLines.range(ofLine: CodeLines.count(in: text), in: text),
                        "最后一行（末尾终止符造出的空行）也算一行")
    }

    /// 覆盖到的原文就是那一行（含行终止符）—— 「跳到命中行」看到的正是这一段。
    func testLineRangeCoversThatLineOnly() {
        let text = "alpha agent\u{2028}beta agent\n"
        let ns = text as NSString
        XCTAssertEqual(ns.substring(with: CodeLines.range(ofLine: 1, in: text)!), "alpha agent\u{2028}")
        XCTAssertEqual(ns.substring(with: CodeLines.range(ofLine: 2, in: text)!), "beta agent\n")
        XCTAssertEqual(ns.substring(with: CodeLines.range(ofLine: 3, in: text)!), "")
    }

    /// 行**内容**范围 = 去掉行终止符的那些行（内容检索按它读原文做摘要）。
    func testContentRangesDropLineTerminators() {
        let samples: [(String, [String])] = [
            ("a\nb\n", ["a", "b", ""]),
            ("a\r\nb\r", ["a", "b", ""]),
            ("alpha agent\u{2028}beta agent\n", ["alpha agent", "beta agent", ""]),
            ("last", ["last"]),
            ("", [""]),
        ]
        for (text, expected) in samples {
            let ns = text as NSString
            let got = CodeLines.contentRanges(in: text).map { ns.substring(with: $0) }
            XCTAssertEqual(got, expected, "\(text.debugDescription) 逐行内容不对")
            XCTAssertEqual(got.count, CodeLines.count(in: text), "内容范围必须与行数一一对应")
        }
    }
}
