import XCTest
@testable import DoyahCore

/// 省 token 的调用门控（`FR-AI-28`）。判据逐条对条文里那五个机械验收要点：
/// ① 无变化 ⇒ 挡下且理由可读；② 纯函数（同输入同结果、不读时钟/网络）；③ 有变化 ⇒ 放行；
/// ④ 每次挡下都留痕可导出；⑤ 门控**不参与**"能不能执行"的判定。
final class AgentInvocationGateTests: XCTestCase {

    private func trigger(_ digest: String, at: TimeInterval = 0, source: String = "chat") -> AgentGateTrigger {
        AgentGateTrigger(source: source, digest: digest, at: Date(timeIntervalSince1970: at))
    }

    /// ① 同样的问法第二次 ⇒ **挡下**，且理由读得懂（带上一次问的时间）。
    func testSameDigestIsSkippedWithReadableReason() {
        var gate = AgentInvocationGate()
        let first = trigger("same", at: 1_700_000_000)
        XCTAssertFalse(gate.decide(first).isSkipped, "第一次一定放行（还没有可比的东西）")
        gate.record(.proceed, for: first)

        let second = trigger("same", at: 1_700_000_060)
        let decision = gate.decide(second)
        guard case .skipped(let reason) = decision else { return XCTFail("同样的问法应当被挡下") }
        XCTAssertTrue(reason.contains("chat"), "理由要说明是哪个来源被挡")
        XCTAssertTrue(reason.contains("上次"), "理由要说明是「上次」问过")
        XCTAssertTrue(reason.contains("省 token") || reason.contains("重复"), "理由要说清为什么挡")
    }

    /// ③ 内容变了（digest 不同）⇒ 照常放行。
    func testChangedDigestProceeds() {
        var gate = AgentInvocationGate()
        let a = trigger("A"); gate.record(gate.decide(a), for: a)
        XCTAssertFalse(gate.decide(trigger("B")).isSkipped, "换了问法就该照常问")
    }

    /// ③ 换**来源**不算同一个问法（定时触发的"同样内容"与手敲的不是一回事）。
    func testDifferentSourceIsIndependent() {
        var gate = AgentInvocationGate()
        let chat = trigger("same", source: "chat")
        gate.record(gate.decide(chat), for: chat)
        XCTAssertFalse(gate.decide(trigger("same", source: "scheduled")).isSkipped, "按来源各自记，互不牵连")
    }

    /// ② 纯函数：同输入两次调用，结果**逐字一致**（不读时钟、不读网络 ⇒ 中间没有别的东西能改变它）。
    func testDecideIsPure() {
        var gate = AgentInvocationGate()
        let t = trigger("same", at: 100); gate.record(.proceed, for: t)
        let probe = trigger("same", at: 200)
        let one = gate.decide(probe)
        let two = gate.decide(probe)
        XCTAssertEqual(one, two, "同输入两次必须逐字一致 —— 否则它不是纯函数")
        XCTAssertFalse(gate.decide(trigger("same", at: 200), ignoringHistory: true).isSkipped,
                       "用户显式「仍然发送」⇒ 绕过重复那一档")
    }

    /// ④ 被挡下的每一次都留痕，且**可导出**（一行一条，字段齐全）。
    func testSkipsAreRecordedAndExportable() {
        var gate = AgentInvocationGate()
        let t = trigger("same", at: 1_700_000_000)
        gate.record(.proceed, for: t)
        let d = gate.decide(trigger("same", at: 1_700_000_500))
        gate.record(d, for: trigger("same", at: 1_700_000_500))

        XCTAssertEqual(gate.skips.count, 1)
        XCTAssertEqual(gate.skips.first?.source, "chat")
        XCTAssertEqual(gate.skips.first?.digest, "same")
        let exported = gate.exportText
        XCTAssertTrue(exported.contains("\"at\""), "导出要带时间")
        XCTAssertTrue(exported.contains("\"source\""), "导出要带来源")
        XCTAssertTrue(exported.contains("\"reason\""), "导出要带理由")
        XCTAssertEqual(exported.split(separator: "\n").count, 1, "一行一条")
    }

    // MARK: - 形状判据（纯逻辑这件事要能被机械复核）

    /// ② 门控自己**不读时钟**：Core 那份里不许出现 `Date()`（时刻一律由调用方经 `trigger.at` 传进来）。
    /// ⑤ 门控**不碰**执行侧：不许引用 `AgentGuardrail` / 审批队列 —— 它只回答"要不要问模型"。
    func testGateIsPureAndDoesNotTouchExecution() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Core/AgentInvocationGate.swift")
        // **先剥注释再扫**：形状判据要管的是**代码**，不是注释（注释里提到某个类型是正常的，
        // 甚至是有用的说明）。这条判据第一版就栽在这里 —— 它在注释里找到了 `AgentGuardrail` 三个字。
        let source = Self.code(byStrippingComments: try String(contentsOf: url, encoding: .utf8))
        XCTAssertFalse(source.contains("Date()"), "门控不许自己取当前时间（那就不是纯函数了）")
        XCTAssertFalse(source.contains("AgentGuardrail"), "门控不参与「能不能执行」的判定")
        XCTAssertFalse(source.contains("URLSession"), "门控不读网络")
        XCTAssertTrue(source.contains("ISO8601DateFormatter"), "时间只用来**格式化传进来的值**，不是取当前时间")
    }

    /// 把注释剥掉（整行 `///` / 行尾 `//` / 块注释）—— 只留代码。
    private static func code(byStrippingComments text: String) -> String {
        var out: [String] = []
        var inBlock = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var s = String(line)
            if inBlock {
                guard let end = s.range(of: "*/") else { continue }
                s = String(s[end.upperBound...]); inBlock = false
            }
            if let start = s.range(of: "/*") {
                if let end = s.range(of: "*/", range: start.upperBound..<s.endIndex) {
                    s.removeSubrange(start.lowerBound..<end.upperBound)
                } else {
                    s = String(s[..<start.lowerBound]); inBlock = true
                }
            }
            if let r = s.range(of: "//") { s = String(s[..<r.lowerBound]) }
            out.append(s)
        }
        return out.joined(separator: "\n")
    }

    /// 接线判据：门控必须在**问模型之前**真的被问到（Core 有了、界面不接 = 白做）。
    func testChatModelConsultsGateBeforeRequest() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/AgentChatModel.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("var gate = AgentInvocationGate()"), "模型要持有门控")
        XCTAssertTrue(source.contains("gate.decide(trigger)"), "要真的问一次")
        XCTAssertTrue(source.contains("gate.record("), "判定结果要记账（放行更新、挡下留痕）")
        XCTAssertTrue(source.contains("prepared.context.systemPrompt"), "指纹要覆盖整段提示词（含本次上下文）")
        // 顺序：门控在 `loop.run` 之前 —— 挡下才可能"一次请求都不发"。
        let gateIndex = source.range(of: "gate.decide(trigger)")?.lowerBound
        let runIndex = source.range(of: "prepared.loop.run(")?.lowerBound
        XCTAssertNotNil(gateIndex); XCTAssertNotNil(runIndex)
        if let g = gateIndex, let r = runIndex { XCTAssertLessThan(g, r, "门控必须在发起请求之前") }
    }
}
