import Foundation

/// 结论正文里的**媒体标签**（`MEDIA:/绝对路径`）：写结论时顺手把图/报表带出去。
///
/// 为什么用标签而不是另开一个接口：结论是一条文本，媒体是它的附件 —— 让人在正文里写一行
/// `MEDIA:/path/report.png`，比要求 agent 记住「发媒体要调哪个工具」可靠得多
/// （Hermes 的通道也是这个形状：正文里写标签，出站侧摘掉标签、按扩展名发原生媒体）。
///
/// 三条纪律：
/// ① **只认整行标签**（行首 `MEDIA:`），正文里提到这三个字不算；
/// ② **标签本身从正文里摘掉** —— 否则用户手机上会看到一行 `MEDIA:/…` 的怪字；
/// ③ 路径必须**本机绝对路径**（相对路径在工作区里，出站时早不知道在哪了 ⇒ 如实报错，不猜）。
public enum AgentIMMediaTag {

    public struct Extracted: Equatable, Sendable {
        /// 摘掉标签后的正文（标签行整行去掉；连续空行压成一个）。
        public let text: String
        /// 待发媒体的路径（原样，交给 `AgentIMMediaSource.validated` 判）。
        public let paths: [String]

        public init(text: String, paths: [String]) {
            self.text = text
            self.paths = paths
        }
    }

    public static let prefix = "MEDIA:"

    public static func extract(from text: String) -> Extracted {
        var kept: [String] = []
        var paths: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                let path = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                if !path.isEmpty { paths.append(path) }
                continue
            }
            kept.append(line)
        }
        var body = kept.joined(separator: "\n")
        while body.contains("\n\n\n") {
            body = body.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return Extracted(text: body.trimmingCharacters(in: .whitespacesAndNewlines), paths: paths)
    }
}
