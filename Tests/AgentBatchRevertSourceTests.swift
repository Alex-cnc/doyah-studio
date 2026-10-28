import XCTest
@testable import DoyahCore

/// `FR-STD-WS-EDIT-015` 的**接线判据**（源树）：整批撤回真的从账算批次、真的接到界面上。
///
/// 为什么这些要用源树判据钉：Core 的纯函数判据全绿，界面照样可能「根本没有那一枚按钮」
/// （Core 有代码、界面上点不到 —— 正是「实现不能标 ✅」的那一档），
/// 也可能「视图自己读盘算前像」（于是「撤回到哪一版」出现第二个答案）。
final class AgentBatchRevertSourceTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        return Self.stripComments(text)
    }

    /// 只剥 `//` 行注释 —— 这几处的文档注释里满是「计划 / 前像」这类词，
    /// 不剥就会把注释当成接线（同族判据既有做法）。
    private static func stripComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    func testHostBuildsTheBatchFromTheLedger() throws {
        let state = try source("App/AppState.swift")
        XCTAssertTrue(state.contains("AgentWriteBatchRevert.snapshots(from: edits)"),
                      "批次必须从「已应用的账」取前像（另存一份前像 = 第二个真相）")
        XCTAssertTrue(state.contains("AgentWriteBatchRevert.plan(snapshots: snapshots, reader: reader)"),
                      "计划必须走 Core 的纯函数，不在这里再写一套")
        XCTAssertTrue(state.contains("AgentWriteBatchRevert.inverse(of: steps, reader: reader)"),
                      "撤回本身要留反向批次（可再撤回）")
    }

    func testInverseIsComputedBeforeTheWrite() throws {
        let state = try source("App/AppState.swift")
        guard let inverse = state.range(of: "AgentWriteBatchRevert.inverse(of: steps, reader: reader)"),
              let apply = state.range(of: "AgentWriteBatchRevert.apply(steps)") else {
            return XCTFail("反向批次与落盘这两处都得在（缺一处这条判据就失效）")
        }
        XCTAssertTrue(inverse.lowerBound < apply.lowerBound,
                      "反向批次必须在落盘**之前**算 —— 落盘后盘上已是撤后的样子，前像就丢了")
    }

    func testEveryAppliedWriteRefreshesTheCounter() throws {
        let state = try source("App/AppState.swift")
        let count = state.components(separatedBy: "syncAgentBatchRevertState()").count - 1
        XCTAssertGreaterThanOrEqual(count, 2,
                                    "写文件那两档（整篇重写 / 定点改）写成功后都要刷新读数，否则入口不出现")
        XCTAssertTrue(state.contains("agentEditJournal.unmarkUndone("),
                      "「撤销这次撤回」之后这一笔要重新算可撤")
    }

    func testRevertAndRedoBothSyncTheEditorBuffer() throws {
        let state = try source("App/AppState.swift")
        let count = state.components(separatedBy: "for path in run.moved { syncEditorBuffer(path: path, root: root) }").count - 1
        XCTAssertEqual(count, 2, "撤回与再撤回都要把盘上结果推进正开着的页签（一份文件只有一个重载出口）")
    }

    func testViewExposesTheEntryAndDoesNotRecomputeThePlan() throws {
        let view = try source("App/Views/AgentChatView.swift")
        XCTAssertTrue(view.contains("appState.agentBatchRevert"),
                      "这一行的读数来自宿主")
        XCTAssertTrue(view.contains("appState.revertAgentBatch(workspacePath:"),
                      "「整批撤回」必须真的点得动")
        XCTAssertTrue(view.contains("appState.redoAgentBatchRevert(workspacePath:"),
                      "「撤销这次撤回」必须真的点得动")
        // 反向：视图不许自己读盘 / 自己算计划（否则撤回逻辑有两份）。
        XCTAssertFalse(view.contains("String(contentsOf:"), "视图不许自己读盘算前像")
        XCTAssertFalse(view.contains("AgentWriteBatchRevert.plan"), "视图不许绕过宿主自己算计划")
    }
}
