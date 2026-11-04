import XCTest
@testable import DoyahRetroCore

// `FR-R-13-10` 触发面**核心层**的机械证据（Retro macOS · Alpha 4 首片 A · 任务卡 `t_7bc2842f`）。
//
// 契约出处 = `Docs/需求规范书.md` §3.13 `FR-R-13-10`（SRS v1.15 · 人类主人 2026-10-09 拍板 C）④
// 「触发失败 ⇒ 记一行「缺期」+ 界面明确提示（**不静默、不补历史**）」；`IR-06` 不变量 6 同口径。
//
// 三条纪律：
//   ① **注入桩**：本族**一律注入** `StubExecuting`，**从不真跑生成侧**（判据 1 的「注入桩未被真实调用」）——
//      也正因为如此，本族跑在 CI / 无生成侧的机器上照样可复现；
//   ② 跑**真目录真文件**（临时目录）：扫描 / 记账吃的是盘上的字节，纯内存测不出现场；
//   ③ 断言**确定结果值**（三态 + 缺期行的三字段），不断言「没崩就算过」。
//
// 六条点名判据：**成功**（不记账）· **失败记缺期** · **跳过不记**（且不跑执行器）·
// **期号正确** · **追加不覆盖** · **注入桩未被真实调用**。另加两条：落点 = 扫描根**同级**文件 ·
// 时刻 = **ISO 8601 带时区**。
final class GenerationTriggerTests: XCTestCase {

    /// 临时根（**每例一个** ⇒ 缺期落点 `base/missed-periods.jsonl` 不跨例串味）。
    private var base: URL!
    /// 扫描根 = `base/packages`（其直接子目录即各期包；缺期落点 = 其**同级** `base/missed-periods.jsonl`）。
    private var scanRoot: URL!

    /// 缺期落点（**唯一**）= 扫描根同级文件。
    private var logURL: URL { GenerationSpec.missedPeriodLogURL(nextToScanRoot: scanRoot) }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-retro-trigger-\(UUID().uuidString)", isDirectory: true)
        scanRoot = base.appendingPathComponent("packages", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let base { try? FileManager.default.removeItem(at: base) }
    }

    // MARK: - 注入桩（**从不真跑生成侧**）

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

    // MARK: - 夹具

    /// 造一份**成包**的期目录（`index.json` + `report.md`，`IR-05` 不变量 2）。
    @discardableResult
    private func makePackage(_ name: String) throws -> URL {
        let directory = scanRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let index = "{ \"id\": \"\(name)\", \"title\": \"国际趋势分析周报\", "
            + "\"published\": \"2026-10-06\", \"summary\": \"摘要\", \"media_count\": 0 }"
        try Data(index.utf8).write(to: directory.appendingPathComponent("index.json"))
        try Data("# 本期周报\n\n正文。\n".utf8).write(to: directory.appendingPathComponent("report.md"))
        return directory
    }

    /// 盘上缺期日志的**逐行**（文件不在 ⇒ 空数组）。
    private func logLines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        let text = try String(contentsOf: logURL, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .dropLast()
            .map(String.init)
    }

