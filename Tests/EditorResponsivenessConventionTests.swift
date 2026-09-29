import Foundation
import XCTest

/// 编辑器响应性的两条判据（2026-09-28 人工点验实测：5,000 行文档「删除时明显卡顿」，NFR-PERF-05）。
///
/// 两条都不是「有没有功能」而是**形态**：一处写得对、下一轮很容易又被改回顺手写法
/// （`DispatchQueue.main.async` 看着就像「延后」）。
final class EditorResponsivenessConventionTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// 高亮必须是**真 debounce**：连续按键合并成一次，且合并窗口按文档大小分档。
    func testHighlightIsDebouncedWithSizeDependentWindow() throws {
        let text = try source("App/Views/CodeEditorView.swift")

        guard let declaration = text.range(of: "func scheduleHighlighting() {") else {
            return XCTFail("找不到 `scheduleHighlighting` —— 判据锚点变了，请更新这条判据而不是删掉它")
        }
        let body = String(text[declaration.lowerBound...].prefix(900))

        XCTAssertTrue(body.contains("asyncAfter"),
                      "高亮必须走 `asyncAfter`（带合并窗口）")
        XCTAssertFalse(body.contains("DispatchQueue.main.async(execute:"),
                       "「扔到下一个 runloop」的旧写法不许回来 —— 连续按键时它等于每个键都全量重着色")
        XCTAssertTrue(body.contains("sqlRealtimeScanLimit"),
                      "合并窗口要按文档大小分档（大文档等更久），阈值复用 Core 的实时扫描上限")
    }

    /// 大文档必须打开非连续布局，否则删一个字符也触发全文重排。
    func testLargeDocumentUsesNonContiguousLayout() throws {
        let text = try source("App/Views/CodeEditorView.swift")
        XCTAssertTrue(text.contains("allowsNonContiguousLayout = true"),
                      "编辑器要打开 `allowsNonContiguousLayout`：关着时 5,000 行的布局是整篇算的")
    }
}
