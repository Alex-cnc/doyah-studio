import Foundation

/// 文件的**换行形态**（`FR-STD-WS-EDIT-023` ③）。
///
/// 三档而不是两档：`\r\n` 与 `\n` 是两种"正常"，而**混排**（一个文件里两种都有）
/// 是第三种事实 —— 把它硬判成其中一种，保存时就会**静默改写**另一种行，
/// 而需求写得很清楚：「编码与换行符的变更必须显式」。所以混排单独成一档，
/// 保存时**原样写回**，除非用户自己把它切到 LF / CRLF。
///
/// 旧式 Mac 的孤立 `\r`（以及 `U+2028` 这类少数终止符）不进三档：遇到它们归到 `.mixed`
/// —— 认识不出来就别声称认识，保存时原样写回是最安全的一档。
public enum LineEnding: String, Sendable, Equatable, CaseIterable {

    /// `\n`（Unix / macOS / 现代编辑器缺省）。
    case lf
    /// `\r\n`（Windows 记事本 / 从 Windows 拷来的源码）。
    case crlf
    /// 一个文件里两种都有（或含孤立 `\r` 这类认不出的终止符）—— **原样保留**。
    case mixed

    /// 菜单里能选的两档（`mixed` 是**判出来的事实**，不是可选口径）。
    public static let selectable: [LineEnding] = [.lf, .crlf]

    /// 状态栏 / 日志里的短名。
    public var shortName: String {
        switch self {
        case .lf: return "LF"
        case .crlf: return "CRLF"
        case .mixed: return "Mixed"
        }
    }

    /// 按**文本**认换行形态（不看字节：解码之后的文本已经能看出形态，不必再读一遍盘）。
    ///
    /// 判定顺序：三种计数（`\r\n` / 只属于 LF 的 `\n` / 只看得到 `\r` 的孤立回车）——
    /// 只有一种计数大于 0 时才是"纯"的形态，两种以上都出现 ⇒ 混排。
    /// 一行都没有换行（单行文件 / 空文件）按 `.lf`：那时候"换行形态"还没有事实可依，
    /// 用编辑器缺省那一档，用户要 CRLF 可以显式切。
    public static func detecting(in text: String) -> LineEnding {
        var crlf = 0
        var loneLF = 0
        var loneCR = 0
        var previousWasCR = false
        // **按 Unicode 标量扫，不按 Character**：Swift 里 `"\r\n"` 是**一个** Character ——
        // 用 `for character in text` 去比对 `"\r"` / `"\n"` 一条都命中不了，于是任何 CRLF 文件
        // 都会被判成 `.lf`（本批的实测现场：三条判据同时红）。同族坑见 `DelimitedTextReader`。
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\r":
                loneCR += 1
                previousWasCR = true
            case "\n":
                if previousWasCR {
                    // 这一对的 `\r` 刚才记过一笔孤立回车，现在归到 CRLF 那一档。
                    loneCR -= 1
                    crlf += 1
                } else {
                    loneLF += 1
                }
                previousWasCR = false
            default:
                previousWasCR = false
            }
        }
        if crlf > 0 && loneLF == 0 && loneCR == 0 { return .crlf }
        if crlf > 0 || (loneLF > 0 && loneCR > 0) { return .mixed }
        if loneCR > 0 { return .mixed }
        return .lf
    }

    /// 把文本里的各种换行统一成 LF（**编辑器内部一律 LF**）。
    ///
    /// 为什么内部只留一种：行号 / 折叠 / 缩进 / 搜索全都按行切，`\r\n` 会让"切出来的每行
    /// 末尾多一个 `\r`"，于是每个按行比较的判断都要各自记得剥一次 —— 迟早漏一处。
    /// 归一发生在**打开那一刻**，写回发生在**保存那一刻**，中间只有一个口径。
    public static func normalizing(_ text: String) -> String {
        // 判定"有没有 `\r`"必须走标量：Swift 里 `"\r\n"` 是**一个** Character，
        // `text.contains("\r")` 对 CRLF 文本返回 **false**（本批实测：归一整段被跳过，
        // 于是"内部一律 LF"这条口径根本没生效）。同族坑见 `DelimitedTextReader`。
        guard text.unicodeScalars.contains("\r") else { return text }
        var out = String.UnicodeScalarView()
        var pendingCR = false
        for scalar in text.unicodeScalars {
            if scalar == "\r" {
                // 连续的 `\r\r`：前一个是孤立回车，先落一个换行。
                if pendingCR { out.append("\n") }
                pendingCR = true
            } else if scalar == "\n" {
                out.append("\n")
                pendingCR = false
            } else {
                if pendingCR {
                    out.append("\n")
                    pendingCR = false
                }
                out.append(scalar)
            }
        }
        if pendingCR { out.append("\n") }
        return String(out)
    }

    /// LF 文本 → 按这一档落盘。（`.mixed` 原样返回：不替用户统一。）
    public func applied(to text: String) -> String {
        switch self {
        case .lf:
            return LineEnding.normalizing(text)
        case .crlf:
            var out = String.UnicodeScalarView()
            for scalar in LineEnding.normalizing(text).unicodeScalars {
                if scalar == "\n" {
                    out.append("\r")
                    out.append("\n")
                } else {
                    out.append(scalar)
                }
            }
            return String(out)
        case .mixed:
            return text
        }
    }
}

