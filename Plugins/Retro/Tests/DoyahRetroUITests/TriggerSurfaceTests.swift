import XCTest

import DoyahRetroCore
import DoyahRetroUI

// `FR-R-13-10` **触发面 UI** 的机械证据（Retro macOS · Alpha 4 首片 B · 任务卡 `t_811e5b11`）。
//
// 契约出处 = `Docs/需求规范书.md` §3.13 `FR-R-13-10`（SRS v1.15 · 人类主人 2026-10-09 拍板 C）
// ①②③④ —— 手动「生成本期」· 用户可配置本地定时（周期 / 时刻 / 开关）· 触发失败 ⇒ 界面明确提示（**不静默**）。
//
// 三条纪律（与首片 A 同款）：
//   ① **注入桩**：执行器与调度器**一律注入桩** —— 从不真跑生成侧、从不真等时间（判据 ⑤）；
//   ② 跑**真目录真文件**（临时目录）：缺期日志吃的是盘上的字节；
//   ③ 断言**确定结果值**（三态 / 三键 / 提示行 / 重扫次数），不断言「没崩就算过」。
//
// 五条点名判据：**按钮触发恰一次生成** · **三键读写 `UserDefaults`** · **缺期提示出现且非静默** ·
// **生成成功后重扫被调** · **注入桩未被真实调用**。另加：三键缺省值 · 调度器可注入且到点走同一条入口 ·
// **到点后重排下一次（「周期」不是一次性）** · 「本月之外无缺期 ⇒ 提示保持静默」（证明提示不是常亮）·
// 下到点纯函数可复算。
final class TriggerSurfaceTests: XCTestCase {

    private var base: URL!
    private var scanRoot: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    /// 固定时区日历（+08:00）—— 让「ISO 周 / 到点」的断言可复算，不受本机时区漂移。
    private var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 缺期落点（**唯一**）= 扫描根同级文件（核心层 `GenerationSpec`）。
    private var logURL: URL { GenerationSpec.missedPeriodLogURL(nextToScanRoot: scanRoot) }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-retro-trigger-ui-\(UUID().uuidString)", isDirectory: true)
        scanRoot = base.appendingPathComponent("packages", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        suiteName = "doyah-retro-trigger-ui-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        if let base { try? FileManager.default.removeItem(at: base) }
    }

    // MARK: - 注入桩（**从不真跑生成侧、从不真等时间**）

    /// 预置读数的执行器桩：记调用次数，返回给它的那条读数。
    private final class StubExecuting: GenerationExecuting {
        private(set) var callCount = 0
        private let result: GenerationExecution
        init(_ result: GenerationExecution) { self.result = result }
        func runGeneration() -> GenerationExecution {
            callCount += 1
            return result
        }
    }

    /// 调度器桩：记安排 / 取消；`fire()` 手动到点（**不真等时间**）。
    private final class StubScheduler: GenerationScheduling {
        private(set) var scheduledDates: [Date] = []
        private(set) var cancelCount = 0
        private var onFire: (@MainActor () -> Void)?

        func schedule(nextFire: Date, onFire: @escaping @MainActor () -> Void) {
            scheduledDates.append(nextFire)
            self.onFire = onFire
        }

        func cancel() {
            cancelCount += 1
            onFire = nil
        }

        @MainActor func fire() { onFire?() }
    }

    // MARK: - 夹具

    @MainActor
    private func makeModel(
        executing: GenerationExecuting = StubExecuting(.exited(code: 0)),
        scheduler: GenerationScheduling = StubScheduler(),
        now: Date,
        onGenerated: @escaping @MainActor () -> Void = {}
    ) -> GenerationTriggerModel {
        GenerationTriggerModel(
            scanRoot: scanRoot,
            defaults: defaults,
            executing: executing,
            scheduler: scheduler,
            now: { now },
            onGenerated: onGenerated
        )
    }

