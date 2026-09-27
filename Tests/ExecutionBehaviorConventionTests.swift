import XCTest

/// 执行路径上两条**用户可见行为**的判据（都来自 2026-09-27 的人工点验）。
///
/// 这两条都是"看起来像小毛病、其实会天天硌人"的那类，而且都不是靠人眼评审能守住的：
/// 一条是赋值**顺序**（日志清空 vs 第一行状态），一条是 NSViewRepresentable 的**重建时序**
/// （读选区 → 设文本 → 挂 delegate → 放回选区）。写反了功能表面照跑，只有用户会发现。
final class ExecutionBehaviorConventionTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// ① **Output 日志按「每次执行」重来**。
    /// 需求提出者原话：「Output 应该只有当前执行的 query 的结果，不能一直往后追加」。
    func testOutputLogRestartsPerExecution() throws {
        let text = try source("App/AppState.swift")
        guard let execution = text.range(of: "func executeQuery(") else {
            return XCTFail("找不到 executeQuery —— 判据的锚点变了，请更新这条判据而不是删掉它")
        }
        let body = text[execution.lowerBound...]

        guard let clear = body.range(of: "$0.outputLog = []"),
              let firstStatus = body.range(of: "$0.statusMessage = L(.stateConnecting") else {
            return XCTFail("executeQuery 里找不到「清空 Output 日志」或「本次执行第一行状态」的锚点")
        }
        XCTAssertLessThan(
            clear.lowerBound, firstStatus.lowerBound,
            "清空 Output 日志必须排在本次第一行状态**之前** —— `statusMessage` 的 didSet 会往日志追加，顺序反了会把第一行（正在连接…）也清掉"
        )
    }

    /// ② 编辑器**重建后选区还在**（需求提出者原话：「选择一段 SQL 执行之后，应该还在被选择态」）。
    ///
    /// 背景：执行时结果区先清空再出现 ⇒ 四种 `VSplitView` 分支换两次 ⇒ SwiftUI 重建编辑器子树 ⇒
    /// 全新的 `NSTextView`，光标归 0、焦点也丢。所以要在新建时把 `EditorCommandCenter` 里记着的选区放回去。
    func testEditorRestoresSelectionAfterRebuild() throws {
        let text = try source("App/Views/SQLEditorView.swift")
        guard let make = text.range(of: "func makeNSView("),
              let update = text.range(of: "func updateNSView(") else {
            return XCTFail("找不到 makeNSView / updateNSView —— 判据的锚点变了，请更新这条判据而不是删掉它")
        }
        let body = text[make.lowerBound..<update.lowerBound]

        guard let read = body.range(of: "let reportedSelection = commandCenter.selection(for: tabID)"),
              let setText = body.range(of: "textView.string = text"),
              let delegate = body.range(of: "textView.delegate = context.coordinator"),
              let restore = body.range(of: "textView.setSelectedRange(reportedSelection)") else {
            return XCTFail("makeNSView 里缺少「读选区 / 设文本 / 挂 delegate / 放回选区」四步之一")
        }

        XCTAssertLessThan(read.lowerBound, setText.lowerBound, "顺序：先读选区，再设文本")
        XCTAssertLessThan(
            setText.lowerBound, delegate.lowerBound,
            "顺序：挂 delegate 必须在设文本**之后** —— 新视图挂上 delegate 会立刻上报 (0,0)，挂早了就把刚读出来的选区记录冲掉了"
        )
        XCTAssertLessThan(delegate.lowerBound, restore.lowerBound, "顺序：放回选区在挂 delegate 之后")

        XCTAssertTrue(body.contains("length > 0"), "只恢复**非空**选区 —— 空选区就是光标，强行放回会跟「载入后光标归 0」打架")
        XCTAssertTrue(
            body.contains("makeFirstResponder"),
            "重建会连焦点一起丢，不把焦点还给编辑器的话选区没有高亮 —— 而需求要的正是「还看得见刚选的那段」"
        )
    }
}
