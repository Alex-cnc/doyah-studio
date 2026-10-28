import Foundation
import Security
import WebKit

import DoyahCore

/// macOS 侧的浏览器引擎实现：`WKWebView`（FR-EDIT-34）。
///
/// **这个类只做三件事**：渲染、回报状态、把每次导航决策交给 Core 的策略。
/// 它**不自己判断"要不要加载"** —— 那是 `BrowserNavigationPolicy` 的事（换引擎时规则必须一字不差）。
///
/// 安全属性（与契约一致）：
/// 1. **默认不加载远程内容**：只有地址栏回车（走 `load(_:)`）或页面内点击链接才放行；
///    引擎的自动跳转 / 会话恢复 / 预取一律按非用户发起处理 → 拒绝 + 留痕；
/// 2. **不注入任何脚本桥**：不注册 `WKScriptMessageHandler`，网页拿不到客户端能力；
/// 3. **站点存储按常规浏览器**（2026-10-28 第三十四批，`FR-STD-WS-WEB-004` ②）：缺省持久化 ——
///    否则「登录跳转回来后还是登录态」这条在重启 / 多次导航后必然断；站点数据仍只落在**本应用容器**的
///    WebKit 目录里，与 SQL 客户端的连接信息、钥匙串凭据不混放（原来那句「默认非持久化」已作废）；
/// 4. 每次裁决（放行 / 拦截）都写进统一外发日志。
///
/// **已知边界**：`WKWebView` 的公开 API 不暴露单个子资源请求，所以日志是**导航级**的
/// （见 `Docs/design/浏览器页签-设计说明.md` §4）。要做到子资源级只能自建本地代理，
/// 体量与风险都不合算 —— 这一条写在需求书里，不假装做到。
@MainActor
public final class WebKitBrowserEngine: NSObject, BrowserEngine {

    public let pageID: UUID

    /// 交给 SwiftUI 承载的视图。
    public let view: WKWebView

    /// 一次下载的进展（引擎 → 应用层）。
    ///
    /// 为什么由应用层收：**落哪个目录、要不要记外发日志、界面说什么**都是产品决定，
    /// 引擎只回答"技术上下载成了没成"。这也让 Core 的命名规则（`BrowserDownload`）能被单测。
    public enum DownloadOutcome: Equatable, Sendable {
        /// 没有可用目录（或同名太多）：`nil` 目标会被 WebKit 当成取消。
        case refused(reason: String)
        case started(filename: String)
        case finished(filename: String, url: URL)
        case failed(filename: String, reason: String)
    }

    /// 下载落地的目录（应用层注入：走用户授权目录，见 `BrowserDownload` 的说明）。
    /// 返回 `nil` 表示"没有可用目录"，引擎会拒绝这次下载并如实说明。
    public var downloadDirectory: (@MainActor () -> URL?)?
    /// 下载进展回调（应用层据此写外发日志与界面状态）。
    public var onDownloadEvent: (@MainActor (DownloadOutcome) -> Void)?

    /// 拒绝理由用哪种语言渲染（**应用层注入**）。
    ///
    /// 引擎在独立的 target（`DoyahPlatform`）里，看不到应用层的语言管理器 ⇒ 与
    /// `downloadDirectory` 同一形状：**谁拥有语言谁注入**。默认简体中文 ——
    /// 那是 `Core/BrowserPage.swift` 每个入口的默认值，不是这里另开的一个口径。
    public var languageProvider: (@MainActor () -> AppLanguage) = { .simplifiedChinese }

    /// 预览页的**读权限根**（`FR-STD-WS-WEB-003` ④）：非 `nil` 时，`file:` 导航必须落在根里。
    ///
    /// 为什么由引擎判而不是只靠 `loadFileURL(_:allowingReadAccessTo:)`：那一条管的是**子资源读盘**，
    /// 页面里点一个指向 `../../` 的链接仍然是一次导航。规则与 Core 共用 `HTMLPreview.decide`
    /// （一处口径），浏览器页签不设它 ⇒ 行为一字未变。
    public var localReadRoot: URL?

    /// 正在进行的下载：`WKDownload` 的完成 / 失败回调里拿不到文件名与落盘位置，
    /// 得在"选目标"那一步自己记下来（这也是唯一知道目标的时刻）。
    private var downloadTargets: [ObjectIdentifier: (filename: String, url: URL)] = [:]

    private let origin: String
    private let log: EgressLog
    private var page: BrowserPage
    private var updateHandler: (@MainActor (BrowserPage) -> Void)?

