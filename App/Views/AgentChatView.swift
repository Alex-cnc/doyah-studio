import SwiftUI
import DoyahCore

/// 对话页签的视图（`FR-AI-25`）：消息流（**流式**）+ 工具卡片（可展开）+ **内联审批** + 输入区。
///
/// 它是 `WorkspaceTab.Kind.agentChat` 的内容 —— **挂在 Home 区页签条上**，
/// 自带**不分栏、不带侧栏**（判据 `AgentChatTests` 扫的就是这一点）。
struct AgentChatView: View {

    @ObservedObject var model: AgentChatModel
    /// 定时 agent 面板的入口（`FR-AI-27`）：面板本身读的是 `AppState` 里的条目与历史。
    @EnvironmentObject private var appState: AppState
    @FocusState private var inputFocused: Bool
    /// 发丝线要按当前外观取色（深色主题用白色低透明叠加，浅色主题用实色）。
    @Environment(\.colorScheme) private var colorScheme
    /// 任务清单是否展开（TUI 的 `▸/▾` 折叠）。跑着时默认收起、只留最后两步。
    @State private var stepsExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            // **输入框上面的任务清单**（人类主人 2026-10-17：「DSH-tui 那个任务清单也挺好，
            // 用户可以看到你正在执行到哪一步了」）—— 行内一行一步，只在本轮有步骤时出现。
            taskList
            currentActionRow
            Divider()
            composer
            // **信息面**（人类主人 2026-10-17：「参考 Hermes 的 cli 界面」+ dsh-tui 输入框下那条状态行）：
            // 摆在**输入框下面**，与两边一致。
            Divider()
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

    private var transcript: some View {
        // **跟着最新内容走**（人类主人 2026-10-17 实机反馈：「对话框不自动滚动到最新位置，要手工拖动」）。
        // 读数取 `model.scrollTick`（消息条数 + 正文总长 + 卡片数）—— 流式逐段出现、过程块追加、
        // 卡片新增，任何一种都会让读数变大 ⇒ 一次滚动跟随；只在**内容真的变了**时动手，不空转。
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    // **空态**（§9.1.16 ⑦）：新会话一片空白时，给一句能直接发出去的起手话。
                    // 空白屏不是「干净」，是「不知道该说什么」—— 别的区域都有空态，这里不该例外。
                    if AgentChatEmptyStateGate.shouldShow(messageCount: model.messages.count,
                                                          cardCount: model.cards.count,
                                                          isRunning: model.isRunning) {
                        emptyState
                    }
                    ForEach(model.messages) { message in
                        messageRow(message)
                    }
                    ForEach(model.cards) { card in
                        toolCard(card)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .onChange(of: model.scrollTick) { _ in follow(proxy) }
            .onChange(of: model.isRunning) { _ in follow(proxy) }
            .onAppear { follow(proxy, animated: false) }
        }
    }

