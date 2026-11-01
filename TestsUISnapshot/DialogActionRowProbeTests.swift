import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **对话框动作行**（`FR-STD-WS-UI-014`）—— 需求 B 的 App 内行为探针。
///
/// ## 判据分三条腿（各自能判红）
///
/// ① **取消是文字按钮，不是一枚 ×**：量的不是"配置里写了标题"，而是**画出来占多宽**。
///    同一枚 `DialogActionButton`：带 `取消` 文字时比空标题宽出一整段文字
///    （实测 77pt vs 41pt）—— 只有文字真的画上去，宽度才会这么变。
/// ② **纯图标动作根本不会被画**：`DialogActionRow` 只画一列纯图标动作时，整行高度是 **0**
///    （口径把它挡在门外：`DialogButtonPolicy.resolve` 的 `.iconOnly`），而同一行换成带文字的动作
///    就有 20pt 高。这不是"文案写没写"的问题，是**画布上有没有它**。
/// ③ **Esc 落到取消、回车落到主按**：把真 `DialogActionRow` 装进离屏窗口，造真 `NSEvent`
///    （Esc / Return）交给它，看**哪个动作被回调**。`role: .cancel` 的可见后果就是这一下
///    （Esc 出去、取消生效），不是源码里那个枚举值。
///
/// 另外真渲染三张代表性对话框（新建库 / 保存查询 / 跳到行），在**底部动作行那一带**量墨迹：
/// 那一带必须真有东西（不是一条空白，也不是几枚空按钮）。
///
/// ## 边界（如实登记，别把这条读成「点过了」）
///
/// · **控件身份**：离屏宿主里 SwiftUI `Button` **不落 `NSButton`**、`NSHostingView` 的无障碍树
///   也不构建（实测 `findViews(NSButton.self)` = 0、`accessibilityChildren()` = 0；同族实测见
///   `NotesEditorSaveProbeTests` 文件头）⇒ 「从视图树里读按钮的 `title` / `role`」这条路在本环境
///   里**做不到**。所以按钮文字判到**几何**（宽度差 = 文字宽度），Esc / 回车判到**真实回调**，
///   而不是伪造一个读得到 `title` 的局面。
/// · **带 `TextField` 的真实表单里 Esc 的落点**：离屏窗口成不了 key window（实测
///   `makeKeyAndOrderFront` 之后 `keyWindow` 仍是 nil）⇒ 焦点链不成立，那一档**未验**，
///   本节只判同一个动作行组件这一层。这一条**不冒充点验过**。
/// · 观感（按钮次序的间距 / 圆角 / 色彩）不在本轮。
///
/// 最后一个用例是**接线判据（源树）**，明确标着：它判的是"每个对话框都在用同一份动作行"这个
/// 结构事实 —— 控件身份在本环境里读不到，行为面只能判到渲染与键盘落点。
final class DialogActionRowProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    // MARK: - ① 取消是文字按钮

    @MainActor
    func testCancelIsDrawnAsATextButton() throws {
        let withText = NSHostingController(
            rootView: DialogActionButton(
                systemName: DialogActionRow.fallbackSystemName(for: .cancel),
                title: L(.commonCancel), role: .cancel
            ) {}
        ).sizeThatFits(in: CGSize(width: 400, height: 60))

        let withoutText = NSHostingController(
            rootView: DialogActionButton(
                systemName: DialogActionRow.fallbackSystemName(for: .cancel),
                title: "", role: .cancel
            ) {}
        ).sizeThatFits(in: CGSize(width: 400, height: 60))

        XCTAssertGreaterThan(
            withText.width - withoutText.width, 20,
            "带「\(L(.commonCancel))」的那枚与空标题那枚一样宽（\(withText.width) vs \(withoutText.width)）"
                + " ⇒ 文字没被画上去，取消就是一枚 ×"
        )
        XCTAssertGreaterThan(withText.height, 10, "取消按钮没有高度（根本没画）")
        XCTAssertEqual(
            withText.height, withoutText.height, accuracy: 0.5,
            "文字把按钮撑高了 ⇒ 量到的宽度差不只是文字"
        )
        print("🧪 取消按钮宽度：带文字 \(withText) / 纯图标 \(withoutText)")
    }

    // MARK: - ② 纯图标动作不会被画

    @MainActor
    func testIconOnlyActionIsRejectedAndNotDrawn() throws {
        let readable = DialogActionRow(actions: [
            DialogActionSpec(id: "cancel", title: L(.commonCancel), role: .cancel),
            DialogActionSpec(id: "create", title: L(.createDatabaseConfirm), role: .primary),
        ]) { _ in }

        let iconOnly = DialogActionRow(actions: [
            DialogActionSpec(id: "cancel", title: "   ", systemImage: "xmark", role: .cancel),
        ]) { _ in }

        let readableHeight = NSHostingController(rootView: readable)
            .sizeThatFits(in: CGSize(width: 320, height: 200)).height
        let iconOnlyHeight = NSHostingController(rootView: iconOnly)
            .sizeThatFits(in: CGSize(width: 320, height: 200)).height

        XCTAssertGreaterThan(readableHeight, 10, "带文字的动作行没有高度（一行按钮没画出来）")
        XCTAssertEqual(
            iconOnlyHeight, 0, accuracy: 0.01,
            "纯图标动作被画出来了（整行高 \(iconOnlyHeight)pt）—— 对话框里不许出现纯图标动作"
        )

        // 同一个口径在投影层也说了一遍（界面上"不画"的理由就是这个违规）。
        // 夹具里**给了取消**（带文字的那一枚）：这样"缺取消"不会顺带报出来，
        // 判到的就只剩"纯图标被拒"这一档。
        let layout = DialogButtonPolicy.resolve(
            [
                DialogActionSpec(id: "cancel", title: L(.commonCancel), role: .cancel),
                DialogActionSpec(id: "icon", title: "   ", systemImage: "xmark", role: .neutral),
            ],
            dismissible: true
        )
        XCTAssertEqual(layout.accepted.map(\.id), ["cancel"], "带文字的那枚没被接受：\(layout.accepted.map(\.id))")
        XCTAssertEqual(layout.rejected.map(\.id), ["icon"], "纯图标动作没被单独记下来（被静默吞掉）")
        XCTAssertEqual(
            layout.violations.map(\.code), ["dialog.action.iconOnly"],
            "违规码不对（夹具里有取消，所以不该再报别的）：\(layout.violations.map(\.code))"
        )
        // 反面：把那一枚的文字补上就被接受 —— 不是"这一行什么都画不出来"的恒真。
        let withTitle = DialogButtonPolicy.resolve(
            [
                DialogActionSpec(id: "cancel", title: L(.commonCancel), role: .cancel),
                DialogActionSpec(id: "icon", title: L(.commonSave), systemImage: "xmark", role: .neutral),
            ],
            dismissible: true
        )
        XCTAssertEqual(withTitle.accepted.map(\.id), ["cancel", "icon"], "补上文字之后仍被拒 ⇒ 上面那条判的是空跑")
        XCTAssertTrue(withTitle.violations.isEmpty, "补上文字之后还有违规：\(withTitle.violations.map(\.code))")
        print("🧪 动作行高度：带文字 \(readableHeight) / 纯图标 \(iconOnlyHeight)")
    }

    /// **同名两条也是违规**：两枚「保存」在截图与读屏里分不清点的是哪一枚。
    func testDuplicateTitlesAreRejected() {
        let layout = DialogButtonPolicy.resolve([
            DialogActionSpec(id: "a", title: L(.commonSave), role: .neutral),
            DialogActionSpec(id: "b", title: L(.commonSave), role: .primary),
        ], dismissible: true)
        XCTAssertTrue(
            layout.violations.contains { $0.code == "dialog.action.duplicateTitle" },
            "两枚同名动作没被判违规：\(layout.violations.map(\.code))"
        )
    }

    // MARK: - ③ Esc 落到取消、回车落到主按（真事件 → 真回调）

    /// 一行代表性动作 + 一枚记录"哪个 id 被点了"的收集器。
    @MainActor
    private func makeRow(fired: @escaping (String) -> Void) -> DialogActionRow {
        DialogActionRow(actions: [
            DialogActionSpec(id: "cancel", title: L(.commonCancel), systemImage: "xmark.circle", role: .cancel),
            DialogActionSpec(
                id: "create", title: L(.createDatabaseConfirm), systemImage: "checkmark", role: .primary
            ),
        ], perform: fired)
    }

    private func keyEvent(_ characters: String, keyCode: UInt16, windowNumber: Int) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        )!
    }

    @MainActor
    func testEscapeFiresTheCancelActionAndReturnFiresThePrimary() throws {
        var fired: [String] = []
        let host = UISnapshot.LiveHost(makeRow { fired.append($0) }, size: CGSize(width: 400, height: 60))
        host.pump(0.3)

        // Esc（keyCode 53，`\u{1b}`）：AppKit 派发取消快捷键的那一层。
        let escape = keyEvent("\u{1b}", keyCode: 53, windowNumber: host.window.windowNumber)
        let handledEscape = host.hosting.performKeyEquivalent(with: escape)
        XCTAssertTrue(handledEscape, "Esc 没人接 ⇒ 「取消」不是 `role: .cancel`（那正是它的可见后果）")
        XCTAssertEqual(
            fired, ["cancel"],
            "按 Esc 落到的不是「取消」：实测 \(fired) —— 用户按 Esc 想要的是「什么都没发生」"
        )

        // 回车（keyCode 36，`\r`）：主按的落点。
        let enter = keyEvent("\r", keyCode: 36, windowNumber: host.window.windowNumber)
        let handledEnter = host.hosting.performKeyEquivalent(with: enter)
        XCTAssertTrue(handledEnter, "回车没人接 ⇒ 主按不是回车落点")
        XCTAssertEqual(
            fired, ["cancel", "create"],
            "回车落到的不是主按：实测 \(fired)"
        )
    }

    // MARK: - ④ 三张代表性对话框：底部动作行那一带真有东西

    /// 三张**真表单**（都是 `DialogActionRow` 的直接消费者：新建库 / 保存查询 / 跳到行）。
    ///
    /// 每张都按**它自己的理想尺寸**渲染：`UISnapshot.write` 会把内容在给定尺寸里居中，
    /// 尺寸给大了动作行就不在底边上 —— 那时「底部那一带有没有墨迹」判的就不是动作行。
    @MainActor
    func testRepresentativeDialogsDrawTheirActionRowBand() throws {
        let dialogs: [(String, AnyView, CGSize)] = [
            ("create-database", AnyView(CreateDatabaseSheet { _ in }), CGSize(width: 380, height: 200)),
            ("save-query", AnyView(SaveQuerySheet(defaultName: "查询 1", isDuplicate: { _ in false }, onSave: { _ in })),
             CGSize(width: 380, height: 200)),
            ("go-to-line", AnyView(GoToLineSheet { _, _ in }), CGSize(width: 320, height: 220)),
        ]

        for (name, view, proposal) in dialogs {
            let ideal = NSHostingController(rootView: view).sizeThatFits(in: proposal)
            XCTAssertGreaterThan(ideal.height, 60, "\(name) 的理想尺寸只有 \(ideal.height)pt —— 内容没排版出来")
            XCTAssertGreaterThan(ideal.width, 200, "\(name) 的理想宽度只有 \(ideal.width)pt")

            let record = try UISnapshot.write(
                "dialog-action-row-\(name)",
                size: CGSize(width: ceil(ideal.width), height: ceil(ideal.height))
            ) { view }
            XCTAssertGreaterThan(record.contentRatio, 0.002, "\(name) 渲染成空白（这张图什么也没画）")

            // 动作行落在图上哪一带：这三张表单都是 `.padding(20)`，按钮本身约 20pt 高
            // ⇒ 动作行在**距底 20pt ~ 40pt** 那一条。裁之前先把「点」换算成「像素」
            // （`UISnapshot.write` 默认 2× 落盘，直接按 pt 裁只会裁到底部那段内边距 —— 本机实测
            // 第一版就是这么量出 0 的）。
            let pixels = try XCTUnwrap(
                UISnapshot.pixelSize(ofPNGAt: record.file), "\(name) 的产物读不出像素尺寸"
            )
            let scale = Double(pixels.height) / Double(ceil(ideal.height))
            XCTAssertGreaterThan(scale, 1.5, "\(name) 的落盘倍率不对（\(scale)）—— 裁带的坐标会错")
            let paddingBand = try XCTUnwrap(
                UISnapshot.band(ofPNGAt: record.file, fromBottom: 0, height: Int((10 * scale).rounded())),
                "\(name) 的产物读不回来（\(record.file)）"
            )
            let rowBand = try XCTUnwrap(
                UISnapshot.band(ofPNGAt: record.file, fromBottom: Int((20 * scale).rounded()),
                                height: Int((24 * scale).rounded())),
                "\(name) 的产物读不回来（\(record.file)）"
            )
            // 对照：最底下那 10pt 是**内边距**（应该干干净净），动作行比它多得多 —— 说明裁的是位置。
            XCTAssertLessThan(
                paddingBand.ink, 40,
                "\(name) 最底下 10pt 内边距里也有 \(paddingBand.ink) 像素墨迹 ⇒ 这一带的定义不对"
            )
            XCTAssertGreaterThan(
                rowBand.ink, 200,
                "\(name) 动作行那一带几乎没有墨迹（\(rowBand.ink) 像素）—— 按钮可能退化成空块"
            )
            print(
                "🧪 \(name)：理想尺寸 \(ideal)，倍率 \(scale)，内容占比 \(record.contentRatio)，"
                    + "内边距带 \(paddingBand.ink) 像素 / 动作行带 \(rowBand.ink) 像素"
            )
        }
    }

    // MARK: - ⑤ 接线判据（源树，明确标注）：每个对话框都在用同一份动作行

    /// **这一条不是行为判据**：控件身份（谁画的这枚按钮）在上面的边界里读不到，所以这里退一步判
    /// 「声明了动作的对话框都在用 `DialogActionRow`」这个结构事实 —— 它挡的是"某个 Sheet 自己
    /// `HStack` 拼一行按钮"（那样次序 / Esc 落点 / 纯图标拦阻三件事就各写一遍）。
    func testEveryDialogThatDeclaresActionsGoesThroughTheSharedRow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let views = root.appendingPathComponent("App/Views", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(atPath: views.path)
            .filter { $0.hasSuffix(".swift") }

        var offenders: [String] = []
        var scanned = 0
        for file in files {
            let source = try String(contentsOf: views.appendingPathComponent(file), encoding: .utf8)
            guard source.contains("DialogActionSpec(") else { continue }
            scanned += 1
            if !source.contains("DialogActionRow(") {
                offenders.append(file)
            }
        }
        XCTAssertGreaterThanOrEqual(scanned, 3, "只在 \(scanned) 份文件里扫到动作声明 ⇒ 这条判据扫错了地方")
        XCTAssertTrue(
            offenders.isEmpty,
            "这些对话框声明了动作却没走 `DialogActionRow`：\(offenders) —— 次序 / Esc / 纯图标拦阻会各写一遍"
        )
    }
}
