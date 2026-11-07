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
        // **越界不是「自己拒」，是「出单等人批」**（详设 §3.26）。2026-10-31 实测：这条原先写的是
        // 「越界的请求请说明原因并停下」，于是模型连工具都不调用、直接回一句「这个请求我需要停下，不做」——
        // 人根本没机会批准。现在改成照常发起，边界由那张单子把着。
        lines.append("3. 默认在本工作区内读写；要动工作区外的东西时**照常发起调用**（工具会出一张审批单，"
                     + "批不批由人定），不要自己改口说「我不做」，也不要用 `cd` / 软链接 / 复制到工作区再读这类绕法。"
                     + "被拒或被拒批时如实转达原因，不重试第三次。")

        // **别把"查证"当成"干活"**（人类主人 2026-10-18 实测：问一句"你具备自进化能力吗"，
        // 助手连查 150 步 `list_dir` / `search`，把步数用光，最后什么也没答出来）。
        // 这条规则针对的就是那种行为：**能力 / 设计类的问题，先用已知事实回答**，
        // 需要证据时查一两次就够，"把工作区翻个遍"既慢又答不出问题。
        lines.append("4. 回答「你的能力是什么」这类问题时：先用已知事实直接回答（代码里有什么、"
                     + "缺什么），需要佐证时最多查 1-2 次；**不许**为了「看看工作区到底有什么」而反复"
                     + "列目录 / 搜索 —— 那不是查证，那是逃避回答。查了 2 次还得不出结论，就直说"
                     + "「我现在不知道」，并说明缺什么信息。")
        lines.append("5. 同一个查询（同工具 + 同参数）**不许重复第三次**，**换个近义词再搜也算重复**"
                     + "（`会话超时` 之后又搜 `会话时间`，就是原地打转）；只读工具每轮次数有上限。"
                     + "重复之前先问自己：上一次的结果为什么不够用？要多个词，就**一次**把词放进 "
                     + "`search` 的 `queries` 数组（一次调用拿到每个词各自的命中）；否则直接给结论。")
        lines.append("6. 回答用中文；代码、路径与命令保持原样，不改写。")
        // `FR-AI-31` ②：**说完成要有据**。这条规矩是给验证器的输入协议 ——
        // 不写这句，模型会照旧说一句「已完成」；写了这句，它要么给出引用，要么如实说没验证。
        lines.append("7. 说「完成 / 改好了 / done」时，必须紧跟一行证据引用，形如 "
                     + "`EVIDENCE: write 相对路径` · `EVIDENCE: edit 相对路径` · `EVIDENCE: command exit=0`；"
                     + "引用**必须是本次真跑过的工具结果**。拿不出就直说「未验证」，不要用一句「已完成」交差。")
        // `FR-AGT-QUAL-VERIFY-003` ②：**不确定就说全** —— 只承认「把握低」而不给替代方案，
        // 等于把人晾在原地（判据会把那种结论判成缺陷、不许当交付物）。
        // 协议文本与解析侧共用一处（`AgentAlternativeProtocol`）：提示词里要是换了引导词，
        // 解析那边自动跟着换 —— 两处各写一份，换的时候必有一个漏。
        lines.append("8. " + AgentAlternativeProtocol.rule)
        lines.append("")
        // **编码工作流**（人类主人 2026-10-31：「Agent 怎么具备编码能力呢？看上去都还不会编 Python 脚本」）。
        // 前面八条讲的是「怎么做人」（如实、别乱查、要有据），这一节讲的是「怎么把活干成」：
        // 计划 → 落盘 → 真跑 → 按报错修 → 带读数交付。缺了这一节，模型会停在「我写好了」，
        // 而屏幕上什么都没有。
        lines.append("【编码工作流】接到编码 / 脚本任务，按这个顺序走，**不许跳步**：")
        lines.append("1. 先看再写：用 read_file / list_dir 看清现有文件与命名风格，再动手；不确定就先问一句。")
        lines.append("2. 一次一小步：先写一个能跑的最小版本（write_file），跑通了再扩。")
        lines.append("3. 落盘就验：写完**立刻**用 run_command 跑一次（`python3 x.py` / `swift build` / 对应测试），"
                     + "拿到真实输出再往下走 —— 没跑过就不算写完。")
        lines.append("4. 按报错改，别重发：exit != 0 时把报错原文当输入去改代码；**同一条命令原样重试不许超过两次**，"
                     + "第三次必须是改过之后的新命令。")
        lines.append("5. 脚本写成文件再跑：用 `python3 script.py`，不要用 `python3 -c \"…\"` 拼长字符串 —— "
                     + "后者报错时看不出行号，也没法复用。")
        lines.append("6. 交付带读数：最后给「命令 + 退出码 + 关键输出」三样；拿不出就读作「未验证」，"
                     + "不要用一句「已完成」交差。")
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
