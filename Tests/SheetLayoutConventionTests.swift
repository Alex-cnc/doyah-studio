import XCTest

/// 弹出面板的**尺寸口径**判据。
///
/// 起因（2026-09-27 人工点验）：需求提出者的原话是「Explain text 弹出对话框布局有问题，
/// 窗口特别高，上下两块很大的空白区域」。根因不是"间距大了点"，而是**尺寸写死**：
/// 面板 620、计划树 220、原始输出 110 都与内容无关，内容只有几行时就是两大片空白。
///
/// 所以口径定为：**面板只定宽、高度由内容算**（行数 × 行高，夹在令牌的上下限内），
/// 超过上限才滚动；空态不许用 `Spacer` 把面板顶满。这条判据守住它，免得下次重构又写回固定高度。
final class SheetLayoutConventionTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// 执行计划面板（FR-DIAG-01）的高度必须跟着内容走。
    func testExecutionPlanPanelHeightFollowsContent() throws {
        let text = try source("App/Views/ExecutionPlanPanel.swift")
        XCTAssertGreaterThan(text.count, 2_000, "读到的内容太短，这条判据不成立")

        XCTAssertFalse(
            text.contains(".frame(width: Metrics.planPanelWidth, height:"),
            "面板不许把宽度和高度一起写死（高度必须由内容算）"
        )
        XCTAssertTrue(
            text.contains("clampedHeight("),
            "两块文本区的高度要按行数算，并夹在上下限之间 —— 这正是本次修的那处"
        )
        for token in ["Metrics.planTreeMinHeight", "Metrics.planTreeMaxHeight",
                      "Metrics.planRawMinHeight", "Metrics.planRawMaxHeight"] {
            XCTAssertTrue(text.contains(token), "高度上下限要走令牌：缺 \(token)")
        }
        XCTAssertFalse(
            text.contains("frame(height: 220)") || text.contains("frame(height: 110)"),
            "这两处写死的固定高度就是「上下两块很大的空白区域」的来源，不许回来"
        )
    }

    /// 空态不许用 `Spacer` 把面板顶满（那也是空白区域的来源之一）。
    func testEmptyStateDoesNotExpandPanel() throws {
        let text = try source("App/Views/ExecutionPlanPanel.swift")
        guard let empty = text.range(of: "L(.planEmpty)") else {
            return XCTFail("找不到空态文案 L(.planEmpty) —— 判据的锚点变了，请更新这条判据而不是删掉它")
        }
        // 空态那一小段里不许出现 Spacer()。
        let after = text[empty.upperBound...].prefix(400)
        XCTAssertFalse(
            after.contains("Spacer()"),
            "空态用 Spacer 会把面板顶到最大高度，留下大片空白（本次修的就是这个）"
        )
    }
}
