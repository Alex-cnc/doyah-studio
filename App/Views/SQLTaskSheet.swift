import SwiftUI
import DoyahCore

/// 「保存为任务」表单（`FR-STD-DB-TASK-001`）。
///
/// 为什么与「保存查询」分开一张表单：那里只要一个名字（片段 + 位置），
/// 这里要定四件事 —— 目标库（这里只显示，取当前库）/ 读写模式 / 影响行数上限 / 要不要审批。
/// 把这四样塞进一个单行输入框里，等于让用户以为自己存的还是「一段 SQL」。
struct SQLTaskSaveSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let tab: QueryTab

    @State private var name = ""
    @State private var accessMode: SQLTaskDefinition.AccessMode = .readOnly
    @State private var rowLimitText = ""
    @State private var requiresApproval = true
    /// 保存失败的原因（重名 / 上限不是正整数 / 没选库…）—— **显示在这里**，
    /// 不悄悄写进别处的状态行：用户正在这张表单上填东西，答案就该在表单上。
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.sqlTaskSheetTitle))
                .font(.headline)

            TextField(L(.sqlTaskNameField), text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)

            HStack(spacing: 8) {
                Text(L(.sqlTaskTargetDatabase))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(currentDatabase)
                    .font(.system(.caption, design: .monospaced))
            }
            Text(L(.sqlTaskTargetDatabaseHint))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(L(.sqlTaskAccessMode), selection: $accessMode) {
                Text(L(.sqlTaskModeReadOnly)).tag(SQLTaskDefinition.AccessMode.readOnly)
                Text(L(.sqlTaskModeWritable)).tag(SQLTaskDefinition.AccessMode.writable)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            HStack(spacing: 8) {
                TextField(L(.sqlTaskRowLimitField), text: $rowLimitText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Text(L(.sqlTaskRowLimitHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(L(.sqlTaskRequiresApproval), isOn: $requiresApproval)

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()

                DialogActionButton(systemName: "xmark.circle", title: L(.commonCancel)) {
                    dismiss()
                }

                DialogActionButton(systemName: "square.and.arrow.down", title: L(.commonSave)) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 470)
        .onAppear {
            if name.isEmpty {
                name = appState.suggestedQueryName(for: tab)
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 目标库取**当前库**（`tab.database ?? selectedDatabase`）—— 与执行时用的是同一个值，
    /// 否则「存的时候看着是 A 库、执行时按 B 库判定」这种错位会让人根本查不出原因。
    private var currentDatabase: String {
        let value = tab.database ?? appState.selectedDatabase ?? ""
        return value.isEmpty ? "—" : value
    }

    private func save() {
        Task {
            let message = await appState.saveCurrentTabAsSQLTask(
                tabID: tab.id,
                name: trimmedName,
                accessMode: accessMode,
                rowLimitText: rowLimitText,
                requiresApproval: requiresApproval
            )
            if let message {
                failure = message
            } else {
                dismiss()
            }
        }
    }
}
