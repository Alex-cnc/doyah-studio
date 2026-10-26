import Foundation

/// 会话导出文件名的**唯一出处**（`FR-AGT-UX-SESS-001` ③）。
///
/// 为什么值得单独一件：文件名是用户唯一会读到的「导出结果的形状」。
/// 直接把会话标题塞进 `NSSavePanel` 有三个坑，都会在别人的机器上炸：
/// ① 标题里带 `/` 或 `:`（`看下 A/B 两张表`）⇒ 保存面板把它当路径分隔符，文件落到别处或直接失败；
/// ② 标题是一整段问题（几十个字）⇒ 文件名被系统截断得只剩前半句；
/// ③ 标题里全是表情 / 空白 ⇒ 落成一个看不见的文件名。
/// 所以这里做三件事：清洗非法字符、按字数封顶、空标题退回会话号。
enum AgentChatSessionFileName {

    /// 标题里**不能出现**的字符（macOS 上 `:` 是历史路径分隔符，`/` 是现在的）。
    static let illegalCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")

    /// 建议文件名：`<清洗后的标题>-<会话号前 8 位>.json`。
    ///
    /// 带上会话号后 8 位是为了**同名不撞**：两条会话都叫「新建会话」时，
    /// 用户在下载目录里一眼能分开，也不会第二次导出就把第一份覆盖掉。
    static func suggested(title: String, sessionID: String) -> String {
        let cleaned = sanitize(title)
        let digest = digestPrefix(sessionID)
        let base = cleaned.isEmpty ? "session" : cleaned
        return "\(base)-\(digest).json"
    }

    /// 清洗：非法字符换成 `-`、连续空白压成一个、按 40 个字符封顶（保留可读性）。
    static func sanitize(_ title: String) -> String {
        var pieces: [String] = []
        for scalar in title.unicodeScalars {
            if illegalCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) {
                pieces.append("-")
            } else {
                pieces.append(String(scalar))
            }
        }
        let collapsed = pieces.joined()
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 前后多余的 `-`（原来是 `/` 变的）去掉，中间保留 —— 那是「A/B」的意思
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if trimmed.count <= 40 { return trimmed }
        return String(trimmed.prefix(40)).trimmingCharacters(in: .whitespaces)
    }

    /// 会话号的短摘要：只取字母数字，前 8 位（`chat-<uuid>` 这类前缀不进文件名）。
    static func digestPrefix(_ sessionID: String) -> String {
        let alphaNumeric = sessionID.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let text = String(String.UnicodeScalarView(alphaNumeric))
        return text.isEmpty ? "session" : String(text.suffix(8))
    }
}
