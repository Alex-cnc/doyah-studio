import XCTest
@testable import DoyahCore

/// 括号匹配高亮（`FR-STD-WS-EDIT-020`）：光标紧邻括号时，与它配对的那一个同时点亮。
///
/// 判据形态：「给『文本 + 选区』要『亮哪几段 + 什么角色』」。坐标一律 UTF-16
/// （`NSTextView.selectedRange()` 那套）—— `😀(x)` 里那个 `(` 在偏移 **2**、不在 1，
/// 这一类差位是括号高亮最常见的错法，所以单独钉一条。
///
/// 三条角色判据是**分开的**（`matched` / `unmatched` / `truncated`）：把「没配上」与
/// 「太远没扫到」压成一个布尔，界面就只能对小括号说错话。
final class BracketHighlightTests: XCTestCase {

    // MARK: - 小工具

    private func plan(_ text: String, caret: Int) -> BracketHighlightPlan? {
        BracketHighlight.plan(in: text, selection: NSRange(location: caret, length: 0))
    }

    private func spans(_ text: String, caret: Int) -> [NSRange] {
        plan(text, caret: caret)?.spans ?? []
    }

    // MARK: - matched：两个都亮

    func testMatchedPairLightsBothSides() {
        // "func(a)"：`(` 在 4、`)` 在 6；光标在 5（两括号之间）
        let result = plan("func(a)", caret: 5)
        XCTAssertEqual(result?.role, .matched)
        XCTAssertEqual(result?.spans, [NSRange(location: 4, length: 1), NSRange(location: 6, length: 1)])
    }

    func testAnchorsOnClosingBracketToo() {
        // 光标贴在右括号右边（`func(a)|`）—— 左边那个字符就是 `)`，锚它、找左边的 `(`
        let result = plan("func(a)", caret: 7)
        XCTAssertEqual(result?.role, .matched)
        XCTAssertEqual(result?.spans.map(\.location), [4, 6], "两段按位置升序，与「先锚谁」无关")
    }

    func testNestedBracketPicksNearestPair() {
        // "([x])"：`[` 在 1、`]` 在 3；光标 2 ⇒ 取最近那一对，不是外层那对
        let result = plan("([x])", caret: 2)
        XCTAssertEqual(result?.role, .matched)
        XCTAssertEqual(result?.spans.map(\.location), [1, 3])
    }

    // MARK: - 没配上 / 太远

    func testUnmatchedBracketReportsUnmatchedRole() {
        let result = plan("abc(def", caret: 4)
        XCTAssertEqual(result?.role, .unmatched)
        XCTAssertEqual(result?.spans, [NSRange(location: 3, length: 1)], "只亮光标旁这一个")
    }

    func testTooFarIsTruncatedNotUnmatched() {
        // 超过扫描上限（`CodeAutoPairing.scanLimit`）还没配到 ⇒ 角色必须是 `truncated`
        let text = "(" + String(repeating: "a", count: CodeAutoPairing.scanLimit + 50)
        let result = plan(text, caret: 1)
        XCTAssertEqual(result?.role, .truncated, "「太远没扫到」不等于「不匹配」")
        XCTAssertEqual(result?.spans.count, 1)
        XCTAssertNotEqual(result?.role, .unmatched)
    }

    // MARK: - 不该亮的场合

    func testNoBracketNearCaretReturnsNil() {
        XCTAssertNil(plan("abc", caret: 1))
        XCTAssertNil(plan("x", caret: 1))
        XCTAssertNil(plan("", caret: 0))
    }

    func testNonEmptySelectionSuppressesHighlight() {
        // 选中一段 ⇒ 什么都不亮（这时用户在做别的事，亮半个括号只是噪声）
        let text = "func(a)"
        XCTAssertNil(BracketHighlight.plan(in: text, selection: NSRange(location: 5, length: 3)))
        XCTAssertNotNil(BracketHighlight.plan(in: text, selection: NSRange(location: 5, length: 0)))
    }

    // MARK: - 坐标口径

