import XCTest
@testable import DoyahCore

/// **单轮成本实测探针**（人类主人 2026-11-04：「执行的过程太长了，每次都要很多步不能快速出结果」）。
///
/// 这不是判据，是**量尺**：同一份任务在改动前后各跑一次，量出
/// 「模型请求数 / 提示词 token / 每跳提示词 / 工具调用数 / 耗时」。
///
/// 两把尺：
/// · `testHeavyTurnCost`（确定性）：脚本化假模型 + **真分发器 / 真工作区工具 / 真文件**。
///   轨迹固定 ⇒ 两次跑的差异只可能来自「循环怎么拼提示词」。默认跳过。
/// · `testRealModelTurnCost`（真机）：真端点 + 真循环。量的是模型真实行为（会不会少走弯路、答得对不对）。
///   默认跳过，要显式设环境变量。
///
/// 跑法：
/// ```
/// AGENT_PROBE_OUT=/tmp/probe.json swift test --filter AgentTurnCostProbeTests/testHeavyTurnCost
/// AGENT_PROBE_OUT=/tmp/real.json swift test --filter AgentTurnCostProbeTests/testRealModelTurnCost
/// ```
final class AgentTurnCostProbeTests: XCTestCase {

    // MARK: - 记录装饰器（两把尺共用的读数口）

    /// 包一层：记下每次请求（提示词全文 + 工具声明字数）与端点报的用量。
    private final class RecordingClient: LLMStreamingClient, @unchecked Sendable {
        let inner: any LLMStreamingClient
        private let lock = NSLock()
        private var captured: [(request: LLMRequest, toolsCharacters: Int)] = []
        private var promptTokens = 0

        init(inner: any LLMStreamingClient) { self.inner = inner }

        var requests: [(request: LLMRequest, toolsCharacters: Int)] {
            lock.lock(); defer { lock.unlock() }
            return captured
        }

        var reportedPromptTokens: Int {
            lock.lock(); defer { lock.unlock() }
            return promptTokens
        }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            let toolsCharacters = (request.tools ?? []).reduce(0) { partial, tool in
                partial + tool.name.count + tool.description.count + tool.parametersJSON.count
            }
            lock.lock()
            captured.append((request, toolsCharacters))
            lock.unlock()

