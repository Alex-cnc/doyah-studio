import XCTest
@testable import DoyahCore

/// 代码折叠（`FR-STD-WS-EDIT-017`）：区域怎么算、状态怎么记、折起来藏哪几行。
///
/// ## 为什么钉在这三条地面
///
/// · **区域从内容算**：字符串 / 注释里的花括号不算、单行块不算、没配上的不猜 ——
///   这三处错了，症状都不是崩溃，而是「折起来藏错了东西」（最难查的一类）；
/// · **状态按锚记、不按行号**：在文件开头加一行注释就把所有折叠挪一格，是这套机制
///   最容易犯的错；本文件里有三例专治它（上方加行仍在 / 首行改了如实丢 / 块删了不残留）；
/// · **折起来藏的是 `start+1 … end`**：首行（函数签名 / `if` 那一行）必须留着 ——
///   藏掉首行等于「折完认不出这是什么」。
final class CodeFoldingTests: XCTestCase {

    // MARK: - 夹具

    private func swiftText() -> String {
        [
            "import Foundation",           // 1
            "",                            // 2
            "struct A {",                  // 3
            "    func run() {",            // 4
            "        let x = 1",           // 5
            "        print(x)",            // 6
            "    }",                       // 7
            "}",                           // 8
            ""                             // 9
        ].joined(separator: "\n")
    }

    private func makeProjection(_ text: String, _ language: TextLanguage) -> FoldProjection {
        CodeFolding.projection(in: text, language: language)
    }

    // MARK: - ① 花括号块

    /// 一个函数体 = 一段区域：首行是开了 `{` 的那一行，尾行是闭合行。
    func testBraceRegionCoversBlock() {
        let text = swiftText()
        let projection = makeProjection(text, .swift)
        XCTAssertEqual(projection.regions.count, 2, "struct 一层 + func 一层，共两段")
        XCTAssertEqual(projection.regions[0].startLine, 3, "外层从 `struct A {` 起")
        XCTAssertEqual(projection.regions[0].endLine, 8)
        XCTAssertEqual(projection.regions[1].startLine, 4, "内层从 `func run() {` 起")
        XCTAssertEqual(projection.regions[1].endLine, 7)
        XCTAssertEqual(projection.regions[0].kind, .block)
        XCTAssertEqual(projection.regions[0].hiddenLineCount, 5, "3…8 这段折起来藏 4…8 —— 首行留着，共 5 行")
    }

    /// 嵌套：外层折起来时，内层的每一行都跟着藏（`hiddenLines` 是并集）。
    func testNestedFoldedOuterHidesInner() {
        let text = swiftText()
        let projection = makeProjection(text, .swift)
        let outer = projection.regions[0]
        let state = FoldState().toggling(line: outer.startLine, in: projection)
        let hidden = state.hiddenLines(in: projection)
        XCTAssertEqual(hidden, [4, 5, 6, 7, 8], "外层折起来 ⇒ 藏 4…8；首行 3 留着")
        XCTAssertFalse(hidden.contains(3), "首行（`struct A {`）不许藏")
        XCTAssertFalse(hidden.contains(1), "块外的行不许受影响")
    }

    /// 字符串与注释里的花括号**不开块**（掩码来自词法器，与着色同一份切分）。
    func testBracesInStringsAndCommentsDoNotOpenBlocks() {
        let text = [
            "let a = \"{ not a block\"",   // 1 字符串里的 `{`
            "// } 注释里的右花括号",         // 2 注释里的 `}`
            "if x {",                       // 3
            "    print(1)",                 // 4
            "}"                             // 5
        ].joined(separator: "\n")
        let regions = makeProjection(text, .swift).regions
        XCTAssertEqual(regions.count, 1, "只有第 3 行那一块；字符串 / 注释里的括号不算")
        XCTAssertEqual(regions[0].startLine, 3)
        XCTAssertEqual(regions[0].endLine, 5)
    }

