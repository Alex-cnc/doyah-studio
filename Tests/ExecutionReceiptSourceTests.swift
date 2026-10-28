import XCTest

/// `FR-STD-DB-TASK-003` 的**源树判据**：形态必须真的接到执行 / 界面两条路上。
///
/// ## 为什么这条必须有
/// Core 那 25 例全绿只说明「算得对」。真正会出事的是接线断在半路：
/// · 只在成功时记回执、`catch` 里不记 ⇒ 需求 ③「失败也有回执（不因报错丢失）」是空的；
/// · 记了回执但没有界面可看 ⇒ 「可复制 / 导出」无从谈起；
/// · 复制 / 导出走的是别的路径（或干脆自己拼一段文本）⇒ 绕开了 `render` 也就绕开了脱敏。
/// 这三种都不会让 Core 判据变红，所以另立一条打在**源码锚点**上的判据。
///
/// 反过来的那一半同样要钉：`Core/ExecutionReceipt.swift` 里**不许**出现「把原文直接赋给字段」
/// 的写法（`self.sql = sql`）—— 它一旦回来，脱敏就只活在 `init` 调用的那一刻，
/// 而回执是长期挂在会话上、会被复制出去的东西。
final class ExecutionReceiptSourceTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relative: String, minLength: Int = 4000) throws -> String {
        let body = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        XCTAssertGreaterThan(body.count, minLength, "\(relative) 读到的内容太短，扫描面可疑")
        return body
    }

    // MARK: - 执行侧：四条出口都记

    /// 成功 / 失败 / 取消 / 被拦下 —— 每一档都得落到 `recordReceipt`。
    func testEveryExecutionExitRecordsAReceipt() throws {
        let body = try text("App/AppState.swift", minLength: 100_000)

        // 唯一写入口存在，且真的往页签的回执册里追加（而不是只打个日志）。
        XCTAssertTrue(body.contains("private func recordReceipt("), "缺少回执的唯一写入口")
        XCTAssertTrue(body.contains("$0.receiptLog.append(receipt)"), "写入口没有落到页签的回执册")

        for anchor in [
            // 成功 / 取消
            "outcome: cancelled ? .cancelled : .succeeded",
            // 失败 / 取消（catch 那一条）
            "outcome: cancelled ? .cancelled : .failed",
            // 只读连接拦下 + 任务定义拦下 + 事务态拦下：三条都读「未发出」
            "outcome: .refused"
        ] {
            XCTAssertTrue(body.contains(anchor), "执行侧缺少回执锚点：\(anchor)")
        }

        // 被拦下那一档至少三处（只读连接 / 任务定义 / 事务态），少一处就是漏了一整类出口。
        let refusedCount = body.components(separatedBy: "outcome: .refused").count - 1
        XCTAssertGreaterThanOrEqual(refusedCount, 3, "「未发出」只接了 \(refusedCount) 处，应有 3 处")

        // 需求 ③ 的反向：`catch` 里**不许**只写查询历史、不记回执。
        // （做法：失败分支里 `recordReceipt` 必须出现在 `succeeded: false` 那次 `recordHistory` 之前。）
        if let failureHistory = body.range(of: "succeeded: false,") {
            let before = body[body.startIndex..<failureHistory.lowerBound]
            XCTAssertTrue(before.contains("outcome: cancelled ? .cancelled : .failed"),
                          "失败分支里没有回执 —— 需求 ③ 的空心")
        } else {
            XCTFail("找不到失败分支的 recordHistory 锚点（扫描面过期）")
        }
    }

    // MARK: - 回执面：构造即脱敏

    func testReceiptRedactsAtConstruction() throws {
        let body = try text("Core/ExecutionReceipt.swift", minLength: 8000)
        XCTAssertTrue(body.contains("let cleanSQL = SensitiveTextRedactor.redact(sql)"),
                      "构造时没有过脱敏口")
        XCTAssertTrue(body.contains("self.sql = cleanSQL.text"),
                      "落字段的不是脱敏后的文本")
        // 反向：**回执本体那一段**里不许出现「原文直接赋给字段」的写法。
        // （只看 ReceiptLabels 之前那一段：文案结构里也有一个 `self.sql = sql`，那是字段名，不是回执内容。）
        if let bodyStart = body.range(of: "public struct ExecutionReceipt: Identifiable"),
           let labelsStart = body.range(of: "public struct ReceiptLabels") {
            let receiptBody = String(body[bodyStart.lowerBound..<labelsStart.lowerBound])
            XCTAssertFalse(receiptBody.contains("self.sql = sql"), "原文被直接塞进回执")
            XCTAssertFalse(receiptBody.contains("self.errorText = errorText"), "错误原文被直接塞进回执")
        } else {
            XCTFail("找不到回执本体的扫描面（结构被改名了？）")
        }
        // 解码也要过同一个口。
        XCTAssertTrue(body.contains("public init(from decoder: Decoder) throws"),
                      "没有自定义解码 —— 外部文件读回来会绕过脱敏")
    }

    // MARK: - 界面侧：能看到、能复制、能导出

    func testReceiptPaneIsWiredIntoTheLowerPane() throws {
        let tabBody = try text("Core/LowerPaneTab.swift", minLength: 2000)
        XCTAssertTrue(tabBody.contains("case receipts"), "下方面板没有「回执」页签")
        XCTAssertTrue(tabBody.contains("case .receipts: return .lowerPaneReceipts"),
                      "页签标题没接文案键")

        let paneBody = try text("App/Views/ExecutionReceiptPane.swift", minLength: 3000)
        XCTAssertTrue(paneBody.contains("tab?.receiptLog.newestFirst"), "视图没有读页签的回执册")
        XCTAssertTrue(paneBody.contains("appState.receiptLabels"), "视图没有用语言表里的文案")
        for action in ["appState.copyReceipts(for: tab.id)",
                       "appState.exportReceipts(for: tab.id)",
                       "appState.clearReceipts(for: tab.id)"] {
            XCTAssertTrue(paneBody.contains(action), "回执页缺少动作：\(action)")
        }

        let lowerBody = try text("App/Views/LowerPaneView.swift", minLength: 10_000)
        XCTAssertTrue(lowerBody.contains("case .receipts:"), "下方面板没有「回执」分支")
        XCTAssertTrue(lowerBody.contains("ExecutionReceiptPane(tab: tab)"), "「回执」页没挂上视图")
    }

    /// 复制 / 导出两条出口都必须走**渲染后的**（也就是脱敏后的）那份文本。
    func testCopyAndExportUseTheRenderedForm() throws {
        let body = try text("App/AppState.swift", minLength: 100_000)
        XCTAssertTrue(body.contains("receipt.render(labels: receiptLabels)"),
                      "复制单条没有走 render（那等于绕开脱敏）")
        XCTAssertTrue(body.contains("tab.receiptLog.exportText(labels: receiptLabels)"),
                      "复制全部没有走 exportText")
        XCTAssertTrue(body.contains("try tab.receiptLog.exportData()"),
                      "导出没有走回执册的 JSON 出口")
        // 反向：不许出现「把原始 SQL 拼进导出文本」的旁路。
        XCTAssertFalse(body.contains("receipt.rawSQL"), "回执不该有原文出口")
    }
}
