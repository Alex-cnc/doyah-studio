import Foundation

/// 编辑区 Agent（AI 辅助编程）—— `FR-STD-WS-AI-001`。
///
/// 判定全在这里（纯函数），界面只负责搬运：动作 → 请求 → 结果 → 差异 → 人点了才落盘。
///
/// ## 需求给的四条契约，各自落在哪
///
/// ① **不许静默改文件**：本类型**没有**任何写盘入口；`rewrite` / `complete` 的产出只是
///    `Proposal`（原文 + 新文 + 差异），要人点「应用」才由编辑面走一次可撤销编辑
///    （`UndoEditKind.assist`）写进去。`explain` / `fixError` 连 `Proposal` 都不给。
/// ② **说得出模型与端点**：`Run.modelLine` 是界面那一行字（模型 + 端点），由调用点从
///    真实配置填；`Run` 里**没有默认值**，取不到就只能是 `refused(.endpointNotConfigured)`。
/// ③ **数据边界可配且默认保守**：`Boundary` 只有两档，`default` 是 `.selection`；
///    `outbound` 是把**真会发出去的那段正文**原样交出来，界面照它显示，不另算一次。
/// ④ **不与本机既有能力重复造**：格式化 / 行号 / 语言识别 / 缩进全在本机算，这几件事
///    **不进模型**（见 `Action.localOnlyAlternative`）—— 调用点选到它们就直接拒。
public enum EditAssist {

    // MARK: - 动作

    /// 首批四个动作（需求原文：解释选中代码 / 按自然语言改写成代码 / 补全当前上下文 / 对报错给修法）。
    public enum Action: String, CaseIterable, Sendable, Equatable {
        /// 解释选中的代码。
        case explain
        /// 按自然语言说明改写（要一句需求）。
        case rewrite
        /// 按上下文补全。
        case complete
        /// 对报错或诊断给修法。
        case fixError

        /// 菜单 / 面板上的名字。
        public var titleKey: LKey {
            switch self {
            case .explain: return .editAssistActionExplain
            case .rewrite: return .editAssistActionRewrite
            case .complete: return .editAssistActionComplete
            case .fixError: return .editAssistActionFixError
            }
        }

        /// 产出会不会写回文件。
        ///
        /// 只有「生成代码」这两个动作能改正文；解释与修法只出文字 —— 这条是契约 ① 的结构面：
        /// 界面拿 `writesBack == false` 的结果时**连差异都不弹**，想改文件得用户自己复制。
        public var writesBack: Bool {
            switch self {
            case .rewrite, .complete: return true
            case .explain, .fixError: return false
            }
        }

        /// 这条动作要不要用户先写一句自然语言。
        public var needsInstruction: Bool { self == .rewrite }

        /// 本机就能算、不必进模型的那件事（契约 ④）。
        ///
        /// - Returns: 与本动作同名的本机能力说明键；`nil` = 本机没有等价能力，只能问模型。
        public var localOnlyAlternative: LKey? {
            switch self {
            case .complete:
                // 补全在本机有词法 / SQL / 路径三路灰字（`InlineGhost`），不需要模型。
                return .editAssistLocalAlternativeCompletion
            case .explain, .rewrite, .fixError:
                return nil
            }
        }

        /// 给模型的一句指令（模型面文案，不进语言表：它不是界面文案）。
        var modelInstruction: String {
            switch self {
            case .explain:
                return "解释下面这段代码做了什么：先说它解决什么问题，再按顺序讲关键步骤，最后指出值得注意的坑。"
            case .rewrite:
                return "按用户的要求改写下面的代码。只给完整可替换的新代码，不要解释，不要省略号。"
            case .complete:
                return "补全下面这段代码缺失的部分，让它能直接编译运行。只给补全后的完整代码，不要解释。"
            case .fixError:
                return "下面这段代码有报错。给出最小修法：先一句话说根因，再给修好后的完整代码。"
            }
        }
    }

    // MARK: - 数据边界

    /// 发出去的内容范围。**默认 `.selection`**（契约 ③：默认保守）。
    public enum Boundary: String, CaseIterable, Sendable, Equatable {
        /// 只发选中的片段。
        case selection
        /// 发整个文件。
        case file

        public static var `default`: Boundary { .selection }

        public var titleKey: LKey {
            switch self {
            case .selection: return .editAssistBoundarySelection
            case .file: return .editAssistBoundaryFile
            }
        }
    }

    // MARK: - 上下文

    /// 一次请求要用的编辑器上下文。
    public struct Context: Equatable, Sendable {
        public var fileName: String
        public var language: TextLanguage
        /// 全文（对齐换行后的，与编辑器里看到的一致）。
        public var fileText: String
        /// 选区（UTF-16）。`length == 0` = 只有光标。
        public var selection: NSRange
        /// 用户的自然语言要求（只有 `rewrite` 用得上）。
        public var instruction: String
        public var boundary: Boundary

        public init(fileName: String,
                    language: TextLanguage,
                    fileText: String,
                    selection: NSRange,
                    instruction: String = "",
                    boundary: Boundary = .default) {
            self.fileName = fileName
            self.language = language
            self.fileText = fileText
            self.selection = selection
            self.instruction = instruction
            self.boundary = boundary
        }

