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

        guard let read = body.range(of: "let reportedSelection = commandCenter.restorableSelection(tabID: tabID, in: text)"),
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
            body.contains("restorableSelection"),
            "放回去之前必须验证记录没过期（位置/长度/内容）；只认位置长度的话，文本一改偏移就漂，高亮会落到别的语句上"
        )
        XCTAssertTrue(
            body.contains("makeFirstResponder"),
            "重建会连焦点一起丢，不把焦点还给编辑器的话选区没有高亮 —— 而需求要的正是「还看得见刚选的那段」"
        )
    }

    // MARK: ③④⑤ 运行范围「跑的是哪一段」这一族（现场：选中 delete，跑的却是第 1 条 select）

    /// ③ 执行时读的选区必须是**显示中的编辑器**，不是那份缓存记录。
    ///
    /// 2026-09-27 人工点验现场：需求提出者选中 `DELETE` 执行，到服务器的却是脚本里第 1 条
    /// `SELECT` —— 数据库侧 `n_tup_del = 0`（那条 DELETE 从未到达服务器）可证。缓存记录会被
    /// 视图重建、外部文本同步（`applyExternalText` 设成 `(0,0)`）冲掉 ⇒ **用户眼里高亮的那一段才算数**。
    func testExecutionResolvesSelectionFromTheLiveEditor() throws {
        let text = try source("App/AppState.swift")
        guard let execution = text.range(of: "func executeQuery(") else {
            return XCTFail("找不到 executeQuery —— 判据的锚点变了，请更新这条判据而不是删掉它")
        }
        let body = String(text[execution.lowerBound...])

        XCTAssertTrue(
            body.contains("selection: EditorCommandCenter.shared.selectionForExecution(tabID: tabID)"),
            "运行范围解析要读显示中的编辑器（`selectionForExecution`）"
        )
        XCTAssertFalse(
            body.contains("selection: EditorCommandCenter.shared.selection(for: tabID)"),
            "不许退回那份缓存记录：它被冲掉过，而冲掉的后果是「静默跑错段落」"
        )
        XCTAssertTrue(
            body.contains("lastSelectionMismatch"),
            "缓存与实际不一致时必须留痕（判据看不见的时序，只能靠现场日志）"
        )
    }

    /// ④ 选区的唯一可信来源，是**显示中的那个 `NSTextView`**。
    func testLiveTextViewIsTheSelectionSource() throws {
        let center = try source("App/EditorCommandCenter.swift")
        XCTAssertTrue(center.contains("weak var view: SQLTextView"), "登记显示中的编辑器要用 weak（视图销毁后不留引用）")
        XCTAssertTrue(center.contains("view?.selectedRange()"), "要直接问那个视图此刻的选区")
        XCTAssertTrue(
            center.contains("return live ?? selection(for: tabID)"),
            "以实际选区为准、缓存只兜底（顺序反了就等于没修）"
        )

        let editor = try source("App/Views/SQLEditorView.swift")
        let registrations = editor.components(separatedBy: "commandCenter.register(textView:").count - 1
        XCTAssertGreaterThanOrEqual(
            registrations, 2,
            "makeNSView 与 updateNSView 都要登记：重建之后登记进去的必须是**新的**那个视图"
        )
    }

    /// ⑤ 「这一跑跑的是哪一段」必须写在 Output 里，而且**工具条上不许再有那个开关**。
    ///
    /// 口径（2026-09-27 需求提出者拍板）：有选区跑选中、没选区跑整篇，**自动判定**；
    /// 「整篇 / 光标所在语句 / 选中片段」那种要用户先设一次的菜单是多此一举，已删。
    /// 这条判据守住两件事：跑哪一段写在明面上（静默跑错段落 = 这一族最坏的形状），
    /// 以及那个菜单不许以任何形式回来。
    func testRunScopeIsStatedInTheOutputLog() throws {
        let appState = try source("App/AppState.swift")
        XCTAssertTrue(
            appState.contains("L(.stateRunScope, scopeSummary.scopeName, scopeSummary.runningStatements)"),
            "Output 要有一行写明本次运行范围与本次语句数"
        )
        XCTAssertTrue(
            appState.contains("L(.stateRunScopeSkipped, scopeSummary.scriptStatements)"),
            "脚本里还有没跑的语句时必须**明说没跑**，不能只跑一条了事"
        )

        let toolbar = try source("App/Views/QueryToolbar.swift")
        for forbidden in ["runScopeMenu", "scopeButton", "executionScope"] {
            XCTAssertFalse(
                toolbar.contains(forbidden),
                "工具条上不许再有「运行范围」这类开关（\(forbidden)）：有选区跑选中、没选区跑整篇，自动判定就够了"
            )
        }

        let labels = try source("App/ExecutionScopeTitle.swift")
        XCTAssertTrue(
            labels.contains("extension ExecutionScope.Source"),
            "「跑的是哪一段」的说法要有一个唯一出处（ExecutionScope.Source.title）"
        )
        for key in [".execSourceSelection", ".execSourceWholeScript"] {
            XCTAssertTrue(labels.contains(key), "来源名映射少了 \(key)")
        }

        // 判定只有一处实现：AppState 里不许再出现"按某个模式跑"的残留。
        XCTAssertFalse(
            appState.contains("executionScope."),
            "执行路径不许再读一个用户设的「运行范围」状态"
        )
    }

    /// ⑥ **高危确认弹窗点「仍然执行」必须真的执行**，而且跑的就是批准过的那一份。
    ///
    /// 2026-09-27 人工点验实测：`DELETE FROM tx_demo;` 被拦下，弹窗里点「Run anyway」——
    /// **什么都没发生**（既不执行也不报错）。根因是这一族里最典型的「闭包 vs 状态」时序：
    /// 按钮的动作是「先 `onConfirm()`（起一个 `Task`）再 `dismiss()`」，而 `.sheet(item:)`
    /// 在关闭时会把绑定的 `pendingExecution` 置空 —— 等 `Task` 真正跑起来，
    /// `guard let pending = pendingExecution else { return }` 就静默返回了。
    ///
    /// 两条都不许回来：① 不读 `pendingExecution` 状态（由弹窗把待执行项传进来）；
    /// ② 执行的是弹窗里那几条（`sqlOverride: pending.sql`），不是重新解析出来的另一份。
    func testConfirmedHighRiskStatementActuallyRunsTheApprovedStatements() throws {
        let appState = try source("App/AppState.swift")
        guard let confirm = appState.range(of: "func confirmPendingExecution(") else {
            return XCTFail("找不到 confirmPendingExecution —— 判据的锚点变了，请更新这条判据而不是删掉它")
        }
        let body = String(appState[confirm.lowerBound...].prefix(1_400))

        XCTAssertTrue(
            body.contains("func confirmPendingExecution(_ pending: PendingExecution)"),
            "待执行项必须由弹窗**传进来**：读 `pendingExecution` 状态会踩上「dismiss 已经把它置空」的时序（实测点「仍然执行」毫无反应）"
        )
        XCTAssertFalse(
            body.contains("guard let pending = pendingExecution"),
            "不许再从状态里取待执行项 —— 那正是静默返回的那个形状"
        )
        XCTAssertTrue(
            body.contains("sqlOverride: pending.sql"),
            "执行弹窗里确认过的那一份 SQL：重新解析编辑器可能换一份跑（选区在弹窗期间可能变）"
        )
        XCTAssertTrue(body.contains("bypassingSafetyCheck: true"), "确认之后不该再弹一次同样的窗")

        let window = try source("App/Views/MainWindow.swift")
        XCTAssertTrue(
            window.contains("confirmPendingExecution(pending)"),
            "`onConfirm` 必须显式带上 `pending`；不带就又回到「读状态」那条老路"
        )
    }
}
