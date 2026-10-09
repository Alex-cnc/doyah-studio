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
}