    /// 空会话的起手话（TUI 语汇：无卡片、无底纹，只有两行等宽字）。
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(.agentChatEmptyTitle))
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.primary))
            Text(L(.agentChatEmptyHint))
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    /// 滚到底。**不抢正在往上翻的人的手**：只在内容变化时执行，且用户点「回到最新」也能主动调它。
    private func follow(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    /// 一条助手消息的两个动作：复制 / 重发（§9.1.16 ③）。
    @ViewBuilder
    private func messageActions(_ message: AgentChatMessage) -> some View {
        HStack(spacing: 10) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
                copiedMessageID = message.id
            } label: {
                Text(copiedMessageID == message.id ? "✓" : "⧉")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.text(.secondary))
            }
            .buttonStyle(.plain)
            .help(L(.agentMessageCopy))

            Button {
                Task { await model.resend(assistantMessageID: message.id) }
            } label: {
                Text("↻")
                    .font(.system(.caption, design: .monospaced))
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
    private static let transcriptFont = Font.system(.callout, design: .monospaced)

    /// 行首栏：**固定宽度**的字形列，正文一律左对齐（TUI 的 gutter）。
    private func gutter(_ glyph: String, _ tint: Color) -> some View {
        Text(glyph)
            .font(Self.transcriptFont)
            .foregroundStyle(tint)
            .frame(width: 14, alignment: .leading)
    }

    @ViewBuilder
    private func messageRow(_ message: AgentChatMessage) -> some View {
        switch message.role {
        case .user:
            // TUI 里用户消息是 `❯ 正文`，**不是右对齐气泡** —— 去掉气泡是这一版最大的外观变化。
            HStack(alignment: .top, spacing: 8) {
                gutter("❯", Theme.accentColor)
                AgentTranscriptText(text: message.text, font: Self.transcriptFont)
                Spacer(minLength: 0)
            }
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                gutter("┊", Theme.text(.secondary))
                AgentTranscriptText(text: message.text, font: Self.transcriptFont)
                if message.isStreaming {
                    // 流式光标：**逐段**出现时它一直在（`FR-AI-25` ②）
                    Text("▌").font(Self.transcriptFont).foregroundStyle(Theme.text(.secondary))
                }
                Spacer(minLength: 0)
                // **消息级操作**（§9.1.16 ③）：悬停才出现，不常驻 —— TUI 的正文里不该挂按钮条。
                // 流式中不给（那一条还没有可复制的结果），正在跑时「重发」也不给（会撞正在跑的那一轮）。
                if !message.isStreaming {
                    messageActions(message)
                }
            }
        case .tool:
            // 工具结果在 TUI 里是**缩进的圆角小框**（`messageLine.tsx`：`borderStyle="round"` + 缩进 3）。
            HStack(alignment: .top, spacing: 8) {
                gutter("⚡", Theme.text(.secondary))
                Text(message.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.text(.secondary))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.hairline(colorScheme), lineWidth: 1)
                    )
                Spacer(minLength: 0)
            }
        case .notice:
            // 时间线事件：`◈` + 灰字，不带栏（TUI 的 `kind === 'event'`）。
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                gutter("◈", Theme.text(.secondary))
                Text(noticeText(message.text))
                    .font(Self.transcriptFont)
                    .foregroundStyle(Theme.text(.secondary))
            }
        }
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

    @ViewBuilder
    private func toolCard(_ card: AgentToolCard) -> some View {
        // §7.9.10：工具卡也守在行首栏里 —— `⚡` 占 14pt，卡体从同一条竖线起；
        // 状态用**文字标记**（`✓ ✗ ◐ ⚠`）而不是 SF Symbol，图标会带自己的光学重心，破了等宽的列。
        // 可以描边，**不许底纹**：卡体只留一圈 hairline 圆角，不再铺 panel 底色。
        HStack(alignment: .top, spacing: 8) {
            gutter("⚡", Theme.accentColor)
            toolCardBody(card)
        }
    }

    @ViewBuilder
    private func toolCardBody(_ card: AgentToolCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(mark(for: card))
                    .font(Self.transcriptFont)
                    .foregroundStyle(tint(for: card))
                Text(card.name).font(Self.transcriptFont)
                Text(card.statusCode).font(.caption).foregroundStyle(Theme.text(.secondary))
                Spacer()
                Button {
                    model.toggle(card.id)
                } label: {
                    Text(card.expanded ? "▾" : "▸")
                        .font(Self.transcriptFont)
                        .foregroundStyle(Theme.text(.secondary))
                }
                .buttonStyle(.plain)
                .help(card.expanded ? L(.agentChatCollapse) : L(.agentChatExpand))
            }
            if card.expanded {
                if let preview = card.approvalPreview {
                    Text(preview)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.hairline(colorScheme), lineWidth: 1)
                        )
                } else if !card.arguments.isEmpty {
                    Text(card.arguments)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(Theme.text(.secondary))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.hairline(colorScheme), lineWidth: 1)
                        )
                }
            }
            // ③「展开可见**用的哪个模型与端点**」（`FR-AI-25` ③）：每张卡展开都带这一行 ——
            // 不能只靠底部状态行（那里是「这一轮」的读数，卡片可能属于上一轮 / 上一个端点）。
            // 端点没配 / 连不上就**如实说**，不写死、不假装在跑。
            if card.expanded, let line = endpointLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(Theme.text(.secondary))
                    .textSelection(.enabled)
            }
            if case .pendingApproval = card.outcome {
                HStack(spacing: 8) {
                    Text(L(.agentChatApprovalPending)).font(.caption).foregroundStyle(Theme.text(.secondary))
                    ToolbarIconButton(systemName: "checkmark.circle", help: L(.agentChatApprovalApprove)) { model.approve(card.id) }
                        .controlSize(.small)
                    ToolbarIconButton(systemName: "xmark.circle", help: L(.agentChatApprovalDeny)) { model.deny(card.id) }
                        .controlSize(.small)
                }
            }
            if case .applied = card.outcome {
                HStack(spacing: 8) {
                    Text(L(.agentChatApprovalApplied)).font(.caption).foregroundStyle(Theme.text(.secondary))
                    // **一步撤销**（`FR-AI-25` ⑤）：点了就把这次写入退回去，文件逐字节回到应用前。
                    // 只出现在「已应用」这一档 —— 别的状态没有可撤的东西。
                    ToolbarIconButton(systemName: "arrow.uturn.backward", help: L(.agentChatUndo)) {
                        model.undo(card.id)
                    }
                    .controlSize(.small)
                }
            }
            if case .undone = card.outcome {
                Text(L(.agentChatUndone)).font(.caption).foregroundStyle(Theme.text(.secondary))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.hairline(colorScheme), lineWidth: 1)
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

    // MARK: - 任务清单（走到哪了）

    @ViewBuilder
    private var taskList: some View {
        if !model.steps.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                // 表头就是 TUI 的 todo 面板那一行：`▸ 任务清单 (3/5)`，灰字带计数。
                Button {
                    stepsExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var doneStepCount: Int {
        model.steps.filter { $0.status == .done }.count
    }

    @ViewBuilder
    private func stepRow(_ step: AgentChatStep, isLast: Bool) -> some View {
        HStack(spacing: 6) {
            // 树轨：TUI 的 `├─` / `└─`
            Text(isLast ? "└─" : "├─")
                .font(Self.transcriptFont)
                .foregroundStyle(Theme.text(.tertiary))
            Text(stepMark(for: step))
                .font(Self.transcriptFont)
                .foregroundStyle(tint(for: step))
            Text(step.tools.joined(separator: " · "))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.text(.secondary))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
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
            HStack(spacing: 6) {
                BrailleSpinner()
                Text(action)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(L(.agentChatRunning2))
                    .font(.caption).foregroundStyle(Theme.text(.secondary))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }

    // MARK: - 信息面（输入框下面那条状态行）

    /// **状态块**（输入框**下面** —— dsh-tui 的位置），两行：
    ///
    /// - 第 1 行（右对齐）：**上下文读数** + **会话累计 token**（dsh 的 `14k/1.0M 1.4%` 那一格）
    /// - 第 2 行：模型 · 端点主机 · 耗时 · 吞吐 · 工作区 · 写确认档 · **最右 = 会话标题**（Hermes 的那一格）
    ///
    /// **如实登记：宁缺不假**。dsh 还有 `cache 96.6%` 与 `≈¥0.02`、Hermes 还有 `~23%` 占比 ——
    /// 那三样要**真值源**（端点的 cache 读数 / 价目表 / 模型窗口大小），仓里都没有 ⇒ 这三格**不放数**。
    /// 要加，先在设置里补那张表或那个读数（已在提交信息里登记）。
    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Spacer()
                // **压缩读数**（`NFR-AI-08` ③）：压了几段、约省多少 token —— 压缩不许静默。
                // 只在真压过时出现（`nil` 不留空壳）；`.help` 里是「最早被压掉的那一段」的摘要。
                if let compression = model.contextCompression {
                    Text(L(.agentStatusCompressed,
                           "\(compression.entries)",
                           "\(compression.estimatedTokensSaved)"))
                        .foregroundStyle(Theme.status(.warning))
                        .help(compression.earliest)
                }
                // **续跑读数**（`NFR-AI-08` ⑤）：续上第几跳、退回几跳 —— 续跑不许静默。
                // 只在真续上时出现（`nil` 不留空壳）；坏行数 > 0 时补一句（`0` 就不留空壳）。
                if let resume = model.resumeReading {
                    Text(L(.agentStatusResumed,
                           "\(resume.fromStep + 1)",
                           "\(resume.skippedSteps)"))
                        .foregroundStyle(Theme.accentColor)
                        .help(resume.skippedCheckpointLines > 0
                              ? L(.agentStatusResumeBadLines, "\(resume.skippedCheckpointLines)")
                              : "")
                }
                // **完成判据读数**（`FR-AI-31` ②）：模型说完成时，这一行给出复核结论 ——
                // 通过了就报几条引用；没通过就**如实说未验证**（原因进 `.help`）。
                // 不许把它并进「跑完了」那一格：跑完 ≠ 做成（SRS 负例）。
                if let completion = model.completionReading, completion.isVerified || completion.isUnverified {
                    Text(completion.isVerified
                         ? L(.agentStatusCompletionVerified, "\(completion.citations)")
                         : L(.agentStatusCompletionUnverified))
                        .foregroundStyle(completion.isVerified ? Theme.status(.success) : Theme.status(.warning))
                        .help(completion.isVerified ? "" : completion.reason)
                }
                // **信息面三格**（`FR-AI-25`）：上下文占用 / 缓存命中率 / 本会话估算花费。
                // 三格都**只在真值源在时出现** —— 窗口认不出就明说「窗口未知」，
                // 端点没报缓存就不画那一格（不当 0%），没填价目就不给钱数（不自造 ¥0）。
                let readings = model.modelReadings
                if let used = readings.contextUsed {
                    if let window = readings.contextWindow, let percent = readings.contextPercent {
                        Text(L(.agentStatusContextOfWindow,
                               AgentTokenShort.text(used),
                               AgentTokenShort.text(window),
                               AgentModelReadings.percentText(percent)))
                            .foregroundStyle(percent >= 90 ? Theme.status(.warning) : Theme.text(.secondary))
                    } else {
                        Text(L(.agentStatusContextWindowUnknown, AgentTokenShort.text(used)))
                    }
                }
                if let cache = readings.cacheHitPercent {
                    Text(L(.agentStatusCache, AgentModelReadings.percentText(cache)))
                        .help(L(.agentStatusCacheHelp))
                }
                if let cost = readings.estimatedCost {
                    Text(readings.costIsUpperBound
                         ? L(.agentStatusCostUpperBound, cost.text)
                         : L(.agentStatusCost, cost.text))
                        .help(readings.costIsUpperBound ? L(.agentStatusCostUpperBoundHelp) : L(.agentStatusCostHelp))
                }
                // **长跑监控读数**（`FR-AI-31` ③）：卡住 / 空转 / 反复重试 / 配额将尽 —— 跑飞不许静默。
                // 只在真报过时出现（`nil` 不留空壳）；卡住那一档用更重的颜色（那要人动手）。
                if let monitor = model.monitorReading {
                    Text(L(.agentStatusMonitor, monitorText(monitor)))
                        .foregroundStyle(monitor.isStalled ? Theme.status(.danger) : Theme.status(.warning))
                        .help(L(.agentStatusMonitor, monitorText(monitor)))
                }
                if model.sessionUsage.requests > 0 {
                    Text(L(.agentStatusSession,
                           "\(model.sessionUsage.requests)",
                           "\(model.sessionUsage.promptTokens)",
                           "\(model.sessionUsage.completionTokens)",
                           "\(model.sessionUsage.totalTokens)"))
                    if model.sessionUsage.responsesWithoutUsage > 0 {
                        Text(L(.agentStatusNoUsage)).foregroundStyle(Theme.status(.warning))
                    }
                }
            }

            HStack(spacing: 8) {
                if case .ready(let modelName, let endpoint) = model.endpointState {
                    Text(L(.agentStatusModel, modelName))
                    Text(URL(string: endpoint)?.host ?? endpoint).foregroundStyle(Theme.text(.secondary))
                } else {
                    Text(L(.agentChatEndpointNotConfigured)).foregroundStyle(Theme.text(.secondary))
                }
                if let seconds = model.lastElapsedSeconds {
                    Text(L(.agentStatusElapsed, String(format: "%.1f", seconds)))
                }
                if let rate = model.tokensPerSecond {
                    Text(String(format: "%.0f token/s", rate)).foregroundStyle(Theme.text(.secondary))
                }
                if let root = WorkspaceStore.shared.rootPath, !root.isEmpty {
                    Text(L(.agentStatusWorkspace, URL(fileURLWithPath: root).lastPathComponent))
                }
                Text(appState.isConfirmAllWritesEnabled ? L(.agentStatusWritesOn) : L(.agentStatusWritesOff))
                    .foregroundStyle(appState.isConfirmAllWritesEnabled ? Theme.text(.secondary) : Theme.status(.warning))

                Spacer()

                // **会话标题在最右**（人类主人 2026-10-17：「最右侧加上 hermes 有的那个会话标题就完美了」）。
                // 取首条提问，不另花钱生成；没有提问时这格不出现（不留空壳）。
                if let title = model.sessionTitle {
                    Text("» " + title).foregroundStyle(Theme.text(.secondary)).help(title)
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(Theme.text(.secondary))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - 输入区（端点没配好时**如实拦住**，不假装在跑）

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let blocker = model.blockerText {
                HStack(spacing: 6) {
                    Text("◈").font(Self.transcriptFont).foregroundStyle(Theme.status(.warning))
                    Text(blocker).font(.callout)
                }
                .foregroundStyle(Theme.text(.secondary))
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("❯")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.accentColor)
                TextField(L(.agentChatPlaceholder), text: $model.input)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($inputFocused)
                    .onSubmit { if model.canSend { Task { await model.send() } } }
                if model.isRunning {
                    Text(L(.agentChatRunning)).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.text(.secondary))
                    ToolbarIconButton(systemName: "stop.fill", help: L(.agentChatStop)) { model.stop() }
                } else {
                    // **继续上次**（`NFR-AI-08` ⑤）：上一轮没走完（限额 / 取消 / 失败）才有这一枚 ——
                    // 点了接着那一轮停在的跳跑，**已完成的跳不重放**。没得续时整枚不出现（不留空壳）。
                    if let step = model.continueStep {
                        ToolbarIconButton(systemName: "play.circle",
                                          help: L(.agentChatContinue, "\(step)")) {
                            Task { await model.continueLast() }
                        }
                    }
                    ToolbarIconButton(systemName: "paperplane", help: L(.agentChatSend)) { Task { await model.send() } }
                        .disabled(!model.canSend)
                }
                // 定时 agent 的入口（`FR-AI-27`）：面板里设「什么时候起一次会话」；
                // 起不起得来、要不要审批都归既有那条路（定时不构成授权）。
                ToolbarIconButton(systemName: "clock.arrow.circlepath",
                                  help: AppShortcut.agentSchedule.help(L(.agentScheduleTitle))) {
                    appState.isAgentSchedulePresented = true
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.hairline(colorScheme), lineWidth: 1)
            )
        }
        .padding(12)
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
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(tint)
        }
    }
}
