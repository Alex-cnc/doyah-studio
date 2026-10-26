import Foundation

/// 九个显示开关的**生效面**（`FR-AGT-UX-CONV-012`）：给定「一条消息 + 当时的读数」和
/// 一份开关值，算出**这一屏该画哪些行**。
///
/// ## 为什么是纯函数、而不是写在视图里
///
/// 契约②③两条是「零占位」「行首栏不抖动」这类**几何**要求，写在 SwiftUI 视图里就只能
/// 靠人眼看；写成「输入 → 行数组」的纯函数之后，判据可以逐行断言：
/// · 关掉思考段 ⇒ 数组里**一行**与思考有关的内容都没有（连空行都没有）；
/// · 时间戳开 / 关 ⇒ 每一行的 `leadingColumnWidth` 一模一样（宽度由常量给，不由内容给）。
///
/// 界面那侧只做一件事：把行数组画出来（`AgentDisplayRow.kind` → 字形 / 缩进 / 折叠头）。
/// **文案一律不进 Core**：Core 只说「这是 N 条工具调用的摘要」，人话由语言表翻。
///
/// 判据：`Tests/AgentDisplayRowsTests`（逐条对契约九项 + 需求书四条验收要点）。
public enum AgentDisplayProjection {

    /// 行首栏（时间戳）的**固定宽度**（字符数，等宽字形下即列数）。
    ///
    /// 它是常量、不随「有没有时间戳」变 —— 这就是契约③「不抖动」的实现口径：
    /// 关掉时间戳之后列照样占着，只是空的（而不是整列收掉、正文左移）。
    public static let timestampColumnWidth = 5

    /// 状态指示三态的机器语义（与字形档无关；字形档只决定画哪个符号）。
    public enum Indicator: String, CaseIterable, Sendable {
        case ready
        case running
        case error
    }

    /// 状态指示字形（`FR-AGT-UX-CONV-012`：三档都必须能表达就绪 / 运行中 / 错误）。
    ///
    /// `ascii` 那一档刻意用两三个字母而不是符号：ASCII 档存在的理由就是
    /// 「终端 / 字体不认符号时照样能读懂」，画 `!` 之类就违背了它自己的用途。
    public static func glyph(for indicator: Indicator, style: AgentIndicatorGlyph) -> String {
        switch (style, indicator) {
        case (.emoji, .ready): return "✅"
        case (.emoji, .running): return "⏳"
        case (.emoji, .error): return "❌"
        case (.unicode, .ready): return "✓"
        case (.unicode, .running): return "⋯"
        case (.unicode, .error): return "✗"
        case (.ascii, .ready): return "ok"
        case (.ascii, .running): return "..."
        case (.ascii, .error): return "err"
        }
    }

    /// 一轮跑着的时候按发送：**打断**（默认）= 先停后发；**排队** = 这一轮结束后接着跑。
    /// 界面据此决定「按发送那一刻先做什么」，判据据此断言两种取值确实分成两条路。
    public static func abortsInFlightBeforeSending(_ preferences: AgentDisplayPreferences) -> Bool {
        preferences.submitWhileRunning == .interrupt
    }

    // MARK: - 行模型

    /// 底栏元数据的三个字段（`FR-AGT-UX-CONV-012`：模型 / 上下文百分比 / 工作目录）。
    public enum MetadataField: String, CaseIterable, Sendable {
        case model
        case contextPercent
        case workingDirectory
    }

    /// 一行。**字段都是这台机器自己产出的数据**（工具名 / 路径 / 时间戳），
    /// 不含任何一句给人读的话 —— 话在语言表里。
    public struct Row: Equatable, Sendable {

        public enum Kind: Equatable, Sendable {
            /// 正文（用户 / 助手）。
            case message(role: AgentChatRole)
            /// 思考段（只在开关打开且真有内容时出现；**关掉是零行，不是空行**）。
            case thinking
            /// 单条工具调用（`全部` 档）。
            case tool(name: String, collapsed: Bool)
            /// 折叠头 + 条数（`摘要` 档：只留折叠头与条数，内容缩在里面）。
            case toolSummary(count: Int, names: [String])
            /// 只留「调用 N 次」（`关` 档：连折叠头都不给，展开不了）。
            case toolCount(count: Int)
            /// 界面自己说的话（如实报的状态 / 原因）。
            case notice
            /// 运行底栏元数据的一段。
            case metadata(field: MetadataField, value: String)
            /// 预览折叠处（`…`，界面画「展开」按钮；`hidden` 是被折起来的行数）。
            case previewGap(hidden: Int)
        }

