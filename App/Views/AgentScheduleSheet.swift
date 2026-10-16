import SwiftUI
import DoyahCore

/// 定时 agent 的面板（`FR-AI-27` 的界面半）：列表 / 新建与编辑 / 启停 / 执行历史 / 错过确认。
///
/// 规则与文案全在 Core（`AgentSchedulePresentation`）—— 这里只把字段摆上去：
/// 档位、下次时刻、错过提示、历史行的三样（时间 / 结果状态 / 扣下几条）都由那一处算。
struct AgentScheduleSheet: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// 编辑中 / 新建中的那一条（`nil` = 没开编辑）。
    @State private var editing: AgentScheduleEntry?

    private var language: AppLanguage { LocalizationManager.shared.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if appState.agentSchedules.isEmpty {
                emptyState
            } else {
                entryList
            }
            Divider()
            history
            Divider()
            footer
        }
        .frame(width: 600, height: 560, alignment: .topLeading)
        .sheet(item: $editing) { entry in
            AgentScheduleEditor(entry: entry, isNew: !appState.agentSchedules.contains { $0.id == entry.id })
                .environmentObject(appState)
        }
        .task { await appState.loadAgentSchedules() }
    }

    // MARK: - 头（错过提示摆在这里：默认不补跑，只有用户点了才起）

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L(.agentScheduleTitle)).font(.headline)
                Spacer()
                Button(L(.commonClose)) { dismiss() }
            }
            if let missed = missedPrompt {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                    Text(missed.text).font(.callout)
                    Spacer()
                    Button(L(.dataTaskRunNow)) {
                        Task { await appState.runMissedAgentScheduleNow() }
                    }
                    Button(L(.commonClose)) { appState.dismissAgentScheduleMissed() }
                }
                .padding(8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
    }

    private var missedPrompt: AgentSchedulePresentation.MissedPrompt? {
        guard let entryID = appState.agentScheduleMissedEntryID,
              let decision = appState.agentScheduleDecisions[entryID] else { return nil }
        return AgentSchedulePresentation.missedPrompt(for: decision, entryID: entryID, language: language)
    }

    private var emptyState: some View {
        Text(L(.agentScheduleEmpty))
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - 列表

    private var entryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(appState.agentSchedules) { entry in
                    entryRow(entry)
                }
            }
            .padding(12)
        }
    }

    private func entryRow(_ entry: AgentScheduleEntry) -> some View {
        let decision = appState.agentScheduleDecision(for: entry)
        let row = AgentSchedulePresentation.row(
            for: entry,
            decision: decision,
            lastRun: appState.agentScheduleLastSuccessfulRun(for: entry.id),
            latestRecord: appState.agentScheduleLatestRun(for: entry.id),
            language: language
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(row.title).font(.body).bold()
                Text(row.statusText)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                Spacer()
                Toggle("", isOn: Binding(
                    get: { row.isEnabled },
                    set: { value in Task { await appState.setAgentScheduleEnabled(value, id: entry.id) } }
                ))
                .labelsHidden()
                .help(L(.dataTaskEnabled))
                // 同上：这是**面板里的行内操作**，走系统标准按钮（图标化只保留给主界面工具条）。
                Button(L(.commonEdit)) { editing = entry }
                    .buttonStyle(.borderless)
                Button(L(.commonDelete)) {
                    Task { await appState.deleteAgentSchedule(id: entry.id) }
                }
            }
            Text(row.targetText).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text(row.scheduleText).font(.caption).foregroundStyle(.secondary)
                if let next = row.nextRunText {
                    Text(L(.dataTaskNextRun, next)).font(.caption).foregroundStyle(.secondary)
                }
                if let last = row.lastRunText {
                    Text(last).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L(.agentScheduleNeverRun)).font(.caption).foregroundStyle(.tertiary)
                }
            }
            if let hint = row.disabledHint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 执行历史（⑤：时间 / 结果状态 / 扣下几条）

    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(.agentScheduleHistory)).font(.headline)
            let rows = AgentSchedulePresentation.historyRows(appState.agentScheduleRuns, language: language)
            if rows.isEmpty {
                Text(L(.agentScheduleHistoryEmpty)).font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(rows.suffix(20)) { row in
                            HStack(spacing: 8) {
                                Text(row.startedAtText).font(.caption).monospaced()
                                Text(row.statusText).font(.caption)
                                if row.isLate { Text("+").font(.caption).foregroundStyle(.orange) }
                                if let executed = row.executedText { Text(executed).font(.caption).foregroundStyle(.secondary) }
                                if let withheld = row.withheldText { Text(withheld).font(.caption).foregroundStyle(.orange) }
                                if let detail = row.detailText { Text(detail).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text(row.durationText).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Button(L(.agentScheduleNew)) { editing = newEntry() }
            Spacer()
        }
        .padding(12)
    }

    /// 新建的默认条目：一次性调度、目标 = 会话、工作区 = 当前工作区。
    private func newEntry() -> AgentScheduleEntry {
        AgentScheduleEntry(
            target: AgentScheduleTarget(
                kind: .conversation,
                title: "",
                prompt: "",
                workspace: appState.workspacePathProvider?() ?? ""
            ),
            schedule: TaskSchedule(kind: .once, runAt: Date().addingTimeInterval(3600)),
            isEnabled: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - 编辑（新建 / 修改）

private struct AgentScheduleEditor: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State var entry: AgentScheduleEntry
    let isNew: Bool

    @State private var intervalText: String

    init(entry: AgentScheduleEntry, isNew: Bool) {
        _entry = State(initialValue: entry)
        self.isNew = isNew
        _intervalText = State(initialValue: String(Int(entry.schedule.intervalSeconds ?? 3600)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Picker(L(.agentScheduleTargetLabel), selection: $entry.target.kind) {
                    ForEach(AgentScheduleTarget.Kind.allCases, id: \.self) { kind in
                        Text(AgentSchedulePresentation.targetKindText(kind, language: LocalizationManager.shared.language))
                            .tag(kind)
                    }
                }
                TextField(L(.agentScheduleTitle), text: $entry.target.title)
                TextField(L(.agentSchedulePromptLabel), text: $entry.target.prompt, axis: .vertical)
                    .lineLimit(3...6)
                TextField(L(.agentScheduleWorkspaceLabel), text: $entry.target.workspace)
                Divider()
                Picker(L(.dataTaskScheduleKind), selection: $entry.schedule.kind) {
                    Text(L(.dataTaskScheduleKindOnce)).tag(TaskSchedule.Kind.once)
                    Text(L(.dataTaskScheduleKindRecurring)).tag(TaskSchedule.Kind.recurring)
                    Text(L(.dataTaskScheduleKindManual)).tag(TaskSchedule.Kind.manual)
                }
                if entry.schedule.kind == .once {
                    DatePicker(L(.dataTaskRunAt),
                               selection: Binding(
                                get: { entry.schedule.runAt ?? Date() },
                                set: { entry.schedule.runAt = $0 }
                               ))
                }
                if entry.schedule.kind == .recurring {
                    TextField(L(.dataTaskIntervalSeconds), text: $intervalText)
                }
                Toggle(L(.dataTaskEnabled), isOn: $entry.isEnabled)
            }
            Divider()
            HStack {
                Button(L(.commonCancel)) { dismiss() }
                Spacer()
                Button(L(.commonSave)) {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entry.target.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 480, height: 420, alignment: .topLeading)
    }

    private func save() async {
        if entry.schedule.kind == .recurring {
            entry.schedule.intervalSeconds = TimeInterval(Int(intervalText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 3600)
        } else {
            entry.schedule.intervalSeconds = nil
        }
        if entry.target.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entry.target.title = entry.target.prompt
        }
        await appState.saveAgentSchedule(entry)
        dismiss()
    }
}
