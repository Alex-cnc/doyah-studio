import Foundation
import Combine

/// 编辑器命令（由工具栏「编辑」菜单发出）。
enum EditorCommand: Equatable {
    case showFind
    case showReplace
    case goToLine(line: Int, column: Int?)
    case indent
    case outdent
    case clear
    case format
    /// 多光标与列编辑（FR-EDIT-27）。
    case selectNextOccurrence
    case addCursorAbove
    case addCursorBelow
}

/// 工具栏 → 当前编辑器（`NSTextView`）的一次性命令通道。
///
/// `SQLEditorView` 观察 `request`，命中自己的 `tabID` 且请求 id 变化时执行一次。
final class EditorCommandCenter: ObservableObject {
    static let shared = EditorCommandCenter()

    struct Request: Equatable {
        let id: UUID
        let tabID: UUID
        let command: EditorCommand
    }

    @Published private(set) var request: Request?

    /// 各页签编辑器最近一次的光标 / 选区（UTF-16，`NSRange` 语义）。
    ///
    /// **刻意不做成 `@Published`**：光标每移动一次都会上报，若触发 SwiftUI 重绘，
    /// 打字过程会持续重算工具栏。执行时按需读取即可。
    private var selections: [UUID: NSRange] = [:]

    /// 上报选区时**那一段文字**（用来判断记录有没有过期）。
    ///
    /// 只看长度对不对是不够的 —— 2026-09-27 现场：编辑器重建时"恢复"的是 `21+22`，
    /// 而那个偏移对应的已经不是用户选的那段（文本改动之后偏移就漂了）。照原样放回去 =
    /// 高亮落到别的语句上；而「选中片段」执行的就是高亮那段 ⇒ **跑错段落**。
    private var selectionTexts: [UUID: String] = [:]
    private let selectionLock = NSLock()

    private init() {}

    func send(_ command: EditorCommand, to tabID: UUID) {
        request = Request(id: UUID(), tabID: tabID, command: command)
    }

    /// 编辑器上报选区（`length == 0` 表示只有光标）。
    /// - Parameter text: 上报那一刻选中的文字（`length == 0` 传空串），用于判断记录是否过期。
    func reportSelection(tabID: UUID, range: NSRange, text: String) {
        selectionLock.lock()
        selections[tabID] = range
        selectionTexts[tabID] = text
        selectionLock.unlock()
    }

    /// 读取某个页签最近的选区；没有上报过则返回 `nil`。
    func selection(for tabID: UUID) -> NSRange? {
        selectionLock.lock()
        defer { selectionLock.unlock() }
        return selections[tabID]
    }

    /// 页签关闭时清掉记录，避免按旧页签 id 取到过期选区。
    func forgetSelection(tabID: UUID) {
        selectionLock.lock()
        selections.removeValue(forKey: tabID)
        selectionTexts.removeValue(forKey: tabID)
        liveTextViews.removeValue(forKey: tabID)
        selectionLock.unlock()
    }

    /// 这条选区记录**现在还原样成立吗**：位置、长度、**以及内容**都要对得上。
    ///
    /// 编辑器重建后"把选区放回去"之前必须先问这一句。2026-09-27 现场：重建时恢复的是
    /// `21+22`，而那个偏移在文本改动之后已经不对应用户选的那段 —— 放回去等于把高亮搬到
    /// 别的语句上，而「选中片段」执行的正是高亮那段 ⇒ 用户点 delete、跑的是别的。
    /// 内容对不上就**不还原**（宁可空着），并由调用方留一行日志。
    func restorableSelection(tabID: UUID, in text: String) -> NSRange? {
        selectionLock.lock()
        let recorded = selections[tabID]
        let recordedText = selectionTexts[tabID]
        selectionLock.unlock()

        guard let recorded, recorded.length > 0 else { return nil }
        let nsText = text as NSString
        guard recorded.location >= 0, NSMaxRange(recorded) <= nsText.length else { return nil }
        let current = nsText.substring(with: recorded)
        guard let recordedText, recordedText == current else { return nil }
        return recorded
    }

    /// 记录过期（位置还在，但那段文字已经换了）时用它留一行日志：判据看不见，现场要能查。
    func recordedText(tabID: UUID) -> String? {
        selectionLock.lock()
        defer { selectionLock.unlock() }
        return selectionTexts[tabID]
    }

    // MARK: - 显示中的编辑器（选区的**唯一可信来源**）

    /// 当前**显示中**的编辑器（每个页签一个）。`weak`：视图销毁后不留引用。
    ///
    /// 为什么需要它：上面那份缓存记录并不可信 —— 视图重建、外部文本同步
    /// （`applyExternalText` 会把选区设成 `(0,0)`）都会覆盖它。2026-09-27 人工点验现场：
    /// 需求提出者选中 `DELETE` 执行，实际到服务器的却是脚本里第 1 条 `SELECT`
    /// （数据库侧 `n_tup_del = 0` 可证那条 DELETE **从未到达服务器**）
    /// ⇒ 解析用的选区不是他眼里高亮的那一段。**唯一可信来源 = 显示中的那个 `NSTextView`**。
    private var liveTextViews: [UUID: WeakTextView] = [:]

    private struct WeakTextView {
        weak var view: SQLTextView?
    }

    /// 登记**显示中**的编辑器；同一页签重复登记时以最新那个视图为准。
    func register(textView: SQLTextView, for tabID: UUID) {
        selectionLock.lock()
        liveTextViews[tabID] = WeakTextView(view: textView)
        selectionLock.unlock()
    }

    /// 编辑器**此刻真实**的选区（直接问显示中的 `NSTextView`）。⚠️ 只在主线程调用。
    func liveSelection(for tabID: UUID) -> NSRange? {
        selectionLock.lock()
        let view = liveTextViews[tabID]?.view
        selectionLock.unlock()
        return view?.selectedRange()
    }

    /// **执行**时用的选区：以显示中的编辑器为准，取不到才退回缓存记录。
    ///
    /// 顺手记下「缓存记录 vs 实际选区」的不一致：这类故障纯函数判据看得见、
    /// 真编辑器里的时序看不见，只能靠现场留痕（下一次谁遇到，日志里有原文）。
    func selectionForExecution(tabID: UUID) -> NSRange? {
        let live = liveSelection(for: tabID)
        if let live, let recorded = selection(for: tabID), recorded != live {
            lastSelectionMismatch = SelectionMismatch(recorded: recorded, live: live)
        } else {
            lastSelectionMismatch = nil
        }
        return live ?? selection(for: tabID)
    }

    /// 最近一次「缓存记录 ≠ 实际选区」（`selectionForExecution` 每次都会重算）。
    private(set) var lastSelectionMismatch: SelectionMismatch?

    struct SelectionMismatch: Equatable {
        var recorded: NSRange
        var live: NSRange
    }
}
