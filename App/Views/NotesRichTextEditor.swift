import AppKit
import SwiftUI
import DoyahCore

/// 笔记正文的**富文本编辑面**（片 `WY-1b1` · 派单 `T-20261009-045` / `-048` · `FR-NOTEUI-11`）。
///
/// ## 这一件做什么
///
/// 编辑态正文原先是一块纯文本 SwiftUI `TextEditor`（`NotesPanel.swift` 的 `.edit` 那一支）——
/// 正文里能看见 `**` / `#` 这些**标记本身**，样式不是「即时呈现」的。本片把它换成**富文本面**：
/// 一块真 `NSTextView`（`NotesTextView`），正文里的行内标记在**装进来时**就解析成属性、标记不再露出；
/// 工具条上那**行内四枚**（粗体 / 斜体 / 下划线 / 笔刷=荧光笔淡黄）直接作用在选区（或光标所在词）上，
/// 改的是 `NSTextStorage` 的属性，所见即所得。
///
/// ## 为什么落在新文件（而不是复用 `EditorSurface.swift`）
///
/// `App/Views/EditorSurface.swift` 只是 `extension View` 上一个 `.editorSurface()` 修饰器
/// （编辑面底色的唯一出处），不是承载件。这一件是**新写的承载视图**：`NSViewRepresentable` 包
/// `NotesTextView`（`NSTextView` 子类）。卡上「已有 `EditorSurface` 承载」那句是**写错的指代**，
/// 组长裁决（2026-10-09 08:2x）明确「以新文件为准」。
///
/// ## 与权威源的关系（本片的边界）
///
/// 权威源是 `NoteSpan` 树（片 `WY-1a`）。本片只做「**面**」：绑定进出的仍是**纯文本投影**
/// （`appState.noteEditorBody`，Markdown 串），四枚按钮改的是内存里那块富文本的属性 ——
/// **落库（`writeNoteEditor` → `setNoteSpans`）不并入本片**（组长裁决第 4 条：归 `WY-2`）。
/// 因此 `bold` / `italic` / `code` 经投影往返仍无损（Markdown 表达得了），而
/// `underline` / `backgroundColor` 是**新字段**（片 `WY-1b1` 加进 `NoteSpan`），Markdown 表达不了 ⇒
/// 落库那条路接上之前**只存在编辑面这一块内存里**。这一段边界是刻意的，写在 `NoteSpan` 头注释里。
///
/// ## 行号列
///
/// 笔记正文是**富文本面**、不是代码，「行号」在这里没有意义 ⇒
/// `Scripts/editor-line-number-surfaces.json` 里登记 `NotesTextView` 为 `hasGutter: false` + 理由。
/// 底色 / 字色仍走 `Theme` 令牌（与另两个 AppKit 编辑面同一档）。
///
/// ## 跑法
///
/// `env DOYAH_UI_SNAPSHOT=1 bash Scripts/run-manual-verification-probes.sh --filter NotesEditor`
/// 或 `env DOYAH_UI_SNAPSHOT=1 swift test --filter NotesEditorFormatProbeTests`。

/// 行内四枚的**命令词表**（片 `WY-1b1`）。
///
/// 工具条那四枚按钮与机器判据读的是**同一份** `rawValue` / 图标 / 文案键 —— 两处各写一遍
/// （「图标住这里、命令名住那里」）迟早对不上，于是收成一个 `CaseIterable` 枚举。
enum NoteInlineCommand: String, CaseIterable, Sendable {
    case bold
    case italic
    case underline
    case highlight

    /// SF Symbols 名（纯图标按钮：名字只由悬停提示给，见 `NotesEditorToolbar`）。
    var symbolName: String {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .underline: return "underline"
        case .highlight: return "highlighter"
        }
    }

    /// 悬停名字（语言表键；中英齐备）。
    var titleKey: LKey {
        switch self {
        case .bold: return .notesFormatBold
        case .italic: return .notesFormatItalic
        case .underline: return .notesFormatUnderline
        case .highlight: return .notesFormatHighlight
        }
    }
}

