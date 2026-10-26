import XCTest
@testable import DoyahCore

/// `FR-AGT-QUAL-VERIFY-002`（长任务一致性：跨小时不丢目标）—— 三条正判据 + 一条反例。
///
/// 判据先行：这里先钉死「恢复要接着做、第一步先复述、目标改了以最新为准」，
/// 以及反例「不是每一步都复述」。
final class AgentResumeBriefTests: XCTestCase {

    private func recovery(stepIndex: Int?,
                          completed: [String] = [],
                          digest: String = "",
                          skippedSteps: Int = 0) -> AgentCheckpointRecovery {
        guard let stepIndex else {
            return AgentCheckpointRecovery(checkpoint: nil, skippedSteps: skippedSteps, skippedLines: 0)
        }
        let checkpoint = AgentCheckpoint(sessionID: "s-1",
                                         stepIndex: stepIndex,
                                         completedSteps: completed,
                                         goalDigest: digest,
                                         at: Date(timeIntervalSince1970: 1_700_000_000))
        return AgentCheckpointRecovery(checkpoint: checkpoint, skippedSteps: skippedSteps, skippedLines: 0)
    }

    // MARK: - 判据 ① 中断之后接着做（不是从头）

    func testResumeContinuesFromNextStepInsteadOfRestarting() {
        let brief = AgentResumeBrief.make(goal: "把 t 表按 region 汇总",
                                          recovery: recovery(stepIndex: 4, completed: ["读了表结构", "写了 SQL"]))
        XCTAssertEqual(brief.fromStep, 5, "检查点在第 4 跳 ⇒ 从第 5 跳接着做")
        XCTAssertFalse(brief.isFreshStart)
        XCTAssertEqual(brief.completedSteps, ["读了表结构", "写了 SQL"], "已完成部分要如实带过来")
    }

    func testNoCheckpointIsHonestlyAFreshStart() {
        let brief = AgentResumeBrief.make(goal: "把 t 表按 region 汇总",
                                          recovery: recovery(stepIndex: nil, skippedSteps: 3))
        XCTAssertEqual(brief.fromStep, 0)
        XCTAssertTrue(brief.isFreshStart)
        XCTAssertTrue(brief.completedSteps.isEmpty, "没有检查点就不许假装有进度")
        XCTAssertEqual(brief.skippedSteps, 3, "回退跳数如实报")
    }

    // MARK: - 判据 ② 恢复第一步先复述目标与已完成

    func testNarrationRestatesGoalAndDoneParts() {
        let brief = AgentResumeBrief.make(goal: "把 t 表按 region 汇总",
                                          recovery: recovery(stepIndex: 2, completed: ["读了表结构", "写了 SQL"]))
        let text = brief.narration()
        XCTAssertTrue(text.contains("目标：把 t 表按 region 汇总"), text)
        XCTAssertTrue(text.contains("已完成：读了表结构；写了 SQL"), text)
        XCTAssertTrue(text.contains("从第 4 步接着做"), text)
    }

    func testNarrationMentionsRedoWhenStepsWereSkipped() {
        let brief = AgentResumeBrief.make(goal: "汇总",
                                          recovery: recovery(stepIndex: 1, completed: ["读了表结构"], skippedSteps: 2))
        XCTAssertTrue(brief.narration().contains("有 2 步没有可用记录"), brief.narration())
    }

    func testEmptyCompletedStepsIsSaidPlainly() {
        let brief = AgentResumeBrief.make(goal: "汇总", recovery: recovery(stepIndex: 0))
        XCTAssertTrue(brief.narration().contains("还没有跑完的步骤"), brief.narration())
    }

    func testEnglishNarrationIsAlsoComplete() {
        let brief = AgentResumeBrief.make(goal: "summarize t by region",
                                          recovery: recovery(stepIndex: 1, completed: ["read schema"]))
        let text = brief.narration(language: .english)
        XCTAssertTrue(text.contains("Goal: summarize t by region"), text)
        XCTAssertTrue(text.contains("Done so far: read schema"), text)
        XCTAssertTrue(text.contains("Resuming at step 3"), text)
    }

    // MARK: - 反例：不是每一步都复述目标（那是噪音）

    func testRestatesOnlyWhenResuming() {
        XCTAssertTrue(AgentResumeBrief.shouldRestate(isResume: true))
        XCTAssertFalse(AgentResumeBrief.shouldRestate(isResume: false), "同一轮里后续每一步不许再复述")
    }

    // MARK: - 判据 ③ 目标被改过时以最新为准

    func testGoalChangeIsDetectedAndNewestGoalWins() {
        let old = "把 t 表按 region 汇总"
        let digest = AgentFingerprint.hash(old)
        let changed = AgentResumeBrief.make(goal: "改成按 city 汇总",
                                            recovery: recovery(stepIndex: 3, completed: ["读了表结构"], digest: digest))
        XCTAssertTrue(changed.goalChanged)
        XCTAssertEqual(changed.goal, "改成按 city 汇总")
        XCTAssertTrue(changed.narration().contains("以现在这份为准"), changed.narration())
        XCTAssertFalse(changed.narration().contains(old), "简报不许还带着旧目标的说法")
    }

    func testSameGoalIsNotReportedAsChanged() {
        let goal = "把 t 表按 region 汇总"
        let brief = AgentResumeBrief.make(goal: goal,
                                          recovery: recovery(stepIndex: 2, digest: AgentFingerprint.hash(goal)))
        XCTAssertFalse(brief.goalChanged)
        XCTAssertFalse(brief.narration().contains("以现在这份为准"))
    }

    func testLegacyCheckpointWithoutGoalDigestIsNotTreatedAsChanged() {
        let brief = AgentResumeBrief.make(goal: "任何目标",
                                          recovery: recovery(stepIndex: 1, completed: ["读了表结构"], digest: ""))
        XCTAssertFalse(brief.goalChanged, "老记录没有指纹 ⇒ 判「没改过」，不许凭空报改")
    }

    // MARK: - 边界：检查点里不存目标原文

    func testCheckpointStoresOnlyGoalDigestNotTheGoalText() throws {
        let goal = "把 t 表按 region 汇总，输出 CSV"
        let checkpoint = AgentCheckpoint(sessionID: "s-9",
                                         stepIndex: 1,
                                         goalDigest: AgentFingerprint.hash(goal),
                                         at: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try AgentCheckpointStore.encoder.encode(checkpoint)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("region"), "检查点不许落目标原文：\(text)")
    }
}
