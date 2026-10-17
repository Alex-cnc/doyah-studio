import Foundation

/// 对话循环的**系统提示**（`FR-AI-16` 基座 · `FR-AI-22` 上下文 · `FR-EDIT-40` 四条契约）。
///
/// **接线段为什么需要它**：此前 `App/AppState.swift` 把 `systemPrompt` 写死成 `""` —— 模型看不到
/// 自己是谁、能用哪些工具、数据边界在哪，于是"能调工具"退化成了"凭猜"。本文件把这三件事变成
/// **可判据的字符串**（判据见 `Tests/AgentContextTests.swift`），而不是靠调用方自觉。
///
/// 数据边界（`NFR-AI-01`）不在这里兜底，而在**类型层**：`AgentContextReference` 里根本没有
/// 承载结果集行数据的形态（见 `Core/AgentContext.swift` 的注释）；本文件只负责把**已被过滤**的
/// 上下文段拼进来，并如实标注截断。
public enum AgentSystemPrompt {

    /// 基础提示：身份 + 模型与端点（`FR-EDIT-40` ③：说出模型与端点，不许静默）+ 工具面 + 数据边界 + 行为规矩。
    public static func base(model: String,
                            endpoint: String,
                            tools: [AgentToolDefinition] = AgentToolRegistry.standard.definitions) -> String {
        var lines: [String] = []
        lines.append("你是 Doyah Studio 内置的编程 / 数据分析助手（跑在本机应用里，不是云端代理）。")
        lines.append("当前模型：\(model)；端点：\(endpoint)。被问到时就照实回答，不要编造别的模型或服务商。")
        lines.append("")
        lines.append("【数据边界】结果集行数据、口令与密钥**从不外发** —— 只能发送表名、列名与行数。")
        lines.append("要分析数据时，先说清你要看哪几列、为什么；只依据工具返回的摘要（列名 / 行数）下判断。")
        lines.append("默认保守：拿不准就少发，宁可不发。")
        lines.append("")
        lines.append("【可用工具】")
        for d in tools where d.enabled {
            let gate = (d.approval == .required) ? "需先审批" : "直接可用"
            let level: String
            switch d.level {
            case .readOnly: level = "只读"
            case .writable: level = "可写"
            case .executable: level = "可执行"
            }
            let stage = (d.stage == .mvp) ? "MVP" : "后续批次"
            lines.append("- \(d.name)（\(level) · \(gate) · \(stage)）：\(d.summary)")
        }
        lines.append("")
        lines.append("【行为规矩】")
        lines.append("1. 要改文件先出差异、等审批通过再落盘 —— 不许静默改文件。")
        lines.append("2. 工具返回 `unavailable` / `denied` 时如实转达，**不许假装做过**。")
        lines.append("3. 只在本工作区内读写；越界的请求请说明原因并停下，不要绕。")
        lines.append("4. 回答用中文；代码、路径与命令保持原样，不改写。")
        return lines.joined(separator: "\n")
    }

    /// 完整系统提示 = 基础提示 + 本次挂上来的上下文（`FR-AI-22`；装配、截断与边界过滤都在 `AgentContextAssembler`）。
    public static func build(model: String,
                             endpoint: String,
                             workspacePath: String,
                             references: [AgentContextReference],
                             limits: AgentContextLimits = AgentContextLimits(),
                             tools: [AgentToolDefinition] = AgentToolRegistry.standard.definitions,
                             soul: AgentSoulComposition? = nil) -> String {
        // **灵魂是固定层，排在最前**（`FR-AI-34`）：L0 与 L1 的任何要求都不得被后面各段相抵。
        // 不给 = 这一路调用没有灵魂（既有测试不必改）；给了就必须完整可用（缺项由 `AgentSoul.compose` 如实写进文本）。
        var parts: [String] = []
        if let soul {
            parts.append(soul.section)
            parts.append("")
        }
        parts.append(base(model: model, endpoint: endpoint, tools: tools))
        parts.append("")
        parts.append("【工作区】\(workspacePath)")
        if !references.isEmpty {
            let payload = AgentContextAssembler.assemble(references, limits: limits)
            parts.append("")
            parts.append("【本次上下文】（已按边界过滤；被截断 / 被挡掉的段会如实标注）")
            parts.append(payload.promptFragment)
        }
        return parts.joined(separator: "\n")
    }
}
