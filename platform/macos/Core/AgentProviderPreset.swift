import Foundation

/// 内置模型服务预设（FR-AI-01 的配置面 · 队列 `L-146` · 内测清单丁3）。
///
/// **为什么有它**：需求提出者 2026-09-30 内测原话「AI 助理配置时应该提供主流大模型配置 url 和
/// 可选择模型，**毕竟很多人是不懂的**」—— 面板原先只给两个空输入框（端点 + 模型名），
/// 不懂端点的人到这一步就走不下去。
///
/// 三条口径：
/// 1. **预设是起点不是锁**：选中提供商只是把端点与常用模型**填好**，两个输入框仍可改
///    （自建网关 / 代理 / 私有部署都要用得上）；
/// 2. **端点只有一份出处**：所有提供商地址都住在本文件（`AgentProviderCatalog.all`），
///    界面不许自带字面量 —— 由 `Scripts/check-agent-provider-presets.py` 判住；
/// 3. **密钥仍是用户自己填**：本类型里没有、也不许有 API Key 字段（密钥只进系统钥匙串，
///    见 `AgentKeyStore`）—— 预设降低的是「懂端点」的门槛，不是「免凭据」。
public struct AgentProviderPreset: Identifiable, Equatable, Sendable {

    /// 稳定标识（匹配与界面选中用；不落盘、不显示）。
    public let id: String
    /// 界面标签**走语言表**：品牌名在两种语言里可能不同写法（`通义千问` / `Qwen`），
    /// 而 Core 里的用户可见文本一律过语言表（R-45）。
    public let labelKey: LKey
    /// OpenAI 兼容端点（`chat/completions` 那一套）。「自定义」条目的端点是**空串**。
    public let endpoint: String
    /// 常用模型名。**空数组 = 没有可预设的清单**（本机服务 / 接入点 ID 这类只能由用户填），
    /// 界面据此把模型下拉置灰 —— 不假装有一个清单。
    public let models: [String]

    public init(id: String, labelKey: LKey, endpoint: String, models: [String]) {
        self.id = id
        self.labelKey = labelKey
        self.endpoint = endpoint
        self.models = models
    }

    /// 是否「自定义」条目（没有预设端点）。
    public var isCustom: Bool { id == AgentProviderCatalog.customID }

    /// 端点是否指向本机 / 局域网（NFR-AI-06 本地模型优先）。
    ///
    /// **口径只有一处**：转发给 `AgentConfiguration.isLocalEndpoint` —— 预设表不自己判一遍，
    /// 否则「什么算本地端点」会有两个定义，改一处另一处就旧了。
    public var isLocal: Bool { AgentConfiguration(endpoint: endpoint).isLocalEndpoint }

    /// 模型下拉的内容（**契约面的一半**）：预设清单 + 「当前模型不在清单里就补一条」。
    ///
    /// 补那一条是因为模型名会过时（服务商上新比本仓发版快）：用户自己填的名字**必须仍然
    /// 看得见**，否则下拉一开就好像把它吞了。空串不补。
    public func modelOptions(currentModel: String) -> [String] {
        var options = models
        let trimmed = currentModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !options.contains(trimmed) {
            options.append(trimmed)
        }
        return options
    }
}

/// 内置预设目录（FR-AI-01）。
///
/// **模型名会过时**（服务商上新比本仓发版快）：清单是**起点**不是白名单 —— 用户永远可以自己填
/// （`modelOptions(currentModel:)` 保证自填的名字不被吞掉），所以「清单里少了某个新模型」
/// 不构成缺陷，判据也不管名字新旧。
public enum AgentProviderCatalog {

    /// 「自定义」条目的标识。
    public static let customID = "custom"

