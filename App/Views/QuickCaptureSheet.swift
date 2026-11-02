import SwiftUI
import DoyahCore

/// **快速捕获面**（`FR-NTS-NOTE-CAPTURE-001` 判据①的界面落点）。
///
/// 口径只有三条，都写在界面上：
/// 1. **一个动作就能输入** —— 进来时正文框已经拿到焦点（`onAppear` 里抢一次），
///    没有「选笔记本」「选标签」「选模板」这几步：捕获是记下来，不是归档；
/// 2. **不填标题也能存** —— 界面上没有标题框，标题由首行推出（`QuickCapture.title`），
///    所以「标题空着能不能存」这个问题在这里不存在；
/// 3. **存 = 只写本地** —— 按键只调 `appState.commitQuickCapture()`（本地库），
///    网络那一半归同步队列；断网时这条路径与联网时一模一样。
struct QuickCaptureSheet: View {

    @EnvironmentObject private var appState: AppState
    @FocusState private var isBodyFocused: Bool
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L(.notesQuickCaptureTitle))
                .font(.headline)

            ZStack(alignment: .topLeading) {
                if appState.quickCapture.body.isEmpty {
                    Text(L(.notesQuickCapturePlaceholder))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $appState.quickCapture.body)
                    .font(.body)
                    .focused($isBodyFocused)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))

            if appState.quickCapture.body.isEmpty {
                Text(L(.notesQuickCaptureUntitled) + " · " + QuickCaptureShortcut.standard.display)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 快捷键被别的应用占住时**照实说**（并给出去处）：捕获不能因为热键失败就变成「记不了」。
            if case .failed = appState.quickCaptureHotKeyOutcome {
                Text(L(.notesQuickCaptureHotKeyTaken))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button {
                    appState.cancelQuickCapture()
                } label: {
                    Label(L(.commonCancel), systemImage: "xmark")
                }
                Button {
                    isSaving = true
                    Task {
                        await appState.commitQuickCapture()
                        isSaving = false
                    }
                } label: {
                    Label(L(.notesQuickCaptureSave), systemImage: "checkmark")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSaving)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            isBodyFocused = true
            appState.quickCapture.focusDidLand()
        }
    }
}