        /// 选中的那一段原文（越界/空选区 ⇒ 空串，不猜）。
        public var selectedText: String {
            let text = fileText as NSString
            guard selection.location >= 0, selection.length > 0,
                  selection.location + selection.length <= text.length else { return "" }
            return text.substring(with: selection)
        }

        /// **真会发出去的正文**（契约 ③）：界面照这个原样显示，不另算一次。
        public var outbound: String {
            switch boundary {
            case .selection: return selectedText.isEmpty ? fileText : selectedText
            case .file: return fileText
            }
        }

        /// 发出去多大（界面那句「将发送：选中 12 行 · 480 字」）。
        public var outboundSummary: OutboundSummary {
            let body = outbound
            let lineCount = body.isEmpty ? 0 : body.components(separatedBy: "\n").count
            return OutboundSummary(scope: boundary, textLength: (body as NSString).length, lineCount: lineCount)
        }
    }

    /// 外发内容的规模读数（只描述，不含正文）。
    public struct OutboundSummary: Equatable, Sendable {
        public var scope: Boundary
        public var textLength: Int
        public var lineCount: Int

        public init(scope: Boundary, textLength: Int, lineCount: Int) {
            self.scope = scope
            self.textLength = textLength
            self.lineCount = lineCount
        }

        /// 界面那一行：`将发送：选中片段 · 12 行 · 480 字`。
        public var displayKey: LKey {
            switch scope {
            case .selection: return .editAssistOutboundSelection
            case .file: return .editAssistOutboundFile
            }
        }

        public var displayArguments: [CVarArg] { [lineCount, textLength] }
    }

    // MARK: - 请求

    /// 发出去的那一份请求（system / user 两段，纯文本）。
    public struct Request: Equatable, Sendable {
        public var action: Action
        public var systemPrompt: String
        public var userPrompt: String
        public var boundary: Boundary
    }

    /// 组装请求。选不出正文（既没选中也读不到文件）⇒ `nil`，调用点如实说「没东西可发」。
    public static func request(action: Action, context: Context) -> Request? {
        guard let prompts = prompts(action: action, context: context) else { return nil }
        return Request(action: action, systemPrompt: prompts.system, userPrompt: prompts.user,
                       boundary: context.boundary)
    }

    /// 两段提示词（`request` 的实底；单测直接看这里）。
    public static func prompts(action: Action, context: Context) -> (system: String, user: String)? {
        let body = context.outbound
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var user = """
        \(action.modelInstruction)

        文件：\(context.fileName)（\(context.language.rawValue)）
        """
        if action.needsInstruction {
            let wanted = context.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wanted.isEmpty else { return nil }
            user += "\n\n改写要求：\(wanted)"
        }
        user += "\n\n```\(codeFenceTag(for: context.language))\n\(body)\n```"
        return (systemPrompt, user)
    }

    /// 系统提示词：三条硬规矩（不给建议外的话、不改无关部分、代码块外不写解释）。
    ///
    /// 与 `AgentSQLGenerator.systemPrompt` 同一体例：模型面口径写死在 Core，
    /// 界面那一侧不再拼一次（两处各写一份 ⇒ 迟早各说一套）。
    public static let systemPrompt = """
    你是 Doyah Studio 编辑区里的编程助手。请严格遵守：
    1. 只回答用户这一次问的那件事；与代码无关的建议一律不提。
    2. 要改代码时，只改为此目的必须改的部分，其余逐字保持原样（不重排、不改风格、不加注释）。
    3. 给出代码时用代码块，代码块之外最多一两句话；不要写「以下是」这类客套话。
    4. 你的输出不会被执行，也不会被自动写进文件：由用户看过差异后自己决定应用。
    """

    /// 代码块的围栏语言标记：**从登记表派生**（语言表是唯一知识源，这里不另写一份别名）。
    /// 认不出（`plainText`）⇒ 空标记 —— 空标记比编一个更像语言的东西更诚实。
    static func codeFenceTag(for language: TextLanguage) -> String {
        language.fileExtensions.first ?? ""
    }

    // MARK: - 结果

    /// 模型回话解析后的产物。
    public enum Result: Equatable, Sendable {
        /// 要写回文件：原文 + 新文 + 差异（人点了才落盘）。
        case proposal(Proposal)
        /// 只出文字（解释 / 修法）。
        case answer(String)
    }

    /// 一条可应用的改动。
    ///
    /// `range` 是**相对原文**的替换范围：`rewrite` = 整个选区（没选区就整篇）；
    /// `complete` = 选区（光标处）之后的插入点，`replacement` 是补上的那一段。
    public struct Proposal: Equatable, Sendable {
        public var action: Action
        public var range: NSRange
        public var original: String
        public var replacement: String
        public var diff: [AgentTextDiff.Line]

        public init(action: Action, range: NSRange, original: String, replacement: String,
                    diff: [AgentTextDiff.Line]) {
            self.action = action
            self.range = range
            self.original = original
            self.replacement = replacement
            self.diff = diff
        }