    /// 开闭在同一行 ⇒ 不是区域（`{ return }` 折起来没有意义，还会把标记画满一屏）。
    func testSingleLineBlockIsNotFolded() {
        let text = [
            "func a() { return }",   // 1
            "func b() {",            // 2
            "    return",            // 3
            "}"                      // 4
        ].joined(separator: "\n")
        let regions = makeProjection(text, .swift).regions
        XCTAssertEqual(regions.map(\.startLine), [2])
    }

    /// 没配上的 `{` 不产出区域，也不崩（不许拿「到文件末尾」当配上了）。
    func testUnbalancedOpenBraceProducesNoRegion() {
        let text = [
            "func a() {",   // 1
            "    let x = 1" // 2
        ].joined(separator: "\n")
        XCTAssertTrue(makeProjection(text, .swift).regions.isEmpty)
    }

    /// 多出来的 `}` 也不会崩（栈空时直接忽略）。
    func testStrayCloseBraceIsIgnored() {
        let text = [
            "}",             // 1
            "func a() {",    // 2
            "    return",    // 3
            "}"              // 4
        ].joined(separator: "\n")
        let regions = makeProjection(text, .swift).regions
        XCTAssertEqual(regions.map(\.startLine), [2])
    }

    // MARK: - ② 缩进块

