import AppKit
import DoyahCore

/// 撤销步的**唯一收口**（`FR-STD-WS-EDIT-014`）：两个编辑面的每一次文本改动都从这里过。
///
/// 为什么要有这张网：一次用户动作该不该独占一步撤销，是**判定**（住 `Core/UndoGranularity`）；
/// 而「在哪断开」只有拿着 `NSTextView` 的地方才做得到（`breakUndoCoalescing` 与
/// `undoManager.setActionName` 都是 AppKit 的东西）。于是这里只做搬运：
///
/// 1. 动手前按 Core 的判定决定要不要 `breakUndoCoalescing()`（← 不并进上一步）；
/// 2. 动作落地后给这一步**命名**（编辑菜单里那一行读的就是它：`撤销 移动行` 而不是 `撤销`）；
/// 3. 原子动作再来一次 `breakUndoCoalescing()`（→ 下一步不并进这一步）。
///
/// **为什么不 `beginUndoGrouping` / `endUndoGrouping`**：实测空分组会在管理器里留下
/// 一层废步（`groupingLevel` 停在 1、`canUndo` 变真、按一次 ⌘Z 什么都不发生）——
/// 而「这次动作会不会落地」只有跑完才知道，开组时没法提前判断。本仓的落地口径是
/// 「一次用户动作 = 一次 `shouldChangeText` → `replaceCharacters` → `didChangeText`」，
/// 一次登记天然就是一步，所以只在边界上断开就够（该口径由
/// `Tests/UndoScopeWiringTests` 的源树判据钉住：编辑器里每个 `didChangeText()` 都必须
/// 落在一个 `performUndoable` 体内）。
protocol UndoScopedEditor: AnyObject {
    var undoGranularity: UndoGranularity { get set }
}

extension UndoScopedEditor where Self: NSTextView {
    /// 按 Core 的粒度判定执行一次文本改动。
    ///
    /// - Returns: `body` 的返回值（`false` = 这次没落地，调用方应当把按键交还系统）。
    @discardableResult
    func performUndoable(_ kind: UndoEditKind, _ body: () -> Bool) -> Bool {
        let decision = undoGranularity.decide(kind)
        if decision.breakBefore {
            breakUndoCoalescing()
        }
        let landed = body()
        guard landed else { return false }
        if decision.breakAfter {
            // 先命名再断开：`setActionName` 命中的是**当前这一组**，断开之后就没有「这一组」了。
            undoManager?.setActionName(L(kind.actionNameKey))
            breakUndoCoalescing()
        }
        return true
    }

    /// 整篇换掉（打开另一个文件 / 会话恢复）时重新起算：撤销链从这里不连续了。
    func restartUndoChain() {
        undoGranularity.reset()
    }
}
