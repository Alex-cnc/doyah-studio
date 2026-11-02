import Foundation

/// **导出与迁移的包格式**（`FR-NTS-NOTE-EXPORT-001` · 概要设计 §15.3）。
///
/// 契约五条不变量，逐条对应到这一层的形状：
///   · **导出是副本** —— 导出只读库（`NoteDatabase.archiveEntries()` 里没有一句写），
///     库里那份的正文 / 时间 / 归属一个字节不动；
///   · **三形态同源** —— Markdown / 纯文本 / 备份包都从**同一份** `[NoteArchiveEntry]` 派生，
///     三种产物里的条数因此恒等；本文件不各写一套取数；
///   · **备份包可完整还原** —— 包里带标题 / 正文投影 / 正文权威源（`spans`）/ 标签 /
///     创建与更新时间 / 附件引用 / 归属 / 三枚整理位；导入走 `NoteDatabase.restoreArchive(_:)`，
///     逐字段写回（不是「当成一次普通保存」—— 那条路会把 `updatedAt` 改成现在、把 `createdAt` 换成首次导入时刻）；
///   · **有损要声明** —— Markdown / 纯文本表达不了行内颜色与字号：逐条由
///     `NoteBodyProjection.exportMarkdown` 报降级并写进产物；备份包带 `spans`，无损；
///   · **版本位在前** —— 包里有 `format` + `formatVersion`；版本高于本端支持范围时
///     **拒绝导入并说明**（`unsupportedFormatVersion`），不做半懂不懂的读取。
///
/// **刻意不带的东西（如实登记，不假装覆盖）**：
///   · **私密条目**不进任何导出产物（`FR-NTS-NOTE-PRIVACY-001`「私密不外发（含导出、含备份包）」）——
///     取数那一步就 `is_private = 0`，三种形态同一条边界；
///   · **附件字节**不随包走，包里只有引用（路径 / 字节数 / 加入时刻）。契约 §15.3 判的是
///     「附件引用逐条相等」；原件本来就留在 `<数据家>/attachments/<noteID>/` 下；
///   · **历史版本 / 时间线 / 回收站**不进包（本条的范围是「笔记本体 + 标签 + 附件引用」）。
public enum NoteArchiveFormat {

    /// 包的格式标识（写进文件第一层；不是产品名，改它等于换格式）。
    public static let identifier = "doyah.notes.backup"

    /// 包格式的版本号。**结构变了才升**，且升版必须同时给迁移规则 ——
    /// 与 `NoteBodyFormat.currentVersion` 同一条纪律。
    public static let currentVersion = 1

    /// 三种产物（契约 §15.3「三形态同源」）。
    public enum Kind: String, CaseIterable, Sendable {
        case markdown
        case plainText
        case package

        /// 保存面板的默认文件名（ASCII，避免在不同语言下各变一次）。
        public func fileName(at moment: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = formatter.string(from: moment)
            switch self {
            case .markdown: return "doyah-notes-\(stamp).md"
            case .plainText: return "doyah-notes-\(stamp).txt"
            case .package: return "doyah-notes-\(stamp).notesbackup"
            }
        }
    }
}

/// 「笔记」菜单那四条导出 / 导入命令**发出的请求**（`FR-NTS-NOTE-EXPORT-001`）。
///
/// 为什么中间隔一层：命令分派器（`performPaletteCommand`）可能在**没有窗口**的宿主里被调用
/// （⌘K 面板、探针），而 `NSSavePanel` / `NSOpenPanel` 是模态的 —— 在那一层直接弹，
/// 轻则挂住，重则在无人值守的机器上等人点。于是命令只写「请求」，由笔记面视图读到后清位并弹面板；
/// 判据看到的是「请求已发出」这一档，与「点了没反应」分得开。
public enum NoteArchiveRequest: Equatable, Sendable {
    case export(NoteArchiveFormat.Kind)
    case importPackage
}
public struct NoteArchiveAttachment: Codable, Equatable, Sendable {
    public var id: UUID
    public var path: String
    public var byteCount: Int64?
    public var addedAt: Date

    public init(id: UUID, path: String, byteCount: Int64?, addedAt: Date) {
        self.id = id
        self.path = path
        self.byteCount = byteCount
        self.addedAt = addedAt
    }
}

