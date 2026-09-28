import SwiftUI
import AppKit
import DoyahCore

/// 工作区的**代码编辑器**（FR-EDIT-36）：按语言着色 + 补全 + ⌘S 保存。
///
/// 与 SQL 编辑器（`SQLEditorView`）的关系：**同一个套路、不同的语言层**。
/// SQL 编辑器那套多光标 / 列选择 / 诊断下划线是 SQL 专用能力，这里不搬过来
/// （工作区编辑器的第一版目标是"能读能改能存"，把功能堆满反而不好验）。
struct CodeEditorView: NSViewRepresentable {
    let tabID: UUID
    let text: String
    let language: TextLanguage
    var onTextChange: (String) -> Void
    var onSave: () -> Void

    /// 订阅字体偏好：偏好一变，SwiftUI 重跑 `updateNSView` → 编辑器换字体。
    @ObservedObject private var fonts = FontManager.shared

    static var baseFont: NSFont { Theme.nsFont(.mono) }
    static var keywordFont: NSFont {
        FontManager.shared.monospaceBoldNSFont(size: Theme.nsFont(.mono).pointSize)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CodeTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = Self.baseFont
        textView.textColor = Theme.nsColor(TextTone.primary)
        textView.backgroundColor = Theme.nsColor(Surface.content)
        textView.insertionPointColor = Theme.nsColor(TextTone.primary)
        textView.drawsBackground = true
        // 代码里不要"智能"替换：把 `"` 换成 `"`、把 `--` 换成 `—` 会直接改坏代码。
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 4
        textView.string = text
        textView.onSave = onSave
        // 行号列的宽度由「行数位数」定（`textContainerInset.width` 就是它的宽度），
        // 所以必须在**文本进去之后**算一次 —— 顺序反了会先按空文档算成 1 位。
        textView.reloadLineNumbers()

        context.coordinator.textView = textView
        context.coordinator.language = language
        textView.completionLanguage = language
        context.coordinator.applyHighlighting()

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        context.coordinator.parent = self
        textView.onSave = onSave
        let fontChanged = textView.font?.fontName != Self.baseFont.fontName
            || textView.font?.pointSize != Self.baseFont.pointSize
        if fontChanged {
            textView.font = Self.baseFont
        }
        // 切页签 / 外部改了内容：把文本同步过去（带上语言变化一起重着色）。
        let languageChanged = context.coordinator.language != language
        context.coordinator.language = language
        textView.completionLanguage = language
        let textChanged = textView.string != text
        if textChanged {
            context.coordinator.isApplyingExternalText = true
            textView.string = text
            context.coordinator.isApplyingExternalText = false
            context.coordinator.lastHighlightedText = nil
        }
        // 行号列：行数（位数）或字宽变了都要重排。字体换了也要重排 ——
        // 列宽是按「数字在当前等宽字体下的宽度」量出来的，不跟着换就会在换字号后偏窄/偏宽。
        if textChanged || fontChanged {
            textView.reloadLineNumbers()
        }
        if fontChanged || languageChanged || context.coordinator.lastHighlightedText != textView.string {
            context.coordinator.applyHighlighting()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        var language: TextLanguage
        weak var textView: CodeTextView?
        var lastHighlightedText: String?
        var isApplyingExternalText = false
        private var highlightWorkItem: DispatchWorkItem?

        init(_ parent: CodeEditorView) {
            self.parent = parent
            self.language = parent.language
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isApplyingExternalText else { return }
            // 行号列跟着内容走：行数（位数）与行起点都在这里重算 —— 打字、粘贴、撤销
            // 都会走到 `textDidChange`，所以这是唯一需要挂的钩子。
            textView.reloadLineNumbers()
            parent.onTextChange(textView.string)
            scheduleHighlighting()
        }

        /// 延后一次高亮：避免与输入法 / 文本编辑回调重入。
        func scheduleHighlighting() {
            highlightWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.applyHighlighting() }
            highlightWorkItem = item
            DispatchQueue.main.async(execute: item)
        }

        func applyHighlighting() {
            guard let textView else { return }
            // 组字期间不重设属性（会打断输入法、丢 marked text）。这条是从 SQL 编辑器学来的。
            guard !textView.hasMarkedText() else { return }
            let current = textView.string
            guard lastHighlightedText != current else { return }

            let tokens = CodeLexer.tokens(in: current, language: language)
            textView.apply(tokens: tokens, language: language)
            lastHighlightedText = current
        }

        // MARK: 补全（FR-EDIT-36）

        /// `NSTextView` 标准补全回调：⌃Space / F5 触发。
        /// 候选项来自**同一份** `CodeSyntax`（与着色共用），再加当前文档里的标识符。
        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            let prefix = (textView.string as NSString).substring(with: charRange)
            let items = CodeCompletion.suggestions(
                prefix: prefix,
                language: language,
                documentWords: CodeCompletion.words(in: textView.string, language: language)
            )
            index?.pointee = items.isEmpty ? -1 : 0
            return items.map(\.insertText)
        }
    }
}

