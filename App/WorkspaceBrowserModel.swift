import Foundation
import Combine

import DoyahCore
import DoyahPlatform

/// 浏览器页签需要宿主（`AppState`）帮它做的三件事。
///
/// **为什么是协议而不是闭包**：这三件都是产品行为（下载必须落到用户**显式授权**过的目录、
/// 下载也算出网必须留痕、启动链上的失败要如实说出来），写在协议上，宿主的实现在复核对账时一眼可见；
/// 反过来，本模型不许自己去读目录书签、也不许自己抄一份外发日志。
@MainActor
protocol WorkspaceBrowserHost: AnyObject {

    /// 下载要落盘的目录（用户显式授权过的那一个）。`nil` ⇒ 引擎拒绝这次下载并说明原因。
    func browserDownloadDirectory() -> URL?

    /// 统一外发日志（`NFR-SEC-08`）：下载也是出网，成功 / 失败 / 被拒都要留一条账。
    ///
    /// **终态（完成 / 失败）** 顺带归还目录访问权 —— 写盘是异步的，持有期必须覆盖它。
    func recordBrowserDownloadEgress(
        outcome: EgressOutcome,
        target: String,
        detail: String,
        tabID: UUID,
        tabTitle: String?
    )

    /// 启动链上的失败（页签库损坏之类）如实说出来，但不打断启动。
    func reportBrowserStatusMessage(_ message: String)
}

/// 工作区的**浏览器页签**（`FR-EDIT-34` / 队列 `L-149` 剩余①「结构债」）。
///
/// ## 为什么要有它
///
/// 需求提出者 2026-09-30 原话：「浏览器内置到工作区 Tab 页，而不是放到数据库 SQL 查询界面，
/// **本质上 html 也是一种文件**」。第 131 轮搬了**展示层**、第 134 轮订正了**条文与判据**，
/// 但状态本身仍挂在 `AppState` 的 `@Published` 上 —— 于是**每一次浏览器状态变化**
/// （引擎回报标题 / 加载中 / 地址）都会让观测 `appState` 的**整个窗口**重算，
/// 而浏览器只是工作区的一类页签，与连接 / 执行 / 元数据 / 事务毫无关系。
///
/// 同一族的病在数据库侧已经用 `QueryEditorBuffer` 治过一次（每键写全局实测 31.74 ms），
/// 工作区页签从第一天起就是独立模型（`WorkspaceTabsModel`）。本条把浏览器页签归到同一条口径上。
///
/// ## 口径（不许改）
///
/// · 状态（页签集 / 选中 / 引擎缓存 / 「这个页签加载过没有」）的**唯一所有者 = 本模型**。
///   `AppState` 只持一个**非 `@Published`** 的引用用于接线（启动链恢复 + 下载留痕 + 授权目录），
///   **不重发**它的变化 —— 观测面因此缩到工作区那一小块。
/// · 下载落盘目录与外发留痕仍归宿主：那两件事的权威数据（目录书签、外发日志面板）在 `AppState`。
/// · 视图只读本模型；**数据库侧不许再出现浏览器状态**（门禁 `check-browser-tab-ownership.py`）。
@MainActor
final class WorkspaceBrowserModel: ObservableObject {

    /// 打开着的浏览器页签（状态模型在 Core，视图只读它）。
    @Published var browserPages: [BrowserPage] = []
    /// 当前选中的浏览器页签；非 `nil` 时工作区内容区显示浏览器。
    @Published var selectedBrowserID: UUID?
    /// 引擎是否已经为某个页签发过请求 —— 用来区分「恢复出来还没加载」与「已在浏览」。
    @Published var browserEngineLoadedPageIDs: Set<UUID> = []

    /// 宿主（`AppState`）。**弱引用** —— 浏览器模型不许把窗口状态钉住。
    weak var host: (any WorkspaceBrowserHost)?

    /// 引擎（`WKWebView`）按页签缓存：视图重建时不重新加载页面。
    private var browserEngines: [UUID: WebKitBrowserEngine] = [:]
    /// 浏览器页签的会话持久化（恢复**不自动请求**，见 `BrowserTabStore` 的说明）。
    private let browserTabStore: BrowserTabStore

    init(browserTabStore: BrowserTabStore = .shared) {
        self.browserTabStore = browserTabStore
    }

    // MARK: 选中与页签

    var selectedBrowserPage: BrowserPage? {
        browserPages.first { $0.id == selectedBrowserID }
    }

    /// 新建浏览器页签。**默认打开空白页** —— 不加载任何远程内容（契约）。
    @discardableResult
    func openBrowserTab() -> UUID {
        let page = BrowserPage()
        browserPages.append(page)
        selectedBrowserID = page.id
        persistBrowserTabs()
        return page.id
    }

    func selectBrowserTab(_ id: UUID) {
        guard browserPages.contains(where: { $0.id == id }) else { return }
        selectedBrowserID = id
    }

    /// 取消浏览器的选中态（选工作区里的 Home / 文件页签时）。
    func clearSelection() {
        selectedBrowserID = nil
    }

    func closeBrowserTab(_ id: UUID) {
        browserPages.removeAll { $0.id == id }
        browserEngines[id] = nil
        browserEngineLoadedPageIDs.remove(id)
        persistBrowserTabs()
        if selectedBrowserID == id {
            selectedBrowserID = browserPages.last?.id
        }
    }

    /// 这个页签是否已经加载过（false = 从会话里恢复出来、还没发过请求）。
    func isBrowserPagePristine(_ id: UUID) -> Bool {
        !browserEngineLoadedPageIDs.contains(id)
    }

