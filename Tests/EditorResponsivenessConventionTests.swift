import Foundation
import XCTest

/// 编辑器响应性的两条判据（2026-09-29 人工点验实测：5,000 行文档「删除时明显卡顿」，NFR-PERF-05）。
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

    /// 非连续布局**只能按文档大小分档打开**：两头都不许。
    ///
    /// 开着（无条件）= 小文档会中它的代价 —— 它按「只排可见范围」省算，某块因此被判成「已排过」⇒
    /// **编辑后那一块不重画**（2026-10-03 人工点验：40 来行的 Markdown 表格一路吃着这档设置，
    /// 把横轴滚到行首被遮住时删一个字，编辑区上半屏整片空白、连行号列都没画，拖一下滚动条才恢复）；
    /// 关掉 = 5,000 行文档「删除时明显卡顿」回来（NFR-PERF-05）。
    func testNonContiguousLayoutIsGatedByDocumentSize() throws {
        let text = try source("App/Views/CodeEditorView.swift")

        XCTAssertFalse(text.contains("allowsNonContiguousLayout = true"),
                       "不许无条件打开非连续布局：小文档会因此出现「编辑后那一块不重画」")
        XCTAssertTrue(text.contains("allowsNonContiguousLayout = CodeLines.lineStarts(in: text).count > 1_000"),
                      "非连续布局要按文档大小分档打开（≥1,000 行），否则 NFR-PERF-05 的删除卡顿会退回来")
    }
}
