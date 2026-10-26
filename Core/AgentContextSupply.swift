import Foundation

/// **上下文供给**（`FR-AGT-CORE-CTX-001` / 本端计划 CORE-CTX-001）：
/// `@文件` / `@目录` / 选中代码 / 终端尾部 / DB schema 五类来源 → 进提示词的段落。
///
/// 三条纪律：
/// ① **每类各有预算**（超了截断并留标记，不静默吞）；
/// ② **同一来源只收一次**（同 kind + 同 path 去重，先到的胜）；
/// ③ **顺序稳定**（kind 固定序 → path 字典序），两次组装逐字相同。
public enum AgentContextSourceKind: String, Sendable, CaseIterable {
    case selection
    case file
    case directory
    case terminal
    case schema
}

public struct AgentContextSource: Equatable, Sendable {
    public var kind: AgentContextSourceKind
    /// 文件 / 目录路径；选择区与终端无路径。用于去重与标题。
    public var path: String?
    public var text: String

    public init(kind: AgentContextSourceKind, path: String? = nil, text: String) {
        self.kind = kind
        self.path = path
        self.text = text
    }
}

public struct AgentContextSupplyLimits: Equatable, Sendable {
    public var perSelection: Int
    public var perFile: Int
    public var perDirectory: Int
    public var perTerminal: Int
    public var perSchema: Int

    public init(perSelection: Int = 20_000, perFile: Int = 40_000, perDirectory: Int = 8_000,
                perTerminal: Int = 4_000, perSchema: Int = 12_000) {
        self.perSelection = perSelection
        self.perFile = perFile
        self.perDirectory = perDirectory
        self.perTerminal = perTerminal
        self.perSchema = perSchema
    }

    public func limit(for kind: AgentContextSourceKind) -> Int {
        switch kind {
        case .selection: return perSelection
        case .file: return perFile
        case .directory: return perDirectory
        case .terminal: return perTerminal
        case .schema: return perSchema
        }
    }
}

public struct AgentContextSupplyResult: Equatable, Sendable {
    public var sections: [AgentContextSection]
    /// 被去重丢掉的来源（判据与「为什么少了一段」用）。
    public var deduplicated: [String]

    public init(sections: [AgentContextSection], deduplicated: [String]) {
        self.sections = sections
        self.deduplicated = deduplicated
    }
}

public enum AgentContextSupply {

    /// 组装：去重 → 排序 → 按类预算截断。
    public static func assemble(_ sources: [AgentContextSource],
                                limits: AgentContextSupplyLimits = AgentContextSupplyLimits()) -> AgentContextSupplyResult {
        var seen = Set<String>()
        var deduplicated: [String] = []
        var kept: [AgentContextSource] = []
        for source in sources {
            let key = "\(source.kind.rawValue)#\(source.path ?? "-")"
            if seen.contains(key) {
                deduplicated.append(key)
                continue
            }
            seen.insert(key)
            kept.append(source)
        }
        kept.sort { lhs, rhs in
            let l = AgentContextSourceKind.allCases.firstIndex(of: lhs.kind) ?? 0
            let r = AgentContextSourceKind.allCases.firstIndex(of: rhs.kind) ?? 0
            if l != r { return l < r }
            return (lhs.path ?? "") < (rhs.path ?? "")
        }
        let sections = kept.map { source -> AgentContextSection in
            let limit = limits.limit(for: source.kind)
            let body = truncate(source.text, limit: limit)
            return AgentContextSection(title: title(for: source),
                                       body: body.text,
                                       truncated: body.truncated,
                                       redactedRows: 0,
                                       redactedSecrets: 0)
        }
        return AgentContextSupplyResult(sections: sections, deduplicated: deduplicated)
    }

    /// 尾巴截断（保留最近的），并留可读标记 —— 截断处必须看得见。
    public static func truncate(_ text: String, limit: Int) -> (text: String, truncated: Bool) {
        guard limit > 0, text.count > limit else { return (text, false) }
        let dropped = text.count - limit
        let tail = String(text.suffix(limit))
        return ("[…truncated \(dropped) chars]\n" + tail, true)
    }

    static func title(for source: AgentContextSource) -> String {
        switch source.kind {
        case .selection: return "selection"
        case .file: return "file:" + (source.path ?? "")
        case .directory: return "dir:" + (source.path ?? "")
        case .terminal: return "terminal"
        case .schema: return "schema"
        }
    }
}
