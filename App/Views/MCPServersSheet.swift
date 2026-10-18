import DoyahCore
import SwiftUI

/// **MCP 服务器配置面**（`FR-AI-21` 的界面片）：加 / 删 / 开关 server、逐工具开关、
/// 「连不上」如实显示。
///
/// 三件刻意的口径：
///
/// · **只用系统标准控件与文字按钮**（人类主人 2026-10-16 订正：弹出对话框与二次配置界面走系统风格，
///   只有主界面工具条才图标化）。所以这里不摆任何纯图标按钮。
/// · **每一行都要有「现在什么状态」**：连上 / 关掉 / 起不来 / 连不上，四种说法各不相同，
///   且都带**机器原话**（`code` / `detail`）—— 用户不必猜「为什么没反应」（验收 ⑤）。
/// · **文本 ⇄ 配置的换算不在本文件里**：`MCPClientConfigurationDraft`（Core）一处做，
///   本文件只把绑定接上去。面板上改的东西存下去到底是什么，由那条判据守着。
struct MCPServersSheet: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft = MCPClientConfigurationDraft()
    @State private var isLoaded = false
    @State private var isBusy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.mcpServersTitle))
                .font(.headline)
            Text(L(.mcpServersHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if draft.servers.isEmpty {
                        Text(L(.mcpServersEmptyHint))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(Array(draft.servers.enumerated()), id: \.offset) { index, _ in
                            serverEditor(index)
                            if index < draft.servers.count - 1 { Divider() }
                        }
                    }
                    problemList
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 560)
        .task { load() }
    }

    // MARK: - 一条 server

    @ViewBuilder
    private func serverEditor(_ index: Int) -> some View {
        let server = draft.servers[index]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle(isOn: $draft.servers[index].enabled) {
                    Text(L(.mcpServersEnabled))
                }
                .toggleStyle(.checkbox)
                TextField(L(.mcpServersName), text: $draft.servers[index].name,
                          prompt: Text(L(.mcpServersNamePlaceholder)))
                    .textFieldStyle(.roundedBorder)
                Button(L(.mcpServersDelete)) { draft.removeServer(at: index) }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Picker(L(.mcpServersTransport), selection: $draft.servers[index].transport) {
                    Text(L(.mcpServersTransportStdio)).tag(MCPClientTransportKind.stdio)
                    Text(L(.mcpServersTransportHTTP)).tag(MCPClientTransportKind.http)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 260, alignment: .leading)
                TextField(L(.mcpServersCommand), text: $draft.servers[index].command,
                          prompt: Text(L(.mcpServersCommandPlaceholder)))
                    .textFieldStyle(.roundedBorder)
            }

            if server.transport == .http {
                Text(L(.mcpServersTransportHint))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            labelledEditor(L(.mcpServersArgs), text: $draft.servers[index].argsText,
                           hint: L(.mcpServersArgsHint), height: 54)
            labelledEditor(L(.mcpServersEnv), text: $draft.servers[index].envText,
                           hint: L(.mcpServersEnvHint), height: 54)

            statusLine(server)
            toolsEditor(server)
        }
        .padding(.vertical, 2)
    }

    private func labelledEditor(_ title: String, text: Binding<String>,
                               hint: String, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
            TextEditor(text: text)
                .font(.system(.caption, design: .monospaced))
                .frame(height: height)
                .border(.separator)
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// 这一条现在的状态（连上 / 关掉 / 起不来 / 连不上 / 还没连过）。
    @ViewBuilder
    private func statusLine(_ server: MCPClientServerDraft) -> some View {
        let report = report(for: server)
        VStack(alignment: .leading, spacing: 2) {
            Text(stateHeadline(report))
                .font(.caption)
                .foregroundStyle(report?.state.isConnected == true ? .primary : .secondary)
            if let detail = stateReason(report) {
                Text(L(.mcpServersStateReason, detail))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            ForEach(report?.notes ?? [], id: \.self) { note in
                Text(noteText(note))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 远端工具 + 逐工具开关。**没连上就如实说「还没连上」**，不画一排假开关。
    @ViewBuilder
    private func toolsEditor(_ server: MCPClientServerDraft) -> some View {
        let tools = discoveredTools(server)
        if tools.isEmpty {
            Text(L(.mcpServersToolsEmpty))
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(L(.mcpServersTools))
                    .font(.caption)
                ForEach(tools, id: \.name) { tool in
                    HStack(spacing: 8) {
                        Text(tool.name)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Picker("", selection: policyBinding(server: server.name, tool: tool.name)) {
                            Text(L(.mcpServersToolAutomatic)).tag(MCPClientToolPolicy.automatic)
                            Text(L(.mcpServersToolApproval)).tag(MCPClientToolPolicy.approval)
                            Text(L(.mcpServersToolDisabled)).tag(MCPClientToolPolicy.disabled)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)
                    }
                }
            }
        }
    }

    /// 校验与坏行都摆在明面上（`problems` 来自唯一出处，坏行另记）。
    @ViewBuilder
    private var problemList: some View {
        let problems = draft.problems
        let environment = draft.environmentProblems
        if !problems.isEmpty || !environment.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                    Text(problemText(problem))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                ForEach(environment, id: \.self) { code in
                    Text(environmentProblemText(code))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(L(.mcpServersAdd)) { draft.addServer() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(L(.commonCancel)) { dismiss() }
                    .buttonStyle(.bordered)
                Button(L(.commonSave)) { save(andConnect: false) }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                Button(L(.mcpServersSaveAndConnect)) { save(andConnect: true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
            }
            Text(L(.mcpServersConfigPath, MCPClientConfiguration.defaultFileURL.path))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - 读数

    private func load() {
        guard !isLoaded else { return }
        isLoaded = true
        draft = MCPClientConfigurationDraft(configuration: appState.loadAgentMCPConfiguration())
        if let error = appState.agentMCPLoadError {
            message = L(.mcpServersLoadError, error)
        }
    }

    private func save(andConnect connect: Bool) {
        message = nil
        if let failure = appState.saveAgentMCPConfiguration(draft.configuration) {
            message = L(.mcpServersSaveFailed, failure.detail)
            return
        }
        let count = draft.servers.count
        guard connect else {
            message = L(.mcpServersSaved, count)
            return
        }
        isBusy = true
        message = L(.mcpServersConnecting)
        Task {
            await appState.connectAgentMCPNow()
            isBusy = false
            message = L(.mcpServersSaved, count)
            // 存下去再读回来：面板此后显示的就是盘上那份（不是它自己心里那份）。
            draft = MCPClientConfigurationDraft(configuration: appState.agentMCPConfiguration)
        }
    }

    private func report(for server: MCPClientServerDraft) -> MCPClientServerReport? {
        let name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return appState.agentMCPReports.first { $0.name == name }
    }

    private func discoveredTools(_ server: MCPClientServerDraft) -> [MCPClientRemoteTool] {
        guard let report = report(for: server), case .connected(_, _, let tools) = report.state else {
            return []
        }
        return tools
    }

    private func policyBinding(server: String, tool: String) -> Binding<MCPClientToolPolicy> {
        Binding(get: { draft.policy(server: server, tool: tool) },
                set: { draft.setPolicy($0, server: server, tool: tool) })
    }

    // MARK: - 人话

    private func stateHeadline(_ report: MCPClientServerReport?) -> String {
        guard let report else { return L(.mcpServersStateNeverConnected) }
        switch report.state {
        case .disabled:
            return L(.mcpServersStateDisabled)
        case .notConnectable(let code, let detail):
            return L(.mcpServersStateNotConnectable, code, detail)
        case .unsupported(let code, _):
            return L(.mcpServersStateUnsupported, code)
        case .unreachable(let code, _):
            return L(.mcpServersStateUnreachable, code)
        case .connected(let serverName, let version, let tools):
            return L(.mcpServersStateConnected, serverName, version, tools.count)
        }
    }

    /// 「原因原样」那一行：连不上 / 起不来时才给（连上了就没有原因可说）。
    private func stateReason(_ report: MCPClientServerReport?) -> String? {
        guard let report else { return nil }
        switch report.state {
        case .disabled, .connected:
            return nil
        case .notConnectable(_, let detail), .unreachable(_, let detail):
            return detail.isEmpty ? nil : detail
        case .unsupported(_, let detail):
            return detail.isEmpty ? nil : detail
        }
    }

    private func problemText(_ problem: MCPClientConfigProblem) -> String {
        switch problem {
        case .emptyName(let index):
            return L(.mcpServersProblemEmptyName, index + 1)
        case .duplicateName(let index, let name):
            return L(.mcpServersProblemDuplicateName, index + 1, name)
        case .stdioWithoutCommand(let index, _):
            return L(.mcpServersProblemNoCommand, index + 1)
        case .unsupportedTransport(let index, _, let kind):
            return L(.mcpServersProblemTransport, index + 1, kind.rawValue)
        }
    }

    /// 机器码 `envLine:<第几条>:<第几行>` → 人话。认不出的原样印（不猜、不吞）。
    private func environmentProblemText(_ code: String) -> String {
        let parts = code.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "envLine",
              let index = Int(parts[1]), let line = Int(parts[2]) else {
            return code
        }
        let name = draft.servers.indices.contains(index)
            ? draft.servers[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let prefix = name.isEmpty ? "\(index + 1). " : "\(name) · "
        return prefix + L(.mcpServersEnvLineBad, line)
    }

    private func noteText(_ note: String) -> String {
        if note.hasPrefix("nameConflict:") {
            return L(.mcpServersNoteConflict, String(note.dropFirst("nameConflict:".count)))
        }
        if note.hasPrefix("disabledTools:"), let count = Int(note.dropFirst("disabledTools:".count)) {
            return L(.mcpServersNoteDisabled, count)
        }
        return note
    }
}
