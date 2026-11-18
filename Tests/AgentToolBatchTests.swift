import XCTest
@testable import DoyahCore

/// **工具并行与保序**（`FR-AGT-CORE-LOOP-012` / 概设 §18.1 第 13 条）。
///
/// 四条判据逐条落成用例：
/// ① 三个只读调用并发执行，墙钟明显短于串行；
/// ② 写类调用不并行（分段计划把写类切在批外）；
/// ③ 并行结果回灌顺序 = 调用顺序（哪怕完成先后相反）；
/// ④ 同批共用一个批号、批间不同。
final class AgentToolBatchTests: XCTestCase {

    // MARK: 计数器（并发度的唯一读数来源）

    private actor ConcurrencyProbe {
        private var inFlight = 0
        private(set) var peak = 0
        private(set) var finishedOrder: [Int] = []

        func enter(_ index: Int) {
            inFlight += 1
            peak = max(peak, inFlight)
        }

        func leave(_ index: Int) {
            inFlight -= 1
            finishedOrder.append(index)
        }
    }

    private func invocation(_ name: String, _ args: String = "{}") -> AgentToolInvocation {
        AgentToolInvocation(name: name, argumentsJSON: args)
    }

    // MARK: ② 分段计划

    func testPlannerKeepsWritesOutOfTheBatch() {
        let calls = [invocation("read_file"), invocation("read_file"), invocation("write_file"), invocation("read_file")]
        let readOnly: Set<String> = ["read_file"]
        let prefix = AgentToolBatchPlanner.parallelPrefix(calls) { readOnly.contains($0.name) }

        XCTAssertEqual(prefix.map(\.name), ["read_file", "read_file"],
                       "前缀只能是**连续**的只读段：写类必须把它切开，否则后一段读会越过写看到写之后的世界")
        // 队首是写类 ⇒ 切不出批（不足 2 条），交回串行路径
        let writeFirst = AgentToolBatchPlanner.parallelPrefix([invocation("write_file"), invocation("read_file")]) {
            readOnly.contains($0.name)
        }
        XCTAssertTrue(writeFirst.isEmpty)
    }

    // MARK: ③ 保序

    func testResultsComeBackInCallOrderEvenWhenTheyFinishReversed() async {
        let calls = (0..<3).map { invocation("read_file", "{\"path\":\"f\($0).txt\"}") }
        // 完成顺序刻意反向：第 0 条最慢、第 2 条最快
        let delays: [UInt64] = [90_000_000, 45_000_000, 5_000_000]
        let results = await AgentToolBatchRunner.run(calls) { inv in
            let index = Int(inv.argumentsJSON.split(separator: "f").last?.first?.wholeNumberValue ?? 0)
            try? await Task.sleep(nanoseconds: delays[index])
            return .file(AgentToolFileOutput(path: "f\(index).txt", text: "\(index)",
                                             truncated: false, totalBytes: 1))
        }

        XCTAssertEqual(results.map(\.index), [0, 1, 2], "回灌顺序必须是调用顺序，不是完成顺序")
        let texts = results.map { result -> String in
            if case .file(let output) = result.outcome { return output.text }
            return "?"
        }
        XCTAssertEqual(texts, ["0", "1", "2"], "第 i 个结果必须属于第 i 条调用（错位就是把 A 的文件内容记在 B 名下）")
    }

    // MARK: ① 并发

    func testThreeReadOnlyCallsReallyRunConcurrently() async {
        let calls = (0..<3).map { invocation("read_file", "{\"path\":\"g\($0).txt\"}") }
        let probe = ConcurrencyProbe()
        let started = Date()
        _ = await AgentToolBatchRunner.run(calls) { inv in
            let index = Int(inv.argumentsJSON.split(separator: "g").last?.first?.wholeNumberValue ?? 0)
            await probe.enter(index)
            try? await Task.sleep(nanoseconds: 120_000_000)   // 每条 120ms；串行会 ≥360ms
            await probe.leave(index)
            return .file(AgentToolFileOutput(path: "g\(index).txt", text: "\(index)",
                                             truncated: false, totalBytes: 1))
        }
        let elapsed = Date().timeIntervalSince(started)
        let peak = await probe.peak

        XCTAssertEqual(peak, 3, "三条只读必须同时在飞（峰值并发 3）——峰值 1 就是串行")
        XCTAssertLessThan(elapsed, 0.30, "墙钟必须明显短于串行的 360ms（实测 \(Int(elapsed * 1000))ms）")
    }

    func testWriteCallsAreNotParallel() async {
        // 写类不进批：调用方给 isParallelizable 返回 false ⇒ 规划器切不出批 ⇒ 走串行
        let calls = [invocation("write_file"), invocation("write_file"), invocation("write_file")]
        let prefix = AgentToolBatchPlanner.parallelPrefix(calls) { _ in false }
        XCTAssertTrue(prefix.isEmpty, "写类调用一条都不许进并发批")
    }

    // MARK: ④ 批号

    func testBatchIDIsSharedInsideABatchAndDiffersAcrossBatches() {
        let first = AgentToolBatchID.make()
        let second = AgentToolBatchID.make()
        XCTAssertNotEqual(first, second, "批间必须不同，否则还原不出「批内并发、批间串行」")
        XCTAssertEqual(AgentToolBatchID.token(batch: first, index: 2, count: 3), "batch:\(first)#2/3")
        XCTAssertFalse(AgentToolBatchID.token(batch: first, index: 1, count: 1).isEmpty)
    }
}
