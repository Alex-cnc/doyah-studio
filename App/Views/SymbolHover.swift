import AppKit
import DoyahCore

/// `FR-STD-WS-NAV-006` 的**界面接线**：悬停给一句话说明 + 定义位置，⌘ 点击跳到定义。
///
/// ## 为什么要一份共享实现而不是各编辑器一份
///
/// 同一动作在两个编辑面上（工作区的 `CodeTextView` 与数据库侧的 `SQLTextView`）**必须同一份**：
/// 各写一份的典型后果是「代码文件里悬停有说明、SQL 里没有」，或者两边的判定条件慢慢分家
/// （一个认 `⌘`、一个认 `⌥`）。这里只留一件事给各编辑器自己回答 ——
///
/// ```swift
/// var symbolLanguage: TextLanguage { .swift }        // CodeTextView ⇒ completionLanguage
/// var symbolLanguage: TextLanguage { .sql }          // SQLTextView
/// ```
///
/// 其余（取值 → 解析 → 出句子 → 落到文本上）全在这份扩展里。
///
/// ## 一句话说明的边界（需求 ③ ④）
///
/// 查不到就**明说查不到**：`notAnIdentifier`（光标不在名词上）不出提示，因为它不是错误；
/// `notDeclaredInFile` / `noSymbolsForLanguage` 出提示且**不带箭头、不带位置** ——
/// 没有定义可跳，界面就不能长得像有。**跨文件与语言服务器不在本期**，所以这里
/// 一次网络请求、一次全仓检索都没有（`SymbolIndex` 只看当前这份文本）。

/// 悬停与跳转需要的两样输入。
protocol SymbolHoverHost: AnyObject {
    /// 这份文本按哪种语言建符号表。
    var symbolLanguage: TextLanguage { get }
}

extension SymbolHoverHost where Self: NSTextView {

    // MARK: 解析

    func symbolLookup(atCharacterIndex index: Int) -> SymbolLookup {
        SymbolIndex.lookup(in: string, language: symbolLanguage, at: index)
    }

    func symbolLookup(at point: NSPoint) -> SymbolLookup {
        symbolLookup(atCharacterIndex: characterIndexForInsertion(at: point))
    }

    // MARK: 悬停（系统 tooltip，动态文案）

    /// 把整个可见区登记成一枚 tool tip：文案在**弹出那一刻**按鼠标位置算
    /// （静态 `toolTip` 只能写一句话，而这里每一格的答案都不同）。
    func installSymbolToolTip() {
        removeAllToolTips()
        addToolTip(bounds, owner: self, userData: nil)
    }

    /// tooltip 的文案：查得到就给「名字 · 类别 · 第几行 + 怎么跳」，查不到就说查不到。
    /// `nil` = 这一刻不弹（光标不在名词上 —— 那不是错误，弹一个框只会打扰）。
    func symbolToolTipText(at point: NSPoint) -> String? {
        switch symbolLookup(at: point) {
        case let .found(hover):
            let kind = Self.symbolKindText(hover.kind)
            let line = "\(L(.symbolLineLabel)) \(hover.definitionLine)"
            var parts = [hover.name, kind, line]
            // 别名 / 列：把真正的表名带上（`o` 是谁的别名，一句话里就说清）。
            if let target = hover.target, !target.isEmpty { parts.append(target) }
            parts.append(L(.symbolGoToDefinitionHint))
            return parts.joined(separator: " · ")
        case let .miss(reason):
            switch reason {
            case .notAnIdentifier, .protectedRegion:
                return nil
            case .notDeclaredInFile:
                return L(.symbolNoDefinitionInFile)
            case .noSymbolsForLanguage:
                return L(.symbolNoSymbolsForLanguage)
            }
        }
    }

    // MARK: 跳转

    /// ⌘ 点击的落点：查得到就把光标落到定义上并滚到可见；查不到**什么都不做**（不猜、不跳）。
    @discardableResult
    func revealDefinition(at point: NSPoint) -> Bool {
        guard let hover = symbolLookup(at: point).hover else { return false }
        setSelectedRange(hover.definition)
        scrollRangeToVisible(hover.definition)
        return true
    }

    @discardableResult
    func revealDefinition(atCharacterIndex index: Int) -> Bool {
        guard let hover = symbolLookup(atCharacterIndex: index).hover else { return false }
        setSelectedRange(hover.definition)
        scrollRangeToVisible(hover.definition)
        return true
    }

    // MARK: 文案

    static func symbolKindText(_ kind: SymbolKind) -> String {
        switch kind {
        case .function: return L(.symbolKindFunction)
        case .type: return L(.symbolKindType)
        case .variable: return L(.symbolKindVariable)
        case .table: return L(.symbolKindTable)
        case .alias: return L(.symbolKindAlias)
        case .column: return L(.symbolKindColumn)
        }
    }
}
