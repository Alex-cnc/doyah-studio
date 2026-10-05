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

    /// 独立数据存储：引擎默认不共享客户端的持久化存储。
    func testEngineUsesIsolatedDataStoreByDefault() {
        let engine = WebKitBrowserEngine(pageID: UUID(), origin: "浏览器 · 页签 1", log: EgressLog(directoryURL: directory))
        XCTAssertFalse(engine.view.configuration.websiteDataStore.isPersistent,
                       "默认应当用非持久化存储，避免与客户端数据混放")
    }
}
