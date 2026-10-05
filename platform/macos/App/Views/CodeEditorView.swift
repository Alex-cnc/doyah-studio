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
    /// 模型算好的格式化结果（一次性投递，FR-EDIT-39）。视图拿它做**可撤销**的整篇替换。
    var pendingFormat: WorkspaceTabsModel.FormatDelivery?
    /// 「跳到第 N 行」的一次性投递（`FR-EDIT-44` 标头搜索框回车）。
    var pendingReveal: WorkspaceTabsModel.RevealDelivery?
    var onTextChange: (String) -> Void
    var onSave: () -> Void

    /// 触发格式化（菜单项与 ⇧⌘F 都调它）。
    var onFormat: () -> Void

    /// 光标行上报（1 起）—— 工作区 Markdown 预览的**跟随滚动**输入面（队列 `L-137`）。
    /// 行号由 `Core/CodeLines` 算（与行号列**同一份**实现，界面层不自己数换行）。
    var onCursorLine: ((Int) -> Void)?

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
        // 大文档（5,000 行 / 数万字符）下 `NSTextView` 默认要**整篇**布局：删一个字符也会触发
        // 全文重排 —— 人工点验实测「删除时明显卡顿」（2026-09-29，NFR-PERF-05）。
        // ⚠️ 只对**大文档**开非连续布局：它的代价就是「可见区被判成已排过」⇒ 编辑后那一块不重画。
        // 需求提出者 2026-10-03 五轮复测（原始症状见队列 `L-178`）：Markdown 表格行很长、编辑与/不过那一列
        // 必须把横轴滚到右边（行首被遮住），此时删一个字 ⇒ **编辑区上半屏整片空白**（连行号列都没画，
        // 同一份文本在预览里完好），拖一下滚动条才恢复；横轴拖回最左（行首可见）则不复现。
        // 这一族的形态＝「那块被当成已排过」⇒ 与 `allowsNonContiguousLayout` 的已知代价吻合
        // （非连续布局正是「只排可见范围、其余延后」）。
        // 取舍：1,000 行以下走标准（连续）布局，稳定优先；大文档（≥1,000 行）仍开非连续布局，
        // 保住 NFR-PERF-05（5,000 行文档删一个字符不整篇重排）——那条人工点验实测过的卡顿不能退回去。
        // 口径（行号类判据 `check-editor-line-numbers.py`，队列 `L-181`）：这里问的是**行数**，不是行起点 ——
        // 行起点的算法只许在绘制件（`App/Views/LineNumberGutter.swift`）里出现一次，
        // 所以走 `CodeLines.count(in:)`（同一个实现、同一个数，不另立第二套口径）。
        textView.layoutManager?.allowsNonContiguousLayout = CodeLines.count(in: text) > 1_000
        textView.string = text
        textView.tabID = tabID
        textView.onSave = onSave
        textView.onFormat = onFormat
        // 行号列的宽度由「行数位数」定（`textContainerInset.width` 就是它的宽度），
        // 所以必须在**文本进去之后**算一次 —— 顺序反了会先按空文档算成 1 位。
        textView.reloadLineNumbers()

        context.coordinator.textView = textView
        context.coordinator.language = language
        textView.completionLanguage = language
        context.coordinator.applyHighlighting()
        // 首次上报光标行：页签刚打开时预览就该对齐到文档开头，而不是等第一次移动光标。
        context.coordinator.reportCursorLine()

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
        textView.tabID = tabID
        textView.onSave = onSave
        textView.onFormat = onFormat
        // 格式化结果：**每条投递只应用一次**（按投递 id 记账，不按文本比 —— 文本可能正好相等）。
        if let delivery = pendingFormat, delivery.tabID == tabID,
           context.coordinator.appliedFormatID != delivery.id {
            context.coordinator.appliedFormatID = delivery.id
            textView.applyFormat(delivery.text)
        }
        // 「跳到命中行」：同样**每条投递只应用一次**（同一条投递重复应用会把用户
        // 自己挪过的光标拽回去 —— 上下滚动一下就跳回命中行是最烦人的那种"智能"）。
        if let reveal = pendingReveal, reveal.tabID == tabID,
           context.coordinator.appliedRevealID != reveal.id {
            context.coordinator.appliedRevealID = reveal.id
            textView.reveal(line: reveal.line)
        }
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
        // 切页签 / 换了内容：光标行跟着新文档重报一次（预览据此重新对齐）。
        if textChanged {
            context.coordinator.reportCursorLine()
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
        /// 已经应用过的格式化投递（同一条投递只应用一次）。
        var appliedFormatID: UUID?
        /// 已经应用过的「跳到第 N 行」投递（同上）。
        var appliedRevealID: UUID?
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

        // MARK: 光标行（队列 L-137：Markdown 预览的跟随滚动）

        /// 选中区一变就上报一次光标行。行号算在 `Core/CodeLines`（与行号列同一份），
        /// 这里只负责把 `NSRange.location`（**UTF-16 单元**）交给它。
        func textViewDidChangeSelection(_ notification: Notification) {
            reportCursorLine()
        }

        func reportCursorLine() {
            guard let textView else { return }
            let location = textView.selectedRange().location
            guard location != NSNotFound else { return }
            parent.onCursorLine?(CodeLines.lineNumber(at: location, in: textView.string))
        }

        /// 延后一次高亮：避免与输入法 / 文本编辑回调重入。
        ///
        /// **这是真的 debounce，不是「扔到下一个 runloop」**：`DispatchQueue.main.async` 在连续
        /// 按键（尤其长按删除）时等于**每个键**都全量重新着色整篇文本（`apply(tokens:)` 先对全文
        /// `setAttributes`），5,000 行文档上表现为「删除时明显卡顿」（2026-09-29 人工点验实测）。
        /// 合并窗口按文档大小分档：大文档等更久，代价是高亮比光标慢一档，换来打字跟手。
        func scheduleHighlighting() {
            highlightWorkItem?.cancel()
            // 尺寸取 `textStorage.length`（**O(1)**）而不是 `string.count`：后者每次都把整篇文本
            // 实体化再数字符（5,000 行 / 414 KB 实测 0.32 ms、1.75 MB 实测 1.12 ms），是白付的 O(n)。
            let size = textView?.textStorage?.length ?? 0
            let delay: TimeInterval = size > sqlRealtimeScanLimit ? 0.45 : 0.12
            let item = DispatchWorkItem { [weak self] in self?.applyHighlighting() }
            highlightWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
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

    /// 触发格式化（FR-EDIT-39）。菜单项与 ⇧⌘F 都落到这一个口子。
    var onFormat: (() -> Void)?

    /// 这个编辑器画的是哪个页签（格式化投递按它归属）。
    var tabID: UUID?

    /// 补全落光标用：插入的是哪个语言，决定片段插入后的落点约定。
    var completionLanguage: TextLanguage = .plainText

    // MARK: 行号列（FR-EDIT-36 的「编辑器行号列」，队列 L-64）
    //
    // 形态 = **在 `textContainerInset.width` 留出的那条空档里画**，不引 `NSRulerView`：
    // 行号要跟着内容一起纵向滚动、又不能参与横向滚动 —— 而正文本身就不横滚
    // （`widthTracksTextView = true`、无横滚条），所以"正文左边那条空档"天然满足这两条。
    // 算「第几行」的活不在这一层（`Core/CodeLines`，有单测）；**画**也不在这一层了 ——
    // 自第 121 轮（队列 `L-111`）起工作区编辑器与**数据库 SQL 编辑器**共用同一个绘制件
    // （`App/Views/LineNumberGutter.swift`），这里只负责把列挂上。

    /// 行号列的**绘制件**（全工程唯一一份，见 `App/Views/LineNumberGutter.swift`）——
    /// 本视图不再自己算行号、也不自己量列宽，只负责把它挂上（`reload` / `draw`）。
    let gutter = LineNumberGutter()

    /// 行号列宽度；`0` 表示还没算过（此时不画）。
    var gutterWidth: CGFloat { gutter.width }

    /// 数字用**当前等宽字体**的小号（FR-EDIT-26 里用户可换字体族 / 字号 ⇒ 跟着变）。
    static var lineNumberFont: NSFont { LineNumberGutter.font }

    static let gutterPaddingLeft = LineNumberGutter.paddingLeft
    static let gutterPaddingRight = LineNumberGutter.paddingRight
    static let verticalInset = LineNumberGutter.verticalInset

    /// 行号列宽（转发绘制件的那一份算——**全工程只有一处算列宽**）。
    static func gutterWidth(digits: Int) -> CGFloat { LineNumberGutter.width(digits: digits) }

    /// 重算行起点与列宽。**加行、改字体会改变位数与数字宽**，所以这两条路都要调它。
    func reloadLineNumbers() {
        gutter.reload(self)
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
        // 行号：交给唯一绘制件画（`LineNumberGutter.draw`）
        gutter.draw(in: dirtyRect, of: self)
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
        // ⌘L：勾 / 取消勾选**光标所在行**的任务框（`FR-MD-02`）。
        // 只认「恰好 ⌘」这一个修饰键 —— 带 ⇧ 的 ⇧⌘L 是应用菜单里的另一件事，不抢。
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "l",
           MarkdownEditingScope.applies(to: completionLanguage),
           let plan = MarkdownListEditing.toggleTask(in: string, selection: selectedRange()) {
            applyMarkdownPlan(plan)
            return true
        }
        // ⇧⌘F：格式化代码（FR-EDIT-39）。与 ⌘S 同一条理由 —— SwiftUI 的 `.keyboardShortcut`
        // 在文本视图拿到焦点时收不到这个按键，而"光标在编辑器里"正是要格式化的那一刻。
        if event.modifierFlags.contains([.command, .shift]),
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            onFormat?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: Markdown 编辑手感（FR-MD-01 / FR-MD-02）
    //
    // 两件事都只对 Markdown 文档生效（生效范围判在 `Core/MarkdownEditingScope`，
    // 不在这里自己判语言）：`- ` / `[ ]` 在 YAML 里是数组、在 SQL 里是减号，纯文本里
    // 用户要的往往是原样的回车。判据在 `Tests/MarkdownEditingTests.swift`。

    /// 回车：列表项自动续行；空条目上的回车 = **退出列表**（都交给 `Core/MarkdownListEditing`）。
    ///
    /// 为什么拦在这里：`NSTextView` 的默认回车不会认列表标记，而 SwiftUI 侧的
    /// `.onSubmit` / 快捷键在文本视图拿到焦点时都收不到这个键 —— 与 ⌘S 同一条理由。
    /// 判据说 `nil`（不是列表项、光标在标记之前、有选区）就原样交还给默认实现。
    override func insertNewline(_ sender: Any?) {
        if MarkdownEditingScope.applies(to: completionLanguage),
           let plan = MarkdownListEditing.continuation(in: string, selection: selectedRange()),
           applyMarkdownPlan(plan) {
            return
        }
        super.insertNewline(sender)
    }

    /// 把 Core 算好的「替换哪一段 / 换成什么 / 光标停哪」落到编辑器上。
    ///
    /// **走 `shouldChangeText` → `replaceCharacters` → `didChangeText`**（与 `applyFormat` 同一条路）：
    /// 这样 ⌘Z 一步回得到续行之前，`didChangeText` 又会带上模型、行号列与着色。
    /// 直接在 `string` 上拼是不行的 —— 那条路不注册撤销、也不通知模型。
    ///
    /// 返回 `false` = 这次没落成（越界 / 被 `shouldChangeText` 拒），调用方应当**交还默认实现**，
    /// 而不是把这个按键悄悄吞掉。
    @discardableResult
    func applyMarkdownPlan(_ plan: MarkdownEditPlan) -> Bool {
        guard let storage = textStorage, plan.range.location >= 0,
              plan.range.location + plan.range.length <= storage.length else { return false }
        guard shouldChangeText(in: plan.range, replacementString: plan.replacement) else { return false }
        storage.replaceCharacters(in: plan.range, with: plan.replacement)
        didChangeText()
        let caret = min(max(0, plan.caret), storage.length)
        setSelectedRange(NSRange(location: caret, length: 0))
        scrollRangeToVisible(NSRange(location: caret, length: 0))
        return true
    }

    /// 跳到第 `line` 行（1 起）：把光标挪过去并滚到可见（`FR-EDIT-44` 的「回车跳到命中行」）。
    ///
    /// 两条口径：
    ///   · 行号 → 位置**只有一处换算**（`Core/CodeLines.range(ofLine:in:)`，与行号列同一份实现）；
    ///     这里自己数 `\n` 的话，`U+2028` 这类终止符上会跳到相邻的行；
    ///   · 光标长度取 0（**不选中整行**）：用户下一步是改这一行，整行高亮只会让他多按一次方向键。
    func reveal(line: Int) {
        guard let range = CodeLines.range(ofLine: line, in: string) else { return }
        setSelectedRange(NSRange(location: range.location, length: 0))
        scrollRangeToVisible(NSRange(location: range.location, length: 0))
    }

    /// 把格式化结果换进编辑器（FR-EDIT-39）。
    ///
    /// **走 `shouldChangeText` → `replaceCharacters` → `didChangeText` 这条路**：
    /// `allowsUndo` 会把它记成一条普通编辑，⌘Z 回到格式化前；`didChangeText` 又会触发
    /// 代理的 `textDidChange` ⇒ 模型里的内容、行号列、着色一起跟上。
    ///
    /// 为什么不用 `string = text`（`updateNSView` 同步外部文本的那条路）：那条路
    /// **不注册撤销、也不触发 `textDidChange`** —— 用户按 ⌘Z 拿不回来、模型还停在旧文本上。
    /// 需求原文要求「格式化前后可撤销」，替换就只能发生在这里。
    func applyFormat(_ text: String) {
        guard text != string, let storage = textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        guard shouldChangeText(in: whole, replacementString: text) else { return }
        storage.replaceCharacters(in: whole, with: text)
        didChangeText()
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
