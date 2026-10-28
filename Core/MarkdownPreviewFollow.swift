import Foundation

/// 预览跟随滚动的**会话面**：哪个页签、那个页签的光标停在第几行（`FR-STD-WS-WEB-002` 收口片）。
///
/// ## 为什么状态得带页签身份
///
/// 这一层此前只有**一个** `Int`（`MarkdownPreviewCursorModel.line`）。一个标量在单页签下够用，
/// 一旦切页签就出两件事：
///
/// ① **旧行号套到新文档上** —— 从光标停在第 800 行的长文档切到另一篇，预览按 800 去找落点；
///    新文档够长就跳到一个**跟用户当前操作无关**的块（够短则越界不动，于是同一缺陷时隐时现）；
/// ② **切回来时位置丢了** —— 用户从 A 翻到 B 再回 A，A 的预览从头开始，得手动再滚回去。
///
/// 判据要判「切页签不串行号」，就必须先有「按页签记」这件事本身，所以把它收成 Core 里的
/// 一个纯值类型（`App/` 的模型只负责把它发布给视图）。
///
/// ## 四条写死口径
///
/// - **越界不猜**：`0` / 负数一律丢弃（与 `MarkdownPreviewContent.scrollTarget` 越界返 `nil` 同一条口径）；
/// - **没有活跃页签时的报数丢弃，不记账**：不知道该记给谁 —— 猜一个就等于把行号记到别人名下
///   （编辑器第一帧可能在 `activate` 之前就报一次光标）；
/// - **同一行重复报数不发布**（连按方向键不该让预览反复对齐同一块）；
/// - **关掉的页签不再记**（`retain`）：留着的话，同一个文件再打开时会跳到一个旧位置。
///
/// 这些都不碰渲染：本类型只回答「滚到哪一块」，块下标仍由 `MarkdownDocument.anchor(forSourceLine:)` 给。
public struct MarkdownPreviewFollow: Equatable, Sendable {

    /// 行号 1 起（与 `CodeLines` 的行号同一口径）；初值 = 文档开头。
    public static let firstLine = 1

    /// 当前该跟哪个页签；`nil` = 还没有页签被激活过。
    public private(set) var activeTab: UUID?

    /// **当前页签**的光标行 —— 预览读的就是它。
    public private(set) var line: Int

    /// 各页签各自记住的行（`retain` 之外只增不改）。
    private var remembered: [UUID: Int]

    public init() {
        activeTab = nil
        line = Self.firstLine
        remembered = [:]
    }

    /// 切到某个页签（打开文件 / 换选中页签 / 视图首次出现时调）。
    ///
    /// 返回该页签该跟的行：记过就回到记的那个位置，没记过就是第 1 行。
    /// 同一页签重复激活是幂等的（返回现价、不改任何状态）。
    @discardableResult
    public mutating func activate(_ tab: UUID) -> Int {
        guard activeTab != tab else { return line }
        activeTab = tab
        line = remembered[tab] ?? Self.firstLine
        return line
    }

    /// 编辑器报来一次光标行（**带页签身份**：报数的那一刻就知道这条该记给谁，不用猜）。
    ///
    /// 返回**要不要发布**（`true` = 这一行跟当前页签记的不一样，视图该滚了）。
    /// 三档返回 `false`，各有由头：
    /// - 越界（`<= 0`）：不猜位置；
    /// - 报数那个页签**不是**当前活跃页签（换页签的那一瞬间，正在拆掉的旧编辑器还会报一次）：
    ///   记在它自己名下，但**不许**拿它去改当前预览 —— 那正是「切页签串行号」的另一半；
    /// - 与现价相同：同一块不重复对齐（连按方向键）。
    @discardableResult
    public mutating func report(line reported: Int, tab: UUID) -> Bool {
        guard reported > 0 else { return false }
        remembered[tab] = reported
        guard tab == activeTab else { return false }
        guard reported != line else { return false }
        line = reported
        return true
    }

    /// 对着现存的页签集收一遍：**关掉的页签的记录丢掉**；活跃页签被关掉就回到「没有活跃页签」。
    ///
    /// 为什么不只是「删多余的那些」：同一个文件关掉再打开会得到**新的页签标识**，
    /// 记录留着也没人再按那个号取 —— 但它会让「这个文件上次停在哪」看起来还活着，
    /// 于是下一次「复原」复到的是上一份文档的位置。
    public mutating func retain(_ tabs: Set<UUID>) {
        remembered = remembered.filter { tabs.contains($0.key) }
        if let tab = activeTab, !tabs.contains(tab) {
            activeTab = nil
            line = Self.firstLine
        }
    }
}
