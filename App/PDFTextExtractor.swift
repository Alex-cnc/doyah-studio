import Foundation
import PDFKit
import DoyahCore

/// PDF 文本抽取（`FR-AGT-TOOL-INGEST-002` 的 macOS 落点）。
///
/// Core 只定义注入点（`AgentDocumentIngestor.pdfTextExtractor`），真正的解析放在这一层：
/// **平台库不进 Core**（Core 要能跨端编译）。启动时调用 `install()` 注册一次。
///
/// 三件如实的事：
/// ① 扫描件（无文本层）抽出来是空串 ⇒ 返回 `nil`，上层报「抽不出文本」，不许返回空文本冒充读到；
/// ② 逐页取文本、按页序拼接（页内换行保留）；
/// ③ 不做 OCR（那是视觉模型的事，`INGEST-003` 已明说「视觉不可用要如实报」）。
enum PDFTextExtractor {

    /// 注册到 Core 的注入点。`PDFKit` 的 `PDFDocument` 非线程安全 ⇒ 每次新建一个文档对象。
    static func install() {
        AgentDocumentIngestor.pdfTextExtractor = { data in
            guard let document = PDFDocument(data: data), document.pageCount > 0 else { return nil }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                let text = document.page(at: index)?.string ?? ""
                if !text.isEmpty { pages.append(text) }
            }
            guard !pages.isEmpty else { return nil }
            return pages.joined(separator: "\n")
        }
    }
}
