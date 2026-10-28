import XCTest
@testable import DoyahCore

/// 撤销步粒度（`FR-STD-WS-EDIT-014`）的**判定层**判据。
///
/// 这一层能机械判的只有两件事（量不出来的那一半如实写在 `Core/UndoGranularity.swift` 的注释里）：
/// 1. **在哪断开** —— 连续键入 / 删除合成一步，其余一次动作一步，且原子动作前后都断开；
/// 2. **这一步叫什么** —— 编辑菜单里「撤销 …」那一行，中英都得有、而且互不相同。
///
/// 反例（各判红一次，见 `.agent/evidence/2026-10-29-EDIT-014.md`）：
/// ① 去掉 `!kind.isAtomic` 这个条件（原子动作也能与同类合并）⇒ 三例红；
/// ② 等长替换那条改成「一律用调用方落点」⇒ 两例红。
final class UndoGranularityTests: XCTestCase {

    // MARK: - 连续输入：一次撤销

    func testFirstEditAlwaysBreaks() {
        var policy = UndoGranularity()
        let decision = policy.decide(.typing)
        XCTAssertTrue(decision.breakBefore, "第一次编辑前面没有可合并的东西，但也要断开一次（同一组里可能有别处的动作）")
        XCTAssertFalse(decision.breakAfter, "键入不是原子动作：后面的键入要能并进这一步")
    }

    func testContinuousTypingMergesIntoOneStep() {
        var policy = UndoGranularity()
        let decisions = (0..<5).map { _ in policy.decide(.typing) }
        XCTAssertEqual(decisions.map(\.breakBefore), [true, false, false, false, false],
                       "一段连续键入必须只断一次 —— 断多了就变成逐字符撤销")
        XCTAssertEqual(decisions.map(\.breakAfter), [false, false, false, false, false])
    }

    func testContinuousDeletingMergesIntoOneStep() {
        var policy = UndoGranularity()
        let decisions = (0..<4).map { _ in policy.decide(.deleting) }
        XCTAssertEqual(decisions.map(\.breakBefore), [true, false, false, false],
                       "连续退格同理：一次撤销删掉一整段，而不是一次一个字符")
    }

    func testSwitchingBetweenTypingAndDeletingBreaks() {
        var policy = UndoGranularity()
        _ = policy.decide(.typing)
        _ = policy.decide(.typing)
        let deleting = policy.decide(.deleting)
        XCTAssertTrue(deleting.breakBefore, "「打了半句又开始删」是两件事，不能合成一步")
        let typingAgain = policy.decide(.typing)
        XCTAssertTrue(typingAgain.breakBefore, "删完再打也是新的一步")
    }

    // MARK: - 一次动作一步（需求 ②）

    func testEveryAtomicKindBreaksOnBothSides() {
        var policy = UndoGranularity()
        for kind in UndoEditKind.allCases where kind.isAtomic {
            // 同一类连着两次：第二次也不许并进第一次（原子动作没有「同类合并」这回事）。
            let first = policy.decide(kind)
            let second = policy.decide(kind)
            XCTAssertTrue(first.breakAfter, "\(kind) 后面必须断开：否则紧接着的键入会并进这一步")
            XCTAssertTrue(second.breakBefore, "\(kind) 连着来两次是两步（同一类也不许合并）")
            XCTAssertTrue(second.breakAfter)
        }
    }

    func testTypingAndDeletingAreTheOnlyMergeableKinds() {
        let mergeable = UndoEditKind.allCases.filter { !$0.isAtomic }
        XCTAssertEqual(Set(mergeable), [.typing, .deleting],
                       "只有连续键入与连续删除允许合并；多出第三类就是把某件事的撤销拆细了")
    }

    func testTypingAfterLineMoveStartsANewStep() {
        var policy = UndoGranularity()
        _ = policy.decide(.lineMove)
        let typing = policy.decide(.typing)
        XCTAssertTrue(typing.breakBefore, "移完行接着打字，打字不能并进「移动行」这一步")
    }

    func testMoveThenCommentToggleAreTwoSteps() {
        var policy = UndoGranularity()
        let move = policy.decide(.lineMove)
        let comment = policy.decide(.commentToggle)
        XCTAssertTrue(move.breakAfter)
        XCTAssertTrue(comment.breakBefore, "移行与注释切换各自算一步（需求 ② 点名的两个动作）")
    }

