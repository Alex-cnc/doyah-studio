import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 笔记正文 **编辑面富文本化 + 行内四枚**的机器判据
/// （片 `WY-1b1` · 派单 `T-20261009-045` 第 ①②③④ 项 / `T-20261009-048`）。
///
/// ## 判什么（卡上判据 3 的三条，逐条对应）
///
///   ① **编辑面承载是富文本** —— 真删去之后宿主里能找到**恰好一块** `NotesTextView`，
///      `isRichText == true`，且 `NSTextStorage` **可施属性**（写一条进去读得回来）。
///      「可施属性」这一条是判据的骨架：纯文本面（`TextEditor`）拒绝富文本，这一条当场红。
///   ② **四枚各点一次，属性确实变** —— 选中一段，依次 `toggle(.bold)` / `.italic` / `.underline` /
///      `.highlight`：粗 / 斜**可见字体变了**（或至少标记属性在）、下划线出 `.underlineStyle`、
///      笔刷让 `.backgroundColor` **由 nil 变成一处定义的那份淡黄**（`NoteHighlight`）。
///   ③ **正文里不出现标记** —— 装进来的正文含 `**`，装完后 `string` 里 `**` / `#` 计数**都是 0**
///      （「即时呈现」不是「把标记原样画出来」）。
///
/// ## 为什么驱动的是 `NotesRichTextController` 而不是「点那四枚 SwiftUI `Button`」
///
/// 实测（macOS 27 / 本机，与 `NotesEditorSaveProbeTests` 头注释同一条）：离屏宿主里 SwiftUI 的
/// `Button` **不落到 `NSButton`**、无障碍树也不构建 ⇒ 「点一下那枚按钮」在这一路上够不着。
/// 于是判据走**按钮点下去真正调的那个入口**（`NotesRichTextController.toggle(_:)`）——
/// 工具条那四枚的 action 就是它，两处不是两条路（见 `NotesEditorToolbar` 与 `NotesRichTextEditor`）。
/// **边界（如实登记）**：判不到「AppKit 把那份 SwiftUI 描述画成按钮并派发点击」（归人工点验）。
///
/// ## 不落快照
///
/// 本探针**不调** `UISnapshot.write` / `LiveHost.capture`：判据读的是 **AppKit 视图树上的属性**
/// （字体 / 下划线 / 底色），不是像素 —— 落图只会搅乱「张数 / 组数」那类派生计数
/// （与 `NotesEditorSaveProbeTests` 刻意不调 `write` 同款理由）。
///
/// 跑法：`env DOYAH_UI_SNAPSHOT=1 swift test --filter NotesEditorFormatProbeTests`
/// （或 `bash Scripts/run-manual-verification-probes.sh --filter NotesEditorFormatProbeTests`）。
final class NotesEditorFormatProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏渲染要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    // MARK: - 装配

    /// 宿主视图：一块绑在 `@State` 上的富文本面（与 `NotesEditorView` 里那一支同构）。
    private struct Mounted: View {
        @State var bodyText: String
        var controller: NotesRichTextController

        var body: some View {
            NotesRichTextEditor(text: $bodyText, controller: controller)
                .frame(width: 640, height: 320)
        }
    }

    private static let size = CGSize(width: 700, height: 380)

    @MainActor
    private func makeSurface(
        text: String
    ) throws -> (host: UISnapshot.LiveHost<Mounted>, controller: NotesRichTextController, textView: NotesTextView) {
        let controller = NotesRichTextController()
        let host = UISnapshot.LiveHost(
            Mounted(bodyText: text, controller: controller),
            size: Self.size,
            scheme: .light
        )
        let found = Self.findTextViews(in: host.hosting)
        XCTAssertEqual(
            found.count, 1,
            "宿主视图树里应当**恰好**有一块 `NotesTextView`（实测 \(found.count) 块）——"
                + " 零块 = 编辑面没建起来，多块 = 有两处编辑面在跑"
        )
        let textView = try XCTUnwrap(found.first, "富文本编辑面没建起来（视图树里找不到 `NotesTextView`）")
        return (host, controller, textView)
    }

    private static func findTextViews(in view: NSView) -> [NotesTextView] {
        var found: [NotesTextView] = []
        if let match = view as? NotesTextView { found.append(match) }
        for subview in view.subviews {
            found.append(contentsOf: findTextViews(in: subview))
        }
        return found
    }

    // MARK: - 判据 ① 承载是富文本

    /// ①-a：`isRichText == true` 且 `NSTextStorage` **真的**可施属性（写进去读得回来）。
    @MainActor
    func testFormatProbeEditorIsRichTextWithAnAttributeCapableStorage() throws {
        let surface = try makeSurface(text: "**加粗** 与 *斜体* 与 `码`")
        let textView = surface.textView

        XCTAssertTrue(textView.isRichText, "编辑面必须是富文本面（`isRichText == true`）")
        XCTAssertTrue(textView.isEditable, "编辑面必须是可编辑的（`.edit` 那一支）")

        // 可施属性：往第一段加一条下划线，再从同一处读回来。
        guard let storage = textView.textStorage else {
            return XCTFail("富文本面必须有 `NSTextStorage`（承载属性的那一层）")
        }
        let probeRange = NSRange(location: 0, length: 1)
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: probeRange)
        let readBack = storage.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
        XCTAssertEqual(
            readBack, NSUnderlineStyle.single.rawValue,
            "`NSTextStorage` 必须真的收得下属性（写进去读不回来 = 它不是富文本承载面）"
        )
        print("📄 WY-1b1 ① 承载：isRichText=\(textView.isRichText) ／ 属性往返=\(readBack.map(String.init) ?? "nil")")

        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 判据 ② 四枚各点一次，属性确实变

    /// ②：粗 / 斜 / 下划线 / 笔刷逐项 —— 下划线与底色判**系统属性**，粗斜判**字体真的换了**
    /// （等宽族未必有粗 / 斜变体 ⇒ 两个方向都留：可见字体变 **或** 标记属性在）。
    @MainActor
    func testFormatProbeFourButtonsEachChangeTheSelection() throws {
        XCTAssertEqual(
            NoteInlineCommand.allCases.count, 4,
            "工具条那行内四枚是**四**条命令（粗 / 斜 / 下划线 / 笔刷）——实测 \(NoteInlineCommand.allCases.count) 条"
        )

        let surface = try makeSurface(text: "ABCDEFGH")
        let textView = surface.textView
        guard let storage = textView.textStorage else {
            return XCTFail("富文本面必须有 `NSTextStorage`")
        }
        let range = NSRange(location: 0, length: 4)
        textView.setSelectedRange(range)

        let baseFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont

        // ① 粗体
        surface.controller.toggle(.bold)
        let boldFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let boldTrait = boldFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
        XCTAssertNotNil(
            storage.attribute(.doyahBold, at: 0, effectiveRange: nil),
            "点一下粗体：这一段的「粗」标记属性必须在（动作没落到选区上）"
        )
        XCTAssertTrue(
            boldTrait || boldFont != baseFont,
            "点一下粗体：可见字体必须变（trait=\(boldTrait)／字体是否换人=\(boldFont != baseFont)）"
        )

        // ② 斜体
        textView.setSelectedRange(range)
        surface.controller.toggle(.italic)
        let italicFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let italicTrait = italicFont?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
        XCTAssertNotNil(
            storage.attribute(.doyahItalic, at: 0, effectiveRange: nil),
            "点一下斜体：这一段的「斜」标记属性必须在"
        )
        XCTAssertTrue(italicTrait || italicFont != baseFont, "点一下斜体：可见字体必须变")

        // ③ 下划线（系统属性直判）
        textView.setSelectedRange(range)
        XCTAssertNil(
            storage.attribute(.underlineStyle, at: 0, effectiveRange: nil),
            "前置：还没点下划线，这一段落不该有 `.underlineStyle`"
        )
        surface.controller.toggle(.underline)
        XCTAssertEqual(
            storage.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue,
            "点一下下划线：`.underlineStyle` 必须出现"
        )

        // ④ 笔刷 = 荧光笔·淡黄（`.backgroundColor` 由 nil 变非 nil，且是唯一出处那份色值）
        textView.setSelectedRange(range)
        XCTAssertNil(
            storage.attribute(.backgroundColor, at: 0, effectiveRange: nil),
            "前置：还没点笔刷，这一段落不该有底色"
        )
        surface.controller.toggle(.highlight)
        let highlight = storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(highlight, "点一下笔刷：`.backgroundColor` 必须由 nil 变成非 nil")
        XCTAssertEqual(
            highlight, Theme.nsColor(hex: NoteHighlight.rgb),
            "底色必须是**一处定义**的那份淡黄（`NoteHighlight`）——不是各写一遍的另一个黄"
        )
        let highlightNote = highlight == Theme.nsColor(hex: NoteHighlight.rgb) ? "淡黄 ✓" : "不是淡黄"
        print(
            "📄 WY-1b1 ② 四枚：粗(trait=\(boldTrait)) ／ 斜(trait=\(italicTrait)) ／ "
                + "下划线=\(NSUnderlineStyle.single.rawValue) ／ 底色=\(highlight == nil ? "nil" : highlightNote)"
        )

        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 判据 ③ 正文里不出现标记

    /// ③：正文装进来时 `**` / `*` / 反引号这些标记**不露出**（即时而得的富文本），
    /// 且 `**` 与 `#` 的计数都是 **0**。
    @MainActor
    func testFormatProbePlainTextCarriesNoMarkup() throws {
        let markdown = "**加粗词** 与 *斜体词* 与 `码词`"
        let surface = try makeSurface(text: markdown)
        let plain = surface.textView.string

        XCTAssertEqual(plain.components(separatedBy: "**").count - 1, 0, "正文里不许出现 `**`：\(plain)")
        XCTAssertEqual(plain.components(separatedBy: "#").count - 1, 0, "正文里不许出现 `#`：\(plain)")
        XCTAssertEqual(
            plain.replacingOccurrences(of: " ", with: ""),
            "加粗词与斜体词与码词",
            "标记剥掉之后剩下的就是那几个词 —— 不吞、也不留残片：\(plain)"
        )
        XCTAssertGreaterThan(plain.count, 0, "空正文会让上面几条恒真（空串里也没有 `**`）")
        print("📄 WY-1b1 ③ 正文：\"\(plain)\" ／ `**`=0 ／ `#`=0")

        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 片 `WY-1b2`：块级三枚（勾选框 / 有序编号 / 无序编号）+ 点正文即出 + 预览只读
    //
    // 判据 3 的四条（卡上逐条对应）：
    //   ① 工具条内**七枚按钮齐**（行内四枚 + 块级三枚）且每枚带 `help`（tips）；
    //   ② ⑤⑥⑦ 各点击一次后正文结构确实变化（任务项 / 编号列表的块级属性落上 span）；
    //   ③ **勾选 ⇒ 退出重开仍在**（同一次跑内重开一次 —— 本片只到 `NoteBody` 交换面往返 +
    //      重挂一次编辑面；真落库 + 端到端归 `WY-2a`，组长裁决第 295 轮）；
    //   ④ `FR-NOTEUI-10` 点正文即出（工具栏只在编辑态出现）· `FR-NOTEUI-12` 预览态（`NotePreviewBody`）
    //      仍 `isEditable == false` 且工具条不出现。
    //
    // **边界（如实登记，与 WY-1b1 同一条）**：这块离屏宿主里 SwiftUI 的 `Button` 不落到 `NSButton`、
    // 无障碍树在离屏时不构建 ⇒ **判不到**「AppKit 把那份 SwiftUI 描述画成七枚按钮并派发点击」
    // （归人工点验）。① 因此拆成「逐枚枚举标识 + 每枚带 help + 源锚点（工具条真的按那两个枚举画）
    // + 渲染级『工具条带内没有文字按钮』」；④ 的「工具条不出现」判在**源锚点**（工具条只在
    // `editorMode == .edit` 那一支里画）与**渲染**（预览态那块可编辑 `NotesTextView` 不在视图树里）。

    /// 仓根：`#filePath` = 本文件在仓里的绝对路径 ⇒ 上两级就是根（与 `NotesEditorSaveProbeTests` 同款）。
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TestsUISnapshot
            .deletingLastPathComponent()  // 仓根
    }

    private func notesPanelSource() throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("App/Views/NotesPanel.swift"),
            encoding: .utf8
        )
    }

    /// **工具条那七枚的标识**：行内四枚（片 `WY-1b1`）+ 块级三枚（本片）—— 从两个 `CaseIterable`
    /// 枚举派生（唯一出处；新增一档编译期就得给标识），顺序与工具条里的排列一致。
    private static var toolbarIdentifiers: [String] {
        NoteInlineCommand.allCases.map(\.accessibilityIdentifier)
            + NoteBlockCommand.allCases.map(\.accessibilityIdentifier)
    }

    /// 一条命令的悬停名字（`help`）：中英都非空、互不相同（缺一语言 = 死译文，`check-literal-language` 同族）。
    private func assertHelpName(_ key: LKey, label: String) throws {
        let chinese = LocalizedStrings.text(key, language: .simplifiedChinese)
        let english = LocalizedStrings.text(key, language: .english)
        XCTAssertFalse(chinese.isEmpty, "\(label) 缺中文悬停名字（\(key.rawValue)）")
        XCTAssertFalse(english.isEmpty, "\(label) 缺英文悬停名字（\(key.rawValue)）")
        XCTAssertNotEqual(chinese, english, "\(label) 中英一模一样 ⇒ 语言表那一半没落地")
        print("📄 WY-1b2 \(label) 悬停名字：中「\(chinese)」／ 英「\(english)」")
    }

    // MARK: 判据 ① 七枚按钮齐 + 每枚带 help

    @MainActor
    func testBlockProbeToolbarHasSevenIconButtons() throws {
        // ①-a 逐枚枚举标识：行内四枚 + 块级三枚 = **七枚**（顺序固定）。
        let identifiers = Self.toolbarIdentifiers
        print("📄 WY-1b2 ①-a 工具条标识（\(identifiers.count) 枚）：\(identifiers)")
        XCTAssertEqual(
            identifiers,
            [
                "notes-editor-format-bold",
                "notes-editor-format-italic",
                "notes-editor-format-underline",
                "notes-editor-format-highlight",
                "notes-editor-block-checkbox",
                "notes-editor-block-ordered",
                "notes-editor-block-unordered",
            ],
            "工具条应当**恰好**是那七枚（行内四枚 + 块级三枚）—— 实测 \(identifiers.count) 枚"
        )

        // ①-a（续）每枚带**图标**：七个符号名非空、互不相同（各写一遍迟早撞车）。
        let symbols = NoteInlineCommand.allCases.map(\.symbolName) + NoteBlockCommand.allCases.map(\.symbolName)
        XCTAssertEqual(symbols.count, 7, "图标数不是七")
        XCTAssertTrue(symbols.allSatisfy { !$0.isEmpty }, "有空图标：\(symbols)")
        XCTAssertEqual(Set(symbols).count, 7, "七枚里有重名的图标：\(symbols)")

        // ①-b 每枚带 **help**（悬停名字）：中英都非空且不同。
        for command in NoteInlineCommand.allCases {
            try assertHelpName(command.titleKey, label: "行内·\(command.rawValue)")
        }
        for command in NoteBlockCommand.allCases {
            try assertHelpName(command.titleKey, label: "块级·\(command.rawValue)")
        }

        // ①-c 源锚点：工具条真的按那两个枚举画（图标 + 悬停 + 标识），不是各写一遍。
        let source = try notesPanelSource()
        for anchor in [
            "ForEach(NoteInlineCommand.allCases, id: \\.self) { command in",
            "ForEach(NoteBlockCommand.allCases, id: \\.self) { command in",
            "Image(systemName: command.symbolName)",
            ".help(L(command.titleKey))",
            ".accessibilityIdentifier(command.accessibilityIdentifier)",
            "controller.toggleBlock(command)",
        ] {
            XCTAssertTrue(
                source.contains(anchor),
                "`NotesPanel.swift` 里找不到「\(anchor)」—— 工具条那一枚的接线掉了"
            )
        }
        XCTAssertFalse(
            source.contains("\"notes-editor-format-\\("),
            "标识不该在视图里再拼一遍（唯一出处是枚举的 `accessibilityIdentifier`）"
        )

        // ①-d 渲染级（NFR-UI-01 禁文字按钮）：工具条那一带里没有带字的 `NSButton`。
        let host = makeEditorHost()
        host.state.editorMode = .edit
        host.state.noteEditorTitle = "临"
        let live = UISnapshot.LiveHost(editorSurface(host), size: Self.editorSize, scheme: .light)
        let band = CGFloat(Self.toolbarBandToTop) / 2  // px → pt
        let bandTitles = UISnapshot.LiveHost<Never>.findViews(ofType: NSButton.self, in: live.hosting)
            .filter { topDistance(of: $0, in: live.hosting) < band }
            .map(\.title)
        print("🖼 WY-1b2 ①-d 工具条那一带（y < \(band)pt）里的 `NSButton` 标题 = \(bandTitles)")
        XCTAssertTrue(
            bandTitles.allSatisfy { $0.isEmpty },
            "工具条那一带里有带字的 `NSButton`：\(bandTitles) —— `NFR-UI-01` / `FR-EXEC-13` 禁文字按钮"
        )

        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: 判据 ② 三条块级命令各点一次，正文结构确实变化

    @MainActor
    func testBlockProbeThreeBlockCommandsChangeBodyStructure() throws {
        XCTAssertEqual(
            NoteBlockCommand.allCases.count, 3,
            "块级是**三**条命令（勾选框 / 有序编号 / 无序编号）——实测 \(NoteBlockCommand.allCases.count) 条"
        )

        let surface = try makeSurface(text: "甲乙丙")
        let textView = surface.textView
        let storage = try XCTUnwrap(textView.textStorage, "富文本面必须有 `NSTextStorage`")
        textView.setSelectedRange(NSRange(location: 0, length: 0))  // 光标落在本段

        let before = NoteRichAttributes.spans(from: storage)
        XCTAssertNil(before.first?.block, "前置：普通段落没有块级属性")

        // ⑤ 勾选框（任务项）—— 段落变成 `LIST_CHECKBOX`（未勾）。
        surface.controller.toggleBlock(.checkbox)
        let afterCheckbox = NoteRichAttributes.spans(from: storage)
        XCTAssertEqual(afterCheckbox.first?.block, .task(checked: false), "点一下勾选框：段落没变成任务项")

        // ⑥ 有序编号 —— 段落变成 `LIST_ORDERED`。
        surface.controller.toggleBlock(.ordered)
        let afterOrdered = NoteRichAttributes.spans(from: storage)
        XCTAssertEqual(afterOrdered.first?.block, .ordered, "点一下有序编号：段落没变成编号列表项")

        // ⑦ 无序编号 —— 段落变成 `LIST_UNORDERED`（圆点）。
        surface.controller.toggleBlock(.unordered)
        let afterBullet = NoteRichAttributes.spans(from: storage)
        XCTAssertEqual(afterBullet.first?.block, .bullet, "点一下无序编号：段落没变成圆点列表项")

        // **正文里不写标记**（契约不变量⑤：编号由渲染层生成、不落库）。
        let typing = textView.string
        for marker in ["1.", "2.", "- ", "☐", "[]", "[x]"] {
            XCTAssertFalse(typing.contains(marker), "正文里冒出了块级标记 \(marker)：\(typing)")
        }
        XCTAssertEqual(typing, "甲乙丙", "块级动作不改正文文字")
        print("📄 WY-1b2 ② 块级：勾选=\(String(describing: afterCheckbox.first?.block))"
            + " ／ 有序=\(String(describing: afterOrdered.first?.block))"
            + " ／ 无序=\(String(describing: afterBullet.first?.block)) ／ 正文=\"\(typing)\"")

        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: 判据 ③ 勾选 ⇒ 退出重开仍在

    @MainActor
    func testBlockProbeCheckedSurvivesReopen() throws {
        let surface = try makeSurface(text: "任务项")
        let textView = surface.textView
        let storage = try XCTUnwrap(textView.textStorage, "富文本面必须有 `NSTextStorage`")
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        // 勾选框 + 勾一下。
        surface.controller.toggleBlock(.checkbox)
        surface.controller.setChecked(true)
        let live = NoteRichAttributes.spans(from: storage)
        XCTAssertEqual(live.first?.block, .task(checked: true), "点一下勾选：段落的勾选态没落上")

        // **退出重开**（本片口径）：重新编解码一块面 —— 交换面（`NoteBody` JSON）往返。
        let data = try JSONEncoder().encode(NoteBody(spans: live))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"LIST_CHECKBOX\""), "交换面里没有 `LIST_CHECKBOX`：\(json)")
        XCTAssertTrue(json.contains("\"checked\":true"), "交换面里没有勾选态：\(json)")
        let reopened = try JSONDecoder().decode(NoteBody.self, from: data)
        XCTAssertEqual(
            reopened.spans.first?.block, .task(checked: true),
            "退出重开（往返）之后勾选态丢了 —— 「勾选状态落盘」不成立"
        )

        // **重挂一次编辑面**：把重开回来的 spans 重新换算成富文本，再从富文本读回 span 树。
        let base = textView.font ?? Theme.nsFont(.mono)
        let reattached = NoteRichAttributes.spans(
            from: NoteRichAttributes.attributed(from: reopened.spans, font: base)
        )
        XCTAssertEqual(
            reattached.first?.block, .task(checked: true),
            "重挂编辑面之后勾选态丢了（富文本换算这一环没带上块级）"
        )
        print("📄 WY-1b2 ③ 勾选 → 重开：交换面=\(json) ／ 重挂后 block=\(String(describing: reattached.first?.block))")

        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: 判据 ④ 点正文即出（FR-NOTEUI-10）· 预览只读（FR-NOTEUI-12）

    /// **正文被按下 ⇒ `onActivate` 投出来**：在正文那块 `PreviewTextView` 上合成一次左键按下，
    /// 断言回调真的发生（`NotesPanel` 把它接到 `appState.beginEditingCurrentNote()` ⇒ 模式翻 `.edit`
    /// ⇒ 工具条出现 —— 那条端到端由 `NotesLayoutProbeTests.testR3R4ClickOnPreviewBodyEntersEditing` 判，
    /// 这里判的是**本件这一跳**）。
    @MainActor
    func testBlockProbePreviewBodyTurnsPressIntoActivation() throws {
        var fired = false
        let live = UISnapshot.LiveHost(
            NotePreviewBody(text: "预览正文", onActivate: { fired = true })
                .frame(width: 480, height: 200),
            size: CGSize(width: 520, height: 240),
            scheme: .light
        )
        let body = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: PreviewTextView.self, in: live.hosting).first,
            "预览态里那块 `PreviewTextView` 没量到 —— 判据的入口没了"
        )
        XCTAssertFalse(body.isEditable, "FR-NOTEUI-12：预览态那块正文必须是只读的（`isEditable == false`）")

        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 8, y: 8),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ),
            "`NSEvent.mouseEvent` 没造出来 ⇒ 这一条判据的输入没了"
        )
        body.mouseDown(with: event)
        XCTAssertTrue(fired, "在预览正文上按下鼠标，`onActivate` 没投出来 —— 点正文进编辑那条线断了")
        print("📄 WY-1b2 ④ 预览正文：isEditable=\(body.isEditable) ／ 按下 ⇒ onActivate=\(fired)")

        UISnapshot.finishManifestIfEnabled()
    }

    /// **工具条只在编辑态出现 · 预览态那块可编辑面不在**（`FR-NOTEUI-12` / 判据 ④）。
    @MainActor
    func testBlockProbePreviewHidesToolbarAndEditSurface() throws {
        let host = makeEditorHost()

        // 源锚点：工具条只画在 `editorMode == .edit` 那一支；正文按下接的是「进编辑」。
        let source = try notesPanelSource()
        for anchor in [
            "if appState.editorMode == .edit {",
            "NotesEditorToolbar(controller: richController)",
            "onActivate: { appState.beginEditingCurrentNote() }",
        ] {
            XCTAssertTrue(source.contains(anchor), "`NotesPanel.swift` 里找不到「\(anchor)」—— 入口判据的接线掉了")
        }

        // 渲染级：预览态 ⇒ 只读预览面在场、可编辑富文本面不在场。
        host.state.editorMode = .preview
        host.state.noteEditorBody = "预览正文"
        let previewLive = UISnapshot.LiveHost(editorSurface(host), size: Self.editorSize, scheme: .light)
        let previewBodies = UISnapshot.LiveHost<Never>.findViews(ofType: PreviewTextView.self, in: previewLive.hosting)
        let previewEditables = UISnapshot.LiveHost<Never>.findViews(ofType: NotesTextView.self, in: previewLive.hosting)
        XCTAssertEqual(previewBodies.count, 1, "预览态应当恰好一块只读预览面（实测 \(previewBodies.count)）")
        XCTAssertFalse(previewBodies.first?.isEditable ?? true, "预览态正文不是只读的（`isEditable` 还是 true）")
        XCTAssertEqual(
            previewEditables.count, 0,
            "预览态里出现了可编辑富文本面（\(previewEditables.count) 块）—— 预览不该可编辑"
        )

        // 对照：编辑态 ⇒ 可编辑富文本面在场（否则「预览态没有」可能是这套遍历看不见）。
        host.state.editorMode = .edit
        let editLive = UISnapshot.LiveHost(editorSurface(host), size: Self.editorSize, scheme: .light)
        let editEditables = UISnapshot.LiveHost<Never>.findViews(ofType: NotesTextView.self, in: editLive.hosting)
        XCTAssertEqual(
            editEditables.count, 1,
            "编辑态里没有那块可编辑富文本面（实测 \(editEditables.count) 块）⇒ 预览态那条对照不成立"
        )
        print("📄 WY-1b2 ④ 预览态：只读面 \(previewBodies.count) 块（isEditable="
            + "\(String(describing: previewBodies.first?.isEditable))）／ 可编辑面 \(previewEditables.count) 块"
            + " ｜ 编辑态：可编辑面 \(editEditables.count) 块")

        UISnapshot.finishManifestIfEnabled()
    }

    // MARK: - 片 `WY-1b2` 的渲染辅助（判据 ①-d / ④ 用真 `NotesEditorView`）

    private typealias EditorHost = (
        state: AppState, workspace: WorkspaceStore, tabs: WorkspaceTabsModel, terminal: TerminalModel
    )

    private static let editorSize = CGSize(width: 700, height: 460)

    /// 工具条那一带（像素，2× 渲染）：与 `NotesEditorSaveProbeTests` 同一条按本机实测定的带。
    private static let toolbarBandToTop = 100

    @MainActor
    private func makeEditorHost() -> EditorHost {
        let scratch = UISnapshot.outputDirectory.deletingLastPathComponent()
            .appendingPathComponent("notes-format-probe-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let historyURL = scratch.appendingPathComponent("workspace-history-\(UUID().uuidString).json")
        return (
            AppState(),
            WorkspaceStore.shared,
            WorkspaceTabsModel(store: WorkspaceHistoryStore(fileURL: historyURL)),
            TerminalModel()
        )
    }

    @MainActor
    private func editorSurface(_ host: EditorHost) -> some View {
        ZStack {
            Theme.surface(.window)
            NotesEditorView()
        }
        .frame(width: Self.editorSize.width, height: Self.editorSize.height)
        .snapshotEnvironment(
            state: host.state,
            workspace: host.workspace,
            tabs: host.tabs,
            terminal: host.terminal
        )
    }

    /// 一个视图的下边缘离宿主顶边多远（pt；宿主是 SwiftUI 的 `NSHostingView`，通常是翻转的）。
    private func topDistance(of view: NSView, in hosting: NSView) -> CGFloat {
        let rect = hosting.convert(view.bounds, from: view)
        return hosting.isFlipped ? rect.minY : hosting.bounds.height - rect.maxY
    }
}
