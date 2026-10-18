import Foundation

/// 一次**已经落盘**的写入 / 定点修改（`FR-AI-25` ⑤：「差异应用后可一步撤销，撤销后文件逐字节回到应用前」）。
///
/// 为什么要把 `before` 整段存下来，而不是存一份反向补丁：
/// **撤销的正确性只认字节**。反向补丁依赖 diff 的可逆性（本仓的 `AgentTextDiff` 明确不是最小编辑距离，
/// 它只保证「每行真实来自原文或新文」），而撤销这件事没有第二次机会 —— 出错就是用户的文件被改坏。
/// 存原文是有代价的（内存里多一份正文），但**一次写入的大小本来就在审批单里给人看过**，
/// 这个代价比「撤销回不到原样」小得多。因此本类型不做「压缩 / 只存增量」这类优化，宁可直白。
public struct AgentAppliedEdit: Equatable, Sendable {

    /// 兑现这次写入的那张工具卡片（撤销按钮挂在卡片上，凭它找回原文）。
    public var cardID: UUID
    /// 工作区相对路径（与审批单上 `path` 同一套写法；撤销时再走一次沙箱解析）。
    public var path: String
    /// 应用前盘上的原文；**`nil` = 应用前这个文件不存在**（撤销 = 删掉它，不是写成空串）。
    public var before: String?
    /// 应用后的原文（撤销前核对盘上还是不是它 —— 别把用户后来自己改的东西一起回退）。
    public var after: String
    public var at: Date

    public init(cardID: UUID, path: String, before: String?, after: String, at: Date = Date()) {
        self.cardID = cardID
        self.path = path
        self.before = before
        self.after = after
        self.at = at
    }

    /// 这次写入是**新建**文件（撤销 = 删）。
    public var createdFile: Bool { before == nil }
}

/// 撤销时要落到盘上的东西（纯值 ⇒ 判据不用真写盘就能断言「撤销会写成什么」）。
public enum AgentEditUndoPayload: Equatable, Sendable {
    /// 把文件写回这段正文（逐字节）。
    case restore(String)
    /// 应用前文件不存在 ⇒ 删掉它。
    case remove
}

/// 撤销的结局（**机器码 + 细节**，人话由界面给 —— 与 `AgentToolRefusal` 同一条纪律）。
public enum AgentEditRevertOutcome: Equatable, Sendable {
    /// 写回去了（带回去后盘上的正文，供判据逐字节比对）。
    case restored(String)
    /// 删掉了（应用前本来没有这个文件）。
    case removed
    /// 拒了。`detail` 说明为什么（`alreadyReverted` / `drifted` / 路径越界说明）。
    case refused(AgentToolRefusal, detail: String)
}

/// 已应用写入的**账**（一次任务里可能改好几个文件）。
///
/// 口径：
/// · 一张卡片只对应一次写入 ⇒ **按卡片号**找回原文，不按路径（同一文件被改两次时，路径会打架）；
/// · **一步撤销** = 最近一次还没撤的（`latestUndoable`）—— 界面上的「撤销」按钮点一下就走这一条；
/// · 撤销过的条目**留在账上**（`undone` 标记），不删记录 —— 事后要能回答「撤过哪一次」。
public struct AgentEditJournal: Equatable, Sendable {

    public private(set) var entries: [AgentAppliedEdit]
    /// 已经撤销掉的卡片号（按次：撤过就不能再撤一次 —— 否则第二次会把「用户后来改的内容」再覆盖一遍）。
    public private(set) var undone: Set<UUID>

    public init(entries: [AgentAppliedEdit] = [], undone: Set<UUID> = []) {
        self.entries = entries
        self.undone = undone
    }

    /// 记一笔（应用成功后立刻记；**先记再动界面**，否则按钮点下去找不到原文）。
    @discardableResult
    public mutating func record(cardID: UUID, path: String, before: String?, after: String,
                                at: Date = Date()) -> AgentAppliedEdit {
        let edit = AgentAppliedEdit(cardID: cardID, path: path, before: before, after: after, at: at)
        entries.append(edit)
        undone.remove(cardID)
        return edit
    }

