import SwiftUI
import DoyahCore

/// 「对话记忆…」面板（`FR-AGT-KNOW-MEM-003` 的界面面）。
///
/// 一屏回答四件事，对应需求那六个验收要点里**靠界面才成立**的那几条：
/// 1. **都记了些什么**（① 可检视）：逐条列出，正文 + 类别 + 连接 + 用到几次；
/// 2. **为什么记着它**（① 可解释）：每条给 `MemoryExplanation.describe` 的那一行 ——
///    与 `FR-AI-15` **同一套口径**，本面板不复算、不改写；也顺带说出「按生命周期该忘了」；
/// 3. **能不能删**（② 可删除）：单条删除 / 整层清空（先问一次），删完立刻重读 ——
///    屏幕上的那一行消失，是**事实源真的被重写**的结果，不是本地把数组摘了一条；
/// 4. **索引是什么状态**（⑤ 纯派生缓存）：在盘几条 / 不在盘 / 与事实源不一致，并给一个
///    「重建索引」的入口 —— 这条判据要能被**点**出来，不只写在注释里。
///
/// 读不进来的东西（坏文件 / 认不出的条目 / 别的工作区 / 头找不着）**一律显式说出来**（⑥）：
/// 「看不到」与「没有」在这个面板上是两句话。
struct AgentMemoryPanel: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var isClearConfirmPresented = false

    private var snapshot: AgentMemorySnapshot? { appState.agentMemorySnapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            header
            Text(L(.agentMemoryHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            scopeRow
            if let notice = appState.agentMemoryNotice {
                noticeLines(notice)
            }
            HairlineView()
            content
            footer
        }
        .padding(Spacing.l)
        .frame(minWidth: 760, minHeight: 560)
        .task {
            appState.refreshAgentMemory()
        }
        .alert(L(.agentMemoryClearConfirmTitle), isPresented: $isClearConfirmPresented) {
            DialogActionButton(systemName: "xmark.circle", title: L(.commonCancel), role: .cancel) {}
            DialogActionButton(systemName: "trash", title: L(.agentMemoryClearAll), role: .destructive) {
                appState.clearAgentMemory()
            }
        } message: {
            Text(L(.agentMemoryClearConfirmMessage))
        }
    }

    // MARK: - 头与范围

    private var header: some View {
        HStack(spacing: Spacing.s) {
            Text(L(.agentMemoryTitle))
                .font(Theme.font(.title))
            Spacer()
            Button(L(.commonClose)) { dismiss() }
        }
    }

    private var scopeRow: some View {
        HStack(spacing: Spacing.m) {
            if let workspace = snapshot?.workspace {
                Label(workspace, systemImage: "folder")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let snapshot {
                Text(snapshot.connection ?? L(.agentMemoryAllConnections))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
            }
            Spacer()
            indexLine
        }
    }

    /// 索引状态那一行（⑤：派生缓存要能被看见、被重建）。
    @ViewBuilder
    private var indexLine: some View {
        if let snapshot {
            if snapshot.indexIsStale {
                Label(L(.agentMemoryIndexStale, Int64(snapshot.indexEntryCount ?? 0), Int64(snapshot.entryCount)),
                      systemImage: "exclamationmark.triangle")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
            } else if let count = snapshot.indexEntryCount {
                Label(L(.agentMemoryIndexOn, Int64(count)), systemImage: "internaldrive")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
            } else {
                Label(L(.agentMemoryIndexOff), systemImage: "internaldrive")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
            }
        }
    }

    // MARK: - 结论行

    @ViewBuilder
    private func noticeLines(_ notice: AgentMemoryNotice) -> some View {
        VStack(alignment: .leading, spacing: Spacing.hair) {
            switch notice {
            case .remembered(let merged, let useCount, let truncated, let evicted):
                Text(merged ? L(.agentMemoryNoticeMerged, Int64(useCount)) : L(.agentMemoryNoticeRemembered))
                if truncated > 0 { Text(L(.agentMemoryNoticeTruncated, Int64(truncated))) }
                if evicted > 0 { Text(L(.agentMemoryNoticeEvicted, Int64(evicted))) }
            case .refused(let rejections, let truncated):
                ForEach(Array(rejections.enumerated()), id: \.offset) { _, rejection in
                    switch rejection {
                    case .rowLikeContent(let count):
                        Text(L(.agentMemoryNoticeRefusedRows, Int64(count)))
                    case .secretFragment(let count):
                        Text(L(.agentMemoryNoticeRefusedSecrets, Int64(count)))
                    case .emptyNote:
                        Text(L(.agentMemoryNoticeFailed))
                    case .workspaceMismatch:
                        Text(L(.agentMemoryWorkspaceMismatch))
                    case .sourceUnreadable:
                        Text(L(.agentMemoryMissingHeader))
                    case .needsUserConfirmation:
                        Text(L(.agentMemoryNoticeNeedsConfirmation))
                    }
                }
                if truncated > 0 { Text(L(.agentMemoryNoticeTruncated, Int64(truncated))) }
            case .needsConfirmation:
                Text(L(.agentMemoryNoticeNeedsConfirmation))
            case .deleted(let indexRebuilt):
                Text(indexRebuilt ? L(.agentMemoryNoticeDeleted) : L(.agentMemoryNoticeDeletedIndexStale))
            case .notFound:
                Text(L(.agentMemoryNoticeNotFound))
            case .cleared(let count, let indexRebuilt):
                Text(L(.agentMemoryNoticeCleared, Int64(count)))
                if !indexRebuilt { Text(L(.agentMemoryNoticeDeletedIndexStale)) }
            case .indexRebuilt(let count):
                Text(L(.agentMemoryNoticeIndexRebuilt, Int64(count)))
            case .failed:
                Text(L(.agentMemoryNoticeFailed))
            }
        }
        .font(Theme.font(.caption))
        .foregroundStyle(Theme.text(.secondary))
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 列表 / 空态 / 读不进来

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            if snapshot.workspaceMismatch {
                warning(L(.agentMemoryWorkspaceMismatch))
            } else if snapshot.missingHeader {
                warning(L(.agentMemoryMissingHeader))
            }
            if snapshot.hasSkippedReadings {
                Text(L(.agentMemorySkipped,
                       Int64(snapshot.skippedLines),
                       Int64(snapshot.unknownEntries),
                       Int64(snapshot.foreignEntries),
                       Int64(snapshot.skippedFiles)))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if snapshot.entries.isEmpty {
                Text(L(.agentMemoryEmpty))
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.text(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        ForEach(snapshot.entries) { entry in
                            row(entry, snapshot: snapshot)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            Text(L(.agentMemoryNoWorkspace))
                .font(Theme.font(.body))
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(Theme.font(.caption))
            .foregroundStyle(Theme.status(.warning))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ entry: AgentMemoryEntry, snapshot: AgentMemorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Text(kindLabel(entry.memoryKind))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                Text(entry.connection.isEmpty ? L(.agentMemoryAllConnections) : entry.connection)
                    .font(Theme.font(.mono))
                    .foregroundStyle(Theme.text(.tertiary))
                Text(L(.agentMemoryUseCount, Int64(entry.useCount)))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                if snapshot.retainedIDs.contains(entry.id) {
                    Text(L(.agentMemoryKept))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.status(.success))
                } else {
                    Text(L(.agentMemoryForgotten))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.status(.warning))
                }
                Spacer()
                Button(L(.commonDelete)) {
                    appState.deleteAgentMemory(id: entry.id)
                }
                .controlSize(.small)
            }
            Text(entry.note)
                .font(Theme.font(.body))
                .foregroundStyle(Theme.text(.primary))
                .fixedSize(horizontal: false, vertical: true)
            if let line = snapshot.reasonLines[entry.id]?.last {
                Text(L(.agentMemoryReasonLabel) + " · " + line)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface(Surface.panel))
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
    }

    private func kindLabel(_ kind: MemoryKind?) -> String {
        switch kind {
        case .routine: return L(.agentMemoryKindRoutine)
        case .troubleshooting: return L(.agentMemoryKindTroubleshooting)
        case .pinned: return L(.agentMemoryKindPinned)
        case .general: return L(.agentMemoryKindGeneral)
        case .none: return L(.agentMemoryKindGeneral)
        }
    }

    // MARK: - 尾

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            Button(L(.agentMemoryRebuildIndex)) {
                appState.rebuildAgentMemoryIndex()
            }
            Button(L(.agentMemoryClearAll), role: .destructive) {
                isClearConfirmPresented = true
            }
            .disabled((snapshot?.entries.isEmpty ?? true) && !(snapshot?.indexExists ?? false))
            Spacer()
            Button(L(.commonClose)) { dismiss() }
        }
    }
}
