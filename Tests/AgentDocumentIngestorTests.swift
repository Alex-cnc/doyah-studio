import XCTest
@testable import DoyahCore

/// `FR-AGT-TOOL-INGEST-002` 判据：Excel / Word 真读、PDF 注入式抽取、其余如实报不可用。
final class AgentDocumentIngestorTests: XCTestCase {

    private func fixture(_ relative: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/
            .appendingPathComponent("Fixtures")
        return try Data(contentsOf: root.appendingPathComponent(relative))
    }

    // MARK: Excel（真读）

    func testReadsXLSXWithSheetSource() throws {
        let data = try fixture("xlsx/orders.xlsx")
        let outcome = AgentDocumentIngestor.ingest(data: data, fileName: "orders.xlsx", uri: "file:///orders.xlsx")
        guard case .chunks(let chunks) = outcome else {
            return XCTFail("xlsx 必须读得出来，实际 \(outcome)")
        }
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.allSatisfy { $0.source.sheet != nil }, "每个块都要带表名来源")
        XCTAssertTrue(chunks.contains { $0.text.contains("\t") }, "单元格按制表分隔")
    }

    func testOldXLSIsReportedUnavailable() {
        let outcome = AgentDocumentIngestor.ingest(data: Data([0xD0, 0xCF]), fileName: "old.xls", uri: "file:///old.xls")
        XCTAssertEqual(outcome, .unavailable(.parserUnavailable(format: "xls")))
    }

    // MARK: Word（真读）

    func testReadsDOCXParagraphs() throws {
        let data = try fixture("docx/minimal.docx")
        let outcome = AgentDocumentIngestor.ingest(data: data, fileName: "minimal.docx", uri: "file:///minimal.docx")
        guard case .chunks(let chunks) = outcome else {
            return XCTFail("docx 必须读得出来，实际 \(outcome)")
        }
        let text = chunks.map(\.text).joined(separator: "\n")
        XCTAssertTrue(text.contains("季度报告"))
        XCTAssertTrue(text.contains("收入同比增长 12%"), "同一段里两个 run 要拼一起")
        XCTAssertTrue(text.contains("结论"))
        XCTAssertEqual(chunks.first?.source.uri, "file:///minimal.docx")
    }

    func testPlainTextExtractionHandlesEntitiesAndRuns() {
        let xml = """
        <w:body><w:p><w:r><w:t>A &amp; B</w:t></w:r></w:p><w:p><w:r><w:t>第二段</w:t></w:r></w:p></w:body>
        """
        let text = AgentDocumentIngestor.plainText(fromWordXML: xml)
        XCTAssertEqual(text, "A & B\n第二段")
    }

    // MARK: PDF（注入式）

    func testPDFWithoutExtractorIsUnavailable() {
        AgentDocumentIngestor.pdfTextExtractor = nil
        let outcome = AgentDocumentIngestor.ingest(data: Data("%PDF-1.4".utf8), fileName: "a.pdf", uri: "file:///a.pdf")
        XCTAssertEqual(outcome, .unavailable(.parserUnavailable(format: "pdf")))
    }

    func testPDFWithInjectedExtractorProducesChunks() {
        AgentDocumentIngestor.pdfTextExtractor = { _ in "第一页文本\n第二页文本" }
        defer { AgentDocumentIngestor.pdfTextExtractor = nil }
        let outcome = AgentDocumentIngestor.ingest(data: Data("%PDF-1.4".utf8), fileName: "a.pdf", uri: "file:///a.pdf")
        guard case .chunks(let chunks) = outcome else {
            return XCTFail("注入抽取器后必须读得出来")
        }
        XCTAssertEqual(chunks.map(\.text).joined(separator: "\n"), "第一页文本\n第二页文本")
    }

    // MARK: 图片

    func testImageNeedsVisionAndSaysSo() {
        let outcome = AgentDocumentIngestor.ingest(data: Data([0x89, 0x50]), fileName: "a.png", uri: "file:///a.png")
        XCTAssertEqual(outcome, .unavailable(.visionUnavailable))
    }

    // MARK: 纯文本

    func testPlainTextIsChunkedWithLineSources() throws {
        let text = (1...5).map { "line \($0)" }.joined(separator: "\n")
        let outcome = AgentDocumentIngestor.ingest(data: Data(text.utf8), fileName: "a.md",
                                                   uri: "file:///a.md", maxChunkCharacters: 12)
        guard case .chunks(let chunks) = outcome else { return XCTFail("md 必须读得出来") }
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.first?.source.link, "file:///a.md:1")
    }
}
