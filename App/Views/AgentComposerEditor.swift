import AppKit
import SwiftUI
import DoyahCore

/// 对话输入框的**编辑面**（详设 §3.35）。
///
/// 为什么不再用 SwiftUI 的 `TextField`：契约 ①/⑥ 要求**多行**（⇧⏎ 换行）且要能精确分层
/// 「这一次 ↑↓ 归历史还是归光标」——`TextField` 是单行控件，既没有「第二行」可供判据 ③ 量，
/// 也拿不到 `doCommandBy` 这一层（方向键被字段编辑器直接消费）。
/// 所以输入框改成 `NSTextView` 承载，**判定仍留在 Core 的纯函数里**（`AgentComposerArrowRouter`
/// / `AgentInputHistoryNavigator`），这一层只做三件事：按键归属、把回填写进文本、量高度。
enum AgentComposerMetrics {
    /// 输入框垂直内边距（与提示符 `>` 的对齐基准，见 `AgentChatView.composer`）。
    static let verticalInset: CGFloat = 2
    /// 长到第几行就不再长（再长就在框内滚）。
    static let maxLines: Int = 8
}

/// 输入框的文本视图。
///
/// 三个按键口子：
/// - ↑↓：**只在边界**（首行行首 / 末行行末）且无选区、无浮层、不在组字时归历史；
///   其余一律 `super`，光标该怎么动就怎么动（契约 ①：不抢光标）。
/// - ⏎：提交（**不插入换行**）；**⇧⏎** 插入换行（契约 ⑥）。
/// - 组字期间（`hasMarkedText()`）**一律交还系统**：中文输入法用 ↑↓ 选字、用 ⏎ 确认候选，
///   这时抢键就是「按了没反应 + 拼音留在框里」那一类最难查的缺陷。
final class AgentComposerTextView: NSTextView {

    /// 提交（⏎）。**只由 `insertNewline` 触发** —— 回填走的是另一个口子，绝不经过这里（契约 ③）。
    var onSubmit: (() -> Void)?

    /// 取历史（返回要回填的文字；`nil` = 这一步没有可回填的，按键交还系统）。
    var onHistoryRecall: ((AgentComposerArrow) -> String?)?

    /// 候选浮层是否开着（斜杠命令候选条）：开着时 ↑↓ 归浮层（契约 ⑥）。
    var overlayOpen: () -> Bool = { false }

    /// 高度变了（协调器据它算 SwiftUI 那一格的高度）。
    var onContentHeightChange: (() -> Void)?

