import SwiftUI
import AppKit
import DoyahCore

/// 工作区**页签条**（`FR-EDIT-35` / `FR-EDIT-36` / `FR-EDIT-34` / `L-149`）。
///
/// 这一行是**应用内 chrome**：左边是页签（浏览器页签与文件页签是同一类），右边是当前
/// 语言的显示、编辑菜单、保存与「打开文件」。
///
/// ## 为什么把它从 `WorkspaceAreaView` 里抽出来（队列 `L-144` · 内测清单乙5）
///
/// 需求提出者 2026-09-30 内测原话：「**新建 2 浏览器页签后，选择空白浏览器页签，整个标题栏
/// 撑得很高，整个布局全乱了**」。第二轮实测**未复现**（浏览器页签被 `L-149` 从数据库侧搬到
/// 工作区后复现路径已变），本条按「**用户判过 + 判据留网**」收口 —— 而「留网」要求这一行的
/// 高度**能被机器量出来**：页面级视图（`WorkspaceAreaView`）里混着内容区与消息条，量出来的
/// 数说不出是哪一段的高度。抽成独立视图之后，「**这一行有多高**」第一次是可断言的
/// （`TestsUISnapshot/WorkspaceChromeHeightProbeTests.swift`）。
///
/// ## 不变量（写在这里 = 唯一出处）
///
/// 这一行的高度**只由内边距与字高决定**，**不许由页签的内容决定** —— 空白页签（标题为默认
/// 值）与有地址的页签同高、页签数量不影响高度、窗口宽度不影响高度。往这一行里塞一个
/// **理想高度随宽度变化的东西**（会换行的长文案、空态视图、`WKWebView` 之类）就是
/// 「标题栏被撑高」这一类病的成因；探针里有对照负例钉住这一点。
struct WorkspaceTabStrip: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tabs: WorkspaceTabsModel

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    // 内置浏览器页签（队列 `L-149`）：与 Home / 文件是**同一类页签**。
                    // 需求提出者 2026-09-30：「浏览器内置到工作区 Tab 页……本质上 html 也是一种文件」；
                    // 原先它长在数据库侧 —— 那是 **SQL 这门语言的工作台**，不归它管。
                    ForEach(appState.browserPages) { page in
                        browserTabButton(page)
                    }
                    ForEach(tabs.tabs) { tab in
                        tabButton(tab)
                    }
                }
                .padding(.vertical, Spacing.hair)
            }

            Spacer(minLength: Spacing.s)

            if let tab = tabs.selectedTab, !tab.isHome {
                Text(L(.workspaceLanguageLabel, tab.language.displayName))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .lineLimit(1)

                editMenu

                Button {
                    tabs.save(tab.id)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(Theme.font(.caption))
                }
                .buttonStyle(.borderless)
                .disabled(!tab.isDirty)
                .help(L(.workspaceSaveButton))
            }

            Button {
                openFileFromPanel()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(Theme.font(.caption))
            }
            .buttonStyle(.borderless)
            .help(L(.workspaceOpenFileButton))
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: 编辑菜单（工作区自己的那一份）

    /// 「编辑」菜单 —— **代码格式化**（FR-EDIT-39）的菜单入口。
    ///
    /// 为什么在工作区页签条上再画一份、而不是塞进主菜单栏的「编辑」：主菜单栏那份是
    /// SQL 编辑器在用的（`QueryToolbar`），而这两个编辑器分属两个活动区、各有一套编辑动作
    /// （SQL 那套有诊断与执行，这套只有格式化）。画在同一处会互相打架。
    private var editMenu: some View {
        Menu {
            Button(L(.workspaceFormatMenuItem, AppShortcut.formatCode.display)) {
                tabs.formatSelected()
            }
            .keyboardShortcut(AppShortcut.formatCode.key, modifiers: AppShortcut.formatCode.modifiers)
        } label: {
            Image(systemName: "text.alignleft")
                .font(Theme.font(.caption))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L(.workspaceFormatMenuItem, AppShortcut.formatCode.display))
    }

    private func tabButton(_ tab: WorkspaceTab) -> some View {
        let isSelected = tab.id == tabs.selectedTab?.id
        return HStack(spacing: Spacing.xs) {
            Image(systemName: tab.isHome ? "house" : "doc.text")
                .font(Theme.font(.caption))
                .foregroundStyle(isSelected ? Theme.accentColor : Theme.text(.secondary))

            Text(tab.title)
                .font(Theme.font(.caption))
                .lineLimit(1)
                .fontWeight(isSelected ? .semibold : .regular)

            if tab.isDirty {
                Circle()
                    .fill(Theme.status(.warning))
                    .frame(width: 6, height: 6)
                    .help(L(.workspaceDirtyTag))
            }

            // Home 关不掉（工作区的落脚点），所以它没有关闭按钮。
            if !tab.isHome {
                Button {
                    tabs.close(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(Theme.font(.caption))
                }
                .buttonStyle(.borderless)
                .help(L(.workspaceCloseTab))
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.hair)
        .background(
            RoundedRectangle(cornerRadius: Radius.badge)
                .fill(isSelected ? Theme.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        // 选工作区页签 = 离开浏览器（否则浏览器那份选中态会一直压在上面，回不到 Home）。
        .onTapGesture {
            appState.selectedBrowserID = nil
            tabs.select(tab.id)
        }
        .help(tab.path ?? tab.title)
    }

    /// 浏览器页签（队列 `L-149`）：与 Home / 文件同一类页签，只是图标与动作走浏览器那条。
    private func browserTabButton(_ page: BrowserPage) -> some View {
        let isSelected = appState.selectedBrowserID == page.id
        return HStack(spacing: Spacing.xs) {
            if page.isLoading {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "globe")
                    .font(Theme.font(.caption))
                    .foregroundStyle(isSelected ? Theme.accentColor : Theme.text(.secondary))
            }

            Text(page.title)
                .font(Theme.font(.caption))
                .lineLimit(1)
                .fontWeight(isSelected ? .semibold : .regular)

            Button {
                appState.closeBrowserTab(page.id)
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.font(.caption))
            }
            .buttonStyle(.borderless)
            .help(L(.workspaceCloseTab))
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.hair)
        .background(
            RoundedRectangle(cornerRadius: Radius.badge)
                .fill(isSelected ? Theme.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { appState.selectBrowserTab(page.id) }
        .help(page.title)
    }

    // MARK: 动作

    private func openFileFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = L(.workspaceOpenFileButton)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        tabs.openFile(at: url)
    }
}
