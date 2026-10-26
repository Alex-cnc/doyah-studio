import Foundation

/// **文档摄取**（`FR-AGT-TOOL-INGEST-002` / 本端计划 P4-摄取）：
/// PDF / Word / Excel / 图片 → 带可点来源的文本块。
///
/// 如实口径（不许假装）：
/// - **Excel**：真读（复用 `XLSXReader`，纯 Swift 解 ZIP + OOXML，零依赖）；
/// - **Word**：真读（`word/document.xml` 的 `<w:t>` 文本串，段落换行）；
/// - **PDF**：Core 不引平台库 ⇒ 走**注入式抽取器**（macOS 侧由 PDFKit 实现并注册）；
///   没注册就返回 `unavailable(parserUnavailable("pdf"))`，不返回空文本冒充「读到了」；
/// - **旧版 `.doc` / `.xls`（二进制）**：明确不支持；
/// - **图片**：需要视觉模型 ⇒ `unavailable(.visionUnavailable)`，并在界面上明说。
public enum AgentDocumentIngestor {

    /// PDF 抽取器（macOS 侧 `App/PDFTextExtractor.swift` 注册；测试可注入假实现）。
    /// 返回 `nil` = 这个 PDF 抽不出文本（扫描件等），调用方据此如实报。
    public static var pdfTextExtractor: (@Sendable (Data) -> String?)?

    /// 按文件名分派。
    public static func ingest(data: Data, fileName: String, uri: String,
                              maxChunkCharacters: Int = 800) -> AgentIngestOutcome {
        guard let kind = AgentIngestion.kind(ofFileNamed: fileName) else {
            return .unavailable(.parserUnavailable(format: (fileName as NSString).pathExtension.lowercased()))
        }
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch kind {
        case .text, .markdown:
            let text = String(decoding: data, as: UTF8.self)
            return .chunks(AgentIngestion.chunk(text: text, uri: uri, maxChunkCharacters: maxChunkCharacters))
        case .excel:
            return ingestExcel(data: data, uri: uri, ext: ext, maxChunkCharacters: maxChunkCharacters)
        case .word:
            guard ext == "docx" else { return .unavailable(.parserUnavailable(format: ext)) }
            return ingestWord(data: data, uri: uri, maxChunkCharacters: maxChunkCharacters)
        case .pdf:
            guard let extractor = pdfTextExtractor, let text = extractor(data), !text.isEmpty else {
                return .unavailable(.parserUnavailable(format: "pdf"))
            }
            return .chunks(AgentIngestion.chunk(text: text, uri: uri, maxChunkCharacters: maxChunkCharacters))
        case .image:
            return .unavailable(.visionUnavailable)
        }
    }

    // MARK: Excel

    static func ingestExcel(data: Data, uri: String, ext: String, maxChunkCharacters: Int) -> AgentIngestOutcome {
        guard ext == "xlsx" || ext == "csv" else {
            return .unavailable(.parserUnavailable(format: ext))
        }
        if ext == "csv" {
            let text = String(decoding: data, as: UTF8.self)
            return .chunks(AgentIngestion.chunk(text: text, uri: uri, maxChunkCharacters: maxChunkCharacters))
        }
        do {
            let sheets = try XLSXReader.sheets(data)
            var chunks: [AgentIngestedChunk] = []
            for sheet in sheets {
                let text = sheet.rows
                    .map { row in row.map { $0 ?? "" }.joined(separator: "\t") }
                    .joined(separator: "\n")
                chunks.append(contentsOf: AgentIngestion.chunk(text: text, uri: uri, maxChunkCharacters: maxChunkCharacters)
                    .map { chunk in
                        AgentIngestedChunk(text: chunk.text,
                                           source: AgentSourceRef(uri: uri, sheet: sheet.name))
                    })
            }
            return .chunks(chunks)
        } catch {
            return .unavailable(.unreadable(path: uri))
        }
    }

    // MARK: Word

    static func ingestWord(data: Data, uri: String, maxChunkCharacters: Int) -> AgentIngestOutcome {
        do {
            guard let archive = try? ZipArchive(data: data) else {
                return .unavailable(.unreadable(path: uri))
            }
            guard let xml = try archive.text(named: "word/document.xml") else {
                return .unavailable(.unreadable(path: uri))
            }
            let text = plainText(fromWordXML: xml)
            return .chunks(AgentIngestion.chunk(text: text, uri: uri, maxChunkCharacters: maxChunkCharacters))
        } catch {
            return .unavailable(.unreadable(path: uri))
        }
    }

    /// `<w:t>` 文本串按段落收，`</w:p>` 换行；制表 `<w:tab/>` 当一个空格。
    /// 只做取文，不解释样式 / 批注 / 修订（不假装）。
    public static func plainText(fromWordXML xml: String) -> String {
        var out = ""
        var cursor = xml.startIndex
        while let start = xml.range(of: "<w:t", range: cursor..<xml.endIndex) {
            guard let openEnd = xml.range(of: ">", range: start.upperBound..<xml.endIndex),
                  let close = xml.range(of: "</w:t>", range: openEnd.upperBound..<xml.endIndex) else { break }
            out += decodeXML(xml[openEnd.upperBound..<close.lowerBound])
            cursor = close.upperBound
        }
        // 段落边界：把每个 </w:p> 换成换行（用替换后再压掉空行，避免首尾空段）
        var normalized = ""
        var scan = xml.startIndex
        var lastEmitted = ""
        while let para = xml.range(of: "</w:p>", range: scan..<xml.endIndex) {
            // 这一段的文本
            let segmentStart = scan
            let segment = xml[segmentStart..<para.lowerBound]
            var segText = ""
            var c = segment.startIndex
            while let s = xml.range(of: "<w:t", range: c..<segment.endIndex),
                  let oe = xml.range(of: ">", range: s.upperBound..<segment.endIndex),
                  let cl = xml.range(of: "</w:t>", range: oe.upperBound..<segment.endIndex) {
                segText += decodeXML(xml[oe.upperBound..<cl.lowerBound])
                c = cl.upperBound
            }
            if !segText.isEmpty {
                normalized += (normalized.isEmpty ? "" : "\n") + segText
                lastEmitted = segText
            }
            scan = para.upperBound
        }
        // 兜底：段落切不到但全文有 `<w:t>` 时用 first-pass 的结果
        return normalized.isEmpty ? out : normalized
    }

    /// 只解 5 个 XML 实体（够 OOXML 的常见写法）。
    static func decodeXML(_ slice: Substring) -> String {
        slice.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
