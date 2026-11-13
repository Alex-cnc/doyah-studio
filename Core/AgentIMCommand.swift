import Foundation

/// **IM 的最小命令层**（`T-3.25-15`，需求 ⑭：至少 `/stop` 与 `/status`，与自然语言同一条入口）。
///
/// 四条纪律：
/// ① **只认整词**：`/stop` 是命令，`/stopwatch` 不是（不许把半个词当命令，那样打错一个字就会误停）；
/// ② **命令不改权限**：`/stop` 只掐当前这一跑，**不清待批单、不放开审批** —— 这条由宿主接线保证，
///    解析层也刻意不给它任何「清单」能力（想加得先改这个类型）；
/// ③ **不认识的斜杠句如实说「没有这个命令」并列出可用命令** —— 静默当普通消息最坑：
///    人会以为命令生效了，实际上那一句被当成派活；
/// ④ 解析是纯函数（不读钟、不碰状态）。
public enum AgentIMCommand: Equatable, Sendable {

    case stop
    case status
    /// 认得出是命令（以斜杠开头）但不在清单里。
    case unknown(String)

    public static let knownNames = ["stop", "status"]

    /// 一句话是不是命令。`nil` = 不是命令（照常当派活）。
    public static func parse(_ text: String) -> AgentIMCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "/" || first == "／" else { return nil }
        let body = trimmed.dropFirst()
        // 整词：取到第一个空白之前的那一段。
        let name = body.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .first.map(String.init) ?? ""
        let lowered = name.lowercased()
        guard !lowered.isEmpty else { return .unknown("") }
        switch lowered {
        case "stop": return .stop
        case "status": return .status
        default: return .unknown(lowered)
        }
    }

    /// `/stop@某机器人` 这类带尾缀的写法：只在 `@` 前那一段是已登记命令时才算（群里常见）。
    public static func parse(_ text: String, botSuffix: String?) -> AgentIMCommand? {
        guard let suffix = botSuffix, !suffix.isEmpty,
              let base = parse(text) else { return parse(text) }
        if case .unknown(let name) = base, name.hasSuffix("@\(suffix.lowercased())") {
            let bare = String(name.dropLast(suffix.count + 1))
            if knownNames.contains(bare) { return parse("/" + bare) }
        }
        return base
    }
}
