import XCTest
@testable import DoyahCore

/// 技能沉淀（`FR-AGT-KNOW-MEM-010`）的机械判据。
///
/// 盯住三处：**失败不抽**、**没确认不抽**、**偶发不抽**（这三条任一松了，
/// 沉淀出来的就是「一次运气」而不是「一类做法」）。
final class AgentSkillSedimentationTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func task(_ id: String,
                      category: String = "doc-gates",
                      keywords: [String] = ["doc", "门禁"],
                      steps: [String] = ["跑 check-doc-tables", "跑 check-doc-numbers"],
                      succeeded: Bool = true,
                      confirmed: Bool = true,
                      minutesAgo: Double = 0) -> AgentTaskOutcome {
        AgentTaskOutcome(taskID: id, category: category, keywords: keywords, steps: steps,
                         succeeded: succeeded, confirmedByUser: confirmed,
                         at: now.addingTimeInterval(-minutesAgo * 60))
    }

    // MARK: - 只从成功且被确认的任务抽

    func testFailedTaskIsNotDistilled() {
        let result = AgentSkillSedimentation.distill([task("t1", succeeded: false), task("t2")])
        XCTAssertTrue(result.candidates.isEmpty, "失败的做法不许变成技能")
        XCTAssertTrue(result.refusals.contains(.notSuccessful(taskID: "t1")))
    }

    func testUnconfirmedTaskIsNotDistilled() {
        let result = AgentSkillSedimentation.distill([task("t1", confirmed: false), task("t2")])
        XCTAssertTrue(result.candidates.isEmpty, "模型自认做对不算确认")
        XCTAssertTrue(result.refusals.contains(.notConfirmed(taskID: "t1")))
    }

    func testEmptyStepsIsNamed() {
        let result = AgentSkillSedimentation.distill([task("t1", steps: []), task("t2")])
        XCTAssertTrue(result.refusals.contains(.emptySteps(taskID: "t1")))
    }

    // MARK: - 偶发不抽

    func testSingleOccurrenceIsNotRecurring() {
        let result = AgentSkillSedimentation.distill([task("t1")])
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(result.refusals.contains(.notRecurring(category: "doc-gates", seen: 1, required: 2)))
    }

    func testTwoOccurrencesAreEnough() {
        let result = AgentSkillSedimentation.distill([task("t1"), task("t2", minutesAgo: 10)])
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates[0].category, "doc-gates")
        XCTAssertEqual(result.candidates[0].evidenceTaskIDs, ["t2", "t1"], "证据按时间先后")
    }

    // MARK: - 抽出来的形状

    func testTriggersAndStepsAreDedupedInOrder() {
        let result = AgentSkillSedimentation.distill([
            task("t1", keywords: ["doc", "门禁"], steps: ["跑 tables", "跑 numbers"]),
            task("t2", keywords: ["门禁", "版本"], steps: ["跑 numbers", "写变更记录"], minutesAgo: 5),
        ])
        let candidate = result.candidates[0]
        // 按发生先后合并去重：t2（5 分钟前）在前、t1 在后。
        XCTAssertEqual(candidate.triggers, ["门禁", "版本", "doc"])
        XCTAssertEqual(candidate.steps, ["跑 numbers", "写变更记录", "跑 tables"])
    }

    func testStepCapTruncatesAndReports() {
        let steps = (1...20).map { "步骤 \($0)" }
        let result = AgentSkillSedimentation.distill([task("t1", steps: steps), task("t2", steps: steps, minutesAgo: 1)],
                                                     policy: .init(minimumOccurrences: 2, maximumSteps: 5))
        XCTAssertEqual(result.candidates[0].steps.count, 5)
        XCTAssertEqual(result.truncatedSteps, 15)
    }

    func testDifferentCategoriesDoNotMix() {
        let result = AgentSkillSedimentation.distill([
            task("t1", category: "doc-gates"),
            task("t2", category: "swift-tests", keywords: ["swift"], steps: ["跑 filter"]),
        ])
        XCTAssertTrue(result.candidates.isEmpty, "两类各只出现一次 ⇒ 都不抽")
        XCTAssertEqual(result.refusals.count, 2)
    }

    func testEmptyInputIsEmptyResult() {
        let result = AgentSkillSedimentation.distill([])
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(result.refusals.isEmpty)
        XCTAssertEqual(result.truncatedSteps, 0)
    }
}