    func testOffsetsAreUTF16WithEmojiBefore() {
        // "😀(x)"：emoji 占 2 个 UTF-16 单元 ⇒ `(` 在 2、`)` 在 4
        let result = plan("😀(x)", caret: 3)
        XCTAssertEqual(result?.role, .matched)
        XCTAssertEqual(result?.spans, [NSRange(location: 2, length: 1), NSRange(location: 4, length: 1)])
    }

    func testFullWidthBracketsMatchToo() {
        // 中文输入法默认上屏全角括号（`FR-EDIT-49` 已按这条配成对，高亮要跟上同一口径）
        let result = plan("（x）", caret: 1)
        XCTAssertEqual(result?.role, .matched)
        XCTAssertEqual(result?.spans.map(\.location), [0, 2])
    }

    // MARK: - 取色只走令牌（不写死颜色）

    /// 三个角色必须各自钉在**具体令牌**上，且互不相同 ——
    /// 写死 RGB 的话这条会红，换主题看不见的毛病就是这么混进去的。
    func testRolesMapToDistinctThemeTokens() {
        for theme in DesignTheme.all {
            XCTAssertEqual(BracketHighlightRole.matched.color(in: theme), AccentFamily.accent.color(in: theme))
            XCTAssertEqual(BracketHighlightRole.unmatched.color(in: theme), StatusTone.danger.color(in: theme))
            XCTAssertEqual(BracketHighlightRole.truncated.color(in: theme), StatusTone.warning.color(in: theme))

            let colors = BracketHighlightRole.allCases.map { $0.color(in: theme) }
            XCTAssertEqual(Set(colors.map { "\($0.light)-\($0.dark)" }).count, colors.count,
                           "三个角色的取值不许撞色（撞了用户分不清「配上了」还是「报错」）")
        }
    }

    func testRoleOpacitiesAreSubduedAndOrdered() {
        for role in BracketHighlightRole.allCases {
            XCTAssertGreaterThan(role.backgroundOpacity, 0, "\(role) 的底色不能是 0（等于没亮）")
            XCTAssertLessThan(role.backgroundOpacity, 0.5, "\(role) 的底色不能盖过文字")
        }
        // 配对比「太远」更实、比「不匹配」浓：三档分明
        XCTAssertGreaterThan(BracketHighlightRole.matched.backgroundOpacity,
                             BracketHighlightRole.unmatched.backgroundOpacity)
        XCTAssertGreaterThan(BracketHighlightRole.unmatched.backgroundOpacity,
                             BracketHighlightRole.truncated.backgroundOpacity)
    }

    // MARK: - 接线判据（源码扫描：Core 有了，界面别掉链子）

    /// 只写 Core 不接界面 =「写好没接线」（本项目反复踩过的坑）。这里钉四件事：
    /// ① 编辑器真的调 Core 的判定；② 涂 / 清只有一个落点；③ 颜色从令牌 + 浓度来；
    /// ④ 选区一动就重算、整篇重涂之后补回来。
    func testEditorWiresBracketHighlight() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/Views/CodeEditorView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("BracketHighlight.plan(in: string, selection: selectedRange())"),
                      "要调 Core 的判定，不许在界面里另写一套")
        XCTAssertTrue(source.contains("func refreshBracketHighlight()"), "涂 / 清要有唯一落点")
        XCTAssertTrue(source.contains("removeAttribute(.backgroundColor, range: range)"),
                      "清场只摘底色（整段重设会把语法色一起抹掉）")
        XCTAssertTrue(source.contains("plan.role.color(in: Theme.designTheme)"), "颜色从令牌来")
        XCTAssertTrue(source.contains("alpha: plan.role.backgroundOpacity"), "浓度从 Core 来")
        XCTAssertTrue(source.contains("textView?.refreshBracketHighlight()"), "选区一变就要重算")
        XCTAssertTrue(source.contains("reapplyBracketHighlight()"), "整篇重涂之后要补回来")
        XCTAssertFalse(source.contains("NSColor(red: 0"), "不许在编辑器里写死括号底色")
    }
}