    public func entry(for cardID: UUID) -> AgentAppliedEdit? {
        entries.last { $0.cardID == cardID }
    }

    /// 这一次还能不能撤（有账、没撤过）。
    public func canUndo(_ cardID: UUID) -> Bool {
        entry(for: cardID) != nil && !undone.contains(cardID)
    }

    /// 还没撤过的那些（按应用顺序）。
    public var undoable: [AgentAppliedEdit] {
        entries.filter { !undone.contains($0.cardID) }
    }

    /// **一步撤销**的目标：最近一次还没撤的。
    public var latestUndoable: AgentAppliedEdit? { undoable.last }

    /// 标记已撤销（**只标不改 entries**）。
    @discardableResult
    public mutating func markUndone(_ cardID: UUID) -> Bool {
        guard canUndo(cardID) else { return false }
        undone.insert(cardID)
        return true
    }

    /// 撤销要写什么 —— **纯函数**，判据直接打它。
    public static func payload(for edit: AgentAppliedEdit) -> AgentEditUndoPayload {
        if let before = edit.before { return .restore(before) }
        return .remove
    }
}

/// 真撤销（落盘）。与 `AgentWorkspaceTools` 同一条边界纪律：**路径必须落在工作区内**。
public struct AgentEditReverter: Sendable {

    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    /// 撤销一次已应用的写入。
    ///
    /// **先核对盘上还是不是「应用后」那一份**：不是 ⇒ 拒（`drifted`）。
    /// 为什么不让它硬回退：审批之后到撤销之间，用户 / 别的工具可能已经又改过这个文件 ——
    /// 拿旧原文盖上去就是把人家后来的改动一起抹掉，比「撤不了」严重得多。
    /// `force` 只给「人明确说了以应用前为准」的场合，界面默认不传。
    public func revert(_ edit: AgentAppliedEdit, force: Bool = false) -> AgentEditRevertOutcome {
        guard case .inside(let url) = AgentWorkspaceSandbox.resolve(edit.path, in: root) else {
            return .refused(.outsideWorkspace, detail: edit.path)
        }

        let current = try? String(contentsOf: url, encoding: .utf8)
        if !force {
            // 应用后那份必须还在：盘上没这个文件（且应用时它存在）⇒ 已被别人删 / 挪 ⇒ 拒。
            guard current == edit.after else {
                return .refused(.unreadable, detail: "drifted")
            }
        }

        switch AgentEditJournal.payload(for: edit) {
        case .remove:
            guard current != nil else {
                // 已经不在了 —— 撤销目的（文件回到「不存在」）已经达成，如实报，不当失败。
                return .removed
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                return .refused(.unreadable, detail: url.lastPathComponent)
            }
            return .removed
        case .restore(let text):
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                return .refused(.unreadable, detail: url.lastPathComponent)
            }
            return .restored(text)
        }
    }
}

/// 落盘之后，**编辑器缓冲区**要不要跟着动（`FR-AI-25` ⑤ 的界面半）。
///
/// 为什么要单列一条判断而不是「写盘之后一律重载」：编辑器手里是**内存正文**，
/// 用户可能正在里面打字（`isDirty`）。这时用磁盘内容盖上去 = 悄悄丢掉用户没保存的输入。
/// 所以口径与 `AppState.reloadTab(force: false)` 完全一致：
/// · 页签开着且**没有**未保存改动 ⇒ 立刻重载（用户眨眼就看见改动，不用等文件监听那一拍）；
/// · 有未保存改动 / 没开着 ⇒ **缓冲区不动**，磁盘已变这件事由既有的「磁盘已改」提示交给人决定。
public enum AgentEditBufferAction: String, Equatable, Sendable {
    case reload
    case leaveBuffer
}

public enum AgentEditBufferPlan {
    public static func action(hasOpenTab: Bool, isDirty: Bool) -> AgentEditBufferAction {
        guard hasOpenTab, !isDirty else { return .leaveBuffer }
        return .reload
    }
}
