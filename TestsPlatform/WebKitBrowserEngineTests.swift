import XCTest
import WebKit

import DoyahCore
@testable import DoyahPlatform

/// `WKWebView` 引擎的适配测试（FR-EDIT-34）。
///
/// 盯住的是**平台侧最容易做错的那一处**：哪些导航算"用户发起"。
/// 判错会二选一地弄坏 —— 要么挡住地址栏（功能坏），要么放过脚本跳转（安全属性坏）。
/// 另外验证引擎的拦截路径**确实写了外发日志**（不需要联网）。
@MainActor
final class WebKitBrowserEngineTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebKitEngineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    // MARK: - 用户发起判定（安全属性）

    func testUserInitiatedNavigationTypes() {
        XCTAssertTrue(WebKitBrowserEngine.isUserInitiated(.linkActivated))
        XCTAssertTrue(WebKitBrowserEngine.isUserInitiated(.formSubmitted))
        XCTAssertTrue(WebKitBrowserEngine.isUserInitiated(.formResubmitted))
        XCTAssertTrue(WebKitBrowserEngine.isUserInitiated(.backForward))
    }

    /// `.other`（脚本跳转 / meta 刷新 / 预取）与 `.reload` **都不算**用户发起。
    ///
    /// 这条如果你看到它被改成 `true`，请先读 `浏览器页签-设计说明.md` §2：
    /// 那等于把「默认不加载远程内容」这条保证扔掉。
    func testScriptedAndReloadNavigationsAreNotUserInitiated() {
        XCTAssertFalse(WebKitBrowserEngine.isUserInitiated(.other))
        XCTAssertFalse(WebKitBrowserEngine.isUserInitiated(.reload))
    }

    // MARK: - 拦截路径 + 留痕

    /// `javascript:` 被 Core 策略拒绝：**不加载**、页面停在原地、日志留下一条 `denied`。
    func testBlockedSchemeDoesNotNavigateAndIsRecorded() async throws {
        let log = EgressLog(directoryURL: directory)
        let pageID = UUID()
        let engine = WebKitBrowserEngine(pageID: pageID, origin: "浏览器 · 页签 1", log: log)

        var reported: BrowserPage?
        engine.setUpdateHandler { reported = $0 }

        await engine.load(URL(string: "javascript:alert(1)")!)

        XCTAssertNil(reported?.url, "被拒绝的导航不该改变地址")
        XCTAssertNotNil(reported?.lastError)

        let entries = try await log.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.kind, .browser)
        XCTAssertEqual(entries.first?.outcome, .denied)
        XCTAssertEqual(entries.first?.origin, "浏览器 · 页签 1")
    }

    /// **真缺陷（2026-09-29 第 103 轮）**：**地址栏导航**这条路原先漏了 `tabID` / `tabTitle`
    /// ⇒ 它留下的每一条日志都没有页签身份，于是「按页签筛」那台下拉永远空（而页面内点击那条路
    /// 一直带着身份 —— 同一个东西两种口径）。判据：**从地址栏发起**的导航，盘上那条要带页签身份。
    ///
    /// 标签此时是页面的默认标题（新建页签 = 「新页签」），真标题要等引擎回报 ——
    /// 同一页签前后几条标签不一样是正常的，下拉那边靠「短标签允许被后来的标题替换」兜住。
    func testAddressBarNavigationRecordsTabIdentity() async throws {
        let log = EgressLog(directoryURL: directory)
        let pageID = UUID()
        let engine = WebKitBrowserEngine(pageID: pageID, origin: "浏览器 · 页签 1", log: log)

        await engine.load(URL(string: "javascript:alert(1)")!)

        let entries = try await log.entries()
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.tabID, pageID, "地址栏导航那条没有页签 id ⇒ 按页签筛永远查不到它")
        XCTAssertFalse(entry.tabTitle?.isEmpty ?? true, "标签为空 ⇒ 下拉里那一项认不出是哪个页签")
    }

    /// 空白页：不加载、也**不产生日志条目**（它没有出网）。
    func testBlankPageProducesNoEntry() async throws {
        let log = EgressLog(directoryURL: directory)
        let engine = WebKitBrowserEngine(pageID: UUID(), origin: "浏览器 · 页签 1", log: log)

        await engine.load(URL(string: "about:blank")!)

        let count = try await log.count()
        XCTAssertEqual(count, 0)
    }

    /// 初始状态就是一个空白页（契约：默认不加载任何远程内容）。
    func testInitialStateIsBlank() {
        let engine = WebKitBrowserEngine(pageID: UUID(), origin: "浏览器 · 页签 1", log: EgressLog(directoryURL: directory))
        var reported: BrowserPage?
        engine.setUpdateHandler { reported = $0 }

        XCTAssertNil(reported?.url)
        XCTAssertFalse(reported?.isLoading ?? true)
        XCTAssertFalse(engine.view.isLoading)
    }

    /// 站点存储按常规浏览器（`FR-STD-WS-WEB-004` ②，2026-10-28 第三十四批）。
    ///
    /// **口径变更**：这条断言原来写的是「默认必须**非**持久化，避免与客户端数据混放」，由头是
    /// 2026-09 的自我约束。需求书 `FR-STD-WS-WEB-004` ② 要求「依赖第三方 Cookie 的登录跳转
    /// 返回后仍是登录态、站点存储按常规行为工作」—— 非持久化存储做不到这一点（重启即断登录）。
    /// 所以缺省改成持久化；「不与客户端数据混放」这条**没有取消**，只是换了守它的地方：
    /// 站点数据仍只落在**本应用容器**的 WebKit 目录，SQL 连接信息与凭据在钥匙串（见引擎头部注释 ③）。
    func testEngineUsesRegularBrowserStorageByDefault() {
        let engine = WebKitBrowserEngine(pageID: UUID(), origin: "浏览器 · 页签 1", log: EgressLog(directoryURL: directory))
        XCTAssertTrue(engine.view.configuration.websiteDataStore.isPersistent,
                      "缺省应为持久化存储，否则登录态跨重启必断（FR-STD-WS-WEB-004 ②）")
    }

    /// 站点身份：UA 落到 WebView 上，且**不拼产品名**（`FR-STD-WS-WEB-004` ①）。
    func testEngineAnnouncesARegularBrowserIdentity() {
        let engine = WebKitBrowserEngine(pageID: UUID(), origin: "浏览器 · 页签 1", log: EgressLog(directoryURL: directory))
        let ua = engine.view.customUserAgent ?? ""
        XCTAssertEqual(ua, BrowserIdentity.userAgent)
        XCTAssertTrue(ua.contains("Safari/"), ua)
        XCTAssertFalse(ua.lowercased().contains("doyah"), ua)
        XCTAssertNil(engine.view.configuration.applicationNameForUserAgent)
    }

    /// 弹窗要有可见结果：`WKUIDelegate` 必须接上（否则 `target=_blank` 被静默吞掉）。
    func testEngineHasAUIDelegateForPopups() {
        let engine = WebKitBrowserEngine(pageID: UUID(), origin: "浏览器 · 页签 1", log: EgressLog(directoryURL: directory))
        XCTAssertNotNil(engine.view.uiDelegate, "没有 UIDelegate 时 window.open / target=_blank 会静默无反应")
    }

    // MARK: - 站点存储按页签隔离（`FR-STD-WS-WEB-001` ③）

    /// 两个页签**各有一套**站点存储 —— 共用一份等于 A 页签登录过的站点在 B 页签也是登录态。
    func testEachTabGetsItsOwnSiteStore() {
        let log = EgressLog(directoryURL: directory)
        let first = WebKitBrowserEngine(pageID: UUID(), origin: "浏览器 · 页签 1", log: log)
        let second = WebKitBrowserEngine(pageID: UUID(), origin: "浏览器 · 页签 2", log: log)

        let a = first.view.configuration.websiteDataStore
        let b = second.view.configuration.websiteDataStore
        XCTAssertFalse(a === b, "两个页签不能共用一个站点存储（否则 Cookie 互串）")
        XCTAssertTrue(a.isPersistent && b.isPersistent, "按页签分仍然是持久化存储（登录态要跨重启）")
        XCTAssertFalse(a === WKWebsiteDataStore.default(), "也不该回落到全应用那一份缺省存储")
    }

    /// 同一页签 id 重建引擎（会话恢复）⇒ 还是那一套存储，登录态不丢。
    func testRebuildingTheSameTabKeepsItsSiteStore() {
        let log = EgressLog(directoryURL: directory)
        let id = UUID()
        let before = WebKitBrowserEngine(pageID: id, origin: "浏览器 · 页签 1", log: log)
        let after = WebKitBrowserEngine(pageID: id, origin: "浏览器 · 页签 1", log: log)

        XCTAssertTrue(
            before.view.configuration.websiteDataStore === after.view.configuration.websiteDataStore,
            "同一页签重建后必须拿回同一套站点存储，否则重启后登录态必断（FR-STD-WS-WEB-004 ②）"
        )
    }

    /// 显式注入的存储照旧优先（探针 / 预览页那条路要能指定）。
    func testExplicitStoreWins() {
        let log = EgressLog(directoryURL: directory)
        let injected = WKWebsiteDataStore(forIdentifier: UUID())
        let engine = WebKitBrowserEngine(pageID: UUID(), origin: "编辑器 · 网页预览", log: log, websiteDataStore: injected)

        XCTAssertTrue(engine.view.configuration.websiteDataStore === injected)
    }
}
