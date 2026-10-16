import Foundation

/// 一次「自动配对 / 跳引号」编辑动作的落法。
///
/// 坐标口径与 `MarkdownEditPlan` 一致：一律 **UTF-16 单元**（`NSTextView.selectedRange()` 那套），
/// 不是 `String.Index` —— 含 emoji / 中文时两者会差出位置（`Core/CodeLines` 头顶注释讲过同一个坑）。
public struct CodePairingPlan: Equatable, Sendable {
    /// 要替换的范围（UTF-16）。
    public let range: NSRange
    /// 替换成什么。
    public let replacement: String
    /// 替换**完成后**的光标位置（UTF-16）。
    public let caret: Int
    /// 替换完成后要**选中**的字符数（默认 0）。
    ///
    /// 只有一种情况非 0：**选中文本再打括号** —— 那一下的意思是把选区**包住**，用户的下一个动作
    /// 通常是接着敲内容或再包一层，所以保持选中比把光标丢到一侧更有用。
    public let selectionLength: Int

    public init(range: NSRange, replacement: String, caret: Int, selectionLength: Int = 0) {
        self.range = range
        self.replacement = replacement
        self.caret = caret
        self.selectionLength = selectionLength
    }
}

/// 括号匹配的结果（`FR-EDIT-50`）：光标旁那一半 + 它的配对者（可能找不到）。
public struct CodeBracketMatch: Equatable, Sendable {
    /// 光标紧邻的那个括号（UTF-16 位置）。
    public let bracket: Int
    /// 与之配对的那个括号；`nil` = **没配上**（界面据此给告警色，而不是假装配上了）。
    public let partner: Int?
    /// 向上/向下找的时候是否被**扫描上限**截断（真·配对在更远的地方）。
    /// 截断 ≠ 不匹配：界面要说"太远，没扫到"，不能报"不匹配"。
    public let truncated: Bool

    public init(bracket: Int, partner: Int?, truncated: Bool = false) {
        self.bracket = bracket
        self.partner = partner
        self.truncated = truncated
    }
}

/// 工作区代码编辑器的**编程助手基础能力**（`FR-EDIT-49` / `FR-EDIT-50`）：自动配对、跳引号、包选区、括号匹配。
///
/// ## 为什么是纯逻辑、纯函数
///
/// 这一族的判据天然是「给『文本 + 光标 + 敲了哪个键』要『期望文本 + 期望光标』」—— 可以在 Core 里逐条钉死。
/// 写在 `NSTextView` 回调里就只能靠人工开界面复测，而"配对之后光标停在哪"恰恰是最容易错半个字符的地方
/// （`()` 里光标该在两括号之间，不是后面）。宿主层（`CodeTextView`）只负责把计划搬过去。
///
/// ## 口径（每一条都有判据）
///
/// · **只配对这三对**：`(` `[` `{` —— 尖括号 `<` **不配**（泛型、比较、HTML 里它更常是运算符，配错比不配更烦）；
/// · **引号按语言族分档**：代码族（SQL / JSON / Swift / Shell…）配对 `"` `'` `` ` ``；**散文族（Markdown）不配引号** ——
///   写中文时打 `'` 是引号本身，自动补一半反而添乱；
/// · **引号贴着词不配**：`don't` 里的那个 `'` 两边都是字母 ⇒ 不配对（这是引号最常被判错的一处）；
/// · **跳引号只在"本来就该跳"时跳**：光标右边正好是**同一个**闭合符 ⇒ 光标移过去、**不插入**；
///   右边不是它 ⇒ 正常插入（用户可能真想再开一层）；
/// · **选中再打 = 包住**：`abc` + `(` ⇒ `(abc)`，且 `abc` 保持选中；
/// · **退格删整对**：光标夹在**空的**一对里（`(|)`）⇒ 一次删掉两个；中间有内容 ⇒ 只删一个（那是用户自己的字）；
/// · **匹配高亮**：只认**真配对**；扫到上限就报"太远"（`truncated`），不报"不匹配"——两者界面话不一样。
public enum CodeAutoPairing {

    /// 语言族 —— 只分两档，因为**只有引号这一件事**按族分。
    public enum LanguageFamily: String, Sendable {
        /// 代码：引号也配对。
        case code
        /// 散文（Markdown 等）：只有括号配对，引号不配。
        case prose

        /// 按文件名后缀判族（默认 code；Markdown 一族进 prose）。
        public static func of(fileName: String) -> LanguageFamily {
            let lower = fileName.lowercased()
            for ext in [".md", ".markdown", ".mdown", ".mkd", ".txt"] where lower.hasSuffix(ext) {
                return .prose
            }
            return .code
        }
    }

    /// 会配对的三种括号（左 → 右）。
    public static let brackets: [(open: Character, close: Character)] = [
        ("(", ")"), ("[", "]"), ("{", "}")
    ]

    /// 会配对的引号（**只在 `.code` 族**）。
    public static let quotes: [Character] = ["\"", "'", "`"]

    /// 扫描上限：超过这么多字符还没配到 ⇒ 报"太远"，不报"不匹配"。
    public static let scanLimit = 20_000

    // MARK: - 判定小工具

    static func closing(for open: Character) -> Character? {
        for pair in brackets where pair.open == open { return pair.close }
        return nil
    }

    static func opening(for close: Character) -> Character? {
        for pair in brackets where pair.close == close { return pair.open }
        return nil
    }