/// 富文本面里承载行内样式的**私有属性键**。
///
/// 为什么不只用系统属性判读：粗体 / 斜体靠 `NSFont` 的 trait，而等宽族未必每一档都真有变体
/// （`NSFontManager` 转换不出来时会原样退回）—— 那样「点一下粗体」就会静默失效，判据也判不动。
/// 于是**判读**走这里这几个键（点过就一定在），**呈现**仍走系统属性（`.font` / `.underlineStyle` /
/// `.backgroundColor`，即用户看得见的那一层）。两个方向各自成立、互不牵连。
extension NSAttributedString.Key {
    static let doyahBold = NSAttributedString.Key("com.doyah.note.bold")
    static let doyahItalic = NSAttributedString.Key("com.doyah.note.italic")
    static let doyahUnderline = NSAttributedString.Key("com.doyah.note.underline")
    static let doyahCode = NSAttributedString.Key("com.doyah.note.code")
}

/// span 树 ↔ `NSAttributedString` 的**唯一换算处**（片 `WY-1b1`）。
///
/// 换算只做两件事：把 `spans` 的样式落成属性（装进来 / 落库那条路）、把属性读回 `spans`
/// （投影回 `appState.noteEditorBody`）。**不解析任何标记** —— 解析仍是
/// `NoteBodyProjection.parseInline`（唯一出处，见 `check-markdown-single-source.py`）。
enum NoteRichAttributes {

    /// 荧光笔底色的 `NSColor`（唯一色值出处 = `NoteHighlight`）。
    static func highlightColor() -> NSColor { Theme.nsColor(hex: NoteHighlight.rgb) }

    /// 基准字体 + trait → 实际字体。
    ///
    /// `NSFontManager.convert(_:toHaveTrait:)` 对没有该变体的族会原样退回 —— 所以「能不能显出粗」
    /// 不是判读依据（判读走私有属性键），这里只是**尽量**把样子画对。
    static func traitFont(_ base: NSFont, bold: Bool, italic: Bool) -> NSFont {
        var font = base
        let manager = NSFontManager.shared
        if bold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    /// span 树 → 富文本（行内样式落到属性上；标记不出现）。
    static func attributed(from spans: [NoteSpan], font base: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for span in spans {
            let bold = span.styles.contains(.bold)
            let italic = span.styles.contains(.italic)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: traitFont(base, bold: bold, italic: italic),
            ]
            if bold { attributes[.doyahBold] = true }
            if italic { attributes[.doyahItalic] = true }
            if span.styles.contains(.underline) {
                attributes[.doyahUnderline] = true
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if span.styles.contains(.code) { attributes[.doyahCode] = true }
            if span.backgroundColor != nil { attributes[.backgroundColor] = highlightColor() }
            result.append(NSAttributedString(string: span.text, attributes: attributes))
        }
        return result
    }

    /// 富文本 → span 树（按属性 run 切；空串不产出空 span）。
    static func spans(from attributed: NSAttributedString) -> [NoteSpan] {
        var spans: [NoteSpan] = []
        let length = attributed.length
        var index = 0
        while index < length {
            var runRange = NSRange(location: index, length: 0)
            let attributes = attributed.attributes(at: index, effectiveRange: &runRange)
            let text = (attributed.string as NSString).substring(with: runRange)
            var styles: Set<NoteSpan.Style> = []
            if attributes[.doyahBold] != nil { styles.insert(.bold) }
            if attributes[.doyahItalic] != nil { styles.insert(.italic) }
            if attributes[.doyahUnderline] != nil { styles.insert(.underline) }
            if attributes[.doyahCode] != nil { styles.insert(.code) }
            let background = attributes[.backgroundColor] != nil ? NoteHighlight.backgroundColorHex : nil
            spans.append(NoteSpan(text: text, styles: styles, backgroundColor: background))
            guard runRange.length > 0 else { break }
            index = runRange.location + runRange.length
        }
        return spans
    }

    /// 富文本 → **Markdown 投影**（写回 `appState.noteEditorBody` 的那一份）。
    static func markdown(from attributed: NSAttributedString) -> String {
        NoteBodyProjection.markdown(from: spans(from: attributed))
    }
}

/// **笔记正文的富文本编辑面**（`NSViewRepresentable` 包 `NotesTextView`）。
struct NotesRichTextEditor: NSViewRepresentable {

