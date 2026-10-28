import XCTest
@testable import DoyahCore

/// `FR-STD-WS-UI-014`：**对话框按钮用系统文字按钮**（Sheet / Form 内无纯图标按钮，取消为 `role: .cancel`）。
///
/// 这一族判据判的是 `Core/DialogButtonPolicy.swift` 的三件事：**画哪几枚 / 什么次序 /
/// 谁拿回车与 Esc**。它们此前一件都没有 —— 25 个对话框各自手搭 `HStack`，取消按钮只挂
/// `.keyboardShortcut(.cancelAction)` 凑 Esc，`ButtonRole` 一枚都没写。
///
/// 每一条都成对：反例（改坏一处）在证据文件 `.agent/evidence/2026-10-29-WS-UI-014.md` 里
/// 逐段跑过判红，然后逐字节还原。
final class DialogButtonPolicyTests: XCTestCase {

    // MARK: - 帮手

    private func spec(
        _ id: String,
        _ title: String,
        role: DialogActionRole = .neutral,
        image: String? = nil,
        enabled: Bool = true
    ) -> DialogActionSpec {
        DialogActionSpec(
            id: id, title: title, systemImage: image, role: role, isEnabled: enabled
        )
    }

    private func codes(_ layout: DialogActionLayout) -> [String] {
        layout.violations.map(\.code)
    }

    // MARK: - ① 纯图标被拒

    func testIconOnlyActionIsRejectedNotRendered() {
        let layout = DialogButtonPolicy.resolve(
            [spec("cancel", "取消", role: .cancel), spec("browse", "")],
            dismissible: true
        )

        XCTAssertEqual(layout.accepted.map(\.id), ["cancel"], "空标题那枚不该被画出来")
        XCTAssertEqual(layout.rejected.map(\.id), ["browse"], "被拒的要如实留在 rejected 里，不静默吞掉")
        XCTAssertEqual(codes(layout), ["dialog.action.iconOnly"])
        XCTAssertFalse(layout.isCompliant)
    }

    func testWhitespaceOnlyTitleCountsAsIconOnly() {
        // 三档空白：空格 / 制表符 / 换行 —— `title.isEmpty` 判不出这三种
        for blank in [" ", "\t", "\n", "  \n\t "] {
            let layout = DialogButtonPolicy.resolve(
                [spec("cancel", "取消", role: .cancel), spec("x", blank)],
                dismissible: true
            )
            XCTAssertEqual(layout.rejected.map(\.id), ["x"], "「\(blank.debugDescription)」应算纯图标")
        }
    }

    func testTitleIsTrimmedForComparisonButKeptForRendering() {
        let layout = DialogButtonPolicy.resolve(
            [spec("cancel", "  取消 ", role: .cancel)],
            dismissible: true
        )

        XCTAssertTrue(layout.isCompliant)
        XCTAssertEqual(layout.accepted.first?.visibleTitle, "取消")
        XCTAssertEqual(layout.accepted.first?.title, "  取消 ", "渲染文案原样保留 ── 不替调用点改字")
    }

    func testEveryActionIconOnlyLeavesNothingToRender() {
        let layout = DialogButtonPolicy.resolve([spec("a", ""), spec("b", " ")], dismissible: false)

        XCTAssertTrue(layout.accepted.isEmpty)
        XCTAssertEqual(layout.rejected.count, 2)
        XCTAssertNil(layout.defaultActionID)
        XCTAssertNil(layout.cancelActionID)
        XCTAssertEqual(codes(layout), ["dialog.action.iconOnly"])
    }

    // MARK: - ② 次序是排出来的

    func testOrderingIsCancelThenNeutralThenDestructiveThenPrimary() {
        // 声明顺序故意打乱（主按写在最前）—— 画出来的次序必须与声明顺序无关
        let layout = DialogButtonPolicy.resolve(
            [
                spec("ok", "保存", role: .primary),
                spec("drop", "删除", role: .destructive),
                spec("defaults", "恢复默认", role: .neutral),
                spec("cancel", "取消", role: .cancel)
            ],
            dismissible: true
        )

        XCTAssertEqual(layout.accepted.map(\.id), ["cancel", "defaults", "drop", "ok"])
        XCTAssertTrue(layout.isCompliant)
    }

    func testOrderingIsStableAcrossRepeatedResolves() {
        let specs = [
            spec("n1", "浏览"),
            spec("cancel", "取消", role: .cancel),
            spec("n2", "预览"),
            spec("ok", "确定", role: .primary)
        ]

        let first = DialogButtonPolicy.resolve(specs, dismissible: true)
        let second = DialogButtonPolicy.resolve(specs, dismissible: true)

        XCTAssertEqual(first, second, "同一份输入两遍必须逐条相同")
        XCTAssertEqual(first.accepted.map(\.id), ["cancel", "n1", "n2", "ok"])
    }

