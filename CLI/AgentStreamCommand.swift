import DoyahCore
import Foundation
import Darwin

/// 终端列宽（`COLUMNS` 环境变量优先；否则问一次 ioctl；再不然 100 列）。
///
/// 为什么不用固定值：折行一旦写死列数，用户在窄窗口里看还是溢、在宽窗口里看又太早折。
func currentTerminalColumns() -> Int {
    if let raw = ProcessInfo.processInfo.environment["COLUMNS"], let value = Int(raw), value >= 20 {
        return value
    }
    var size = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
        return Int(size.ws_col)
    }
    return 100
}

/// `agent-sql-stream`：无界面地跑一遍**流式**模型通道（`FR-AI-16` ② 的脚本取证入口）。
///
/// 为什么单开一条子命令：`agent-sql` 走的是整段那条路（`stream: false`）。流式的判据必须在
/// 「**真进程 + 真 HTTP + 真 SSE**」下能跑一遍才算数 —— Core 侧单测覆盖的是解码器与事件序列，
/// 这一层覆盖的是「接线到底接对了没有」。失败一律给可读原因，**不把半截回复当完整回复**。
func runAgentSQLStreamCommand(arguments: [String]) async -> Int32 {
    func value(for flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    let usageLine = "用法：DoyahCLI agent-sql-stream --endpoint <url> [--model <名>] [--api-key <key>] \"<需求>\""

    let flagsWithValue: Set<String> = ["--endpoint", "--model", "--api-key"]
    var instruction: String?
    var skipNext = false
    for argument in arguments {
        if skipNext { skipNext = false; continue }
        if flagsWithValue.contains(argument) { skipNext = true; continue }
        if argument.hasPrefix("--") { continue }
        instruction = argument
        break
    }

    guard let endpointText = value(for: "--endpoint"), let endpoint = URL(string: endpointText), !endpointText.isEmpty else {
        print(usageLine)
        return 64
    }
    guard let instruction, !instruction.isEmpty else {
        print(usageLine)
        return 64
    }

    let model = value(for: "--model") ?? "local-model"
    let request = LLMRequest(endpoint: endpoint,
                             model: model,
                             apiKey: value(for: "--api-key"),
                             systemPrompt: "你是数据库助手，只回 SQL。",
                             userPrompt: instruction,
                             stream: true)

    // **模型信息摆在最前面**（人类主人 2026-10-17：「要加上模型信息，会话已消耗的 token 等信息，
    // 可以参考 Hermes 的 cli 界面」）—— 开跑之前就看得见"这次是谁在回答、端点在哪、按多少列折行"。
    let columns = currentTerminalColumns()
    var session = TokenUsageLedger()
    var wrapper = TerminalTextWrapper(columns: columns)
    print("模型：\(model)")
    print("端点：\(endpoint.absoluteString)")
    print("折行：\(columns) 列（中文按 2 列计）")
    print("")

    var pieces: [String] = []
    var textDeltas = 0
    var toolCallDeltas = 0
    var sawDone = false

    do {
        let client = OpenAICompatibleStreamingClient()
        for try await event in try await client.stream(request) {
            switch event {
            case .textDelta(let piece):
                textDeltas += 1
                pieces.append(piece)
                // **按列宽折行**再吐（改前 `print(piece, terminator: "")` 直接给终端硬折，
                // 折点会落在词中间；中文按字符数算还会低估一半列宽）。
                print(wrapper.feed(piece), terminator: "")
            case .toolCallDelta:
                toolCallDeltas += 1
            case .usage(let usage, let actualModel):
                print(wrapper.flush())
                let missing = session.add(prompt: usage.promptTokens, completion: usage.completionTokens)
                let input = usage.promptTokens.map(String.init) ?? "—"
                let output = usage.completionTokens.map(String.init) ?? "—"
                print("")
                print("用量（第 \(session.requests) 次）：输入 \(input) / 输出 \(output) / 实际模型 \(actualModel ?? model)"
                      + (missing ? " · ⚠️ 本次端点未回完整用量（缺值不当 0 累加）" : ""))
                print("会话累计：输入 \(session.promptTokens) / 输出 \(session.completionTokens) / 合计 \(session.totalTokens) token"
                      + (session.responsesWithoutUsage > 0 ? "（其中 \(session.responsesWithoutUsage) 次无用量读数）" : ""))
            case .finished(let reason):
                print("")
                print("结束原因：\(reason ?? "—")")
            case .done:
                sawDone = true
            }
        }
    } catch {
        // 断流那条路会到这里：如实说，且**不宣称拿到完整回复**。
        print("")
        print("生成失败：\(CLIFailureText.oneLine(error))")
        return 67
    }

    print(wrapper.flush())
    print("")
    print("（流式：正文块 \(textDeltas) 个 / 工具调用块 \(toolCallDeltas) 个 / 拼接 \(pieces.joined().count) 个字符 / 见到 [DONE]：\(sawDone ? "是" : "否")）")
    print("（会话：\(session.requests) 次请求 · 输入 \(session.promptTokens) / 输出 \(session.completionTokens) / 合计 \(session.totalTokens) token）")
    return sawDone ? 0 : 67
}
