import Foundation

/// 查询编辑器里**正在编辑的文本**（队列 `L-148`）。
///
/// ## 为什么要有它
///
/// `SQLEditorView.textDidChange` 每敲一个键都会把**整篇文本**推给 SwiftUI 绑定。
/// 这条绑定原来直接写**全局** `AppState`（`@Published var tabs`，`AppState.swift:268`）
/// ⇒ 观测 `appState` 的**整个窗口**同步重算 + AppKit 布局。
/// 5,000 行 / 739,219 字符实测 **每键 31.74 ms**（产品代码内打点，见
/// `TestsUISnapshot/PerfTypingProbeTests.swift`）—— 用户侧表现就是"打字、删除明显卡顿"。
///
/// 对照：**工作区编辑器不卡**，是因为它写进**独立的** `WorkspaceTabsModel`，
/// 每键重算范围只有工作区那一小块。本模型就是把同一条口径搬到数据库侧。
///
/// ## 口径（不许改）
///
/// * `AppState.tabs[i].sql` 仍是**唯一权威副本** —— 结果区 / 侧栏 / 菜单可用性读它，
///   所以它们**不需要**改观测面。
/// * 本模型只是"编辑器缓冲"：每键只写这里；在**提交点**由 `AppState.commitEditorDraft(for:)`
///   同步回权威副本 —— 执行前 / 关闭页签前 / 视图消失（切页签、切模块）时。
/// * **不设提交点 = 执行到旧 SQL**；所以每新增一个读 `tab.sql` 的入口，都要问一句
///   "这里要不要先提交草稿"。
///
/// ## 为什么不把 `tabs` 整体搬出 `AppState`
///
/// 那要迁移 13 处 `.tabs` 访问的**观测面**（结果区 / 侧栏 / 菜单），漏一个就是
/// **静默不变** —— 比本体量出来的性能问题更难查。选"缓冲 + 提交点"这条外科路线。
@MainActor
final class QueryEditorBuffer: ObservableObject {

    /// 与权威副本**不同**的那些页签的草稿（相同的不存：省内存，也便于判断"有没有未提交"）。
    @Published private(set) var drafts: [UUID: String] = [:]

    /// 编辑器该显示的文本：有草稿用草稿，否则用权威副本。
    func displayText(for tabID: UUID, authoritative: String) -> String {
        drafts[tabID] ?? authoritative
    }

    /// 每键调用（**只许写这里**，不许顺手写 `AppState`）。
    func noteEdit(_ text: String, for tabID: UUID) {
        drafts[tabID] = text
    }

    func hasDraft(for tabID: UUID) -> Bool { drafts[tabID] != nil }

    /// 把草稿交给权威副本（由 `AppState.commitEditorDraft(for:)` 调用）。
    func commit(for tabID: UUID, apply: (String) -> Void) {
        guard let draft = drafts[tabID] else { return }
        apply(draft)
        drafts[tabID] = nil
    }

    /// 页签关掉 / 内容作废时丢弃草稿。
    func discard(for tabID: UUID) {
        drafts[tabID] = nil
    }
}
