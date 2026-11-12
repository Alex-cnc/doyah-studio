import Foundation

/// **从 IM 回话里认「批准 / 拒绝」**（`FR-AGT-LINK-CHAN-003`，2026-11-11 主人原话：
/// 「我只能在 QQ 指挥，不在电脑前」）。
///
/// 只认**带码**的那一句：`批准 a1b2` / `拒绝 a1b2`（英文 `approve a1b2` / `reject a1b2`）。
///
/// 三条纪律：
/// ① **没有码就不算指令** —— 「批准」两个字单独发过来可能只是聊天，不许因此放行任何东西；
/// ② 码必须是十六进制 4–8 位（从审批指纹里截出来的那一小段），别的形状一律当普通消息；
/// ③ 解析是纯函数（不读钟、不碰状态），放行与否由宿主拿票据再判（一次性 + 过期）。
public enum AgentIMApprovalCommand: Equatable, Sendable {

    /// 一条可执行的决定。
    public struct Decision: Equatable, Sendable {
        public let approve: Bool
        public let code: String

        public init(approve: Bool, code: String) {
            self.approve = approve
            self.code = code
        }
    }

    /// 认出来的批准词（中文 / 英文都收，别逼人记一种）。
    static let approveWords: Set<String> = ["批准", "同意", "放行", "approve", "approve.", "ok", "yes"]
    /// 认出来的拒绝词。
    static let rejectWords: Set<String> = ["拒绝", "驳回", "不准", "reject", "deny", "no"]

    /// 解析一句话。不是指令 ⇒ `nil`（**绝不把普通聊天当成放行**）。
    public static func parse(_ text: String) -> Decision? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 词 + 空白 + 码；也收「批准a1b2」（有人不打空格）。
        let parts = trimmed
            .replacingOccurrences(of: "：", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map(String.init)
        guard parts.count == 2 else { return nil }
        let word = parts[0].lowercased()
        let code = parts[1].lowercased()
        guard isHexCode(code) else { return nil }
        if approveWords.contains(word) { return Decision(approve: true, code: code) }
        if rejectWords.contains(word) { return Decision(approve: false, code: code) }
        return nil
    }

    /// 十六进制 4–8 位（指纹截段就这个形状）。
    static func isHexCode(_ code: String) -> Bool {
        guard (4...8).contains(code.count) else { return false }
        return code.allSatisfy { $0.isHexDigit }
    }
}
