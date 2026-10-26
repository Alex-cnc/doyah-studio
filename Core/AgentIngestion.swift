import Foundation

/// **摄取工具**（`FR-AGT-TOOL-INGEST-001/002/003` / 本端计划 P4-摄取）：
/// 检索带**可点来源**；PDF/Word/Excel/图片解析；**视觉不可用要明说**。
///
/// 这一版**不假装有解析器**：能力表如实登记每类文件当前能不能读，
/// 读不了就给 `unavailable(reason)`，而不是返回空文本冒充「读到了但没内容」。
public enum AgentSourceKind: String, Codable, Sendable, CaseIterable {
    case text
    case markdown
    case pdf
    case word
    case excel
    case image
}

/// 可点来源：定位到行 / 页 / 表页，界面据此跳到原文。
public struct AgentSourceRef: Equatable, Sendable, Codable {
    public var uri: String
    public var line: Int?
    public var page: Int?
    public var sheet: String?

    public init(uri: String, line: Int? = nil, page: Int? = nil, sheet: String? = nil) {
        self.uri = uri
        self.line = line
        self.page = page
        self.sheet = sheet
    }

    /// 可点串：`file:///a.md:12` / `file:///a.pdf#page=3` / `file:///a.xlsx#sheet=Sheet1`。
    public var link: String {
        if let line { return "\(uri):\(line)" }
        if let page { return "\(uri)#page=\(page)" }
        if let sheet { return "\(uri)#sheet=\(sheet)" }
        return uri
    }
}

public struct AgentIngestedChunk: Equatable, Sendable {
    public var text: String
    public var source: AgentSourceRef

    public init(text: String, source: AgentSourceRef) {
        self.text = text
        self.source = source
    }
}

public enum AgentIngestUnavailableReason: Equatable, Sendable {
    /// 本机没有该格式的解析器（不许假装读到了）。
    case parserUnavailable(format: String)
    /// 需要视觉模型但当前不可用 —— **要明说**。
    case visionUnavailable
    /// 文件不存在或不可读。
    case unreadable(path: String)
    /// 超出体积上限。
    case tooLarge(bytes: Int, limit: Int)
}

public enum AgentIngestOutcome: Equatable, Sendable {
    case chunks([AgentIngestedChunk])
    case unavailable(AgentIngestUnavailableReason)
}

public struct AgentIngestLimits: Equatable, Sendable {
    public var maxBytes: Int
    public var maxChunks: Int

    public init(maxBytes: Int = 20 * 1024 * 1024, maxChunks: Int = 2_000) {
        self.maxBytes = maxBytes
        self.maxChunks = maxChunks
    }
}

public enum AgentIngestion {

    /// 能力表（本轮真实状态：纯文本 / Markdown 可读；PDF·Word·Excel 待解析器；图片待视觉）。
    public static func capability(for kind: AgentSourceKind) -> AgentIngestOutcome {
        switch kind {
        case .text, .markdown:
            return .chunks([])   // 有解析器，返回空块表示「能读，但这次没内容」
        case .pdf:  return .unavailable(.parserUnavailable(format: "pdf"))
        case .word: return .unavailable(.parserUnavailable(format: "docx"))
        case .excel: return .unavailable(.parserUnavailable(format: "xlsx"))
        case .image: return .unavailable(.visionUnavailable)
        }
    }

    public static func kind(ofFileNamed name: String) -> AgentSourceKind? {
        switch (name as NSString).pathExtension.lowercased() {
        case "txt", "log", "json", "yaml", "yml", "toml", "swift", "kt", "py", "sh", "sql": return .text
        case "md", "markdown": return .markdown
        case "pdf": return .pdf
        case "doc", "docx": return .word
        case "xls", "xlsx", "csv": return .excel
        case "png", "jpg", "jpeg", "heic", "gif", "webp": return .image
        default: return nil
        }
    }

    /// 按行切块（检索要能定位到行）。
    public static func chunk(text: String, uri: String, maxChunkCharacters: Int = 800) -> [AgentIngestedChunk] {
        guard !text.isEmpty else { return [] }
        var chunks: [AgentIngestedChunk] = []
        var buffer: [String] = []
        var bufferLength = 0
        var startLine = 1
        for (offset, line) in text.components(separatedBy: "\n").enumerated() {
            let lineNumber = offset + 1
            if buffer.isEmpty { startLine = lineNumber }
            buffer.append(line)
            bufferLength += line.count + 1
            if bufferLength >= maxChunkCharacters {
                chunks.append(AgentIngestedChunk(text: buffer.joined(separator: "\n"),
                                                 source: AgentSourceRef(uri: uri, line: startLine)))
                buffer = []
                bufferLength = 0
            }
        }
        if !buffer.isEmpty {
            chunks.append(AgentIngestedChunk(text: buffer.joined(separator: "\n"),
                                             source: AgentSourceRef(uri: uri, line: startLine)))
        }
        return chunks
    }

    /// 检索：命中块必须带可点来源；命不中就返回空数组（不编来源）。
    public static func search(_ query: String, in chunks: [AgentIngestedChunk]) -> [AgentIngestedChunk] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }
        return chunks.filter { $0.text.lowercased().contains(needle) }
    }
}