    // MARK: - ③ 回车与 Esc 的落点

    func testPrimaryGetsReturnAndCancelGetsEscape() {
        let layout = DialogButtonPolicy.resolve(
            [spec("cancel", "取消", role: .cancel), spec("ok", "确定", role: .primary)],
            dismissible: true
        )

        XCTAssertEqual(layout.defaultActionID, "ok")
        XCTAssertEqual(layout.cancelActionID, "cancel")
        XCTAssertEqual(layout.shortcut(for: "ok"), .default)
        XCTAssertEqual(layout.shortcut(for: "cancel"), .cancel)
    }

    func testNeutralAndDestructiveNeverTakeReturn() {
        let layout = DialogButtonPolicy.resolve(
            [
                spec("cancel", "取消", role: .cancel),
                spec("browse", "浏览"),
                spec("drop", "删除", role: .destructive)
            ],
            dismissible: true
        )

        XCTAssertNil(layout.defaultActionID, "没有主按时回车不该落到任何一枚上")
        XCTAssertNil(layout.shortcut(for: "browse"))
        XCTAssertNil(layout.shortcut(for: "drop"), "破坏性动作抢回车 = 顺手一回车就删了")
        XCTAssertEqual(layout.shortcut(for: "cancel"), .cancel)
    }

    // MARK: - ④ 取消档：必须有一枚，且只能有一枚

    func testDismissibleDialogWithoutCancelIsAViolation() {
        let layout = DialogButtonPolicy.resolve([spec("ok", "确定", role: .primary)], dismissible: true)

        XCTAssertEqual(codes(layout), ["dialog.action.missingCancel"])
        XCTAssertNil(layout.cancelActionID, "缺取消时不许把别的动作冒充成 Esc 落点")
    }

    func testNonDismissibleRowDoesNotRequireCancel() {
        let layout = DialogButtonPolicy.resolve([spec("next", "下一步", role: .primary)], dismissible: false)

        XCTAssertTrue(layout.isCompliant)
        XCTAssertEqual(layout.defaultActionID, "next")
    }

    func testTwoCancelsAreReportedAndBothStayVisible() {
        let layout = DialogButtonPolicy.resolve(
            [spec("c1", "取消", role: .cancel), spec("c2", "关闭", role: .cancel), spec("ok", "确定", role: .primary)],
            dismissible: true
        )

        XCTAssertEqual(codes(layout), ["dialog.action.duplicateCancel"])
        XCTAssertEqual(layout.accepted.count, 3, "两条都在画面上（不静默吞掉一条）")
        XCTAssertEqual(layout.cancelActionID, "c1", "落点取声明里的第一条 —— 确定可判")
    }

    // MARK: - ⑤ 主按只有一枚、同名不许并存

    func testTwoPrimariesAreReportedAndDefaultTakesTheFirst() {
        let layout = DialogButtonPolicy.resolve(
            [spec("cancel", "取消", role: .cancel), spec("p1", "保存", role: .primary), spec("p2", "另存", role: .primary)],
            dismissible: true
        )

        XCTAssertEqual(codes(layout), ["dialog.action.duplicatePrimary"])
        XCTAssertEqual(layout.defaultActionID, "p1")
    }

    func testDuplicateVisibleTitleIsAViolation() {
        let layout = DialogButtonPolicy.resolve(
            [spec("cancel", "取消", role: .cancel), spec("a", "保存"), spec("b", " 保存 ", role: .destructive)],
            dismissible: true
        )

        XCTAssertEqual(layout.violations.count, 1)
        XCTAssertEqual(layout.violations.first?.code, "dialog.action.duplicateTitle")
        XCTAssertEqual(layout.violations.first?.ids, ["a", "b"], "两端空白不构成区分")
    }

    func testComplianceMeansNoViolationAtAll() {
        let layout = DialogButtonPolicy.resolve(
            [spec("cancel", "取消", role: .cancel), spec("ok", "确定", role: .primary)],
            dismissible: true
        )

        XCTAssertTrue(layout.violations.isEmpty)
        XCTAssertTrue(layout.isCompliant)
    }

    // MARK: - ⑥ 违规码是机器读的

    func testViolationCodesAreStable() {
        XCTAssertEqual(
            DialogActionViolation.iconOnly(ids: ["a"]).code,
            "dialog.action.iconOnly"
        )
        XCTAssertEqual(DialogActionViolation.missingCancel.code, "dialog.action.missingCancel")
        XCTAssertEqual(
            DialogActionViolation.duplicateTitle(title: "保存", ids: ["a", "b"]).ids,
            ["a", "b"]
        )
        XCTAssertTrue(DialogActionViolation.missingCancel.ids.isEmpty, "它缺的正是那一枚")
    }
}