        public var kind: Kind
        /// 行首栏内容：**开着时间戳**时是补齐到 `timestampColumnWidth` 的时刻串；关掉是空串。
        public var leading: String
        /// 行首栏该占多宽。**与有没有时间戳无关**（契约③）。
        public var leadingColumnWidth: Int
        public var text: String
        /// 工具行的参数摘要 / 拒因（机器码或路径原文）。
        public var detail: String
        public var elapsed: String?
        /// 这一行之后留几行空白（紧凑模式取 0）。
        public var spacingAfter: Int
        /// 还在流式接收（界面画光标 / 不做收尾）。
        public var live: Bool
        /// 被预览折叠掉的行数（0 = 没折）。
        public var hiddenLines: Int

        init(kind: Kind,
             leading: String,
             leadingColumnWidth: Int,
             text: String = "",
             detail: String = "",
             elapsed: String? = nil,
             spacingAfter: Int,
             live: Bool = false,
             hiddenLines: Int = 0) {
            self.kind = kind
            self.leading = leading
            self.leadingColumnWidth = leadingColumnWidth
            self.text = text
            self.detail = detail
            self.elapsed = elapsed
            self.spacingAfter = spacingAfter
            self.live = live
            self.hiddenLines = hiddenLines
        }
    }

    /// 一条工具调用（界面侧从过程行解析出来的那几条数据）。
    public struct ToolLine: Equatable, Sendable {
        public var name: String
        public var summary: String
        public var elapsed: String?
        /// 拒因 / 失败原因（机器码原文）；`nil` = 成功。
        public var failure: String?

        public init(name: String, summary: String, elapsed: String? = nil, failure: String? = nil) {
            self.name = name
            self.summary = summary
            self.elapsed = elapsed
            self.failure = failure
        }
    }

    /// 运行读数（底栏元数据的数据源）。**缺的那一项不写 0、不写占位符**（概设 §8.9 ④）。
    public struct RunMeta: Equatable, Sendable {
        public var model: String?
        public var contextPercent: Int?
        public var workingDirectory: String?

        public init(model: String? = nil, contextPercent: Int? = nil, workingDirectory: String? = nil) {
            self.model = model
            self.contextPercent = contextPercent
            self.workingDirectory = workingDirectory
        }
    }

    /// 一条消息 + 它的旁证。`timestamp` 是**已经格式化好的**时刻串（格式化归界面，
    /// Core 不碰时区与 locale —— 否则同一份判据在不同机器上结果不同）。
    public struct Input: Equatable, Sendable {
        public var message: AgentChatMessage
        public var timestamp: String?
        public var thinking: String?
        public var tools: [ToolLine]
        public var runMeta: RunMeta?

        public init(message: AgentChatMessage,
                    timestamp: String? = nil,
                    thinking: String? = nil,
                    tools: [ToolLine] = [],
                    runMeta: RunMeta? = nil) {
            self.message = message
            self.timestamp = timestamp
            self.thinking = thinking
            self.tools = tools
            self.runMeta = runMeta
        }
    }

    // MARK: - 投影

    /// 一屏该画的行（顺序 = 思考段 → 工具行 → 正文 → 元数据）。
    public static func rows(for input: Input, preferences: AgentDisplayPreferences) -> [Row] {
        let message = input.message

        // ①「流式输出 = 关 ⇒ 收齐再显示」：这一条还在流、正文没定稿 ⇒ **一行都不出**。
        //    不出行比出「半截正文再换成全文」诚实：后者会让人以为自己读过了。
        if message.isStreaming && !preferences.streaming {
            return []
        }

        var rows: [Row] = []
        let spacing = preferences.compact ? 0 : 1
        let leading = leadingText(timestamp: input.timestamp, preferences: preferences)

        // ② 思考段：关 ⇒ **零行**（连空白行都不留）；开但没内容 ⇒ 同样零行
        //    （画一个空框等于告诉人「这里有东西、只是空」）。
        if preferences.thinking, let thinking = input.thinking,
           !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(Row(kind: .thinking,
                            leading: leading,
                            leadingColumnWidth: timestampColumnWidth,
                            text: thinking,
                            spacingAfter: spacing))
        }

        // ⑤ 工具进度三档。
        rows.append(contentsOf: toolRows(input.tools, leading: leading,
                                         preferences: preferences, spacing: spacing))

        // 正文（含长消息预览）。
        rows.append(contentsOf: bodyRows(input, leading: leading, preferences: preferences, spacing: spacing))

        // ⑧ 运行底栏元数据：关 ⇒ 一段都不出；开 ⇒ 只出**有读数**的那几段。
        if preferences.bottomBarMeta, let meta = input.runMeta {
            rows.append(contentsOf: metadataRows(meta, leading: leading))
        }