    static func isBracketClose(_ c: Character) -> Bool { opening(for: c) != nil }

    /// 词字符 = 字母 / 数字 / 下划线（判"引号贴着词"用）。
    static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    static func char(_ s: String, at index: Int) -> Character? {
        guard index >= 0, index < s.utf16.count else { return nil }
        let ns = s as NSString
        guard let scalar = UnicodeScalar(ns.character(at: index)) else { return nil }
        let ch = Character(scalar)
        // 只处理 BMP 单单元字符：代理对（emoji 等）一律当"不是我们关心的字符"。
        return ns.character(at: index) >= 0xD800 && ns.character(at: index) <= 0xDFFF ? nil : ch
    }

    // MARK: - FR-EDIT-49 打字：配对 / 跳引号 / 包选区

    /// 敲下一个字符时该怎么落笔。返回 `nil` = **按原样输入**（不是失败，是"这条口径不适用"）。
    ///
    /// - Parameters:
    ///   - typed: 用户敲下的字符（通常是 1 个字符；多字符 = 粘贴等，本函数不管）。
    ///   - text: 当前全文。
    ///   - selection: 当前选区（UTF-16）；`length > 0` 表示有选中。
    ///   - family: 语言族（决定引号配不配）。
    public static func plan(
        typed: String,
        in text: String,
        selection: NSRange,
        family: LanguageFamily
    ) -> CodePairingPlan? {
        guard typed.count == 1, let ch = typed.first else { return nil }
        let ns = text as NSString
        let caret = selection.location
        let hasSelection = selection.length > 0

        let isOpen = closing(for: ch) != nil
        let isQuote = quotes.contains(ch)
        guard isOpen || isQuote else {
            // 闭合符：只有"该跳"时才动（否则按原样输入）。
            if isBracketClose(ch), !hasSelection, char(text, at: caret) == ch {
                return CodePairingPlan(
                    range: NSRange(location: caret, length: 0), replacement: "", caret: caret + 1
                )
            }
            return nil
        }
        if isQuote && family == .prose { return nil }

        // 选中再打 ⇒ 包住（选中保持）。
        if hasSelection {
            let selected = ns.substring(with: selection)
            let close: Character = isOpen ? (closing(for: ch) ?? ch) : ch
            return CodePairingPlan(
                range: selection,
                replacement: "\(ch)\(selected)\(close)",
                caret: selection.location + 1,
                selectionLength: selection.length
            )
        }

        // 引号贴着词 ⇒ 不配对（`don't` / `it's`）。
        if isQuote {
            let before = char(text, at: caret - 1)
            let after = char(text, at: caret)
            if (before.map(isWordCharacter) ?? false) || (after.map(isWordCharacter) ?? false) { return nil }
        }

        let close: Character = isOpen ? (closing(for: ch) ?? ch) : ch
        return CodePairingPlan(
            range: NSRange(location: caret, length: 0),
            replacement: "\(ch)\(close)",
            caret: caret + 1
        )
    }

    // MARK: - FR-EDIT-49 退格：删整对

    /// 退格时该怎么落笔。返回 `nil` = 按普通退格（删光标左边一个字符）。
    public static func backspacePlan(in text: String, selection: NSRange) -> CodePairingPlan? {
        guard selection.length == 0, selection.location >= 1 else { return nil }
        let caret = selection.location
        guard let before = char(text, at: caret - 1), let after = char(text, at: caret) else { return nil }
        guard let expected = closing(for: before), expected == after else { return nil }
        return CodePairingPlan(
            range: NSRange(location: caret - 1, length: 2), replacement: "", caret: caret - 1
        )
    }

    // MARK: - FR-EDIT-50 括号匹配

    /// 光标旁的括号 + 它的配对者。
    ///
    /// 取法（与主流编辑器一致）：**先看光标左边那一个字符，再看右边那一个** —— 左边优先，
    /// 因为刚敲完左括号时用户的注意力在它身上。
    public static func match(in text: String, caret: Int) -> CodeBracketMatch? {
        var anchor: Int?
        if let left = char(text, at: caret - 1), closing(for: left) != nil || isBracketClose(left) {
            anchor = caret - 1
        } else if let right = char(text, at: caret), closing(for: right) != nil || isBracketClose(right) {
            anchor = caret
        }
        guard let start = anchor, let ch = char(text, at: start) else { return nil }

        if let close = closing(for: ch) {
            // 向左开括号 ⇒ 向右找它的一半（支持嵌套）。
            var depth = 0
            var i = start
            let end = min(text.utf16.count, start + scanLimit)
            while i < end {
                if let c = char(text, at: i) {
                    if c == ch { depth += 1 }
                    else if c == close {
                        depth -= 1
                        if depth == 0 { return CodeBracketMatch(bracket: start, partner: i) }
                    }
                }
                i += 1
            }
            return CodeBracketMatch(bracket: start, partner: nil, truncated: i < text.utf16.count)
        }

        if let open = opening(for: ch) {
            // 右闭合符 ⇒ 向左找（支持嵌套）。
            var depth = 0
            var i = start
            let end = max(-1, start - scanLimit)
            while i > end {
                if let c = char(text, at: i) {
                    if c == ch { depth += 1 }
                    else if c == open {
                        depth -= 1
                        if depth == 0 { return CodeBracketMatch(bracket: start, partner: i) }
                    }
                }
                i -= 1
            }
            return CodeBracketMatch(bracket: start, partner: nil, truncated: i > -1)
        }

        return nil
    }
}
