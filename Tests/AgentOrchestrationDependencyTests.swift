import XCTest
@testable import DoyahCore

/// **编排层 · 依赖判据**（`FR-AGT-TOOL-SYS-002` · 详设 §3.20「有依赖却并发提交」）。
///
/// 覆盖范围：只判「带依赖的路不许并发跑、且如实说出来」这一格。
/// 不判：依赖拓扑排序（本层明确不做，由调用方排序）、也不判并行跑得快不快。
final class AgentOrchestrationDependencyTests: XCTestCase {

    private final class RecordingRunner: AgentSubtaskRunner, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var ran: [String] = []
        func run(_ spec: AgentSubtaskSpec, budgetSeconds: TimeInterval) async -> AgentSubtaskResult {
            lock.lock(); ran.append(spec.id); lock.unlock()
            return AgentSubtaskResult(subtaskID: spec.id, label: spec.label, status: .completed,
                                      summary: "done-\(spec.id)", artifacts: [],
                                      approvalFingerprint: nil)
        }
        var ranIDs: [String] { lock.lock(); defer { lock.unlock() }; return ran }
    }

    /// 带依赖的那一路**一次都不许跑**，其余照跑，且汇总里点明依赖谁。
    func testDependentSubtaskIsNotRunConcurrentlyAndSaysWhy() async {
        let runner = RecordingRunner()
        let executor = AgentSubagentExecutor(
            policy: AgentSubagentPolicy(maxConcurrent: 3),
            runner: runner)
        let specs = [
            AgentSubtaskSpec(id: "a", label: "读配置", prompt: "p"),
            AgentSubtaskSpec(id: "b", label: "改配置", prompt: "p", dependsOn: ["a"]),
        ]
        let report = await executor.run(specs)

        XCTAssertEqual(runner.ranIDs, ["a"], "带依赖的 b 不许被并发派出去")
        XCTAssertEqual(report.results.map(\.subtaskID), ["a", "b"], "报告仍按输入顺序")
        let b = report.results.first { $0.subtaskID == "b" }
        XCTAssertEqual(b?.status, .skipped)
        XCTAssertEqual(b?.summary, "depends-on:a", "要说清它依赖谁，不能只写「跳过」")
    }

    /// 无依赖的批照旧全部跑完（别为了防依赖把正常路径也掐了）。
    func testIndependentBatchStillRunsAll() async {
        let runner = RecordingRunner()
        let executor = AgentSubagentExecutor(policy: AgentSubagentPolicy(maxConcurrent: 3), runner: runner)
        let report = await executor.run([
            AgentSubtaskSpec(id: "x", label: "X", prompt: "p"),
            AgentSubtaskSpec(id: "y", label: "Y", prompt: "p"),
        ])
        XCTAssertEqual(Set(runner.ranIDs), ["x", "y"])
        XCTAssertEqual(report.completedCount, 2)
    }

    /// 解析层认得 `dependsOn` / `depends_on` 两种写法（模型两种都会写）。
    func testParseAcceptsBothDependencySpellings() throws {
        let json = """
        {"tasks": "[{\\"id\\":\\"a\\",\\"prompt\\":\\"p1\\"},{\\"id\\":\\"b\\",\\"prompt\\":\\"p2\\",\\"depends_on\\":[\\"a\\"]},{\\"id\\":\\"c\\",\\"prompt\\":\\"p3\\",\\"dependsOn\\":[\\"a\\"]}]"}
        """
        let specs = try AgentSubtaskSpecList.parse(argumentsJSON: json).get()
        XCTAssertEqual(specs.map(\.id), ["a", "b", "c"])
        XCTAssertTrue(specs[0].dependsOn.isEmpty)
        XCTAssertEqual(specs[1].dependsOn, ["a"], "蛇形写法要认")
        XCTAssertEqual(specs[2].dependsOn, ["a"], "驼峰写法也要认")
    }
}
