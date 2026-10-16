import Foundation

/// 一条**技能**（`FR-AI-26`）：声明式登记 —— 名称 + 适用面 / 触发 + 步骤（**引用工具名**）+ 披露面。
///
/// ## 三条纪律（写在类型头上，改的人先看这里）
///
/// 1. **技能不新造能力**：步骤里只出现**工具名**，真正干活的是 `AgentStandardDispatcher` ——
///    等级（只读 / 可写 / 可执行）与逐次审批**照走**，本文件一行判定都不做；
/// 2. **技能名只许出现在登记档里**：本文件（以及任何核心代码）不得按技能名分支 ——
///    照 `Core/CodeLanguageDefinitions.swift` 的「语言知识只允许出现在本文件」同族；新增技能只动登记档；
/// 3. **字段给全**：`name` / `applicability` / `triggers` / `steps` / `disclosure` 任一为空 ⇒ 加载即判红
///    （不静默跳过 —— 半条技能比没有技能更坏：模型会以为它可用）。
public struct AgentSkill: Equatable, Sendable {

    /// 技能名（唯一）。
    public var name: String
    /// 适用面：一句话说明**什么时候该用它**（给人看，也给模型看）。
    public var applicability: String
    /// 触发词（按需披露的判据：命中任一即可能被披露）。
    public var triggers: [String]
    /// 步骤：每步 = 引用一个**工具名** + 这步要做什么。
    public var steps: [Step]
    /// 披露面：这条技能被披露给模型时**允许说出去的内容**（不含密钥 / 不含行数据）。
    public var disclosure: String

    /// 一步：引用工具名 + 说明。
    public struct Step: Equatable, Sendable {
        public var tool: String
        public var summary: String

        public init(tool: String, summary: String) {
            self.tool = tool
            self.summary = summary
        }
    }

    public init(name: String, applicability: String, triggers: [String],
                steps: [Step], disclosure: String) {
        self.name = name
        self.applicability = applicability
        self.triggers = triggers
        self.steps = steps
        self.disclosure = disclosure
    }
}

/// 技能库（`FR-AI-26`）：**加载登记档 + 校验 + 按需披露**。三件事，都在这一个类型里。
///
/// ## 为什么是纯逻辑
///
/// 判据天然是「给『登记档 + 一次提问』要『披露了哪些技能 / 加载报了什么错』」—— 完全可以在 Core 里钉死。
/// 它**不执行任何工具**：披露出去的是"能做哪几步"，执行与审批仍归既有那条路（判据里有一条负例专门钉这件事）。
public enum AgentSkillLibrary {

    /// 加载失败的一档（**如实报，不静默跳过**）。
    public struct LoadIssue: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// 字段为空（`field` 说明是哪一格）。
            case emptyField(field: String)
            /// 步骤引用的工具名不在注册表里。
            case unknownTool(tool: String)
            /// 重名。
            case duplicateName(String)
        }
        public var skill: String
        public var kind: Kind

        public init(skill: String, kind: Kind) {
            self.skill = skill
            self.kind = kind
        }

        /// 给人看的一句话。
        public var text: String {
            switch kind {
            case .emptyField(let field): return "技能「\(skill)」的 \(field) 是空的 —— 半条技能比没有更坏"
            case .unknownTool(let tool): return "技能「\(skill)」引用了注册表里没有的工具「\(tool)」"
            case .duplicateName(let name): return "技能名「\(name)」重复"
            }
        }
    }

    /// 加载结果：**通过的**与**被判红的**分开报（界面上两种情况都要能说清）。
    public struct LoadResult: Equatable, Sendable {
        public var skills: [AgentSkill]
        public var issues: [LoadIssue]

        public init(skills: [AgentSkill], issues: [LoadIssue]) {
            self.skills = skills
            self.issues = issues
        }

        /// 有据可依的加载（没有判红）。
        public var isClean: Bool { issues.isEmpty }
    }

    /// 加载并校验一份登记档。
    ///
    /// - Parameters:
    ///   - skills: 登记档里解析出来的技能（解析 JSON 不是本类型的事：**登记档格式与解析**留在宿主侧，
    ///     这样 Core 不绑死一种序列化；本类型只管"这些技能合不合法"）。
    ///   - registry: 工具注册表（步骤里引用的工具名必须在这里找得到）。
    public static func load(_ skills: [AgentSkill],
                            registry: AgentToolRegistry = .standard) -> LoadResult {
        var accepted: [AgentSkill] = []
        var issues: [LoadIssue] = []
        var seen = Set<String>()

        for skill in skills {
            var bad = false
            // ① 字段给全（任一为空即判红，**一条都不放行** —— 半条技能比没有更坏）
            if skill.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(LoadIssue(skill: skill.name, kind: .emptyField(field: "name"))); bad = true
            }
            if skill.applicability.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(LoadIssue(skill: skill.name, kind: .emptyField(field: "适用面"))); bad = true
            }
            if skill.triggers.isEmpty || skill.triggers.contains(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                issues.append(LoadIssue(skill: skill.name, kind: .emptyField(field: "触发"))); bad = true
            }
            if skill.steps.isEmpty {
                issues.append(LoadIssue(skill: skill.name, kind: .emptyField(field: "步骤"))); bad = true
            }
            if skill.disclosure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(LoadIssue(skill: skill.name, kind: .emptyField(field: "披露面"))); bad = true
            }
            // ② 步骤引用的工具名必须在注册表里（找不到 ⇒ 判红，不许静默跳过）
            for step in skill.steps {
                if registry.definition(named: step.tool) == nil {
                    issues.append(LoadIssue(skill: skill.name, kind: .unknownTool(tool: step.tool))); bad = true
                }
            }
            // 重名
            if seen.contains(skill.name) {
                issues.append(LoadIssue(skill: skill.name, kind: .duplicateName(skill.name))); bad = true
            } else {
                seen.insert(skill.name)
            }
            if !bad { accepted.append(skill) }
        }
        return LoadResult(skills: accepted, issues: issues)
    }

    /// 按需披露：一次提问命中哪些技能（触发词出现在提问里，大小写不敏感）。
    ///
    /// **纯**：只看入参，不改状态、不联网、不读盘。命中多条就按登记顺序全给（不替用户挑一条 —— 挑错更贵）。
    public static func disclose(_ skills: [AgentSkill], for prompt: String) -> [AgentSkill] {
        let haystack = prompt.lowercased()
        guard !haystack.isEmpty else { return [] }
        return skills.filter { skill in
            skill.triggers.contains { needle in
                let n = needle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                return !n.isEmpty && haystack.contains(n)
            }
        }
    }

    /// 把一个技能渲染成**给模型看的一段**（披露面的落地形式）。
    ///
    /// 只写技能名 / 适用面 / 步骤的工具名与说明 —— `disclosure` 之外的东西一概不写
    /// （这是"披露面"这个字段的意义：它决定**能说出去什么**）。
    public static func promptFragment(for skill: AgentSkill) -> String {
        var lines: [String] = []
        lines.append("· 技能「\(skill.name)」：\(skill.applicability)")
        lines.append("  可用的步骤（工具名来自注册表，调用仍走等级与审批）：")
        for (index, step) in skill.steps.enumerated() {
            lines.append("    \(index + 1). \(step.tool) —— \(step.summary)")
        }
        lines.append("  披露面：\(skill.disclosure)")
        return lines.joined(separator: "\n")
    }
}