    /// 往缺期日志落一行（走核心层的 `MissedPeriodRecord.jsonLine` —— 键序与 A 逐字节同源）。
    private func seedMissedPeriod(period: String, timestamp: String) throws {
        let record = MissedPeriodRecord(period: period, result: "失败", timestamp: timestamp)
        try Data((record.jsonLine + "\n").utf8).write(to: logURL)
    }

    /// 盘上缺期日志的逐行（文件不在 ⇒ 空数组）。
    private func missedLines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        let text = try String(contentsOf: logURL, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
    }

    // MARK: - 判据 ①：按钮 ⇒ 恰触发一次生成

    @MainActor
    func testManualGenerateRunsExactlyOneGeneration() throws {
        let stub = StubExecuting(.exited(code: 0))
        let model = makeModel(executing: stub, now: date(2026, 10, 9, 10, 0))

        // 「本期」= 当前周的 ISO 周（2026-10-09 ⇒ 2026-W41）。
        XCTAssertEqual(model.currentPeriod, "2026-W41")

        let outcome = model.generateNow()
        XCTAssertEqual(outcome, .success(period: "2026-W41"))
        XCTAssertEqual(stub.callCount, 1, "手动按钮应触发**恰好一次**生成")
        XCTAssertNotNil(model.lastOutcomeLine, "结果行应可见（不静默）")
    }

    // MARK: - 判据 ②：定时三键读写 `UserDefaults`（含缺省值）

    @MainActor
    func testThreeSettingsRoundTripThroughUserDefaults() throws {
        let first = makeModel(now: date(2026, 10, 9, 10, 0))
        // 缺省：每周 · 08:30 · 关。
        XCTAssertEqual(first.cycle, .weekly)
        XCTAssertEqual(first.timeOfDay, "08:30")
        XCTAssertFalse(first.isScheduledEnabled)

        first.setCycle(.daily)
        first.setTimeOfDay("21:15")
        first.setEnabled(true)

        // 原始键面：三个键名（唯一出处 = `GenerationSettingKey`）逐键读回。
        XCTAssertEqual(defaults.string(forKey: GenerationSettingKey.cycle), "daily")
        XCTAssertEqual(defaults.string(forKey: GenerationSettingKey.timeOfDay), "21:15")
        XCTAssertTrue(defaults.bool(forKey: GenerationSettingKey.enabled))

        // 用同一份 `UserDefaults` 再建一个模型 ⇒ 三键读回一致（真落盘、不是内存态）。
        let second = makeModel(now: date(2026, 10, 9, 10, 0))
        XCTAssertEqual(second.cycle, .daily)
        XCTAssertEqual(second.timeOfDay, "21:15")
        XCTAssertTrue(second.isScheduledEnabled)
    }

    // MARK: - 判据 ③：缺期提示出现且**非静默**（+ 本月之外保持静默）

    @MainActor
    func testMissedPeriodNoticeIsVisibleForCurrentMonthAndNotSilent() throws {
        try seedMissedPeriod(period: "2026-W40", timestamp: "2026-10-05T08:30:00+08:00")
        let model = makeModel(now: date(2026, 10, 9, 10, 0))

        let notice = try XCTUnwrap(model.missedPeriodNotice, "本月有缺期 ⇒ 界面必须给一行可见提示（不静默）")
        XCTAssertTrue(notice.contains("2026-W40"), "提示应点出最近缺期的期号，实际 \(notice)")
        XCTAssertTrue(notice.contains("1 条"), "提示应点出条数，实际 \(notice)")
    }