        return rows
    }

    /// 批量（一屏里有多条消息时用；逐条独立投影，不跨消息合并）。
    public static func rows(for inputs: [Input], preferences: AgentDisplayPreferences) -> [Row] {
        inputs.flatMap { rows(for: $0, preferences: preferences) }
    }

    // MARK: - 各段

    static func leadingText(timestamp: String?, preferences: AgentDisplayPreferences) -> String {
        guard preferences.timestamps, let timestamp, !timestamp.isEmpty else { return "" }
        // 超宽就截断（列宽是契约常量，不能让内容把它撑开 —— 撑开就是「抖动」）。
        if timestamp.count >= timestampColumnWidth {
            return String(timestamp.prefix(timestampColumnWidth))
        }
        return timestamp + String(repeating: " ", count: timestampColumnWidth - timestamp.count)
    }

    static func toolRows(_ tools: [ToolLine],
                         leading: String,
                         preferences: AgentDisplayPreferences,
                         spacing: Int) -> [Row] {
        guard !tools.isEmpty else { return [] }
        switch preferences.toolProgress {
        case .all:
            return tools.map { tool in
                Row(kind: .tool(name: tool.name, collapsed: preferences.compact),
                    leading: leading,
                    leadingColumnWidth: timestampColumnWidth,
                    text: tool.name,
                    detail: tool.failure ?? tool.summary,
                    elapsed: tool.elapsed,
                    spacingAfter: spacing)
            }
        case .summary:
            // 只留折叠头 + 条数：内容折在里面（界面按 `names` 画展开后的那几条）。
            return [Row(kind: .toolSummary(count: tools.count, names: tools.map(\.name)),
                        leading: leading,
                        leadingColumnWidth: timestampColumnWidth,
                        detail: tools.map(\.name).joined(separator: ","),
                        spacingAfter: spacing)]
        case .off:
            // 只留「调用 N 次」：**连折叠头都不给**（给了就等于给了一个能展开的口子）。
            return [Row(kind: .toolCount(count: tools.count),
                        leading: leading,
                        leadingColumnWidth: timestampColumnWidth,
                        detail: "",
                        spacingAfter: spacing)]
        }
    }

    static func bodyRows(_ input: Input,
                         leading: String,
                         preferences: AgentDisplayPreferences,
                         spacing: Int) -> [Row] {
        let message = input.message
        let full = message.text
        guard let edges = preferences.longPreview.edges else {
            return [Row(kind: .message(role: message.role),
                        leading: leading,
                        leadingColumnWidth: timestampColumnWidth,
                        text: full,
                        spacingAfter: spacing,
                        live: message.isStreaming)]
        }
        let lines = full.components(separatedBy: "\n")
        guard lines.count > edges.head + edges.tail else {
            // 不够长 ⇒ **原样出**（预览不该在短消息上加一个折叠口）。
            return [Row(kind: .message(role: message.role),
                        leading: leading,
                        leadingColumnWidth: timestampColumnWidth,
                        text: full,
                        spacingAfter: spacing,
                        live: message.isStreaming)]
        }
        let hidden = lines.count - edges.head - edges.tail
        let head = lines.prefix(edges.head).joined(separator: "\n")
        let tail = lines.suffix(edges.tail).joined(separator: "\n")
        // 折叠处给一个 `…`（契约：折叠处有省略号且可展开）+ 独立一行「折了几行」，
        // 界面据此画展开按钮；`hiddenLines` 同时给机器读。
        return [
            Row(kind: .message(role: message.role),
                leading: leading,
                leadingColumnWidth: timestampColumnWidth,
                text: head,
                spacingAfter: 0,
                live: message.isStreaming,
                hiddenLines: hidden),
            Row(kind: .previewGap(hidden: hidden),
                leading: "",
                leadingColumnWidth: timestampColumnWidth,
                text: "…",
                spacingAfter: 0),
            Row(kind: .message(role: message.role),
                leading: "",
                leadingColumnWidth: timestampColumnWidth,
                text: tail,
                spacingAfter: spacing,
                live: message.isStreaming),
        ]
    }

    static func metadataRows(_ meta: RunMeta, leading: String) -> [Row] {
        var rows: [Row] = []
        if let model = meta.model, !model.isEmpty {
            rows.append(Row(kind: .metadata(field: .model, value: model),
                            leading: leading,
                            leadingColumnWidth: timestampColumnWidth,
                            text: model,
                            spacingAfter: 0))
        }
        if let percent = meta.contextPercent {
            // 有读数才出（`nil` = 读不到 ⇒ 整段不出现，不写 0）。
            rows.append(Row(kind: .metadata(field: .contextPercent, value: "\(percent)%"),
                            leading: leading,
                            leadingColumnWidth: timestampColumnWidth,
                            text: "\(percent)%",
                            spacingAfter: 0))
        }
        if let directory = meta.workingDirectory, !directory.isEmpty {
            rows.append(Row(kind: .metadata(field: .workingDirectory, value: directory),
                            leading: leading,
                            leadingColumnWidth: timestampColumnWidth,
                            text: directory,
                            spacingAfter: 0))
        }
        return rows
    }
}
