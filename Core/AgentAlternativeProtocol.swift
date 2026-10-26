import Foundation

/// 替代方案协议（`FR-AGT-QUAL-VERIFY-003` ②）：**把握低时的替代方案由模型给**，这一处认定它的形状。
///
/// ## 为什么需要单独一层
///
/// 「不确定就说」此前只做到一半：`AgentClaimProvenance` 会判「把握低却没给替代方案」是缺陷，
/// 但**没有任何东西把替代方案填进去** —— 账上那一栏永远是空的，于是每条低把握结论都天然不可交付，
/// 而模型其实完全可以在答复里说一句「另一种做法是…」。缺口不在判据，在**协议**：
/// 提示词里没有要求（`rule`），解析侧也不认那种行（`marker`）。
///
/// ## 两条边界
///
/// · **提示词是中文单语**（与 `AgentSystemPrompt` 同族）：模型侧不本地化，界面切英文时提示词仍是中文；
/// · **解析要认两种文字**：模型用哪种起头不由界面语言决定，所以中文与英文标记都收，
///   另派生半角冒号变体（模型常把全角写成半角）。
///
/// 文本一律取自语言表（`agentAlternative*`）：调用点不写字面量，
/// 「语言只有一个来源」与「Core 中文字面量棘轮」两道门禁都不会被这一层撞到。
public enum AgentAlternativeProtocol {

    /// 提示词里要写进去的那一行（模型读的组装串，取语言表的语言无关槽位）。
    public static var rule: String { LocalizedStrings.defaultText(.agentPromptAlternativeRule) }

    /// 解析时认的引导词（顺序 = 先认长的，避免「替代方案：」被「备选：」之类的短词吞掉）。
    public static var markers: [String] {
        let base = [
            LocalizedStrings.englishText(.agentAlternativeMarkerLong),
            LocalizedStrings.defaultText(.agentAlternativeMarkerLong),
            LocalizedStrings.defaultText(.agentAlternativeMarker),
            LocalizedStrings.englishText(.agentAlternativeMarker),
        ]
        // 半角冒号变体：模型常把 `：` 写成 `:`；反过来也收一份（输入法不可控）。
        var all: [String] = []
        for marker in base where !marker.isEmpty {
            all.append(marker)
            if marker.contains("：") {
                all.append(marker.replacingOccurrences(of: "：", with: ":"))
            } else if marker.contains(":") {
                all.append(marker.replacingOccurrences(of: ":", with: "："))
            }
        }
        // 长的在前：`替代方案：` 与 `备选：` 都命中时按长的那条切（否则会留下一个「替代方案」前缀）。
        return all.sorted { $0.count > $1.count }
    }

    /// 一行是不是替代方案；是则返回**去掉引导词后的内容**（空内容算「不是」—— 只写引导词等于没给）。
    ///
    /// 行首允许列表符号（`- ` / `* ` / `• `），因为模型常把它写成列表项。
    public static func alternative(in line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["- ", "* ", "• "] where text.hasPrefix(marker) {
            text = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        // 大小写不敏感：英文标记 `Alternative:` 与 `alternative:` 都认（模型不保证大小写）。
        let lowered = text.lowercased()
        for marker in markers {
            let needle = marker.lowercased()
            guard lowered.hasPrefix(needle) else { continue }
            let rest = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }
}
