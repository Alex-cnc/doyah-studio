import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// `FR-AGT-UX-CONV-008` / `-009` / `FR-AGT-GUARD-COST-001` 的**接线判据**。
///
/// 这三条此前都只到 Core：通知有策略没人发、求助有单子没有卡、门控挡下之后界面上
/// 连一个「仍然发送」都没有（而那两句理由里早就写着「点『仍然发送』」）。本文件守三件事：
///
/// ① 通知的**两处出口**口径不同（页内提示条 vs 系统通知），且必须一份文案；
/// ② 求助卡只在「需人处理」那一档出，且必须说清要什么 / 为什么 / 从哪接；
/// ③ 强发用的是**被挡下那一刻的**提示词与触发，且照常记账。
final class AgentNotifyWiringTests: XCTestCase {

    private let policy = AgentNotifyPolicy(longTaskThresholdSeconds: 30)

    // MARK: - 主动通知的两处出口

    /// 必须打断的那两档：人就在这页时**系统通知不弹，但页内提示条必须出**。
    ///
    /// 这是本条最容易做错的一格 —— 直接拿 `decide` 的 nil 当「什么都不用出」，
    /// 结果就是「他看着屏幕，界面上却什么都没有」。
    func testMustInterruptShowsBannerEvenWhenUserIsWatching() {
        let plan = policy.plan(.needsHumanDecision(question: "删还是留？"), userIsLookingAtThisPane: true)
        XCTAssertNil(plan.system, "人就在这页，不再弹系统通知")
        XCTAssertEqual(plan.banner?.body, "删还是留？", "页内提示条要出，且文案逐字一致")
    }

    func testMustInterruptRingsSystemWhenUserIsAway() {
        let plan = policy.plan(.approvalRequired(summary: "要改 3 个文件"), userIsLookingAtThisPane: false)
        XCTAssertEqual(plan.system?.mustInterrupt, true)
        XCTAssertNotNil(plan.banner)
    }

    /// 短任务两个出口都安静（界面上本来就看得到结果）。
    func testShortTaskStaysQuietOnBothOutlets() {
        let plan = policy.plan(.longTaskFinished(elapsedSeconds: 12),
                               userIsLookingAtThisPane: false, userIsIdle: true)
        XCTAssertTrue(plan.isEmpty)
    }

    /// 长任务：页内照出提示条；系统通知只在人走开的时候。
    func testLongTaskBannersAlwaysAndRingsOnlyWhenAway() {
        let watching = policy.plan(.longTaskFinished(elapsedSeconds: 95), userIsLookingAtThisPane: true)
        XCTAssertNotNil(watching.banner)
        XCTAssertNil(watching.system)
        let away = policy.plan(.longTaskFinished(elapsedSeconds: 95),
                               userIsLookingAtThisPane: false, userIsIdle: true)
        XCTAssertNotNil(away.banner)
        XCTAssertEqual(away.system?.title, "跑完了（95 秒）")
    }

    /// 失败：页内总出（失败最该被看见）；系统按「在不在看」判。
    func testFailureBannersAlwaysAndRingsWhenAway() {
        let watching = policy.plan(.failed(summary: "连不上库"), userIsLookingAtThisPane: true)
        XCTAssertNotNil(watching.banner)
        XCTAssertNil(watching.system)
        let away = policy.plan(.failed(summary: "连不上库"),
                               userIsLookingAtThisPane: false, userIsIdle: true)
        XCTAssertEqual(away.system?.body, "失败了：连不上库")
    }

    /// 两处出口**共用同一份文案**：语言换到英文时都不许漏汉字（各写一份就会在这里分叉）。
    func testBothOutletsUseTheSameLocalizedCopy() {
        let plan = policy.plan(.failed(summary: "timeout"), userIsLookingAtThisPane: false,
                               userIsIdle: true, language: .english)
        let han = try! NSRegularExpression(pattern: "\\p{Han}", options: [])
        for text in [plan.banner?.title, plan.banner?.body, plan.system?.title, plan.system?.body] {
            let value = text ?? ""
            XCTAssertNil(han.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                         "英文界面下不该出现汉字：\(value)")
        }
    }

    // MARK: - 求助卡（`FR-AGT-UX-CONV-009`）

    /// 缺装配：卡必须**可执行**（要什么 / 为什么 / 从哪接三样齐全），且归「要信息」那一类。
    func testMissingLoopHelpIsActionable() {
        let help = AgentHelpCatalogue.missingLoop()
        XCTAssertEqual(help.kind, .information)
        XCTAssertTrue(help.isActionable)
        XCTAssertFalse(help.ask.isEmpty)
        XCTAssertFalse(help.why.isEmpty)
        XCTAssertNotNil(help.resumeFrom, "必须说清给完之后从哪接着跑")
        XCTAssertTrue(help.rendered.contains(help.reasonPrefixForTest), "三行文案要真的拼出来")
    }

