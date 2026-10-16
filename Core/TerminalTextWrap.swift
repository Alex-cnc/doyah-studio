import Foundation

/// 终端折行（`FR-AI-25` 的脚本侧那一半）。
///
/// 由头（人类主人 2026-10-17 实机反馈）：「**cli 对话框要能自动换行**」——
/// 改前 CLI 是 `print(piece, terminator: "")` 直接吐字符：长行交给终端硬折，
/// **折点落在词中间**；中文更糟 —— 终端按**列**算宽度，而 `String.count` 按**字符**算，
/// 「中文字符数统计」永远低估一半 ⇒ 一行中文在 80 列终端上必折。
///
/// 本件是**纯逻辑**（无数值以外的依赖、无用户可见文案），判据在 `Tests/TerminalWrapTests.swift`。
public enum TerminalTextWrap {

    /// 一个字符占的**显示列数**（东亚宽字符 = 2 列，其余 = 1 列）。
    ///
    /// 覆盖常用区间：CJK 统一表意 / 扩展 A / 全角标点 / 假名 / 韩文 / 兼容表意。
    public static func displayWidth(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 0 }
        let v = scalar.value
        let wide: [ClosedRange<UInt32>] = [
            0x1100...0x115F,    // 韩文字母
            0x2E80...0x303E,    // CJK 部首 / 标点
            0x3041...0x33FF,    // 假名 / CJK 兼容
            0x3400...0x4DBF,    // 扩展 A
            0x4E00...0x9FFF,    // 统一表意
            0xA000...0xA4CF,    // 彝文
            0xAC00...0xD7A3,    // 韩文音节
            0xF900...0xFAFF,    // 兼容表意
            0xFE30...0xFE6F,    // CJK 兼容形式
            0xFF00...0xFF60,    // 全角 ASCII
            0xFFE0...0xFFE6,    // 全角符号
            0x20000...0x3FFFD,  // 扩展 B~
        ]
        return wide.contains { $0.contains(v) } ? 2 : 1
    }

    /// 整串的显示列数。
    public static func displayWidth(of text: String) -> Int {
        text.reduce(0) { $0 + displayWidth(of: $1) }
    }
}

/// **流式**折行器：喂一段吐一段（`TerminalTextWrap` 的有状态那一半）。
///
/// 为什么要有状态：终端**不能回退**，所以「先打印再回头插换行」这条路不存在；
/// 必须留一截缓冲（最多一行宽），等**可断点**出现再吐。代价是最后不满一行的那截要
/// 由调用方 `flush()` 收尾 —— 这是流式打印的固有形状，不是漏。
public struct TerminalTextWrapper {

    /// 目标列宽。
    public let columns: Int
    private var pending = ""

    public init(columns: Int) {
        self.columns = max(20, columns)
    }

    /// 喂入一段流式文本 ⇒ 返回**现在就该打印的文本**（含折行；未满一行的尾巴留在内部）。
    public mutating func feed(_ piece: String) -> String {
        pending += piece
        var out = ""
        while let (line, rest) = Self.takeLine(from: pending, columns: columns) {
            out += line + "\n"
            pending = rest
        }
        return out
    }

    /// 收尾：把最后那截（可能不满一行）吐出来。**不再补换行**（外层负责行尾）。
    public mutating func flush() -> String {
        defer { pending = "" }
        return pending
    }

    /// 从缓冲里取「一整行」。取不到（还没满、也没有显式换行）⇒ `nil`。
    ///
    /// 断行优先级：**显式 `\n`** > 列宽内的**最后一个可断点**（空格之后 / 宽字符之后）> 硬断。
    private static func takeLine(from buffer: String, columns: Int) -> (String, String)? {
        if let newline = buffer.firstIndex(of: "\n") {
            return (String(buffer[..<newline]), String(buffer[buffer.index(after: newline)...]))
        }
        guard TerminalTextWrap.displayWidth(of: buffer) > columns else { return nil }

        var width = 0
        var index = buffer.startIndex
        var cut = buffer.startIndex
        while index < buffer.endIndex {
            let character = buffer[index]
            let w = TerminalTextWrap.displayWidth(of: character)
            if width + w > columns { break }
            width += w
            index = buffer.index(after: index)
            // 可断点：空格之后（词边界）· 宽字符之后（中文逐字可断）
            if character == " " || w == 2 { cut = index }
        }
        if cut == buffer.startIndex { cut = index }   // 全无断点（超长单词）⇒ 硬断，绝不丢字
        let head = String(buffer[..<cut]).trimmingCharacters(in: .whitespaces)
        return (head, String(buffer[cut...]))
    }
}

/// 一条会话的 token 账（**可判的纯数字那半**；给人看的措辞由调用方拼）。
///
/// 两侧共用：CLI 的流式打印与 App 的对话框状态条各记各的账，形状同一个（免得两处口径漂移）。
///
/// 由头（人类主人 2026-10-17）：「要加上模型信息，**会话已消耗的 token** 等信息，可以参考 Hermes 的 cli 界面」。
public struct TokenUsageLedger: Equatable, Sendable {

    /// 本次会话**请求次数**（每拿到一条用量就算一次）。
    public private(set) var requests = 0
    public private(set) var promptTokens = 0
    public private(set) var completionTokens = 0
    /// 有几次**端点没回用量**（缺值不猜、不当 0 累加 —— 如实留痕）。
    public private(set) var responsesWithoutUsage = 0

    public init() {}

    public var totalTokens: Int { promptTokens + completionTokens }

    /// 记一次用量。缺哪些就不累加哪些（**不把缺值当 0**），返回这次是否有缺值。
    @discardableResult
    public mutating func add(prompt: Int?, completion: Int?) -> Bool {
        let missing = prompt == nil || completion == nil
        if missing { responsesWithoutUsage += 1 }
        requests += 1
        promptTokens += prompt ?? 0
        completionTokens += completion ?? 0
        return missing
    }
}
