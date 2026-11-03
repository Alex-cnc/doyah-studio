import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// `FR-STD-DB-IO-007` · Excel 导入 Sheet：**尺寸与关闭入口**（2026-11-03 人类主人真机点验）。
///
/// 原话两条：
///   ① 「执行导入的按钮快被遮住」（Sheet 高度不够，底部动作区被截）；
///   ② 「对话框上部又有一个 close 按钮」（与已修的 `AboutLicenseSheet` 同族：同一件事出现两次）。
///
/// 判什么（两条口径，各自有反例）：
///   A. **面板根只钉宽度、高度由内容算**：空态高度必须**小于**原来写死的 760；
///      底部动作区长出一行（导入错误）之后，面板要**跟着长**（而不是把动作区挤出画布）。
///   B. **关闭入口只有一处**：`ImportPanel` 源里 `L(.commonClose)` 恰好一次（在 footer），
///      并且渲染出来的图里底部那一行动作在画布之内（图落在 `ui-snapshots/`，人可以直接看）。
///
/// 边界（如实登记）：探针判的是**离屏宿主里的排版**；sheet 在真窗口上被父窗口高度限制的观感
/// 要人点一次（清单见任务清单那一行）。这里不假装判得了"真机上看着舒服"。
final class ImportSheetLayoutProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "导入面板排版探针要真渲染：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
    }

    @MainActor
    private func makeState() async -> AppState {
        let state = AppState()
        await state.startupChain?.value
        state.connections = []
        state.selectedConnectionID = nil
        state.importError = nil
        state.importMessage = nil
        state.selectedTreeObject = nil
        return state
    }

    /// 面板递给 SwiftUI 的**理想尺寸**（sheet 就是按它定大小的）。
    @MainActor
    private func naturalSize(_ state: AppState) -> CGSize {
        let hosting = NSHostingView(rootView: ImportPanel().environmentObject(state))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    @MainActor
    func testPanelHeightFollowsContent() async throws {
        let state = await makeState()
        let empty = naturalSize(state)

        XCTAssertEqual(empty.width, 780, accuracy: 1, "面板宽度口径变了（宽度是钉死的，高度不是）")
        XCTAssertLessThan(
            empty.height, 760,
            "空态理想高度 \(empty.height) —— 面板根还钉着 760：父窗口矮一点就是把底部动作区裁掉"
        )
        XCTAssertGreaterThan(empty.height, 450, "空态高度 \(empty.height) 太小 —— 内容区被压成一条缝了")

        // 底部动作区长出一行（导入失败的原因）：面板必须跟着长，不许把动作区挤出画布。
        state.importError = L(.importFailed, "连不上 127.0.0.1:1：Connection refused")
        let withError = naturalSize(state)
        XCTAssertGreaterThan(
            withError.height, empty.height,
            "动作区长了一行而面板高度一点没变 —— 那行只能被裁掉（\(empty.height) → \(withError.height)）"
        )
        XCTAssertLessThanOrEqual(
            withError.height, Metrics.importContentMaxHeight + 360,
            "动作区长一行，面板长出一大截（\(withError.height)）—— 内容区没有上限，会把窗口顶爆"
        )

        // 留一张真图：底部「执行导入 / 关闭」那一行必须在画面里。
        try UISnapshot.write("import-sheet-with-error", size: withError, scale: 2) {
            ImportPanel().environmentObject(state)
        }
        XCTAssertEqual(
            withError, naturalSize(state),
            "同一份状态连算两次理想尺寸不一样 —— 排版不稳定，判据不成立"
        )
    }

    /// 关闭入口只有一处（footer）。顶部那枚已删 —— 同一件事在屏幕上出现两次，用户会犹豫点哪个。
    func testCloseAppearsExactlyOncePerSheet() throws {
        for file in ["App/Views/ImportPanel.swift",
                     "App/Views/AgentMemoryPanel.swift",
                     "App/Views/DebugPanelView.swift"] {
            let text = try source(file)
            let count = text.components(separatedBy: "L(.commonClose)").count - 1
            XCTAssertEqual(
                count, 1,
                "\(file) 里有 \(count) 处关闭入口 —— 关掉这个对话框的入口只许一处（底部动作区）"
            )
        }
    }
}
