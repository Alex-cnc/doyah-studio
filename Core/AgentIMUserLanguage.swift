import Foundation

/// **用户说话的语言**（`FR-AGT-LINK-CHAN-001` 附则）。
///
/// 2026-11-14 主人拍板：IM 的回话**跟用户说的语言走，不随界面语言**。
///
/// 背景：手机点「批准」没有正文，早先只能退回界面语言 —— 本机界面是英文，
/// 于是中文使用者收到的是 `That code does not match what is waiting right now.`。
/// 这里把「用户最近一次说话用的是什么语言」学下来（`user-language.json`），
/// 无正文的动作（按钮点击、逾期补发）就按它回话；从没说过话时才退到界面语言。
public struct AgentIMUserLanguage: Equatable, Codable, Sendable {

    /// 学到的那门语言；`nil` = 还没学到（这时调用方退到界面语言）。
    public var language: AppLanguage?
    /// 学到它的时刻（只用于排查，不参与判定）。
    public var learnedAt: Date

    public init(language: AppLanguage? = nil, learnedAt: Date = .distantPast) {
        self.language = language
        self.learnedAt = learnedAt
    }

    /// 一句话能学出什么语言：**有汉字** → 简体中文；**没有汉字但有拉丁字母** → English；
    /// 其余（纯数字、纯表情、纯标点）**学不出**，返回 `nil`，不许拿它覆盖已经学到的。
    public static func infer(from text: String) -> AppLanguage? {
        var hasLatin = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
                return .simplifiedChinese
            case 0x41...0x5A, 0x61...0x7A:
                hasLatin = true
            default:
                continue
            }
        }
        return hasLatin ? .english : nil
    }

    /// 学一句话。学不出（纯数字/表情）就**原样不动**。
    @discardableResult
    public mutating func learn(from text: String, at date: Date = Date()) -> Bool {
        guard let learned = Self.infer(from: text) else { return false }
        language = learned
        learnedAt = date
        return true
    }

    /// 回话该用哪门语言：学到了就用学到的，没学到才退到调用方给的语言。
    public func resolved(fallback: AppLanguage) -> AppLanguage {
        language ?? fallback
    }

    // MARK: - 落盘（0600，与 IM 其它状态同一目录）

    public static func load(from url: URL) -> AgentIMUserLanguage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgentIMUserLanguage.self, from: data)
    }

    public func save(to url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
