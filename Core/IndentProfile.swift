import Foundation

/// 一个文档的**缩进口径**（`FR-STD-WS-EDIT-022`）：软 / 硬 tab 与宽度**按内容判定**，不靠扩展名猜。
///
/// ## 为什么判在内容上（而不是按扩展名）
///
/// 同一堆 `.swift`：有人 2 空格、有人 4 空格；`.py` 里 PEP 8 是 4、老项目是 8；而 `.txt` / `.md` /
/// `.conf` 里硬 tab 比空格还常见。按扩展名给一张表，等于把「用户手上这份文件实际怎么写」换成
/// 「我以为这类文件一般怎么写」—— 一次猜错，按一次 Tab 就插错一种缩进，而**每一次**按 Tab 都在
/// 加深这份不一致（混排文件就是这么长出来的）。所以口径只有一条：**数这份文件自己的缩进证据**。
///
/// ## 口径（每条都有判据）
///
/// · **证据行** = 非空、且前导空白非空的行（只有空格或制表符的空白行不算 —— 它说明不了任何事）；
/// · **软 / 硬** = 证据行的多数派（空格缩进 vs 含制表符缩进）；**并列取空格**（更保守的一侧）；
///   两种都出现时 `conflictingLines` 如实记下少数派有几行，**不假装这份文件很干净**；
/// · **证据不足两行不猜**（空文件 / 全顶格 / 只缩进过一行）⇒ `fallback`（空格 4）并把 `origin`
///   说成 `fallback` —— 状态栏据此说「按缺省」，而不是冒充「按内容判定」；
/// · **宽度**：先看「更深一级」的**增量**（相邻证据行里缩进变大的差值取众数）—— 这是编辑器最常用的
///   那条证据；没有增量（整份文件只在一个深度上）才退回**绝对缩进的最小公分母**；
///   增量并列时取**能整除其余候选**的那个（`2` 与 `4` 并列 ⇒ 4 就是两级 2，取 2；`4` 与 `8` ⇒ 取 4）；
/// · **硬 tab 的宽度不可从内容推出**（tab 本身没有宽度，宽度是显示 / 插入口径）⇒ 取缺省 4；
/// · 用户改过的口径（`chosen`）**不会被重新检测冲掉** —— `adopting` 只覆盖机器判出来的那一档。
public struct IndentProfile: Equatable, Sendable {

    /// 用空格还是用制表符缩进。
    public enum Style: String, Sendable, Equatable, CaseIterable {
        case spaces
        case tabs
    }

    /// 这个口径怎么来的。
    /// - `fallback`：内容里没有足够证据，用的是缺省（空格 4）
    /// - `detected`：从内容里判出来的
    /// - `chosen`：用户自己选的（**不再被重新检测覆盖**）
    public enum Origin: String, Sendable, Equatable {
        case fallback
        case detected
        case chosen
    }

    /// 缺省宽度（与内置格式化器 `CodeBuiltinFormatter.indentUnit` 同一个数）。
    public static let defaultWidth = 4
    /// 宽度取值域：状态栏只给这一档里的值，越界一律夹回（宽度是给人看的，不是给人算的）。
    public static let widthRange = 1...8

    public let style: Style
    public let width: Int
    public let origin: Origin
    /// 参与判定的证据行数（非空且有前导空白的行）。
    public let evidenceLines: Int
    /// 与多数派不一致的缩进行数（混用文件如实报出来）。
    public let conflictingLines: Int

    public init(style: Style,
                width: Int,
                origin: Origin = .detected,
                evidenceLines: Int = 0,
                conflictingLines: Int = 0) {
        self.style = style
        self.width = min(max(width, Self.widthRange.lowerBound), Self.widthRange.upperBound)
        self.origin = origin
        self.evidenceLines = max(0, evidenceLines)
        self.conflictingLines = max(0, conflictingLines)
    }

    /// 没证据时的缺省口径：空格 4（与 `CodeBuiltinFormatter.indentUnit` 同一个值）。
    public static let fallback = IndentProfile(style: .spaces,
                                               width: defaultWidth,
                                               origin: .fallback)

    /// 落到文本里的那一份**缩进单位**：软 tab = `width` 个空格；硬 tab = 一个 `\t`。
    public var unit: String {
        switch style {
        case .spaces: return String(repeating: " ", count: width)
        case .tabs: return "\t"
        }
    }

    /// 用户改口径：改过的记 `chosen`（之后 `adopting` 不会再把它冲掉）。
    /// 参数为 `nil` 的那一半保持原样。
    public func choosing(style: Style? = nil, width: Int? = nil) -> IndentProfile {
        IndentProfile(style: style ?? self.style,
                      width: width ?? self.width,
                      origin: .chosen,
                      evidenceLines: evidenceLines,
                      conflictingLines: conflictingLines)
    }

    /// 重新检测的落法：**用户选过的不覆盖**（否则「我就要 2 空格」会被下一次检测改回去）。
    public func adopting(_ detected: IndentProfile) -> IndentProfile {
        origin == .chosen ? self : detected
    }

