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
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L(.notesQuickCaptureTitle))
                .font(Theme.font(.title))

            ZStack(alignment: .topLeading) {
                if appState.quickCapture.body.isEmpty {
                    Text(L(.notesQuickCapturePlaceholder))
                        .foregroundStyle(Theme.text(.secondary))
                        .padding(.top, 8)
                        .padding(.leading, Spacing.xs)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $appState.quickCapture.body)
                    .font(Theme.font(.body))
                    .focused($isBodyFocused)
                    .frame(minHeight: 150)
                    // 编辑面底色 / 字色的唯一出处（`L-142` 甲2）：这里既不许自己写
                    // `scrollContentBackground` ，也不许自己填色 —— 上面那层占位文字跟着
                    // 同一块底色走，所以容器底也取同一个令牌。
                    .editorSurface()
            }
            .padding(Spacing.s)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface(.content)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.surface(.panel)))

            if appState.quickCapture.body.isEmpty {
                Text(L(.notesQuickCaptureUntitled) + " · " + QuickCaptureShortcut.standard.display)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            }

            // 快捷键被别的应用占住时**照实说**（并给出去处）：捕获不能因为热键失败就变成「记不了」。
            if case .failed = appState.quickCaptureHotKeyOutcome {
                Text(L(.notesQuickCaptureHotKeyTaken))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
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
        .padding(Spacing.l)
        .frame(width: 520)
        .onAppear {
            isBodyFocused = true
            appState.quickCapture.focusDidLand()
        }
    }
}
