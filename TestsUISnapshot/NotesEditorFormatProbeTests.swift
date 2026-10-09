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
    ///
    /// **片 `WY-2a`**：`NotesRichTextEditor` 多了权威源那个绑定（`spans`）—— 这里留空，
    /// 于是装内容走的是「按 Markdown 投影解析」那一档（本文件前面三条判据量的就是它）。
    private struct Mounted: View {
        @State var bodyText: String
        @State var spans: [NoteSpan] = []
        var controller: NotesRichTextController

        var body: some View {
            NotesRichTextEditor(text: $bodyText, spans: $spans, controller: controller)
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

    // MARK: - 片 `WY-2a`：编辑器写路径端到端落库（本片主判据）

    /// 「夹具要写笔记库」的前置（与 `NotesLayoutProbeTests` 同一条纪律：`DOYAH_NOTES_DIR` 不在场就跳过
    /// —— 探针**绝不**往真实用户数据家里写夹具）。
    private func requireIsolatedNotesDirectory() throws {
        try XCTSkipIf(
            (ProcessInfo.processInfo.environment["DOYAH_NOTES_DIR"] ?? "").isEmpty,
            "本用例要往笔记库写夹具 ⇒ 必须在临时数据家里跑（`DOYAH_NOTES_DIR` 没设就跳过）—— "
                + "取证脚本 `Scripts/run-manual-verification-probes.sh` 会设它"
        )
        // 直跑（`swift test --filter ...`）时那个目录还没人建（取证脚本会建）—— 这里补一次：
        // 不然 SQLite 报 `CANTOPEN`，会把「目录不存在」误读成「写不进去」。
        try FileManager.default.createDirectory(
            at: NoteLibrary.defaultDirectory(), withIntermediateDirectories: true
        )
    }

    /// **本片主判据（端到端）**：编辑面里改出**两处 span 级差异** ——
    /// ① 「加粗」那一段加粗 · ② 整段挂勾选框并**勾上**（`checked=true`）—— ⇒ 触发保存 ⇒
    /// **重新从库读回**（另开一个 `NoteLibrary` 实例、读同一条）⇒ 两处**同值仍在**；
    /// 再「退出重开」一次（`edit(_:)` 把这一条重新装进编辑器）⇒ 权威源**还是那一棵**。
    ///
    /// ## 改前反例的读数（同一条用例里先量一份，不给说法给读数）
    ///
    /// 改前 `writeNoteEditor` 的落库动作**只有** `upsert`（`body` 列），**一处 `setNoteSpans` 都没有**
    /// ⇒ 两处差异一个都留不住：
    ///   · ① 加粗：Markdown 表达得了 ⇒ `body` 里剩下 `**` 标记，但 **`spans` 列是 `NULL`**（权威源根本没写）；
    ///   · ② 勾选框 / 勾选态：Markdown **没有形状** ⇒ `body` 里连痕迹都没有，读回来这一档**根本不存在**
    ///     （不是「读出来是 false」）；
    ///   · 同理下划线 / 荧光底色（片 `WY-1b1` 加的两个字段）：只在内存里。
    /// 反例那一半由 `testWY2aOldWritePathLosesEverySpanLevelDifference` 单独钉住。
    @MainActor
    func testWY2aEditorSaveWritesSpansAndTheySurviveReopen() async throws {
        try requireIsolatedNotesDirectory()
        let host = makeEditorHost()
        let load = try UISnapshot.applyLicense(.standard, to: host.state)
        XCTAssertEqual(load.entitlements.basis, .licensed, "临时许可证没落地 ⇒ 下面读不到笔记能力")
        XCTAssertTrue(host.state.notesEnabled, "Standard 档必须带笔记能力（capabilities.notes）")

        // ── 编辑面：真 `NotesEditorView`（`editorMode == .edit` 那一支），拿里面的 `NotesTextView` ──
        host.state.editorMode = .edit
        host.state.noteEditorTitle = "WY-2a 端到端"
        let live = UISnapshot.LiveHost(editorSurface(host), size: Self.editorSize, scheme: .light)
        let textView = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: NotesTextView.self, in: live.hosting).first,
            "编辑态里那块可编辑富文本面没量到 —— 端到端那条路的入口没了"
        )
        let storage = try XCTUnwrap(textView.textStorage, "富文本面必须有 `NSTextStorage`")

        // 在**编辑面本体**上改出那两处差异（与 `NotesTextView.apply(_:)` / `applyBlock(_:)` 落的
        // 是同一批私有属性键；离屏宿主里 SwiftUI `Button` 派发不了点击，这条边界与 WY-1b1/WY-1b2 同一条）。
        textView.string = "加粗 任务项"
        let paragraph = NSRange(location: 0, length: ("加粗 任务项" as NSString).length)
        storage.beginEditing()
        storage.addAttribute(.doyahBold, value: true, range: NSRange(location: 0, length: 2))
        storage.addAttribute(
            .doyahBlock, value: NoteSpan.Block.task(checked: true).exchangeType, range: paragraph
        )
        storage.addAttribute(.doyahChecked, value: true, range: paragraph)
        storage.endEditing()
        // 让「这一面被改过」走产品的同一条路（撤销栈 / 绑定回推 / 脏标记）。
        textView.didChangeText()
        live.pump(0.3)

        // **接线那一跳**：编辑面改出来的那棵树必须真的回推到了 `AppState`（写库那条路读的是它）。
        XCTAssertTrue(
            host.state.noteEditorSpans.contains { $0.styles.contains(.bold) },
            "① 加粗那一棵没回推到 `AppState.noteEditorSpans` ⇒ 写库那条路拿不到权威源"
        )
        XCTAssertTrue(
            host.state.noteEditorSpans.contains { $0.block == .task(checked: true) },
            "② 勾选框（已勾）那一棵没回推到 `AppState.noteEditorSpans`"
        )
        XCTAssertEqual(
            host.state.noteEditorBody, "**加粗** 任务项",
            "`body` 必须是由那棵树派生的**单向投影**（块级不产出标记）"
        )

        // ── 触发保存（手动「保存」= 产品里那条唯一写路） ──
        await host.state.saveNoteFromEditor()
        await live.pumpAsync(seconds: 0.3)

        // ── 重新从库读回（**另一个** `NoteLibrary` 实例、同一条） ──
        let library = NoteLibrary.defaultLibrary()
        let reopened = try await library.load()
        let saved = try XCTUnwrap(
            reopened.first { $0.title == "WY-2a 端到端" }, "保存之后库里读不到这一条（标题：WY-2a 端到端）"
        )
        let persisted = try await library.noteSpans(id: saved.id)
        let spansJSON = try XCTUnwrap(
            persisted, "`spans` 列是 `NULL` ⇒ 编辑面那一棵树**根本没落库**（正是改前那条写路的读数）"
        )
        XCTAssertTrue(spansJSON.contains("\"LIST_CHECKBOX\""), "交换面里没有块级字面量：\(spansJSON)")
        XCTAssertTrue(spansJSON.contains("\"checked\":true"), "勾选态没落库：\(spansJSON)")
        let decoded = try JSONDecoder().decode(NoteBody.self, from: Data(spansJSON.utf8))
        XCTAssertTrue(decoded.spans.contains { $0.styles.contains(.bold) }, "① 加粗读回来没了")
        XCTAssertTrue(
            decoded.spans.contains { $0.block == .task(checked: true) }, "② 勾选框 / 勾选态读回来没了"
        )
        // **两列同一份**：落库的 `body` 恒等于那棵树的投影（`NoteBody.body` 同一个函数）。
        XCTAssertEqual(saved.body, decoded.body, "落库的 `body` 不是 `spans` 那一棵树的投影 ⇒ 两列各说各话")
        XCTAssertEqual(decoded.body, "**加粗** 任务项", "投影与编辑面上那一份对不上：\(decoded.body)")

        // ── 退出重开（界面那一侧的人令：「重开仍在」） ──
        // 重新打开这一条 ⇒ 编辑面按**权威源**重挂（`loadEditorSpans`），不是按 Markdown 投影重新解析
        // —— 后者会把块级 / 下划线 / 底色静默抹掉。
        host.state.edit(saved)
        await host.state.awaitPendingNoteSpansLoad()
        XCTAssertTrue(
            host.state.noteEditorSpans.contains { $0.block == .task(checked: true) },
            "退出重开之后编辑面里勾选框丢了 —— 「重开仍在」不成立"
        )
        XCTAssertTrue(
            host.state.noteEditorSpans.contains { $0.styles.contains(.bold) }, "退出重开之后加粗丢了"
        )
        print(
            "📄 WY-2a 主判据：spans 列 = \(spansJSON)"
                + " ／ 读回 block=\(String(describing: decoded.spans.first { $0.block != nil }?.block))"
                + " ／ body 投影 = 「\(decoded.body)」／ 重开后编辑面 spans = \(host.state.noteEditorSpans.count) 棵"
        )

        UISnapshot.finishManifestIfEnabled()
    }

    /// **改前反例**（本片主判据的反面读数）：**只经 `upsert` 的那条旧写路** —— 那正是改前
    /// `writeNoteEditor` 的全部落库动作 —— 两处 span 级差异**一个都留不住**：
    ///
    ///   · `spans` 列：`NULL`（权威源根本没写）；
    ///   · 正文解回来（`parseInline`，与编辑面装进来**同一个函数**）：加粗那一档 Markdown 表达得了
    ///     ⇒ 还剩一个 span；**块级（勾选框）与 `checked` 一档整个不存在**；下划线 / 底色同理。
    ///
    /// 这一条不是「再跑一遍同样的判据」，它是**反面**：没有本片这一笔，上面那条主判据的第二、三句
    /// 一个字都立不住。
    @MainActor
    func testWY2aOldWritePathLosesEverySpanLevelDifference() async throws {
        try requireIsolatedNotesDirectory()
        // 前置：许可证不给也行（这一条只碰存储层），但库要落在临时家里（上面那句守卫已把住）。
        let library = NoteLibrary.defaultLibrary()
        let legacy = try await library.upsert(
            NoteDraft(title: "WY-2a 反例·只写 body", body: "**加粗** 任务项")
        )
        let legacySpans = try await library.noteSpans(id: legacy.id)
        XCTAssertNil(
            legacySpans,
            "反例前置：只写 `body` 的旧写路下 `spans` 列应当是 `NULL`（它从来不碰这一列）"
        )

        let reparsed = NoteBodyProjection.parseInline(legacy.body)
        XCTAssertTrue(
            reparsed.contains { $0.styles.contains(.bold) },
            "反例·① 加粗：Markdown 表达得了 ⇒ 正文里还留着 `**`，读回来只剩这一档"
        )
        XCTAssertFalse(
            reparsed.contains { $0.block != nil },
            "反例·② 勾选框 / 勾选态：Markdown 没有形状 ⇒ 旧写路下这一档**根本不存在**（丢了，不是 false）"
        )
        XCTAssertFalse(
            reparsed.contains { $0.styles.contains(.underline) },
            "反例·③ 下划线（片 `WY-1b1` 的字段）：同样只在内存里，读不回来"
        )
        XCTAssertFalse(
            reparsed.contains { $0.backgroundColor != nil },
            "反例·④ 荧光底色：同上"
        )
        print(
            "📄 WY-2a 反例（只写 body）：spans 列 = nil ／ 正文解回来 —— 粗=\(reparsed.contains { $0.styles.contains(.bold) })"
                + " ／ 块级=\(reparsed.contains { $0.block != nil }) ／ 下划线="
                + "\(reparsed.contains { $0.styles.contains(.underline) }) ／ 底色="
                + "\(reparsed.contains { $0.backgroundColor != nil })"
        )

        UISnapshot.finishManifestIfEnabled()
    }

    /// **判据：单一写入口**（片 `WY-2a`）—— 全仓写 `note.spans` 列的地方**只有** `NoteDatabase.setNoteSpans`
    /// 一处。三层机械检查（都在源上，不靠人眼）：
    ///   ① 全仓 `.swift` 里出现「把 `spans` 列写下去」那个 SQL 形状（`spans = ?`）的文件**只有**
    ///      `Core/NoteStorage/NoteDatabase.swift`；
    ///   ② 那一处落在 `setNoteSpans` 的函数体里（不是散在别的语句里）；
    ///   ③ `note` 的 `INSERT` 列表里**没有** `spans`（新建那条路也不许各写一份 —— 正文只从写入口进）。
    @MainActor
    func testWY2aSpansColumnHasExactlyOneWriter() throws {
        let sources = Self.allSwiftSources()
        XCTAssertGreaterThan(sources.count, 100, "仓里扫到的 `.swift` 只有 \(sources.count) 份 —— 扫描面太小，判据不成立")

        let writers = sources.filter { $0.text.contains("spans = ?") }.map(\.path).sorted()
        XCTAssertEqual(
            writers, ["Core/NoteStorage/NoteDatabase.swift"],
            "写 `spans` 列的地方不止一处：\(writers)"
        )

        let database = try XCTUnwrap(
            sources.first { $0.path == "Core/NoteStorage/NoteDatabase.swift" }?.text,
            "读不到 `NoteDatabase.swift`"
        )
        // ② 那一处必须在 `setNoteSpans` 的函数体里。
        let body = try XCTUnwrap(Self.functionBody(named: "setNoteSpans", in: database), "找不到 `setNoteSpans` 的函数体")
        XCTAssertTrue(body.contains("spans = ?"), "写 `spans` 的那句不在 `setNoteSpans` 的函数体里")
        XCTAssertEqual(
            database.components(separatedBy: "spans = ?").count - 1, 1,
            "`NoteDatabase.swift` 里 `spans = ?` 出现了不止一次"
        )
        // ③ `note` 的 INSERT 列清单里没有 `spans`（新建那条路也走同一个写入口）。
        let insert = try XCTUnwrap(Self.insertColumnList(of: "note", in: database), "找不到 `note` 的 INSERT 列清单")
        XCTAssertFalse(insert.contains("spans"), "`note` 的 INSERT 列清单里出现了 `spans`：\(insert)")

        let callSites = sources
            .filter { $0.text.contains(".setNoteSpans(") }
            .map(\.path).sorted()
        print("📄 WY-2a 单一写入口：`spans = ?` 在 \(writers) ／ `setNoteSpans` 全仓命中 \(callSites)")

        UISnapshot.finishManifestIfEnabled()
    }

    /// 仓里所有 `.swift` 源文件（相对路径 + 内容）—— 跳过 `.build` / `.git`（构建产物不是源）。
    private static func allSwiftSources() -> [(path: String, text: String)] {
        var found: [(String, String)] = []
        guard let walker = FileManager.default.enumerator(at: repositoryRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        for case let url as URL in walker {
            let relative = url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
            if relative.hasPrefix(".build") || relative.hasPrefix(".git") {
                walker.skipDescendants()
                continue
            }
            guard url.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            found.append((relative, text))
        }
        return found
    }

    /// 从 `func <name>(` 起、到下一个顶层 `\n    func `（或 `\n    }`）为止的那段源文本。
    private static func functionBody(named name: String, in source: String) -> String? {
        guard let start = source.range(of: "func \(name)(") else { return nil }
        let rest = source[start.lowerBound...]
        for terminator in ["\n    // MARK: ", "\n    /// ", "\n    @discardableResult", "\n    public func ", "\n    private func ", "\n    func "] {
            if let end = rest.range(of: terminator) {
                return String(rest[..<end.lowerBound])
            }
        }
        return String(rest)
    }

    /// `INSERT INTO <table> ( ... )` 的那一段列清单。
    private static func insertColumnList(of table: String, in source: String) -> String? {
        guard let start = source.range(of: "INSERT INTO \(table) (") else { return nil }
        let rest = source[start.upperBound...]
        guard let end = rest.firstIndex(of: ")") else { return nil }
        return String(rest[..<end])
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
