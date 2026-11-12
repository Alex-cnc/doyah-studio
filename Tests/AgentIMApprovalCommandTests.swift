import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// **「批准 <码>」这条远程通道**（2026-11-11 主人原话：「我只能在 QQ 指挥，不在电脑前」）。
///
/// 背景：桌面弹层是主路，主人在外面时那条路走不通 —— 一轮就卡在等审批上，
/// IM 只发了「waiting for approval」，人却没有任何手段放行。
///
/// 设计约束（每条都配了负例）：
/// ① **只认带码的句子**；「批准」两个字单发不许放行任何东西；
/// ② **码对不上就拒绝**（每条命令一个码，不能拿别的单的码混过去）；
/// ③ **一次性**：用过即焚，同一句重发不再生效；
/// ④ **过期作废**：超过 15 分钟的单不许再放；
/// ⑤ 没有待批的单时如实说，不许假装成功。
final class AgentIMApprovalCommandTests: XCTestCase {

    // MARK: - ① 解析：只认带码

    func testParsesChineseApproveWithCode() {
        XCTAssertEqual(AgentIMApprovalCommand.parse("批准 a1b2"),
                       .init(approve: true, code: "a1b2"))
        XCTAssertEqual(AgentIMApprovalCommand.parse("  拒绝 9F3C "),
                       .init(approve: false, code: "9f3c"))
    }

    func testParsesEnglishAndNoSpaceForms() {
        XCTAssertEqual(AgentIMApprovalCommand.parse("approve 12ab"),
                       .init(approve: true, code: "12ab"))
        XCTAssertEqual(AgentIMApprovalCommand.parse("批准：a1b2"),
                       .init(approve: true, code: "a1b2"))
    }

    /// 负例：没有码的「批准」只是聊天，**不许**放行任何东西。
    func testBareApprovalIsNotACommand() {
        XCTAssertNil(AgentIMApprovalCommand.parse("批准"))
        XCTAssertNil(AgentIMApprovalCommand.parse("批准吧"))
        XCTAssertNil(AgentIMApprovalCommand.parse("好的，我批准"))
        XCTAssertNil(AgentIMApprovalCommand.parse("approve"))
    }

    /// 负例：码的形状不对就不是指令（避免把「批准 5 条」这种话当成码）。
    func testNonHexOrWrongLengthCodeIsNotACommand() {
        XCTAssertNil(AgentIMApprovalCommand.parse("批准 abc"))
        XCTAssertNil(AgentIMApprovalCommand.parse("批准 abcdefghi"))
        XCTAssertNil(AgentIMApprovalCommand.parse("批准 zzzz"))
        XCTAssertNil(AgentIMApprovalCommand.parse("批准 3"))
    }

    func testUnrelatedWordsAreNotCommands() {
        XCTAssertNil(AgentIMApprovalCommand.parse("跑一下测试 a1b2"))
        XCTAssertNil(AgentIMApprovalCommand.parse("现在Doyah Studio能否正常使用？"))
    }

    // MARK: - ②–⑤ 票据：码 / 一次性 / 过期 / 没有待批

    @MainActor
    private func makeModel() -> AgentChatModel {
        let model = AgentChatModel()
        model.languageProvider = { .simplifiedChinese }
        return model
    }

    @MainActor
    func testNoTicketSaysNothingIsWaiting() {
        let model = makeModel()
        let reply = model.resolveIMApproval(.init(approve: true, code: "a1b2"))
        XCTAssertTrue(reply.contains("没有等你批"), "没有待批的单要如实说：\(reply)")
    }

    @MainActor
    func testWrongCodeIsRejected() {
        let model = makeModel()
        model.setIMApprovalTicketForTesting(code: "a1b2", cardID: UUID())
        let reply = model.resolveIMApproval(.init(approve: true, code: "ffff"))
        XCTAssertTrue(reply.contains("对不上"), "码不对要明说：\(reply)")
        XCTAssertNotNil(model.imApprovalTicket, "码不对不许把票作废（人可能只是打错了）")
    }

    @MainActor
    func testTicketIsSingleUse() {
        let model = makeModel()
        let card = UUID()
        model.setIMApprovalTicketForTesting(code: "a1b2", cardID: card)
        let first = model.resolveIMApproval(.init(approve: false, code: "a1b2"))
        XCTAssertTrue(first.contains("已拒绝"), "第一次应当落地：\(first)")
        XCTAssertNil(model.imApprovalTicket, "用过即焚")
        let second = model.resolveIMApproval(.init(approve: false, code: "a1b2"))
        XCTAssertTrue(second.contains("没有等你批"), "同一句重发不许再生效：\(second)")
    }

    @MainActor
    func testExpiredTicketIsDropped() {
        let model = makeModel()
        model.setIMApprovalTicketForTesting(code: "a1b2", cardID: UUID(),
                                            issuedAt: Date().addingTimeInterval(-AgentChatModel.imApprovalTicketLifetime - 5))
        let reply = model.resolveIMApproval(.init(approve: true, code: "a1b2"))
        XCTAssertTrue(reply.contains("过期"), "过期要明说：\(reply)")
        XCTAssertNil(model.imApprovalTicket)
    }
}
