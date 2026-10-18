import AppKit
import DoyahCore

/// 行内灰字的**唯一一份**状态 + 画法（`FR-EDIT-57` 的行内形态）。
///
/// ## 为什么抽成一层
///
/// 这块东西此前长在工作区编辑器的 `CodeTextView` 里。数据库 SQL 编辑器是**另一个** `NSTextView`
/// 子类（`SQLTextView`，多光标 / 列选择 / 行号列都在它身上），两边的候选还不是一套
/// （代码侧 `CodeCompletion`、SQL 侧 `QueryCompletion`）。若各写一遍画法与接受逻辑，
/// 会出现"同一屏两个编辑面灰字位置、淡法、Esc 之后会不会复活都不一样"——
/// 与行号列（`LineNumberGutter`）、着色同一条纪律：**画法只有一处**。
///
/// 所以这里只认三件事：**什么时候画**（候选与口径全在 Core `InlineGhostCompletion`）、
/// **画在哪**（排版结果算，不自己数字符宽）、**接受后怎么落**（由宿主编辑器给的闭包，各自实现）。
///
/// 不变量（与 Core 的注释对应）：灰字**只画不写** —— 它从不进 `textStorage`，
/// 所以撤销栈 / 保存的文件 / 复制走的文本里都没有它。想让它进正文，只有宿主按 Tab 那一条路。
final class GhostTextOverlay {

    /// 宿主编辑器（弱引用：这一层是宿主的附属，不该替它续命）。
    private weak var host: NSTextView?

    /// 当前语言（字符串 / 注释的上下文判定按它走；与着色 / 补全同一份语言表）。
    var language: TextLanguage = .plainText

    /// 总开关（与"是否已经有模型端点"无关：这一片是**词法级**提示，不调模型）。
    var enabled = true

    /// 候选来源（`nil` = 这一层还没接上候选 ⇒ 一条都不出，而不是瞎猜）。
    var candidateProvider: ((String) -> [InlineGhostCandidate])?

    /// 接受灰字时怎么落到缓冲区 —— **由宿主给**（各编辑器的插入语义不一样：
    /// 工作区编辑器走 `applyEditPlan`，SQL 编辑器走自己的单光标替换）。
    var apply: ((InlineGhostSuggestion) -> Bool)?

    /// 当前该画的灰字（`nil` = 不画）。
    private(set) var suggestion: InlineGhostSuggestion?

    /// 用户按 Esc 关掉的那一条（`位置 + 前缀 + 候选` 三元组）。
    /// 为什么要记：Esc 之后宿主的 `textViewDidChangeSelection` 还会再来一拍，
    /// 不记的话灰字会**立刻原地复活** —— 按了没反应比没有还糟。
    private var dismissedKey: String?

    init(host: NSTextView) {
        self.host = host
    }

    private func key(_ suggestion: InlineGhostSuggestion) -> String {
        "\(suggestion.range.location)|\(suggestion.range.length)|\(suggestion.insertText)"
    }

    /// 重算灰字。文本变、光标动、词表刷新、语言切换都要调它。
    func refresh() {
        guard let host else { setSuggestion(nil); return }
        // 组字期间不算：输入法候选还没上屏，这时的前缀不是用户想补的词。
        guard enabled, !host.hasMarkedText(), let candidateProvider else {
            setSuggestion(nil)
            return
        }
        let suggested = InlineGhostCompletion.suggestion(
            in: host.string,
            selection: host.selectedRange(),
            language: language,
            candidateProvider: candidateProvider,
            enabled: enabled
        )
        if let suggested, key(suggested) == dismissedKey {
            setSuggestion(nil)
            return
        }
        setSuggestion(suggested)
    }

    /// 接受灰字（`Tab`）：把**已输入的前缀**换成整词，光标落到末尾。
    /// 返回 `false` = 这一刻没有可接受的灰字 ⇒ 调用方交还默认实现（Tab 仍然缩进）。
    @discardableResult
    func accept() -> Bool {
        guard let suggestion, let host, let apply else { return false }
        let caret = suggestion.range.location + suggestion.range.length
        // 灰字画出来之后光标可能已经挪走（多一条防线：宁可不出，也不在错的位置上改字）。
        guard host.selectedRange() == NSRange(location: caret, length: 0) else {
            setSuggestion(nil)
            return false
        }
        guard apply(suggestion) else {
            setSuggestion(nil)
            return false
        }
        dismissedKey = nil
        setSuggestion(nil)
        return true
    }