    /// 正文的**纯文本投影**（Markdown 串）—— 与 `TextEditor` 时代同一个绑定，一字未改写路。
    @Binding var text: String

    /// 行内四枚按钮作用的**唯一出口**（工具条与本视图登记的是同一个实例）。
    let controller: NotesRichTextController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NotesTextView()
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        // 尺寸口径与 `NSTextView.scrollableTextView()` 一致（与 `NotePreviewBody` 同款）。
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        configure(textView)
        textView.delegate = context.coordinator
        context.coordinator.install(text: text, into: textView)
        controller.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NotesTextView else { return }
        context.coordinator.parent = self
        // 回调可能随视图重建换人（工具条与本视图登记的是同一个控制器）⇒ 每次更新都重申一次。
        controller.textView = textView
        configure(textView)
        context.coordinator.install(text: text, into: textView)
    }

    /// 底色 / 字色走**主题令牌**（与另两个 AppKit 编辑面同一档；`check-editor-surface-tokens.py` 的 D 组判这一条）。
    private func configure(_ textView: NotesTextView) {
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = Theme.nsColor(Surface.content)
        textView.textColor = Theme.nsColor(TextTone.primary)
        textView.insertionPointColor = Theme.nsColor(TextTone.primary)
        textView.font = Theme.nsFont(.mono)
        textView.textContainerInset = NSSize(width: Spacing.s, height: Spacing.s)
    }

    /// 与 `NSTextViewDelegate` 之间的桥：**用户敲键 ⇒ 投影回绑定**。
    final class Coordinator: NSObject, NSTextViewDelegate {

        var parent: NotesRichTextEditor

        init(_ parent: NotesRichTextEditor) {
            self.parent = parent
        }

        /// 把绑定里的文本装进富文本面（**只在需要时**重装 —— 见下）。
        ///
        /// 为什么要比一次：敲键那条路是「属性 → Markdown → 绑定 → SwiftUI 更新 → 这里」的环，
        /// 无条件重装会把用户的光标位置与刚上的样式一起抹掉（`L-50` 同族：多做一步反而坏）。
        /// 比较的两边都是**同一份投影函数**的产物，环就停在这里。
        func install(text: String, into textView: NotesTextView) {
            let current = NoteRichAttributes.markdown(from: textView.textStorage ?? NSAttributedString())
            guard current != text else { return }
            let base = textView.font ?? Theme.nsFont(.mono)
            let attributed = NoteRichAttributes.attributed(
                from: NoteBodyProjection.parseInline(text),
                font: base
            )
            textView.textStorage?.setAttributedString(attributed)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NotesTextView else { return }
            let markdown = NoteRichAttributes.markdown(from: textView.textStorage ?? NSAttributedString())
            if parent.text != markdown { parent.text = markdown }
        }
    }
}

/// **编辑态正文那块 `NSTextView`**（片 `WY-1b1`）。
///
/// 除了「是富文本」这一条，它还持有行内四枚的**动作本体**（`apply(_:)`）—— 工具条那四枚按钮
/// 经 `NotesRichTextController` 转到这里，机器判据也从这里驱动（同一入口，见 `NotesRichTextController`）。
final class NotesTextView: NSTextView {

