import SwiftUI
import DoyahCore

/// 对话页签的视图（`FR-AI-25`）：消息流（**流式**）+ 工具卡片（可展开）+ **内联审批** + 输入区。
///
/// 它是 `WorkspaceTab.Kind.agentChat` 的内容 —— **挂在 Home 区页签条上**，
/// 自带**不分栏、不带侧栏**（判据 `AgentChatTests` 扫的就是这一点）。
struct AgentChatView: View {

    @ObservedObject var model: AgentChatModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            composer
        }
        .onAppear { model.refreshEndpoint() }
    }

    // MARK: - 消息流 + 卡片

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(model.messages) { message in
                    messageRow(message)
                }
                ForEach(model.cards) { card in
                    toolCard(card)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
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
                    .onSubmit { if model.canSend { model.send() } }
                if model.isRunning {
                    Text(L(.agentChatRunning)).font(.caption).foregroundStyle(.secondary)
                    ToolbarIconButton(systemName: "stop.fill", help: L(.agentChatStop)) { model.stop() }
                } else {
                    ToolbarIconButton(systemName: "paperplane", help: L(.agentChatSend)) { model.send() }
                        .disabled(!model.canSend)
                }
            }
        }
        .padding(12)
    }
}
