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
        .onAppear { model.refreshEndpoint() }
        .sheet(isPresented: $appState.isAgentSchedulePresented) {
            AgentScheduleSheet().environmentObject(appState)
        }
    }

    // MARK: - 消息流 + 卡片

    /// 底部锚的 id（自动滚动用）。
    private static let bottomAnchor = "agentChatBottom"

    private var transcript: some View {
        // **跟着最新内容走**（人类主人 2026-10-17 实机反馈：「对话框不自动滚动到最新位置，要手工拖动」）。
        // 读数取 `model.scrollTick`（消息条数 + 正文总长 + 卡片数）—— 流式逐段出现、过程块追加、
        // 卡片新增，任何一种都会让读数变大 ⇒ 一次滚动跟随；只在**内容真的变了**时动手，不空转。
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
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

    /// 滚到底。**不抢正在往上翻的人的手**：只在内容变化时执行，且用户点「回到最新」也能主动调它。
    private func follow(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func messageRow(_ message: AgentChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
        case .assistant:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(message.text)
                    .textSelection(.enabled)
                if message.isStreaming {
                    // 流式光标：**逐段**出现时它一直在（`FR-AI-25` ②）
                    Text("▌").foregroundStyle(.secondary)
                }
            }
        case .tool:
            Text(message.text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        case .notice:
            Text(noticeText(message.text))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon(for: card))
                Text(card.name).font(.system(.body, design: .monospaced))
                Text(card.statusCode).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.toggle(card.id)
                } label: {
                    Image(systemName: card.expanded ? "chevron.down" : "chevron.right")
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
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                } else if !card.arguments.isEmpty {
                    Text(card.arguments)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
            // ③「展开可见**用的哪个模型与端点**」（`FR-AI-25` ③）：每张卡展开都带这一行 ——
            // 不能只靠底部状态行（那里是「这一轮」的读数，卡片可能属于上一轮 / 上一个端点）。
            // 端点没配 / 连不上就**如实说**，不写死、不假装在跑。
            if card.expanded, let line = endpointLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if case .pendingApproval = card.outcome {
                HStack(spacing: 8) {
                    Text(L(.agentChatApprovalPending)).font(.caption).foregroundStyle(.secondary)
                    ToolbarIconButton(systemName: "checkmark.circle", help: L(.agentChatApprovalApprove)) { model.approve(card.id) }
                        .controlSize(.small)
                    ToolbarIconButton(systemName: "xmark.circle", help: L(.agentChatApprovalDeny)) { model.deny(card.id) }
                        .controlSize(.small)
                }
            }
            if case .applied = card.outcome {
                HStack(spacing: 8) {
                    Text(L(.agentChatApprovalApplied)).font(.caption).foregroundStyle(.secondary)
                    // **一步撤销**（`FR-AI-25` ⑤）：点了就把这次写入退回去，文件逐字节回到应用前。
                    // 只出现在「已应用」这一档 —— 别的状态没有可撤的东西。
                    ToolbarIconButton(systemName: "arrow.uturn.backward", help: L(.agentChatUndo)) {
                        model.undo(card.id)
                    }
                    .controlSize(.small)
                }
            }
            if case .undone = card.outcome {
                Text(L(.agentChatUndone)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
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

    private func icon(for card: AgentToolCard) -> String {
        switch card.outcome {
        case .running: return "hourglass"
        case .executed: return "checkmark.circle"
        case .denied: return "xmark.octagon"
        case .pendingApproval, .approved: return "hand.raised"
        case .applied: return "checkmark.seal"
        case .undone: return "arrow.uturn.backward.circle"
        }
    }

    // MARK: - 任务清单（走到哪了）

    @ViewBuilder
    private var taskList: some View {
        if !model.steps.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L(.agentChatStepsTitle, "\(model.steps.count)"))
                    if let seconds = model.lastElapsedSeconds {
                        Text(L(.agentStatusElapsed, String(format: "%.1f", seconds)))
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                // **不再把每一步都铺成一行**（人类主人 2026-10-18：「被你的 step 刷屏了」
                // 「不清楚为什么要把这个 step 打印出来」）—— 这些是机械动作，不是进展：
                // 一次 20 步的活会印 20 行 `list_dir · search`，把真正的回答挤出屏幕。
                //
                // 口径：
                // · **跑着**：只留最后 2 步（知道它此刻在干什么就够了，历史不值钱）；
                // · **跑完**：一行总结（几步 / 多久），明细收进「查看明细」里 —— 要查的时候才看。
                if model.isRunning {
                    ForEach(model.steps.suffix(2)) { step in
                        stepRow(step)
                    }
                } else if model.steps.count > 0 {
                    DisclosureGroup {
                        ForEach(model.steps) { step in
                            stepRow(step)
                        }
                    } label: {
                        Text(L(.agentChatStepsDone, "\(model.steps.count)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .disclosureGroupStyle(.automatic)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func stepRow(_ step: AgentChatStep) -> some View {
        HStack(spacing: 6) {
            Image(systemName: mark(for: step))
                .foregroundStyle(tint(for: step))
                .font(.caption)
            Text(L(.agentChatStepNo, "\(step.index)"))
                .font(.caption)
            Text(step.tools.joined(separator: " · "))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    private func mark(for step: AgentChatStep) -> String {
        switch step.status {
        case .running: return "circle.dotted"
        case .done: return "checkmark.circle"
        case .failed: return "xmark.octagon"
        }
    }

    private func tint(for step: AgentChatStep) -> Color {
        switch step.status {
        case .running: return .accentColor
        case .done: return .secondary
        case .failed: return .orange
        }
    }

    /// **当前动作**（输入框上方**一行**）—— dsh-tui 的 `🌙 … Firing a command … · 1s` 那一格。
    /// 命门是**就地更新、不追加**：跑一百跳也只占这一行（不刷屏）。
    @ViewBuilder
    private var currentActionRow: some View {
        if let action = model.currentAction {
            HStack(spacing: 6) {
                Image(systemName: "circle.dotted").foregroundStyle(Color.accentColor)
                Text(action)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(L(.agentChatRunning2))
                    .font(.caption).foregroundStyle(.secondary)
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
                        .foregroundStyle(.orange)
                        .help(compression.earliest)
                }
                // **续跑读数**（`NFR-AI-08` ⑤）：续上第几跳、退回几跳 —— 续跑不许静默。
                // 只在真续上时出现（`nil` 不留空壳）；坏行数 > 0 时补一句（`0` 就不留空壳）。
                if let resume = model.resumeReading {
                    Text(L(.agentStatusResumed,
                           "\(resume.fromStep + 1)",
                           "\(resume.skippedSteps)"))
                        .foregroundStyle(.blue)
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
                        .foregroundStyle(completion.isVerified ? Color.green : Color.orange)
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
                            .foregroundStyle(percent >= 90 ? Color.orange : Color.secondary)
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
                        .foregroundStyle(monitor.isStalled ? Color.red : Color.orange)
                        .help(L(.agentStatusMonitor, monitorText(monitor)))
                }
                if model.sessionUsage.requests > 0 {
                    Text(L(.agentStatusSession,
                           "\(model.sessionUsage.requests)",
                           "\(model.sessionUsage.promptTokens)",
                           "\(model.sessionUsage.completionTokens)",
                           "\(model.sessionUsage.totalTokens)"))
                    if model.sessionUsage.responsesWithoutUsage > 0 {
                        Text(L(.agentStatusNoUsage)).foregroundStyle(.orange)
                    }
                }
            }

            HStack(spacing: 8) {
                if case .ready(let modelName, let endpoint) = model.endpointState {
                    Text(L(.agentStatusModel, modelName))
                    Text(URL(string: endpoint)?.host ?? endpoint).foregroundStyle(.secondary)
                } else {
                    Text(L(.agentChatEndpointNotConfigured)).foregroundStyle(.secondary)
                }
                if let seconds = model.lastElapsedSeconds {
                    Text(L(.agentStatusElapsed, String(format: "%.1f", seconds)))
                }
                if let rate = model.tokensPerSecond {
                    Text(String(format: "%.0f token/s", rate)).foregroundStyle(.secondary)
                }
                if let root = WorkspaceStore.shared.rootPath, !root.isEmpty {
                    Text(L(.agentStatusWorkspace, URL(fileURLWithPath: root).lastPathComponent))
                }
                Text(appState.isConfirmAllWritesEnabled ? L(.agentStatusWritesOn) : L(.agentStatusWritesOff))
                    .foregroundStyle(appState.isConfirmAllWritesEnabled ? Color.secondary : Color.orange)

                Spacer()

                // **会话标题在最右**（人类主人 2026-10-17：「最右侧加上 hermes 有的那个会话标题就完美了」）。
                // 取首条提问，不另花钱生成；没有提问时这格不出现（不留空壳）。
                if let title = model.sessionTitle {
                    Text("» " + title).foregroundStyle(.secondary).help(title)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: - 输入区（端点没配好时**如实拦住**，不假装在跑）

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let blocker = model.blockerText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(blocker).font(.callout)
                }
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField(L(.agentChatPlaceholder), text: $model.input)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .onSubmit { if model.canSend { Task { await model.send() } } }
                if model.isRunning {
                    Text(L(.agentChatRunning)).font(.caption).foregroundStyle(.secondary)
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
                ToolbarIconButton(systemName: "clock.arrow.circlepath", help: L(.agentScheduleTitle)) {
                    appState.isAgentSchedulePresented = true
                }
            }
        }
        .padding(12)
    }
}