    static func make(font: NSFont) -> AgentComposerTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let view = AgentComposerTextView(frame: .zero, textContainer: container)
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [NSView.AutoresizingMask.width]
        view.textContainerInset = NSSize(width: 0, height: AgentComposerMetrics.verticalInset)
        view.font = font
        // 对话输入框不是代码框：智能引号 / 破折号替换会把用户打的原文改掉，一律关掉。
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.allowsDocumentBackgroundColorChange = false
        return view
    }

    // MARK: - 方向键

    /// 这次按键是不是「恰好一个方向键」。
    ///
    /// **两条来源都要看**：`specialKey` 是 AppKit 从键位映射出的语义，而
    /// `charactersIgnoringModifiers` 里 `0xF700/0xF701` 是方向键的 Unicode 函数键码 ——
    /// 合成事件（判据里造的那种）只保证后者，真实键盘两者都在。
    static func arrow(for event: NSEvent) -> AgentComposerArrow? {
        if let key = event.specialKey {
            switch key {
            case .upArrow: return .up
            case .downArrow: return .down
            default: return nil
            }
        }
        switch event.charactersIgnoringModifiers {
        case "\u{F700}": return .up
        case "\u{F701}": return .down
        default: return nil
        }
    }

    /// ↑↓ 的归属判定在这里（`keyDown` 是按键的第一入口：`doCommandBySelector` 那一层
    /// 在 Swift 里的名字与协议实现随 SDK 变动，而 `keyDown` 一定先到）。
    ///
    /// 三条「不接管」：组字期间（输入法用 ↑↓ 选字）、带任何修饰键（⇧↑ 扩选区、⌥↑ 别处有用）、
    /// 以及 `Core` 的判定说不该接管（光标不在边界 / 有选区 / 浮层开着）。
    override func keyDown(with event: NSEvent) {
        var modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // 大写锁 / Fn / 小键盘不是「用户按住的修饰键」，不参与「恰好一个方向键」的判决。
        modifiers.subtract([.capsLock, .numericPad, .function])
        if modifiers.isEmpty, !hasMarkedText(), isEditable {
            if let arrow = AgentComposerTextView.arrow(for: event) {
                let range = selectedRange()
                let owns = AgentComposerArrowRouter.takesHistory(
                    arrow,
                    text: string,
                    caret: range.location,
                    selectionLength: range.length,
                    overlayOpen: overlayOpen()
                )
                // `nil` 也交还系统：到了最旧一条 / 草稿态，这次按键本来就「什么都不该发生」，
                // 与其吞掉，不如让光标按常规走（契约 ⑤：到边界不静默，但也不装作用了）。
                if owns, let recalled = onHistoryRecall?(arrow) {
                    replaceEntireText(with: recalled)
                    return
                }
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - 回车

    override func insertNewline(_ sender: Any?) {
        // 组字中：这一下是**确认候选**，不是提交（同 `CodeTextView` 的输入法口径）。
        guard !hasMarkedText() else { return super.insertNewline(sender) }
        let shiftHeld = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        if shiftHeld { return super.insertNewline(sender) }   // ⇧⏎ = 换行
        onSubmit?()
    }

    /// ⌥⏎ / 部分键位绑定下的 ⇧⏎ 落到这里：一律换行，不提交。
    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        super.insertNewline(sender)
    }

    // MARK: - 回填

    /// 整段替换 + 光标落到末尾 + 滚到可见。**不碰 `onSubmit`**（契约 ③：只回填不发送）。
    func replaceEntireText(with text: String) {
        let full = NSRange(location: 0, length: (string as NSString).length)
        guard shouldChangeText(in: full, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: full, with: text)
        didChangeText()
        let end = (string as NSString).length
        setSelectedRange(NSRange(location: end, length: 0))
        scrollRangeToVisible(NSRange(location: end, length: 0))
    }

    // MARK: - 高度

    /// 内容自然高度（不封顶，用来撑滚动内容）。
    func naturalHeight(width: CGFloat, lineHeight: CGFloat) -> CGFloat {
        guard let layoutManager, let textContainer else {
            return lineHeight + AgentComposerMetrics.verticalInset * 2
        }
        let textWidth = max(1, width - textContainerInset.width * 2)
        if abs(textContainer.containerSize.width - textWidth) > 0.5 {
            textContainer.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer).height
        return max(lineHeight, used) + AgentComposerMetrics.verticalInset * 2
    }

    /// 输入框这一格的高度（封顶 `maxLines` 行；超过就在框内滚）。
    func clampedHeight(width: CGFloat, lineHeight: CGFloat, maxLines: Int) -> CGFloat {
        let cap = lineHeight * CGFloat(max(1, maxLines)) + AgentComposerMetrics.verticalInset * 2
        return min(naturalHeight(width: width, lineHeight: lineHeight), cap)
    }
}

/// 输入框（`NSTextView` 承载，外面套一层不画底的滚动视图：超过 `maxLines` 行时框内滚）。
struct AgentComposerEditor: NSViewRepresentable {

    @Binding var text: String
    /// 输入框这一格的高度（由内容量出，SwiftUI 据此排版）。
    @Binding var height: CGFloat
    let font: NSFont
    let isEnabled: Bool
    /// 候选浮层开着 ⇒ ↑↓ 归浮层（契约 ⑥）。
    let overlayOpen: Bool
    let onSubmit: () -> Void
    /// 取一条历史；`nil` = 没得回填 ⇒ 这一次 ↑↓ 交还光标。
    let onHistoryRecall: (AgentComposerArrow) -> String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none

        let textView = AgentComposerTextView.make(font: font)
        textView.delegate = context.coordinator
        let coordinator = context.coordinator
        textView.onSubmit = { coordinator.parent.onSubmit() }
        textView.onHistoryRecall = { coordinator.parent.onHistoryRecall($0) }
        textView.overlayOpen = { coordinator.parent.overlayOpen }
        textView.onContentHeightChange = { coordinator.relayout() }
        textView.string = text
        scroll.documentView = textView
        context.coordinator.textView = textView
        applyStyle(textView)
        context.coordinator.relayout()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        applyStyle(textView)
        // 外部改动（发送后清空、点候选填字）才回写；打字时不回写（否则每敲一个字就重设一次文本，
        // 画面会闪、撤销栈也会被切碎）。
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            let end = (text as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
        }
        context.coordinator.relayoutDeferred()
    }

    private func applyStyle(_ textView: AgentComposerTextView) {
        textView.font = font
        textView.textColor = Theme.nsColor(TextTone.primary)
        textView.insertionPointColor = Theme.nsColor(TextTone.primary)
        textView.isEditable = isEnabled
        textView.isSelectable = true
    }

    static func lineHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AgentComposerEditor
        weak var textView: AgentComposerTextView?
        private var pendingRelayout = false

        init(_ parent: AgentComposerEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? AgentComposerTextView else { return }
            if parent.text != textView.string { parent.text = textView.string }
            relayout()
        }

        /// 排到下一拍再量：`updateNSView` 里改 SwiftUI 状态会撞「Modifying state during view update」。
        func relayoutDeferred() {
            guard !pendingRelayout else { return }
            pendingRelayout = true
            DispatchQueue.main.async { [weak self] in
                self?.pendingRelayout = false
                self?.relayout()
            }
        }

        func relayout() {
            guard let textView else { return }
            let width = textView.enclosingScrollView?.contentSize.width ?? textView.bounds.width
            let lineHeight = AgentComposerEditor.lineHeight(for: parent.font)
            guard width > 1 else { return }
            let natural = textView.naturalHeight(width: width, lineHeight: lineHeight)
            let clamped = textView.clampedHeight(width: width,
                                                lineHeight: lineHeight,
                                                maxLines: AgentComposerMetrics.maxLines)
            if abs(textView.frame.height - natural) > 0.5 {
                textView.setFrameSize(NSSize(width: width, height: natural))
            }
            if abs(parent.height - clamped) > 0.5 {
                parent.height = clamped
            }
        }
    }
}
