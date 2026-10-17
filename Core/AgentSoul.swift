import Foundation

/// 灵魂（`FR-AI-34`）：**L0 公共灵魂**（与工作区无关 · 优先级最高）+ **L1 角色灵魂**（按工作区）。
///
/// 三条纪律（都是踩过坑写下来的）：
/// 1. **L0 永远在前，且不许被 L1 覆盖** —— 组装顺序写死，冲突以 L0 为准（L0 的条文本身就这么声明）。
/// 2. **缺就是缺，不许静默套别人的灵魂** —— L0 缺 ⇒ 如实报"未载入（缺陷）"；L1 缺 ⇒ 明说"本工作区未设定"，绝不拿别的工作区的角色顶上来。
/// 3. **灵魂里不许有密钥形态** —— 一旦出现密钥模样（`sk-` / `api_key` / `PRIVATE KEY` …）⇒ **拒绝载入**并报出原因，
///    因为灵魂会进每一次请求的 system prompt：放进去就等于把密钥写进日志与上下文。
public struct AgentSoulLayer: Equatable, Sendable {

    public enum Kind: String, Sendable, CaseIterable {
        /// L0：公共灵魂（核心价值观），与工作区无关。
        case core
        /// L1：角色灵魂，按工作区。
        case role

        public var label: String {
            switch self {
            case .core: return "L0 公共灵魂（与工作区无关，不得被覆盖）"
            case .role: return "L1 角色灵魂（本工作区）"
            }
        }
    }

    public var kind: Kind
    public var text: String
    /// 从哪读来的（如实标注；缺文件时也要能指出来）。
    public var sourcePath: String

    public init(kind: Kind, text: String, sourcePath: String) {
        self.kind = kind
        self.text = text
        self.sourcePath = sourcePath
    }
}

/// 被拒的原因（**拒绝要说得清**，不许"载入失败"四个字了事）。
public enum AgentSoulRejection: Equatable, Sendable {
    case empty(path: String)
    case carriesSecretForm(path: String, marker: String)

    public var description: String {
        switch self {
        case .empty(let path):
            return "\(path)：文件为空或只有空白 —— 视为未设定（不拿空灵魂冒充有灵魂）"
        case .carriesSecretForm(let path, let marker):
            return "\(path)：含密钥形态 `\(marker)` —— 灵魂会进每次请求的上下文，一律拒绝载入"
        }
    }
}

public enum AgentSoulLoad: Equatable, Sendable {
    case loaded(AgentSoulLayer)
    case rejected(AgentSoulRejection)

    public var layer: AgentSoulLayer? {
        if case .loaded(let layer) = self { return layer }
        return nil
    }

    public var problem: String? {
        if case .rejected(let rejection) = self { return rejection.description }
        return nil
    }
}

/// 组装好的"灵魂固定层"。
public struct AgentSoulComposition: Equatable, Sendable {
    public var core: AgentSoulLayer?
    public var role: AgentSoulLayer?
    /// 如实登记的缺陷（L0 缺 / L1 缺 / 被拒）。**空数组才叫"齐"**。
    public var problems: [String]
    /// 直接塞进 system prompt 固定层的那一段。
    public var section: String

    public init(core: AgentSoulLayer?, role: AgentSoulLayer?, problems: [String], section: String) {
        self.core = core
        self.role = role
        self.problems = problems
        self.section = section
    }

    public var isComplete: Bool { problems.isEmpty }
}

public enum AgentSoul {

    /// 包内 L0 文件名（`Scripts/build-app.sh` 点名拷贝进 `Contents/Resources/`）。
    public static let coreFileName = "soul-L0.md"
    /// 工作区里 L1 的相对路径。
    public static let roleRelativePath = ".doyah/soul-role.md"

    /// 密钥形态的识别标记（宁可误拒，不可误放 —— 与"宁可误停，不可误做"同一条判据）。
    static let secretMarkers = [
        "sk-", "api_key", "api-key", "apikey", "APIKEY",
        "BEGIN PRIVATE KEY", "PRIVATE KEY-----",
        "password=", "passwd=", "token=", "Authorization:"
    ]