    // MARK: - 从内容判定

    /// 按内容判定这份文档的缩进口径（纯函数：同样输入永远同样输出，不读盘、不读扩展名、不读时钟）。
    public static func detect(in text: String) -> IndentProfile {
        /// 有前导空白、且含制表符的行。
        var tabIndented = 0
        /// 有前导空白、且只有空格的行。
        var spaceIndented = 0
        /// 空格侧每行的缩进深度（**含顶格的 0**）：宽度要从「相邻两行深了几格」里看，
        /// 而从顶格进到缩进那一步正是最常见的那一次 —— 只数「有缩进的行」会把它漏掉
        /// （实测让一份 4 空格文件被读成 8）。
        var spaceStream: [Int] = []

        for line in Self.lines(of: text) {
            let leading = Self.leadingWhitespace(line)
            let rest = line.dropFirst(leading.count)
            // 只有空白的行说明不了缩进口径（复制粘贴留下的尾随空白最常见）。
            guard !rest.isEmpty else { continue }
            if leading.contains("\t") {
                tabIndented += 1
            } else {
                spaceStream.append(leading.count)
                if !leading.isEmpty { spaceIndented += 1 }
            }
        }
        let evidence = tabIndented + spaceIndented

        // 证据不足两行：不猜（空文件、全顶格、只缩进过一行都走这一档）。
        guard evidence >= 2 else {
            return IndentProfile(style: .spaces, width: defaultWidth,
                                 origin: .fallback, evidenceLines: evidence)
        }

        // 并列取空格（更保守的一侧）。
        let style: Style = tabIndented > spaceIndented ? .tabs : .spaces
        let conflicting = min(tabIndented, spaceIndented)
        let width: Int
        switch style {
        case .tabs:
            // tab 本身没有宽度 ⇒ 宽度不可从内容推出，取缺省。
            width = defaultWidth
        case .spaces:
            width = Self.spaceWidth(from: spaceStream)
        }
        return IndentProfile(style: style, width: width, origin: .detected,
                             evidenceLines: evidence, conflictingLines: conflicting)
    }

    /// 空格缩进的宽度：先看相邻行的**增量**众数，没有增量才退回绝对缩进的最小公分母。
    static func spaceWidth(from indents: [Int]) -> Int {
        let values = indents.filter { $0 > 0 }
        guard !values.isEmpty else { return defaultWidth }

        // ① 增量直方图：只有「比上一行更深」的那一步才是缩进证据（深到浅不是）。
        var histogram: [Int: Int] = [:]
        var previous = indents.first ?? 0
        for value in indents.dropFirst() {
            if value > previous { histogram[value - previous, default: 0] += 1 }
            previous = value
        }
        if let width = dominantIncrement(histogram) { return width }

        // ② 整份文件只在一个深度上（没有增量）⇒ 绝对缩进的最小公分母。
        //    `1` 说明每行缩进都不一样（缩进对不齐）—— 那不是「一格一级」，是没有口径，别猜。
        let gcd = values.reduce(0) { Self.greatestCommonDivisor($0, $1) }
        if gcd >= 2 && gcd <= Self.widthRange.upperBound { return gcd }
        if gcd > Self.widthRange.upperBound {
            // 12 / 16 / 24 这类：取能整除它的最大常规档（8 → 4 → 3 → 2）。
            for candidate in [8, 4, 3, 2] where gcd % candidate == 0 { return candidate }
        }
        return defaultWidth
    }

    /// 增量众数；并列时取**能整除其余候选**的那个（它就是那个「两级」）。
    /// 只在 `2...8` 里挑：增量 1 多是手工对齐（不是缩进一级），9 以上多半是块级对齐。
    static func dominantIncrement(_ histogram: [Int: Int]) -> Int? {
        let ranked = histogram.filter { $0.key >= 2 && $0.key <= 8 }
        guard let maxCount = ranked.values.max() else { return nil }
        let tied = ranked.filter { $0.value == maxCount }.keys.sorted()
        if tied.count == 1 { return tied[0] }
        for candidate in tied where tied.allSatisfy({ $0 % candidate == 0 }) { return candidate }
        // 互相都解释不了（4 与 6 这种真混排）⇒ 取小的一档（少猜一半）。
        return tied.first
    }

    static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var x = abs(a), y = abs(b)
        while y != 0 { (x, y) = (y, x % y) }
        return max(1, x)
    }

    // MARK: - 行与空白

    /// 按行切（`\r\n` / `\r` / `\n` 三种终止符都认；**不丢末尾空行**，空行在判定里本来就不算证据）。
    static func lines(of text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n")
    }

    /// 前导空白（只认空格与制表符；`\u{3000}` 这类全角空白不是缩进）。
    static func leadingWhitespace(_ text: String) -> String {
        var out = ""
        for character in text {
            guard character == " " || character == "\t" else { break }
            out.append(character)
        }
        return out
    }
}
