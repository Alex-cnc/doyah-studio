import XCTest
@testable import DoyahCore

/// **只报关键节点**（2026-11-11 真机 · QQ 通道）。
///
/// 现场：一轮跑完，手机那头一口气收到六条 ——
/// ```
/// Step 1 · running list_dir（.） · 12s in
/// Step 2 · waiting for the model · 13s in
/// Step 2 · running read_file（Scripts/verify-all.sh） · 20s in
/// Step 3 · waiting for the model · 20s in
/// Step 3 · waiting for approval on the desktop · 30s elapsed
/// Step 3 · running run_command（git status --short） · 30s in
/// ```
/// 根因：`thinking ↔ tool` 每次来回都算「阶段变了」，于是**一次工具调用推两条**。
/// 主人当场定调：「应该是关键步骤和结论发 IM 通道」。
///
/// 判据四条：
/// ① `thinking ↔ tool` 振荡**一律不推**（这条是刷屏的正源，负例必须判红）；
/// ② 停在桌面审批 / 开始收尾 —— **推**（这是人真正要知道的转折）；
/// ③ 总条数封顶 3（一轮再长也不刷屏）；
/// ④ 结论一到就关闸：之后 `report` 一律不进箱。
final class AgentIMProgressKeyMomentsTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    // MARK: - ① 振荡不推

    func testToolToThinkingOscillationIsNotAdmitted() {
        let cadence = AgentIMProgressCadence()
        // 已经推过一条（在 30 秒处），此刻第 3 步 → 第 4 步，工具↔思考来回。
        let track = AgentIMProgressCadence.Track(pushes: 1, lastPushAt: t0, lastHop: 3, lastStage: .tool)
        XCTAssertFalse(cadence.admits(hop: 4, elapsed: 32, stage: .thinking,
                                      at: t0.addingTimeInterval(2), track: track),
                       "回到「等模型」不算关键节点")
        let track2 = AgentIMProgressCadence.Track(pushes: 1, lastPushAt: t0, lastHop: 3, lastStage: .thinking)
        XCTAssertFalse(cadence.admits(hop: 4, elapsed: 32, stage: .tool,
                                      at: t0.addingTimeInterval(2), track: track2),
                       "又去跑工具也不算关键节点")
    }

    // MARK: - ② 关键转折要推

    func testApprovalAndFinalizingAreAdmitted() {
        let cadence = AgentIMProgressCadence()
        let beforeApproval = AgentIMProgressCadence.Track(pushes: 1, lastPushAt: t0,
                                                          lastHop: 9, lastStage: .tool)
        XCTAssertTrue(cadence.admits(hop: 9, elapsed: 40, stage: .awaitingApproval,
                                     at: t0.addingTimeInterval(2), track: beforeApproval),
                      "停在桌面等审批必须推 —— 不动手就没法继续")
        let beforeFinal = AgentIMProgressCadence.Track(pushes: 2, lastPushAt: t0,
                                                       lastHop: 9, lastStage: .tool)
        XCTAssertTrue(cadence.admits(hop: 9, elapsed: 40, stage: .finalizing,
                                     at: t0.addingTimeInterval(2), track: beforeFinal),
                      "开始收尾要推 —— 结论马上到")
    }

    // MARK: - ③ 封顶

    func testCapIsThreePushesPerRun() {
        let cadence = AgentIMProgressCadence()
        XCTAssertEqual(cadence.maxPushes, 3, "一轮最多三条进度（加 ack 与结论 = 五条消息封顶）")
        let atCap = AgentIMProgressCadence.Track(pushes: 3, lastPushAt: t0, lastHop: 1, lastStage: .tool)
        XCTAssertFalse(cadence.admits(hop: 99, elapsed: 9_999, stage: .awaitingApproval,
                                      at: t0.addingTimeInterval(9_999), track: atCap),
                       "到了封顶，连审批也不再推 —— 结论会说明卡在哪")
    }

    func testDefaultsAreCoarseEnoughForARealRun() {
        let cadence = AgentIMProgressCadence()
        XCTAssertEqual(cadence.minHopDelta, 8)
        XCTAssertEqual(cadence.minInterval, 45)
        XCTAssertEqual(cadence.firstPushAfter, 20, "开跑 20 秒内不播报，别跟 ack 撞在一起")
    }

    // MARK: - ④ 收尾关闸

    func testReportAfterFinishIsDropped() async {
        let box = LineBox()
        let reporter = AgentIMProgressReporter(cadence: AgentIMProgressCadence(firstPushAfter: 0),
                                               language: .english) { line in
            await box.append(line)
            return true
        }
        // 关闸前：关键节点能进箱。
        let progressed = await reporter.report(AgentIMRunProgress(hop: 3, elapsed: 30, toolCalls: 2,
                                                                   stage: .awaitingApproval))
        XCTAssertTrue(progressed)
        await reporter.finish()
        // 关闸后：再报什么都不进箱（结论已经发出去了）。
        let afterFinish = await reporter.report(AgentIMRunProgress(hop: 4, tool: "run_command", summary: "git status",
                                                                    elapsed: 40, toolCalls: 3))
        XCTAssertFalse(afterFinish, "收尾后到的进度行一律丢弃")
        let lines = await box.lines
        XCTAssertEqual(lines.count, 1, "只该有收尾前那一条")
    }

    private actor LineBox {
        var lines: [String] = []
        func append(_ line: String) { lines.append(line) }
    }
}

/// **等确认那一档要带命令**（2026-11-11 真机：「这个 im 通道配置得有问题，批准的信息得发 IM 通道」）。
///
/// 现场：手机那头只看到 `Step 4 · waiting for approval on the desktop`，
/// 想知道拦的是什么必须跑回桌面 —— 等于没通知。
///
/// 判据：① 文案里要有工具名与被拦的内容；② 长命令截到 120 字（不把网关帧撑爆）；
/// ③ 没有工具名时退回旧文案，不许印出空括号。
final class AgentIMProgressApprovalInfoTests: XCTestCase {

    private func line(tool: String?, summary: String) -> String {
        AgentIMProgressText.line(for: AgentIMRunProgress(hop: 4, tool: tool, summary: summary,
                                                         elapsed: 25, toolCalls: 3,
                                                         stage: .awaitingApproval),
                                 language: .simplifiedChinese)
    }

    func testApprovalLineCarriesTheBlockedCommand() {
        let text = line(tool: "run_command", summary: "git commit -m \"IM 只报关键节点\"")
        XCTAssertTrue(text.contains("run_command"), "要说出哪个工具在等确认：\(text)")
        XCTAssertTrue(text.contains("git commit"), "要带上被拦的命令：\(text)")
        XCTAssertTrue(text.contains("批准"), "要告诉人在哪儿点：\(text)")
    }

    func testLongCommandIsBoundedToOneHundredTwentyCharacters() {
        let long = String(repeating: "a", count: 400)
        let text = line(tool: "run_command", summary: long)
        XCTAssertTrue(text.contains("…"), "超长要截断并留省略号")
        XCTAssertLessThan(text.count, 220, "整行不许超过 220 字：\(text.count)")
    }

    func testMissingToolFallsBackToThePlainLine() {
        let text = line(tool: nil, summary: "")
        XCTAssertTrue(text.contains("审批"), "没有工具名时退回旧文案：\(text)")
        XCTAssertFalse(text.contains("（）"), "不许印空括号：\(text)")
    }
}
