import AppKit
import SwiftUI
import DoyahCore

/// **笔记正文的只读呈现**（片 `N2-3a`「单击预览」· 人类主人令 `T-20261007-004` 第三节第 3 条）。
///
/// ## 它为什么存在（而不是给 `TextEditor` 挂 `.disabled(_:)`）
///
/// 判据要的是**读得出来的一条事实**：预览态下正文区那个 `NSTextView` 的 `isEditable == false`
/// （`TestsUISnapshot/NotesLayoutProbeTests.swift`）。实测（macOS 27 / 本机 2026-10-07，离屏宿主）：
/// 给 SwiftUI `TextEditor` 挂 `.disabled(true)` 之后，底层 `NSTextView` 的 `isEditable`
/// **仍然是 `true`**（`isSelectable` 也不变）—— `.disabled` 只是不投递事件，
/// **不是**「这块文本视图不可编辑」。所以只读这件事**必须**落在 `NSTextView` 自己身上，
/// 于是有了这一件。
///
/// ## 它与「可编辑那一半」的关系
///
/// · 可编辑那一半仍是 SwiftUI `TextEditor`（`NotesEditorView` 里 `.edit` 那一支），
///   底色 / 字色仍走 `.editorSurface()`（唯一出处 `App/Views/EditorSurface.swift`）；
/// · 这一件是**另一条呈现支**：自己按**同一套令牌**给底色与字色
///   （`Surface.content` / `TextTone.primary`），只是把 `isEditable` 置假。
///   它**不是**「多行编辑面」（`Scripts/check-editor-surface-tokens.py` 的台账口径是
///   `TextEditor(` 那种可编辑面）—— 这里没有可编辑面。
///
/// ## 边界（如实登记）
///
/// · 判的是**这一件真的把 `NSTextView.isEditable` 置了假**；「用户点不动它」是同一件事的
///   另一面（不可编辑的 `NSTextView` 本来就不接受打字），不另开判据；
/// · 只读但**可选中**（`isSelectable = true`）：预览要能选中 / 复制正文，这不是编辑。
struct NotePreviewBody: NSViewRepresentable {

    /// 该条笔记的正文（**只读**：这一件不回写 `AppState`）。
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        configure(textView)
        textView.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        // 每次更新都重申一次「不可编辑」：模式从 `.edit` 切回来时，重建的视图也走这里不会漏。
        configure(textView)
        if textView.string != text { textView.string = text }
    }

    /// 只读 + 令牌底色 / 字色（与可编辑那一半同一套令牌）。
    private func configure(_ textView: NSTextView) {
        textView.isEditable = false          // ← 判据读的就是这一条
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = Theme.nsColor(Surface.content)
        textView.textColor = Theme.nsColor(TextTone.primary)
        textView.font = Theme.nsFont(.mono)
    }
}