    /// 内置预设；**最后一条固定是「自定义」**（端点为空）。
    ///
    /// 一行一条、形状规整：`Scripts/check-agent-provider-presets.py` 按这个形状解析
    /// （端点唯一 / 标识唯一 / 条数下限 / 语言表齐备）。
    public static let all: [AgentProviderPreset] = [
        AgentProviderPreset(id: "openai", labelKey: .agentProviderOpenAI, endpoint: "https://api.openai.com/v1", models: ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini"]),
        AgentProviderPreset(id: "anthropic", labelKey: .agentProviderAnthropic, endpoint: "https://api.anthropic.com/v1", models: ["claude-3-7-sonnet-20250219", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"]),
        AgentProviderPreset(id: "deepseek", labelKey: .agentProviderDeepSeek, endpoint: "https://api.deepseek.com/v1", models: ["deepseek-chat", "deepseek-reasoner"]),
        AgentProviderPreset(id: "qwen", labelKey: .agentProviderQwen, endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1", models: ["qwen-max", "qwen-plus", "qwen-turbo", "qwen-long"]),
        AgentProviderPreset(id: "zhipu", labelKey: .agentProviderZhipu, endpoint: "https://open.bigmodel.cn/api/paas/v4", models: ["glm-4-plus", "glm-4-air", "glm-4-flash"]),
        AgentProviderPreset(id: "moonshot", labelKey: .agentProviderMoonshot, endpoint: "https://api.moonshot.cn/v1", models: ["moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"]),
        AgentProviderPreset(id: "volcano", labelKey: .agentProviderVolcano, endpoint: "https://ark.cn-beijing.volces.com/api/v3", models: []),
        AgentProviderPreset(id: "siliconflow", labelKey: .agentProviderSiliconFlow, endpoint: "https://api.siliconflow.cn/v1", models: ["deepseek-ai/DeepSeek-V3", "Qwen/Qwen2.5-72B-Instruct"]),
        AgentProviderPreset(id: "openrouter", labelKey: .agentProviderOpenRouter, endpoint: "https://openrouter.ai/api/v1", models: ["openai/gpt-4o-mini", "anthropic/claude-3.5-sonnet", "google/gemini-2.0-flash-001"]),
        AgentProviderPreset(id: "groq", labelKey: .agentProviderGroq, endpoint: "https://api.groq.com/openai/v1", models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]),
        AgentProviderPreset(id: "mistral", labelKey: .agentProviderMistral, endpoint: "https://api.mistral.ai/v1", models: ["mistral-large-latest", "mistral-small-latest"]),
        AgentProviderPreset(id: "xai", labelKey: .agentProviderXAI, endpoint: "https://api.x.ai/v1", models: ["grok-2-latest", "grok-2-1212"]),
        AgentProviderPreset(id: "gemini", labelKey: .agentProviderGemini, endpoint: "https://generativelanguage.googleapis.com/v1beta/openai", models: ["gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash"]),
        AgentProviderPreset(id: "ollama", labelKey: .agentProviderOllama, endpoint: "http://127.0.0.1:11434/v1", models: ["qwen2.5:7b", "llama3.2:3b", "deepseek-r1:7b", "gemma2:9b"]),
        AgentProviderPreset(id: "vllm", labelKey: .agentProviderVLLM, endpoint: "http://127.0.0.1:8000/v1", models: []),
        AgentProviderPreset(id: "custom", labelKey: .agentProviderCustom, endpoint: "", models: [])
    ]

    /// 「自定义」条目（端点为空；界面选中它时不改用户已填的端点）。
    public static var custom: AgentProviderPreset { all[all.count - 1] }

    /// 按标识取预设；没有这个标识给 `nil`（不猜、也不退回第一条）。
    public static func preset(id: String) -> AgentProviderPreset? {
        all.first { $0.id == id }
    }

    /// 用户当前端点「是谁」（用于**重开面板时恢复选中**）。
    ///
    /// 认不出（自建网关 / 代理 / 改过端口）⇒ `nil` —— 那不是失败，界面落到「自定义」。
    public static func preset(matchingEndpoint raw: String) -> AgentProviderPreset? {
        let normalized = normalizedEndpoint(raw)
        guard !normalized.isEmpty else { return nil }
        return all.first { !$0.isCustom && normalizedEndpoint($0.endpoint) == normalized }
    }

    /// 上面那条的界面口径：认不出就是「自定义」。
    public static func resolved(endpoint: String) -> AgentProviderPreset {
        preset(matchingEndpoint: endpoint) ?? custom
    }

    /// 端点归一化（**只用于比较**，不改用户配置里的原文）：去首尾空白 + 小写 + 去掉结尾的 `/`。
    ///
    /// 为什么要有它：`https://api.openai.com/v1/` 与 `https://api.openai.com/v1` 是同一个端点，
    /// 用户手抄常带尾巴；不归一化就会「重开面板显示成自定义」，而这看着像功能坏了。
    public static func normalizedEndpoint(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }
}
