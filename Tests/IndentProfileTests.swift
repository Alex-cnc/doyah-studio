import XCTest
@testable import DoyahCore

/// 缩进口径（`FR-STD-WS-EDIT-022`）：打开文件时**按内容**判定软 / 硬 tab 与宽度，不靠扩展名猜。
///
/// ## 判据为什么钉在这一层
///
/// 「这份文件怎么缩进」是一件事的两种说法：判错了，状态栏显示错的、按 Tab 插错的、
/// 回车继承错的 —— 三处都错，而**每一处单看都像正常工作**（这就是为什么它得有一条自己的判据）。
/// 所以这里钉的是三条地面：
///
/// · **证据从内容里数**（证据行的定义、空白行不算、证据不足两行不猜）；
/// · **宽度从增量里取**（相邻证据行「更深一级」的众数），没有增量才退回绝对缩进的最小公分母；
/// · **口径可以被用户改，且改过的不被重新检测冲掉**（`chosen` 是粘的）。
///
/// 源树那一半（`testSource…` 几条）判「视图真的用了它」：核心层判据全绿而视图没人用，
/// 等于这件功能在做的东西只有测试看得见。
final class IndentProfileTests: XCTestCase {

    // MARK: - ① 软 tab 与宽度

    /// 4 空格 + 两级嵌套：增量两次都是 4 ⇒ 宽度 4（不是取绝对缩进里的最小值 4 那种巧合）。
    func testDetectsFourSpaces() {
        let text = """
        func a() {
            if x {
                return
            }
        }
        """
        let profile = IndentProfile.detect(in: text)
        XCTAssertEqual(profile.style, .spaces)
        XCTAssertEqual(profile.width, 4)
        XCTAssertEqual(profile.origin, .detected)
        XCTAssertEqual(profile.evidenceLines, 3, "三行有前导空白：4 格 / 8 格 / 4 格")
        XCTAssertEqual(profile.conflictingLines, 0)
        XCTAssertEqual(profile.unit, "    ")
    }

    /// 2 空格（PEP 8 之外的那一半现实）：同样结构、增量是 2 ⇒ 宽度 2，不是「默认 4」。
    func testDetectsTwoSpaces() {
        let text = """
        def a():
          if x:
            return 1
          return 2
        """
        let profile = IndentProfile.detect(in: text)
        XCTAssertEqual(profile.style, .spaces)
        XCTAssertEqual(profile.width, 2)
        XCTAssertEqual(profile.unit, "  ")
    }

    /// 8 空格：增量是 8 ⇒ 宽度 8（不许被「常规档 4」压回去）。
    func testDetectsEightSpaces() {
        let text = """
        class A:
                def b(self):
                        pass
        """
        let profile = IndentProfile.detect(in: text)
        XCTAssertEqual(profile.width, 8)
    }

    /// 整份文件只在一个深度上（没有增量证据）⇒ 退回绝对缩进：全是 4 ⇒ 4。
    func testSingleDepthFallsBackToAbsoluteIndent() {
        let text = "    a\n    b\n"
        let profile = IndentProfile.detect(in: text)
        XCTAssertEqual(profile.style, .spaces)
        XCTAssertEqual(profile.width, 4)
        XCTAssertEqual(profile.evidenceLines, 2)
    }

    /// 缩进对不齐（一行 5、一行 3，没有增量、公分母是 1）⇒ **不猜**，用缺省 4。
    func testRaggedIndentUsesDefaultWidth() {
        let text = "     a\n   b\n"
        let profile = IndentProfile.detect(in: text)
        XCTAssertEqual(profile.style, .spaces)
        XCTAssertEqual(profile.width, IndentProfile.defaultWidth, "缩进对不齐时不许硬造一个宽度")
    }

    /// 12 / 24 这种「一级 12 格」（少见但真有人这么写）⇒ 取能整除它的常规档 4。
    func testMultipleOfEightMapsToRegularWidth() {
        let text = "            a\n                        b\n"
        let profile = IndentProfile.detect(in: text)
        XCTAssertEqual(profile.width, 4)
    }

    // MARK: - ② 增量并列

    /// 增量 4 与 8 各一次：8 = 两级 4 ⇒ 取 4（不是取大的那个）。
    func testTiedIncrementsPreferTheDivisor() {
        let text = "a\n    b\n    c\n            d\n"
        let profile = IndentProfile.detect(in: text)
        XCTAssertEqual(profile.width, 4)
    }

    /// 增量 2 与 4 各一次：4 = 两级 2 ⇒ 取 2。
    func testTiedIncrementsPreferTwoWhenFourIsTwoLevels() {
        let text = "a\n  b\n  c\n      d\n"
        let profile = IndentProfile.detect(in: text)
        XCTAssertEqual(profile.width, 2)
    }

    /// 增量 4 与 6 各一次：谁也整除不了谁（真混排）⇒ 取**小的一档**（少猜一半），不是取大的。
    func testTiedIncrementsWithNoDivisorPreferSmaller() {
        let text = "a\n    b\n    c\n          d\n"
        let profile = IndentProfile.detect(in: text)
        XCTAssertEqual(profile.width, 4)
    }

