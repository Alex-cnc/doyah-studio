import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **工作区打开文件的路由** —— 队列 `L-149` 剩余②（`.html` / `.htm` 接到浏览器视图）。
///
/// ## 由头（需求提出者 2026-09-30 原话）
///
/// 「浏览器内置到工作区 Tab 页，而不是放到数据库 SQL 查询界面，**本质上 html 也是一种文件**」。
/// 第 131 / 134 / 135 轮把浏览器页签的**展示层 / 条文 / 状态所有者**搬进了工作区，
/// 但 `.html` 点开之后**还是当文本打开** —— 这一片补的就是这一步。
///
/// ## 判据方向（队列原文三条）
///
/// ① 工作区树里点 `.html` ⇒ 开在工作区页签且是**浏览器视图**；
/// ② 数据库侧页签条里**不再**出现浏览器页签（由 `Scripts/check-browser-tab-ownership.py` 守着）；
/// ③ 语言登记表里 `.html` 的消费者必须是浏览器视图（可断言）。
///
/// 本族判的是 ① 与 ③ 的**接线**那一半：路由问的是**登记表里的数据**
/// （`CodeLanguageRegistry.defaultView(forPath:)`），不是这里的字符串比较；
/// 「浏览器页签真的渲染出页面」是观感，归人工点验（清单 §10）。
///
/// ## 边界（如实登记，别当已验）
///
/// · 不验渲染：本族只看**路由与页签账**（`browserPages` / 选中态 / 有没有被开成文本页签）；
///   本机页面的样式与图片能不能加载出来，要真窗口 + 真点击（清单 §10.24）；
/// · 不写用户数据：临时工作区 + 临时页签库 + 临时外发日志目录都在 `.build/` 下（跑完删）；
/// · **不挂 `DOYAH_UI_SNAPSHOT`**（离屏、不渲染位图）⇒ 与 `WorkspaceChromeHeightProbeTests`
///   同一档，随每轮门禁第 1 项天天跑。
final class WorkspaceFileRoutingProbeTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = UISnapshot.outputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("workspace-file-routing-probe", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        try write("<!DOCTYPE html>\n<html><body><h1>本地页面</h1></body></html>", as: "index.html")
        try write("<html><body>另一页</body></html>", as: "page.htm")
        try write("<!DOCTYPE html>\n<html><body>xhtml</body></html>", as: "TEMPLATE.XHTML")
        try write("# 说明\n\n正文\n", as: "notes.md")
        try write("select 1;\n", as: "schema.sql")
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        scratch = nil
    }

    private func write(_ text: String, as name: String) throws {
        try text.write(to: scratch.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    // MARK: - 装配（全在临时目录里，不碰用户数据）

    @MainActor
    private func makeTabs() -> WorkspaceTabsModel {
        WorkspaceTabsModel(
            store: WorkspaceHistoryStore(fileURL: scratch.appendingPathComponent("history-\(UUID().uuidString).json"))
        )
    }

    @MainActor
    private func makeBrowser() -> WorkspaceBrowserModel {
        WorkspaceBrowserModel(
            browserTabStore: BrowserTabStore(directoryURL: scratch.appendingPathComponent("browser-tabs", isDirectory: true)),
            egressLog: EgressLog(directoryURL: scratch.appendingPathComponent("egress", isDirectory: true))
        )
    }

    // MARK: - ① 登记表说「默认用浏览器打开」的那一类

    /// `.html` ⇒ **交给浏览器那一侧**，且**不同时**开成文本页签。
    @MainActor
    func testHTMLFileIsHandedToTheBrowserSide() throws {
        let tabs = makeTabs()
        var handed: [URL] = []
        tabs.openInBrowserTab = { handed.append($0) }
        let html = scratch.appendingPathComponent("index.html")

        tabs.openFile(at: html)

        XCTAssertEqual(handed, [html], "`.html` 必须走工作区的浏览器页签那一侧")
        XCTAssertFalse(tabs.tabs.contains { $0.path == html.path }, "不该同时开成文本页签")
        XCTAssertEqual(tabs.history.files.first?.path, html.path, "打开过就该进「最近文件」")
        XCTAssertNil(tabs.errorText)
    }

    /// `.htm` 与**大写**扩展名走同一条路 —— 判的是登记表（判语言不分大小写），不是字符串比较。
    @MainActor
    func testHTMAndUppercaseExtensionFollowTheRegistry() throws {
        let tabs = makeTabs()
        var handed: [URL] = []
        tabs.openInBrowserTab = { handed.append($0) }

        let htm = scratch.appendingPathComponent("page.htm")
        let xhtml = scratch.appendingPathComponent("TEMPLATE.XHTML")
        tabs.openFile(at: htm)
        tabs.openFile(at: xhtml)

        XCTAssertEqual(handed, [htm, xhtml])
        XCTAssertFalse(
            tabs.tabs.contains { $0.path == htm.path || $0.path == xhtml.path },
            "两个文件都不该在编辑器里开成文本页签"
        )
    }

    // MARK: - ② 对照：别的文件照旧进编辑器（证明路由没有把大家都带走）

    @MainActor
    func testNonMarkupFileStaysInTheEditor() throws {
        let tabs = makeTabs()
        var handed: [URL] = []
        tabs.openInBrowserTab = { handed.append($0) }

        for name in ["notes.md", "schema.sql"] {
            let file = scratch.appendingPathComponent(name)
            tabs.openFile(at: file)
            XCTAssertEqual(tabs.tabs.filter { $0.path == file.path }.count, 1, "\(name) 应当开成一个文本页签")
        }

        XCTAssertTrue(handed.isEmpty, "非标记文件不该被交给浏览器")
    }

    /// **没接线时不静默丢失**：宿主没注入交接闭包时，`.html` 照旧当文本打开（能看源码），
    /// 而不是点一下什么反应都没有。
    @MainActor
    func testUnwiredRouteFallsBackToTheTextEditor() throws {
        let tabs = makeTabs()
        let html = scratch.appendingPathComponent("index.html")

        tabs.openFile(at: html)

        XCTAssertEqual(tabs.tabs.filter { $0.path == html.path }.count, 1)
        XCTAssertNil(tabs.errorText)
    }

    // MARK: - ③ 真接线（宿主 `DoyahStudioApp` 注入的那一条）落到的账

    /// 走真接线：浏览器模型里**真的**多了一个指向该文件的页签、被选中、且**不停在恢复态**
    /// （恢复态是给"上次开着这次没点"的页签用的；这个文件是用户刚点的）。
    @MainActor
    func testWiredRouteOpensTheFileInTheBrowserModel() throws {
        let tabs = makeTabs()
        let browser = makeBrowser()
        tabs.openInBrowserTab = { [browser] url in browser.openFileInBrowser(url) }
        let html = scratch.appendingPathComponent("index.html")

        tabs.openFile(at: html)

        XCTAssertEqual(browser.browserPages.count, 1)
        let page = try XCTUnwrap(browser.browserPages.first)
        XCTAssertEqual(page.url, html)
        XCTAssertEqual(browser.selectedBrowserID, page.id, "打开的文件应当是被选中的那一个页签")
        XCTAssertFalse(
            browser.isBrowserPagePristine(page.id),
            "用户刚点开的文件不该显示那条「点一下才加载」的恢复态"
        )
        XCTAssertFalse(tabs.tabs.contains { $0.path == html.path }, "浏览器那一侧开了，文本那一侧就不该再开")
    }

    /// 同一个文件点两次 ⇒ 仍然只有一个页签（与文件页签同一口径：不重复开）。
    @MainActor
    func testOpeningTheSameFileTwiceReusesTheBrowserTab() throws {
        let tabs = makeTabs()
        let browser = makeBrowser()
        tabs.openInBrowserTab = { [browser] url in browser.openFileInBrowser(url) }
        let html = scratch.appendingPathComponent("index.html")

        tabs.openFile(at: html)
        let first = try XCTUnwrap(browser.browserPages.first).id
        tabs.openFile(at: html)

        XCTAssertEqual(browser.browserPages.count, 1)
        XCTAssertEqual(browser.selectedBrowserID, first)
        XCTAssertEqual(tabs.history.files.filter { $0.path == html.path }.count, 1, "「最近文件」也不该出现两条")
    }
}
