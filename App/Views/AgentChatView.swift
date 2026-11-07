import AppKit
import SwiftUI
import UniformTypeIdentifiers
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
    /// 挂载时的**初始展开态**（缺省收起）。生产不传。
    ///
    /// 为什么要这个口：详单的展开态是 `@State`，从外面点不动（SwiftUI `Button` 在离屏宿主里
    /// 不落 `NSButton`，见 `DialogActionRowProbeTests` 文件头的实测）—— 而「展开后把布局撑爆」
    /// 这条缺陷恰恰只在展开态出现。不给口，判据就只能靠人点；给了口，探针能把
    /// 「展开 + 300 步」这一面真挂起来量（`AgentChatStepListProbeTests`）。
    var initialStepsExpanded: Bool = false
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
    /// 归档面是否展开（`FR-AGT-UX-SESS-001`）：默认收起，展开时现读一次盘。
    @State private var showArchivedSessions = false
    /// 待确认删除的那一条（`nil` = 没有待确认动作）—— 真删不可逆，必须二次确认。
    @State private var pendingDeleteSession: AgentSessionSummary?

    /// 显式 init 只为下面这一件事：`@State` 的初始值必须在**挂载时**从 `initialStepsExpanded` 取
    /// （成员缺省值会在属性初始化时就把状态钉成 `false`，探针那条口就成摆设了）。
    init(model: AgentChatModel, readOnly: Bool = false, initialStepsExpanded: Bool = false) {
        self.model = model
        self.readOnly = readOnly
        self.initialStepsExpanded = initialStepsExpanded
        _stepsExpanded = State(initialValue: initialStepsExpanded)
    }

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
            batchRevertRow
            wishDeliveryRow
            agentAlerts
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
    /// **显式展开**过的工具块（详设 §3.33：工具块**默认折成一行摘要**，
    /// 于是「点开过」必须记下来 —— 否则点开一下、下一次重绘又收回去，等于点不动）。
    @State private var expandedToolBlocks: Set<UUID> = []
    /// **思考区手动态**（详设 §3.33「思考区三态」）：记「哪一轮 + 用户动过没有」，
    /// 换轮次就清（回到「按阶段默认」）。sticky 与轮次作用域都在 Core，
    /// 这里只是持有它 —— 视图自己记 `Bool` 会在新轮次里沿用上一轮的选择。
    @State private var thinkingManual = AgentThinkingManualState()
    /// **显式展开**过的长消息（`FR-AGT-UX-CONV-012` ⑥ 预览）：点过 `… 展开` 就记下来，
    /// 否则下一次重绘又折回去，等于点不动。
    @State private var expandedPreview: Set<UUID> = []
    /// **显式展开**过的「已应用」摘要组（按组 id）。同一条纪律：点开过就不再收回去。
    @State private var expandedAppliedGroups: Set<String> = []
    /// **显式展开**过的断言台账（按时间线事件的 id）。默认折叠成一行（详设 §3.33）——
    /// 点开过就记下来，否则下一次重绘又折回去，等于点不动。
    @State private var expandedClaimAudits: Set<UUID> = []

    /// 对话区**是不是贴着底**（详设 §3.33.2 ③）：只由真实滚动读数改写，内容长高不改它。
    @State private var transcriptPinned = true

    private var transcript: some View {
        // **哪一条助手消息是「结论」**（详设 §3.33）：轮内最后一条。算一次给整屏用 ——
        // 逐条算会把同一份判定算 N 遍，还会让「第几条是最后一条」出现第二个答案。
        let finalAssistants = AgentChatTurnShape.finalAssistantIndices(in: model.messages)
        // **跟着最新内容走**（人类主人 2026-10-17 实机反馈：「对话框不自动滚动到最新位置，要手工拖动」）。
        // 读数取 `model.scrollTick`（消息条数 + 正文总长 + 卡片数）—— 流式逐段出现、过程块追加、
        // 卡片新增，任何一种都会让读数变大 ⇒ 一次滚动跟随；只在**内容真的变了**时动手，不空转。
        return ScrollViewReader { proxy in
            ScrollView {
                // 块间距跟「紧凑模式」（`FR-AGT-UX-CONV-012` ②）：紧档用发丝间距。
                LazyVStack(alignment: .leading,
                           spacing: appState.agentDisplayPreferences.compact ? Spacing.hair : Spacing.xs) {
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
                        //
                        // **行首栏 = 时间戳列**（`FR-AGT-UX-CONV-012` ③）：开关关掉时
                        // 这一格仍占等宽（不可见填充），所以正文不会左移 —— 不抖动。
                        HStack(alignment: .top, spacing: 0) {
                            leadingColumn(message)
                            VStack(alignment: .leading, spacing: Spacing.hair) {
                                thinkingZone(message,
                                             isFinalAssistant: finalAssistants.contains(index),
                                             isLastTurn: isLastTurn(index))
                                messageRow(message, isFinalAssistant: finalAssistants.contains(index))
                            }
                        }
                        .id(message.id)
                    }
                    ForEach(cardItems) { item in
                        cardRow(item)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                        // 贴底判定（§3.33.2 ③）：只吃**真实滚动读数**，内容长高不刷新它。
                        .background(ScrollOffsetSpy { distance in
                            let pinned = distance <= AgentScrollFollow.bottomTolerance
                            if pinned != transcriptPinned { transcriptPinned = pinned }
                        })
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.m)
            }
            .onChange(of: model.scrollTick) { _ in follow(proxy) }
            .onChange(of: model.isRunning) { _ in follow(proxy) }
            // **新轮开始 ⇒ 思考区回到「按阶段默认」**（§3.33 三态之四）：手动态只在本轮内生效。
            .onChange(of: currentTurnKey) { _, _ in
                thinkingManual.register(turnKey: currentTurnKey)
                // **人刚张了口就把视口贴回底部**：否则上一轮翻到上面的位置会把这一轮的回答挡在屏外。
                transcriptPinned = true
                follow(proxy)
            }
            .onAppear { thinkingManual.register(turnKey: currentTurnKey) }
            // 搜索词一变就**定位到第一条命中**（§9.1.16 缺口 ③）。
            .onChange(of: searchText) { _, _ in revealFirstHit(proxy) }
            .onAppear { follow(proxy) }
        }
    }

    /// 当前轮次的钥匙：**最后一条用户提问的 id**（没有提问 ⇒ `nil`）。
    /// 思考区的手动态按它分轮（`AgentThinkingManualState`）。
    private var currentTurnKey: UUID? {
        model.messages.last(where: { $0.role == .user })?.id
    }

    /// 第 `index` 条消息是否属于最后一轮（思考区是否可能处于「运行中」）。
    private func isLastTurn(_ index: Int) -> Bool {
        AgentChatTurnShape.isInLastTurn(in: model.messages, at: index)
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

    /// **滚到底 —— 但只在人贴着底的时候**（详设 §3.33.2 ③）。
    ///
    /// 改前这里有两条「闪」的根因，各自独立：
    /// ① `withAnimation(.easeOut(0.15))` + 每个 token 都触发 ⇒ 动画**永远重启**、永远跑不完，
    ///    滚动条一路处于「正在滑」的状态；
    /// ② 无条件跟随 ⇒ 人往上翻也被拽回底部，跟用户抢控制权。
    ///
    /// 现在：贴底才跟、跟就**直接跳**（不插值）。用户点「回到最新」这类显式动作也走它 ——
    /// 那时 `transcriptPinned` 由真实滚动读数改回 `true` 之后自然跟随。
    private func follow(_ proxy: ScrollViewProxy) {
        guard transcriptPinned else { return }
        proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
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

    /// 思考区展开态的**整块上限**（详设 §3.33「思考区三态」：整块 ≯ 200pt = 抬头 + 发丝 + 内容 178）。
    ///
    /// 常量而不是「按屏高算」：这样「思考多长」对外层只差一个**有界**的量，
    /// 探针能拿它当判据（`AgentChatNarrationProbeTests`）。真值在 `AgentThinkingZone`。
    static var thinkingZoneExpandedMaxHeight: CGFloat { AgentThinkingZone.expandedMaxHeight }

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
    private func messageRow(_ message: AgentChatMessage, isFinalAssistant: Bool = true) -> some View {
        switch message.role {
        case .user:
            // 行首栏是 `>`（§5.3.8.1 ②），**不是右对齐气泡**，也不是每条一个卡片。
            //
            // 用户**自己的字**仍走 `AgentTranscriptText`（原样显示，不改写他的话）；
            // 富文本渲染只针对**模型回复** —— 见下面 `.assistant` 那一支。
            HStack(alignment: .top, spacing: 0) {
                gutter(">", Theme.chat(.user, colorScheme))
                // **用户的话走暖金**（主人 2026-10-31：「用户输入的文字和 Agent 返回的文字颜色一样，
                // 一眼难以区分」——Hermes 那边也是把他的话标成金色）。助手正文仍走常规文本色，
                // 两种颜色对看，谁说的不用猜。取 `accentWarm` 这条既有令牌：三个主题都有值，
                // 且它本来就是"文字级暖色"，不必新增令牌（新令牌要连带跑设计棘轮）。
                AgentTranscriptText(text: message.text, font: Self.transcriptFont, highlight: highlightNeedle)
                    .foregroundStyle(Theme.chat(.user, colorScheme))
                Spacer(minLength: 0)
            }
        case .assistant:
            // **流式输出 = 关 ⇒ 收齐再显示**（`FR-AGT-UX-CONV-012`）：这一条还在收的时候
            // 一行都不画（不出半截正文再换成全文 —— 那会让人以为自己读过了）。
            if message.isStreaming && !appState.agentDisplayPreferences.streaming {
                EmptyView()
            } else {
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
                        assistantBody(message, isFinalAssistant: isFinalAssistant)
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
        // **断言台账**（详设 §3.33）：这段文本不是阅读内容，是「这句话有没有依据」的
        // 审计账（每条断言 + 它的出处行）。默认折成**一行**，有未核断言时那一行就是告警；
        // 展开才逐条看，且明细有高度上限、内部滚动。
        // 认不出机器头的时间线事件照旧走下面那条「一行灰字」的老路，这里不猜。
        if let audit = AgentClaimAudit.parse(message.text) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                gutter("▼", Theme.text(.secondary))
                AgentClaimAuditRow(audit: audit,
                                   expanded: Binding(
                                    get: { expandedClaimAudits.contains(message.id) },
                                    set: { isOpen in
                                        if isOpen { expandedClaimAudits.insert(message.id) }
                                        else { expandedClaimAudits.remove(message.id) }
                                    }
                                   ))
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
            // 时间线事件的字形（§5.3.8.1 ②）：告警 `⚠`，其余 `▼`。
            // 三档字形都要能表达「错误」（`FR-AGT-UX-CONV-012`）：失败那一行取
            // `AgentDisplayProjection.glyph(.error, style:)`，不是写死一个 `⚠`。
            gutter(Self.failureReason(in: message.text) == nil
                   ? "▼"
                   : AgentDisplayProjection.glyph(for: .error,
                                                  style: appState.agentDisplayPreferences.indicatorGlyph),
                   Theme.text(.secondary))
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
                    .foregroundStyle(Theme.chat(.notice, colorScheme))
            }
            }
        }
    }

    /// 一组工具调用（§5.3.8.1 ②）：**默认折成一行摘要**，展开才是 `├─ ⏺` 条目。
    ///
    /// ## 2026-11-07 真机第三次缺陷：「tools 调用了最终还没折叠起来」
    ///
    /// 改前的默认形态是 `!(compact || toolProgress == .summary)` —— 契约默认
    /// `toolProgress = .all` ⇒ **默认展开**。一轮 56 次调用就是 56 行，工具列表铺满
    /// 对话区、结论被挤到屏幕外。工具调用是**过程信息**，按 §3.33 的优先级它只配占
    /// **一行**：`▸ 56 次工具调用 · 8.2s · 展开`。
    ///
    /// 渲染在 `AgentToolBlockView`（独立件，探针能把展开态真挂起来量）；这里只做
    /// 「开关 → 形态」的接线与展开态记账。
    @ViewBuilder
    private func toolBlock(_ message: AgentChatMessage) -> some View {
        let rows = AgentToolLines.rows(message.text)
        let rawLines = message.text.components(separatedBy: "\n")
        let count = rows.isEmpty ? rawLines.count : rows.count
        let display = appState.agentDisplayPreferences
        // **默认折叠**（唯一形态）：点开过才展开。以前这里还有一个「默认展开」的分支，
        // 那正是主人看到的「一大块 tools 列表没折」—— 过程信息不许有「默认铺开」这一档。
        let expanded = expandedToolBlocks.contains(message.id)

        if display.toolProgress == .off {
            // 「工具进度 = 关」：只留「调用 N 次」—— **不给折叠头**（给了就等于留了个能展开的口子）。
            HStack(spacing: Spacing.s) {
                Text("▸")
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.tertiary))
                Text(L(.agentChatToolCallsOnly, Int64(count)))
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            AgentToolBlockView(text: message.text,
                               expanded: expanded,
                               highlight: highlightNeedle,
                               language: LocalizationManager.shared.effectiveLanguage) {
                if expanded {
                    expandedToolBlocks.remove(message.id)
                } else {
                    expandedToolBlocks.insert(message.id)
                }
            }
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
                case .spinning(let hops): return L(.agentChatStopSpinning, Int(hops))
                case .deadline: return L(.agentChatStopDeadline)
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

    // MARK: - 卡片行（连续的「已应用」合并成一行摘要）

    /// 对话区里的一条卡片行：普通工具卡**一张一条**，连续的 `.applied` 卡合并成**一条摘要**。
    ///
    /// 为什么合并：每张 `.applied` 卡原本在对话区占三行（`✓ ▸ 命令` / `⎿ applied` /
    /// `Applied ⟲`），一次批量写入 20 个文件就是 60 行，页面又自动滚到底 ⇒
    /// thinking / 正文的可视高度被挤没（人类主人 2026-11-06 原话：「Applied 三行是什么东西，
    /// 而且占用的区域越来越多，让 thinking 区域越来越少」）。
    /// 合并后默认只占**一行**（`AgentAppliedSummaryRow.summaryHeight`），点开才看明细。
    private enum CardRow: Identifiable {
        case card(AgentToolCard)
        case applied(id: String, cards: [AgentToolCard])

        var id: String {
            switch self {
            case .card(let card): return "card-" + card.id.uuidString
            case .applied(let id, _): return id
            }
        }
    }

    /// 把 `model.cards` 按「连续同态」压成行：一段连续的 `.applied` 合成一条（组 id 取段首卡片的 id，
    /// 卡片增删时不会把已展开的组错配到别的段上）。
    private var cardItems: [CardRow] {
        var items: [CardRow] = []
        var pending: [AgentToolCard] = []
        func flush() {
            guard let first = pending.first else { return }
            items.append(.applied(id: "applied-" + first.id.uuidString, cards: pending))
            pending = []
        }
        for card in model.cards {
            if case .applied = card.outcome {
                pending.append(card)
            } else {
                flush()
                items.append(.card(card))
            }
        }
        flush()
        return items
    }

    @ViewBuilder
    private func cardRow(_ item: CardRow) -> some View {
        switch item {
        case .card(let card):
            toolCard(card)
        case .applied(let id, let cards):
            AgentAppliedSummaryRow(
                cards: cards,
                expanded: Binding(
                    get: { expandedAppliedGroups.contains(id) },
                    set: { isOpen in
                        if isOpen { expandedAppliedGroups.insert(id) } else { expandedAppliedGroups.remove(id) }
                    }
                ),
                onUndo: { model.undo($0) }
            )
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
                   pendingApproval(card) ? Theme.chat(.pending, colorScheme) : Theme.text(.secondary))
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
                    // **命令 / 参数走淡蓝**（主人 2026-10-31：「DSH 还会把命令类的信息标记成标志性的
                    // 淡蓝色，让人想起蓝色鲸鱼娘」）。取 `accentGlow` 这条既有令牌：深色 #7AB0FA、
                    // 浅色 #1C63C4 —— 与用户那句暖金、助手正文的中性色三方对比，一眼分得清谁在说话、
                    // 哪一段是机器要做的事。状态字形（✓ / ✗）仍按成败着色，不被这一层覆盖。
                    Text(card.arguments)
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.chat(.command, colorScheme))
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
                // **预览也要有上限**（2026-11-06）：这是一段差异 / 命令原文，长度由文件决定 ——
                // 摊开就是「一张卡占满一屏」，把同一轮里别的卡片与 thinking 全推到屏幕外。
                // 上限取与步骤详单同一个常量，超出在内部滚。
                ScrollView(.vertical) {
                    Text(preview)
                        .font(Self.transcriptFont)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.s)
                }
                .frame(maxHeight: AgentStepListPanel.maxHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.badge)
                        .strokeBorder(Theme.hairline(colorScheme), lineWidth: 1)
                )
                .padding(.leading, Spacing.l)
            } else if card.expanded, !card.arguments.isEmpty {
                Text(card.arguments)
                    .font(Self.transcriptFont)
                    .textSelection(.enabled)
                    .foregroundStyle(Theme.chat(.command, colorScheme))
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
                    Text(L(.agentChatApprovalPending)).font(Self.transcriptFont).foregroundStyle(Theme.chat(.pending, colorScheme))
                    ToolbarIconButton(systemName: "checkmark.circle",
                                      help: L(.agentChatApprovalApprove),
                                      tint: Theme.status(.success)) { model.approve(card.id) }
                        .controlSize(.small)
                    ToolbarIconButton(systemName: "xmark.circle",
                                      help: L(.agentChatApprovalDeny),
                                      tint: Theme.status(.danger)) { model.deny(card.id) }
                        .controlSize(.small)
                }
            }
            // `.applied` 不再走这张卡（2026-11-06）：同一段连续的「已应用」在 `cardItems` 里
            // 已合并成一行摘要（`AgentAppliedSummaryRow`），跑到这里就是漏了 —— 所以这里
            // 刻意**不留**那份「✓ 命令 / ⎿ applied / Applied ⟲」三行，免得哪天又长出 60 行。
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
                // 待批那一圈用**紫**（§5.3.8.4）：框和「待你决定」徽章、`⚠` 字形同一色，
                // 一眼就是「这件事在等你」；其余状态仍是中性发丝线（终端语汇里没有彩色卡片）。
                .strokeBorder(pendingApproval(card)
                              ? Theme.chat(.pending, colorScheme).opacity(0.55)
                              : .clear, lineWidth: 1)
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
        // 待批用紫（与用户的金黄拉开）：紫只标「这件事在等你」，
        // 真按下去的两个动作才走语义色 —— 批准绿、拒绝红。
        case .pendingApproval: return Theme.chat(.pending, colorScheme)
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

    /// 输入框上方那块（`AgentStepListPanel`）：表头 `▸ 任务清单 · N 步 (95/150)`，展开是**有高度上限、
    /// 内部滚动**的步骤行。
    ///
    /// 2026-11-04 真机两处缺陷都落在这块上，所以整块搬进了 `AgentStepListPanel`：
    /// ① 计数器分母写成 `model.steps.count`（本次运行已产生的步数）⇒ 分母跟着步数长；
    /// ② 步骤行直接摊在页面的 `VStack` 里、无上限无滚动 ⇒ 几百步之后把对话区与输入框整体顶出屏幕。
    /// 这个视图现在只负责**传值**（步数 / 计数器 / 展开态），不再自己排步骤行。
    @ViewBuilder
    private var taskList: some View {
        AgentStepListPanel(steps: model.steps,
                           counter: model.stepCounter,
                           isRunning: model.isRunning,
                           elapsedSeconds: model.lastElapsedSeconds,
                           expanded: $stepsExpanded)
    }

    // MARK: - 整批撤回（`FR-STD-WS-EDIT-015`）

    /// 这一行的三样：这一轮 Agent 改了几个文件（+「整批撤回」）· 撤完之后的结果 · 「撤销这次撤回」。
    ///
    /// 只在**有事**时出现（还能撤 / 刚撤过 / 刚失败）—— 没有 Agent 写入的那一轮不占位置。
    /// 读数全部来自 `AppState.agentBatchRevert`：**账与计划都在宿主侧**，视图不自己数、
    /// 更不自己算前像（否则「撤回到哪一版」会有第二个答案）。
    @ViewBuilder
    private var batchRevertRow: some View {
        let state = appState.agentBatchRevert
        if state.pending > 0 || state.receipt != nil || state.lastFailure != nil {
            HStack(spacing: Spacing.s) {
                if state.pending > 0 {
                    Text(L(.agentBatchRevertPending, state.pending))
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.secondary))
                    DialogActionButton(systemName: "arrow.uturn.backward",
                                       title: L(.agentBatchRevert),
                                       isDisabled: agentBatchRoot == nil) {
                        Task { await runBatchRevert() }
                    }
                } else if let receipt = state.receipt {
                    Text(L(.agentBatchRevertDone, receipt.reverted))
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.secondary))
                    // 撤不了的**逐条点名**（人改过 / 已被删 / 又被造回来各不相同，只说个数不够）。
                    if !receipt.unmoved.isEmpty {
                        Text(L(.agentBatchRevertUnmoved, receipt.unmoved.count))
                            .font(Self.transcriptFont)
                            .foregroundStyle(Theme.status(.warning))
                    }
                }
                if state.redoPending > 0 {
                    DialogActionButton(systemName: "arrow.uturn.forward",
                                       title: L(.agentBatchRevertRedo),
                                       isDisabled: agentBatchRoot == nil) {
                        Task { await runBatchRedo() }
                    }
                }
                if state.lastFailure != nil {
                    Text(L(.agentBatchRevertFailed))
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.status(.danger))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.m)
        }
    }

    /// 撤回要对哪个工作区动手（没打开工作区就不给点 —— 空路径会解析成进程当前目录）。
    private var agentBatchRoot: String? {
        guard let root = WorkspaceStore.shared.rootPath, !root.isEmpty else { return nil }
        return root
    }

    private func runBatchRevert() async {
        guard let root = agentBatchRoot else { return }
        _ = await appState.revertAgentBatch(workspacePath: root)
    }

    private func runBatchRedo() async {
        guard let root = agentBatchRoot else { return }
        _ = await appState.redoAgentBatchRevert(workspacePath: root)
    }

    // MARK: - 交付面（`FR-STD-WS-AI-002` ①③）

    /// 差异清单是否展开（默认收起：这一行只回答「交付了什么、跑没跑通」）。
    @State private var wishDiffExpanded = false

    /// 这一批交付了什么：改了哪些文件（新建 / 修改 / 增删行数）+ **跑没跑通** + 逐行差异。
    ///
    /// 读数全部来自 `AppState.wishDelivery`（Core 的 `WishDelivery` 从账反推，
    /// 差异切分与审批单同一份）—— 视图不自己数文件、不自己算行数，也不自己判「算不算成功」。
    /// 只在**有事**时出现（有改动 / 跑过命令），没有的轮次不占位置。
    @ViewBuilder
    private var wishDeliveryRow: some View {
        if let proposal = appState.wishDelivery {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    if proposal.changes.isEmpty {
                        Text(L(.wishDeliveryNoChanges))
                            .font(Self.transcriptFont)
                            .foregroundStyle(Theme.text(.secondary))
                    } else {
                        Text(L(.wishDeliveryTitle, proposal.changes.count))
                            .font(Self.transcriptFont)
                            .foregroundStyle(Theme.text(.secondary))
                        if proposal.createdCount > 0 {
                            Text(L(.wishDeliveryCreated, proposal.createdCount))
                                .font(Self.transcriptFont)
                                .foregroundStyle(Theme.text(.tertiary))
                        }
                        if proposal.modifiedCount > 0 {
                            Text(L(.wishDeliveryModified, proposal.modifiedCount))
                                .font(Self.transcriptFont)
                                .foregroundStyle(Theme.text(.tertiary))
                        }
                        Text(L(.wishDeliveryLines, proposal.addedTotal, proposal.removedTotal))
                            .font(Self.transcriptFont)
                            .foregroundStyle(Theme.text(.tertiary))
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: Spacing.s) {
                    if let verdict = verdictText(for: proposal) {
                        Text(verdict)
                            .font(Self.transcriptFont)
                            .foregroundStyle(verdictTint(for: proposal))
                    }
                    if !proposal.changes.isEmpty {
                        DialogActionButton(systemName: wishDiffExpanded ? "chevron.up" : "list.bullet.rectangle",
                                           title: L(.wishDeliveryShowDiff)) {
                            wishDiffExpanded.toggle()
                        }
                    }
                    Spacer(minLength: 0)
                }
                if wishDiffExpanded {
                    deliveryDiff(proposal)
                }
            }
            .padding(.horizontal, Spacing.m)
        }
    }

    /// 判定那一行的一句话。**没改动时不说话**（上一行已经说了「没有改动任何文件」）。
    private func verdictText(for proposal: WishProposal) -> String? {
        switch WishDelivery.verdict(of: proposal) {
        case .noChanges:
            return nil
        case .unverified:
            return L(.wishDeliveryUnverified)
        case .passed:
            return L(.wishDeliveryPassed)
        case .failed:
            return L(.wishDeliveryFailed, proposal.validation?.exitCode ?? 0)
        }
    }

    /// 判定那一行的颜色：没跑通必是告警色（不许和「通过」一个颜色），未验证走次要色。
    private func verdictTint(for proposal: WishProposal) -> Color {
        switch WishDelivery.verdict(of: proposal) {
        case .noChanges, .unverified:
            return Theme.text(.secondary)
        case .passed:
            return Theme.status(.success)
        case .failed:
            return Theme.status(.danger)
        }
    }

    /// 逐文件差异（每行带 `+` / `-` / 空格前缀，与审批单同一套写法）。
    ///
    /// 单文件最多显示 `deliveryDiffLineLimit` 行：一屏塞不下的差异会把人劝退，
    /// 而「还有几行没显示」这句话必须留着 —— 静默截断会让人以为差异就这么点。
    private func deliveryDiff(_ proposal: WishProposal) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(proposal.changes, id: \.path) { change in
                HStack(spacing: Spacing.s) {
                    Text(change.path)
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.secondary))
                    Text(L(.wishDeliveryLines, change.addedLines, change.removedLines))
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.tertiary))
                    Spacer(minLength: 0)
                }
                let shown = change.diff.prefix(Self.deliveryDiffLineLimit)
                ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                    Text(Self.diffPrefix(line.kind) + line.text)
                        .font(Self.transcriptFont)
                        .foregroundStyle(diffTint(line.kind))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if change.diff.count > Self.deliveryDiffLineLimit {
                    Text(L(.wishDeliveryDiffTruncated, Int(change.diff.count - Self.deliveryDiffLineLimit)))
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.tertiary))
                }
            }
            // 没跑通时把命令与输出尾一并亮出来：只说「没跑通」而不给读数，人还得自己再跑一遍。
            if let validation = proposal.validation, !validation.passed {
                Text(validation.command)
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
                    .lineLimit(2)
                ForEach(Array(validation.outputTail.split(separator: "\n", omittingEmptySubsequences: false)
                    .prefix(Self.deliveryDiffLineLimit).enumerated()), id: \.offset) { _, line in
                    Text(String(line))
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.status(.danger))
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, Spacing.xs)
    }

    /// 单个文件在交付面里最多显示多少行差异。
    private static let deliveryDiffLineLimit = 40

    private static func diffPrefix(_ kind: AgentTextDiff.Line.Kind) -> String {
        switch kind {
        case .context: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }

    private func diffTint(_ kind: AgentTextDiff.Line.Kind) -> Color {
        switch kind {
        case .context: return Theme.text(.tertiary)
        case .added: return Theme.status(.success)
        case .removed: return Theme.status(.danger)
        }
    }

    // MARK: - 主动通知 / 求助卡 / 门控重发（`FR-AGT-UX-CONV-008` · `-009` · `FR-AGT-GUARD-COST-001`）

    /// 三格只在**有事**时出现，且每一格都能就地收起。
    ///
    /// 为什么放在输入框上方而不是消息流里：这三件事都是「这一轮之后要你做点什么」，
    /// 贴着输入框才有人照着做；塞进消息流会被下一次滚动带走（正是「不让人守着屏幕」要避免的）。
    @ViewBuilder
    private var agentAlerts: some View {
        if let banner = model.notifyBanner {
            alertCard(icon: banner.mustInterrupt ? "exclamationmark.bubble" : "bell.badge",
                      title: banner.title) {
                Text(banner.body)
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            } actions: {
                DialogActionButton(systemName: "checkmark", title: L(.agentNotifyDismiss)) {
                    model.dismissNotifyBanner()
                }
            }
        }
        if let help = model.helpRequest {
            alertCard(icon: "questionmark.bubble", title: L(.agentHelpCardTitle)) {
                VStack(alignment: .leading, spacing: Spacing.hair) {
                    Text(help.kind.label(language: language) + "：" + help.ask)
                    Text(help.whyLine(language: language))
                    Text(help.resumeLine(language: language))
                }
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            } actions: {
                DialogActionButton(systemName: "checkmark", title: L(.agentHelpCardDismiss)) {
                    model.dismissHelpRequest()
                }
            }
        }
        if let recall = model.gateRecall {
            alertCard(icon: "hand.raised", title: L(.agentGateRecallTitle)) {
                Text(recall.reason)
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            } actions: {
                DialogActionButton(systemName: "paperplane", title: L(.agentGateRecallForceSend)) {
                    Task { await model.forceSend() }
                }
                DialogActionButton(systemName: "xmark", title: L(.agentGateRecallDismiss), role: .cancel) {
                    model.dismissGateRecall()
                }
            }
        }
    }

    /// 三格共用的纸面壳：**浮层用 `Theme.paper`**（不透明的主题面板色）——
    /// 壁纸皮肤下 `surface` 是半透明的，两层叠起来文字会糊。
    private func alertCard<BodyContent: View, Actions: View>(
        icon: String,
        title: String,
        @ViewBuilder _ bodyContent: () -> BodyContent,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.status(.warning))
                Text(title)
                    .font(Self.transcriptFont.bold())
                    .foregroundStyle(Theme.text(.primary))
                Spacer(minLength: 0)
            }
            bodyContent()
            HStack(spacing: Spacing.s) {
                actions()
                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper(.raised))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
    }

    /// 文案语言（与 `model.languageProvider` 同一来源 —— 界面与状态壳各写一份就会分叉）。
    private var language: AppLanguage { model.languageProvider() }

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
    ///
    /// **生命周期入口也在这里**（`FR-AGT-UX-SESS-001`）：每行的 `⇩ 归档 / ↗ 导出 / ✕ 删除`，
    /// 顶部 `导入会话…`，底部一行 `归档（n）` 展开归档面（那面里每行是 `↩ 恢复`）。
    /// 所有动作都走 `AgentChatModel` 的同名方法（→ `Core/AgentSessionLifecycleDesk`），
    /// 视图不直接碰存储 —— 那样才只有一处「删干净」的定义。
    private var sessionsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.s) {
                Text(L(.agentChatSessionsTitle))
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
                Spacer(minLength: 0)
                // 导入（③的反方向）：把以前导出的会话文件装回来。
                Button {
                    importSession()
                } label: {
                    Text("⤓ " + L(.agentChatSessionsImport))
                        .font(Self.transcriptFont)
                }
                .buttonStyle(.plain)
                .disabled(!model.canSwitchSession)
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
                            sessionRow(session, archived: false)
                        }
                    }
                }
                .frame(maxHeight: Spacing.xxl * 8)
            }

            // 归档面（①的收口）：默认收起 —— 平时用不到，但删不掉的会话必须有地方回去。
            Divider()
            Button {
                showArchivedSessions.toggle()
                if showArchivedSessions {
                    model.reloadArchivedSessions(workspacePath: workspacePath)
                }
            } label: {
                Text((showArchivedSessions ? "▾ " : "▸ ")
                     + L(.agentChatSessionsArchivedToggle, model.archivedSessions.count))
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)

            if showArchivedSessions {
                if model.archivedSessions.isEmpty {
                    Text(L(.agentChatSessionsArchivedEmpty))
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.tertiary))
                        .padding(.horizontal, Spacing.s)
                        .padding(.bottom, Spacing.xs)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(model.archivedSessions) { session in
                                sessionRow(session, archived: true)
                            }
                        }
                    }
                    .frame(maxHeight: Spacing.xxl * 6)
                }
            }

            // 上一动作的一句话结论（成功也说话；被拒说清为什么）—— 没有就不占行。
            if let line = model.sessionLifecycleLine {
                Divider()
                Text(line)
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, Spacing.xs)
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
        // 删除必须二次确认（真删不可逆：会话本体 + 归档副本 + 续跑记录一起没）。
        .confirmationDialog(
            L(.agentChatSessionDelete),
            isPresented: Binding(
                get: { pendingDeleteSession != nil },
                set: { if !$0 { pendingDeleteSession = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L(.agentChatSessionDelete), role: .destructive) {
                if let session = pendingDeleteSession {
                    model.deleteSession(session.id, workspacePath: workspacePath)
                }
                pendingDeleteSession = nil
            }
            Button(L(.commonCancel), role: .cancel) { pendingDeleteSession = nil }
        } message: {
            let title: String = pendingDeleteSession?.title ?? ""
            Text(L(.agentChatSessionDeleteConfirmMessage, title))
        }
    }

    /// 一行会话：**主体是「打开」，右侧三个动作各自是独立按钮**。
    ///
    /// 形状说明：以前整行就是一个 `Button`，动作塞不进它的 label（按钮里嵌按钮在 SwiftUI 里
    /// 点击归属是不确定的）⇒ 现在拆成「打开」按钮 + 动作按钮并排。
    private func sessionRow(_ session: AgentSessionSummary, archived: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            Button {
                guard !archived else { return }
                model.openSession(session.id, workspacePath: workspacePath)
                showSessions = false
            } label: {
                VStack(alignment: .leading, spacing: Spacing.hair) {
                    Text(session.title)
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(archived ? .secondary : .primary))
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
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!archived && !model.canSwitchSession)

            if archived {
                glyphButton("↩", help: L(.agentChatSessionRestore)) {
                    model.restoreSession(session.id, workspacePath: workspacePath)
                }
            } else {
                glyphButton("⇩", help: L(.agentChatSessionArchive)) {
                    model.archiveSession(session.id, workspacePath: workspacePath)
                }
                glyphButton("↗", help: L(.agentChatSessionExport)) {
                    exportSession(session)
                }
                glyphButton("✕", help: L(.agentChatSessionDelete)) {
                    pendingDeleteSession = session
                }
            }
        }
        .padding(.horizontal, Spacing.s)
    }

    /// 导出：Core 只给数据，落哪儿由系统保存面板决定（用户的目录归用户）。
    private func exportSession(_ session: AgentSessionSummary) {
        guard let payload = model.exportSessionData(session.id, workspacePath: workspacePath) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = payload.fileName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.writeExportedSession(payload, to: url)
    }

    /// 导入：选一个以前导出的 `.json`，装回当前工作区（撞名给新号，不覆盖已有的）。
    private func importSession() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let json = UTType(filenameExtension: "json") {
            panel.allowedContentTypes = [json]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            model.importSessionData(Data(), workspacePath: workspacePath)   // 读不出来也走同一条结论路径
            return
        }
        model.importSessionData(data, workspacePath: workspacePath)
    }

    /// 当前工作区（会话按工作区隔离：列表、归档面、动作全部只对这一处生效）。
    private var workspacePath: String? { WorkspaceStore.shared.rootPath }

    /// 列表里的时间：**今天只给时分、别的日子带日期** —— 一列里全是「2026-10-22 11:03」看不出远近。
    private static func sessionTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 行首栏（时间戳）的时刻串：**恒定 5 个字符**（`HH:mm`）。
    ///
    /// 为什么不按「今天 / 别的日子」分两档：那一列是**定宽**的（契约③不抖动），
    /// 一个 11 字符的串会被截成 `10-22` 这种半截日期 —— 看着像时间坏了。
    /// 日期归属由会话列表那一条（`sessionTimeText`）负责，这里只管「这一条是什么时候说的话」。
    private static func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 行首栏 / 思考段 / 预览（`FR-AGT-UX-CONV-012` 的三项接线）

    /// 行首栏那一串：**开关关 ⇒ 等宽不可见填充**，正文一个像素都不左移。
    ///
    /// 列宽由**字符数**保证（`AgentDisplayProjection.leadingColumn`），视图这里
    /// 不写 `frame(width:)` —— 少一个会随字号漂移的几何常量。
    @ViewBuilder
    private func leadingColumn(_ message: AgentChatMessage) -> some View {
        let preferences = appState.agentDisplayPreferences
        let stamp = preferences.timestamps ? message.createdAt.map(Self.clockText) : nil
        Text(verbatim: AgentDisplayProjection.leadingColumn(timestamp: stamp, preferences: preferences))
            .font(Self.transcriptFont)
            .foregroundStyle(Theme.text(.tertiary))
    }

    /// **思考区**（详设 §3.33「思考区三态」）：过程独白 + （开关打开时的）思考段都住在这里。
    ///
    /// 三态由 Core 判（`AgentThinkingFold`）：
    /// · **运行中** ⇒ 默认展开、限高 200pt + 内部滚动（「我先读一下…再…」逐段吐出来）；
    /// · **任一终态** ⇒ 自动折成一行（`思考过程 · 12 步 · 18.4s · 展开`）；
    /// · **用户手动动过** ⇒ 以用户为准且本轮内保持（sticky，`AgentThinkingManualState`）。
    ///
    /// 为什么独白也放这里、而不另做一个「独白行」：两者都是**过程信息**，同一轮里
    /// 该有同一个形态（否则一轮里两套折叠规则，主人得记住哪个会自己折）。
    ///
    /// 内容空（没有独白、也没有打开的思考段）⇒ 一行都不画（契约②：零占位）。
    @ViewBuilder
    private func thinkingZone(_ message: AgentChatMessage, isFinalAssistant: Bool,
                              isLastTurn: Bool) -> some View {
        let parts = thinkingParts(message, isFinalAssistant: isFinalAssistant)
        if !parts.isEmpty {
            let phase: AgentThinkingPhase = (model.isRunning && isLastTurn) ? .running : .finished
            let manual = thinkingManual.manual(for: currentTurnKey)
            AgentThinkingZone(text: parts.joined(separator: "\n\n"),
                              phase: phase,
                              manual: manual,
                              steps: model.steps.count,
                              elapsedSeconds: model.lastElapsedSeconds,
                              highlight: highlightNeedle,
                              language: LocalizationManager.shared.effectiveLanguage) { expanded in
                thinkingManual.set(expanded)
            }
        }
    }

    /// 思考区里该有哪些内容（顺序：**思考段在前、独白在后** —— 前者是模型的内部独白，
    /// 后者是它写在正文里的过程叙述）。
    ///
    /// · 思考段仍受 `display.thinking` 开关管（关 = 不画那一段，但数据照收）；
    /// · **过程独白不受这个开关管**：它是模型写进正文的字，既不能回正文（主人明确
    ///   「这是思考过程，不是正文」），也不该被静默吞掉（关掉开关不等于删掉它）。
    private func thinkingParts(_ message: AgentChatMessage, isFinalAssistant: Bool) -> [String] {
        guard message.role == .assistant else { return [] }
        var parts: [String] = []
        if appState.agentDisplayPreferences.thinking,
           let thinking = message.thinking,
           !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(thinking)
        }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            if isFinalAssistant {
                let split = AgentAnswerClassifier.split(message.text)
                // 整条都是独白 ⇒ 它按「末段永远是结论」的兜底走正文（否则正文区一个字都没有），
                // 这里就不再放一遍——同一段字在两处出现，读起来像重复。
                if !split.isNarrationOnly, let narration = split.narration,
                   !narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(narration)
                }
            } else {
                // 轮内的中间叙述：整条都是过程（位置判定，不看长相）。
                parts.append(text)
            }
        }
        return parts
    }

    /// 正文（结论）区。
    ///
    /// ## 这里只画结论（详设 §3.33）
    ///
    /// 主人问：「Doyah Agent 里输出的『我先读一下……再……』这是思考过程吗？」——是。
    /// 于是正文只留**结论**：过程独白归思考区（`thinkingZone`），中间叙述（轮内非最后
    /// 一条助手消息）整条也归思考区。正文区里一个「我先…」都不该出现。
    ///
    /// · 终态：`AgentAnswerClassifier` 切出结论段（末段 + 代码块）；
    /// · 流式中：同样只画结论那一段 —— 独白正在思考区里增量长，若此时整段画进正文，
    ///   终态一到它会在正文里「消失」，读起来像内容被吞了。
    ///
    /// 整条都是独白（`isNarrationOnly`，例如只说了一句「我先看一下」就断了）⇒ 按契约
    /// 「末段永远是结论」的兜底原样出 —— 这种消息**不折**，否则正文区一个字都没有。
    @ViewBuilder
    private func assistantBody(_ message: AgentChatMessage, isFinalAssistant: Bool) -> some View {
        if !isFinalAssistant {
            // 中间叙述：整条在思考区里（`thinkingZone`）。正文区不重复画一遍。
            EmptyView()
        } else {
            conclusionBody(AgentAnswerClassifier.split(message.text).conclusion, message: message)
        }
    }

    /// **结论段**：默认整段呈现（含代码块）。`longPreview` 是**显式 opt-in** ——
    /// 它折的正是结论本身，所以默认必须是 `off`（§3.33；旧机器盘上的 `2+2` 由
    /// `AgentDisplayPreferencesFile` 的一次性迁移改掉）。
    @ViewBuilder
    private func conclusionBody(_ text: String, message: AgentChatMessage) -> some View {
        let split = expandedPreview.contains(message.id)
            ? nil
            : AgentDisplayProjection.previewSplit(text: text,
                                                  preferences: appState.agentDisplayPreferences)
        if let split {
            VStack(alignment: .leading, spacing: Spacing.hair) {
                markdownBody(split.head, isStreaming: false)
                // 折叠处：`…` + 展开入口（契约⑥「折叠处有 `…` 且可展开」）。
                //
                // **这里刻意不用 `Button`**：转写区的折叠行是**内容里的一个折角**，不是工具条按钮；
                // 按钮化会被「主界面动作面一律图标」那条判据算成 a 类（`Scripts/check-button-icon-only.py`
                // 判据 C 按「水平 Button + 文字标签」机械识别，转写行也在它的扫描面里），
                // 而本条不许去改那份台账 —— 所以形态取「可点的正文行」+ 无障碍按钮语义（读屏仍当按钮）。
                Text("… " + L(.agentChatExpand) + " (" + String(split.hidden) + ")")
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.accentColor)
                    .contentShape(Rectangle())
                    .onTapGesture { expandedPreview.insert(message.id) }
                    .accessibilityAddTraits(.isButton)
                    .help(L(.agentChatExpand))
                markdownBody(split.tail, isStreaming: false)
            }
        } else {
            markdownBody(text, isStreaming: message.isStreaming)
        }
    }

    /// 助手正文的 Markdown 呈现（解析只走 `MarkdownDocument`，见 `AgentMarkdownBody`）。
    private func markdownBody(_ text: String, isStreaming: Bool) -> some View {
        AgentMarkdownBody(
            text: text,
            isStreaming: isStreaming,
            font: Self.transcriptFont,
            highlight: highlightNeedle,
            tint: Theme.chat(.assistant, colorScheme)
        )
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
            stateGlyph: statusStateGlyph,
            elapsed: model.lastElapsedSeconds.map { String(format: "%.1fs", $0) },
            model: modelName,
            contextUsed: readings.contextUsed,
            contextWindow: readings.contextWindow,
            contextPercent: readings.contextPercent,
            cachePercent: readings.cacheHitPercent,
            tokensPerSecond: model.tokensPerSecond
        )
    }

    /// 状态词前面那个字形（`FR-AGT-UX-CONV-012` 的「状态指示字形」）：
    /// 跑着 ⇒ 运行中那一档；端点就绪 ⇒ 就绪那一档；其余（没配 / 连不上）**不给字形**
    /// —— 那一态在别处已经有一句「为什么不能发」，这里挂个 ❌ 只会让状态词自相矛盾。
    private var statusStateGlyph: String {
        let style = appState.agentDisplayPreferences.indicatorGlyph
        if model.isRunning {
            return AgentDisplayProjection.glyph(for: .running, style: style)
        }
        if case .ready = model.endpointState {
            return AgentDisplayProjection.glyph(for: .ready, style: style)
        }
        return ""
    }

    /// 固定七格之后的「不许静默」读数（压缩 / 续跑 / 完成判据 / 长跑监控 / 本会话 token 账 / 写确认档）。
    private var statusExtras: [String] {
        var extras: [String] = []
        // ⑤ 运行底栏元数据：开 ⇒ 状态行追加**模型 / 上下文百分比 / 工作目录**。
        // 前两格已被 ④ 的固定七格钉死（「模型名永不丢」），所以这里只补状态行真没有的那段
        // （工作目录）—— 同一行不把同一个数印两遍。去重的依据就是 `metadataSegments` 的 `field`。
        for segment in AgentDisplayProjection.metadataSegments(meta: runMeta, preferences: appState.agentDisplayPreferences)
        where segment.field == .workingDirectory {
            extras.append("⌂ " + segment.value)
        }
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
        //
        // **取值必须是 Agent 自己那一档**（`AgentGuardPolicy.requireApprovalForWrites`，落 `agent.json`），
        // 不能拿 SQL 工具条的 `execution.confirmAllWrites` 顶 —— 2026-10-31 现场就是这么错的：
        // 状态行写着「写确认：关」，而 `agent.json` 里 `requireApprovalForWrites: true`，两个开关说两句话。
        extras.append(appState.agentGuardPolicy.requireApprovalForWrites
                      ? L(.agentStatusWritesOn) : L(.agentStatusWritesOff))
        return extras
    }

    /// 运行元数据的**真值源**（`FR-AGT-UX-CONV-012` ⑤）：模型取端点状态、
    /// 上下文百分比取本会话读数、工作目录取当前工作区。**缺的那一项传 `nil`** ——
    /// 「没有读数」不许写成 0（`metadataSegments` 会整段不出）。
    private var runMeta: AgentDisplayProjection.RunMeta {
        var name: String?
        if case .ready(let modelName, _) = model.endpointState { name = modelName }
        let percent = model.modelReadings.contextPercent.map { Int($0.rounded()) }
        return AgentDisplayProjection.RunMeta(model: name,
                                              contextPercent: percent,
                                              workingDirectory: workspacePath)
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

    /// 斜杠命令候选条（`FR-AGT-UX-CONV-014` 输入侧）。
    ///
    /// 一行一条：左边是命令本身（等宽），右边一句话说明；点一下把命令填进输入框。
    /// **候选由 Core 的 `AgentSlashCompleter` 算**（这里不判前缀、不判大小写）——
    /// 界面与解析器共用一套规矩，才不会出现「点得出来、按不进去」。
    private var slashSuggestionStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.xs / 2) {
            ForEach(model.slashSuggestions) { suggestion in
                Button {
                    model.applySlashSuggestion(suggestion)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text(suggestion.insertion.trimmingCharacters(in: .whitespaces))
                            .font(Self.transcriptFont)
                            .foregroundStyle(Theme.accentColor)
                        Text(suggestion.detail)
                            .font(Self.transcriptFont)
                            .foregroundStyle(Theme.text(.secondary))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(suggestion.detail)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
    }


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
            // 斜杠命令候选（`FR-AGT-UX-CONV-014` 输入侧）：敲了 `/` 就出，进了参数区自动收。
            if !model.slashSuggestions.isEmpty {
                slashSuggestionStrip
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
