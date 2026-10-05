import SwiftUI
import DoyahCore

/// 「锁与阻塞…」面板（FR-DIAG-05）。
///
/// 列出**未获得**的锁及其阻塞者：被阻塞 pid、阻塞者 pid、锁类型 / 模式、对象、
/// 已等待时长，并给出「汇总」行。选中某个被阻塞会话后可「定位阻塞者」，
/// 在面板内直接跳到对应的阻塞行（跳进完整会话列表要等会话面板 T-30）。
struct LockPanel: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var waits: [LockWait] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var hasLoaded = false
    /// 「定位阻塞者」高亮的 pid。
    @State private var highlightedPid: Int?

    /// 面板的**初始等待列表**（队列 L-18 的「可注入口子」；口子形状由 L-12 定）。
    ///
    /// 为什么需要它：`waits` 是私有 `@State`、`.task` 打开即查库，没选连接时走 `catch` ⇒
    /// 离线只能拍到「未选连接提示 + 空列表文案**同屏**」那种真运行态；
    /// 「连上了、这次 0 条等待」这个**纯空态**拍不到（L-16 第 3 批实测，与 `SessionPanel` 同族）。
    ///
    /// 三条口径（与 `ERDiagramPanel(initialDiagram:)` 同源）：
    ///   ① 只**给初值**，生产路径不传 ⇒ 行为逐字不变；
    ///   ② 不是测试后门：没有「测试才走」的分支，「定位阻塞者」按钮照样按数据灰着 / 亮着；
    ///   ③ `nil` 与 `[]` 语义不同：`nil` = 没注入（照旧查库），`[]` = 注入「查过了，0 条」——
    ///      同时把 `hasLoaded` 置真，于是画面停在 `lockEmpty` 那一支（而不是那个占位空格）。
    private let injectedWaits: [LockWait]?

    init(initialWaits: [LockWait]? = nil) {
        self.injectedWaits = initialWaits
        _waits = State(initialValue: initialWaits ?? [])
        _hasLoaded = State(initialValue: initialWaits != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(L(.lockTitle))
                    .font(.headline)

                if isLoading {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                Button(L(.lockRefresh)) {
                    Task { await load() }
                }
                .disabled(isLoading)

                Button(L(.commonClose)) { dismiss() }
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            // 权限说明常驻：无权限时至少让人知道「看到的信息为什么不全」。
            Text(L(.lockPermissionHint))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if waits.isEmpty {
                Text(hasLoaded ? L(.lockEmpty) : " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                summarySection
                tableSection
            }
        }
        .padding(20)
        .frame(width: 760, height: 560)
        // `injectedWaits != nil` 是「给了初值就不去取」的**唯一**保证（见 `init(initialWaits:)`）：
        // 去掉它，注入进来的空列表会被紧随其后的 `load()` 覆写成「未选连接」那一支。
        .task { if injectedWaits == nil { await load() } }
    }

    // MARK: - 汇总

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(LockMonitor.summaryLines(for: waits).prefix(3).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - 列表

    private var tableSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(waits) { wait in
                    row(wait)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ wait: LockWait) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("\(L(.lockColumnPid)) \(wait.pid)")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("→ \(L(.lockColumnBlockedBy)) \(blockersText(wait))")
                    .font(.caption)
                    .foregroundStyle(wait.isBlocked ? .orange : .secondary)

                if let seconds = wait.waitingSeconds {
                    Text("· \(L(.lockColumnWaiting)) \(seconds)s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(wait.granted ? "· \(L(.lockGranted))" : "· \(L(.lockWaitingState))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if let blocker = wait.blockingPids.first, blocker != wait.pid {
                    Button(L(.lockShowBlocker)) {
                        highlightedPid = blocker
                    }
                    .controlSize(.small)
                }
            }

            Text(detailText(wait))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(6)
        .background(
            highlightedPid == wait.pid
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func blockersText(_ wait: LockWait) -> String {
        wait.blockingPids.isEmpty ? "—" : wait.blockingPids.map(String.init).joined(separator: ", ")
    }

    private func detailText(_ wait: LockWait) -> String {
        var parts: [String] = []
        if let database = wait.database { parts.append("\(L(.lockColumnDatabase)) \(database)") }
        if let user = wait.user { parts.append("\(L(.lockColumnUser)) \(user)") }

        let lock = [wait.lockType, wait.mode, wait.relation]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        if !lock.isEmpty { parts.append(lock) }

        if let query = wait.query, !query.isEmpty {
            parts.append(query.replacingOccurrences(of: "\n", with: " "))
        }
        return parts.joined(separator: " | ")
    }

    // MARK: - 加载

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            waits = try await appState.loadLockWaits()
            hasLoaded = true
            if let highlightedPid, !waits.contains(where: { $0.pid == highlightedPid }) {
                self.highlightedPid = nil
            }
        } catch {
            waits = []
            hasLoaded = true
            errorText = ErrorPresenter.message(for: error)
        }
    }
}