    /// 施加一条行内命令：作用在**选区**；选区为空时作用在**光标所在词**上。
    func apply(_ command: NoteInlineCommand) {
        let range = targetRange()
        guard range.length > 0 else { return }
        switch command {
        case .bold:
            toggleFontTrait(.boldFontMask, key: .doyahBold, in: range)
        case .italic:
            toggleFontTrait(.italicFontMask, key: .doyahItalic, in: range)
        case .underline:
            toggleUnderline(in: range)
        case .highlight:
            toggleHighlight(in: range)
        }
        // 让「这一面被改过」这件事走产品的同一条路（撤销栈 / 绑定投影 / 脏标记）。
        didChangeText()
    }

    // MARK: - 目标范围

    private func targetRange() -> NSRange {
        let selection = selectedRange()
        if selection.length > 0 { return selection }
        return wordRange(at: selection.location)
    }

    private func wordRange(at location: Int) -> NSRange {
        let ns = string as NSString
        let length = ns.length
        guard length > 0 else { return NSRange(location: location, length: 0) }
        var start = min(max(location, 0), length)
        var end = start
        while start > 0, Self.isWordCharacter(ns.character(at: start - 1)) { start -= 1 }
        while end < length, Self.isWordCharacter(ns.character(at: end)) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func isWordCharacter(_ value: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(value) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || CharacterSet.letters.contains(scalar)
    }

    // MARK: - 三条行内动作

    private func toggleFontTrait(_ mask: NSFontTraitMask, key: NSAttributedString.Key, in range: NSRange) {
        guard let storage = textStorage else { return }
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let turningOff = storage.attribute(key, at: range.location, effectiveRange: nil) != nil
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let base = (value as? NSFont) ?? self.font ?? Theme.nsFont(.mono)
            let manager = NSFontManager.shared
            let converted = turningOff
                ? manager.convert(base, toNotHaveTrait: mask)
                : manager.convert(base, toHaveTrait: mask)
            storage.addAttribute(.font, value: converted, range: subrange)
            if turningOff {
                storage.removeAttribute(key, range: subrange)
            } else {
                storage.addAttribute(key, value: true, range: subrange)
            }
        }
        storage.endEditing()
    }

    private func toggleUnderline(in range: NSRange) {
        guard let storage = textStorage else { return }
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let turningOff = storage.attribute(.doyahUnderline, at: range.location, effectiveRange: nil) != nil
        storage.beginEditing()
        if turningOff {
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.doyahUnderline, range: range)
        } else {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            storage.addAttribute(.doyahUnderline, value: true, range: range)
        }
        storage.endEditing()
    }

    private func toggleHighlight(in range: NSRange) {
        guard let storage = textStorage else { return }
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let turningOff = storage.attribute(.backgroundColor, at: range.location, effectiveRange: nil) != nil
        storage.beginEditing()
        if turningOff {
            storage.removeAttribute(.backgroundColor, range: range)
        } else {
            storage.addAttribute(
                .backgroundColor,
                value: NoteRichAttributes.highlightColor(),
                range: range
            )
        }
        storage.endEditing()
    }
}

/// 工具条那**行内四枚**与编辑面之间的**唯一接线**（片 `WY-1b1`）。
///
/// 为什么不让工具条直接去够 `NSResponder` / 焦点链：那一路上「当前编辑面是谁」是**运行期事实**，
/// 判据够不着、也会在视图重建时悄悄失效。这里由 `NotesRichTextEditor` 在 `make` / `update` 时
/// 登记编辑面，方向是**明确的、可断言的**；按钮与判据都从 `toggle(_:)` 走同一条路。
@MainActor
final class NotesRichTextController: ObservableObject {

    /// 当前编辑面（视图重建会换人 —— 登记处每次都重申）。
    weak var textView: NotesTextView?

    /// 「有编辑面接着」——按钮该不该可点（没有编辑面时点下去什么都不发生，那就是静默无反应）。
    var isReady: Bool { textView != nil }

    func toggle(_ command: NoteInlineCommand) {
        textView?.apply(command)
    }
}