    /// 缺点端：同一条纪律（这是一类要人去设置里办的事，不是「重试就好」）。
    func testMissingEndpointHelpIsActionable() {
        let help = AgentHelpCatalogue.missingEndpoint()
        XCTAssertTrue(help.isActionable)
        XCTAssertEqual(help.kind, .information)
        XCTAssertTrue(help.rendered.contains("API Key"))
    }

    /// 英文界面下求助卡也不许漏汉字。
    func testHelpCatalogueIsLocalized() {
        let han = try! NSRegularExpression(pattern: "\\p{Han}", options: [])
        let help = AgentHelpCatalogue.missingLoop(language: .english)
        let text = help.rendered(language: .english)
        XCTAssertNil(han.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                     "英文界面下不该出现汉字：\(text)")
    }

    // MARK: - 「仍然发送」（`FR-AGT-GUARD-COST-001`）

    /// 强发：同一个触发再来一次，**必须放行**，并且照常记账（下一次同样问法才不会立刻又被挡）。
    func testForcedProceedPassesAndRecords() {
        var gate = AgentInvocationGate()
        let trigger = AgentGateTrigger(source: "chat", digest: "abc", at: Date())
        XCTAssertTrue(gate.decide(trigger).isSkipped == false, "第一次当然放行")
        gate.record(.proceed, for: trigger)
        // 同样的指纹再来一次 ⇒ 挡下（这就是省 token 的那一刀）。
        guard case .skipped(let reason) = gate.decide(trigger) else {
            return XCTFail("同样的问法第二次必须被挡")
        }
        XCTAssertTrue(reason.contains("仍然发送"), "理由里点名那个按钮，界面才有出处")
        let recall = AgentGateRecall(prompt: "再问一次同样的", reason: reason, trigger: trigger)
        let decision = gate.forcedProceed(recall)
        XCTAssertFalse(decision.isSkipped, "「仍然发送」必须真的放行")
        // 记账复查：放行之后「上一次问过什么」更新成这一次 ⇒ 下一次同样问法仍会被挡（口径不变）。
        XCTAssertEqual(gate.lastProceeded["chat"]?.digest, "abc")
    }

    /// 强发**不许换一份数据**：提示词与触发逐字保留（界面不读输入框）。
    func testRecallKeepsTheExactPromptAndTrigger() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let trigger = AgentGateTrigger(source: "chat", digest: "digest-1", at: at)
        let recall = AgentGateRecall(prompt: "替我把表结构读出来", reason: "同样的问法刚问过", trigger: trigger)
        XCTAssertEqual(recall.prompt, "替我把表结构读出来")
        XCTAssertEqual(recall.trigger.digest, "digest-1")
        XCTAssertEqual(recall.trigger.at, at)
    }

    // MARK: - 界面模型的三格状态（真模型，不另写一份规则）

    /// 宿主没接装配 ⇒ 求助卡当场出（这是唯一能告诉用户「缺的是什么」的通道）。
    @MainActor
    func testChatModelSurfacesHelpWhenHostWiredNoLoop() async {
        let model = AgentChatModel()
        model.endpointProvider = { .ready(model: "m", endpoint: "https://example.invalid") }
        model.refreshEndpoint()
        model.makeLoop = { _, _, _ in nil }
        model.input = "看一下这个库"
        await model.send()
        XCTAssertEqual(model.helpRequest?.kind, .information)
        XCTAssertTrue(model.helpRequest?.isActionable == true)
        // 收起之后不再出现（不自己回来骚扰）。
        model.dismissHelpRequest()
        XCTAssertNil(model.helpRequest)
    }

    /// 端点没配 ⇒ 连一轮都起不来，求助卡**也不许出**（缺的是设置，不是这一轮的失败 ——
    /// 界面上「没法发」那条提示已经在说这件事，再来一张卡是重复）。
    @MainActor
    func testChatModelDoesNotSurfaceHelpWhenEndpointIsMissing() async {
        let model = AgentChatModel()
        model.endpointProvider = { .notConfigured }
        model.refreshEndpoint()
        model.makeLoop = { _, _, _ in nil }
        model.input = "看一下这个库"
        await model.send()
        XCTAssertNil(model.helpRequest)
    }

    /// 没有门控挡下时，「仍然发送」那一行不该存在；收起它也不改任何别的状态。
    @MainActor
    func testNoGateRecallByDefault() {
        let model = AgentChatModel()
        XCTAssertNil(model.gateRecall)
        XCTAssertNil(model.notifyBanner)
        model.dismissGateRecall()
        XCTAssertNil(model.gateRecall)
    }
}

private extension AgentHelpRequest {
    /// 判据用：`rendered` 里「原因：」那一行的抬头（从语言表取，别在测试里抄死文案）。
    var reasonPrefixForTest: String {
        LocalizedStrings.format(.agentHelpWhyPrefix, language: .simplifiedChinese, "占位")
            .replacingOccurrences(of: "占位", with: "")
    }
}
