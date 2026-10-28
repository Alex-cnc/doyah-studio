import SwiftUI
import WebKit

import DoyahCore
import DoyahPlatform

/// 网页文件在**编辑器内**的只读预览（`FR-STD-WS-WEB-003`）。
///
/// 与 Markdown 预览是**同一套交互**（只读 · 可切换 / 可分屏 · 源码与预览互不覆盖），
/// 区别只在渲染器：这里用与浏览器页签**同一个引擎**（`WebKitBrowserEngine`），
/// 于是策略、外发留痕、本机文件读权限三条口径不必再写第二份。
///
/// 这一层只做三件事：问 Core 要计划（`HTMLPreview.plan`）→ 把计划交给引擎 →
/// 把「打不开的原因」照实画出来。**它自己不许判断能不能加载**。
struct HTMLPreviewView: View {
    /// 页签标识 —— 引擎按它缓存（切页签 / 重绘都不重新加载）。
    let tabID: UUID
    /// 这个页签对应的磁盘路径（`nil` = 还没落盘）。
    let path: String?
    /// 编辑器里是否有未保存改动（有则渲染缓冲，看到的就是正在编辑的那份）。
    let isDirty: Bool
    /// 当前编辑缓冲。
    let content: String
    /// 需要地址栏 / 后退 / 本地服务时，把这一个文件交给**浏览器页签**（`FR-STD-WS-WEB-003` ⑦）。
    let onOpenInBrowser: (URL) -> Void

    @StateObject private var model = HTMLPreviewModel()
    /// 手动刷新：改动落盘之后不自动跟（不跟每一次击键重排），给一枚按钮按需重渲。
    @State private var refreshToken = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineView()
            if let reason = model.blockReason {
                reasonBar(reason)
            } else if let engine = model.engine {
                HTMLPreviewEngineView(engine: engine)
            } else {
                // 计划还没算出来（第一次出现的一瞬）：画空白而不是闪一下「打不开」。
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surface(.content))
        .onAppear { render() }
        .onChange(of: refreshToken) { _, _ in render() }
        // 换文件 / 脏状态翻转 ⇒ 重新计划；**内容逐字符变化不重渲**（那会在打字时反复重排）。
        .onChange(of: path) { _, _ in render() }
        .onChange(of: isDirty) { _, _ in render() }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "globe")
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
            Text(L(.workspaceHTMLPreviewToggle))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .lineLimit(1)
            if isDirty {
                // 说明白「你看到的是没保存的那份」—— 否则用户会以为预览没跟上。
                Text(L(.workspaceDirtyTag))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.s)
            Button {
                refreshToken &+= 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(Theme.font(.caption))
            }
            .buttonStyle(.borderless)
            .help(L(.workspaceHTMLPreviewRefresh))
            Button {
                if let url = path.map({ URL(fileURLWithPath: $0) }) {
                    onOpenInBrowser(url)
                }
            } label: {
                Image(systemName: "macwindow.on.rectangle")
                    .font(Theme.font(.caption))
            }
            .buttonStyle(.borderless)
            .disabled(path == nil)
            .help(L(.workspaceHTMLPreviewOpenInBrowser))
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.hair)
    }

    /// 打不开的原因（文件不在了 / 是目录 / 磁盘根下不给读权限 …）。
    ///
    /// 与 Markdown 预览那条「如实报数」同一条纪律：宁可说一句为什么，也不给一张空白页。
    private func reasonBar(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
                Text(reason)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: 渲染

    private func render() {
        let facts = HTMLPreview.FileFacts(
            exists: path.map { FileManager.default.fileExists(atPath: $0) } ?? false,
            isDirectory: path.map { isDirectory($0) } ?? false
        )
        let outcome = HTMLPreview.plan(
            path: path,
            isDirty: isDirty,
            buffer: content,
            facts: facts,
            language: LocalizationManager.shared.effectiveLanguage
        )
        switch outcome {
        case .block(let reason):
            model.show(reason: reason)
        case .render(let plan):
            model.render(plan, tabID: tabID)
        }
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }
}

/// 预览的引擎缓存与计划落地（状态住在模型里：视图重建不该把已渲染的页面丢掉）。
@MainActor
final class HTMLPreviewModel: ObservableObject {
    /// 打不开的原因（`nil` = 有页面可看）。
    @Published private(set) var blockReason: String?
    /// 当前这枚页签的引擎（第一次渲染时建）。
    @Published private(set) var engine: WebKitBrowserEngine?

    private var engines: [UUID: WebKitBrowserEngine] = [:]
    private var renderedSignature: [UUID: String] = [:]

    func show(reason: String) {
        blockReason = reason
    }

    func render(_ plan: HTMLPreview.Plan, tabID: UUID) {
        blockReason = nil
        let engine = engines[tabID] ?? makeEngine(tabID: tabID)
        self.engine = engine
        // 读权限根每次重算（文件可能被移动过）—— 引擎里那一档是导航裁决用的。
        engine.localReadRoot = plan.readAccessRoot

        let signature = Self.signature(plan)
        guard renderedSignature[tabID] != signature else { return }
        renderedSignature[tabID] = signature

        switch plan.source {
        case .file(let url):
            Task { await engine.load(url) }
        case .buffer(let text, let baseDirectory):
            // 未保存的缓冲：内容已在内存里，没有出网（不写外发日志）；读权限仍只到那个目录。
            engine.loadHTMLString(text, baseDirectory: baseDirectory)
        }
    }

    private func makeEngine(tabID: UUID) -> WebKitBrowserEngine {
        let engine = WebKitBrowserEngine(
            pageID: tabID,
            origin: "编辑器 · 网页预览",
            log: .shared
        )
        engine.languageProvider = { LocalizationManager.shared.effectiveLanguage }
        // 预览里点下载 = 出网 + 写盘：与浏览器页签同一条口径（落授权目录，没授权就如实拒绝）。
        engine.downloadDirectory = { nil }
        engines[tabID] = engine
        return engine
    }

    /// 「渲染的是什么」的指纹：路径 + 盘上 / 缓冲 + 缓冲内容。
    ///
    /// 缓冲那一档带上内容：脏着的时候**保存**会让 `isDirty` 翻成假、签名随之变化 ⇒ 自动重渲一次；
    /// 而打字过程中签名只在「缓冲区内容」这一维上变，重渲由视图决定要不要触发（本视图不打字触发）。
    private static func signature(_ plan: HTMLPreview.Plan) -> String {
        switch plan.source {
        case .file(let url): return "file:" + url.path
        case .buffer(let text, let directory): return "buffer:\(directory.path):\(text.count):\(text.hashValue)"
        }
    }
}

/// `WKWebView` 的 SwiftUI 承载（与浏览器页签那一枚同一形状：引擎按页签缓存，重建视图不重载）。
private struct HTMLPreviewEngineView: NSViewRepresentable {
    let engine: WebKitBrowserEngine

    func makeNSView(context: Context) -> WKWebView {
        engine.view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
