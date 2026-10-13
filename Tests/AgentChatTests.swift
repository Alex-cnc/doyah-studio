import XCTest
@testable import DoyahCore

/// `FR-AI-25`（Home 区对话页签）在本侧可判的那一半 —— 验收要点 ①②③④⑤。
/// 界面模型按仓里既有纪律拆开：**规则与状态在 Core（这里判）**，SwiftUI 薄壳在 App。
final class AgentChatTests: XCTestCase {

    private func ready(_ state: inout AgentChatState) {
        state.setEndpoint(.ready(model: "m-1", endpoint: "http://127.0.0.1:11434/v1"))
    }

    // MARK: - ② 流式渲染：增量**逐段**追加，不是等整段

    func testDeltasAppendIncrementallyNotAsOneBlock() {
        var state = AgentChatState()
        ready(&state)
        state.beginRun(prompt: "你好")
        state.apply(.hopStarted(index: 0))
        state.apply(.delta("你"))
        XCTAssertEqual(state.messages.last?.text, "你", "收到一个增量就该看见一个增量")
        state.apply(.delta("好，"))
        XCTAssertEqual(state.messages.last?.text, "你好，")
        state.apply(.delta("世界"))
        XCTAssertEqual(state.messages.last?.text, "你好，世界")
        XCTAssertEqual(state.messages.last?.isStreaming, true, "还没收尾")

        // 下一跳开始 ⇒ 上一条**定稿**、新开一条
        state.apply(.hopStarted(index: 1))
        XCTAssertEqual(state.messages.filter { $0.role == .assistant }.count, 2)
        XCTAssertEqual(state.messages[state.messages.count - 2].isStreaming, false, "上一跳要定稿")

        // 停 ⇒ 收尾 + 如实说停因 + 不再「在跑」
        state.apply(.stopped(.stepLimit(3)))
        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(state.messages.last?.text, "stepLimit:3", "停因如实摆出来（含数值）")
        XCTAssertFalse(state.messages.contains { $0.isStreaming })
    }

    // MARK: - ③ 工具卡片：可展开，未登记的调用也如实显示为「被拒」+ 原因

    func testToolCallsBecomeExpandableCardsAndRefusalsShowTheirReason() {
        var state = AgentChatState()
        ready(&state)
        state.beginRun(prompt: "读文件")
        state.apply(.toolStarted(name: "read_file"))
        XCTAssertEqual(state.cards.count, 1)
        XCTAssertEqual(state.cards[0].outcome, .running)
        XCTAssertFalse(state.cards[0].expanded, "默认收起")

        state.apply(.toolFinished(name: "read_file", outcome: "executed"))
        XCTAssertEqual(state.cards[0].outcome, .executed("executed"))
        XCTAssertEqual(state.cards[0].statusCode, "executed")

        state.toggleExpanded(cardID: state.cards[0].id)
        XCTAssertTrue(state.cards[0].expanded, "能展开")

        // 未登记的调用：**不执行**，但卡片如实标被拒 + 原因
        state.apply(.toolStarted(name: "delete_everything"))
        state.apply(.toolFinished(name: "delete_everything", outcome: "denied"))
        XCTAssertEqual(state.cards.last?.outcome, .denied("denied"))

        let reasonCard = state.cards.last!.id
        state.markDenied(cardID: reasonCard, reason: "unregistered")
        XCTAssertEqual(state.cards.last?.outcome, .denied("unregistered"))
        XCTAssertEqual(state.cards.last?.statusCode, "denied:unregistered")
        XCTAssertTrue(state.cards.last!.outcome.isTerminal)
    }

    // MARK: - ④ 内联审批：**批准之前先看见要改什么**；批准后才应用；授权按次

    func testApprovalShowsThePreviewFirstAndGrantsOnlyOneUse() {
        var state = AgentChatState()
        ready(&state)
        let cardID = state.requestApproval(name: "write_file", fingerprint: "fp-1",
                                          preview: "--- a.txt\n+++ a.txt\n-旧\n+新")

        XCTAssertEqual(state.cards.last?.outcome, .pendingApproval(fingerprint: "fp-1",
                                                                  preview: "--- a.txt\n+++ a.txt\n-旧\n+新"))
        XCTAssertTrue(state.cards.last?.expanded == true, "审批卡片默认展开（要人做决定）")
        XCTAssertEqual(state.cards.last?.approvalPreview, "--- a.txt\n+++ a.txt\n-旧\n+新", "**批准前就能看见要改什么**")
        XCTAssertTrue(state.grants.isEmpty, "还没批就没有授权")

        XCTAssertTrue(state.approve(cardID: cardID), "能批准")
        XCTAssertEqual(state.grants, ["fp-1"])
        if case .approved(let fingerprint, _) = state.cards.last?.outcome {
            XCTAssertEqual(fingerprint, "fp-1")
        } else { XCTFail("批准后卡片该是 approved") }

        XCTAssertTrue(state.markApplied(cardID: cardID), "批准后才应用")
        XCTAssertEqual(state.cards.last?.outcome, .applied(fingerprint: "fp-1"))
        XCTAssertTrue(state.grants.isEmpty, "**按次**：用过就没了，再要动得重新批")

        // 拒绝那一档：不留授权
        let second = state.requestApproval(name: "run_command", fingerprint: "fp-2", preview: "cat a.txt")
        XCTAssertTrue(state.deny(cardID: second))
        XCTAssertEqual(state.cards.last?.outcome, .denied("userRejected"))
        XCTAssertTrue(state.grants.isEmpty)
        XCTAssertFalse(state.markApplied(cardID: second), "被拒的卡片不许被应用")
    }

