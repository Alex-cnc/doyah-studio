import XCTest
@testable import DoyahCore

/// `/compact` 手动触发（`FR-AGT-KNOW-CTX-002` · 会话边界 `userCompact`）。
///
/// 判据只喂纯数据（历史 + 预算 + 是否回合内），不起真循环、不连模型。
final class AgentManualCompactionTests: XCTestCase {

    private func turns(_ pairs: [(String, String)]) -> [LLMTurn] {
        pairs.map { LLMTurn(role: $0.0, content: $0.1) }
    }

    private var longHistory: [LLMTurn] {
        turns([
            ("user", "帮我把这一批文档的条号对一遍"),
            ("assistant", String(repeating: "第一批读完了，四十份文件里只有三份的条号是断的。", count: 20)),
            ("user", "继续"),
            ("assistant", String(repeating: "第二批读完，断号集中在附则那一段。", count: 20)),
            ("user", "再看一眼索引"),
            ("assistant", String(repeating: "索引十七条与正文一致，附则那三条要补。", count: 20)),
            ("assistant", String(repeating: "最后一跳：判据跑完绿了。", count: 4)),
        ])
    }

    /// ① 回合内：只排队，历史一个字不改（§3.21 硬约束）。
    func testInTurnDefersAndLeavesHistoryUntouched() {
        let result = AgentManualCompaction.compact(history: longHistory,
                                                   budget: AgentContextCompressionBudget(),
                                                   inTurn: true)
        XCTAssertEqual(result.status, .deferred(next: .userCompact))
        XCTAssertEqual(result.history, longHistory, "回合内不许改写历史")
        XCTAssertNil(result.product, "回合内不许报「压过了」")
    }

    /// ② 历史太短：如实说「没什么可压」，不当失败、也不假装压过。
    func testShortHistoryReportsNothingToCompress() {
        let short = turns([("user", "问一句"), ("assistant", "答一句")])
        let result = AgentManualCompaction.compact(history: short,
                                                   budget: AgentContextCompressionBudget(),
                                                   inTurn: false)
        XCTAssertEqual(result.status, .nothingToCompress)
        XCTAssertEqual(result.history, short)
        XCTAssertNil(result.product)
    }

    /// ③ 真压：助手早期正文被折叠，**用户原话逐字保留**。
    func testCompactsAssistantBodiesButNeverUserWords() {
        let result = AgentManualCompaction.compact(history: longHistory,
                                                   budget: AgentContextCompressionBudget(),
                                                   inTurn: false)
        guard case .compacted = result.status else {
            return XCTFail("应当真压，实际 \(result.status)")
        }
        let userWordsBefore = longHistory.filter { $0.role == "user" }.map(\.content)
        let userWordsAfter = result.history.filter { $0.role == "user" }.map(\.content)
        XCTAssertEqual(userWordsAfter, userWordsBefore, "用户原话一个字都不许动")
        XCTAssertLessThan(result.history.reduce(0) { $0 + $1.content.count },
                          longHistory.reduce(0) { $0 + $1.content.count },
                          "压完应当更短")
        XCTAssertTrue(result.history.contains { $0.content.hasPrefix("[context compressed") },
                      "要有模型看得懂的折叠标记")
    }

    /// ④ 三个数都要报得出来（压了几条 / 约省多少 / 丢了哪些）+ 前后 token。
    func testReportsThreeReadings() throws {
        let result = AgentManualCompaction.compact(history: longHistory,
                                                   budget: AgentContextCompressionBudget(),
                                                   inTurn: false)
        let product = try XCTUnwrap(result.product)
        XCTAssertEqual(product.boundary, .userCompact)
        XCTAssertGreaterThan(product.tokensAfter, 0)
        XCTAssertLessThan(product.tokensAfter, product.tokensBefore)
        XCTAssertFalse(product.droppedKinds.isEmpty, "要说得出丢了哪一类")
        XCTAssertFalse(product.marker.isEmpty)
    }

    /// ⑤ 压完再压：已经只剩 keep 条正文 ⇒ 不重复压（幂等，不白烧一次）。
    func testSecondCompactionIsIdempotent() throws {
        let first = AgentManualCompaction.compact(history: longHistory,
                                                  budget: AgentContextCompressionBudget(),
                                                  inTurn: false)
        guard case .compacted = first.status else { return XCTFail("第一遍应当压") }
        let second = AgentManualCompaction.compact(history: first.history,
                                                   budget: AgentContextCompressionBudget(),
                                                   inTurn: false)
        XCTAssertEqual(second.status, .nothingToCompress)
        XCTAssertEqual(second.history, first.history, "第二遍不许再改历史")
    }

    /// ⑥ 压完仍超上限：拒不静默截断，历史原样（负例：预算小到压不进去）。
    func testRefusesWhenStillOverLimitAndKeepsHistory() {
        let tight = AgentContextCompressionBudget(maxPromptCharacters: 40,
                                                  keepRecentEntries: 1,
                                                  minimumEntries: 1)
        let result = AgentManualCompaction.compact(history: longHistory, budget: tight, inTurn: false)
        guard case .refused = result.status else {
            return XCTFail("预算远小于历史时应当拒（不静默截断），实际 \(result.status)")
        }
        XCTAssertEqual(result.history, longHistory, "拒的时候历史必须原样")
        XCTAssertNil(result.product)
    }
}
