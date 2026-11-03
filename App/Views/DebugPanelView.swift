import SwiftUI
import DoyahCore

/// 调试面板（`FR-STD-WS-TOOL-003` 的界面）：断点清单 + 程序路径 + 单步工具栏 + 变量 + 输出。
///
/// 需求写着「经 DAP 接入既有调试器，不自研调试协议」——所以这一屏**只有**搬运：
/// 按钮打的是 `DAPSession.Step` 那四个真请求，断点清单发的是 `DebugBreakpointSet.dapMap()`
/// 那份 `[path: [行号]]`。停在哪一行、变量是什么，都来自适配器的读数；读不到就如实空着。
struct DebugPanelView: View {

    @ObservedObject var model: DebugSessionModel
    /// 当前编辑器里的光标行（1 起）；没有可编辑文件时为 `nil`。
    var caretLine: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            programRow
            Divider()
            HStack(alignment: .top, spacing: 0) {
                breakpointList.frame(width: 300, alignment: .topLeading)
                Divider()
                variableList
            }
            Divider()
            logView
            Divider()
            footer
        }
        .frame(width: 720, height: 560, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: Spacing.s) {
            Text(L(.debugTitle)).font(Theme.font(.title))
            Text(stateLine)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(TextTone.secondary))
            Spacer()
            // 顶部**不放关闭键**：关掉这个面板的入口只有 `footer` 那枚
            // （2026-11-03 人类主人真机点验：同一件事在屏幕上出现两次）。
        }
        .padding(Spacing.m)
    }

    private var programRow: some View {
        HStack(spacing: Spacing.s) {
            Text(L(.debugProgramLabel)).font(Theme.font(.body))
            TextField(L(.debugProgramLabel), text: $model.program)
                .textFieldStyle(.roundedBorder)
            Button(L(.debugStart)) { model.start() }
                .disabled(model.isBusy || model.program.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(L(.debugStop)) { model.stop() }
                .disabled(model.isBusy == false && model.phase == .idle)
        }
        .padding(Spacing.m)
    }

    private var breakpointList: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L(.debugBreakpoints)).font(Theme.font(.title))
            if model.breakpoints.isEmpty {
                Text(L(.debugEmptyBreakpoints, 1))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(TextTone.secondary))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(model.breakpoints.listing, id: \.path) { entry in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(entry.path).font(Theme.font(.monoSmall))
                                ForEach(entry.lines, id: \.self) { line in
                                    HStack(spacing: Spacing.s) {
                                        Text("\(line)").font(Theme.font(.monoSmall))
                                        Text("●").foregroundStyle(Theme.status(.danger))
                                        Spacer()
                                        Button(L(.commonDelete)) {
                                            model.toggleBreakpoint(line: line, in: entry.path)
                                        }
                                        .buttonStyle(.link)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(Spacing.m)
    }

    private var variableList: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L(.debugVariables)).font(Theme.font(.title))
            if model.variables.isEmpty {
                Text(L(.debugNoVariables))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(TextTone.secondary))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(model.variables, id: \.name) { item in
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                                Text(item.name).font(Theme.font(.monoSmall))
                                Text("=").foregroundStyle(Theme.text(TextTone.secondary))
                                Text(item.value).font(Theme.font(.monoSmall))
                            }
                        }
                    }
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(L(.debugLog)).font(Theme.font(.title))
                Spacer()
                // 单步工具栏：四条都打真 DAP 请求（next / stepIn / stepOut / continue）。
                Button(L(.debugContinue)) { model.step(.resume) }
                    .disabled(model.isBusy)
                Button(L(.debugStepOver)) { model.step(.over) }
                    .disabled(model.isBusy)
                Button(L(.debugStepInto)) { model.step(.into) }
                    .disabled(model.isBusy)
                Button(L(.debugStepOut)) { model.step(.out) }
                    .disabled(model.isBusy)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(Theme.font(.monoSmall))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 120)
        }
        .padding(Spacing.m)
    }

    private var footer: some View {
        HStack {
            Text(L(.debugIdleHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(TextTone.secondary))
            Spacer()
            DialogActionRow(
                actions: [DialogActionSpec(id: "close", title: L(.commonClose), role: .cancel)],
                dismissible: true,
                pushesTrailing: false
            ) { _ in dismiss() }
        }
        .padding(Spacing.m)
    }

    /// 「正在启动调试：」那一行里的程序路径（单独取出来，别把成员表达式塞进格式实参）。
    private var runningProgram: String { model.program }

    private var stateLine: String {
        switch model.phase {
        case .idle: return ""
        case .running: return L(.debugStarting, runningProgram)
        case .stopped(let file, let line): return L(.debugStoppedAt, file, line)
        case .finished(let reason): return L(.debugFinished, reason)
        case .failed(let reason): return reason
        }
    }
}
