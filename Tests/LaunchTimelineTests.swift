import XCTest

@testable import DoyahCore

/// `NFR-ALL-GATE-PERF-001`（App 冷启动到可交互 ≤ 2 s）的**算术那一半**。
///
/// 真启动那一半由 `Scripts/measure-cold-start.py` 量（它读 App 写出的收据）。
/// 这里判的是：收据写得对、读得回、自相矛盾的收据不许当成绩、阈值判定不耍滑
/// （正好等于阈值算达标、多遍取中位数而不是挑最快那遍）。
///
/// **覆盖边界（如实）**：不含「真进程起点取到没取到」（那要真起一个进程，
/// 由测量脚本的 `build` 字段与收据里的 `processStart=firstLine` 标注来暴露）。
final class LaunchTimelineTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    private func timeline(elapsedMs: Double? = nil) -> LaunchTimeline {
        var timeline = LaunchTimeline(processStart: base)
        timeline.mark(.appInitialised, at: base.addingTimeInterval(0.12))
        if let elapsedMs {
            timeline.mark(.rootViewAppeared, at: base.addingTimeInterval(elapsedMs / 1000))
        }
        return timeline
    }

    // MARK: - 计时

    func testElapsedIsNilUntilTheRootViewHasAppeared() {
        // 零不是「很快」，是「没量到」—— 混成 0 会把没跑起来的启动读成好成绩。
        XCTAssertNil(timeline().elapsedMilliseconds)
        XCTAssertNil(timeline().milliseconds(at: .rootViewAppeared))
        XCTAssertEqual(timeline().milliseconds(at: .appInitialised).map { ($0 * 1000).rounded() / 1000 }, 120)
    }

    func testElapsedIsMeasuredFromProcessStart() {
        XCTAssertEqual(timeline(elapsedMs: 850).elapsedMilliseconds ?? -1, 850, accuracy: 0.001)
    }

    func testMarkKeepsTheFirstValueSoRebuildingTheViewDoesNotStretchTheStartup() {
        var value = timeline(elapsedMs: 700)
        // 主题 / 语言切换会让 `onAppear` 再跑一遍：终点不许被推后。
        value.mark(.rootViewAppeared, at: base.addingTimeInterval(9))
        XCTAssertEqual(value.elapsedMilliseconds ?? -1, 700, accuracy: 0.001)
    }

    func testTimestampsBeforeTheStartAreUnmeasurableNotZero() {
        XCTAssertNil(LaunchTimeline.milliseconds(from: base, to: base.addingTimeInterval(-1)))
        XCTAssertNil(LaunchTimeline.milliseconds(from: base, to: base.addingTimeInterval(.infinity)))
        XCTAssertEqual(LaunchTimeline.milliseconds(from: base, to: base) ?? -1, 0, accuracy: 0.001)
    }

    // MARK: - 收据读写

    func testReceiptRoundTripsThroughJSON() throws {
        let receipt = try LaunchReceipt(timeline: timeline(elapsedMs: 1234.5), build: "Debug;arm64")
        let decoded = try LaunchReceipt.decode(try receipt.encoded())
        XCTAssertEqual(decoded, receipt)
        XCTAssertEqual(decoded.elapsedMs, 1234.5, accuracy: 0.001)
        XCTAssertEqual(decoded.phasesMs["appInitialised"].map { ($0 * 1000).rounded() / 1000 }, 120)
        XCTAssertEqual(decoded.build, "Debug;arm64")
        XCTAssertEqual(decoded.schema, LaunchReceipt.schema)
    }

    func testReceiptRefusesToBeWrittenBeforeInteractive() {
        XCTAssertThrowsError(try LaunchReceipt(timeline: timeline())) { error in
            XCTAssertEqual(error as? LaunchReceiptError, .notInteractiveYet)
        }
    }

    func testHandEditedReceiptIsRejectedInsteadOfSilentlyScored() throws {
        let receipt = try LaunchReceipt(timeline: timeline(elapsedMs: 1500))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try receipt.encoded()) as? [String: Any]
        )
        // 只把「结论」改快，不改两个时刻 —— 正是「改收据骗门禁」的那一种形状。
        var tampered = object
        tampered["elapsedMs"] = 100
        let data = try JSONSerialization.data(withJSONObject: tampered)
        XCTAssertThrowsError(try LaunchReceipt.decode(data))
    }

    func testUnknownSchemaIsRejected() throws {
        let receipt = try LaunchReceipt(timeline: timeline(elapsedMs: 1500))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try receipt.encoded()) as? [String: Any]
        )
        var tampered = object
        tampered["schema"] = "doyah-launch-receipt/0"
        let data = try JSONSerialization.data(withJSONObject: tampered)
        XCTAssertThrowsError(try LaunchReceipt.decode(data)) { error in
            XCTAssertEqual(error as? LaunchReceiptError, .unknownSchema("doyah-launch-receipt/0"))
        }
    }

    // MARK: - 判定

    func testExactlyAtTheLimitCountsAsWithin() throws {
        // 需求原文是「≤ 2 s」—— 正好 2000 必须算达标，否则判据比契约更严。
        let receipt = try LaunchReceipt(timeline: timeline(elapsedMs: 2000))
        XCTAssertEqual(LaunchBudget.evaluate(receipt, limitMs: 2000), .within(measuredMs: 2000, limitMs: 2000))
        let slower = try LaunchReceipt(timeline: timeline(elapsedMs: 2000.5))
        XCTAssertFalse(LaunchBudget.evaluate(slower, limitMs: 2000).isPassing)
    }

    func testMissingReceiptAndBrokenLimitAreUnmeasurableNotPassing() {
        XCTAssertFalse(LaunchBudget.evaluate(nil, limitMs: 2000).isPassing)
        XCTAssertEqual(LaunchBudget.evaluate(nil, limitMs: 2000), .unmeasurable(reason: "no-receipt"))
        XCTAssertEqual(LaunchBudget.evaluate(nil, limitMs: 0), .unmeasurable(reason: "limit-not-positive"))
        XCTAssertEqual(LaunchBudget.evaluate(runs: [], limitMs: 2000), .unmeasurable(reason: "no-runs"))
        XCTAssertFalse(LaunchBudget.evaluate(runs: [100, 3000, 4000], limitMs: 2000).isPassing,
                       "三遍里两遍超阈值 ⇒ 中位数超阈值，不许报到最快那一遍（100 ms）身上")
        XCTAssertTrue(LaunchBudget.evaluate(runs: [100, 1400, 1800], limitMs: 2000).isPassing)
        // 覆盖边界（如实）：三遍里**只有一遍**超阈值时中位数仍达标 ⇒ 判绿。
        // 中位数的用途就是免疫单遍抖动；「一次都不许超」要另立判据（本版不立）。
    }

    func testMedianTakesTheLowerMiddleAndIgnoresGarbage() {
        XCTAssertEqual(LaunchBudget.median([3, 1, 2]), 2)
        XCTAssertEqual(LaunchBudget.median([4, 1, 3, 2]), 2)
        XCTAssertNil(LaunchBudget.median([]))
        XCTAssertNil(LaunchBudget.median([.nan, -5]))
    }
}