    // MARK: 引擎

    /// 取（或建）该页签的引擎。视图每次重绘都会调用它，所以必须是幂等的。
    func browserEngine(for page: BrowserPage) -> WebKitBrowserEngine {
        if let existing = browserEngines[page.id] {
            return existing
        }
        let engine = WebKitBrowserEngine(pageID: page.id, origin: "浏览器 · 页签")
        // 引擎回报的状态（加载中 / 标题 / 地址 / 失败原因）写回模型 —— 否则切页签或重绘后
        // 界面就停在旧状态；`setUpdateHandler` 在主线程回调，直接转发即可。
        engine.setUpdateHandler { [weak self] updated in
            self?.applyBrowserUpdate(updated)
            if !updated.isLoading, updated.url != nil {
                self?.browserEngineLoadedPageIDs.insert(updated.id)
            }
        }
        // 下载落盘目录（FR-EDIT-34）：目录归宿主（用户**显式授权**过的那一个），
        // 没有授权就返回 nil ⇒ 引擎拒绝并说明 —— 沙箱里偷偷落到容器里，用户会
        // 「下载成功但找不到文件」。
        engine.downloadDirectory = { [weak self] in
            self?.host?.browserDownloadDirectory()
        }
        engine.onDownloadEvent = { [weak self] outcome in
            guard let self else { return }
            let current = self.browserPages.first { $0.id == page.id } ?? BrowserPage(id: page.id)
            self.handleBrowserDownload(outcome, page: current)
        }
        browserEngines[page.id] = engine
        return engine
    }

    /// 下载进展 → 页上提示条 + 外发留痕（FR-EDIT-34 / NFR-SEC-08）。
    ///
    /// **下载也是出网**：不管成功、失败还是被拒，都留一条账 —— 与浏览器导航同一条纪律。
    /// 留痕本身走宿主（外发日志面板是 `AppState` 的数据），本模型只出形状
    /// （目标 / 明细 / 页签身份）与那条要显示在页上的提示。
    func handleBrowserDownload(_ outcome: WebKitBrowserEngine.DownloadOutcome, page: BrowserPage) {
        let tabTitle = page.title ?? page.url?.absoluteString
        let target = page.url?.absoluteString ?? "(未知来源)"

        func record(_ result: EgressOutcome, detail: String) {
            host?.recordBrowserDownloadEgress(
                outcome: result,
                target: target,
                detail: detail,
                tabID: page.id,
                tabTitle: tabTitle
            )
        }

        func showNotice(_ message: String) {
            guard let index = browserPages.firstIndex(where: { $0.id == page.id }) else { return }
            browserPages[index].setNotice(message)
        }

        switch outcome {
        case .refused(let reason):
            record(.denied, detail: reason)
            showNotice(reason)
        case .started(let filename):
            showNotice(L(.browserDownloadStarted, filename))
        case .finished(let filename, let url):
            record(.allowed, detail: BrowserDownload.logDetail(filename: filename, outcome: "完成"))
            showNotice(L(.browserDownloadFinished, url.path))
        case .failed(let filename, let reason):
            record(.failed, detail: BrowserDownload.logDetail(filename: filename, outcome: "失败：\(reason)"))
            showNotice(L(.browserDownloadFailed, filename, reason))
        }
    }

    // MARK: 导航

    /// 把引擎回报的状态写回模型（引擎在主线程回调，这里只做转发）。
    func applyBrowserUpdate(_ page: BrowserPage) {
        guard let index = browserPages.firstIndex(where: { $0.id == page.id }) else { return }
        browserPages[index] = page
        // 标题 / 地址变化也落盘：否则下次恢复出来的是上次启动时的旧地址。
        persistBrowserTabs()
    }

    /// 地址栏提交：解析 → 交给引擎（引擎内部先过 Core 策略、再写外发日志）。
    func navigateBrowserTab(_ id: UUID, input: String) {
        guard let page = browserPages.first(where: { $0.id == id }) else { return }
        switch BrowserSession.parseAddress(input) {
        case .success(let url):
            let engine = browserEngine(for: page)
            Task { await engine.load(url) }
        case .failure(let error):
            var rejected = page
            rejected.rejectNavigation(reason: error.reason)
            applyBrowserUpdate(rejected)
        }
    }

    /// 在浏览器里打开某个地址（供「用浏览器打开」这类入口复用）。
    func openInBrowser(_ text: String) {
        let id = browserPages.contains(where: { $0.id == selectedBrowserID })
            ? selectedBrowserID!
            : openBrowserTab()
        navigateBrowserTab(id, input: text)
    }

    // MARK: 会话持久化

    /// 恢复上次的浏览器页签：**只恢复地址与历史，不发起任何请求**。
    ///
    /// 恢复完**不自动选中**它们 —— 用户上次在写代码，就该回到工作区（选中态不持久化是刻意的：
    /// 把「上次在看某个网页」当成默认状态，反而会在启动时把一个空白浏览器推到眼前）。
    func restoreBrowserTabs() async {
        do {
            browserPages = try await browserTabStore.load()
        } catch {
            // 文件损坏之类：如实说出来，但不要打断启动。
            host?.reportBrowserStatusMessage(ErrorPresenter.message(for: error))
        }
    }

    /// 任何页签变化都落盘（失败只提示，不影响使用）。
    private func persistBrowserTabs() {
        let pages = browserPages
        Task {
            do {
                try await browserTabStore.save(pages)
            } catch {
                host?.reportBrowserStatusMessage(ErrorPresenter.message(for: error))
            }
        }
    }
}