/// 一条笔记在包里的**完整一份**。
///
/// `spans` 是正文权威源（可能为空 —— v1 存量笔记还没迁移），`body` 是它的投影；
/// 两者都带，是因为还原时要逐字节回到导出那一刻的那一份（只带 `body` 会丢行内样式）。
public struct NoteArchiveEntry: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var spans: String?
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var notebookUID: String?
    public var isFavorite: Bool
    public var isPinned: Bool
    public var isArchived: Bool
    public var containsRowData: Bool
    public var sourceKind: String
    public var sourceConnectionName: String?
    public var sourceFingerprint: String?
    public var sourceCapturedAt: Date
    public var attachments: [NoteArchiveAttachment]

    public init(
        id: UUID,
        title: String,
        body: String,
        spans: String? = nil,
        tags: [String] = [],
        createdAt: Date,
        updatedAt: Date,
        notebookUID: String? = nil,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        isArchived: Bool = false,
        containsRowData: Bool = false,
        sourceKind: String = NoteSource.Kind.manual.rawValue,
        sourceConnectionName: String? = nil,
        sourceFingerprint: String? = nil,
        sourceCapturedAt: Date,
        attachments: [NoteArchiveAttachment] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.spans = spans
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notebookUID = notebookUID
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.containsRowData = containsRowData
        self.sourceKind = sourceKind
        self.sourceConnectionName = sourceConnectionName
        self.sourceFingerprint = sourceFingerprint
        self.sourceCapturedAt = sourceCapturedAt
        self.attachments = attachments
    }
}

/// 备份包（JSON 落盘的那一份）。
public struct NoteArchivePackage: Codable, Equatable, Sendable {
    public var format: String
    /// **版本位在前**：读的时候先判它，再判别的字段（契约 §15.3 第 5 条）。
    public var formatVersion: Int
    public var exportedAt: Date
    public var notes: [NoteArchiveEntry]

    public init(
        format: String = NoteArchiveFormat.identifier,
        formatVersion: Int = NoteArchiveFormat.currentVersion,
        exportedAt: Date,
        notes: [NoteArchiveEntry]
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.notes = notes
    }
}

/// 导入的读数（**回执，不是「成功」两个字**）。
public struct NoteArchiveImportReport: Equatable, Sendable {
    /// 真的写回库的条数。
    public var restored: Int
    /// 目标库里同 uuid 的那一条是**私密**的，因而**跳过没碰**的条数。
    /// 不静默覆盖：那样会把一条私密笔记的内容换掉却仍让它隐身。
    public var skippedPrivateExisting: Int
    /// 原归属的笔记本在目标库不存在、落回默认笔记本的条数（如实报，不假装一模一样）。
    public var notebookFallbacks: Int

    public init(restored: Int, skippedPrivateExisting: Int = 0, notebookFallbacks: Int = 0) {
        self.restored = restored
        self.skippedPrivateExisting = skippedPrivateExisting
        self.notebookFallbacks = notebookFallbacks
    }
}

/// 导入被拒的机器可读原因（人话由带 `language:` 的渲染入口给）。
public enum NoteArchiveFailure: Error, Equatable, CustomStringConvertible {
    /// 不是本产品的备份包（`format` 不认）。
    case notABackupPackage(String)
    /// 包的版本高于本端支持范围 —— **拒绝导入**，不半懂不懂地读。
    case unsupportedFormatVersion(found: Int, supported: Int)
    /// 包结构读不出来（JSON 坏了 / 缺必填字段）。
    case malformed(String)

    public var description: String {
        switch self {
        case .notABackupPackage(let found): return "not a note backup package: \(found)"
        case .unsupportedFormatVersion(let found, let supported):
            return "backup format version \(found) is newer than supported \(supported)"
        case .malformed(let reason): return "malformed note backup package: \(reason)"
        }
    }
}

/// 包编解码 + 三种产物的派生（**取数不在这里** —— 那一半在 `NoteDatabase.archiveEntries()`）。
public enum NoteArchive {

    /// 落盘用的编码器：键排序（同一份数据两次导出逐字节相同）、日期按秒、不转义斜杠（路径好读）。
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    public static func encode(_ package: NoteArchivePackage) throws -> Data {
        try encoder().encode(package)
    }

