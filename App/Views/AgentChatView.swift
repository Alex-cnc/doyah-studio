import SwiftUI
import DoyahCore

/// 对话页签的视图（`FR-AI-25`）：消息流（**流式**）+ 工具卡片（可展开）+ **内联审批** + 输入区。
///
/// 它是 `WorkspaceTab.Kind.agentChat` 的内容 —— **挂在 Home 区页签条上**，
/// 自带**不分栏、不带侧栏**（判据 `AgentChatTests` 扫的就是这一点）。
struct AgentChatView: View {

    @ObservedObject var model: AgentChatModel
    /// 会话已归档 ⇒ **只读**（详设 `§5.3.8` 的 Props）：输入框禁用、发送入口不出现。
    /// 归档流程还没做（`nil` 之外没有别的来源），所以缺省是假；接上之后由宿主传进来。
    var readOnly: Bool = false
    /// 定时 agent 面板的入口（`FR-AI-27`）：面板本身读的是 `AppState` 里的条目与历史。
    @EnvironmentObject private var appState: AppState
    @FocusState private var inputFocused: Bool
    /// 发丝线要按当前外观取色（深色主题用白色低透明叠加，浅色主题用实色）。
    @Environment(\.colorScheme) private var colorScheme
    /// 任务清单是否展开（TUI 的 `▸/▾` 折叠）。跑着时默认收起、只留最后两步。
    @State private var stepsExpanded = false
    /// 会话列表的气泡（§9.1.16 缺口 ②）。
    @State private var showSessions = false
    /// 会话内搜索（§9.1.16 缺口 ③）：开关与查询词。
    @State private var searchActive = false
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            transcript
            // **会话内搜索**（§9.1.16 缺口 ③）：只在打开时占一行，关掉立刻让位给正文。
            if searchActive { searchBar }
            hairline
            // **输入框上面的任务清单**（人类主人 2026-10-17：「DSH-tui 那个任务清单也挺好，
            // 用户可以看到你正在执行到哪一步了」）—— 行内一行一步，只在本轮有步骤时出现。
            taskList
            currentActionRow
            hairline
            composer
            // **信息面**（人类主人 2026-10-17：「参考 Hermes 的 cli 界面」+ dsh-tui 输入框下那条状态行）：
            // 摆在**输入框下面**，与两边一致。
            hairline
            statusBlock
        }
        .background(Theme.surface(.content))
        .onAppear { model.refreshEndpoint() }
        .sheet(isPresented: $appState.isAgentSchedulePresented) {
            AgentScheduleSheet().environmentObject(appState)
        }
    }

    // MARK: - 消息流 + 卡片

    /// 底部锚的 id（自动滚动用）。
    private static let bottomAnchor = "agentChatBottom"

    /// 悬停中的消息（消息级操作只在悬停时露出）与刚复制过的那条。
    @State private var hoveredMessageID: UUID?
    @State private var copiedMessageID: UUID?
    /// 被收起的过程块（按过程消息的 id；**缺省是展开 `▼`** —— 收起的是「看过了」的那几块）。
    @State private var collapsedToolBlocks: Set<UUID> = []

    private var transcript: some View {
        // **跟着最新内容走**（人类主人 2026-10-17 实机反馈：「对话框不自动滚动到最新位置，要手工拖动」）。
        // 读数取 `model.scrollTick`（消息条数 + 正文总长 + 卡片数）—— 流式逐段出现、过程块追加、
        // 卡片新增，任何一种都会让读数变大 ⇒ 一次滚动跟随；只在**内容真的变了**时动手，不空转。
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                    // **空态**（§9.1.16 ⑦）：新会话一片空白时，给一句能直接发出去的起手话。
                    // 空白屏不是「干净」，是「不知道该说什么」—— 别的区域都有空态，这里不该例外。
                    if AgentChatEmptyStateGate.shouldShow(messageCount: model.messages.count,
                                                          cardCount: model.cards.count,
                                                          isRunning: model.isRunning) {
                        startupPanel
                    }
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        // 轮次之间用**一条细横线**分开（§5.3.8.1 ③：分隔用 `Metrics.hairline`，
                        // 不给每条消息套卡片/底纹）。用户提问就是「新一轮」的起点。
                        if message.role == .user, index > 0 {
                            hairline.padding(.vertical, Spacing.m)
                        }
                        // `.id` 是搜索定位用的锚（`⌕` 命中时滚到那一条）。
                        messageRow(message).id(message.id)
                    }
                    ForEach(model.cards) { card in
                        toolCard(card)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
            }
            .onChange(of: model.scrollTick) { _ in follow(proxy) }
            .onChange(of: model.isRunning) { _ in follow(proxy) }
            // 搜索词一变就**定位到第一条命中**（§9.1.16 缺口 ③）。
            .onChange(of: searchText) { _, _ in revealFirstHit(proxy) }
            .onAppear { follow(proxy, animated: false) }
        }
    }

    /// **启动界面**（空会话 / 首启，§5.3.8.1 ⑥）：品牌块 → 信息面（本视图里**唯一**允许描边的块）
    /// → 空态一句。块间距 `Spacing.l`。
    ///
    /// 两处**如实登记**（不许编）：
    ///   · `▼ 可用技能 (N)` 这一格**不画** —— 本端没有技能这一层，仓里零真值源，
    ///     画个 `(0)` 会让人以为「有这一层、只是还没装」；
    ///   · 底部汇总只报**真的数**（工具 / MCP server），不写 `/help for commands`
    ///     （本端没有 slash 命令，写了就是教人去敲一个不存在的东西）。
    private var startupPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            // ① 品牌块：**应用图标 + 大号等宽艺术字 + 一行暗色副题**
            //    （人类主人 2026-10-25：「Chat 欢迎页面也是如此，要出现 Doyah 的图标」；
            //     图标取 `NSApp.applicationIconImage`，与 Dock / 关于本应用同一份）。
            HStack(alignment: .center, spacing: Spacing.s) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: Self.brandWordmark)
                        .font(Theme.font(.display))
                        .foregroundStyle(Theme.text(.bright))
                    Text(L(.agentChatEmptyTitle))
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.secondary))
                }
            }

            // ② 信息面：本视图里唯一描边的块（棕色 1pt 圆角 `Radius.badge`）。
            startupInfoPanel

            // ③ 空态引导一句话（灰色）。
            Text(L(.agentChatEmptyHint))
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.tertiary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    /// 品牌字（等宽艺术字那一格）：产品名大写，字母之间留一格。
    private static let brandWordmark = "D O Y A H   S T U D I O"

    /// 启动界面的信息面（§5.3.8.1 ⑥ 第 2 块）：左三行身份、右三组折叠头（缺真值源的**不画**）、
    /// 底一行汇总、右上角版本号。
    private var startupInfoPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .top, spacing: Spacing.l) {
                // 左：模型 · 品牌 / 数据目录 / Session: <id 前 8 位>
                VStack(alignment: .leading, spacing: Spacing.hair) {
                    Text(startupModelBrandLine)
                    Text(startupDataLine)
                    Text("Session: " + String(model.sessionID.prefix(8)))
                }
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.secondary))

                Spacer(minLength: Spacing.s)

                // 右：折叠头（工具 / MCP server）。技能那一格没有真值源 ⇒ 不画。
                VStack(alignment: .leading, spacing: Spacing.hair) {
                    Text("▼ " + L(.agentChatToolsAvailable) + " (" + String(Self.builtinToolCount) + ")")
                    Text("▼ " + L(.mcpServersTitle) + " (" + String(appState.agentMCPConfiguration.servers.count) + ")")
                }
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.secondary))

                // 右上角版本号
                Text(verbatim: Self.appVersion)
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.tertiary))
            }
            Text(L(.agentChatStartupSummary, String(Self.builtinToolCount),
                   String(appState.agentMCPConfiguration.servers.count)))
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.tertiary))
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.badge)
                .strokeBorder(Theme.status(.warning), lineWidth: 1)
        )
    }

    /// 内置工具数（真值源 = `AgentToolRegistry.standard` 里**启用**的那几条，不是手写数字）。
    private static var builtinToolCount: Int {
        AgentToolRegistry.standard.definitions.filter(\.enabled).count
    }

    /// `模型名 · 品牌`（端点没配好就如实说没配，不假装有模型）。
    private var startupModelBrandLine: String {
        switch model.endpointState {
        case .ready(let modelName, _):
            return L(.agentStatusModel, modelName) + " · " + DoyahIdentity.applicationSupportDirectoryName
        case .notConfigured: return L(.agentChatEndpointNotConfigured)
        case .unreachable: return L(.agentChatEndpointUnreachable)
        }
    }

    /// 数据目录（工作区根；没有工作区就说没有，不编一个路径）。
    private var startupDataLine: String {
        guard let root = WorkspaceStore.shared.rootPath, !root.isEmpty else {
            return L(.agentChatWorkspaceNone)
        }
        return URL(fileURLWithPath: root).lastPathComponent
    }

    /// 版本号（`CFBundleShortVersionString`；取不到就一个 `—`，不编版本）。
    private static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    /// 滚到底。**不抢正在往上翻的人的手**：只在内容变化时执行，且用户点「回到最新」也能主动调它。
    private func follow(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    /// 定位到**第一条**命中（§9.1.16 缺口 ③）。
    ///
    /// 只滚一条：一屏里逐条跳比不定位更烦；人要看下一条自己接着敲就是了。
    /// 一条都没命中就**不动滚动位置**（画面没理由因为「没找到」跳一下）。
    private func revealFirstHit(_ proxy: ScrollViewProxy) {
        guard searchActive, let id = AgentTranscriptSearch.firstMatchID(searchText, in: model.messages) else { return }
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
    }

    /// 一条助手消息的两个动作：复制 / 重发（§9.1.16 ③）。
    @ViewBuilder
    private func messageActions(_ message: AgentChatMessage) -> some View {
        HStack(spacing: Spacing.m) {
            Button {
                // **复制的是 Markdown 源码**（§5.3.8）：用户要拿去粘回终端 / 贴进文件，
                // 渲染后的可见文本（去掉的 `**`、代码块加的抬头）不是他要的东西。
                // 所以这里取 `message.text` 原文，**不**取渲染结果。
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
                copiedMessageID = message.id
            } label: {
                Text(copiedMessageID == message.id ? "✓" : "⧉")
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
            }
            .buttonStyle(.plain)
            .help(L(.agentMessageCopy))

            Button {
                Task { await model.resend(assistantMessageID: message.id) }
            } label: {
                Text("↻")
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
            }
            .buttonStyle(.plain)
            .disabled(model.isRunning)
            .help(L(.agentMessageResend))
        }
        .opacity(hoveredMessageID == message.id ? 1 : 0)
        .onHover { inside in hoveredMessageID = inside ? message.id : (hoveredMessageID == message.id ? nil : hoveredMessageID) }
        .accessibilityElement(children: .contain)
    }

    // MARK: - 转写区：Hermes TUI 的行首栏语法

    /// 正文用等宽 —— TUI 只有一种字体，等宽本身就是它的观感（人类主人 2026-10-22：
    /// 「我希望 Agent 的界面像 Hermes -tui 的界面」）。
    private static let transcriptFont = Theme.font(.mono)

    /// 行首栏：**两个等宽字符**的固定列宽（§5.3.8.1 ②），正文从同一列起。
    /// 取 `Spacing.l`（16pt ≈ 13pt 等宽字两个字符宽）—— 版式语汇不许在视图里写裸数字（§5.3.8.1 ⑧）。
    private static let gutterWidth: CGFloat = Spacing.l

    /// 行首栏的一格字形。宽度**固定**（两字符列），所以「有字形」与「没字形」的行正文仍然对齐。
    private func gutter(_ glyph: String, _ tint: Color) -> some View {
        Text(glyph)
            .font(Self.transcriptFont)
            .foregroundStyle(tint)
            .frame(width: Self.gutterWidth, alignment: .leading)
    }

    /// 一条把消息分开的**细横线**（§5.3.8.1 ③：分隔用横线，不是卡片）。
    private var hairline: some View {
        Rectangle()
            .fill(Theme.hairline(colorScheme))
            .frame(height: Metrics.hairline)
    }

    @ViewBuilder
    private func messageRow(_ message: AgentChatMessage) -> some View {
        switch message.role {
        case .user:
            // 行首栏是 `>`（§5.3.8.1 ②），**不是右对齐气泡**，也不是每条一个卡片。
            //
            // 用户**自己的字**仍走 `AgentTranscriptText`（原样显示，不改写他的话）；
            // 富文本渲染只针对**模型回复** —— 见下面 `.assistant` 那一支。
            HStack(alignment: .top, spacing: 0) {
                gutter(">", Theme.accentColor)
                AgentTranscriptText(text: message.text, font: Self.transcriptFont, highlight: highlightNeedle)
                Spacer(minLength: 0)
            }
        case .assistant:
            // **正文按 Markdown 渲染**（§5.3.8）：解析只走契约层 `MarkdownDocument`，
            // 呈现换成一份等宽口径 —— 绝不再把 `**粗体**` / ```` ```lang ```` 的源码直出。
            // 行首栏**不给字形**：助手正文顶格起（§5.3.8.1 ② 的表里只有用户行与工具行有字形）。
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if message.isStreaming && message.text.isEmpty {
                        // 六态「加载中」：**占位行**（不是空白气泡 —— 空白让人以为卡住了）。
                        // 这一句只在「开跑但还没吐第一个字」时出现，第一个增量到了就换成正文。
                        HStack(spacing: Spacing.s) {
                            BrailleSpinner(tint: Theme.text(.secondary))
                            Text(L(.agentChatStreamingPlaceholder))
                                .font(Self.transcriptFont)
                                .foregroundStyle(Theme.text(.secondary))
                        }
                    } else {
                        AgentMarkdownBody(
                            text: message.text,
                            isStreaming: message.isStreaming,
                            font: Self.transcriptFont,
                            highlight: highlightNeedle
                        )
                    }
                    if message.isStreaming {
                        // 流式光标：**逐段**出现时它一直在（`FR-AI-25` ②）。
                        // 摆在正文下一行的行首：块渲染是多行的，光标跟在最后一段的末尾会随重排跳动。
                        Text("▌").font(Self.transcriptFont).foregroundStyle(Theme.text(.secondary))
                    }
                }
                Spacer(minLength: 0)
                // **消息级操作**（§9.1.16 ③）：悬停才出现，不常驻 —— TUI 的正文里不该挂按钮条。
                // 流式中不给（那一条还没有可复制的结果），正在跑时「重发」也不给（会撞正在跑的那一轮）。
                if !message.isStreaming {
                    messageActions(message)
                }
            }
        case .tool:
            // 工具调用 = **一组过程块**（§5.3.8.1 ②）：折叠头 `└─ ▼`，条目 `├─ ⏺` / `└─ ⏺`。
            // **不描边、不铺底**（§5.3.8.1 ③：终端语汇里没有通栏卡片）。
            toolBlock(message)
        case .notice:
            noticeRow(message)
        }
    }

    /// 时间线事件（`◈` + 灰字，不带栏）。**这一轮没跑成**另说：
    ///
    /// 六态「错误」那一档要的是「原因 + 可重试入口，已产生的部分消息照常显示」——
    /// 以前 `failed:<机器码>` 落到 `noticeText` 的 `default` 分支被原样印出来，
    /// 人既看不懂、也没有下一次动作。这里把它拆成「一句人话 + 原因 + ↻ 重试」。
    @ViewBuilder
    private func noticeRow(_ message: AgentChatMessage) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // 时间线事件的字形（§5.3.8.1 ②）：告警 `⚠`，其余 `▼`。
            gutter(Self.failureReason(in: message.text) == nil ? "▼" : "⚠", Theme.text(.secondary))
            if let reason = Self.failureReason(in: message.text) {
                HStack(spacing: Spacing.s) {
                    Text(L(.agentChatTurnFailed) + " · " + reason)
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.status(.warning))
                        .textSelection(.enabled)
                    // 重试 = 拿上一轮的原话再跑一轮（`retryLastTurn`），不是「把输入框里的字发出去」。
                    Button {
                        Task { await model.retryLastTurn() }
                    } label: {
                        Text("↻ " + L(.commonRetry))
                            .font(Self.transcriptFont)
                            .foregroundStyle(Theme.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRunning)
                    .help(L(.commonRetry))
                }
            } else {
                Text(TranscriptHighlight.apply(highlightNeedle, to: AttributedString(noticeText(message.text))))
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
            }
        }
    }

    /// 一组工具调用（§5.3.8.1 ②）：折叠头 `└─ ▼ 工具 (3)`，条目 `├─ ⏺` / `└─ ⏺`。
    ///
    /// **不描边、不铺底**（§5.3.8.1 ③：终端语汇里没有通栏卡片）；缩进取令牌 `Metrics.listIndent`。
    /// 条目文本由 `AgentToolLines` 从 Core 写的那一行过程里拆出来（认不出就原样画，不猜）。
    @ViewBuilder
    private func toolBlock(_ message: AgentChatMessage) -> some View {
        let rows = AgentToolLines.rows(message.text)
        let expanded = !collapsedToolBlocks.contains(message.id)
        let rawLines = message.text.components(separatedBy: "\n")

        VStack(alignment: .leading, spacing: Spacing.hair) {
            Button {
                if expanded {
                    collapsedToolBlocks.insert(message.id)
                } else {
                    collapsedToolBlocks.remove(message.id)
                }
            } label: {
                HStack(spacing: Spacing.s) {
                    Text(expanded ? "└─ ▼" : "└─ ▶")
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.secondary))
                    Text(L(.agentChatToolBlockTitle) + " (" + String(rows.isEmpty ? rawLines.count : rows.count) + ")")
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.secondary))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? L(.agentChatCollapse) : L(.agentChatExpand))

            if expanded {
                if rows.isEmpty {
                    // 认不出的过程行：**原样**逐行画（Core 换了格式时，这里既不吞字也不猜）。
                    ForEach(Array(rawLines.enumerated()), id: \.offset) { _, line in
                        Text(TranscriptHighlight.apply(highlightNeedle, to: AttributedString(line)))
                            .font(Self.transcriptFont)
                            .foregroundStyle(Theme.text(.secondary))
                            .textSelection(.enabled)
                            .padding(.leading, Metrics.listIndent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        toolEntryRow(row, isLast: index == rows.count - 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 一条工具条目：`├─ ⏺ <名>("<参数摘要>") (<耗时>s)`（末条用 `└─`）。
    private func toolEntryRow(_ row: AgentToolLine, isLast: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(isLast ? "└─ ⏺" : "├─ ⏺")
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.tertiary))
            Text(TranscriptHighlight.apply(highlightNeedle,
                                           to: AttributedString(AgentToolLines.callText(row))))
                .font(Self.transcriptFont)
                .foregroundStyle(row.outcome == .running ? Theme.text(.secondary) : Theme.text(.primary))
                .textSelection(.enabled)
            // **失败逐条标在自己这一行上**（六态「部分失败」：不许整轮报失败、也不许丢失败条目）。
            // 行内只放**短码**（一行要看得完），整句解释进 `.help`。
            if case let .failure(reason) = row.outcome {
                Text("✗ " + refusalCode(reason))
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.status(.danger))
                    .help(refusalHelp(reason) ?? "")
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Metrics.listRowHeight)
        .padding(.leading, Metrics.listIndent)
    }

    /// 拒因里的 `denied:` 前缀（`Core` 的 `toolFinished` 事件把它拼在机器码前面）。
    private static let deniedPrefix = "denied:"

    /// 行内那个**短码**：剥掉 `denied:` 包装词，其余原样（宁可见码，也不编一句像解释的话）。
    private func refusalCode(_ raw: String) -> String {
        raw.hasPrefix(Self.deniedPrefix) ? String(raw.dropFirst(Self.deniedPrefix.count)) : raw
    }

    /// 短码 → 整句解释（只翻能确定的那两种；其余返回 `nil`，不挂提示）。
    private func refusalHelp(_ raw: String) -> String? {
        switch refusalCode(raw) {
        case "writeConflict": return L(.agentChatWriteBusy)
        case "staleTarget": return L(.agentChatWriteStale)
        default: return nil
        }
    }

    /// `failed:<原因>` 的前缀（`Core/AgentChat.swift` 的 `.failed` 事件拼的）。
    ///
    /// **只剥前缀，不改原因** —— 认不出的原因原样给人看，不在这儿编一句「网络错误」当解释
    /// （编出来的解释比机器码更坏：它看起来像我们知道发生了什么）。
    static let failurePrefix = "failed:"

    static func failureReason(in code: String) -> String? {
        guard code.hasPrefix(failurePrefix) else { return nil }
        return String(code.dropFirst(failurePrefix.count))
    }

    /// 角色 / 状态这类**机器码**在这里翻成给人看的话（码本身留在 Core，判据判的是码）。
    private func noticeText(_ code: String) -> String {
        switch code {
        case "finished": return L(.agentChatDone)
        case "endpointNotConfigured": return L(.agentChatEndpointNotConfigured)
        case "endpointUnreachable": return L(.agentChatEndpointUnreachable)
        // 撤销那三种结局各说各的（`FR-AI-25` ⑤）：被又改过 ≠ 写盘失败 ≠ 宿主没接。
        case "drifted": return L(.agentChatUndoDrifted)
        case "failed": return L(.agentChatUndoFailed)
        case "noUndoer": return L(.agentChatUndoUnavailable)
        // `FR-AI-31` ①：写类动作「没写成」的三种原因，各说各的。
        case "writeConflict": return L(.agentChatWriteBusy)
        case "staleTarget": return L(.agentChatWriteStale)
        case "applyFailed": return L(.agentChatApplyFailed)
        case "noApplier": return L(.agentChatApplyFailed)
        // `FR-AI-31` ②：**它说做完了，但拿不出可复核的证据** —— 这一条要让人看懂，不是一声「完成」。
        case "completionUnverified": return L(.agentChatCompletionUnverified)
        // §9.1.16 缺口 ②：切到一条读不出来的会话 —— 如实说，界面留在原地。
        case "sessionUnavailable": return L(.agentSessionUnavailable)
        // `FR-AI-31` ③：**跑飞了** 五种形态各说各的（读数在状态块那一行，这一句进消息流）。
        case "monitor:stalled": return L(.agentChatMonitorStalled)
        case "monitor:spinning": return L(.agentChatMonitorSpinning)
        case "monitor:retryStorm": return L(.agentChatMonitorRetryStorm)
        case "monitor:budgetApproaching": return L(.agentChatMonitorBudgetApproaching)
        case "monitor:budgetExhausted": return L(.agentChatMonitorBudgetExhausted)
        default:
            // `FR-AI-18` ②③④：循环「如实停」的三种机器码（`stepLimit:3` / `tokenLimit:10` /
            // `cancelled`）此前落到这里原样印出去 ⇒ 界面上写着 `cancelled`，人既看不懂也看不出
            // 是不是自己按的停。解析只认 Core 的那一处（`AgentLoopStop.parse(reason:)`），
            // 本函数只负责把解析结果翻成话 —— 前缀判断不许在这里写第二份。
            if let stop = AgentLoopStop.parse(reason: code) {
                switch stop {
                // 实参一律**显式构造**（`Int(...)` / `String(...)`）：本仓的类型判定只认类型级与
                // 全局函数，模式绑定变量（`let limit`）它判不出类型 ⇒ 会把 `%d` 槽喂进未登记形状。
                case .cancelled: return L(.agentChatStopCancelled)
                case .stepLimit(let limit): return L(.agentChatStopStepLimit, Int(limit))
                case .tokenLimit(let limit): return L(.agentChatStopTokenLimit, Int(limit))
                case .quotaLimit(let detail): return L(.agentChatQuotaStopped, String(detail))
                }
            }
            // 认不出的码原样交回（宁可见机器码，也不假装成别的话 —— 但已知的四种一个都不许落到这里）。
            return code
        }
    }

    /// 长跑告警的**一句话读数**（`FR-AI-31` ③）：机器码在这里翻成人话，观测值与阈值原样带出来。
    private func monitorText(_ reading: AgentChatMonitorReading) -> String {
        switch reading.kind {
        case "stalled":
            return L(.agentMonitorStalled, "\(reading.observed)", "\(reading.threshold)")
        case "spinning":
            return L(.agentMonitorSpinning, "\(reading.observed)")
        case "retryStorm":
            return L(.agentMonitorRetryStorm, "\(reading.observed)")
        case "budgetApproaching":
            return L(.agentMonitorBudget, "\(reading.observed)", "\(reading.threshold)")
        case "budgetExhausted":
            return L(.agentMonitorBudgetOut, "\(reading.observed)", "\(reading.threshold)")
        default:
            return reading.kind
        }
    }

    /// 这张卡是不是**在等人点**（只有这种才值得用强调色与描边）。
    private func pendingApproval(_ card: AgentToolCard) -> Bool {
        if case .pendingApproval = card.outcome { return true }
        return false
    }

    @ViewBuilder
    private func toolCard(_ card: AgentToolCard) -> some View {
        // §7.9.10：工具卡也守在行首栏里 —— `⚡` 占 14pt，卡体从同一条竖线起；
        // 状态用**文字标记**（`✓ ✗ ◐ ⚠`）而不是 SF Symbol，图标会带自己的光学重心，破了等宽的列。
        // 可以描边，**不许底纹**：卡体只留一圈 hairline 圆角，不再铺 panel 底色。
        HStack(alignment: .top, spacing: 0) {
            // 卡片行首栏用「要人动手」的告警字形（§5.3.8.1 ②：`⚠`），其余候补用 `▼`。
            gutter(pendingApproval(card) ? "⚠" : "▼",
                   pendingApproval(card) ? Theme.accentColor : Theme.text(.secondary))
            toolCardBody(card)
        }
    }

    @ViewBuilder
    private func toolCardBody(_ card: AgentToolCard) -> some View {
        // **只有「等审批」才是一块框**（那是一条要人动手的决定）；跑完的调用在 TUI 里就是
        // 两行字：`⚡ 工具名` + `⎿ 结果`。以前每张卡都描一个通栏框 ⇒ 看起来像列表控件，
        // 而不是终端里滚过去的一段输出。
        VStack(alignment: .leading, spacing: Spacing.hair) {
            HStack(spacing: Spacing.s) {
                Text(mark(for: card))
                    .font(Self.transcriptFont)
                    .foregroundStyle(tint(for: card))
                Button {
                    model.toggle(card.id)
                } label: {
                    Text(card.expanded ? "▾" : "▸")
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.secondary))
                }
                .buttonStyle(.plain)
                .help(card.expanded ? L(.agentChatCollapse) : L(.agentChatExpand))
                if !card.arguments.isEmpty {
                    Text(card.arguments)
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.secondary))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            // `⎿ ` 是 TUI 的续行标记（`thinking.tsx` 用 `├─ / └─`，工具结果用同一个位置）。
            // **失败原因逐条留在自己这一行上**（六态「部分失败」：不许整轮报失败、也不许丢失败条目）。
            Text("⎿ " + statusText(for: card))
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.tertiary))
                .padding(.leading, Spacing.l)
            if card.expanded, let preview = card.approvalPreview {
                Text(preview)
                    .font(Self.transcriptFont)
                    .textSelection(.enabled)
                    .padding(Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.badge)
                            .strokeBorder(Theme.hairline(colorScheme), lineWidth: 1)
                    )
                    .padding(.leading, Spacing.l)
            } else if card.expanded, !card.arguments.isEmpty {
                Text(card.arguments)
                    .font(Self.transcriptFont)
                    .textSelection(.enabled)
                    .foregroundStyle(Theme.text(.secondary))
                    .padding(.leading, Spacing.l)
            }
            // ③「展开可见**用的哪个模型与端点**」（`FR-AI-25` ③）：每张卡展开都带这一行 ——
            // 不能只靠底部状态行（那里是「这一轮」的读数，卡片可能属于上一轮 / 上一个端点）。
            // 端点没配 / 连不上就**如实说**，不写死、不假装在跑。
            if card.expanded, let line = endpointLine {
                Text(line)
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
                    .textSelection(.enabled)
            }
            if case .pendingApproval = card.outcome {
                HStack(spacing: Spacing.s) {
                    Text(L(.agentChatApprovalPending)).font(Self.transcriptFont).foregroundStyle(Theme.text(.secondary))
                    ToolbarIconButton(systemName: "checkmark.circle", help: L(.agentChatApprovalApprove)) { model.approve(card.id) }
                        .controlSize(.small)
                    ToolbarIconButton(systemName: "xmark.circle", help: L(.agentChatApprovalDeny)) { model.deny(card.id) }
                        .controlSize(.small)
                }
            }
            if case .applied = card.outcome {
                HStack(spacing: Spacing.s) {
                    Text(L(.agentChatApprovalApplied)).font(Self.transcriptFont).foregroundStyle(Theme.text(.secondary))
                    // **一步撤销**（`FR-AI-25` ⑤）：点了就把这次写入退回去，文件逐字节回到应用前。
                    // 只出现在「已应用」这一档 —— 别的状态没有可撤的东西。
                    ToolbarIconButton(systemName: "arrow.uturn.backward", help: L(.agentChatUndo)) {
                        model.undo(card.id)
                    }
                    .controlSize(.small)
                }
            }
            if case .undone = card.outcome {
                Text(L(.agentChatUndone)).font(Self.transcriptFont).foregroundStyle(Theme.text(.secondary))
            }
        }
        // **只有等审批的卡才描边**（TUI 里其余工具调用只是两行字）。
        // 通栏底纹与通栏边框都是 GUI 语法：终端里没有「一条横贯整屏的框」这种东西。
        // 只有等审批的卡才留内边距（它是一块要人动手的框）；令牌取 `Spacing.s`，不写裸数字。
        .padding(.vertical, pendingApproval(card) ? Spacing.s : 0)
        .padding(.horizontal, pendingApproval(card) ? Spacing.s : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.badge)
                .strokeBorder(pendingApproval(card) ? Theme.hairline(colorScheme) : .clear, lineWidth: 1)
        )
    }

    /// 卡片上那一行「用的哪个模型与端点」（`FR-AI-25` ③）。
    /// 端点没配 / 连不上 ⇒ 如实说（不写死、不假装在跑），与底部状态行同一个真值源（`model.endpointState`）。
    private var endpointLine: String? {
        switch model.endpointState {
        case .ready(let model, let endpoint):
            return L(.agentStatusModel, model) + " · " + (URL(string: endpoint)?.host ?? endpoint)
        case .notConfigured:
            return L(.agentChatEndpointNotConfigured)
        case .unreachable:
            return L(.agentChatEndpointUnreachable)
        }
    }

    /// 工具卡的状态标记（文字，不用 SF Symbol —— §7.9.10 硬规则 ②：一律等宽）。
    private func mark(for card: AgentToolCard) -> String {
        switch card.outcome {
        case .running: return "◐"
        case .executed: return "✓"
        case .denied: return "✗"
        case .pendingApproval: return "⚠"
        case .approved: return "✓"
        case .applied: return "✓"
        case .undone: return "↩"
        }
    }

    private func tint(for card: AgentToolCard) -> Color {
        switch card.outcome {
        case .running: return Theme.accentColor
        case .executed, .applied, .approved: return Theme.status(.success)
        case .denied: return Theme.status(.danger)
        case .pendingApproval: return Theme.status(.warning)
        case .undone: return Theme.text(.secondary)
        }
    }

    /// 卡片那一行 `⎿` 的状态文字（**人话优先，码兜底**）。
    ///
    /// `.denied` 的机器码形如 `denied:writeConflict` —— 把 `denied:` 这个包装词剥掉、
    /// 能翻的两种（写冲突 / 基线过期）翻成人话；认不出的仍然原样给出来
    /// （宁可见码，也不编一句听起来像解释的话）。
    private func statusText(for card: AgentToolCard) -> String {
        guard case .denied(let reason) = card.outcome else { return card.statusCode }
        switch reason {
        case "writeConflict": return L(.agentChatWriteBusy)
        case "staleTarget": return L(.agentChatWriteStale)
        default: return reason
        }
    }

    // MARK: - 任务清单（走到哪了）

    @ViewBuilder
    private var taskList: some View {
        if !model.steps.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.hair) {
                // 表头就是 TUI 的 todo 面板那一行：`▸ 任务清单 (3/5)`，灰字带计数。
                Button {
                    stepsExpanded.toggle()
                } label: {
                    HStack(spacing: Spacing.s) {
                        Text(stepsExpanded ? "▾" : "▸")
                            .font(Self.transcriptFont)
                            .foregroundStyle(Theme.accentColor)
                        Text(L(.agentChatStepsTitle, "\(model.steps.count)"))
                            .font(Self.transcriptFont)
                        Text("(\(doneStepCount)/\(model.steps.count))")
                            .font(Self.transcriptFont)
                            .foregroundStyle(Theme.text(.secondary))
                        if let seconds = model.lastElapsedSeconds {
                            Text(L(.agentStatusElapsed, String(format: "%.1f", seconds)))
                                .font(Self.transcriptFont)
                                .foregroundStyle(Theme.text(.secondary))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)

                // **跑着**：只留最后 2 步（知道它此刻在干什么就够了）；**跑完**：收进折叠里。
                if stepsExpanded || model.isRunning {
                    let visible = model.isRunning && !stepsExpanded
                        ? Array(model.steps.suffix(2))
                        : model.steps
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, step in
                        stepRow(step, isLast: index == visible.count - 1)
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var doneStepCount: Int {
        model.steps.filter { $0.status == .done }.count
    }

    @ViewBuilder
    private func stepRow(_ step: AgentChatStep, isLast: Bool) -> some View {
        HStack(spacing: Spacing.s) {
            // 树轨：TUI 的 `├─` / `└─`
            Text(isLast ? "└─" : "├─")
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.tertiary))
            Text(stepMark(for: step))
                .font(Self.transcriptFont)
                .foregroundStyle(tint(for: step))
            Text(step.tools.joined(separator: " · "))
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.secondary))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, Spacing.m)
    }

    /// 状态字形照 TUI：跑着是旋转的那个（这里用静态 `◐`，转起来由 `currentActionRow` 负责），
    /// 成了 `✓`、失败 `✗`。
    private func stepMark(for step: AgentChatStep) -> String {
        switch step.status {
        case .running: return "◐"
        case .done: return "✓"
        case .failed: return "✗"
        }
    }

    private func tint(for step: AgentChatStep) -> Color {
        switch step.status {
        case .running: return Theme.accentColor
        case .done: return Theme.text(.secondary)
        case .failed: return Theme.status(.warning)
        }
    }

    /// **当前动作**（输入框上方**一行**）—— dsh-tui 的 `🌙 … Firing a command … · 1s` 那一格。
    /// 命门是**就地更新、不追加**：跑一百跳也只占这一行（不刷屏）。
    @ViewBuilder
    private var currentActionRow: some View {
        if let action = model.currentAction {
            HStack(spacing: Spacing.s) {
                BrailleSpinner()
                Text(action)
                    .font(Self.transcriptFont)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(L(.agentChatRunning2))
                    .font(Self.transcriptFont).foregroundStyle(Theme.text(.secondary))
                Spacer()
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.xs)
        }
    }

    // MARK: - 搜索条 / 会话列表（§9.1.16 缺口 ②③）

    /// 当前要染的词（关掉搜索就是 `nil` —— 关掉之后正文立刻回到原样）。
    private var highlightNeedle: String? { searchActive ? searchText : nil }

    /// 命中读数：**有命中报条数，没命中明说**（沉默会让人以为搜索坏了）。
    private var searchHitLine: some View {
        let count = AgentTranscriptSearch.total(searchText, in: model.messages)
        let typing = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Text(typing ? "" : (count > 0 ? "\(count)" : L(.agentChatSearchNoHits)))
            .font(Self.transcriptFont)
            .foregroundStyle(count > 0 ? Theme.text(.secondary) : Theme.status(.warning))
    }

    private var searchBar: some View {
        HStack(spacing: Spacing.s) {
            Text("⌕").font(Self.transcriptFont).foregroundStyle(Theme.text(.secondary))
            TextField(L(.agentChatSearchPlaceholder), text: $searchText)
                .textFieldStyle(.plain)
                .font(Self.transcriptFont)
            searchHitLine
            glyphButton("✕", help: L(.agentChatSearchToggle)) {
                searchActive = false
                searchText = ""
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
    }

    /// 会话列表（气泡）：标题 + 时间 + 跳数；空列表给空态；顶部一条「新会话」。
    ///
    /// 为什么用气泡而不是分栏：对话页签的契约是**不自带侧栏 / 分栏**（`FR-AI-25` ①），
    /// 一份「看历史」的列表没理由为它破例 —— 用完即走的浮层更合这条契约。
    private var sessionsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.s) {
                Text(L(.agentChatSessionsTitle))
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
                Spacer(minLength: 0)
                Button {
                    model.startNewSession()
                    showSessions = false
                } label: {
                    Text("＋ " + L(.agentChatSessionsNew))
                        .font(Self.transcriptFont)
                }
                .buttonStyle(.plain)
                .disabled(!model.canSwitchSession)
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            Divider()

            if model.sessions.isEmpty {
                Text(L(.agentChatSessionsEmpty))
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.s)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.sessions) { session in
                            sessionRow(session)
                        }
                    }
                }
                .frame(maxHeight: Spacing.xxl * 8)
            }

            if model.sessionsSkippedFiles > 0 {
                Divider()
                // 坏文件**报数**（跳过 ≠ 通过）：不静默吞掉读不出来的那些。
                Text("\(model.sessionsSkippedFiles) " + L(.agentChatSessionsSkippedUnit))
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.status(.warning))
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.xs)
            }
        }
        .frame(minWidth: 320, maxWidth: 380)
        .background(Theme.surface(.panel))
    }

    private func sessionRow(_ session: AgentSessionSummary) -> some View {
        Button {
            model.openSession(session.id, workspacePath: WorkspaceStore.shared.rootPath)
            showSessions = false
        } label: {
            VStack(alignment: .leading, spacing: Spacing.hair) {
                Text(session.title)
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: Spacing.s) {
                    Text(Self.sessionTimeText(session.updatedAt))
                    Text("\(session.turnCount) " + L(.agentChatSessionTurnsUnit))
                }
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.tertiary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canSwitchSession)
    }

    /// 列表里的时间：**今天只给时分、别的日子带日期** —— 一列里全是「2026-10-22 11:03」看不出远近。
    private static func sessionTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 状态行（§5.3.8.1 ④：一行、字段顺序固定）

    /// 底部状态行：**一行**，按契约顺序 `— ready | 模型 | 已用/窗口 | [█░░] 百分比 | ⊙ 缓存 |
    /// ↑ t/s | voice off`，右端对齐会话名 / 工作目录。
    ///
    /// 三条口径（都是「不许自说自话」那一族）：
    ///   · **没读数的那一格整段不出现**（不写 `0`、不写 `n/a`）—— 组装在 `AgentChatStatusLine`；
    ///   · **花费不进来**（2026-10-25 令：成本只看 token），状态行一个字都不提钱；
    ///   · 别的条款要求「不许静默」的四条读数（压缩 / 续跑 / 完成判据 / 长跑监控）**跟在固定七格之后**，
    ///     顺序不乱、一个都不丢（它们是被别处判据钉着的东西，版式重排不许把它们吞掉）。
    private var statusBlock: some View {
        HStack(spacing: Spacing.s) {
            Text("— " + AgentChatStatusLine.fields(statusInput, extras: statusExtras).joined(separator: " | "))
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)

            Spacer(minLength: Spacing.s)

            // 会话记录（§9.1.16 缺口 ②）：打开时现读一次盘 —— 列表要新鲜，
            // 别拿上次打开时的那份（跑完一轮就多一条会话）。
            glyphButton("⌸", help: L(.agentChatSessionsTitle)) {
                model.reloadSessions(workspacePath: WorkspaceStore.shared.rootPath)
                showSessions = true
            }
            .popover(isPresented: $showSessions, arrowEdge: .bottom) {
                sessionsPopover
            }
            // 会话内搜索（§9.1.16 缺口 ③）：关掉就清词，正文立刻回原样。
            glyphButton("⌕", help: L(.agentChatSearchToggle)) {
                searchActive.toggle()
                if !searchActive { searchText = "" }
            }

            // **右端 = 会话名 / 工作目录**（§5.3.8.1 ④）。两个入口按钮排在它左边，是为了
            // 让「会话名在右端」这条位置口径成立（入口不能消失：那是 §9.1.16 ②③ 的缺口入口）。
            if let anchor = statusAnchor {
                Text("— " + anchor)
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(anchor)
            }
        }
        .font(Self.transcriptFont)
        .foregroundStyle(Theme.text(.secondary))
        .lineLimit(1)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
    }

    /// 状态行那七格的输入（**只传有真值源的**，`nil` 就是没有）。
    private var statusInput: AgentChatStatusInput {
        let readings = model.modelReadings
        var modelName: String?
        if case .ready(let name, _) = model.endpointState { modelName = name }
        return AgentChatStatusInput(
            isRunning: model.isRunning,
            elapsed: model.lastElapsedSeconds.map { String(format: "%.1fs", $0) },
            model: modelName,
            contextUsed: readings.contextUsed,
            contextWindow: readings.contextWindow,
            contextPercent: readings.contextPercent,
            cachePercent: readings.cacheHitPercent,
            tokensPerSecond: model.tokensPerSecond
        )
    }

    /// 固定七格之后的「不许静默」读数（压缩 / 续跑 / 完成判据 / 长跑监控 / 本会话 token 账 / 写确认档）。
    private var statusExtras: [String] {
        var extras: [String] = []
        // `NFR-AI-08` ③：压了几段、约省多少 token —— 压缩不许静默（`nil` 不留空壳）。
        if let compression = model.contextCompression {
            extras.append(L(.agentStatusCompressed,
                            "\(compression.entries)",
                            "\(compression.estimatedTokensSaved)"))
        }
        // `NFR-AI-08` ⑤：续上第几跳、退回几跳 —— 续跑不许静默。
        if let resume = model.resumeReading {
            extras.append(L(.agentStatusResumed,
                            "\(resume.fromStep + 1)",
                            "\(resume.skippedSteps)"))
        }
        // `FR-AI-31` ②：模型说完成时的复核结论（跑完 ≠ 做成）。
        if let completion = model.completionReading, completion.isVerified || completion.isUnverified {
            extras.append(completion.isVerified
                          ? L(.agentStatusCompletionVerified, "\(completion.citations)")
                          : L(.agentStatusCompletionUnverified))
        }
        // `FR-AI-31` ③：卡住 / 空转 / 反复重试 / 配额将尽 —— 跑飞不许静默。
        if let monitor = model.monitorReading {
            extras.append(L(.agentStatusMonitor, monitorText(monitor)))
        }
        // 本会话 token 账（`NFR-AI-04`）：有轮次没报用量时明说（不把缺值当 0）。
        if model.sessionUsage.requests > 0 {
            extras.append(L(.agentStatusSession,
                            "\(model.sessionUsage.requests)",
                            "\(model.sessionUsage.promptTokens)",
                            "\(model.sessionUsage.completionTokens)",
                            "\(model.sessionUsage.totalTokens)"))
            if model.sessionUsage.responsesWithoutUsage > 0 {
                extras.append(L(.agentStatusNoUsage))
            }
        }
        // 写确认档：关掉「每次确认」时这一格要看得见（那是一档风险状态，不是装饰）。
        extras.append(appState.isConfirmAllWritesEnabled ? L(.agentStatusWritesOn) : L(.agentStatusWritesOff))
        return extras
    }

    /// 右端那格：会话名（有提问才生成）＞ 工作目录名（还没提问时）。
    private var statusAnchor: String? {
        if let title = model.sessionTitle { return title }
        guard let root = WorkspaceStore.shared.rootPath, !root.isEmpty else { return nil }
        return L(.agentStatusWorkspace, URL(fileURLWithPath: root).lastPathComponent)
    }

    /// 输入行右侧的控件一律是**等宽字形**（`⏎ ■ ▶ ⏱`），不用 SF Symbol：
    /// 图标自带留白与光学重心，在一条等宽的行里就是「贴了一张小图」，终端里没有这种东西。
    private func glyphButton(_ glyph: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.secondary))
                .frame(width: 18, alignment: .center)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - 输入区（端点没配好时**如实拦住**，不假装在跑）

    private var composer: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            // 排队中的提问（`/queue` 的同义物）：一轮还在跑时提交的话不丢，
            // 这里按序列出；点 `✕` 撤掉一条。**不打断正在跑的这一轮**。
            if !model.queue.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.hair) {
                    ForEach(Array(model.queue.items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: Spacing.s) {
                            Text("⇥")
                                .font(Self.transcriptFont)
                                .foregroundStyle(Theme.text(.secondary))
                            Text("\(index + 1).")
                                .font(Self.transcriptFont)
                                .foregroundStyle(Theme.text(.tertiary))
                            Text(AgentPromptQueue.preview(item.text))
                                .font(Self.transcriptFont)
                                .foregroundStyle(Theme.text(.secondary))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            // 调序（`FR-AGT-CORE-LOOP-008` ②）：首行不给 ↑、末行不给 ↓
                            // —— 按不动的按钮不画，不让用户点了没反应。
                            if index > 0 {
                                glyphButton("↑", help: "上移一位") {
                                    model.moveQueued(id: item.id, offset: -1)
                                }
                            }
                            if index + 1 < model.queue.count {
                                glyphButton("↓", help: "下移一位") {
                                    model.moveQueued(id: item.id, offset: 1)
                                }
                            }
                            glyphButton("✕", help: "移出队列") { model.removeQueued(id: item.id) }
                        }
                    }
                }
            }
            if let blocker = model.blockerText {
                HStack(spacing: Spacing.s) {
                    Text("⚠").font(Self.transcriptFont).foregroundStyle(Theme.status(.warning))
                    Text(blocker).font(Self.transcriptFont).foregroundStyle(Theme.text(.secondary))
                }
                .foregroundStyle(Theme.text(.secondary))
            }
            // 斜杠命令要改配置时的那张单（`FR-AGT-UX-CONV-015`）：**批准之前不动配置**。
            // 形态与工具审批那一行一致 —— 等批的事要看得见、点得到、也能拒。
            if let pending = model.pendingSlashChange {
                HStack(spacing: Spacing.s) {
                    Text("⚠").font(Self.transcriptFont).foregroundStyle(Theme.accentColor)
                    Text(pending.auditLine)
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.secondary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    ToolbarIconButton(systemName: "checkmark.circle",
                                      help: L(.agentChatApprovalApprove)) {
                        Task { await model.approveSlashChange() }
                    }
                    ToolbarIconButton(systemName: "xmark.circle",
                                      help: L(.agentChatApprovalDeny)) {
                        Task { await model.rejectSlashChange() }
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                // 提示符 `>`（§5.3.8.1 ⑤），与消息区用户行同一个字形、同一列。
                Text(">")
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.accentColor)
                TextField(L(.agentChatPlaceholder), text: $model.input)
                    .textFieldStyle(.plain)
                    .font(Self.transcriptFont)
                    .focused($inputFocused)
                    // 六态「权限不足」那一档（§5.3.8）：**有单子等批 或 会话已归档 ⇒ 输入框禁用**。
                    // 禁用而不是「灰掉仍然发送」—— 先发后问是本条的明令禁止项。
                    .disabled(readOnly || model.hasPendingApproval)
                    .onSubmit {
                        // 跑着时提交 = 排队（不是无视、也不是打断）
                        let typed = !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        if typed { Task { await model.send() } }
                    }
                if model.isRunning {
                    Text(L(.agentChatRunning)).font(Self.transcriptFont).foregroundStyle(Theme.text(.secondary))
                    // **停止是等宽字形 `■`，不是 SF Symbol**（§5.3.8.1 ⑤）：图标自带留白与光学重心，
                    // 在一条等宽的行里就是「贴了一张小图」。
                    glyphButton("■", help: L(.agentChatStop)) { model.stop() }
                        // 中断提示写的是 `⌘.`，那就必须真的能按（写一个按不动的手势比不写更坏）。
                        .keyboardShortcut(".", modifiers: .command)
                } else {
                    // **继续上次**（`NFR-AI-08` ⑤）：上一轮没走完（限额 / 取消 / 失败）才有这一枚 ——
                    // 点了接着那一轮停在的跳跑，**已完成的跳不重放**。没得续时整枚不出现（不留空壳）。
                    if let step = model.continueStep {
                        glyphButton("▶", help: L(.agentChatContinue, "\(step)")) {
                            Task { await model.continueLast() }
                        }
                    }
                    glyphButton("⏎", help: L(.agentChatSend)) { Task { await model.send() } }
                        .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                // 定时 agent 的入口（`FR-AI-27`）：面板里设「什么时候起一次会话」；
                // 起不起得来、要不要审批都归既有那条路（定时不构成授权）。
                glyphButton("⏱", help: AppShortcut.agentSchedule.help(L(.agentScheduleTitle))) {
                    appState.isAgentSchedulePresented = true
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Theme.hairline(colorScheme), lineWidth: 1)
            )
            // 运行中常驻一行中断提示（§5.3.8.1 ⑤）：跑着的时候人要知道**怎么停**。
            if model.isRunning {
                Text(L(.agentChatInterruptHint))
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.tertiary))
                    .padding(.leading, Spacing.l)
            }
        }
        .padding(Spacing.m)
    }
}

/// 盲文旋转（`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`）—— Hermes TUI 的 spinner 就是这十帧，
/// 用它而不是 SF Symbol，是因为「像 TUI」这件事一半在字形上。
private struct BrailleSpinner: View {
    var tint: Color = Theme.accentColor

    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.09)) { context in
            let index = Int(context.date.timeIntervalSinceReferenceDate * 10) % Self.frames.count
            Text(Self.frames[index])
                .font(Theme.font(.mono))
                .foregroundStyle(tint)
        }
    }
}
