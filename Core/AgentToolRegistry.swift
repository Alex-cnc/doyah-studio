import Foundation

/// 工具的权限等级（`FR-AI-19` 的「等级」列，`FR-AI-23` 的审批按同一份声明走）。
public enum AgentToolLevel: String, Codable, Sendable {
    case readOnly
    case writable
    case executable
}

/// 审批策略：只读直接跑；写 / 执行**逐次**要审批（不许变成「给工具开总开关」）。
public enum AgentToolApproval: String, Codable, Sendable {
    case none
    case required
}

/// 交付阶段：MVP 六件 / 第二批（`FR-AI-20` ⑥ 要求如实登记，不许写成已做）。
public enum AgentToolStage: String, Codable, Sendable {
    case mvp
    case secondBatch
}

/// 一个工具的**一处声明**（`FR-AI-19`：内置与 MCP 工具都从这一张表走，新增工具必须在此登记）。
///
/// 表里的字面量（工具名 / 参数名 / JSON Schema 关键字）是**接口层载荷**，不是展示文案 —— 人话那一半
/// （`summary`）与 `Core/AgentSQLGenerator.swift` 的提示词族同性质：**给模型读的请求组装文本**。
public struct AgentToolDefinition: Equatable, Sendable {

    public var name: String
    /// 给模型读的一句话（同提示词族口径；不是界面文案）。
    public var summary: String
    /// 参数名 → JSON Schema 类型（`string` / `integer` / `boolean`）。
    public var parameters: [String: String]
    /// 必填参数（必须是 `parameters` 的子集）。
    public var required: [String]
    public var level: AgentToolLevel
    public var approval: AgentToolApproval
    public var stage: AgentToolStage
    /// 是否注入给模型（`FR-AI-19` ③：注入条数 = 本表**启用**条数）。
    public var enabled: Bool

    public init(name: String,
                summary: String,
                parameters: [String: String] = [:],
                required: [String] = [],
                level: AgentToolLevel,
                approval: AgentToolApproval,
                stage: AgentToolStage = .mvp,
                enabled: Bool = true) {
        self.name = name
        self.summary = summary
        self.parameters = parameters
        self.required = required
        self.level = level
        self.approval = approval
        self.stage = stage
        self.enabled = enabled
    }

    /// 参数的 JSON Schema（**由声明生成**，不手抄第二份）。
    public var schemaJSON: String {
        var properties: [String: [String: String]] = [:]
        for (key, type) in parameters { properties[key] = ["type": type] }
        let payload: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": required.sorted(),
            "additionalProperties": false,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    /// 指纹：**随 schema 变化而变**（改一个字段 ⇒ 指纹变）。FNV-1a 64，纯函数、不引随机源。
    public var fingerprint: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let material = [name, schemaJSON, level.rawValue, approval.rawValue].joined(separator: "|")
        for byte in Array(material.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// 注入模型的形状（`FR-AI-19` ③）。
    public var llmTool: LLMTool {
        LLMTool(name: name, description: summary, parametersJSON: schemaJSON)
    }
}

/// 工具注册表（**唯一出处**）：模型看到的 `tools` 只能从这里出。
public struct AgentToolRegistry: Sendable {

    public private(set) var definitions: [AgentToolDefinition]

    public init(definitions: [AgentToolDefinition]) {
        self.definitions = definitions
    }

    /// 标准表：MVP 六件（可用）+ 第二批两件（**如实登记为未启用**）。
    ///
    /// 六件 MVP 与两件第二批的划分来自 SRS `FR-AI-20`（`read_notes` / `fetch_url` 按调研件为第二批）。
    public static var standard: AgentToolRegistry {
        AgentToolRegistry(definitions: [
            AgentToolDefinition(name: "read_file",
                                summary: "读工作区里的一个文件（只读）",
                                parameters: ["path": "string"],
                                required: ["path"],
                                level: .readOnly, approval: .none),
            AgentToolDefinition(name: "list_dir",
                                summary: "列工作区里一个目录的条目（只读）",
                                parameters: ["path": "string"],
                                required: [],
                                level: .readOnly, approval: .none),
            AgentToolDefinition(name: "search",
                                summary: "在工作区里按名字或内容搜索（只读）",
                                parameters: ["query": "string", "limit": "integer"],
                                required: ["query"],
                                level: .readOnly, approval: .none),
            AgentToolDefinition(name: "query_db",
                                summary: "在连接上跑一条只读查询（写语句要走审批）",
                                parameters: ["sql": "string"],
                                required: ["sql"],
                                level: .readOnly, approval: .none),
            AgentToolDefinition(name: "write_file",
                                summary: "写工作区里的一个文件（需审批；应用前先出差异）",
                                parameters: ["path": "string", "content": "string"],
                                required: ["path", "content"],
                                level: .writable, approval: .required),
            AgentToolDefinition(name: "run_command",
                                summary: "在工作目录沙箱里跑一条白名单命令（需审批）",
                                parameters: ["command": "string"],
                                required: ["command"],
                                level: .executable, approval: .required),
            AgentToolDefinition(name: "read_notes",
                                summary: "读笔记（第二批，本档未启用）",
                                parameters: ["path": "string"],
                                required: ["path"],
                                level: .readOnly, approval: .none,
                                stage: .secondBatch, enabled: false),
            AgentToolDefinition(name: "fetch_url",
                                summary: "抓一个 URL（第二批，本档未启用）",
                                parameters: ["url": "string"],
                                required: ["url"],
                                level: .readOnly, approval: .none,
                                stage: .secondBatch, enabled: false),
        ])
    }

    /// 按名查一处声明。**未登记的名字查不到**（`FR-AI-19` ④：未登记不可被调用）。
    public func definition(named name: String) -> AgentToolDefinition? {
        definitions.first { $0.name == name }
    }

    /// 启用的声明（稳定顺序 = 表的声明顺序）。
    public var enabledDefinitions: [AgentToolDefinition] {
        definitions.filter(\.enabled)
    }

    /// 注入模型的 `tools`：与「启用」条目**逐条相等**（一条不多、一条不少）。
    public var enabledTools: [LLMTool] {
        enabledDefinitions.map(\.llmTool)
    }

    /// 表里有没有这条声明（不等于允许调用 —— 允许与否还要看等级与审批）。
    public func isRegistered(_ name: String) -> Bool {
        definition(named: name) != nil
    }
}