    /// Python：以 `:` 收尾的行开块，块尾 = 更深缩进的最后一行。
    func testPythonIndentationRegion() {
        let text = [
            "def run(x):",      // 1
            "    if x:",        // 2
            "        return 1", // 3
            "    return 2",     // 4
            "",                 // 5
            "print(1)"          // 6
        ].joined(separator: "\n")
        let regions = makeProjection(text, .python).regions
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].startLine, 1)
        XCTAssertEqual(regions[0].endLine, 4, "空行不算进块，块尾是第 4 行")
        XCTAssertEqual(regions[1].startLine, 2)
        XCTAssertEqual(regions[1].endLine, 3)
    }

    /// YAML：缩进更深即属本块（键名后面没写 `:` 的那种多行值不折）。
    func testYamlIndentationRegion() {
        let text = [
            "server:",        // 1
            "  host: a",      // 2
            "  port: 1",      // 3
            "other: 2"        // 4
        ].joined(separator: "\n")
        let regions = makeProjection(text, .yaml).regions
        XCTAssertEqual(regions.map(\.startLine), [1])
        XCTAssertEqual(regions[0].endLine, 3)
    }

    /// 行尾的 `:` 在**字符串里** ⇒ 不开块（`print(\"x:\")` 不该成为折叠头）。
    func testColonInsideStringDoesNotOpenIndentedBlock() {
        let text = [
            "print(\"a:\")",     // 1
            "    weird",        // 2
            "b = 1"             // 3
        ].joined(separator: "\n")
        XCTAssertTrue(makeProjection(text, .python).regions.isEmpty)
    }

    // MARK: - ③ 区域标记

    /// `#region` … `#endregion` 成对折；嵌套两层各一段。
    func testRegionMarkersPair() {
        let text = [
            "// #region outer",   // 1
            "let a = 1",          // 2
            "// #region inner",   // 3
            "let b = 2",          // 4
            "// #endregion",      // 5
            "// #endregion"       // 6
        ].joined(separator: "\n")
        let markers = makeProjection(text, .swift).regions.filter { $0.kind == .marker }
        XCTAssertEqual(markers.count, 2)
        XCTAssertEqual(markers[0].startLine, 1)
        XCTAssertEqual(markers[0].endLine, 6)
        XCTAssertEqual(markers[1].startLine, 3)
        XCTAssertEqual(markers[1].endLine, 5)
    }

    /// 没配上的 `#region` 不产出区域。
    func testUnclosedRegionMarkerIgnored() {
        let text = ["#region a", "let x = 1"].joined(separator: "\n")
        XCTAssertTrue(makeProjection(text, .swift).regions.filter { $0.kind == .marker }.isEmpty)
    }

    /// 注释里只是**提到** region 两个字，不开块（判定取行首第一个词，不是整行包含）。
    func testMentioningRegionInProseDoesNotOpenBlock() {
        let text = [
            "// 这一段是 region 相关的处理",   // 1
            "let x = 1",                       // 2
            "// #endregion"                    // 3
        ].joined(separator: "\n")
        XCTAssertTrue(makeProjection(text, .swift).regions.isEmpty)
    }

    // MARK: - ④ 规则从登记表来

    /// 规则的来源是**语言登记表里的数据**，不是核心代码里的身份分支。
    func testFoldRuleComesFromRegistryData() {
        XCTAssertEqual(CodeFolding.rule(for: .swift), .braces)
        XCTAssertEqual(CodeFolding.rule(for: .sql), .braces)
        XCTAssertEqual(CodeFolding.rule(for: .python), .indentation)
        XCTAssertEqual(CodeFolding.rule(for: .yaml), .indentation)
        XCTAssertEqual(CodeFolding.rule(for: .html), .none, "HTML 要按标签配对，不是花括号")
        XCTAssertEqual(CodeFolding.rule(for: .markdown), .none)
        XCTAssertEqual(CodeFolding.rule(for: .plainText), .none)
        // 同一份定义两条路取到的必须一致（与 `formats` 同一条纪律）。
        XCTAssertEqual(
            CodeLanguageRegistry.all.first { $0.language == .python }?.fold,
            CodeLanguageRegistry.definition(of: .python).fold
        )
    }

    /// 没有块级规则的语言：一个区域都不给（纯文本 / Markdown / HTML）。
    func testLanguagesWithoutBlockRuleProduceNoRegions() {
        let text = ["fn a() {", "  return", "}"].joined(separator: "\n")
        XCTAssertTrue(makeProjection(text, .plainText).regions.isEmpty)
        XCTAssertTrue(makeProjection(text, .markdown).regions.isEmpty)
        XCTAssertTrue(makeProjection(text, .html).regions.isEmpty)
        XCTAssertTrue(CodeFolding.projection(in: "", language: .swift).regions.isEmpty)
    }

    // MARK: - ⑤ 状态：折叠 / 展开 / 记忆

    /// 标记表跟着状态走：折起来是 `isFolded = true`，再折一次回来。
    func testMarkersReflectFoldStateAndToggleTwiceRestores() {
        let text = swiftText()
        let projection = makeProjection(text, .swift)
        var state = FoldState()
        XCTAssertEqual(state.markers(in: projection).map(\.isFolded), [false, false])

        state = state.toggling(line: 4, in: projection)
        XCTAssertEqual(state.markers(in: projection).map(\.isFolded), [false, true])
        XCTAssertEqual(state.count, 1)

        state = state.toggling(line: 4, in: projection)
        XCTAssertEqual(state.markers(in: projection).map(\.isFolded), [false, false])
        XCTAssertTrue(state.isEmpty)
    }

    /// 折的不是区域首行 ⇒ 原样返回（不猜用户想折哪一段）。
    func testTogglingNonHeaderLineDoesNothing() {
        let projection = makeProjection(swiftText(), .swift)
        let state = FoldState().toggling(line: 5, in: projection)
        XCTAssertTrue(state.isEmpty)
        XCTAssertEqual(state, FoldState())
    }

    /// 同一份文件里两段首行原文相同的区域，**各自独立**（锚带序号）。
    func testSameSignatureRegionsAreIndependent() {
        let text = [
            "func a() {",   // 1
            "    run()",    // 2
            "}",            // 3
            "func a() {",   // 4
            "    run()",    // 5
            "}"             // 6
        ].joined(separator: "\n")
        let projection = makeProjection(text, .swift)
        XCTAssertEqual(projection.regions.count, 2)
        XCTAssertNotEqual(projection.anchors[0], projection.anchors[1], "同签名靠序号区分")

        let state = FoldState().toggling(line: 4, in: projection)
        XCTAssertEqual(state.markers(in: projection).map(\.isFolded), [false, true],
                       "折第 4 行那一段，第 1 行那段不许跟着折")
    }

    // MARK: - ⑥ 藏哪几行 / 映到字符范围

    /// 折起来藏 `start+1 … end`，且**合并成连续段**（视图据此一次设一段样式）。
    func testHiddenRangesExcludeHeaderAndMergeIntoRuns() {
        let text = swiftText()
        let projection = makeProjection(text, .swift)
        let state = FoldState().toggling(line: 3, in: projection)
        let ranges = state.hiddenRanges(in: projection, text: text)
        XCTAssertEqual(ranges.count, 1, "3…8 里藏 4…8，是连续的一段")

        let ns = text as NSString
        let hidden = ns.substring(with: ranges[0])
        XCTAssertTrue(hidden.hasPrefix("    func run() {"), "从第 4 行起")
        XCTAssertTrue(hidden.hasSuffix("}\n"), "到第 8 行（闭合行）止；行的范围含它自己的行终止符")
        XCTAssertFalse(hidden.contains("struct A {"), "首行不许进隐藏段")

        // 藏起来的是**显示**，字还在：文本一个字都没少（需求 ④）。
        XCTAssertEqual(ns.length, (swiftText() as NSString).length)
    }

    /// 两段不相邻的折叠 ⇒ 两个 `NSRange`（不合成一段，否则会把中间折没折的行也藏了）。
    func testDisjointFoldsProduceSeparateRanges() {
        let text = [
            "func a() {",   // 1
            "    x()",      // 2
            "}",            // 3
            "let mid = 1",  // 4
            "func b() {",   // 5
            "    y()",      // 6
            "}"             // 7
        ].joined(separator: "\n")
        let projection = makeProjection(text, .swift)
        var state = FoldState()
        state = state.toggling(line: 1, in: projection)
        state = state.toggling(line: 5, in: projection)
        let ranges = state.hiddenRanges(in: projection, text: text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(state.hiddenLines(in: projection), [2, 3, 6, 7])
    }

    /// 行号 → 字符范围走的是 `CodeLines`（`\r\n` 文档里不能少数一个字节）。
    func testHiddenRangesUseCodeLinesOffsets() {
        let text = "func a() {\r\n    x()\r\n}\r\n"
        let projection = makeProjection(text, .swift)
        XCTAssertEqual(projection.regions.map(\.startLine), [1])
        XCTAssertEqual(projection.regions[0].endLine, 3)
        let state = FoldState().toggling(line: 1, in: projection)
        let ranges = state.hiddenRanges(in: projection, text: text)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual((text as NSString).substring(with: ranges[0]), "    x()\r\n}\r\n")
    }

    // MARK: - ⑦ 编辑之后：按锚对账

    /// 在块**上方**加行 ⇒ 折叠还在（锚不看行号）。
    func testFoldSurvivesEditsAboveBlock() {
        let text = swiftText()
        let projection = makeProjection(text, .swift)
        let state = FoldState().toggling(line: 4, in: projection)

        let edited = "// 新加的注释\n// 再加一行\n" + text
        let newProjection = makeProjection(edited, .swift)
        let reconciled = state.reconciled(with: newProjection)
        XCTAssertEqual(reconciled.count, 1, "首行原文没变 ⇒ 折叠必须还在")
        XCTAssertEqual(reconciled.markers(in: newProjection).map(\.isFolded), [false, true],
                       "行号整体下移两行，标记跟着挪到新的第 6 行")
        XCTAssertEqual(newProjection.regions[1].startLine, 6)
    }

    /// 首行被改（函数改名）⇒ 那一条如实丢掉，不猜「原来是哪一段」。
    func testFoldDroppedWhenHeaderChanges() {
        let text = swiftText()
        let projection = makeProjection(text, .swift)
        let state = FoldState().toggling(line: 4, in: projection)

        let edited = text.replacingOccurrences(of: "func run() {", with: "func walk() {")
        let newProjection = makeProjection(edited, .swift)
        XCTAssertEqual(state.reconciled(with: newProjection).count, 0)
    }

    /// 块被删掉（首行也没了）⇒ 不残留，且**不会**在别处冒出一个折着的块。
    func testFoldDroppedWhenBlockRemoved() {
        let text = swiftText()
        let projection = makeProjection(text, .swift)
        let state = FoldState().toggling(line: 4, in: projection)
        let edited = "import Foundation\n"
        let newProjection = makeProjection(edited, .swift)
        XCTAssertEqual(state.reconciled(with: newProjection).count, 0)
        XCTAssertEqual(newProjection.regions.count, 0)
    }

    /// 没变的文档对账后**等于自己**（不制造无意义的状态变更，避免视图反复重排）。
    func testReconcileIsIdentityWhenNothingChanged() {
        let text = swiftText()
        let projection = makeProjection(text, .swift)
        let state = FoldState().toggling(line: 3, in: projection)
        XCTAssertEqual(state.reconciled(with: projection), state)
    }

    // MARK: - ⑧ 光标进到折起来的块里

    /// 光标落到被藏起来的行 ⇒ 那一段要展开（否则用户会在看不见的行里打字）。
    func testCaretInsideFoldedRegionExpandsIt() {
        let text = swiftText()
        let projection = makeProjection(text, .swift)
        var state = FoldState()
        state = state.toggling(line: 3, in: projection)
        state = state.toggling(line: 4, in: projection)
        XCTAssertEqual(state.count, 2)

        // 光标落在第 5 行（被外层藏着、也在内层段里）⇒ 两段都该展开。
        let containing = state.foldedRegions(containing: 5, in: projection)
        XCTAssertEqual(containing.count, 2)
        let expanded = state.expanding(containing, in: projection)
        XCTAssertTrue(expanded.isEmpty)
        XCTAssertTrue(expanded.foldedRegions(containing: 5, in: projection).isEmpty)
    }

    /// 光标在**首行**（折起来之后仍然看得见的那一行）⇒ 不算「进到块里」，不展开。
    func testCaretOnHeaderLineDoesNotExpand() {
        let projection = makeProjection(swiftText(), .swift)
        let state = FoldState().toggling(line: 4, in: projection)
        XCTAssertTrue(state.foldedRegions(containing: 4, in: projection).isEmpty)
        XCTAssertEqual(state.foldedRegions(containing: 6, in: projection).map(\.startLine), [4])
    }

    // MARK: - ⑨ 每个文件各记各的（会话内）

    /// 折叠状态是页签上的一个值：两个页签互不影响（同族口径见 `FR-STD-WS-EDIT-022`）。
    func testFoldStateLivesOnTheTabAndIsIndependent() {
        let text = swiftText()
        let first = WorkspaceTab.file(path: "/tmp/a.swift", content: text)
        let second = WorkspaceTab.file(path: "/tmp/b.swift", content: text)
        XCTAssertTrue(first.folds.isEmpty)
        XCTAssertTrue(second.folds.isEmpty, "新打开的页签一律全展开（不是「上次怎么折就怎么折」）")

        let projection = makeProjection(text, .swift)
        var foldedFirst = first
        foldedFirst.folds = foldedFirst.folds.toggling(line: 4, in: projection)
        XCTAssertEqual(foldedFirst.folds.count, 1)
        XCTAssertTrue(second.folds.isEmpty, "另一个页签的状态不许被带着走")
    }

    /// 折起来**不动文本、不动撤销栈**（需求 ④）：判定层只读，状态是值类型。
    func testFoldingIsReadOnlyOverTheText() {
        let text = swiftText()
        let projection = makeProjection(text, .swift)
        let state = FoldState().toggling(line: 3, in: projection)
        _ = state.hiddenRanges(in: projection, text: text)
        // 原文一字未变：判定层没有写入口（`projection` / `FoldState` 都不持文本）。
        XCTAssertEqual(text, swiftText())
        // 而且每次折 / 展都产出**新状态**，旧状态不受影响（值语义 ⇒ 视图拿到的永远是快照）。
        let toggled = state.toggling(line: 3, in: projection)
        XCTAssertEqual(state.count, 1)
        XCTAssertEqual(toggled.count, 0)
    }
}
