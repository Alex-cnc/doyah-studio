import DoyahCore
import SwiftUI

/// 「慢查询排行」面板（FR-DIAG-03）：`pg_stat_statements` 按总耗时 / 平均耗时 / 调用次数排序。
///
/// 三条与 Core 一致的口径，界面上必须看得见，否则用户会误判：
/// ① **没装扩展不是「一条都没有」** —— 三态分开画：排行 / 没装扩展（给可照做的安装步骤）/
///    连主版本都拿不到（不猜列名）；
/// ② **排序切换真的换一条 SQL** —— 排序与列名适配都在 `Core/SlowQueryReport`，界面不自己拼；
/// ③ **点一行只放进编辑器、不执行** —— 需求原文「可点击某条回填到编辑器」，
///    执行仍然走用户自己那一步。
struct SlowQueryPanel: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var sort: SlowQueryReport.Sort = .totalTime
    @State private var outcome: AppState.SlowQueryOutcome?
    @State private var errorMessage: String?
    @State private var isLoading = false

    private let limit = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 760, height: 560)
        .task { await load() }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(L(.slowQueryTitle)).font(Theme.font(.title))
                if let connection = appState.selectedConnection {
                    Text(connection.endpointDescription)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                }
            }
            Spacer()
            Picker(L(.slowQuerySortLabel), selection: $sort) {
                Text(L(.slowQuerySortTotal)).tag(SlowQueryReport.Sort.totalTime)
                Text(L(.slowQuerySortMean)).tag(SlowQueryReport.Sort.meanTime)
                Text(L(.slowQuerySortCalls)).tag(SlowQueryReport.Sort.calls)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            .onChange(of: sort) { _, _ in Task { await load() } }

            DialogActionButton(systemName: "arrow.clockwise", title: L(.slowQueryRefresh)) {
                Task { await load() }
            }
            .disabled(isLoading)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if isLoading, outcome == nil {
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text(L(.slowQueryLoading))
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.text(.secondary))
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        } else if let errorMessage {
            Text(errorMessage)
                .font(Theme.font(.body))
                .foregroundStyle(Theme.status(.warning))
                .fixedSize(horizontal: false, vertical: true)
                .padding(Spacing.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        } else if let outcome {
            switch outcome {
            case .ranking(let entries) where entries.isEmpty:
                Text(L(.slowQueryEmpty))
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.text(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Spacing.l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            case .ranking(let entries):
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            row(index: index + 1, entry: entry)
                            Divider()
                        }
                    }
                }

            case .missingExtension(let instructions):
                // 「没装扩展」要把怎么安装摊开 —— 只说没装等于把问题丢回给用户。
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(L(.slowQueryMissingTitle)).font(Theme.font(.bodyStrong))
                    Text(instructions)
                        .font(Theme.font(.monoSmall))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            case .unsupported(let reason):
                Text(reason)
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.status(.warning))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Spacing.l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

        } else {
            Text(L(.slowQueryEmpty))
                .font(Theme.font(.body))
                .foregroundStyle(Theme.text(.secondary))
                .padding(Spacing.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func row(index: Int, entry: SlowQueryReport.Entry) -> some View {
        Button {
            appState.putSlowQueryInEditor(entry)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(entry.display())
                    .font(Theme.font(.monoSmall))
                    .foregroundStyle(Theme.text(.primary))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Spacing.m) {
                    Text("#\(index)")
                        .font(Theme.font(.data))
                        .foregroundStyle(Theme.text(.tertiary))
                    Text(L(.slowQueryCalls, entry.calls))
                    Text(L(.slowQueryTotal, SlowQueryReport.formatDuration(millis: entry.totalMillis)))
                    Text(L(.slowQueryMean, SlowQueryReport.formatDuration(millis: entry.meanMillis)))
                }
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L(.slowQueryHint))
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            Text(L(.slowQueryHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
            Spacer()
            DialogActionButton(systemName: "xmark", title: L(.commonClose)) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    // MARK: 取数

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            outcome = try await appState.slowQueryRanking(sort: sort, limit: limit)
        } catch {
            errorMessage = L(.databaseStatsFailure, ErrorPresenter.message(for: error))
        }
        isLoading = false
    }
}
