import Foundation

/// 括号匹配高亮的**取色角色**（`FR-STD-WS-EDIT-020`）。
///
/// 为什么要分成三个角色而不是一个布尔：**「没配上」与「太远没扫到」不是同一件事**，
/// 界面上要说的话也不一样（前者是「这里不匹配」，后者是「配对在很远的地方，没扫到」）。
/// 一条 `isMatched: Bool` 会把这两种情况压成一个红叉，用户会以为自己的代码坏了。
public enum BracketHighlightRole: String, CaseIterable, Sendable {
    /// 光标旁那一半 + 它的配对者：**两个都亮**。
    case matched
    /// 没配上：只亮光标旁这一个，走告警色。
    case unmatched
    /// 扫描到上限还没找到配对者：**不是不匹配**，走另一档色与另一句话。
    case truncated

    /// 角色 → 主题令牌。**颜色只从这里来**，界面层不许自己写 RGB / `NSColor(red:…)`。
    ///
    /// 这条不是洁癖：主题有五套（深浅各一份值），写死的颜色在换主题时要么看不见、
    /// 要么在浅色主题下把字盖住 —— 而判据能守住的正是「取的是哪个令牌」。
    public func color(in theme: DesignTheme) -> ThemeColor {
        switch self {
        case .matched: return AccentFamily.accent.color(in: theme)
        case .unmatched: return StatusTone.danger.color(in: theme)
        case .truncated: return StatusTone.warning.color(in: theme)
        }
    }

    /// 底色浓度（0…1）。比前景色淡得多：它衬在字底下，不能把可读性拖下去。
    ///
    /// 三档不同值是有意的 —— 「配对成功」不该和「不匹配」看起来一样浓，
    /// 否则用户扫一眼分不清这是提示还是报错。
    public var backgroundOpacity: Double {
        switch self {
        case .matched: return 0.28
        case .unmatched: return 0.22
        case .truncated: return 0.16
        }
    }
}

/// 一次括号匹配高亮的落法：亮哪几段（UTF-16 单元，长度恒为 1）+ 用哪个角色取色。
///
/// 坐标口径与 `CodePairingPlan` 一致：一律 **UTF-16 单元**（`NSTextView.selectedRange()` 那套），
/// 不是 `String.Index` —— 含 emoji 时两者会差出位置（`Core/CodeLines` 头顶注释讲过同一个坑）。
public struct BracketHighlightPlan: Equatable, Sendable {
    /// 本次高亮的角色（决定颜色与界面上的说法）。
    public let role: BracketHighlightRole
    /// 要涂底色的字符范围；**按位置升序**。`matched` 恒为 2 段，另两个角色恒为 1 段。
    public let spans: [NSRange]

    public init(role: BracketHighlightRole, spans: [NSRange]) {
        self.role = role
        self.spans = spans
    }
}

/// 括号匹配高亮（`FR-STD-WS-EDIT-020`）：光标紧邻括号时，与它配对的那一个同时点亮。
///
/// ## 为什么是纯逻辑、纯函数
///
/// 「光标在哪、亮哪两个字符」是一条**可以逐字钉死**的判定 —— 可以在 Core 里跑完，
/// 不需要开界面。宿主层（`CodeTextView.refreshBracketHighlight`）只负责把 `spans` 涂上去、
/// 把 `role` 换成令牌色。
///
/// ## 口径（每一条都有判据）
///
/// · **谁算「紧邻」**：先看光标左边那一个字符、再看右边那一个（与 `CodeAutoPairing.match` 同一套取法，
///   **不在这里另写一份**）—— 刚敲完左括号时用户的注意力在它身上；
/// · **有选中就不亮**：选中一段时用户在做别的事，这时点亮半个括号只是噪声；
/// · **配对成功 ⇒ 两个都亮**（光标旁那一半 + 配对者），按位置升序给；
/// · **没配上 ⇒ 只亮那一个**，角色 `unmatched`；
/// · **扫到上限 ⇒ 只亮那一个**，角色 `truncated`（话与色都与 `unmatched` 不同）；
/// · **附近没有括号 ⇒ 什么都不亮**（返回 `nil`，宿主据此把上一次的高亮清掉）。
public enum BracketHighlight {

    /// 由「全文 + 当前选区」算出该亮哪几段。`nil` = 附近没有括号（界面要清掉上一次的）。
    ///
    /// - Parameters:
    ///   - text: 当前全文。
    ///   - selection: 当前选区（UTF-16）；`length > 0` ⇒ 直接 `nil`。
    public static func plan(in text: String, selection: NSRange) -> BracketHighlightPlan? {
        guard selection.location != NSNotFound, selection.length == 0 else { return nil }
        guard let match = CodeAutoPairing.match(in: text, caret: selection.location) else { return nil }

        let anchor = NSRange(location: match.bracket, length: 1)
        guard let partner = match.partner else {
            return BracketHighlightPlan(
                role: match.truncated ? .truncated : .unmatched,
                spans: [anchor]
            )
        }
        // 两个都亮：顺序按位置排（不是「先锚点后配对」）—— 界面与判据取到同一份顺序，
        // 免得「点的是左括号还是右括号」变成调用顺序的副作用。
        let pair = [anchor, NSRange(location: partner, length: 1)]
        return BracketHighlightPlan(
            role: .matched,
            spans: pair.sorted { $0.location < $1.location }
        )
    }
}