    /// 本次加载是否由**应用层显式发起**（地址栏 / 前进后退按钮）。
    ///
    /// 为什么需要它：`WKNavigationAction.navigationType` 里，地址栏导航会落成 `.other` ——
    /// 与"脚本自己发起的跳转"同类。只靠它判断会把地址栏也当成自动加载挡掉（功能坏掉），
    /// 或者反过来把脚本跳转放过去（安全属性坏掉）。所以由我们自己标记"这是用户按的"。
    private var explicitLoadRequested = false

    public init(
        pageID: UUID = UUID(),
        origin: String = "浏览器 · 页签",
        log: EgressLog = .shared,
        websiteDataStore: WKWebsiteDataStore = .default()
    ) {
        self.pageID = pageID
        self.origin = origin
        self.log = log
        self.page = BrowserPage(id: pageID)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        // 站点身份（`FR-STD-WS-WEB-004` ①）：**不往 UA 尾巴上拼产品名** —— 拼了就等于自报
        // 「内嵌面板」，站点据此降级（`nil` = 不拼）。
        configuration.applicationNameForUserAgent = BrowserIdentity.applicationNameForUserAgent
        // 刻意不注册任何 WKScriptMessageHandler：网页不该有通往客户端能力的桥。

        self.view = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        self.view.navigationDelegate = self
        // UA 原文由 Core 唯一给出（确定性：同一台机器每次都是同一串）。
        self.view.customUserAgent = BrowserIdentity.userAgent
        // 弹窗（`FR-STD-WS-WEB-004` ③）：没有 `WKUIDelegate` 时 `target=_blank` / `window.open`
        // 会被**静默吞掉**（用户点了像没点）—— 接上之后至少有可见结果。
        self.view.uiDelegate = self
    }

    public func setUpdateHandler(_ handler: @escaping @MainActor (BrowserPage) -> Void) {
        updateHandler = handler
        handler(page)
    }

    public func load(_ url: URL) async {
        // 地址栏导航：用户显式发起，但仍**必须过策略**（策略是唯一出口）。
        await navigate(to: url, isUserInitiated: true)
    }

    /// 渲染一段**未保存的缓冲**（`FR-STD-WS-WEB-003` ②：编辑器里改了还没存，预览看到的就是改后的那份）。
    ///
    /// 与 `load(_:)` 的差别只在「内容从哪来」：这里内容已经在内存里 ⇒ **没有出网**，不写外发日志；
    /// 读权限仍然只到 `baseDirectory`（同目录的 css / 图片照常能读，别处照旧读不到）。
    public func loadHTMLString(_ html: String, baseDirectory: URL) {
        view.loadHTMLString(html, baseURL: baseDirectory)
    }

    public func goBack() async {
        guard let url = page.goBack() else { return }
        publish()
        await navigate(to: url, isUserInitiated: true)
    }

    public func goForward() async {
        guard let url = page.goForward() else { return }
        publish()
        await navigate(to: url, isUserInitiated: true)
    }

    public func reload() async {
        guard let url = page.url else {
            view.reload()
            return
        }
        await navigate(to: url, isUserInitiated: true)
    }

    public func stopLoading() {
        view.stopLoading()
        page.rejectNavigation(reason: page.lastError ?? "")
        page.finishNavigation(title: nil)
        publish()
    }

    /// **唯一**的导航入口：裁决 → 留痕（await，记完才走）→ 交给 WebView 或就地拒绝。
    ///
    /// 为什么是 `await` 而不是起一个游离的 `Task`：出网日志的意义就在于"出事时它已经写下了"。
    /// 游离 Task 既没有时序保证，也很容易漏掉后退 / 前进 / 刷新这些同样出网的路径
    /// （它们原来直接调 `view.load`，绕过了一切判定与记录）。
    private func navigate(to url: URL, isUserInitiated: Bool) async {
        let transition = BrowserSession.navigate(
            page: page,
            to: url,
            origin: origin,
            isUserInitiated: isUserInitiated,
            language: languageProvider()
        )
        page = transition.page
        publish()

        // 页签身份**与代理那条路同一份口径**（2026-09-29 第 103 轮实测的真缺陷）：
        // 这里原先漏了 `tabID` / `tabTitle` ⇒ **地址栏导航**留下的那一条日志没有页签身份，
        // 于是清单 `FR-EDIT-34` 里「打开一个站点 → 按页签筛一次」在真机上筛不出来 ——
        // 而"页面内点击"那条路（`decidePolicyFor`）是带着的，两条路记出来的记录形状不一致。
        await BrowserSession.record(
            transition,
            origin: origin,
            tabID: pageID,
            tabTitle: tabLabel,
            log: log
        )

        guard let loadURL = transition.urlToLoad else { return }
        // 这一次 `view.load` 是"应用层已裁决过"的，代理里放行即可（一次标记，一次消费）。
        explicitLoadRequested = true
        present(loadURL)
    }

