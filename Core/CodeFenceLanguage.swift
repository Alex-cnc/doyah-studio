import Foundation

/// 围栏语言（```sql）→ 词法器认的语言（`TextLanguage`）。
///
/// 为什么单独一条：围栏里写的是**别名**（`sql` / `py` / `js` / `sh` / `postgres`），
/// 而词法器只认登记表里的扩展名。这层翻译放在 Core，就能被判据钉住 ——
/// 少了它，界面上「像没上色」与「语言没认出来」长得一模一样（2026-10-22 实测踩过一次）。
public enum CodeFenceLanguage {

    /// 别名 → 扩展名（扩展名即登记表里的键）。
    static let aliases: [String: String] = [
        // 别名一律翻成**登记表里真有的扩展名**（`javascript` / `shell` 不是扩展名 ——
        // 翻成它们会让 `detect` 静默回落到 plainText，界面表现就是「没上色」）。
        "python": "py",
        "javascript": "js",
        "typescript": "ts",
        "shell": "sh",
        "bash": "sh",
        "zsh": "sh",
        "jsx": "js",
        "tsx": "ts",
        "yml": "yaml",
        "markdown": "md",
        "postgres": "sql",
        "postgresql": "sql",
        "psql": "sql",
        "text": "",
        "plain": "",
        "plaintext": ""
    ]

    /// 认不出 ⇒ `.plainText`（正文逐字不变、不着色；**不猜**）。
    public static func resolve(_ fence: String?) -> TextLanguage {
        guard let fence else { return .plainText }
        let name = fence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return .plainText }
        let extensionName = aliases[name] ?? name
        guard !extensionName.isEmpty else { return .plainText }
        return TextLanguage.detect(path: "snippet.\(extensionName)")
    }
}