/// 代码编辑器用的 `NSTextView`：只多做一件事 —— **把 ⌘S 交出去**。
///
/// 为什么在这里拦：`NSTextView` 不处理保存（那是应用级动作），而 SwiftUI 侧的
/// `.keyboardShortcut` 在文本视图获得焦点时收不到这个按键。拦在这里最稳。
final class CodeTextView: NSTextView {
    var onSave: (() -> Void)?

    /// 补全落光标用：插入的是哪个语言，决定片段插入后的落点约定。
    var completionLanguage: TextLanguage = .plainText

    // MARK: 行号列（FR-EDIT-36 的「编辑器行号列」，队列 L-64）
    //
    // 形态 = **在 `textContainerInset.width` 留出的那条空档里画**，不引 `NSRulerView`：
    // 行号要跟着内容一起纵向滚动、又不能参与横向滚动 —— 而正文本身就不横滚
    // （`widthTracksTextView = true`、无横滚条），所以"正文左边那条空档"天然满足这两条。
    // 算「第几行」的活不在这一层（`Core/CodeLines`，有单测），这里只负责**画**。

    /// 已经算好的行起点（UTF-16 偏移）。打字 / 换页签 / 换字体时由 `reloadLineNumbers()` 重算。
    private var lineStarts: [Int] = [0]

    /// 行号列宽度；`0` 表示还没算过（此时不画）。
    private(set) var gutterWidth: CGFloat = 0

    /// 数字用**当前等宽字体**的小号（FR-EDIT-26 里用户可换字体族 / 字号 ⇒ 跟着变）。
    static var lineNumberFont: NSFont {
        FontManager.shared.monospaceNSFont(size: TypeScale.monoSmallSize)
    }

    static let gutterPaddingLeft = Spacing.xs
    static let gutterPaddingRight = Spacing.s
    static let verticalInset = Spacing.s

