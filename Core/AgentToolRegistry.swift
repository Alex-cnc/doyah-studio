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

/// 工具的**能力**（`FR-AI-19` 的登记面）：循环按能力把「模型要调的工具」映射到实现，
/// 于是实现侧**不必写工具名字面量**（源树判据守的就是那一点）。
public enum AgentToolCapability: String, Codable, Equatable, Sendable, CaseIterable {
    case readFile
    case listDirectory
    case search
    case queryDatabase
    case writeFile
    /// **定点改代码**（`edit_file`）：按唯一锚点换一段 —— 与整篇重写分开一件，因为两者风险不同。
    case editFile
    case runCommand
    case readNotes
    case fetchURL
    /// **用户自配 MCP server 上的工具**（`FR-AI-21`）：名字与参数**原样透传**，
    /// 这一侧不解释、不改写、不补全 —— 于是「同一个工具在两个客户端里名字不同」这件事不发生。
    case mcpTool
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
    /// 能力（实现在哪一侧认领它；`FR-AI-19` 的登记面）。
    public var capability: AgentToolCapability
    /// 参数名 → JSON Schema 类型（`string` / `integer` / `boolean`）。
    public var parameters: [String: String]
    /// 必填参数（必须是 `parameters` 的子集）。
    public var required: [String]
    public var level: AgentToolLevel
    public var approval: AgentToolApproval
    public var stage: AgentToolStage
    /// 是否注入给模型（`FR-AI-19` ③：注入条数 = 本表**启用**条数）。
    public var enabled: Bool
    /// **远端给的 JSON Schema 原文**（只有 MCP 工具用）：有它时 `schemaJSON` **原样返回** ——
    /// 远端 schema 的形状（`oneOf` / `enum` / 嵌套对象）不该由我们用「参数名 → 类型」重编一遍。
    public var schemaOverride: String?
    /// 参数是否**原样透传**给远端（`FR-AI-21` ①：工具名与参数不改名、不改形状）。
    /// `true` ⇒ 循环只判「是不是一个 JSON 对象」，不按本地声明的参数表挑三拣四（远端自己校验）。
    public var passesArgumentsThrough: Bool

    public init(name: String,
                summary: String,
                capability: AgentToolCapability,
                parameters: [String: String] = [:],
                required: [String] = [],
                level: AgentToolLevel,
                approval: AgentToolApproval,
                stage: AgentToolStage = .mvp,
                enabled: Bool = true,
                schemaOverride: String? = nil,
                passesArgumentsThrough: Bool = false) {
        self.name = name
        self.summary = summary
        self.capability = capability
        self.parameters = parameters
        self.required = required
        self.level = level
        self.approval = approval
        self.stage = stage
        self.enabled = enabled
        self.schemaOverride = schemaOverride
        self.passesArgumentsThrough = passesArgumentsThrough
    }