    // MARK: - ⑤ 端点未配置 / 连不上 ⇒ 界面如实说，**不许假装在跑**

    func testUnconfiguredOrUnreachableEndpointIsReportedAndNothingIsSent() {
        var state = AgentChatState()
        XCTAssertEqual(state.endpoint, .notConfigured)
        XCTAssertFalse(state.canSend, "没配端点就是不能发")
        XCTAssertEqual(state.endpoint.blockerCode, "endpointNotConfigured")

        state.beginRun(prompt: "你好")
        XCTAssertTrue(state.messages.isEmpty || state.messages.allSatisfy { $0.role == .notice },
                      "不能发的时候**一条提问都不许装进对话**")
        XCTAssertEqual(state.messages.last?.text, "endpointNotConfigured", "要如实说原因")
        XCTAssertFalse(state.isRunning, "不许显示成「在跑」")

        state.setEndpoint(.unreachable("connection refused"))
        XCTAssertFalse(state.canSend)
        XCTAssertEqual(state.endpoint.blockerCode, "endpointUnreachable")
        state.beginRun(prompt: "再试一次")
        XCTAssertEqual(state.messages.last?.text, "endpointUnreachable")

        state.setEndpoint(.ready(model: "m", endpoint: "http://127.0.0.1:11434/v1"))
        XCTAssertTrue(state.canSend, "配好了就能发")
        state.beginRun(prompt: "现在可以了")
        XCTAssertEqual(state.messages.last?.role, .assistant)
        XCTAssertTrue(state.messages.last?.isStreaming == true)
    }

    // MARK: - ① 对话页签挂在 **Home 区页签条**上（不是新开侧栏 / 分栏）

    func testAgentChatIsAWorkspaceTabKindAndReusesTheSingleTab() {
        // 对话是 `WorkspaceTab` 的第三种，而不是另立门户
        let kinds = WorkspaceTab.Kind.allCases
        XCTAssertEqual(kinds, [.home, .file, .agentChat], "对话页签是 Home 区页签条上的一种")
        let chat = WorkspaceTab.agentChat(title: "对话")
        XCTAssertTrue(chat.isAgentChat)
        XCTAssertFalse(chat.isHome, "**对话页签不是 Home 欢迎页**")
        XCTAssertNil(chat.path, "它不是文件页")

        // 打开规则与文件页签同一条纪律：**已经有就复用**
        let home = WorkspaceTab.home(title: "首页")
        let first = WorkspaceTabSet.openingAgentChat(title: "对话", in: [home])
        XCTAssertEqual(first.tabs.count, 2)
        let second = WorkspaceTabSet.openingAgentChat(title: "对话", in: first.tabs)
        XCTAssertEqual(second.tabs.count, 2, "同一个对话不许开成两个页签")
        XCTAssertEqual(second.selected, first.selected)
    }

    /// 源树判据：**对话界面不许自立门户**（不得用侧栏 / 分栏容器承载对话）。
    ///
    /// 现在一个都还没有（界面是下一片）—— 这条判据的价值在下一片落地后生效；
    /// 它同时守着「提对话的文件数不许是零之外的意外增长」这件事由下一片的接线判据接管。
    func testChatSurfaceDoesNotBringItsOwnSidebarOrSplitContainer() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let views = root.appendingPathComponent("App/Views")
        guard let enumerator = FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil) else {
            return XCTFail("扫不到 App/Views —— 判据自己失效了")
        }
        let chatFiles = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .filter { (try? String(contentsOf: $0, encoding: .utf8))?.contains("AgentChat") == true }
        for file in chatFiles {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            for forbidden in ["NavigationSplitView", "HSplitView", "VSplitView", "Sidebar"] {
                XCTAssertFalse(text.contains(forbidden),
                               "\(file.lastPathComponent) 里出现了 `\(forbidden)` —— 对话不许自立门户（`FR-AI-25` ①）")
            }
        }
    }
}