    /// 忽略灰字（`Esc`）。返回 `false` = 本来就没有灰字 ⇒ 交还默认实现。
    @discardableResult
    func dismiss() -> Bool {
        guard let suggestion else { return false }
        dismissedKey = key(suggestion)
        setSuggestion(nil)
        return true
    }

    private func setSuggestion(_ next: InlineGhostSuggestion?) {
        guard next != suggestion else { return }
        let previous = suggestion
        suggestion = next
        guard let host else { return }
        // 只脏那两行（旧的与新的）：整块 `bounds` 是**整篇文档**那么高，无谓地标脏是白付的。
        if let previous { host.setNeedsDisplay(rect(for: previous) ?? host.bounds) }
        if let next { host.setNeedsDisplay(rect(for: next) ?? host.bounds) }
    }

    /// 灰字画在哪：**前缀末尾**那一格，纵向与该行文字对齐。
    ///
    /// 位置由排版结果算（`layoutManager`），不自己数字符宽度 —— 制表符、连字、代理对都算不对。
    private func rect(for suggestion: InlineGhostSuggestion) -> NSRect? {
        guard let host, let layoutManager = host.layoutManager, let container = host.textContainer else {
            return nil
        }
        let caret = suggestion.range.location + suggestion.range.length
        let origin = host.textContainerOrigin
        var x = origin.x + container.lineFragmentPadding
        var lineHeight = host.font?.boundingRectForFont.height ?? 16
        var y = origin.y
        if caret > 0, caret <= (host.textStorage?.length ?? 0) {
            let glyph = layoutManager.glyphIndexForCharacter(at: caret - 1)
            if glyph < layoutManager.numberOfGlyphs {
                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: glyph, length: 1), in: container
                )
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                x = origin.x + glyphRect.maxX
                y = origin.y + lineRect.minY
                lineHeight = lineRect.height
            }
        }
        let ghostFont = host.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let width = (suggestion.ghost as NSString).size(withAttributes: [.font: ghostFont]).width
        return NSRect(x: x - 1, y: y, width: min(width, 400) + 4, height: lineHeight)
    }

    /// 把灰字画上去。它**不是**文本存储的一部分 —— 所以必须在这里画，且只在这时候画。
    func draw(in dirtyRect: NSRect) {
        guard let host,
              let suggestion,
              host.window?.firstResponder === host,
              let container = host.textContainer,
              let rect = rect(for: suggestion),
              rect.intersects(dirtyRect) else { return }
        let ghostFont = host.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ghostFont,
            // 灰字走**三级文本**令牌（辅助信息那一档）：不抢正文字色，又不至于看不见。
            .foregroundColor: Theme.nsColor(TextTone.tertiary)
        ]
        let text = fitting(suggestion.ghost, in: rect, container: container, attributes: attributes)
        guard !text.isEmpty else { return }
        NSAttributedString(string: text, attributes: attributes)
            .draw(at: NSPoint(x: rect.minX + 1, y: rect.minY))
    }

    /// 灰字太长、这一行剩下的地方画不下 ⇒ 截断加省略号（**不静默消失**：
    /// 消失会让人以为"它本来就没有建议"，截断至少说明"还有，只是没地方放"）。
    private func fitting(
        _ ghost: String,
        in rect: NSRect,
        container: NSTextContainer,
        attributes: [NSAttributedString.Key: Any]
    ) -> String {
        guard let host else { return "" }
        let origin = host.textContainerOrigin
        let available = origin.x + container.size.width
            - container.lineFragmentPadding - (rect.minX + 1)
        guard available > 8 else { return "" }
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: attributes).width
        }
        if width(ghost) <= available { return ghost }
        var characters = Array(ghost)
        while !characters.isEmpty {
            characters.removeLast()
            let candidate = String(characters) + "…"
            if width(candidate) <= available { return candidate }
        }
        return ""
    }
}