    /// 行号列宽 = 左留白 + 位数 × 数字宽 + 右留白。
    ///
    /// 数字宽按**当前字体实量**而不是写死：列宽写死的话，用户把字号调大（或换个更宽的等宽字体）
    /// 之后数字会被裁掉，而 99 → 100 行这种"多一位"同样会挤（`CodeLines.digits`）。
    static func gutterWidth(digits: Int) -> CGFloat {
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: lineNumberFont]).width
        return gutterPaddingLeft + CGFloat(max(1, digits)) * digitWidth + gutterPaddingRight
    }

    /// 重算行起点与列宽。**加行、改字体会改变位数与数字宽**，所以这两条路都要调它。
    func reloadLineNumbers() {
        lineStarts = CodeLines.lineStarts(in: string)
        let width = Self.gutterWidth(digits: CodeLines.digits(of: lineStarts.count))
        if abs(width - gutterWidth) > 0.5 {
            gutterWidth = width
            // `textContainerInset.width` 左右同时生效 ⇒ 右边也留同一宽度。接受它：
            // 无横滚 + 自动换行，代价只是换行位置提前一点，换来的形态最简单（没有第二套滚动同步）。
            textContainerInset = NSSize(width: width, height: Self.verticalInset)
        }
        needsDisplay = true
    }

    /// 先让 `NSTextView` 画底色与正文，再把行号画上去 —— 顺序反了会被底色盖掉
    /// （`drawsBackground = true` 时它填的是**整个 bounds**）。
    ///
    /// **`saveGraphicsState` / `restoreGraphicsState` 这一对不是装饰**：`NSTextView` 在 `draw(_:)`
    /// 里会把**裁剪区收窄到文本容器**（也就是把 `textContainerInset` 留出的那条空档裁掉），而且不还回来。
    /// 不还原的话，行号列画不出来 —— 实测症状是**整条列被裁得只剩右侧一个像素**（第 45 轮实测：
    /// x=0..25pt 全是背景白，只有 x=50/2=25pt 那一列留下一个绿色像素），而"画了但看不见"最容易
    /// 被当成"忘了调用"。存一次、画完正文就还原，裁剪区回到整个 `dirtyRect`。
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
        drawLineNumbers(in: dirtyRect)
    }

    private func drawLineNumbers(in dirtyRect: NSRect) {
        guard gutterWidth > 0, let layoutManager, let container = textContainer else { return }

        let gutter = NSRect(x: 0, y: dirtyRect.minY, width: gutterWidth, height: dirtyRect.height)
        Theme.nsColor(Surface.panel).setFill()
        gutter.fill()
        Theme.hairlineNSColor.setFill()
        NSRect(
            x: gutterWidth - Metrics.hairline,
            y: dirtyRect.minY,
            width: Metrics.hairline,
            height: dirtyRect.height
        ).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.lineNumberFont,
            .foregroundColor: Theme.nsColor(TextTone.tertiary),
        ]
        let origin = textContainerOrigin
        let length = (string as NSString).length

        // 只画看得见的那几行：先问"可见区顶部落在哪个字符上"，再从那一行往后画到出界为止。
        // 从第 1 行硬扫虽然在短文件上没差别，但在几千行的文件里会让**每一帧**都变成几千次排版查询。
        let probeY = max(0, dirtyRect.minY - origin.y)
        let probeCharacter = layoutManager.characterIndex(
            for: NSPoint(x: 0, y: probeY),
            in: container,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        var index = max(0, CodeLines.lineNumber(at: probeCharacter, lineStarts: lineStarts) - 1)

        while index < lineStarts.count {
            let top = origin.y
                + fragmentTop(forLineStartingAt: lineStarts[index], layoutManager: layoutManager, container: container, length: length)
            if top > dirtyRect.maxY { break }

            let label = "\(index + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            let x = gutterWidth - Self.gutterPaddingRight - size.width
            // 与正文**基线对齐**：数字比正文小一号，按顶边对齐会看起来高一档。
            let y = top + (CodeEditorView.baseFont.ascender - Self.lineNumberFont.ascender)
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
            index += 1
        }
    }

    /// 某一行的**顶边**（文本容器坐标）。
    ///
    /// 两类位置要分开取：正常行按第一个字形的 line fragment（软换行的续行用同一个起点 ⇒ 一个逻辑行
    /// 只有一个号，这是对的）；而末尾那个空行**没有字形**，取 `NSTextView` 为它准备的 extra line fragment
    /// （口径 ② 在画这一侧的落点 —— 少了它，末尾空行就没有号）。
    private func fragmentTop(
        forLineStartingAt lineStart: Int,
        layoutManager: NSLayoutManager,
        container: NSTextContainer,
        length: Int
    ) -> CGFloat {
        guard lineStart < length else {
            if layoutManager.extraLineFragmentTextContainer != nil {
                return layoutManager.extraLineFragmentRect.minY
            }
            return layoutManager.usedRect(for: container).maxY
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: lineStart)
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    }

    /// 补全**自己插**，不交给 `NSTextView` 默认实现。
    ///
    /// 为什么：默认实现把候选原样塞进去、光标留在末尾。对多行片段（`function name() {\n  \n}`）
    /// 与带括号的片段（`console.log()`）那都不对 —— 用户的下一步是"在括号里 / 空行里继续写"。
    /// 落点约定在 Core（`CodeCompletion.caretOffset`，有单测），这里只负责搬。
    override func insertCompletion(
        _ word: String,
        forPartialWordRange charRange: NSRange,
        movement: Int,
        isFinal flag: Bool
    ) {
        guard flag, let storage = textStorage else {
            super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
            return
        }
        let characters = Array(word)
        let offset = min(max(0, CodeCompletion.caretOffset(inInsertText: word)), characters.count)
        let prefix = String(characters[0..<offset])

        let replacement = NSRange(location: charRange.location, length: charRange.length)
        guard shouldChangeText(in: replacement, replacementString: word) else { return }
        storage.replaceCharacters(in: replacement, with: word)
        didChangeText()

        // 注意：`caretOffset` 数的是**字符**，而 `NSRange` 数的是 UTF-16 单元 —— 中文注释里插入
        // 片段时两者会差，所以按前缀的 utf16 长度换算（片段里出现宽字符时不换算就会偏到别处）。
        let caret = replacement.location + prefix.utf16.count
        setSelectedRange(NSRange(location: min(caret, storage.length), length: 0))
        scrollRangeToVisible(NSRange(location: caret, length: 0))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "s" {
            onSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// 把记号涂上去。基色与字体先铺满，再逐段覆盖 —— 与 SQL 编辑器同一手法。
    func apply(tokens: [CodeToken], language: TextLanguage) {
        guard let storage = textStorage else { return }
        let length = storage.length
        let baseFont = CodeEditorView.baseFont
        let keywordFont = CodeEditorView.keywordFont

        storage.beginEditing()
        storage.setAttributes(
            [.font: baseFont, .foregroundColor: Theme.nsColor(TextTone.primary)],
            range: NSRange(location: 0, length: length)
        )
        for token in tokens where token.kind.isHighlighted {
            let range = NSRange(token.range, in: string)
            guard range.location >= 0, range.length > 0, range.location + range.length <= length else { continue }
            let attributes = Self.attributes(for: token.kind, keywordFont: keywordFont)
            if !attributes.isEmpty {
                storage.addAttributes(attributes, range: range)
            }
        }
        storage.endEditing()
        typingAttributes = [
            .font: baseFont,
            .foregroundColor: Theme.nsColor(TextTone.primary)
        ]
    }

    private static func attributes(
        for kind: CodeToken.Kind,
        keywordFont: NSFont
    ) -> [NSAttributedString.Key: Any] {
        // 颜色一律走 `SyntaxTone` 令牌（深浅两套各一份，对比度由单测守着）——
        // 与 SQL 编辑器共用同一套语法色，两个编辑器里的"关键字"才是同一个绿。
        switch kind {
        case .keyword, .tag:
            return [.foregroundColor: Theme.nsColor(SyntaxTone.keyword), .font: keywordFont]
        case .builtin:
            return [.foregroundColor: Theme.nsColor(SyntaxTone.function)]
        case .string:
            return [.foregroundColor: Theme.nsColor(SyntaxTone.string)]
        case .comment:
            return [.foregroundColor: Theme.nsColor(SyntaxTone.comment)]
        case .number:
            return [.foregroundColor: Theme.nsColor(SyntaxTone.number)]
        case .attribute:
            return [.foregroundColor: Theme.nsColor(SyntaxTone.identifier)]
        case .identifier, .punctuation:
            return [:]
        }
    }
}