    /// 真正交给 WebView 的那一步。
    ///
    /// **本机文件必须走 `loadFileURL`**（队列 `L-149` 剩余②）：`WKWebView` 不把 `file:` 当成
    /// 可导航的请求，`load(URLRequest(fileURL))` 会以 `WebKitErrorDomain` 失败 ——
    /// 而 `loadFileURL(_:allowingReadAccessTo:)` 才是官方的本机文件入口（它同时把沙箱读权限
    /// 交给渲染进程，这正是沙箱里本机页面能读到自己同目录资源的原因）。
    ///
    /// 读取范围 = 该文件**所在的目录**：本机页面里的同目录资源（css / 图片 / 脚本）本来就要一起读，
    /// 收得只剩一个文件会让页面渲染成裸文档。这一步仍然**只在用户显式发起**时到达（策略已放行）、
    /// 也已经**写过外发日志**；写盘照旧走授权目录 —— 给读权限不等于给写权限。
    private func present(_ url: URL) {
        if url.isFileURL {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            view.load(URLRequest(url: url))
        }
    }

    private func publish() {
        updateHandler?(page)
    }

    /// 日志那条记录上的**页签标签** = 页面当前的标题。
    ///
    /// 三处记录点共用这一份口径：同一个东西不许有两个说法 —— 两条路记出来的记录形状不一致，
    /// 「按页签筛」就会漏（2026-09-29 第 103 轮实测：地址栏那条路原先连 `tabID` 都没带）。
    ///
    /// 注意新建页签的标题就是「新页签」那一档，真标题由引擎 `finishNavigation` 之后才回报
    /// ⇒ **同一页签前后几条记录的标签会不一样**；所以「按页签筛」下拉那边的口径是
    /// 「短标签允许被后来的标题替换」（`EgressTabOptions`）。
    private var tabLabel: String { page.title }
}

// MARK: - WKNavigationDelegate

extension WebKitBrowserEngine: WKNavigationDelegate {

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        let url = navigationAction.request.url

        // 应用层显式动作（地址栏 / 后退前进 / 刷新）已在 `navigate(to:)` 里裁决并记过日志，
        // 这里放行即可 —— 但仍然只在"确实标记过"时放行，不让标记无限期生效。
        if explicitLoadRequested {
            explicitLoadRequested = false
            return .allow
        }

        // 下载：`shouldPerformDownload` 是 WebKit 给的明确信号（点了下载链接 / 附件）。
        // 它仍然要**记一条外发日志**再走 —— 下载同样是出网。
        if navigationAction.shouldPerformDownload {
            let transition = BrowserSession.navigate(
                page: page,
                to: url,
                origin: origin,
                isUserInitiated: Self.isUserInitiated(navigationAction.navigationType),
                language: languageProvider()
            )
            page = transition.page
            publish()
            await BrowserSession.record(
                transition,
                origin: origin,
                tabID: pageID,
                tabTitle: tabLabel,
                log: log
            )
            return .download
        }

        let userInitiated = Self.isUserInitiated(navigationAction.navigationType)
        let transition = BrowserSession.navigate(
            page: page,
            to: url,
            origin: origin,
            isUserInitiated: userInitiated,
            language: languageProvider()
        )
        page = transition.page
        publish()

        // 页面内点击 / 脚本跳转同样"记完再走"。
        await BrowserSession.record(
            transition,
            origin: origin,
            tabID: pageID,
            tabTitle: tabLabel,
            log: log
        )

        // 预览页的读权限根（`FR-STD-WS-WEB-003` ④）：`file:` 落在根外、或页面想加载远程地址，
        // 都在这里拦下并说清原因（远程那一档在 Core 里是「交给浏览器页签」—— 原因本身就是出路）。
        if let root = localReadRoot, let url {
            let decision = HTMLPreview.decide(
                resource: url,
                baseDirectory: root,
                language: languageProvider()
            )
            if let reason = decision.reason {
                var blocked = transition
                blocked.page.rejectNavigation(reason: reason)
                blocked.urlToLoad = nil
                blocked.egressOutcome = .denied
                blocked.egressDetail = reason
                blocked.shouldRecord = true
                page = blocked.page
                publish()
                await BrowserSession.record(
                    blocked,
                    origin: origin,
                    tabID: pageID,
                    tabTitle: tabLabel,
                    log: log
                )
                return .cancel
            }
        }

