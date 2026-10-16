import Foundation

/// 工具调用的**一行摘要**（过程行里给人看的那一截 —— Hermes CLI 的 `$ echo "..." 0.3s` 那个位置）。
///
/// 为什么单开一个纯函数：过程行要能判。取哪一格**不猜**（第十一条：读数器的口子只开在**能指认的那一族**上）——
/// 只认一张字段名白名单；白名单里一个都没有，就把整个 JSON 压平截断，**不假装知道哪个字段重要**。
public enum AgentToolSummary {

    /// 白名单：按「一次调用里哪个字段最像目标」排序（具体在前、泛化在后）。
    ///
    /// 命令 / SQL / 路径 / URL 是**目标本身**；`name` / `table` / `model` 是次一级的限定词。
    /// 序 = **做什么**在前、**在哪**在后：`search` 这种一次调用同时带 `pattern` 与 `path` 时，
    /// 过程行该显示**在搜什么**（`pattern`），而不是"在哪个目录搜" —— 后者是限定词。
    static let keys = ["command", "sql", "query", "pattern", "path", "file", "url", "table", "name", "model"]

    /// 从参数 JSON 取一行摘要。取不到任何白名单字段 ⇒ 压平 + 截断（绝不返回多行）。
    public static func line(fromArgumentsJSON json: String, limit: Int = 60) -> String {
        let text = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "{}" else { return "" }
        for key in keys {
            if let value = stringValue(of: key, in: text), !value.isEmpty {
                return flatten(value, limit: limit)
            }
        }
        return flatten(text, limit: limit)
    }

    /// 取某个键的字符串值（只认**顶层**那个键的第一次出现；不做完整 JSON 解析 —— 摘要不是判据面）。
    private static func stringValue(of key: String, in json: String) -> String? {
        let pattern = "\"" + key + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(json.startIndex..., in: json)
        guard let match = regex.firstMatch(in: json, range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: json) else { return nil }
        return String(json[valueRange]).replacingOccurrences(of: "\\n", with: " ")
    }

    /// 压平（换行 → 空格、连续空白 → 一个空格）并截断。
    private static func flatten(_ text: String, limit: Int) -> String {
        let flat = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return flat.count <= limit ? flat : String(flat.prefix(limit)) + "…"
    }
}
