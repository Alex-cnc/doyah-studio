import XCTest
@testable import DoyahCore

/// 上下文预算账本（`FR-AGT-KNOW-MEM-009`）的机械判据。
///
/// 盯住三处：**逐段有数**（不是一句「大概占一半」）、**超预算要逐条点名**、
/// **只读**（账本不参与装配，算一遍不许改动上下文本身）。
final class AgentContextLedgerTests: XCTestCase {

    private let limits = AgentContextLimits()

    // MARK: - 逐段有数

    func testEverySectionHasCharactersTokensAndShare() {
        let refs: [AgentContextReference] = [
            .file(path: "memory://ws/routine/m1", text: "迁移之前先跑对账"),
            .projectRule(path: "AGENTS.md", text: "发布前先跑 verify-core"),
            .file(path: "src/main.swift", text: "print(1)"),
        ]
        let ledger = AgentContextLedgerBuilder.build(references: refs, limits: limits, budgetTokens: 100_000)

        XCTAssertEqual(ledger.rows.count, 3)
        XCTAssertTrue(ledger.rows.allSatisfy { $0.characters > 0 && $0.estimatedTokens > 0 })
        let sum = ledger.rows.reduce(0.0) { $0 + $1.share }
        XCTAssertEqual(sum, 1.0, accuracy: 0.0001, "占比之和应当是一整份")
        XCTAssertEqual(ledger.totalTokens, ledger.rows.reduce(0) { $0 + $1.estimatedTokens })
    }

    func testSegmentsAreClassifiedBySourceNotByTitle() {
        let refs: [AgentContextReference] = [
            .file(path: "memory://ws/routine/m1", text: "记忆"),
            .projectRule(path: "AGENTS.md", text: "规矩"),
            .file(path: "src/main.swift", text: "代码"),
            .terminalTail(text: "$ ls"),
            .gitState(branch: "main", changed: ["a.swift"], ahead: 1, behind: 0),
        ]
        let kinds = AgentContextLedgerBuilder.build(references: refs, limits: limits, budgetTokens: 100_000)
            .rows.map(\.kind)
        XCTAssertEqual(kinds, [.memory, .projectRule, .file, .toolResult, .toolResult])
    }

    func testExtraSectionsCoverSystemPromptAndHistory() {
        let ledger = AgentContextLedgerBuilder.build(
            references: [],
            extra: [(kind: .systemPrompt, title: "系统提示", text: "你是 Doyah 智能体"),
                    (kind: .history, title: "历史 3 轮", text: "用户：跑测试\n助手：已跑")],
            limits: limits,
            budgetTokens: 100_000)
        XCTAssertEqual(ledger.rows.map(\.kind), [.systemPrompt, .history])
        XCTAssertEqual(ledger.rows.map(\.title), ["系统提示", "历史 3 轮"])
    }

    // MARK: - 超预算：从后往前丢，逐条点名

    func testOverBudgetDropsFromTheEndAndNamesWhatWent() {
        let big = String(repeating: "字", count: 100)
        let refs: [AgentContextReference] = [
            .projectRule(path: "AGENTS.md", text: big),
            .file(path: "a.swift", text: big),
            .file(path: "b.swift", text: big),
        ]
        let ledger = AgentContextLedgerBuilder.build(references: refs, limits: limits, budgetTokens: 150)

        XCTAssertFalse(ledger.droppedTitles.isEmpty, "超预算必须点名丢了谁")
        XCTAssertEqual(ledger.droppedTitles.last, "file:b.swift", "从最后一段开始丢")
        XCTAssertLessThanOrEqual(ledger.totalTokens, 150)
        XCTAssertFalse(ledger.isOverBudget)
    }

    func testStillOverBudgetSaysSoInsteadOfPretending() {
        let refs: [AgentContextReference] = [.projectRule(path: "AGENTS.md", text: String(repeating: "字", count: 200))]
        let ledger = AgentContextLedgerBuilder.build(references: refs, limits: limits, budgetTokens: 10)
        XCTAssertTrue(ledger.isOverBudget, "只有一段且本身就超 ⇒ 如实说超，不假装塞得下")
    }

    func testEmptyContextIsAnEmptyLedger() {
        let ledger = AgentContextLedgerBuilder.build(references: [], limits: limits, budgetTokens: 100)
        XCTAssertTrue(ledger.isEmpty)
        XCTAssertEqual(ledger.totalTokens, 0)
        XCTAssertTrue(ledger.droppedTitles.isEmpty)
        XCTAssertFalse(ledger.isOverBudget)
    }

    // MARK: - 估算器口径

    func testEstimatorTreatsCJKAndASCIIDifferently() {
        XCTAssertEqual(AgentTokenEstimator.tokens("迁移对账"), 4, "中文一字一 token")
        XCTAssertEqual(AgentTokenEstimator.tokens("abcd"), 1)
        XCTAssertEqual(AgentTokenEstimator.tokens("abcde"), 2, "非中文按 4 字一 token 向上取整")
        XCTAssertEqual(AgentTokenEstimator.tokens(""), 0)
    }

    // MARK: - 截断透传 + 人读一行

    func testTruncatedFlagComesFromTheAssembler() {
        var small = limits
        small.maxFileCharacters = 5
        let ledger = AgentContextLedgerBuilder.build(
            references: [.file(path: "a.swift", text: String(repeating: "x", count: 100))],
            limits: small,
            budgetTokens: 100_000)
        XCTAssertTrue(ledger.rows[0].truncated, "装配截了就标截了，账本不另算")
    }

    func testDescribeLineIsHumanReadable() {
        let row = AgentContextLedgerRow(kind: .memory, title: "memory://ws/routine/m1",
                                        characters: 40, estimatedTokens: 40, share: 0.5, truncated: true)
        let line = AgentContextLedgerBuilder.describe(row)
        XCTAssertTrue(line.contains("40 token"))
        XCTAssertTrue(line.contains("50%"))
        XCTAssertTrue(line.contains("已截断"))
    }
}
