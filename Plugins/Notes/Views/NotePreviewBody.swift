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

    /// **正文被按下（单击或双击）时回调** —— 由 `NotesPanel` 接 `AppState.beginEditingCurrentNote()`
    /// （人类主人裁决 `T-20261007-077`：**R3 预览态单击正文 ⇒ 进编辑 · R4 双击 ⇒ 进编辑**）。
    ///
    /// 默认空实现：让「忘了接线」表现为**没反应**（判据当场红），而不是编译不过、
    /// 也不是落进 AppKit 的跟踪循环（见 `PreviewTextView.mouseDown` 那条实测）。
    var onActivate: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PreviewTextView()
        textView.onActivate = onActivate
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        // 尺寸口径与 `NSTextView.scrollableTextView()` 一致，只把载体换成子类。
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        configure(textView)
        textView.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        // 回调可能随视图重建换人（捕的是 `AppState`）⇒ 每次更新都重申一次。
        (textView as? PreviewTextView)?.onActivate = onActivate
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

/// **预览态正文那个 `NSTextView`**：把「在这块文本上按下鼠标」这件事**投出去**
/// （`onActivate`；人类主人裁决 `T-20261007-077` 的 R3 / R4）。
///
/// ## 为什么必须落在这一层
///
/// 修前那一版把「双击进编辑」挂在 SwiftUI 那一侧（`NotePreviewBody(...)` 上的
/// `.onTapGesture(count: 2)`）。实测（本机 2026-10-07，离屏宿主）：**事件收下了但 SwiftUI 的
/// 手势不响应**（`window.sendEvent` ⇒ `notesModule` 不动），而正文那块 `NSTextView` 本来就
/// **自己吃掉**落进去的鼠标事件 ⇒ 手势挂在外层，按在正文上永远轮不到它。
/// AppKit 这一层是**同步、确定**的：按下就调回调，没有手势判定那一步。
///
/// ## 不许把 `super.mouseDown(with:)` 加回来（**别改成那样**）
///
/// 本机实测：`NSTextView.mouseDown(with:)` 会落进 **AppKit 的跟踪循环**、等一个 `mouseUp`。
/// 真实的鼠标当然有抬起那一下，但**离屏探针**里只有一个孤立事件 ⇒ 整个用例挂在那一行
/// （实测跑满 4 分钟 CPU 不返回）。所以有回调时**只调回调**、不下传；没回调时
/// （`onActivate == nil`，例如别处单用这一件）才落回 AppKit 自己的处置。
final class PreviewTextView: NSTextView {

    /// 正文被按下时回调；`nil` = 这一件没接产品那条路（落回 AppKit 自己的处置）。
    var onActivate: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if let onActivate = onActivate {
            onActivate()
            return
        }
        super.mouseDown(with: event)
    }
}