    /// 一行 JSONL ⇒ 字段字典（键名 = 期号 / 结果 / 时刻）。
    private func fields(of line: String) throws -> [String: String] {
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            "缺期行应是 JSON 对象：\(line)"
        )
        return object.compactMapValues { $0 as? String }
    }

    // MARK: - 判据 ①：成功 ⇒ 不记账

    func testSuccessfulGenerationRecordsNoMissedPeriod() throws {
        let stub = StubExecuting(.exited(code: 0))

        let outcome = GenerationTrigger.trigger(period: "2026-W40", scanRoot: scanRoot, executing: stub)

        XCTAssertEqual(outcome, .success(period: "2026-W40"))
        XCTAssertEqual(outcome.label, "成功")
        XCTAssertEqual(stub.callCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path),
                       "成功不该产生缺期记录（落点文件都不该被建出来）")
        XCTAssertEqual(try logLines(), [])
    }

    // MARK: - 判据 ②③：失败 ⇒ 记一行缺期，且**期号正确**

    func testFailedGenerationAppendsOneMissedPeriodLineWithCorrectPeriod() throws {
        let stub = StubExecuting(.exited(code: 3))

        let outcome = GenerationTrigger.trigger(period: "2026-W52", scanRoot: scanRoot, executing: stub)

        guard case .failure(let period, let reason) = outcome else {
            return XCTFail("退出码非零应判失败，实际 \(outcome)")
        }
        XCTAssertEqual(period, "2026-W52")
        XCTAssertTrue(reason.contains("3"), "失败原因应点出退出码，实际 \(reason)")

        let lines = try logLines()
        XCTAssertEqual(lines.count, 1, "失败应**恰好**追一行缺期")

        let fields = try self.fields(of: lines[0])
        XCTAssertEqual(fields["期号"], "2026-W52", "缺期行的期号应与本次触发一致")
        XCTAssertEqual(fields["结果"], "失败")
        let timestamp = try XCTUnwrap(fields["时刻"])
        let iso = try NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$"#)
        let range = NSRange(timestamp.startIndex..<timestamp.endIndex, in: timestamp)
        XCTAssertNotNil(iso.firstMatch(in: timestamp, range: range),
                        "时刻应是 ISO 8601 带时区，实际 \(timestamp)")
    }

    // MARK: - 判据 ④：本期已存在 ⇒ 跳过（**不跑执行器、不记账**）

    func testSkippedWhenPeriodAlreadyExistsNeitherRunsNorRecords() throws {
        try makePackage("2026-W40")
        let stub = StubExecuting(.exited(code: 0))

        let outcome = GenerationTrigger.trigger(period: "2026-W40", scanRoot: scanRoot, executing: stub)

        XCTAssertEqual(outcome, .skipped(period: "2026-W40"))
        XCTAssertEqual(outcome.label, "跳过")
        XCTAssertEqual(stub.callCount, 0, "本期已存在 ⇒ **不重复触发**，执行器一次都不该被调")
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path), "跳过不该产生缺期记录")
        XCTAssertEqual(try logLines(), [])
    }

    // MARK: - 判据 ⑤：追加不覆盖（已有的行原样保留）

    func testAppendDoesNotOverwriteExistingLines() throws {
        let seeded = "{\"期号\":\"2026-W39\",\"结果\":\"失败\",\"时刻\":\"2026-09-28T08:30:00+08:00\"}\n"
        try Data(seeded.utf8).write(to: logURL)

        let stub = StubExecuting(.exited(code: 2))
        _ = GenerationTrigger.trigger(period: "2026-W40", scanRoot: scanRoot, executing: stub)

        let lines = try logLines()
        XCTAssertEqual(lines.count, 2, "追加 ⇒ 旧行保留 + 新行在末尾")
        XCTAssertEqual(lines[0] + "\n", seeded, "已有的那一行必须逐字节不变")
        XCTAssertEqual(try fields(of: lines[1])["期号"], "2026-W40")
    }

    // MARK: - 判据 ⑥：注入桩未被真实调用（真生成侧从不被起）

    func testInjectedStubIsUsedAndRealGeneratorNeverLaunched() throws {
        // 桩回一个「真生成侧不会这么退」的码：能出现 ⇒ 证明走的是**注入桩**，不是真起子进程。
        let stub = StubExecuting(.exited(code: 7))

        let outcome = GenerationTrigger.trigger(period: "2026-W40", scanRoot: scanRoot, executing: stub)

        guard case .failure(_, let reason) = outcome else {
            return XCTFail("应判失败，实际 \(outcome)")
        }
        XCTAssertTrue(reason.contains("7"), "失败原因应来自**注入桩**的读数，实际 \(reason)")
        XCTAssertEqual(stub.callCount, 1, "注入桩应被调用**恰好一次**（真生成侧一次都没被起）")
        XCTAssertEqual(try logLines().count, 1)
    }

    // MARK: - 另两条：起不来 / 超时也算失败并记账

    func testLaunchFailedAndTimedOutBothRecordMissedPeriod() throws {
        _ = GenerationTrigger.trigger(
            period: "2026-W40",
            scanRoot: scanRoot,
            executing: StubExecuting(.launchFailed(reason: "找不到可执行文件"))
        )
        _ = GenerationTrigger.trigger(
            period: "2026-W41",
            scanRoot: scanRoot,
            executing: StubExecuting(.timedOut(seconds: 900))
        )

        let lines = try logLines()
        XCTAssertEqual(lines.count, 2, "起不来 + 超时 ⇒ 各追一行")
        XCTAssertEqual(try fields(of: lines[0])["期号"], "2026-W40")
        XCTAssertEqual(try fields(of: lines[1])["期号"], "2026-W41")
        XCTAssertTrue(try fields(of: lines[0])["结果"] == "失败")
    }

    // MARK: - 另两条：落点（扫描根同级）· 时刻（ISO 8601 带时区）

    func testMissedPeriodLogIsTheSiblingFileOfTheScanRoot() {
        // 本机固定扫描根 ⇒ 落点 = 其**同级**文件（`FR-R-13-10` 的口径）。
        let fixedScanRoot = URL(fileURLWithPath: "/Users/alex/.dsh/notes/geopolitics-weekly/packages",
                                isDirectory: true)
        XCTAssertEqual(
            GenerationSpec.missedPeriodLogURL(nextToScanRoot: fixedScanRoot).path,
            "/Users/alex/.dsh/notes/geopolitics-weekly/missed-periods.jsonl"
        )
        XCTAssertEqual(GenerationSpec.missedPeriodFileName, "missed-periods.jsonl")

        // 入口字符串的**唯一出处**（真生成侧从不被本族起，这里只校形状）。
        XCTAssertEqual(GenerationSpec.executableName, "dsh")
        XCTAssertFalse(GenerationSpec.generationTask.isEmpty)
    }

    func testTimestampIsISO8601WithTimeZone() {
        let date = Date(timeIntervalSince1970: 1_791_077_100)
        let text = GenerationTimestamp.iso8601(date, timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
        XCTAssertEqual(text, "2026-10-04T09:25:00+08:00", "时刻应是带时区偏移的 ISO 8601")
    }
}