    // MARK: - ③ 硬 tab

    /// 全 tab ⇒ 制表符；宽度不可从内容推出 ⇒ 缺省 4；单位就是一个 `\t`（不是 4 个空格）。
    func testDetectsTabs() {
        let text = "\tfunc a() {\n\t\treturn\n\t}\n"
        let profile = IndentProfile.detect(in: text)
        XCTAssertEqual(profile.style, .tabs)
        XCTAssertEqual(profile.width, IndentProfile.defaultWidth)
        XCTAssertEqual(profile.origin, .detected)
        XCTAssertEqual(profile.unit, "\t")
    }

    /// 混用：tab 多数 + 一行空格 ⇒ 判 tab，但**少数派行数如实记下**（不假装干净）。
    func testMixedFileReportsConflictingLines() {
        let text = "\tfoo\n\tbar\n    baz\n"
        let profile = IndentProfile.detect(in: text)
        XCTAssertEqual(profile.style, .tabs)
        XCTAssertEqual(profile.conflictingLines, 1)
        XCTAssertEqual(profile.evidenceLines, 3)
    }

    /// 并列（各一行）⇒ 取空格（保守的一侧），并把「有一种不一致」记下来。
    func testTieBetweenTabsAndSpacesStaysOnSpaces() {
        let text = "\tfoo\n    bar\n"
        let profile = IndentProfile.detect(in: text)
        XCTAssertEqual(profile.style, .spaces)
        XCTAssertEqual(profile.width, 4, "只有一行空格缩进（4 格）⇒ 绝对缩进给 4")
        XCTAssertEqual(profile.conflictingLines, 1)
    }

    // MARK: - ④ 证据不足不猜

    /// 空文件 / 全顶格 ⇒ `fallback`（状态栏据此说「按缺省」，不冒充「按内容判定」）。
    func testEmptyAndFlatFilesFallBack() {
        for text in ["", "a\nb\nc\n"] {
            let profile = IndentProfile.detect(in: text)
            XCTAssertEqual(profile.origin, .fallback, "证据 0 行不该判成 detected")
            XCTAssertEqual(profile.style, .spaces)
            XCTAssertEqual(profile.width, IndentProfile.defaultWidth)
            XCTAssertEqual(profile.evidenceLines, 0)
        }
    }

    /// 只缩进过一行（证据 1 行）⇒ 同样不猜。
    func testSingleIndentedLineIsNotEnoughEvidence() {
        let profile = IndentProfile.detect(in: "  foo\nbar\n")
        XCTAssertEqual(profile.origin, .fallback)
        XCTAssertEqual(profile.evidenceLines, 1)
    }

    /// 只有空白的行不算证据（复制粘贴留下的尾随空白最常见），别让它们把「证据不足」顶成「够了」。
    func testWhitespaceOnlyLinesAreNotEvidence() {
        let profile = IndentProfile.detect(in: "\n   \n\t\t\n  foo\n  bar\n")
        XCTAssertEqual(profile.evidenceLines, 2, "两行空白行不算证据")
        XCTAssertEqual(profile.origin, .detected)
        XCTAssertEqual(profile.width, 2)
    }

    // MARK: - ⑤ 用户改过的口径是粘的

    /// 用户改成硬 tab ⇒ 记 `chosen`；此后再检测一次**不许**把它改回空格。
    func testChosenProfileSurvivesRedetection() {
        let detected = IndentProfile.detect(in: "    a\n        b\n")
        XCTAssertEqual(detected.origin, .detected)
        let chosen = detected.choosing(style: .tabs, width: 8)
        XCTAssertEqual(chosen.origin, .chosen)
        XCTAssertEqual(chosen.style, .tabs)
        XCTAssertEqual(chosen.width, 8)
        XCTAssertEqual(chosen.adopting(IndentProfile.detect(in: "\tfoo\n\t\tbar\n")), chosen,
                       "用户选过的口径不许被重新检测冲掉")
    }

    /// 机器判出来的那一档**会**被重新检测覆盖（换了文件就是另一份口径）。
    func testDetectedProfileIsReplacedByNewDetection() {
        let first = IndentProfile.detect(in: "    a\n        b\n")
        let second = IndentProfile.detect(in: "\tfoo\n\t\tbar\n")
        XCTAssertEqual(first.adopting(second), second)
    }

    /// 宽度是给人看的：越界一律夹回 `1...8`（不是拒、也不是原样留着）。
    func testWidthIsClamped() {
        XCTAssertEqual(IndentProfile(style: .spaces, width: 0).width, 1)
        XCTAssertEqual(IndentProfile(style: .spaces, width: 99).width, 8)
        XCTAssertEqual(IndentProfile(style: .spaces, width: 4).choosing(width: 3).width, 3)
        XCTAssertEqual(IndentProfile.fallback.width, IndentProfile.defaultWidth)
    }

    /// 纯函数：同一份文本连判两次逐字相同（不读盘、不读时钟、不读语言）。
    func testDetectionIsDeterministic() {
        let text = "def a():\n  if x:\n    return 1\n"
        XCTAssertEqual(IndentProfile.detect(in: text), IndentProfile.detect(in: text))
    }