    @MainActor
    func testMissedPeriodNoticeStaysSilentForOtherMonthsThenAppearsOnRefresh() throws {
        // 上月的缺期 ⇒ 提示保持静默（证明它不是**常亮**）。
        try seedMissedPeriod(period: "2026-W39", timestamp: "2026-09-28T08:30:00+08:00")
        let model = makeModel(now: date(2026, 10, 9, 10, 0))
        XCTAssertNil(model.missedPeriodNotice)

        // 追加一行**本月**缺期 ⇒ 刷新后提示出现（不静默）。
        let seeded = try String(contentsOf: logURL, encoding: .utf8)
        let extra = MissedPeriodRecord(period: "2026-W41", result: "失败", timestamp: "2026-10-09T09:00:00+08:00").jsonLine + "\n"
        try Data((seeded + extra).utf8).write(to: logURL)

        model.refreshMissedPeriodNotice()
        let notice = try XCTUnwrap(model.missedPeriodNotice, "新增本月缺期 ⇒ 刷新后应出现提示")
        XCTAssertTrue(notice.contains("2026-W41"), "实际 \(notice)")
    }

    // MARK: - 判据 ④：生成**成功**后重扫被调（失败不重扫）

    @MainActor
    func testSuccessfulGenerationTriggersRescanExactlyOnceAndFailureDoesNot() throws {
        var rescans = 0

        let success = makeModel(
            executing: StubExecuting(.exited(code: 0)),
            now: date(2026, 10, 9, 10, 0),
            onGenerated: { rescans += 1 }
        )
        _ = success.generateNow()
        XCTAssertEqual(rescans, 1, "生成成功 ⇒ 重扫入口被调**恰好一次**")

        let failure = makeModel(
            executing: StubExecuting(.exited(code: 2)),
            now: date(2026, 10, 9, 10, 0),
            onGenerated: { rescans += 1 }
        )
        _ = failure.generateNow()
        XCTAssertEqual(rescans, 1, "失败 ⇒ 不重扫（只记一行缺期 + 出提示）")
    }

    // MARK: - 判据 ⑤：注入桩未被真实调用（真生成侧从不被起）

    @MainActor
    func testInjectedStubExecutorIsUsedAndRealGeneratorNeverLaunched() throws {
        // 桩回一个「真生成侧不会这么退」的码：能出现 ⇒ 证明走的是**注入桩**，不是真起子进程。
        let stub = StubExecuting(.exited(code: 7))
        let model = makeModel(executing: stub, now: date(2026, 10, 9, 10, 0))

        let outcome = model.generateNow()

        guard case .failure(_, let reason) = outcome else {
            return XCTFail("应判失败，实际 \(outcome)")
        }
        XCTAssertTrue(reason.contains("7"), "失败原因应来自**注入桩**的读数，实际 \(reason)")
        XCTAssertEqual(stub.callCount, 1, "注入桩应被调用**恰好一次**（真生成侧一次都没被起）")
        XCTAssertEqual(try missedLines().count, 1, "失败 ⇒ 向扫描根同级追**一行**缺期")
    }

    // MARK: - 另加：调度器可注入 · 到点走同一条入口 · 关开关清到点

    @MainActor
    func testSchedulerIsInjectableAndTimedFireRunsTheSameEntry() throws {
        let scheduler = StubScheduler()
        let stub = StubExecuting(.exited(code: 0))
        let model = makeModel(executing: stub, scheduler: scheduler, now: date(2026, 10, 9, 10, 0))

        model.setEnabled(true)
        XCTAssertEqual(scheduler.scheduledDates.count, 1, "开定时 ⇒ 恰好安排一次到点")
        let next = try XCTUnwrap(model.nextFireDate)
        XCTAssertGreaterThan(next, date(2026, 10, 9, 10, 0), "到点应在 now 之后")

        scheduler.fire() // 注入桩手动到点 ⇒ 走**同一条** `generateNow()` 入口
        XCTAssertEqual(stub.callCount, 1, "到点应触发一次生成")

        model.setEnabled(false)
        XCTAssertEqual(scheduler.cancelCount, 1, "关开关 ⇒ 取消安排")
        XCTAssertNil(model.nextFireDate)
    }

