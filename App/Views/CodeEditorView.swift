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

    /// 当前工作区根（行内灰字的**路径候选**按它取表，`FR-EDIT-57`）。`nil` = 没有工作区 ⇒ 不补路径。
    var workspaceRoot: URL?

    /// 光标行上报（1 起）—— 工作区 Markdown 预览的**跟随滚动**输入面（队列 `L-137`）。
    /// 行号由 `Core/CodeLines` 算（与行号列**同一份**实现，界面层不自己数换行）。
    var onCursorLine: ((Int) -> Void)?

    /// **会话恢复的落脚点**（`FR-EDIT-43` 队列 `L-116` 第二片）：取本页上次退出时的
    /// 插入点与垂直滚动位置。**取走即没**（见 `WorkspaceTabsModel.takeCursorPlacement`）——
    /// 视图重建时不再放一遍，否则用户挪过的光标会被反复拽回上次退出时的位置。
    var takeCursorPlacement: ((UUID) -> WorkspaceTabsModel.CursorPlacement?)?

    /// **现场读数上报**（同上）：选区一变 / 滚一帧各报一次，退出时落快照的输入面。
    /// 与 `onCursorLine` 分开两条：预览只要行号，会话快照要**偏移**（行号换算不回偏移）。
    var onCursorPosition: ((UUID, Int, Double) -> Void)?

    /// 这一页的**缩进口径**（`FR-STD-WS-EDIT-022`）：按一次 Tab 插什么、回车继承几级、
    /// 硬 tab 在屏幕上占几格 —— 三处读同一个值（口径与屏幕上看到的东西必须是同一件事）。
    var indent: IndentProfile = .fallback

    /// 这一页的**折叠展示面**（`FR-STD-WS-EDIT-017`）：行号槽要画哪些标记、现在该藏哪几段字符。
    /// 判定与状态都在模型侧（`CodeFolding` + `WorkspaceTab.folds`），这里只负责搬。
    var foldPresentation: WorkspaceTabsModel.FoldPresentation = WorkspaceTabsModel.FoldPresentation()

    /// 点了行号槽上的折叠标记（参数 = 行号，1 起）。
    var onToggleFold: ((Int) -> Void)?

    /// 光标落进折起来的块里（参数 = 光标所在行）—— 展开哪几段由模型判（`unfoldAroundCaret`）。
    var onCaretEnteredFoldedBlock: ((Int) -> Void)?

    /// 内容稳定了（着色那一拍）：模型据此重算折叠区域与标记（不是每次击键都跑词法器）。
    var onDocumentSettled: (() -> Void)?

    /// 订阅字体偏好：偏好一变，SwiftUI 重跑 `updateNSView` → 编辑器换字体。
    @ObservedObject private var fonts = FontManager.shared

    static var baseFont: NSFont { Theme.nsFont(.mono) }
    static var keywordFont: NSFont {
        FontManager.shared.monospaceBoldNSFont(size: Theme.nsFont(.mono).pointSize)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // 会话恢复（`FR-EDIT-43` 第二片）：**先读落脚点**再动文本 / 挂代理 —— 设文本会让选区
        // 回到 0 并触发一次上报，读晚了拿到的是那个 0（见 `references/macos-ui-conventions.md`
        // 「视图重建类坑」的恢复顺序）。取走即没：视图重建时拿到的就是 `nil`，不再放一遍。
        let placement = takeCursorPlacement?(tabID)
        let textView = CodeTextView(frame: .zero)
        textView.delegate = context.coordinator
        // 登记「显示中的编辑器」：`FR-AI-22` ② 取「用户选的那段」只认这个（缓存记录会被重建冲掉）。
        EditorCommandCenter.shared.register(textView: textView, for: tabID)
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
        // 折叠（`FR-STD-WS-EDIT-017`）：标记挂到行号槽、该藏的行先藏起来。
        // 顺序在行号列之后：标记列占不占位会改变列宽，列宽又决定正文的可用宽度。
        textView.applyFolds(foldPresentation)

        context.coordinator.textView = textView
        context.coordinator.language = language
        textView.completionLanguage = language
        // 路径候选的表按工作区取（`ensure` 是幂等的：根没变、表没过期就立刻返回）。
        textView.workspaceRoot = workspaceRoot
        // 缩进口径（`FR-STD-WS-EDIT-022`）：Tab 插什么、硬 tab 在屏幕上占几格。
        textView.applyIndent(indent, forceRelayout: true)
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

        // ④ **把插入点与滚动位置放回去**（会话恢复）。放在最后一步：文本已设、行号列已算、
        //    代理已挂、滚动视图已就位 —— 缺任何一样这一步都会落空（光标放不进 / 滚动夹到 0）。
        if let placement {
            textView.applyCursor(caretOffset: placement.caretOffset, scrollOffset: placement.scrollOffset)
        }
        // 从现在起盯着这个页签的滚动位置（退出时落快照的输入面）。
        context.coordinator.observeScrolling(in: scrollView)
        // 放回去之后**如实上报一次** —— 用户什么都不动就退出时，这一栏不该被洗成 0。
        context.coordinator.reportCursorPosition()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        context.coordinator.parent = self
        textView.tabID = tabID
        textView.onSave = onSave
        textView.onFormat = onFormat
        // 折叠（`FR-STD-WS-EDIT-017`）：回调每次都重绑（视图会重建，旧的那个捕获的是旧模型）。
        textView.onToggleFold = onToggleFold
        textView.onCaretEnteredFoldedBlock = onCaretEnteredFoldedBlock
        textView.onDocumentSettled = onDocumentSettled
        textView.onFoldDisplayChanged = { [weak coordinator = context.coordinator] in
            coordinator?.rehighlightAfterFold()
        }
        // 展示面变了才重设（折 / 展 / 换内容）：`applyFolds` 会重排段落高度，不该每帧跑。
        if context.coordinator.lastFoldPresentation != foldPresentation {
            context.coordinator.lastFoldPresentation = foldPresentation
            textView.applyFolds(foldPresentation)
        }
        // 显示中的那个视图才算数（重建之后登记的必须是新的这个）—— `FR-AI-22` ②：
        // 对话要带上「用户选的那段」，取的就是这里登记的 `selectedRange()`。
        EditorCommandCenter.shared.register(textView: textView, for: tabID)
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
        // 路径候选：换了工作区就地换表；表过期（30 秒）则后台重搭，界面不等它。
        textView.workspaceRoot = workspaceRoot
        WorkspacePathIndex.shared.ensure(root: workspaceRoot)
        // 缩进口径（`FR-STD-WS-EDIT-022`）：用户在状态栏改了口径 ⇒ 这里跟着换（同一格数据）；
        // 换了字体也要重算制表位（制表位是按空格在这个字体下的宽度量的）。
        textView.applyIndent(indent, forceRelayout: fontChanged)
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
            // 换页签就换了一份文档：上一条灰字属于**上一个**文件的词表，必须当场重算。
            textView.refreshGhost()
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
        /// 上一次交给视图的折叠展示面（同一条不重复应用 —— 它会重排段落高度）。
        var lastFoldPresentation = WorkspaceTabsModel.FoldPresentation()
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
            // 行内灰字（`FR-EDIT-57`）：每个击键重算一次，但**词表不在这里切**
            // （词表跟着高亮那一拍刷新，见 `applyHighlighting`）—— 这里只做候选比较。
            textView.refreshGhost()
        }

        // MARK: 光标行（队列 L-137：Markdown 预览的跟随滚动）

        /// 选中区一变就上报一次光标行。行号算在 `Core/CodeLines`（与行号列同一份），
        /// 这里只负责把 `NSRange.location`（**UTF-16 单元**）交给它。
        func textViewDidChangeSelection(_ notification: Notification) {
            reportCursorLine()
            reportCursorPosition()
            // 光标动 ⇒ 灰字该重算（换行 / 点到别处 / 选中一段，都应立刻改口或消失）。
            textView?.refreshGhost()
            // 光标动 ⇒ 括号匹配高亮跟着换（`FR-STD-WS-EDIT-020`）：它判的是「光标紧邻哪个括号」，
            // 不重算就会一直亮着上一个位置的那一对。
            textView?.refreshBracketHighlight()
            // 光标落进**折起来的块**里 ⇒ 交给模型展开（`FR-STD-WS-EDIT-017`）：
            // 不展开的话用户是在看不见的行里打字 —— 折叠最典型的「按了没反应」。
            // 只在行号变了时才问一次（模型侧也会在「没折任何东西」时立刻返回）。
            if let textView {
                let line = CodeLines.lineNumber(at: textView.selectedRange().location, in: textView.string)
                if line != lastReportedFoldLine {
                    lastReportedFoldLine = line
                    parent.onCaretEnteredFoldedBlock?(line)
                }
            }
        }

        /// 上一次问过「这一行在折起来的块里吗」的行号（避免同一行反复问模型）。
        private var lastReportedFoldLine = 0

        func reportCursorLine() {
            guard let textView else { return }
            let location = textView.selectedRange().location
            guard location != NSNotFound else { return }
            parent.onCursorLine?(CodeLines.lineNumber(at: location, in: textView.string))
        }

        // MARK: 现场读数（FR-EDIT-43 第二片：会话恢复要的插入点与滚动位置）

        /// 盯住这个页签的滚动位置：clip view 的 bounds 一变就上报一次。
        ///
        /// 为什么不只在选区变化时上报：**纯滚动**（拖滚动条 / 触控板）不动光标 ——
        /// 只挂选区那一处的话，「滚到中间然后退出」记下来的还是上次动光标时的位置。
        func observeScrolling(in scrollView: NSScrollView) {
            let clip = scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clip
            )
        }

        @objc private func clipViewBoundsDidChange(_ notification: Notification) {
            reportCursorPosition()
        }

        /// 上报本页的插入点（UTF-16 偏移）与垂直滚动偏移（点）—— 退出时落快照的输入面。
        func reportCursorPosition() {
            guard let textView, let tabID = textView.tabID, let onCursorPosition = parent.onCursorPosition else {
                return
            }
            let location = textView.selectedRange().location
            let scroll = textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0
            onCursorPosition(tabID, location == NSNotFound ? 0 : location, Double(scroll))
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
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
            // 行内灰字用的文档词**跟着这一次切分算**（`words(inTokens:)` 不再重切整篇）：
            // 这样击键路径（`refreshGhost`）只做候选比较，大文档不会被每次按键拖成 O(n)。
            textView.updateGhostWords(CodeCompletion.words(inTokens: tokens, text: current))
            // 内容稳定了（这一拍已经重新切过分词）：模型据此重算**折叠区域与标记**
            // （`FR-STD-WS-EDIT-017`）—— 不是每次击键都跑，「一次击键一次词法器」在大文档上
            // 就是 `NFR-PERF-05` 那类卡顿。
            parent.onDocumentSettled?()
        }

        /// 折 / 展之后补一次着色：`applyFoldCollapse` 会摘掉被藏那几行的前景色与字体
        /// （不摘就画得出来），展开时那些行要按语法重上色 —— 否则它们会一直是正文色，
        /// 肉眼一看就是「折过一次的文件少了高亮」。
        func rehighlightAfterFold() {
            lastHighlightedText = nil
            applyHighlighting()
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
final class CodeTextView: NSTextView, UndoScopedEditor {
    /// 撤销步粒度的状态（`FR-STD-WS-EDIT-014`）：上一次动作是什么，据此决定这次要不要断开。
    /// 状态必须**每个视图一份**（两个页签各自一条撤销链，共用一份会把 A 页签的动作名写到 B 上）。
    var undoGranularity = UndoGranularity()

    var onSave: (() -> Void)?

    /// 触发格式化（FR-EDIT-39）。菜单项与 ⇧⌘F 都落到这一个口子。
    var onFormat: (() -> Void)?

    /// 这个编辑器画的是哪个页签（格式化投递按它归属）。
    var tabID: UUID?

    /// 补全落光标用：插入的是哪个语言，决定片段插入后的落点约定。
    var completionLanguage: TextLanguage = .plainText

    // MARK: 行内灰字补全（FR-EDIT-57 的行内形态 · Core `InlineGhostCompletion`）

    /// 灰字的状态与画法（**与数据库 SQL 编辑器共用这一份**，见 `GhostTextOverlay`）。
    /// 这里只做接线：候选来自 `CodeCompletion`、落地走本视图的 `applyEditPlan`。
    private lazy var ghostOverlay: GhostTextOverlay = {
        let overlay = GhostTextOverlay(host: self)
        overlay.apply = { [weak self] suggestion in
            guard let self else { return false }
            return self.applyEditPlan(
                range: suggestion.range,
                replacement: suggestion.insertText,
                caret: suggestion.caretOffset,
                kind: .completion
            )
        }
        overlay.candidateProvider = { [weak self] prefix in
            guard let self else { return [] }
            return CodeCompletion
                .suggestions(
                    prefix: prefix,
                    language: self.completionLanguage,
                    documentWords: self.ghostDocumentWords
                )
                .map { InlineGhostCandidate(insertText: $0.insertText, kind: $0.kind) }
        }
        // 路径候选（`FR-EDIT-57` 最后一块）：表来自 `WorkspacePathIndex`（后台搭、30 秒过期），
        // 这里只把"当前那一份"递进去 —— 前缀边界与口径全在 `PathGhostCompletion` 里。
        overlay.pathIndex = { WorkspacePathIndex.shared.candidates }
        return overlay
    }()

    /// 这个编辑器看的是哪个工作区（路径候选按它取表）。由 SwiftUI 侧在创建 / 更新时投递。
    var workspaceRoot: URL? {
        didSet {
            guard workspaceRoot != oldValue else { return }
            WorkspacePathIndex.shared.ensure(root: workspaceRoot)
            observePathIndexIfNeeded()
            refreshGhost()
        }
    }

    /// 表搭完的广播（只挂一次；视图去了窗口再挂回来时不会重复注册）。
    private var pathIndexObserver: NSObjectProtocol?

    private func observePathIndexIfNeeded() {
        guard pathIndexObserver == nil else { return }
        pathIndexObserver = NotificationCenter.default.addObserver(
            forName: WorkspacePathIndex.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // 表晚到时补画一次：灰字是画出来的，晚一拍出现没有任何副作用（见 `WorkspacePathIndex`）。
            self?.refreshGhost()
        }
    }

    deinit {
        if let pathIndexObserver { NotificationCenter.default.removeObserver(pathIndexObserver) }
    }

    /// 当前该画的灰字（`nil` = 不画）。**只画、不写**：它从不进 `textStorage`，
    /// 所以撤销栈 / 保存的文件 / 复制走的文本里都没有它。想让它进正文只有 `Tab` 一条路。
    var ghost: InlineGhostSuggestion? { ghostOverlay.suggestion }

    /// 文档词缓存：由代理在**高亮那一拍**（已经切过词法）刷新，击键路径只读它。
    /// 每次击键重切整篇 = 大文档上 `NFR-PERF-05` 那类卡顿。
    private(set) var ghostDocumentWords: [String] = []

    /// 总开关（与"是否已经有模型端点"无关：这一片是**词法级**提示，不调模型）。
    var ghostEnabled: Bool {
        get { ghostOverlay.enabled }
        set {
            ghostOverlay.enabled = newValue
            ghostOverlay.refresh()
        }
    }

    /// 重算灰字。文本变、光标动、词表刷新、语言切换都要调它。
    func refreshGhost() {
        // 语言跟着本视图的页签走（字符串 / 注释判定按它），再交给共用的那一层算。
        ghostOverlay.language = completionLanguage
        ghostOverlay.refresh()
    }

    /// 代理在高亮那一拍把词表递进来（跟着一次 `CodeLexer.tokens` 的结果，不额外切一遍）。
    func updateGhostWords(_ words: [String]) {
        ghostDocumentWords = words
        refreshGhost()
    }

    /// 接受灰字（`Tab`）：把**已输入的前缀**换成整词，光标落到末尾。
    /// 返回 `false` = 这一刻没有可接受的灰字 ⇒ 调用方交还默认实现（Tab 仍然缩进）。
    @discardableResult
    func acceptGhost() -> Bool {
        ghostOverlay.accept()
    }

    /// 忽略灰字（`Esc`）。返回 `false` = 本来就没有灰字 ⇒ 交还默认实现。
    @discardableResult
    func dismissGhost() -> Bool {
        ghostOverlay.dismiss()
    }

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

    // MARK: 代码折叠（`FR-STD-WS-EDIT-017`）
    //
    // 判定与状态都在 Core / 模型侧；这一层只做两件事：**把标记挂到行号槽**、**把藏起来的行
    // 折掉**。折叠**不改一个字**：藏起来靠段落样式（行高 1pt + 前景透明），字符仍在
    // `textStorage` 里 ⇒ 搜索搜得到、保存存得全、撤销栈里多一条都不多（需求 ④）。

    /// 点了行号槽上的折叠标记（参数 = 行号，1 起）。
    var onToggleFold: ((Int) -> Void)?

    /// 光标落进折起来的块里（参数 = 光标所在行）。
    var onCaretEnteredFoldedBlock: ((Int) -> Void)?

    /// 内容稳定了（着色那一拍）。
    var onDocumentSettled: (() -> Void)?

    /// 折 / 展之后要补一次着色（被摘掉前景色的那几行要按语法重上色）。
    var onFoldDisplayChanged: (() -> Void)?

    /// 现在该藏起来的字符范围（由模型给，已合并成连续段）。
    private(set) var foldHiddenRanges: [NSRange] = []

    /// 上一次真正写进 `textStorage` 的段落样式范围（展开时按它逐段摘掉）。
    private var appliedFoldRanges: [NSRange] = []

    /// 换上这一份折叠展示面：标记先挂（它可能改变列宽 ⇒ 要重排），再折行。
    func applyFolds(_ presentation: WorkspaceTabsModel.FoldPresentation) {
        // 同一行可能既有块、又有手写区域标记 ⇒ 取「任一折着就算折着」（标记只有一枚）。
        var markers: [Int: Bool] = [:]
        for marker in presentation.markers {
            markers[marker.line] = (markers[marker.line] ?? false) || marker.isFolded
        }
        // 标记列占不占位会改列宽（正文可用宽度跟着变）⇒ 变了就重排。
        gutter.applyFoldMarkers(markers, to: self)
        let changed = foldHiddenRanges != presentation.hiddenRanges
        foldHiddenRanges = presentation.hiddenRanges
        applyFoldCollapse()
        // 折 / 展之后补一次着色：展开时那几行的语法色是被上一轮折叠摘掉的。
        if changed { onFoldDisplayChanged?() }
    }

    /// 按 `foldHiddenRanges` 把该藏的行「折」起来 —— **只动段落样式，不动字符**。
    ///
    /// 做法：被藏的行给一个「行高 1pt + 前景透明 + 极小字号」的段落样式。为什么不删文本 /
    /// 不换一份显示用字符串：那两条路都会让 `textView.string` 与模型里的内容分叉，
    /// 而模型那份内容正是搜索、保存、撤销、光标行上报的唯一来源（需求 ④）。
    ///
    /// 为什么不 `invalidateLayout`：非连续布局下把可见区判成「没排过」⇒ 编辑区整块不画
    /// （本仓已栽过，见 `references/macos-ui-conventions.md` §十七）。属性变更会由
    /// `textStorage` 自己触发对应范围的重排，这里只需要重画。
    func applyFoldCollapse() {
        guard let storage = textStorage else { return }
        let length = storage.length
        storage.beginEditing()
        for range in appliedFoldRanges where range.location >= 0 && range.location + range.length <= length {
            storage.removeAttribute(.paragraphStyle, range: range)
            storage.removeAttribute(.foregroundColor, range: range)
            storage.removeAttribute(.font, range: range)
        }
        appliedFoldRanges = []
        let ranges = foldHiddenRanges.filter {
            $0.length > 0 && $0.location >= 0 && $0.location + $0.length <= length
        }
        if !ranges.isEmpty {
            let collapsed = NSMutableParagraphStyle()
            collapsed.minimumLineHeight = 1
            collapsed.maximumLineHeight = 1
            let invisible: [NSAttributedString.Key: Any] = [
                .paragraphStyle: collapsed,
                .foregroundColor: NSColor.clear,
                .font: NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular)
            ]
            for range in ranges {
                storage.addAttributes(invisible, range: range)
                appliedFoldRanges.append(range)
            }
        }
        storage.endEditing()
        needsDisplay = true
    }

    /// 点在行号槽的**标记列**上 = 折 / 展那一块；其余位置的点击原样交还（选词、拖选都不受影响）。
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // ⌘ 点击 = 跳到定义（`FR-STD-WS-NAV-006` ②）。解析与跳转都在 `SymbolHover.swift` 那一份里
        // （与 SQL 编辑器**同一份**），这里只递坐标；查不到就**不吞这次点击**，交还系统做选词。
        if event.modifierFlags.contains(.command), revealDefinition(at: point) { return }
        if let line = gutter.foldMarkerLine(at: point, of: self) {
            onToggleFold?(line)
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: 悬停文档（`FR-STD-WS-NAV-006` ①）

    /// 几何一变就重登记 tool tip（矩形是**当时的 bounds**，不重登记则新露出的区域不弹）。
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        installSymbolToolTip()
    }

    /// 系统 tooltip 的**动态**文案：在弹出那一刻按鼠标位置解析
    /// （静态 `toolTip` 只能写一句固定的话，而这里每一格答案都不同）。
    /// 判定、句子、跳转全在 `SymbolHover.swift` 那一份 —— 与 SQL 编辑器同一份实现。
    @objc func view(_ view: NSView,
                    stringForToolTip tag: NSView.ToolTipTag,
                    point: NSPoint,
                    userData data: UnsafeMutableRawPointer?) -> String {
        symbolToolTipText(at: point) ?? ""
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
        // 行内灰字补全：正文画完之后叠一层（它不在文本存储里，`super.draw` 不会画它）
        ghostOverlay.draw(in: dirtyRect)
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
        let landed = performUndoable(.completion) {
            guard shouldChangeText(in: replacement, replacementString: word) else { return false }
            storage.replaceCharacters(in: replacement, with: word)
            didChangeText()
            return true
        }
        guard landed else { return }

        // 注意：`caretOffset` 数的是**字符**，而 `NSRange` 数的是 UTF-16 单元 —— 中文注释里插入
        // 片段时两者会差，所以按前缀的 utf16 长度换算（片段里出现宽字符时不换算就会偏到别处）。
        let caret = replacement.location + prefix.utf16.count
        setSelectedRange(NSRange(location: min(caret, storage.length), length: 0))
        scrollRangeToVisible(NSRange(location: caret, length: 0))
    }

    /// `⌥↑` / `⌥↓` / `⇧⌥↓`：移行与复制行（`FR-STD-WS-EDIT-009`）。
    ///
    /// **为什么在 `keyDown` 而不在 `performKeyEquivalent`**：`performKeyEquivalent` 主要收「带 ⌘」的键；
    /// `⌥` 方向键是普通按键事件，走的是 `keyDown`。放在 `performKeyEquivalent` 里会「按了没反应」——
    /// 这类静默失效最难查（与 `⌘L` 那条掩码判据同一个教训：先确认这条路真的被调用）。
    ///
    /// 判定全在 `Core/LineMoveEdit`（纯函数，`Tests/LineMoveEditTests.swift`）；`nil` = 无操作（首行上移 /
    /// 末行下移）⇒ **交还系统**，不把这个按键吞掉（否则首行按 ⌥↑ 会变成「什么都没发生且没提示」）。
    override func keyDown(with event: NSEvent) {
        var modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // 大写锁 / Fn / 小键盘标志不是用户按下的修饰键，不参与「恰好 ⌥」的判决（同 `⌘L` 的掩码口径）。
        modifiers.subtract([.capsLock, .numericPad, .function])
        if modifiers == [.option] || modifiers == [.option, .shift] {
            let key = event.specialKey
            if key == .upArrow, modifiers == [.option] {
                if moveLines(.up) { return }
            } else if key == .downArrow, modifiers == [.option] {
                if moveLines(.down) { return }
            } else if key == .downArrow, modifiers == [.option, .shift] {
                if duplicateLines() { return }
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "s" {
            onSave?()
            return true
        }
        // ⌘L：勾 / 取消勾选**光标所在行**的任务框（`FR-EDIT-48`）。**与菜单项 `L(.menuToggleTaskCheckbox)`
        // 共用一个入口**（`toggleMarkdownTaskCheckbox()`；需求 ⑤ 原话「同一动作在菜单里也给一个条目（与快捷键
        // 同一个入口）」）。
        // 只认「恰好 ⌘」这一个修饰键 —— 带 ⇧ 的 ⇧⌘L 是应用菜单里的另一件事，不抢。
        //
        // **判掩码时先把三枚「不是用户按的」标志摘掉**（`T-20261018-204`）：`⌘L` 原先用
        // `intersection(.deviceIndependentFlagsMask) == [.command]` 判，而大写锁开着时真实事件带着
        // `.capsLock`（长按 Fn 时带 `.function`、部分键盘带 `.numericPad`）⇒ 掩码一不等就**静默放行**
        // ——按了没反应、也没有任何提示，属于最难查的那一类。不是用户按的键就不该参与「恰好 ⌘」的判决。
        var toggleTaskModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        toggleTaskModifiers.subtract([.capsLock, .numericPad, .function])
        if toggleTaskModifiers == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "l",
           toggleMarkdownTaskCheckbox() {
            return true
        }
        // ⇧⌘F：格式化代码（FR-EDIT-39）。与 ⌘S 同一条理由 —— SwiftUI 的 `.keyboardShortcut`
        // 在文本视图拿到焦点时收不到这个按键，而"光标在编辑器里"正是要格式化的那一刻。
        if event.modifierFlags.contains([.command, .shift]),
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            onFormat?()
            return true
        }
        // ⌘/：注释切换（`FR-EDIT-51`）。**只认恰好 ⌘** —— ⌘? 与 ⌘/ 在中文输入法下会撞车，
        // 所以这里按 `charactersIgnoringModifiers` 判（不按键盘布局）。
        // 注释符取自当前语言的 `CodeSyntax`（与着色 / 补全同一份），核心代码里没有第二种语言知识。
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
           event.charactersIgnoringModifiers == "/",
           toggleLineComment() {
            return true
        }
        // ⌃Space：候选列表（`FR-EDIT-57`）。AppKit 默认只有 F5 绑着 `complete:`，
        // 而"⌃Space 要候选"是所有写代码的人的肌肉记忆 —— 在这里显式接一下，
        // 免得用户按了没反应还以为补全没做。候选来自同一个 `CodeCompletion`（代理回调那儿）。
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control],
           event.charactersIgnoringModifiers == " " {
            complete(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: 行内灰字补全的按键（FR-EDIT-57）

    /// `Tab`：有片段会话就跳下一格 → 有灰字就**接受** → 触发词命中就插入骨架 → 否则按这一页的口径缩进。
    ///
    /// **次序就是口径**（`FR-STD-WS-NAV-005` ②）：
    /// · 会话排第一 —— 已经在片段里，Tab 的语义是「跳下一格」，此时再去接受灰字会把人从骨架里弹出去；
    /// · 灰字排第二 —— 它是「补全这一整个词」，与片段在同一位置二选一时，先让灰字落（它的判定更窄更具体）；
    /// · 片段第三；都不成立才缩进（**不吞正常输入**）。
    override func insertTab(_ sender: Any?) {
        if advanceSnippetStop() { return }
        if acceptGhost() { return }
        if expandSnippetTrigger() { return }
        insertIndentUnit()
    }

    // MARK: 片段模板（FR-STD-WS-NAV-005）

    /// 当前这次片段插入的会话（`nil` = 不在片段里）。**状态在编辑器**上：
    /// 片段是「一段正在填的骨架」，与页签模型无关；换页签再回来本来就该重新开始。
    var snippetSession: SnippetSession?

    /// Tab：跳下一个落点；跳完最后一格 ⇒ 收尾并结束会话（返回 `false` 让调用方继续往下走）。
    @discardableResult
    func advanceSnippetStop() -> Bool {
        guard var session = snippetSession else { return false }
        if session.isFinished {
            snippetSession = nil
            return false
        }
        guard let next = session.advance() else {
            snippetSession = nil
            return false
        }
        snippetSession = session.isFinished ? nil : session
        setSelectedRange(next)
        scrollRangeToVisible(NSRange(location: next.location, length: 0))
        return true
    }

    /// 光标前那个词命中片段触发词 ⇒ 换成骨架、光标落到第一个落点。
    /// 返回 `false` = 这一刻没有可展开的片段 ⇒ 调用方交还默认实现（Tab 仍然缩进）。
    @discardableResult
    func expandSnippetTrigger() -> Bool {
        let templates = SnippetCatalog.templates(for: completionLanguage)
        guard let plan = SnippetEngine.expansion(
            in: string,
            caret: selectedRange().location,
            templates: templates,
            language: completionLanguage
        ) else { return false }
        // 旧会话作废：这一次是**新插入**，不是在填上一份骨架。
        snippetSession = nil
        let location = plan.replaceRange.location
        guard applyEditPlan(
            range: plan.replaceRange,
            replacement: plan.insertion,
            caret: location + (plan.insertion as NSString).length,
            kind: .snippet
        ) else { return false }
        let session = SnippetSession.starting(after: plan, at: location)
        if let range = session.activeRange {
            setSelectedRange(range)
            scrollRangeToVisible(NSRange(location: range.location, length: 0))
        }
        snippetSession = session.isFinished ? nil : session
        return true
    }

    /// 每次编辑都要让会话跟着平移（否则用户在第一格多打两个字，后面所有落点就全错位）。
    /// 落在「两个落点之间」的改动 ⇒ 会话作废（`noteEdit` 回 `false`）：宁可不跳，也不跳到猜出来的位置。
    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: range, replacementString: replacementString) else { return false }
        if snippetSession != nil {
            let newLength = ((replacementString ?? "") as NSString).length
            if snippetSession?.noteEdit(range: range, replacementLength: newLength) == false {
                snippetSession = nil
            }
        }
        return true
    }

    // MARK: 缩进口径（`FR-STD-WS-EDIT-022`）

    /// 插进文本的那一份缩进单位（软 tab = N 个空格、硬 tab = 一个 `\t`）。
    /// 从 `IndentProfile.unit` 取，**不在这里再拼一次**（口径与状态栏显示必须是同一个值）。
    var indentUnit: String = IndentProfile.fallback.unit

    /// 硬 tab 在屏幕上占几格（`defaultParagraphStyle` 的制表位按它算）。
    private(set) var indentWidth: Int = IndentProfile.defaultWidth

    /// 换上这一页的口径：单位 + 显示宽度。宽度没变就不重排（`applyIndent` 每次 `updateNSView` 都会被调）。
    ///
    /// 为什么显示宽度要跟着走：口径里说「制表符 · 4」，屏幕上却按系统那一档（8 格）展开，
    /// 是「说的和看到的不一致」—— 而这类不一致用户只能靠肉眼发现，判据看不见。
    /// `forceRelayout` 给「换了字体」那条路：制表位是按**空格在这个字体下的宽度**算的，
    /// 字号一变同一个 `4` 对应的点数就变了，不重算就偏。
    func applyIndent(_ profile: IndentProfile, forceRelayout: Bool = false) {
        indentUnit = profile.unit
        guard indentWidth != profile.width || forceRelayout else { return }
        indentWidth = profile.width
        applyIndentTabStops()
    }

    /// 把制表位设成 `width × 空格宽度`：已有正文里没有自带段落样式的段落，按文本视图的缺省段落样式排。
    private func applyIndentTabStops() {
        let font = self.font ?? CodeEditorView.baseFont
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let paragraph = NSMutableParagraphStyle()
        paragraph.defaultTabInterval = max(1, spaceWidth * CGFloat(indentWidth))
        paragraph.tabStops = []
        defaultParagraphStyle = paragraph
        // 打字属性是分开存的一份：只设 `defaultParagraphStyle` 的话，**新打的字**仍按老制表位排。
        var attributes = typingAttributes
        attributes[.paragraphStyle] = paragraph
        typingAttributes = attributes
        // 换宽度要重排：不重排的话旧段落还按上一档排，肉眼看起来「改了没变」。
        if let layoutManager, let textContainer = textContainer {
            layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: (string as NSString).length),
                                           actualCharacterRange: nil)
            textContainer.containerSize = textContainer.containerSize
        }
    }

    /// 按 Tab 落一格（用 `insertText` 走系统那条路 ⇒ 撤销分组、输入法、选区替换都是现成的）。
    func insertIndentUnit() {
        guard !indentUnit.isEmpty else { return }
        insertText(indentUnit, replacementRange: selectedRange())
    }

    /// `Esc`：有灰字就忽略它（并记住"这一条我不要"），没有就交还默认实现。
    override func cancelOperation(_ sender: Any?) {
        if dismissGhost() { return }
        super.cancelOperation(sender)
    }

    // MARK: FR-EDIT-48 ⑤ —— 菜单入口（与 ⌘L 共用）

    /// 菜单项 `L(.menuToggleTaskCheckbox)` 的落点：AppKit 按 first responder 把动作派到**当前编辑器**，
    /// 与 ⌘L 走的是**同一个方法**（`toggleMarkdownTaskCheckbox()`）⇒ 需求 ⑤ 的「同一个入口」。
    @objc func toggleMarkdownTaskFromMenu(_ sender: Any?) {
        _ = toggleMarkdownTaskCheckbox()
    }

    /// 翻转光标所在行的任务框（`[ ]` ⇄ `[x]`），只动方框里那一个字符、等长替换。
    /// **⌘L 与菜单项共用此入口**；非 Markdown 文档 ⇒ 返回 `false`（按键不吞，交还系统；菜单项则无事发生）。
    @discardableResult
    func toggleMarkdownTaskCheckbox() -> Bool {
        guard MarkdownEditingScope.applies(to: completionLanguage),
              let plan = MarkdownListEditing.toggleTask(in: string, selection: selectedRange())
        else { return false }
        applyMarkdownPlan(plan, kind: .taskToggle)
        return true
    }

    // MARK: Markdown 编辑手感（FR-EDIT-47 / FR-EDIT-48）
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
           applyMarkdownPlan(plan, kind: .newline) {
            return
        }
        // 自动缩进（`FR-STD-WS-EDIT-021` ① ② ③）：判定全在 `Core/AutoIndent`（纯函数，
        // `Tests/AutoIndentTests.swift`），这里只把计划搬过去。`nil` = 交还系统默认回车
        // （有选区 / 光标后面还有正文 / 顶格且无级可继承）—— **不许吞掉按键什么都不做**。
        if let plan = AutoIndent.newline(in: string, selection: selectedRange(), indentUnit: indentUnit),
           applyEditPlan(range: plan.range, replacement: plan.replacement, caret: plan.caret, kind: .newline) {
            return
        }
        super.insertNewline(sender)
    }

    /// 粘贴：多行文本按上下文重排缩进（`FR-STD-WS-EDIT-021` ④）。
    ///
    /// 只在这四种情况之外动手：单行 / 空块 / 顶格粘到顶格 / 没有公共缩进可剥 —— `AutoIndent`
    /// 一律给 `nil`，这里就**原样交还系统粘贴**（别把默认粘贴换成自己那一份，尤其别吞掉富文本与文件粘贴）。
    override func paste(_ sender: Any?) {
        if let clip = NSPasteboard.general.string(forType: .string),
           let plan = AutoIndent.paste(clip, into: string, selection: selectedRange(), indentUnit: indentUnit),
           applyEditPlan(range: plan.range, replacement: plan.replacement, caret: plan.caret, kind: .paste) {
            return
        }
        super.paste(sender)
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
    func applyMarkdownPlan(_ plan: MarkdownEditPlan, kind: UndoEditKind) -> Bool {
        // 落地口径只有 `applyEditPlan` 一处（撤销粒度 / 等长替换保选区都在那里）。
        applyEditPlan(range: plan.range, replacement: plan.replacement, caret: plan.caret, kind: kind)
    }

    // MARK: 编程助手基础能力（FR-EDIT-49 / FR-EDIT-50）
    //
    // 与 Markdown 手感同一条理由：`NSTextView` 的默认输入不认识"配对 / 跳引号"，而"光标在编辑器里"
    // 正是要配对的那一刻。**判据全在 `Core/CodeAutoPairing`**（纯函数，`Tests/CodeAutoPairingTests.swift`），
    // 这里只负责把计划搬过去；Core 说 `nil`（多字符 / IME 候选 / 这条口径不适用）就原样交还默认实现。

    /// 语言族：Markdown 一族不配引号（写中文时 `'` 就是引号本身），代码族全配。
    var pairingFamily: CodeAutoPairing.LanguageFamily {
        MarkdownEditingScope.applies(to: completionLanguage) ? .prose : .code
    }

    /// 敲字符：左括号 / 引号配对，闭合符该跳就跳，选中再打 = 包住（`FR-EDIT-49`）。
    ///
    /// 只认"用户敲下的单字符"：`replacementRange.location != NSNotFound` 是替换选区 / 输入法上屏，
    /// 多字符是粘贴 —— 这些一律走默认实现，别去猜用户在干什么。
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if replacementRange.location == NSNotFound,
           let typed = string as? String,
           let plan = CodeAutoPairing.plan(
               typed: typed, in: self.string, selection: selectedRange(), family: pairingFamily
           ),
           applyPairingPlan(plan) {
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// 退格：光标夹在**空的**一对里（`(|)`）⇒ 一次删掉两个，不为一个自动补上的字符多按一次（`FR-EDIT-49`）。
    override func deleteBackward(_ sender: Any?) {
        if let plan = CodeAutoPairing.backspacePlan(in: string, selection: selectedRange()),
           applyPairingPlan(plan) {
            return
        }
        super.deleteBackward(sender)
    }

    /// 把 Core 算好的一次编辑落到编辑器上 —— **所有编辑动作的唯一落点**（配对 / 注释切换都走它）。
    ///
    /// 走 `shouldChangeText` → `replaceCharacters` → `didChangeText`：这样 ⌘Z 一步回得到改动之前，
    /// `didChangeText` 又会带上模型、行号列与着色。
    /// 返回 `false` = 没落成（越界 / 被 `shouldChangeText` 拒）⇒ 调用方应当**交还默认实现**，
    /// 而不是把这个按键悄悄吞掉。
    @discardableResult
    func applyEditPlan(range: NSRange,
                       replacement: String,
                       caret: Int,
                       selectionLength: Int = 0,
                       kind: UndoEditKind) -> Bool {
        guard let storage = textStorage, range.location >= 0,
              range.location + range.length <= storage.length else { return false }
        // 替换**之前**的选区：等长替换要原样留住它（需求 ③，`Core/EditSelectionPolicy`）。
        let original = selectedRange()
        let landed = performUndoable(kind) {
            guard shouldChangeText(in: range, replacementString: replacement) else { return false }
            storage.replaceCharacters(in: range, with: replacement)
            didChangeText()
            return true
        }
        guard landed else { return false }
        let placement = EditSelectionPolicy.after(
            original: original,
            editRange: range,
            replacementLength: (replacement as NSString).length,
            requested: NSRange(location: min(max(0, caret), storage.length),
                               length: min(max(0, selectionLength), storage.length)),
            documentLength: storage.length
        )
        setSelectedRange(placement)
        scrollRangeToVisible(NSRange(location: placement.location, length: 0))
        return true
    }

    @discardableResult
    func applyPairingPlan(_ plan: CodePairingPlan) -> Bool {
        applyEditPlan(range: plan.range, replacement: plan.replacement,
                      caret: plan.caret, selectionLength: plan.selectionLength, kind: .pairing)
    }

    // MARK: 括号匹配高亮（FR-STD-WS-EDIT-020）

    /// 上一次涂过底色的字符范围（清场用）。**只记范围、不记颜色** ——
    /// 颜色每次从令牌现取，换主题后下一次刷新拿的就是新值。
    private var bracketHighlightRanges: [NSRange] = []

    /// 按当前选区重算括号匹配高亮：**涂与清都只有这一处**。
    ///
    /// 判定全在 `Core/BracketHighlight`（纯函数，`Tests/BracketHighlightTests.swift`）；
    /// 这里只做两件事：把上一批底色摘掉、把新一批按令牌色涂上。
    func refreshBracketHighlight() {
        guard let storage = textStorage else { return }
        // 组字期间不动属性（会打断输入法、丢 marked text）—— 与 `apply(tokens:)` 同一条理由。
        guard !hasMarkedText() else { return }
        let length = storage.length

        storage.beginEditing()
        // 清场只摘 `.backgroundColor`，**不重置整段属性**：那个字符可能同时带着语法色
        // （字符串 / 注释里的括号就是），整段 `setAttributes` 会把它涂回默认色。
        for range in bracketHighlightRanges
        where range.location >= 0 && range.location + range.length <= length {
            storage.removeAttribute(.backgroundColor, range: range)
        }
        bracketHighlightRanges = []

        if let plan = BracketHighlight.plan(in: string, selection: selectedRange()) {
            let color = Theme.nsColor(
                plan.role.color(in: Theme.designTheme), alpha: plan.role.backgroundOpacity
            )
            for range in plan.spans
            where range.location >= 0 && range.length > 0 && range.location + range.length <= length {
                storage.addAttribute(.backgroundColor, value: color, range: range)
                bracketHighlightRanges.append(range)
            }
        }
        storage.endEditing()
    }

    /// 整篇重涂之后把括号底色补回来（`apply(tokens:)` 会 `setAttributes` 铺满全文，
    /// 那一下把之前的底色一起抹掉了）。清掉记账再重算，避免拿旧范围去摘已经不存在的东西。
    func reapplyBracketHighlight() {
        bracketHighlightRanges = []
        refreshBracketHighlight()
    }

    /// 注释切换（`FR-EDIT-51`）：**语言从当前文档来、注释符从语言表来** —— 本文件里不出现任何具体注释符
    /// （语言知识只有 `Core/CodeLanguageDefinitions.swift` 一处，新增语言因此不改核心代码）。
    /// 返回 `false` = 这门语言没登记行注释符 / 没什么可动的 ⇒ 按键**不吞**，交还系统。
    @discardableResult
    func toggleLineComment() -> Bool {
        let syntax = CodeLanguageRegistry.definition(of: completionLanguage).syntax
        guard let plan = CodeCommentToggling.plan(in: string, selection: selectedRange(), syntax: syntax)
        else { return false }
        return applyEditPlan(range: plan.range, replacement: plan.replacement,
                             caret: plan.caret, selectionLength: plan.selectionLength,
                             kind: .commentToggle)
    }

    /// 整行 / 整段上移、下移（`FR-STD-WS-EDIT-009`）：`⌥↑` / `⌥↓` 的落点。
    ///
    /// 判定全在 `Core/LineMoveEdit`（纯函数）—— 这里只把计划搬到编辑器上：
    /// 走 `applyEditPlan` 那条唯一落点（`shouldChangeText → replaceCharacters → didChangeText`），
    /// 所以 ⌘Z 一步回得到移动之前，模型 / 行号列 / 着色也跟着刷新。
    /// 返回 `false` = 无操作（首行上移 / 末行下移）⇒ 调用方把按键交还系统。
    @discardableResult
    func moveLines(_ direction: LineMoveDirection) -> Bool {
        guard let plan = LineMoveEdit.move(in: string, selection: selectedRange(),
                                           direction: direction)
        else { return false }
        return applyEditPlan(range: plan.range, replacement: plan.replacement,
                             caret: plan.caret, selectionLength: plan.selectionLength,
                             kind: .lineMove)
    }

    /// 向下复制当前行 / 选中整段（`FR-STD-WS-EDIT-009` ③）：`⇧⌥↓` 的落点。副本紧随原行、选区留在原件上。
    @discardableResult
    func duplicateLines() -> Bool {
        guard let plan = LineMoveEdit.duplicate(in: string, selection: selectedRange())
        else { return false }
        return applyEditPlan(range: plan.range, replacement: plan.replacement,
                             caret: plan.caret, selectionLength: plan.selectionLength,
                             kind: .duplicateLine)
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

    // MARK: 会话恢复的落脚点（FR-EDIT-43 · 队列 L-116 第二片）

    /// 把上次退出时的**插入点**与**垂直滚动位置**放回去。
    ///
    /// 偏移已经由 `Core` 夹进恢复后的文档范围（`WorkspaceSessionSnapshot.clampCaret` /
    /// `clampScroll`）；这里再夹一次只是兜住「文本与快照不一致」的时序（文本刚设进来，
    /// 理论上是一致的）。**不选中任何文字**：会话恢复要的是「接着往下写」，
    /// 回来时突然高亮一段上一次的选区只会让人以为误触了什么。
    func applyCursor(caretOffset: Int, scrollOffset: Double) {
        let length = (string as NSString).length
        let caret = min(max(0, caretOffset), length)
        setSelectedRange(NSRange(location: caret, length: 0))
        applyScrollOffset(scrollOffset)
    }

    /// 把垂直滚动位置设回去。
    ///
    /// 为什么要先 `ensureLayout`：**文档高度是排完版才知道的**，而这里刚把文本设进来 ——
    /// 不补算这一次，`scroll(to:)` 会被夹到当时已知的文档高度（新建的编辑器≈一行），
    /// 症状是「恢复完滚动条还在顶上、光标也不在原来的高度」。
    /// 用 `ensureLayout`（**只补算、不作废**）而不是 `invalidateLayout`：非连续布局下后者会把
    /// 可见区判成「没排过」⇒ 编辑区整块不画（`references/macos-ui-conventions.md` §十七）。
    func applyScrollOffset(_ offset: Double) {
        guard let scrollView = enclosingScrollView else { return }
        if let layoutManager, let container = textContainer {
            layoutManager.ensureLayout(for: container)
        }
        let clip = scrollView.contentView
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let maxY = max(0, documentHeight - clip.bounds.height)
        let y = min(max(0, CGFloat(offset)), maxY)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
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
        performUndoable(.formatting) {
            guard shouldChangeText(in: whole, replacementString: text) else { return false }
            storage.replaceCharacters(in: whole, with: text)
            didChangeText()
            return true
        }
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
        // 上面那次 `setAttributes` 铺满全文 ⇒ 括号底色被一起抹掉了，这里补回来
        // （`FR-STD-WS-EDIT-020`：光标不动、只是文本变了时也得继续亮着）。
        reapplyBracketHighlight()
        // 同一条理由：`setAttributes` 也把折叠的段落样式抹掉了 ⇒ 折着的块会当场展开一下再被藏回去。
        applyFoldCollapse()
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

// MARK: 悬停文档与跳转到定义（`FR-STD-WS-NAV-006`）

/// 工作区编辑器按**当前页签的语言**建符号表 —— 与着色 / 补全同一个 `completionLanguage`
/// （另立一个「这份文件是什么语言」的字段，两者迟早分家）。其余全在 `SymbolHover.swift`。
extension CodeTextView: SymbolHoverHost {
    var symbolLanguage: TextLanguage { completionLanguage }
}