    /// 解包：**先判格式、再判版本、最后才解条目**。
    ///
    /// 顺序是契约条文（「版本位在前」）：先按一个只含版本位的壳解出来，
    /// 版本高了就在**还没碰任何条目**的时候停下 —— 否则「半懂不懂地读」正是要挡的那件事。
    public static func decode(_ data: Data) throws -> NoteArchivePackage {
        struct Header: Decodable {
            var format: String
            var formatVersion: Int
        }
        let header: Header
        do {
            header = try decoder().decode(Header.self, from: data)
        } catch {
            throw NoteArchiveFailure.malformed(String(describing: error))
        }
        guard header.format == NoteArchiveFormat.identifier else {
            throw NoteArchiveFailure.notABackupPackage(header.format)
        }
        guard header.formatVersion <= NoteArchiveFormat.currentVersion else {
            throw NoteArchiveFailure.unsupportedFormatVersion(
                found: header.formatVersion,
                supported: NoteArchiveFormat.currentVersion
            )
        }
        do {
            return try decoder().decode(NoteArchivePackage.self, from: data)
        } catch {
            throw NoteArchiveFailure.malformed(String(describing: error))
        }
    }

    /// **Markdown 产物**：一条笔记一段（`# 标题` + 正文 + 标签 + 附件引用）。
    ///
    /// 正文走 `NoteBodyProjection.exportMarkdown`（权威源在时），于是「Markdown 表达不了的东西」
    /// 逐条写进产物（契约「有损要声明」）；`spans` 不在（v1 存量）就原样搬 `body`。
    public static func markdown(_ entries: [NoteArchiveEntry], language: AppLanguage) -> String {
        entries.map { entry in
            var lines: [String] = ["# " + entry.title, ""]
            let projected = projectedBody(entry, language: language)
            if !projected.text.isEmpty {
                lines.append(projected.text)
                lines.append("")
            }
            if !projected.degradations.isEmpty {
                lines.append(contentsOf: projected.degradations.map { "> " + $0 })
                lines.append("")
            }
            if !entry.tags.isEmpty {
                lines.append(LocalizedStrings.text(.noteArchiveTags, language: language)
                    + "：" + entry.tags.joined(separator: "、"))
                lines.append("")
            }
            if !entry.attachments.isEmpty {
                lines.append(LocalizedStrings.text(.noteArchiveAttachments, language: language)
                    + "：")
                for attachment in entry.attachments {
                    let size = attachment.byteCount.map { " (\($0))" } ?? ""
                    lines.append("- " + attachment.path + size)
                }
                lines.append("")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n---\n\n")
    }

    /// **纯文本产物**：同样的条目、同样的顺序，只是不带 Markdown 标记。
    /// 标题、正文、标签、附件引用一个不少（契约 ①「导出包含全部正文与附件引用」）。
    public static func plainText(_ entries: [NoteArchiveEntry], language: AppLanguage) -> String {
        entries.map { entry in
            var lines: [String] = [entry.title, String(repeating: "=", count: max(entry.title.count, 1)), ""]
            let projected = projectedBody(entry, language: language)
            if !projected.text.isEmpty {
                lines.append(projected.text)
                lines.append("")
            }
            if !projected.degradations.isEmpty {
                lines.append(contentsOf: projected.degradations)
                lines.append("")
            }
            if !entry.tags.isEmpty {
                lines.append(LocalizedStrings.text(.noteArchiveTags, language: language)
                    + "：" + entry.tags.joined(separator: "、"))
            }
            if !entry.attachments.isEmpty {
                lines.append(LocalizedStrings.text(.noteArchiveAttachments, language: language)
                    + "：" + entry.attachments.map(\.path).joined(separator: "、"))
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private struct ProjectedBody {
        var text: String
        var degradations: [String]
    }

    private static func projectedBody(_ entry: NoteArchiveEntry, language: AppLanguage) -> ProjectedBody {
        guard let spans = entry.spans,
              let data = spans.data(using: .utf8),
              let body = try? decoder().decode(NoteBody.self, from: data) else {
            return ProjectedBody(text: entry.body, degradations: [])
        }
        let result = NoteBodyProjection.exportMarkdown(body, language: language)
        return ProjectedBody(text: result.markdown, degradations: result.degradations)
    }
}