        return transition.urlToLoad == nil ? .cancel : .allow
    }

    /// 由 `navigationType` 判断是否用户发起。
    ///
    /// `.other` **不算**用户发起：脚本跳转、meta 刷新、预取都落在这里。
    /// 这偏保守，代价是某些站点内部的合法跳转会被拦 —— 宁可拦掉让用户手动点一次，
    /// 也不要让"默认不加载远程内容"这条保证失效。
    static func isUserInitiated(_ type: WKNavigationType) -> Bool {
        switch type {
        case .linkActivated, .formSubmitted, .formResubmitted, .backForward:
            return true
        case .other, .reload:
            return false
        @unknown default:
            return false
        }
    }

    /// 响应阶段：WebKit 显示不了的 MIME（附件、二进制）转下载。
    ///
    /// `canShowMIMEType == false` 是官方判据 —— 自己去看 `Content-Disposition` 字符串
    /// 容易漏（大小写、参数、引号），而且 `navigationResponse.response` 未必带那个头。
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    public func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    public func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        page.finishNavigation(title: nil)      // 先结束上一轮的加载态
        publish()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        page.finishNavigation(title: webView.title)
        publish()
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        page.failNavigation(reason: error.localizedDescription)
        publish()
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        page.failNavigation(reason: error.localizedDescription)
        publish()
    }

    /// 证书挑战（`FR-STD-WS-WEB-004` ④）：不受信就**取消并说明原因**，不静默放行、也不白屏。
    ///
    /// 判定分类交 Core（`BrowserCertificatePolicy`）；这里只说得出「系统信任评估没通过」这一层，
    /// 所以失败类别按最保守的那一档（签发者不受信任）报 —— 宁可说得笼统，不许说成具体原因。
    public func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        let prompt = BrowserCertificatePolicy.prompt(for: .untrustedAnchor, language: languageProvider())
        page.setNotice(prompt.message)
        publish()
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

// MARK: - WKUIDelegate（FR-STD-WS-WEB-004 ③）

extension WebKitBrowserEngine: WKUIDelegate {

    /// 页面要开新窗口：**必须有可见结果**，所以回 `nil`（不在引擎里悄悄造假页签）的同时
    /// 把带地址的那句话挂到页面提示条上 —— 用户至少知道「点了之后发生了什么、地址是什么」。
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let notice = BrowserPopupPolicy.decide(
            url: navigationAction.request.url,
            language: languageProvider()
        )
        page.setNotice(notice.message)
        publish()
        return nil
    }
}

// MARK: - WKDownloadDelegate（FR-EDIT-34）

extension WebKitBrowserEngine: WKDownloadDelegate {

    /// 目标路径：授权目录 + 安全文件名 + 不覆盖已有文件（规则全在 `BrowserDownload` 里）。
    public func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let filename = BrowserDownload.sanitizeFilename(suggestedFilename)

        guard let directory = downloadDirectory?() else {
            onDownloadEvent?(.refused(reason: BrowserDownload.noDirectoryReason))
            completionHandler(nil)
            return
        }

        let destination = BrowserDownload.destination(
            suggestedFilename: suggestedFilename,
            directory: directory,
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )
        switch destination {
        case .ready(let url):
            downloadTargets[ObjectIdentifier(download)] = (filename: filename, url: url)
            onDownloadEvent?(.started(filename: filename))
            completionHandler(url)
        case .refused(let reason):
            onDownloadEvent?(.refused(reason: reason))
            completionHandler(nil)
        }
    }

    public func downloadDidFinish(_ download: WKDownload) {
        let target = downloadTargets.removeValue(forKey: ObjectIdentifier(download))
        onDownloadEvent?(
            .finished(filename: target?.filename ?? "download", url: target?.url ?? URL(fileURLWithPath: "download"))
        )
    }

    public func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        let target = downloadTargets.removeValue(forKey: ObjectIdentifier(download))
        onDownloadEvent?(
            .failed(filename: target?.filename ?? "download", reason: error.localizedDescription)
        )
    }
}
