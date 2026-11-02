import Foundation

// 历史版本（需求 `FR-NTS-NOTE-VERSION-001`）· **每次保存留一版**。
//
// 契约出处：`DoyahNotes/Docs/核心契约.md` §2.1（`InspirationVersion` 提案）+ 需求书 §3.5 该行三条判据。
// 本文件只放**纯数据与纯函数**（没有连接、没有界面），落库在 `NoteDatabase`（schema v11），
// 编排在 `NoteLibrary.save` / `NoteLibrary.rollback`。
//
// 四条口径（都是本条真正的取舍）：
//   ① **一版 = 一次保存后的完整内容**（标题 / 正文 / 标签 / 富文本权威源），不是 diff ——
//      需求原文「不是 Git」：不做分支、不做提交信息、不要用户懂版本库。存全量最贵的是磁盘，
//      而笔记这一档的体量（几十 KB 一版、默认留 50 版）换的是「回滚永远能取回原文」。
//   ② **内容没变不记版**：自动保存每 1.5 秒就可能落一次库，如果按「每写一次记一版」，
//      停顿窗口里同一份内容会被记成几十版 —— 版本列表当场变成噪声，真正想回去的那一版被埋掉。
//      去重口径是**内容全等**（标题 + 正文 + 标签 + spans），不是时间间隔。
//   ③ **回滚本身也是一次保存** ⇒ 自然生成新版本（判据「回滚本身也生成新版本」由形状保证，
//      不靠回滚路径上多写一句）。
//   ④ **有上限、且上限可配**：默认每篇 50 版；超出按「最旧的先丢」裁剪，
//      裁剪在同一事务里做完（判据「保留策略可配置且有上限说明」）。
public enum NoteVersionReason: String, Codable, Sendable, CaseIterable {
    /// 普通保存（手动 / 自动保存走同一条写路，都记这一档）。
    case save
    /// 回滚产生的版本（`rollback` 落到 `save` 的那一次，标成这一档，便于界面区分）。
    case rollback
    /// 同步冲突合并后落地的版本（`FR-NTS-NOTE-SYNC-002` 的第 ③ 条「合并结果是新版本」）。
    case conflict
}

/// 一条历史版本（**完整内容**，不是 diff）。
public struct NoteVersionEntry: Identifiable, Equatable, Sendable {
    /// 本表 rowid（界面 `Identifiable` 用；跨端交换不认它）。
    public var id: Int64
    /// 归属笔记（`Note.id`）。
    public var noteID: UUID
    /// **这篇笔记内的版本号**（1 起、严格递增；回滚也占一个新号）。
    public var version: Int
    public var title: String
    public var body: String
    public var tags: [String]
    /// 富文本权威源（`spans` 列的 JSON 原样）；`nil` = 这一版还没有 v2 权威源（v1 存量）。
    public var spans: String?
    /// **摘要**（判据①「版本列表含时间与摘要」）：正文首个非空行，截到 60 个字符；正文为空时退回标题。
    public var summary: String
    public var reason: NoteVersionReason
    public var savedAt: Date

    public init(
        id: Int64 = 0,
        noteID: UUID,
        version: Int,
        title: String,
        body: String,
        tags: [String] = [],
        spans: String? = nil,
        summary: String? = nil,
        reason: NoteVersionReason = .save,
        savedAt: Date = Date()
    ) {
        self.id = id
        self.noteID = noteID
        self.version = version
        self.title = title
        self.body = body
        self.tags = tags
        self.spans = spans
        self.summary = summary ?? NoteVersionSummary.of(title: title, body: body)
        self.reason = reason
        self.savedAt = savedAt
    }
}

/// 版本保留策略（判据③「可配置且有上限说明」）。
///
/// 默认档写在这里**一处**：界面说明、门禁读数、测试都引用它 —— 不各写一个 50。
/// 「上限说明」的落点 = 这个类型的注释 + 版本历史面板底部那句话（`NotePanel` 侧引用 `defaultLimit`）。
public struct NoteVersionRetention: Equatable, Sendable {
    /// 每篇笔记最多留多少版（**默认 50**）。`<= 0` 表示不裁剪（只给测试 / 迁移用，界面不开这一档）。
    public var maxCount: Int

    public static let defaultLimit = 50
    public static let `default` = NoteVersionRetention(maxCount: defaultLimit)
    /// 不裁剪（迁移 / 判据构造大历史用）。
    public static let unlimited = NoteVersionRetention(maxCount: 0)

    public init(maxCount: Int = NoteVersionRetention.defaultLimit) {
        self.maxCount = maxCount
    }
}

/// 摘要生成（**一处**）：界面列表、判据读数、证据文件都认它，避免三处各截一个长度。
public enum NoteVersionSummary {

    /// 摘要最大字符数。
    public static let limit = 60

    public static func of(title: String, body: String) -> String {
        let firstLine = body
            .split(whereSeparator: { $0 == "\n" || $0 == "\r\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let source = firstLine ?? title.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty { return "" }
        return source.count <= limit ? source : String(source.prefix(limit)) + "…"
    }
}
