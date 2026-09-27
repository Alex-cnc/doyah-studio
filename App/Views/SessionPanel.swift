import SwiftUI
import DoyahCore

/// 服务器会话面板（FR-SESS-01 / FR-SESS-02）。
///
/// 与「锁与阻塞」面板是两类视角：那个看**等待关系**，这个看**全部会话**。
/// 界面上要说清两件事，否则用户会踩：
/// 1. **权限**：普通用户只能操作自己的会话（PG 需要同用户或 `pg_signal_backend`）；
/// 2. **终止是不可逆的**：`pg_terminate_backend` 会把那条连接整个掐掉，因此必须二次确认，
///    而「取消当前语句」相对温和 —— 两者不能做成一样重的动作。
struct SessionPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [ServerSession] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var selectedPID: Int?
    /// 待确认的终止目标（`nil` = 没有待确认的操作）。
    @State private var pendingTerminate: ServerSession?

    /// 面板的**初始会话列表**（队列 L-18 的「可注入口子」；口子形状由 L-12 定）。
    ///
    /// 为什么需要它：`sessions` 是私有 `@State`、`.task` 打开即 `await loadServerSessions()`，
    /// 没选连接时只会抛 `notConnected` ⇒ 离线永远只能拍到「红字错误 + 空占位」那种**真运行态**，
    /// 而「连上了、这次查到 0 条会话」这个**纯空态**在快照里根本不可达（L-11 第 11 轮实测）。
    ///
    /// 三条口径（与 `ERDiagramPanel(initialDiagram:)` 同源）：
    ///   ① 它只**给初值**，不改任何行为分支 —— 生产路径（`MainWindow`）不传，行为与以前逐字一致；
    ///   ② 它不是测试后门：没有「测试才走」的分支，也不放行被禁动作 ——
    ///      终止 / 取消语句两个按钮照样按 `selectedPID` 灰着；
    ///   ③ `nil` 与 `[]` **语义不同**：`nil` = 没注入（照旧去取），`[]` = 注入「取过了，就是 0 条」——
    ///      这正是「拦下那次取数」能表达出来的原因（非可选的话两者分不开）。
    private let injectedSessions: [ServerSession]?

    init(initialSessions: [ServerSession]? = nil) {
        self.injectedSessions = initialSessions
        _sessions = State(initialValue: initialSessions ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text(L(.sessionTitle)).font(Theme.font(.title))
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Label(L(.sessionRefresh), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
            }

            Text(L(.sessionPermissionNote))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
                .fixedSize(horizontal: false, vertical: true)

            if let errorText {
                Text(errorText)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.danger))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isLoading && sessions.isEmpty {
                HStack(spacing: Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text(L(.sessionLoading)).font(Theme.font(.body)).foregroundStyle(Theme.text(.secondary))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.isEmpty {
                ContentUnavailableView(L(.sessionEmpty), systemImage: "person.2.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedPID) {
                    ForEach(sessions) { session in
                        row(session).tag(session.pid)
                    }
                }
                .listStyle(.inset)
            }

            HStack(spacing: Spacing.s) {
                Text(L(.sessionCount, sessions.count))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                Spacer()
                Button(L(.sessionCancelStatement)) {
                    guard let selectedPID else { return }
                    Task { await cancelStatement(pid: selectedPID) }
                }
                .disabled(selectedPID == nil)
                .help(L(.sessionCancelStatementHelp))

                Button(L(.sessionTerminate)) {
                    pendingTerminate = sessions.first { $0.pid == selectedPID }
                }
                .disabled(selectedPID == nil)
                .help(L(.sessionTerminateHelp))

                Button(L(.commonClose)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.l)
        .frame(width: 860, height: 520)
        // `injectedSessions != nil` 是「给了初值就不去取」的**唯一**保证（见 `init(initialSessions:)`）：
        // 去掉它，注入进来的空列表会被紧随其后的 `reload()` 覆写成「红字错误 + 空占位」。
        .task { if injectedSessions == nil { await reload() } }
        // 二次确认：终止会话会掐断连接，不能一键就做。
        .confirmationDialog(
            L(.sessionTerminateConfirmTitle, pendingTerminate?.pid ?? 0),
            isPresented: Binding(
                get: { pendingTerminate != nil },
                set: { if !$0 { pendingTerminate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L(.sessionTerminateConfirm), role: .destructive) {
                if let pid = pendingTerminate?.pid {
                    Task { await terminate(pid: pid) }
                }
                pendingTerminate = nil
            }
            Button(L(.commonCancel), role: .cancel) { pendingTerminate = nil }
        } message: {
            Text(L(.sessionTerminateConfirmMessage, pendingTerminate?.user ?? "?", pendingTerminate?.database ?? "?"))
        }
    }

    // MARK: 行

    private func row(_ session: ServerSession) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Text("\(session.pid)")
                .font(Theme.font(.data))
                .foregroundStyle(Theme.text(.secondary))
                .frame(width: 64, alignment: .trailing)

            VStack(alignment: .leading, spacing: Spacing.hair) {
                HStack(spacing: Spacing.xs) {
                    Text(session.user ?? "—").font(Theme.font(.bodyStrong))
                    Text(session.database ?? "—")
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                    if let address = session.clientAddress, !address.isEmpty {
                        Text(address)
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.tertiary))
                    }
                    if session.isWaiting {
                        // 等待中的会话排在最前，也在这里标明 —— 排查时第一眼要看的就是它。
                        Text(L(.sessionWaiting))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.status(.warning))
                    }
                }
                Text(session.querySummary)
                    .font(Theme.font(.monoSmall))
                    .foregroundStyle(Theme.text(.primary))
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.hair) {
                Text(session.state ?? "—")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                if let elapsed = session.elapsedSeconds(), elapsed >= 0 {
                    Text(L(.sessionElapsed, Int(elapsed)))
                        .font(Theme.font(.data))
                        .foregroundStyle(elapsed > 300 ? Theme.status(.warning) : Theme.text(.tertiary))
                }
                if let wait = session.waitEvent {
                    Text(wait)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.status(.warning))
                }
            }
        }
        .padding(.vertical, Spacing.hair)
    }

    // MARK: 动作

    private func reload() async {
        isLoading = true
        errorText = nil
        do {
            sessions = try await appState.loadServerSessions()
            if let selectedPID, !sessions.contains(where: { $0.pid == selectedPID }) {
                self.selectedPID = nil
            }
        } catch {
            errorText = L(.sessionLoadFailed, ErrorPresenter.message(for: error))
        }
        isLoading = false
    }

    private func cancelStatement(pid: Int) async {
        let message = await appState.cancelSessionStatement(pid: pid)
        errorText = message.isEmpty ? nil : message
        await reload()
    }

    private func terminate(pid: Int) async {
        let message = await appState.terminateSession(pid: pid)
        errorText = message.isEmpty ? nil : message
        await reload()
    }
}