    func testNewlineIsItsOwnStep() {
        var policy = UndoGranularity()
        _ = policy.decide(.typing)
        let newline = policy.decide(.newline)
        XCTAssertTrue(newline.breakBefore, "打完一行按回车：回车是另一步，不能并把整行都撤掉")
        XCTAssertTrue(newline.breakAfter)
        let typing = policy.decide(.typing)
        XCTAssertTrue(typing.breakBefore, "回车之后的输入是新的一步")
    }

    func testResetStartsOver() {
        var policy = UndoGranularity()
        _ = policy.decide(.typing)
        policy.reset()
        let typing = policy.decide(.typing)
        XCTAssertTrue(typing.breakBefore, "换文件后重新起算：第一下键入不能并进上一份文档的那一步")
    }

    // MARK: - 动作名（编辑菜单里那一行）

    func testEveryKindHasBothLanguages() {
        for kind in UndoEditKind.allCases {
            let chinese = LocalizedStrings.text(kind.actionNameKey, language: .simplifiedChinese)
            let english = LocalizedStrings.text(kind.actionNameKey, language: .english)
            XCTAssertFalse(chinese.isEmpty, "\(kind) 少了中文动作名：菜单会显示「撤销 」后面空着")
            XCTAssertFalse(english.isEmpty, "\(kind) 少了英文动作名")
            XCTAssertNotEqual(chinese, english, "\(kind) 中英同名 = 英文那一格没写（把键名当中文填了）")
            XCTAssertFalse(chinese.hasPrefix("undoAction"), "\(kind) 拿到的是键名而不是文案（语言表没登记）")
        }
    }

    func testActionNamesAreDistinct() {
        var seen: [String: UndoEditKind] = [:]
        for kind in UndoEditKind.allCases {
            let name = LocalizedStrings.text(kind.actionNameKey, language: .simplifiedChinese)
            if let other = seen[name] {
                XCTFail("「\(name)」同时属于 \(other) 与 \(kind)：撤销菜单里分不清做了什么")
            }
            seen[name] = kind
        }
    }

    // MARK: - 等长替换不顶掉选区与光标（需求 ③）

    func testEqualLengthReplacementKeepsCaret() {
        // 「- [ ] x」里把方框里那一个字符换掉：光标在 8，替换发生在 3
        let result = EditSelectionPolicy.after(original: NSRange(location: 8, length: 0),
                                              editRange: NSRange(location: 3, length: 1),
                                              replacementLength: 1,
                                              requested: NSRange(location: 4, length: 0),
                                              documentLength: 9)
        XCTAssertEqual(result, NSRange(location: 8, length: 0),
                       "等长替换把光标顶到替换末尾 = 用户按一次 ⌘L 光标就跳一下（需求 ③ 明确禁止）")
    }

    func testEqualLengthReplacementKeepsSelection() {
        let result = EditSelectionPolicy.after(original: NSRange(location: 5, length: 3),
                                              editRange: NSRange(location: 1, length: 1),
                                              replacementLength: 1,
                                              requested: NSRange(location: 2, length: 0),
                                              documentLength: 20)
        XCTAssertEqual(result, NSRange(location: 5, length: 3),
                       "选中的一段不许因为一次等长替换被清掉")
    }

    func testLengthChangingReplacementUsesRequestedCaret() {
        let result = EditSelectionPolicy.after(original: NSRange(location: 0, length: 0),
                                              editRange: NSRange(location: 0, length: 2),
                                              replacementLength: 6,
                                              requested: NSRange(location: 6, length: 0),
                                              documentLength: 6)
        XCTAssertEqual(result, NSRange(location: 6, length: 0),
                       "变长替换（续行 / 注释切换）必须用 Core 算好的落点")
    }

    func testRequestedCaretIsClampedToDocument() {
        let result = EditSelectionPolicy.after(original: NSRange(location: 99, length: 0),
                                              editRange: NSRange(location: 0, length: 2),
                                              replacementLength: 6,
                                              requested: NSRange(location: 99, length: 40),
                                              documentLength: 6)
        XCTAssertEqual(result, NSRange(location: 6, length: 0),
                       "落点要被夹进文档，否则选区一越界 AppKit 会把它归零（光标莫名跳到文首）")
    }

    func testEqualLengthKeepsSelectionEvenWhenRequestedDiffers() {
        // 反向守卫：等长这一支**不许**看 `requested` —— 两处都写成 requested 就等于没实现 ③。
        let kept = EditSelectionPolicy.after(original: NSRange(location: 1, length: 2),
                                             editRange: NSRange(location: 4, length: 1),
                                             replacementLength: 1,
                                             requested: NSRange(location: 9, length: 0),
                                             documentLength: 12)
        XCTAssertEqual(kept, NSRange(location: 1, length: 2))
    }
}