    // MARK: - 另加：到点**重排下一次**（「周期」= 每天 / 每周重复，不是一次性）

    @MainActor
    func testTimedFireReschedulesTheNextOccurrence() throws {
        let scheduler = StubScheduler()
        let stub = StubExecuting(.exited(code: 0))
        // 时钟可推：到点后把「现在」拨到上一次到点 ⇒ 重排的读数可复算。
        var clock = date(2026, 10, 9, 10, 0) // 周五
        let model = GenerationTriggerModel(
            scanRoot: scanRoot,
            defaults: defaults,
            executing: stub,
            scheduler: scheduler,
            now: { clock },
            onGenerated: {}
        )

        model.setCycle(.daily)
        model.setEnabled(true)
        XCTAssertEqual(scheduler.scheduledDates.count, 1, "开定时 ⇒ 恰好安排一次到点")
        let first = try XCTUnwrap(model.nextFireDate)
        XCTAssertEqual(first, date(2026, 10, 10, 8, 30), "每天 08:30（今天已过）⇒ 明天 08:30")

        // 到点（注入桩手动）⇒ 跑一次生成 **且再排下一次**（周期不是一次性）。
        clock = first
        scheduler.fire()
        XCTAssertEqual(stub.callCount, 1, "到点应触发一次生成")
        XCTAssertEqual(scheduler.scheduledDates.count, 2, "到点后应**重排**下一次（否则「周期」只生效一次）")
        let second = try XCTUnwrap(model.nextFireDate)
        XCTAssertGreaterThan(second, first, "重排的到点应**前移**（严格晚于上一次）")
        XCTAssertEqual(second, date(2026, 10, 11, 8, 30), "下一次 = 后天同一时刻")

        // 再走一轮 ⇒ 再排一次（链条持续，不是排两次就停）。
        clock = second
        scheduler.fire()
        XCTAssertEqual(stub.callCount, 2, "第二次到点再触发一次生成")
        XCTAssertEqual(scheduler.scheduledDates.count, 3, "第二轮到点后仍应重排")
        XCTAssertEqual(model.nextFireDate, date(2026, 10, 12, 8, 30))
    }

    @MainActor
    func testTimedFireDoesNotRescheduleWhenDisabledDuringRun() throws {
        let scheduler = StubScheduler()
        var clock = date(2026, 10, 9, 10, 0)
        // 关开关的动作发生在到点回调内（`onGenerated` 里关）⇒ 到点后**不再重排**。
        var model: GenerationTriggerModel!
        model = GenerationTriggerModel(
            scanRoot: scanRoot,
            defaults: defaults,
            executing: StubExecuting(.exited(code: 0)),
            scheduler: scheduler,
            now: { clock },
            onGenerated: { model.setEnabled(false) }
        )

        model.setCycle(.daily)
        model.setEnabled(true)
        let first = try XCTUnwrap(model.nextFireDate)

        clock = first
        scheduler.fire()

        XCTAssertEqual(scheduler.scheduledDates.count, 1, "到点回调内已关开关 ⇒ **不再**重排")
        XCTAssertNil(model.nextFireDate, "关开关 ⇒ 到点清零")
    }

    // MARK: - 另加：下到点纯函数（可复算）

    func testNextFireIsDeterministicForCycleAndTimeOfDay() {
        let now = date(2026, 10, 9, 10, 0) // 周五

        // 每天 08:30 ⇒ 明天（今天这一时刻已过）。
        XCTAssertEqual(
            GenerationTimer.nextFire(cycle: .daily, timeOfDay: "08:30", now: now, calendar: calendar),
            date(2026, 10, 10, 8, 30)
        )
        // 每周 08:30 ⇒ 下一个周一。
        XCTAssertEqual(
            GenerationTimer.nextFire(cycle: .weekly, timeOfDay: "08:30", now: now, calendar: calendar),
            date(2026, 10, 12, 8, 30)
        )
    }
}
