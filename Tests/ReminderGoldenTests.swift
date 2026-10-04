import Foundation
import XCTest

import DoyahCore

/// 跨端提醒调度语义对账（`FR-NOTE-02` / 契约 §2.10 §3.12 / §6 `I9`）——
/// **本侧（macOS）实现 vs 鸿蒙侧已交付实现**。
///
/// 真值来源不是本文件、也不是本侧实现：`Tests/Fixtures/reminder-golden-v1.json` 由
/// `DoyahNotes/tools/fixtures/gen-reminder-golden.mjs` 从 `entry/src/main/ets/common/Reminder.ets`
/// （已交付的参考实现）跑出来，**39 例**。本用例逐例断言本侧结果与它**逐字段相同** ——
/// 「三端算出同一个『下一次』」这条不变量在这条能力上的机械证据。
///
/// **样例是 vendored 的**（原样收进本仓、只读不写）：源文件
/// `DoyahNotes/tools/fixtures/reminder-golden-v1.json`，本仓副本的 sha256 = `6b52cf46…`（与源逐字节相同，
/// 2026-10-04 第 188 轮收进）。**要改口径**：先在 `DoyahNotes` 侧重跑生成器、再同步这一份，
/// 不许就地改数（改了就是「拿自己改的答案考自己」）。
///
/// 跨端比较面只有**日历日 + 当日分钟 + 档位**（契约 §5 第 5 条）：`toEpoch` 依赖本机时区、
/// **不进**黄金样例，那一半在 `Tests/ReminderTests.swift` 里用**显式偏移**单独验。
///
/// 只读盘、不写盘；找不到黄金样例即判失败（**空跑不许通过**：查了个空不等于查过且一致）。
final class ReminderGoldenTests: XCTestCase {

    private static let goldenRelativePath = "Tests/Fixtures/reminder-golden-v1.json"

    /// 从本文件位置逐级向上找样例（不依赖 `cwd` —— 直接跑 / 经 `verify-core.sh` 跑都成立）。
    private func goldenURL() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent(Self.goldenRelativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory = directory.deletingLastPathComponent()
        }
        XCTFail("找不到黄金样例 \(Self.goldenRelativePath)（从 \(#filePath) 逐级向上找过）")
        throw XCTSkip("样例不在盘上 — 已在上一行报失败")
    }

    private func loadCases() throws -> [[String: Any]] {
        let data = try Data(contentsOf: try goldenURL())
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let cases = root["cases"] as? [[String: Any]] ?? []
        XCTAssertEqual(root["caseCount"] as? Int, cases.count,
                       "样例自称的例数与实际条数不一致（样例本身被改坏了）")
        // 空跑不许通过。
        XCTAssertFalse(cases.isEmpty, "黄金样例里一条用例都没有")
        return cases
    }

    private func spec(from raw: [String: Any]) -> ReminderSpec {
        ReminderSpec(
            rule: raw["rule"] as? String ?? "",
            anchorDate: raw["anchorDate"] as? String ?? "",
            minuteOfDay: raw["minuteOfDay"] as? Int ?? -1,
            intervalCount: raw["intervalCount"] as? Int ?? 0,
            intervalUnit: raw["intervalUnit"] as? String ?? "",
            weekdays: raw["weekdays"] as? [Int] ?? [],
            untilDate: raw["untilDate"] as? String ?? ""
        )
    }

    private func moments(from raw: Any?) -> [(String, Int)] {
        let rows = raw as? [[String: Any]] ?? []
        return rows.map { ($0["date"] as? String ?? "", $0["minute"] as? Int ?? -1) }
    }

    func testGoldenCasesMatchFixtureExactly() throws {
        let cases = try loadCases()
        XCTAssertEqual(cases.count, 39, "黄金样例的例数变了 —— 同步前先看生成器改了没有")
        for (index, item) in cases.enumerated() {
            let name = item["name"] as? String ?? "第 \(index + 1) 例"
            let fromDate = item["from"] as? String ?? ""
            let fromMinute = item["fromMinute"] as? Int ?? -1
            let count = item["count"] as? Int ?? 0
            let spec = spec(from: item["spec"] as? [String: Any] ?? [:])

            let plan = ReminderSchedule.next(spec: spec, fromDate: fromDate, fromMinute: fromMinute)
            XCTAssertEqual(plan.ok, item["ok"] as? Bool ?? false, "\(name)｜ok 不一致")
            XCTAssertEqual(plan.state.rawValue, item["state"] as? String ?? "", "\(name)｜档位不一致")
            XCTAssertEqual(plan.code, item["code"] as? String ?? "", "\(name)｜错误码不一致")
            XCTAssertEqual(plan.due.date, item["dueDate"] as? String ?? "", "\(name)｜due.date 不一致")
            XCTAssertEqual(plan.due.minute, item["dueMinute"] as? Int ?? -1, "\(name)｜due.minute 不一致")

            let upcoming = ReminderSchedule.upcoming(
                spec: spec, fromDate: fromDate, fromMinute: fromMinute, count: count
            ).map { ($0.date, $0.minute) }
            let expected = moments(from: item["upcoming"])
            XCTAssertEqual(upcoming.count, expected.count, "\(name)｜upcoming 条数不一致")
            for (lhs, rhs) in zip(upcoming, expected) {
                XCTAssertEqual(lhs.0, rhs.0, "\(name)｜upcoming 的日期不一致")
                XCTAssertEqual(lhs.1, rhs.1, "\(name)｜upcoming 的分钟不一致")
            }
        }
    }
}