    // MARK: - ⑥ 打开文件即带上口径（页签侧）

    /// 打开一个文件 = 已经带上这份内容的判定结果（状态栏与编辑器读的是同一个值）。
    func testOpeningTabCarriesDetection() {
        let opened = WorkspaceTabSet.opening(path: "/ws/demo.py",
                                             in: [.home(title: "Home")],
                                             content: "def a():\n  if x:\n    return 1\n")
        let tab = try! XCTUnwrap(opened.tabs.last)
        XCTAssertEqual(tab.indent.style, .spaces)
        XCTAssertEqual(tab.indent.width, 2)
        XCTAssertEqual(tab.indent.origin, .detected)
    }

    /// 空文件打开 ⇒ 缺省口径（页签上也一样，不因为「打开过」就变成 detected）。
    func testOpeningBlankTabKeepsFallback() {
        let opened = WorkspaceTabSet.opening(path: "/ws/blank.txt",
                                             in: [.home(title: "Home")],
                                             content: "")
        let tab = try! XCTUnwrap(opened.tabs.last)
        XCTAssertEqual(tab.indent.origin, .fallback)
        XCTAssertEqual(tab.indent.unit, "    ")
    }

    // MARK: - ⑦ 源树：核心层的东西视图真的在用

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let url = root.appendingPathComponent(relative)
        let body = try String(contentsOf: url, encoding: .utf8)
        XCTAssertGreaterThan(body.count, 3_000, "\(relative) 读到的内容太短，扫描面可疑")
        return body
    }

    /// 判定只看内容：`detect` 的入参只有文本，Core 里不许出现「按扩展名猜缩进」这种写法。
    func testDetectionNeverLooksAtPathOrExtension() throws {
        let body = try text("Core/IndentProfile.swift")
        XCTAssertTrue(body.contains("public static func detect(in text: String) -> IndentProfile"),
                      "detect 只许接文本（不许把路径 / 扩展名塞进来）")
        XCTAssertFalse(body.contains("pathExtension"), "缩进口径不许按扩展名猜")
        XCTAssertFalse(body.contains("TextLanguage"), "缩进口径不许按语言猜（那是扩展名的另一张皮）")
    }

    /// 页签上的口径由**打开那一刻**算：`WorkspaceTab.file` 是唯一入口。
    func testTabFileInitialisesIndentFromContent() throws {
        let body = try text("Core/WorkspaceTab.swift")
        XCTAssertTrue(body.contains("indent: IndentProfile.detect(in: content)"),
                      "打开文件的唯一入口必须带上按内容判定的口径")
        XCTAssertTrue(body.contains("public var indent: IndentProfile"),
                      "页签上要有口径这一格（状态栏与编辑器读同一份）")
    }

    /// 编辑器：Tab 真的按口径插单位，回车 / 粘贴真的把单位传给了 `AutoIndent`。
    func testEditorUsesProfileForTabAndAutoIndent() throws {
        let body = try text("App/Views/CodeEditorView.swift")
        for anchor in [
            "var indentUnit: String = IndentProfile.fallback.unit",
            "func insertIndentUnit()",
            "AutoIndent.newline(in: string, selection: selectedRange(), indentUnit: indentUnit)",
            "AutoIndent.paste(clip, into: string, selection: selectedRange(), indentUnit: indentUnit)"
        ] {
            XCTAssertTrue(body.contains(anchor), "编辑器缺少缩进口径的接线锚点：\(anchor)")
        }
        // 按 Tab 必须真的落到口径上：这一段三个动作缺一不可（灰字优先 / 插单位 / 不交还系统）。
        XCTAssertTrue(
            body.contains("override func insertTab(_ sender: Any?) {\n        if acceptGhost() { return }\n        insertIndentUnit()\n    }"),
            "Tab 的三个动作顺序：有灰字先接受，否则按口径插一格"
        )
        // 反向：交还 `super.insertTab` 等于把口径架空（系统那套按制表位走，不看这份文件的写法）。
        XCTAssertFalse(body.contains("super.insertTab(sender)"), "Tab 不许交还系统")
    }

    /// 状态栏：菜单上的每一次改动都落到 `WorkspaceTabsModel.chooseIndent` 一个入口。
    func testStatusBarMenuWritesThroughOneEntry() throws {
        let area = try text("App/Views/WorkspaceAreaView.swift")
        XCTAssertTrue(area.contains("tabs.chooseIndent(tabID: tab.id"), "状态栏缺少改口径的入口锚点")
        XCTAssertTrue(area.contains("tabs.redetectIndent(tabID: tab.id)"), "状态栏缺少「按内容重新判定」的入口锚点")
        let model = try text("App/WorkspaceTabsModel.swift")
        XCTAssertTrue(model.contains("func chooseIndent(tabID: UUID"), "改口径的唯一入口住在页签模型里")
        XCTAssertTrue(model.contains("func redetectIndent(tabID: UUID"), "重新检测的入口同样只有一处")
    }
}