    /// 参数的 JSON Schema（**由声明生成**，不手抄第二份）；远端 schema 有原文时**原文优先**。
    public var schemaJSON: String {
        if let schemaOverride, !schemaOverride.isEmpty { return schemaOverride }
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

    /// 指纹：**随 schema 变化而变**（改一个字段 ⇒ 指纹变）。纯函数、不引随机源；实现只有一处（`AgentFingerprint`）。
    public var fingerprint: String {
        AgentFingerprint.hash([name, schemaJSON, level.rawValue, approval.rawValue].joined(separator: "|"))
    }

    /// 注入模型的形状（`FR-AI-19` ③）。
    public var llmTool: LLMTool {
        LLMTool(name: name, description: summary, parametersJSON: schemaJSON)
    }
}

/// 工具注册表（**唯一出处**）：模型看到的 `tools` 只能从这里出。
public struct AgentToolRegistry: Sendable {
    /// 工具名常量 —— `FR-AI-19`「工具名只许出现在本文件」的取用口。
    ///
    /// 别处（循环 / 界面）要报工具名时**从这儿取**，不另写字面量：
    /// 判据 `AgentToolRegistrySourceTests` 逐文件扫 `"search"` 这类字面量，写一处就判红。
    public static let searchToolName = "search"


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
                                capability: .readFile,
                                parameters: ["path": "string"],
                                required: ["path"],
                                level: .readOnly, approval: .none),
            AgentToolDefinition(name: "list_dir",
                                summary: "列工作区里一个目录的条目（只读）",
                                capability: .listDirectory,
                                parameters: ["path": "string"],
                                required: [],
                                level: .readOnly, approval: .none),
            AgentToolDefinition(name: searchToolName,
                                summary: "在工作区里按名字或内容搜索（只读）",
                                capability: .search,
                                parameters: ["query": "string", "limit": "integer"],
                                required: ["query"],
                                level: .readOnly, approval: .none),
            AgentToolDefinition(name: "query_db",
                                summary: "在连接上跑一条只读查询（写语句要走审批）",
                                capability: .queryDatabase,
                                parameters: ["sql": "string"],
                                required: ["sql"],
                                level: .readOnly, approval: .none),
            AgentToolDefinition(name: "write_file",
                                summary: "写工作区里的一个文件（需审批；应用前先出差异）",
                                capability: .writeFile,
                                parameters: ["path": "string", "content": "string"],
                                required: ["path", "content"],
                                level: .writable, approval: .required),
            AgentToolDefinition(name: "edit_file",
                                summary: "定点改工作区里的一个文件：按**唯一锚点**换掉一段（需审批；应用前先出差异）",
                                capability: .editFile,
                                parameters: ["path": "string", "old_string": "string", "new_string": "string"],
                                required: ["path", "old_string", "new_string"],
                                level: .writable, approval: .required),
            AgentToolDefinition(name: "run_command",
                                summary: "在工作目录沙箱里跑一条白名单命令（需审批）",
                                capability: .runCommand,
                                parameters: ["command": "string"],
                                required: ["command"],
                                level: .executable, approval: .required),
            AgentToolDefinition(name: "read_notes",
                                summary: "读笔记（第二批，本档未启用）",
                                capability: .readNotes,
                                parameters: ["path": "string"],
                                required: ["path"],
                                level: .readOnly, approval: .none,
                                stage: .secondBatch, enabled: false),
            AgentToolDefinition(name: "fetch_url",
                                summary: "抓一个 URL（第二批，本档未启用）",
                                capability: .fetchURL,
                                parameters: ["url": "string"],
                                required: ["url"],
                                level: .readOnly, approval: .none,
                                stage: .secondBatch, enabled: false),
        ])
    }

    /// 按**能力**取声明（实现侧因此不必写工具名 —— 见 `FR-AI-19` ① 的源树判据）。
    public func definition(for capability: AgentToolCapability) -> AgentToolDefinition? {
        definitions.first { $0.capability == capability && $0.enabled }
    }

    /// 「可写」那一件（`write_file` 一类）—— 按**等级**取，不按名字。
    /// 这样工具实现里不必写工具名字面量（`FR-AI-19` ① 的源树判据守着那一点），名字仍只有注册表一处。
    public var writableDefinition: AgentToolDefinition? {
        definitions.first { $0.level == .writable && $0.enabled }
    }

    /// 「可执行」那一件（`run_command` 一类）。同上：按等级取。
    public var executableDefinition: AgentToolDefinition? {
        definitions.first { $0.level == .executable && $0.enabled }
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

    /// 把**另一批**声明并进来（`FR-AI-21`：发现到的 MCP 工具进同一张表）。
    ///
    /// **与已有名字冲突的条目一律不并**（结果里把它们交回调用方）—— 远端工具**不许**顶掉内置工具的
    /// 名字：那会让「模型说要 `write_file`」这句话的含义随用户配了什么 server 而变。
    /// 同名冲突由调用方如实登记进连接状态（不静默丢）。
    public func merging(_ extra: [AgentToolDefinition]) -> (registry: AgentToolRegistry, conflicts: [String]) {
        var existing = Set(definitions.map(\.name))
        var merged = definitions
        var conflicts: [String] = []
        for definition in extra {
            if existing.contains(definition.name) {
                conflicts.append(definition.name)
                continue
            }
            existing.insert(definition.name)
            merged.append(definition)
        }
        return (AgentToolRegistry(definitions: merged), conflicts)
    }
}
