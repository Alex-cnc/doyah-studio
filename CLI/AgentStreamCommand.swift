import DoyahCore
import Foundation

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

    print("端点：\(endpoint.absoluteString)")
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
                print(piece, terminator: "")
            case .toolCallDelta:
                toolCallDeltas += 1
            case .usage(let usage, let actualModel):
                print("")
                let input = usage.promptTokens.map(String.init) ?? "—"
                let output = usage.completionTokens.map(String.init) ?? "—"
                print("用量：输入 \(input) / 输出 \(output) / 实际模型 \(actualModel ?? model)")
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
        print("生成失败：\(error.localizedDescription)")
        return 67
    }

    print("")
    print("（流式：正文块 \(textDeltas) 个 / 工具调用块 \(toolCallDeltas) 个 / 拼接 \(pieces.joined().count) 个字符 / 见到 [DONE]：\(sawDone ? "是" : "否")）")
    return sawDone ? 0 : 67
}