/// 一份文本文件的**打开形态**：编码 + 换行 + 有没有 BOM（`FR-STD-WS-EDIT-023`）。
///
/// 为什么把三样合成一个值：它们都由**盘上字节**决定，又都必须**原样带回**保存那一刻。
/// 拆成三个字段散在页签上，迟早就出现"编码记住了、换行忘了"这种半套口径 ——
/// 而那一条的症状是"保存一次，整个文件在 git 里变成全文改动"。
///
/// 编码复用 `ResultExportEncoding`：导出侧已经有一套"UTF-8 / GB18030"的判定与文案，
/// 打开侧再写一套就是在同一件事上有两个真相。
public struct TextFileFormat: Equatable, Sendable {

    /// 编码。
    public var encoding: ResultExportEncoding
    /// 换行形态。
    public var lineEnding: LineEnding
    /// 盘上那份文件开头有没有 UTF-8 BOM。**保存时按原样决定写不写** ——
    /// 给没有 BOM 的文件凭空加一个，会让一些工具（含部分编译器配置）认不出它；
    /// 反而把有 BOM 的去掉，中文 Windows 上的 Excel 又会读成乱码。
    public var hadByteOrderMark: Bool

    public init(encoding: ResultExportEncoding = .utf8,
                lineEnding: LineEnding = .lf,
                hadByteOrderMark: Bool = false) {
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.hadByteOrderMark = hadByteOrderMark
    }

    /// 新建 / 认不出时的缺省：UTF-8 + LF + 不带 BOM（与本产品其它写文本的地方同口径）。
    public static let utf8LF = TextFileFormat()

    /// 状态栏那一格：`UTF-8 · CRLF`。
    public var displayName: String { encoding.shortName + " · " + lineEnding.shortName }

    /// 解码结果：**LF 归一之后的文本** + 打开形态。
    public struct Opened: Equatable, Sendable {
        public var text: String
        public var format: TextFileFormat
    }

    /// 按字节判定打开形态并把文本归一到 LF。
    ///
    /// 编码的判定本身交给 `TextFileDecoder`（BOM → 严格 UTF-8 → GB18030），
    /// 这里只补上它不管的那一半：换行。两处共用同一个解码器，
    /// 是因为"同一个文件被两边读成两种编码"这种缺陷最难查（导入侧对、编辑器侧错）。
    public static func decode(_ data: Data) throws -> Opened {
        let decoded = try TextFileDecoder.decode(data)
        let lineEnding = LineEnding.detecting(in: decoded.text)
        let text = lineEnding == .mixed ? decoded.text : LineEnding.normalizing(decoded.text)
        return Opened(
            text: text,
            format: TextFileFormat(encoding: decoded.encoding,
                                   lineEnding: lineEnding,
                                   hadByteOrderMark: decoded.hadByteOrderMark)
        )
    }

    /// 只要形态（不要文本）—— 会话恢复那条路用得上。
    public static func detecting(_ data: Data) throws -> TextFileFormat {
        try decode(data).format
    }

    /// 便捷入口：直接读文件。
    public static func detect(contentsOf url: URL) throws -> TextFileFormat {
        try detecting(try Data(contentsOf: url))
    }

    /// 按这一档把文本编成字节。**编不出来回 `nil`**（不静默写出一个残缺文件）。
    ///
    /// GB18030 编不出来的情况是真实的：源文件里有一个 emoji 或生僻字，用户又把编码切到
    /// GB18030 —— 这时 Foundation 会拒绝（`allowLossyConversion` 缺省 false），
    /// 调用点必须**如实报错**，而不是让文件里出现一串问号。
    public func bytes(for text: String) -> Data? {
        let body = lineEnding.applied(to: text)
        switch encoding {
        case .utf8:
            var data = Data(body.utf8)
            if hadByteOrderMark {
                data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0)
            }
            return data
        case .gb18030:
            guard let foundation = encoding.foundationEncoding else { return nil }
            // BOM 只对 UTF-8 有意义；GB18030 下 `U+FEFF` 是真实字符，写进去会变成首格乱码。
            //
            // **编完要解回来对一遍**（实测：`allowLossyConversion: false` 并不能拦住不可表示的
            // 字符 —— `"😀".data(using: gb18030, allowLossyConversion: false)` 照样给出字节）。
            // 唯一的可靠判据是"解回来是否等于原文"：不等就是有字符被换掉了，如实回 `nil`。
            guard let data = body.data(using: foundation, allowLossyConversion: false),
                  String(data: data, encoding: foundation) == body
            else { return nil }
            return data
        }
    }

    // MARK: 显式切换（状态栏那两档口径）

    /// 换成另一个编码（**只改口径、不动文本**；写盘时生效）。
    public func choosing(encoding: ResultExportEncoding) -> TextFileFormat {
        var copy = self
        copy.encoding = encoding
        // 切到 GB18030 时 BOM 无意义；切回 UTF-8 时按文件原来的样子恢复（有就写、没有就不写）。
        if encoding == .gb18030 { copy.hadByteOrderMark = false }
        return copy
    }

    /// 换成另一档换行（**同时把文本统一成那一档**：用户在菜单上点 CRLF 的意思
    /// 就是"这个文件以后用 CRLF"，只记一格不落地会让状态栏与实际内容相抵）。
    public func choosing(lineEnding: LineEnding, in text: String) -> (format: TextFileFormat, text: String) {
        var copy = self
        copy.lineEnding = lineEnding
        return (copy, lineEnding.applied(to: text))
    }
}
