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
            Divider()
            composer
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
        default: return code
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
                Text(L(.agentChatApprovalApplied)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func icon(for card: AgentToolCard) -> String {
        switch card.outcome {
        case .running: return "hourglass"
        case .executed: return "checkmark.circle"
        case .denied: return "xmark.octagon"
        case .pendingApproval, .approved: return "hand.raised"
        case .applied: return "checkmark.seal"
        }
    }

    // MARK: - 任务清单（走到哪了）

    @ViewBuilder
    private var taskList: some View {
        if !model.steps.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(L(.agentChatStepsTitle, "\(model.steps.count)"))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.steps) { step in
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
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