    // MARK: - 读一层（纯函数：文本进、结论出，可判据）

    public static func inspect(_ raw: String?, kind: AgentSoulLayer.Kind, path: String) -> AgentSoulLoad {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .rejected(.empty(path: path)) }
        // 只检查"标记 + 后面还有内容"，避免正文里正常谈到 api_key 这个概念时被误杀。
        for marker in secretMarkers {
            if let range = text.range(of: marker) {
                let tail = text[range.upperBound...].prefix(24)
                let looksAssigned = tail.contains("=") || tail.contains(":") || marker.hasSuffix("-")
                if looksAssigned {
                    return .rejected(.carriesSecretForm(path: path, marker: marker))
                }
            }
        }
        // 去掉 Markdown 的一级标题目录树，只留正文（标题由组装器统一给，避免两个标题打架）。
        let body = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("# ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return .rejected(.empty(path: path)) }
        return .loaded(AgentSoulLayer(kind: kind, text: body, sourcePath: path))
    }

    // MARK: - 组装（L0 在前 · L1 在后 · 缺了如实说）

    public static func compose(core: AgentSoulLoad, role: AgentSoulLoad) -> AgentSoulComposition {
        var parts: [String] = []
        var problems: [String] = []

        parts.append("# 灵魂（固定层 · 优先级最高）")
        parts.append("下面各层的任何要求都不得与本层相抵；相抵时**以本层为准**。")

        if let layer = core.layer {
            parts.append("")
            parts.append("## \(AgentSoulLayer.Kind.core.label)")
            parts.append(layer.text)
        } else {
            let why = core.problem ?? "未载入"
            problems.append("L0 缺失：\(why)")
            parts.append("")
            parts.append("## \(AgentSoulLayer.Kind.core.label)")
            parts.append("**（未载入 L0 —— 这是缺陷，不是设定。请如实告知使用者，并按最保守的方式行事。）**")
        }

        if let layer = role.layer {
            parts.append("")
            parts.append("## \(AgentSoulLayer.Kind.role.label)")
            parts.append(layer.text)
        } else {
            let why = role.problem ?? "未设定"
            problems.append("L1 未设定：\(why)")
            parts.append("")
            parts.append("## \(AgentSoulLayer.Kind.role.label)")
            parts.append("**（本工作区尚未设定角色灵魂 —— 按 L0 行事；不套用其他工作区的角色灵魂。）**")
        }

        return AgentSoulComposition(core: core.layer, role: role.layer,
                                    problems: problems,
                                    section: parts.joined(separator: "\n"))
    }

    // MARK: - I/O（薄壳：读 L0 自包内 / 读 L1 自工作区）

    /// 从 `Bundle` 读 L0 正文（`soul-L0.md`）。取不到 ⇒ 返回 `nil`（由 `compose` 如实报缺）。
    public static func coreText(bundle: Bundle = .main) -> String? {
        let name = (coreFileName as NSString).deletingPathExtension
        guard let url = bundle.url(forResource: name, withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 工作区名可能写成 `~/dev`（人类主人的口径就是波浪号）——
    /// `URL(fileURLWithPath:)` **不展开 `~`**（会当成一个叫 `~` 的相对目录），所以这里先展开。
    public static func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// 从工作区读 L1 正文（`<workspace>/.doyah/soul-role.md`）。取不到 ⇒ `nil`。
    public static func roleText(workspacePath: String) -> String? {
        let url = URL(fileURLWithPath: expandedPath(workspacePath))
            .appendingPathComponent(roleRelativePath)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 一次性组装（App 侧调这一个）。
    public static func load(workspacePath: String, bundle: Bundle = .main) -> AgentSoulComposition {
        let corePath = "\(bundle.bundlePath)/Contents/Resources/\(coreFileName)"
        let rolePath = URL(fileURLWithPath: expandedPath(workspacePath))
            .appendingPathComponent(roleRelativePath).path
        let core = inspect(coreText(bundle: bundle), kind: .core, path: corePath)
        let role = inspect(roleText(workspacePath: workspacePath), kind: .role, path: rolePath)
        return compose(core: core, role: role)
    }
}