        /// 差异里的增删行数（界面「+3 ×2」那一格）。
        public var summary: (added: Int, removed: Int) {
            let added = diff.filter { $0.kind == .added }.count
            let removed = diff.filter { $0.kind == .removed }.count
            return (added, removed)
        }

        /// 改完之后这一页的正文（供界面预览与判据对账；不落盘）。
        public func applying(to text: String) -> String {
            let ns = text as NSString
            guard range.location >= 0, range.location + range.length <= ns.length else { return text }
            return ns.replacingCharacters(in: range, with: replacement)
        }
    }

    /// 拒绝的原因（每一条都要能在界面上说成人话）。
    public enum Refusal: Equatable, Sendable {
        /// 没有可发的东西（空文件 / 空选区）。
        case nothingToSend
        /// 改写型动作缺自然语言要求。
        case missingInstruction
        /// 本机就能算（契约 ④：格式化 / 补全 / 行号…）。
        case localCapabilityExists(LKey)
        /// 端点没配。
        case endpointNotConfigured
        /// 模型名没配。
        case modelNotConfigured
        /// 连不上（带原文，界面原样显示，不美化）。
        case unreachable(String)
        /// 模型回了个空。
        case emptyResponse

        public var messageKey: LKey {
            switch self {
            case .nothingToSend: return .editAssistRefusedNothingToSend
            case .missingInstruction: return .editAssistRefusedMissingInstruction
            case .localCapabilityExists: return .editAssistRefusedLocalCapability
            case .endpointNotConfigured: return .editAssistRefusedEndpoint
            case .modelNotConfigured: return .editAssistRefusedModel
            case .unreachable: return .editAssistRefusedUnreachable
            case .emptyResponse: return .editAssistRefusedEmptyResponse
            }
        }
    }

    /// 请求发出前的闸门（契约 ② ③ ④ 都在这里判，判在**发请求之前**）。
    ///
    /// - Parameters:
    ///   - endpoint: 配置里的端点；空 / 非法 ⇒ `.endpointNotConfigured`。
    ///   - model: 配置里的模型名；空 ⇒ `.modelNotConfigured`。
    public static func gate(action: Action, context: Context,
                            endpoint: String, model: String) -> Refusal? {
        if let local = action.localOnlyAlternative { return .localCapabilityExists(local) }
        if context.outbound.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .nothingToSend
        }
        if action.needsInstruction,
           context.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingInstruction
        }
        if endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .endpointNotConfigured }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .modelNotConfigured }
        return nil
    }

    /// 把模型的原话解析成结果。
    ///
    /// 代码围栏（```lang … ```）剥掉；`rewrite` / `complete` 的正文就是新代码。
    /// **解析不出代码也不编**：`rewrite` / `complete` 拿到空 ⇒ `.emptyResponse` 由调用点说。
    public static func result(from response: String, action: Action, context: Context) -> Result? {
        let cleaned = stripFence(response)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard action.writesBack else { return .answer(cleaned) }
        let range = replacementRange(for: action, context: context)
        let original = originalText(in: context, range: range)
        let diff = AgentTextDiff.lines(before: original, after: cleaned)
        return .proposal(Proposal(action: action, range: range, original: original,
                                  replacement: cleaned, diff: diff))
    }

    /// 这条动作要替换哪一段。
    ///
    /// - `rewrite`：有选区就换选区，没选区就换整篇（用户只说了「按这个要求改」）。
    /// - `complete`：**在光标处插入**（零长范围）——补全是往后接，不是把已有代码换掉。
    static func replacementRange(for action: Action, context: Context) -> NSRange {
        let length = (context.fileText as NSString).length
        switch action {
        case .complete:
            let caret = min(max(0, context.selection.location), length)
            return NSRange(location: caret, length: 0)
        case .rewrite, .explain, .fixError:
            if context.selection.length > 0 { return context.selection }
            return NSRange(location: 0, length: length)
        }
    }

    static func originalText(in context: Context, range: NSRange) -> String {
        let ns = context.fileText as NSString
        guard range.location >= 0, range.length > 0, range.location + range.length <= ns.length else { return "" }
        return ns.substring(with: range)
    }

    /// 剥掉最外层的代码围栏，并去掉**首尾空行**。没有围栏就原样返回。
    ///
    /// ⚠️ **只剪空行，不剪空格**：早一版用 `whitespacesAndNewlines` 把两头都剪了，
    /// 于是代码第一行的缩进被吃掉（`    return` → `return`）—— 补全写进文件就是错的。
    /// 判据：`testCompleteInsertsAtCaretInsteadOfReplacing`。
    public static func stripFence(_ raw: String) -> String {
        var text = trimBlankLines(raw)
        guard text.hasPrefix("```") else { return text }
        guard let firstNewline = text.firstIndex(of: "\n") else { return text }
        text = String(text[text.index(after: firstNewline)...])
        if let closing = text.range(of: "```", options: .backwards) {
            text = String(text[..<closing.lowerBound])
        }
        return trimBlankLines(text)
    }

    /// 去掉首尾的**空行**（行里只有空白也算空行），行内缩进逐字保留。
    static func trimBlankLines(_ raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