            let upstream = try await inner.stream(request)
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        for try await event in upstream {
                            if case .usage(let usage, _) = event, let prompt = usage.promptTokens {
                                self.lock.lock()
                                self.promptTokens += prompt
                                self.lock.unlock()
                            }
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    /// 按跳脚本吐 `tool_calls`；脚本用尽就收盘（= 模型给了最终答复）。
    private final class ReplayClient: LLMStreamingClient, @unchecked Sendable {
        private let toolHops: [[AgentToolInvocation]]
        private let answer: String
        private let lock = NSLock()
        private var served = 0

        init(toolHops: [[AgentToolInvocation]], answer: String) {
            self.toolHops = toolHops
            self.answer = answer
        }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock()
            let index = served
            served += 1
            lock.unlock()

            let events: [LLMStreamEvent]
            if index < toolHops.count {
                var batch: [LLMStreamEvent] = []
                for (slot, invocation) in toolHops[index].enumerated() {
                    batch.append(.toolCallDelta(index: slot, id: "call-\(index)-\(slot)",
                                                name: invocation.name,
                                                argumentsFragment: invocation.argumentsJSON))
                }
                batch.append(.finished(reason: "tool_calls"))
                batch.append(.done)
                events = batch
            } else {
                events = [.textDelta(answer), .finished(reason: "stop"), .done]
            }
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    // MARK: - 工作区（真文件的临时副本：读得动、不碰活仓）

    private var workspaceRoot: URL!

    override func setUpWithError() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let core = repo.appendingPathComponent("Core")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        // **按大小降序**取真文件：先撞大文件，才量得出「整篇进上下文」的代价。
        func size(_ name: String) -> Int {
            let attributes = try? FileManager.default.attributesOfItem(atPath: core.appendingPathComponent(name).path)
            return (attributes?[.size] as? NSNumber)?.intValue ?? 0
        }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: core.path)) ?? [])
            .filter { $0.hasSuffix(".swift") }
            .sorted { size($0) > size($1) }
        for name in names {
            try? FileManager.default.copyItem(at: core.appendingPathComponent(name),
                                              to: destination.appendingPathComponent(name))
        }
        workspaceRoot = destination
    }

    override func tearDownWithError() throws {
        if let workspaceRoot { try? FileManager.default.removeItem(at: workspaceRoot) }
    }

    // MARK: - 轨迹：94 跳 / 每跳 2 读 + 每 5 跳 1 搜 ≈ 207 次工具调用

    /// 每一条 (工具, 参数) 都不重复 —— 「重复调用闸」（`AgentRepeatGuard`）不会把它挡掉，
    /// 量到的就是纯粹的「提示词怎么长起来的」。
    private func heavyTrace() -> [[AgentToolInvocation]] {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: workspaceRoot.path)) ?? [])
            .filter { $0.hasSuffix(".swift") }.sorted()
        guard !files.isEmpty else { return [] }
        var hops: [[AgentToolInvocation]] = []
        for hop in 0..<94 {
            var batch: [AgentToolInvocation] = []
            for slot in 0..<2 {
                let pick = (hop * 2 + slot) % files.count
                batch.append(AgentToolInvocation(name: "read_file",
                                                 argumentsJSON: #"{"path":"\#(files[pick])"}"#))
            }
            if hop % 5 == 0 {
                batch.append(AgentToolInvocation(name: "search",
                                                 argumentsJSON: #"{"query":"zzp\#(hop)","limit":20}"#))
            }
            hops.append(batch)
        }
        return hops
    }

    // MARK: - 读数

    private struct Reading {
        var label: String
        var requests: Int
        var promptCharacters: Int
        var estimatedPromptTokens: Int
        var firstHopCharacters: Int
        var lastHopCharacters: Int
        var peakHopCharacters: Int
        var toolsExecuted: Int
        var toolsRejected: Int
        var loopMillis: Int
        var readPathsRecalled: Int
        var readPathsTotal: Int
        var compressedEntries: Int
        var estimatedTokensSaved: Int
        var reportedPromptTokens: Int
        var answer: String

        var json: String {
            let head = String(answer.prefix(240))
                .replacingOccurrences(of: "\"", with: "'")
                .replacingOccurrences(of: "\n", with: " ")
            return """
            {
              "label": "\(label)",
              "requests": \(requests),
              "promptCharacters": \(promptCharacters),
              "estimatedPromptTokens": \(estimatedPromptTokens),
              "firstHopCharacters": \(firstHopCharacters),
              "lastHopCharacters": \(lastHopCharacters),
              "peakHopCharacters": \(peakHopCharacters),
              "toolsExecuted": \(toolsExecuted),
              "toolsRejected": \(toolsRejected),
              "loopMillis": \(loopMillis),
              "readPathsRecalled": \(readPathsRecalled),
              "readPathsTotal": \(readPathsTotal),
              "compressedEntries": \(compressedEntries),
              "estimatedTokensSaved": \(estimatedTokensSaved),
              "reportedPromptTokens": \(reportedPromptTokens),
              "answerCharacters": \(answer.count),
              "answerHead": "\(head)"
            }
            """
        }
    }

    private func measure(label: String,
                         client: RecordingClient,
                         result: AgentLoopResult,
                         loopMillis: Int,
                         readPaths: [String]) -> Reading {
        let captured = client.requests
        let chars = captured.reduce(0) {
            $0 + $1.request.systemPrompt.count + $1.request.userPrompt.count + $1.toolsCharacters
        }
        let perHop = captured.map {
            $0.request.systemPrompt.count + $0.request.userPrompt.count + $0.toolsCharacters
        }
        let lastPrompt = captured.last.map { $0.request.systemPrompt + "\n" + $0.request.userPrompt } ?? ""
        // 「模型还记不记得自己读过哪些文件」：最终提示词里还认得出几条读过的路径
        // （认领方式是观察段抬头 `file:<路径>:` —— 折叠时这一条**必须留着**，否则模型会重读，那正是慢的根）。
        let recalled = Set(readPaths).filter { lastPrompt.contains("file:\($0):") }.count

        return Reading(label: label,
                       requests: captured.count,
                       promptCharacters: chars,
                       estimatedPromptTokens: AgentContextCompressor.estimatedTokens(characters: chars),
                       firstHopCharacters: perHop.first ?? 0,
                       lastHopCharacters: perHop.last ?? 0,
                       peakHopCharacters: perHop.max() ?? 0,
                       toolsExecuted: result.executedTools.count,
                       toolsRejected: result.rejectedTools.count,
                       loopMillis: loopMillis,
                       readPathsRecalled: recalled,
                       readPathsTotal: Set(readPaths).count,
                       compressedEntries: result.compressedEntries,
                       estimatedTokensSaved: result.estimatedTokensSaved,
                       reportedPromptTokens: client.reportedPromptTokens,
                       answer: result.text)
    }

    private func readPaths(in trace: [[AgentToolInvocation]]) -> [String] {
        trace.flatMap { $0 }.filter { $0.name == "read_file" }.compactMap { invocation in
            guard let data = invocation.argumentsJSON.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return object["path"] as? String
        }
    }

    // MARK: - 尺一：确定性（脚本轨迹 × 真工具）

    func testHeavyTurnCost() async throws {
        guard let outPath = ProcessInfo.processInfo.environment["AGENT_PROBE_OUT"] else {
            throw XCTSkip("量尺默认不跑：设 AGENT_PROBE_OUT=<路径> 才跑")
        }
        let trace = heavyTrace()
        XCTAssertEqual(trace.count, 94)

        let client = RecordingClient(inner: ReplayClient(toolHops: trace, answer: "报告：已按轨迹读完。"))
        let dispatcher = AgentStandardDispatcher(registry: .standard,
                                                 workspace: AgentWorkspaceTools(root: workspaceRoot),
                                                 repeatGuard: AgentRepeatGuard())
        let systemPrompt = AgentSystemPrompt.build(model: "probe", endpoint: "http://127.0.0.1/v1",
                                                  workspacePath: workspaceRoot.path, references: [])
        let loop = AgentLoop(client: client, dispatcher: dispatcher, registry: .standard,
                             compressionBudget: AgentContextCompressionBudget(),
                             limits: AgentLoopLimits(maxSteps: 150))
        let context = AgentLoopContext(
            systemPrompt: systemPrompt,
            userPrompt: "把工作区里智能体循环相关的实现通读一遍，找出 read_file 的截断上限写在哪里，并给出结论。",
            baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1/v1")!,
                                    model: "probe", systemPrompt: "", userPrompt: ""),
            sessionID: "probe-heavy", workspace: workspaceRoot.path)

        let started = Date()
        let result = await loop.run(context: context)
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)

        let reading = measure(label: "heavy-scripted", client: client, result: result,
                              loopMillis: elapsed, readPaths: readPaths(in: trace))
        print("PROBE_READING " + reading.json)
        try reading.json.write(toFile: outPath, atomically: true, encoding: .utf8)

        XCTAssertGreaterThan(reading.requests, 1)
        // 信息地板：折叠之后「我读过哪些文件」**在台账容量之内**一条都不许丢
        // （丢了模型就会重读 —— 那正是慢的根）。超出台账上限的那几条由口径**如实报数**（`beyondLedger`）。
        let policy = AgentObservationDigestPolicy.standard
        let expectedRecall = min(reading.readPathsTotal, policy.maxLedgerLines + policy.keepRecent)
        XCTAssertGreaterThanOrEqual(reading.readPathsRecalled, expectedRecall,
                                    "最终提示词里认得出的已读路径条数不许少于台账容量（\(expectedRecall)）")
    }

    // MARK: - 尺二：真端点（真模型 × 真循环）

    /// 真机跑一次「旧配置」与「新配置」各一遍，比较同一个任务的四样读数。
    ///
    /// 旧配置是**忠实复刻改动前**的那一套：`read_file` 没有 `offset/limit`（schema 里就没有，
    /// 模型给了也会被判 `unknown`）、整篇读（回灌那一层截到 8KB）、不折叠、24k 字符预算。
    private func runArm(label: String,
                        prompt: String,
                        systemPrompt: String,
                        baseRequest: LLMRequest,
                        maxSteps: Int,
                        legacy: Bool) async -> Reading {
        var registry: AgentToolRegistry = .standard
        if legacy {
            let rewritten = registry.definitions.map { definition -> AgentToolDefinition in
                guard definition.capability == .readFile else { return definition }
                var copy = definition
                copy.parameters = ["path": "string"]
                return copy
            }
            registry = AgentToolRegistry(definitions: rewritten)
        }
        let tools = legacy
            ? AgentWorkspaceTools(root: workspaceRoot, registry: registry,
                                  maxReadBytes: 262_144, maxReadLines: 12_000)
            : AgentWorkspaceTools(root: workspaceRoot, registry: registry)
        let client = RecordingClient(inner: OpenAICompatibleStreamingClient())
        let dispatcher = AgentStandardDispatcher(registry: registry, workspace: tools,
                                                 repeatGuard: AgentRepeatGuard())
        let loop = AgentLoop(client: client, dispatcher: dispatcher, registry: registry,
                             compressionBudget: legacy
                                 ? AgentContextCompressionBudget(maxPromptCharacters: 24_000)
                                 : AgentContextCompressionBudget(),
                             observationDigest: legacy ? nil : .standard,
                             limits: AgentLoopLimits(maxSteps: maxSteps))
        let context = AgentLoopContext(systemPrompt: systemPrompt, userPrompt: prompt,
                                       baseRequest: baseRequest,
                                       sessionID: "probe-real-\(label)",
                                       workspace: workspaceRoot.path)
        let started = Date()
        let result = await loop.run(context: context)
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        let reading = measure(label: label, client: client, result: result,
                              loopMillis: elapsed, readPaths: [])
        print("PROBE_OUTCOME \(label) \(result.outcome) · usage=\(result.usage)")
        print("PROBE_REJECTED \(label) " + result.rejectedTools.map { "\($0.name)|\($0.reason)" }
            .joined(separator: " , "))
        return reading
    }

    private func realModelSetup() throws -> (model: String, baseRequest: LLMRequest, maxSteps: Int, outPath: String) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AGENT_PROBE_REAL"] == "1",
              let apiKey = environment["SILICONFLOW_API_KEY"],
              let outPath = environment["AGENT_PROBE_OUT"] else {
            throw XCTSkip("真机尺默认不跑：AGENT_PROBE_REAL=1 + SILICONFLOW_API_KEY + AGENT_PROBE_OUT")
        }
        let model = environment["AGENT_PROBE_MODEL"] ?? "deepseek-ai/DeepSeek-V3"
        var baseRequest = LLMRequest(endpoint: URL(string: "https://api.siliconflow.cn/v1")!,
                                     model: model, apiKey: apiKey, timeoutSeconds: 120,
                                     systemPrompt: "", userPrompt: "")
        baseRequest.maxOutputTokens = 900
        baseRequest.temperature = 0
        // 产品里封条由「配置读回」同步；测试进程没有配置 ⇒ 显式打开（只影响本进程）。
        AgentEgressSeal.shared.setOpen(true)
        return (model, baseRequest, Int(environment["AGENT_PROBE_STEPS"] ?? "") ?? 20, outPath)
    }

    /// **深段取数**：题目落在 570KB 大文件的第 6000 行 —— 旧行为每次只能拿到开头 8KB，
    /// 这一段**根本读不到**；能 `offset` 定位的新行为一两次就取到。
    func testRealModelDeepSpan() async throws {
        let setup = try realModelSetup()
        let span = 6000...6008
        let prompt = """
        这个工作区是一个 Swift 工程 Core 目录的副本。`Localization.swift` 有七千多行。
        请把该文件 **第 \(span.lowerBound) 行到第 \(span.upperBound) 行**逐行抄下来（每行只要前 30 个字符）。
        不要读整篇，直接读那一段。
        最后一行必须是：SPAN=<用 | 分隔的 \(span.count) 段原文>
        """
        let systemPrompt = AgentSystemPrompt.build(model: setup.model,
                                                  endpoint: setup.baseRequest.endpoint.absoluteString,
                                                  workspacePath: workspaceRoot.path, references: [])
        let legacy = await runArm(label: "legacy", prompt: prompt, systemPrompt: systemPrompt,
                                  baseRequest: setup.baseRequest, maxSteps: setup.maxSteps, legacy: true)
        let optimized = await runArm(label: "optimized", prompt: prompt, systemPrompt: systemPrompt,
                                     baseRequest: setup.baseRequest, maxSteps: setup.maxSteps, legacy: false)
        let truth = Self.truthSpan(in: workspaceRoot.appendingPathComponent("Localization.swift"), span: span)
        let report = """
        {
          "task": "deepSpan",
          "model": "\(setup.model)",
          "truth": "\(truth.first ?? "")",
          "legacy": \(legacy.json),
          "optimized": \(optimized.json)
        }
        """
        print("PROBE_REAL " + report)
        try report.write(toFile: setup.outPath, atomically: true, encoding: .utf8)

        let fingerprint = String(truth[0].prefix(18))
        XCTAssertTrue(optimized.answer.contains(fingerprint),
                      "新行为要抄对第 \(span.lowerBound) 行（指纹「\(fingerprint)」）：\(optimized.answer.prefix(160))")
    }

    /// **多段统计**：要把 600 行分几段读完才数得出来（一次只给一屏 ⇒ 必须续读）。
    /// 旧行为每次读都只给开头那 8KB ⇒ 第 200 行以后永远看不到，只能反复重读到步数用光。
    func testRealModelRepeatedReads() async throws {
        let setup = try realModelSetup()
        let span = 1...600
        let prompt = """
        这个工作区是一个 Swift 工程 Core 目录的副本。
        请统计 `Localization.swift` 里**第 1 行到第 \(span.upperBound) 行**中共出现多少次 `simplifiedChinese`。
        需要分段读完这一段再数，答完就停。
        最后一行必须是：COUNT=<数字>
        """
        let systemPrompt = AgentSystemPrompt.build(model: setup.model,
                                                  endpoint: setup.baseRequest.endpoint.absoluteString,
                                                  workspacePath: workspaceRoot.path, references: [])
        let legacy = await runArm(label: "legacy", prompt: prompt, systemPrompt: systemPrompt,
                                  baseRequest: setup.baseRequest, maxSteps: setup.maxSteps, legacy: true)
        let optimized = await runArm(label: "optimized", prompt: prompt, systemPrompt: systemPrompt,
                                     baseRequest: setup.baseRequest, maxSteps: setup.maxSteps, legacy: false)
        let truth = Self.truthCount(in: workspaceRoot.appendingPathComponent("Localization.swift"),
                                    span: span, needle: "simplifiedChinese")
        let report = """
        {
          "task": "repeatedReads",
          "model": "\(setup.model)",
          "truth": \(truth),
          "legacy": \(legacy.json),
          "optimized": \(optimized.json)
        }
        """
        print("PROBE_REAL " + report)
        try report.write(toFile: setup.outPath, atomically: true, encoding: .utf8)

        XCTAssertTrue(optimized.answer.contains("COUNT=\(truth)"),
                      "新行为要数对（真值 \(truth)）：\(optimized.answer.suffix(120))")
    }

    /// 取文件里某一段（1 起，含首尾）每行的前 30 个字符 —— 真值，不写死。
    static func truthSpan(in url: URL, span: ClosedRange<Int>) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: "\n")
        return span.compactMap { number in
            guard number > 0, number <= lines.count else { return nil }
            let line = lines[number - 1].trimmingCharacters(in: .whitespaces)
            return String(line.prefix(30))
        }
    }

    /// 数出文件某一段里某个词出现的次数 —— 真值，不写死。
    static func truthCount(in url: URL, span: ClosedRange<Int>, needle: String) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let lines = text.components(separatedBy: "\n")
        return span.reduce(0) { total, number in
            guard number > 0, number <= lines.count else { return total }
            let line = lines[number - 1]
            var count = 0
            var search = line[...]
            while let found = search.range(of: needle) {
                count += 1
                search = search[found.upperBound...]
            }
            return total + count
        }
    }
}
