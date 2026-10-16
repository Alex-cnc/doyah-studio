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

    /// ③ 过程聚合（**2026-10-17 人类主人口径**）：「智能体自己执行的命令这些信息应该是在**同一条信息中滚动**，
    /// 避免刷屏」 —— 改前每调一次工具就开一张卡片（一跑十几跳就是一屏）；现在自跑的工具**只并进同一条过程消息**，
    /// 卡片只留给**要人动手**的那几种（等审批 / 已批 / 已应用）。
    ///
    /// 同时判**步骤清单**（人类主人同日第二令：「用户可以看到你正在执行到哪一步了」）。
    func testSelfRunToolsGatherIntoOneProgressMessageAndOnlyApprovalsBecomeCards() {
        var state = AgentChatState()
        ready(&state)
        state.beginRun(prompt: "读文件")

        state.apply(.hopStarted(index: 0))
        state.apply(.toolStarted(name: "read_file"))
        state.apply(.toolFinished(name: "read_file", outcome: "executed"))
        state.apply(.toolStarted(name: "list_dir"))
        state.apply(.toolFinished(name: "list_dir", outcome: "executed"))

        XCTAssertTrue(state.cards.isEmpty, "自跑的工具**不再**逐条开卡片（改前这里是 2 张）")
        let progress = state.messages.filter { $0.role == .tool }
        XCTAssertEqual(progress.count, 1, "自跑的命令收在**同一条**过程消息里（不刷屏）")
        XCTAssertEqual(progress[0].text.components(separatedBy: "\n").count, 2, "两次工具 = 同一块里两行")
        XCTAssertTrue(progress[0].text.contains("✓"), "跑完**就地**把那一行收尾")

        state.apply(.toolStarted(name: "delete_everything"))
        state.apply(.toolFinished(name: "delete_everything", outcome: "denied"))
        XCTAssertEqual(state.messages.filter { $0.role == .tool }.count, 1, "被拒的也进同一块")
        XCTAssertTrue(state.messages.last?.text.contains("✗ denied") ?? false, "被拒原因如实摆在那一行")

        // 步骤清单：第 1 步在跑，带着它跑过的工具名
        XCTAssertEqual(state.steps.count, 1, "一跳 = 一行（清单在输入框上方）")
        XCTAssertEqual(state.steps[0].index, 1)
        XCTAssertEqual(state.steps[0].tools, ["read_file", "list_dir", "delete_everything"])
        XCTAssertEqual(state.steps[0].status, .running)

        // **要人动手的**才开卡片（等审批 ⇒ 逐张可点）
        let id = state.requestApproval(name: "write_file", fingerprint: "fp-1", preview: "- a\n+ b")
        XCTAssertEqual(state.cards.count, 1)
        XCTAssertEqual(state.cards[0].outcome, .pendingApproval(fingerprint: "fp-1", preview: "- a\n+ b"))
        XCTAssertTrue(state.cards[0].expanded, "审批卡默认展开（要看见改什么）")
        state.toggleExpanded(cardID: id)
        XCTAssertFalse(state.cards[0].expanded, "能收起")
        XCTAssertTrue(state.approve(cardID: id))
        XCTAssertEqual(state.cards[0].outcome, .approved(fingerprint: "fp-1", preview: "- a\n+ b"))
        XCTAssertTrue(state.markApplied(cardID: id))
        XCTAssertEqual(state.cards[0].statusCode, "applied")

        // 跑完 ⇒ 最后一步收尾
        state.finishRun()
        XCTAssertEqual(state.steps[0].status, .done)

        // 新一轮 ⇒ 清单**另起**（上一轮的步骤不混进来），过程块也另起
        state.beginRun(prompt: "再来")
        XCTAssertTrue(state.steps.isEmpty, "新一轮 = 新任务，清单重新起")
        state.apply(.hopStarted(index: 0))
        state.apply(.toolStarted(name: "search"))
        XCTAssertEqual(state.messages.filter { $0.role == .tool }.count, 2, "新一轮另起一块")
        XCTAssertEqual(state.steps.count, 1)
        XCTAssertEqual(state.steps[0].index, 1, "新一轮从第 1 步起")
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
    /// 范围 = **对话界面自己的文件**（文件名带 `AgentChat`），不是「任何提到对话的文件」——
    /// 早先那版按**内容**筛，把 `WorkspaceAreaView.swift` 也圈了进来：那个文件里本来就有 Markdown 预览用的
    /// `HSplitView`（与对话无关），于是判据误报。**判据要按「这个文件是干什么的」划范围**，不是按它提到谁。
    func testChatSurfaceDoesNotBringItsOwnSidebarOrSplitContainer() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let views = root.appendingPathComponent("App/Views")
        guard let enumerator = FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil) else {
            return XCTFail("扫不到 App/Views —— 判据自己失效了")
        }
        let chatFiles = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .filter { $0.lastPathComponent.contains("AgentChat") }
        XCTAssertFalse(chatFiles.isEmpty, "对话界面文件一个都没扫到 ⇒ 判据自己失效了（不许空跑成绿）")
        for file in chatFiles {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            for forbidden in ["NavigationSplitView", "HSplitView", "VSplitView", "Sidebar"] {
                XCTAssertFalse(text.contains(forbidden),
                               "\(file.lastPathComponent) 里出现了 `\(forbidden)` —— 对话不许自立门户（`FR-AI-25` ①）")
            }
        }
    }

    /// 状态行最右那格：**会话标题**（取首条提问，不另调模型生成）。
    func testSessionTitleComesFromTheFirstPromptAndIsTruncated() {
        var state = AgentChatState()
        XCTAssertNil(state.sessionTitle, "还没提问 ⇒ 那格不出现（不留空壳）")
        ready(&state)
        state.beginRun(prompt: "修好滚动")
        XCTAssertEqual(state.sessionTitle, "修好滚动")

        // 一轮跑完再问第二句：标题仍跟**首条**（不跟最后一条）
        state.finishRun()
        state.beginRun(prompt: "第二问不该顶掉标题")
        XCTAssertEqual(state.sessionTitle, "修好滚动", "标题跟首条提问，不跟最后一条")

        // 超长 ⇒ 截断到 28 字 + 省略号（换行也压成空格）
        var long = AgentChatState()
        ready(&long)
        long.beginRun(prompt: String(repeating: "长", count: 40))
        XCTAssertEqual(long.sessionTitle, String(repeating: "长", count: 28) + "…", "超长截断到 28 字 + 省略号")

        var multiline = AgentChatState()
        ready(&multiline)
        multiline.beginRun(prompt: "第一行\n第二行")
        XCTAssertEqual(multiline.sessionTitle, "第一行 第二行", "换行压成空格（是一行标题，不是两行）")
    }
}
