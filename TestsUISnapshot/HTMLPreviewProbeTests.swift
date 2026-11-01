import AppKit
import SwiftUI
import WebKit
import XCTest

import DoyahCore
import DoyahPlatform
@testable import DoyahStudioApp

/// **网页文件在编辑器内的预览**（`FR-STD-WS-WEB-003`）—— 需求 C 的 App 内行为探针。
///
/// ## 这条需求里能机器判的四件事
///
///   ① **一键切回源码 / 可分屏**：`.html` 既能在编辑器里当源码改，也能在旁边看渲染结果，
///      而且**同一份文件的两面互不覆盖**（预览不写盘、源码不被预览重排走）；
///   ② **未保存改动不丢**：脏着的时候预览渲染的是**缓冲**（看到的就是正在编辑的那份），
///      保存之后同一份页面改成读盘上那份；
///   ③ **相对路径按文件所在目录解析**：同目录的 css / 图片要读得到，越界与远程要**给可读理由**
///      （或交给浏览器页签）；
///   ④ **与浏览器页签同一个网页引擎**：预览里那枚 `WKWebView` 的 `navigationDelegate`
///      必须就是浏览器页签用的 `WebKitBrowserEngine`（策略 / 外发留痕 / 本机读权限三条口径
///      共用一份实现，而不是预览自带一个 `WKWebView`）。
///
/// ③ 的判定在 `Core/HTMLPreview.swift`（纯函数）；本探针判的是**它有没有真的被那枚视图接上**
/// —— 用临时目录里的真文件、真 `WorkspaceTabsModel`、真 `HTMLPreviewView`，并在视图树里把
/// `WKWebView` 掏出来读它的 `navigationDelegate` 与 `localReadRoot`。
///
/// ## 边界（如实登记）
///
/// · **页面真的画出来了吗**（DOM 渲染结果）不在本判据内：那要等 WebKit 的异步加载完成再对像素，
///   而离屏宿主里那一步不可靠（既有 `BrowserTabDownloadProbeTests` 也是同一条边界：判的是引擎
///   **之后**的每一环）。这里判的是「谁在渲染 / 渲染哪一份 / 允许读哪儿」—— 那是本需求真正的
///   判定面，缺失就会表现成「预览成裸文档」「未保存改动看不到」「整机可读」。
/// · 「预览与 Markdown 预览同一套交互」里的**观感**（面板宽度 / 分屏比例）不在本轮。
final class HTMLPreviewProbeTests: XCTestCase {

    private var root: URL!
    private var page: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HTMLPreviewProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // 夹具：一份页面 + 同目录的样式 + 子目录里的图片占位 + 一个「根之外」的文件。
        page = root.appendingPathComponent("index.html")
        try """
        <!doctype html><html><head><link rel="stylesheet" href="style.css"></head>
        <body><h1>标题</h1><img src="img/pic.png"><a href="https://example.com/away">远处</a></body></html>
        """.write(to: page, atomically: true, encoding: .utf8)
        try "h1 { color: #333 }".write(
            to: root.appendingPathComponent("style.css"), atomically: true, encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("img", isDirectory: true), withIntermediateDirectories: true
        )
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: root.appendingPathComponent("img/pic.png"))
        try "outside".write(
            to: root.deletingLastPathComponent().appendingPathComponent("outside-\(root.lastPathComponent).txt"),
            atomically: true, encoding: .utf8
        )
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(
                at: root.deletingLastPathComponent()
                    .appendingPathComponent("outside-\(root.lastPathComponent).txt")
            )
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - 装配

    @MainActor
    private func makeTabs() -> WorkspaceTabsModel {
        WorkspaceTabsModel(
            store: WorkspaceHistoryStore.standard(applicationSupport: root),
            sessionStore: WorkspaceSessionStore.standard(applicationSupport: root)
        )
    }

    private var facts: HTMLPreview.FileFacts {
        HTMLPreview.FileFacts(
            exists: FileManager.default.fileExists(atPath: page.path),
            isDirectory: false
        )
    }

    // MARK: - ① 计划：渲染哪一份 + 读权限根 = 文件所在目录

    func testPlanRendersTheFileAndConfinesReadsToItsDirectory() throws {
        guard case let .render(plan) = HTMLPreview.plan(
            path: page.path, isDirty: false, buffer: "", facts: facts
        ) else {
            return XCTFail("盘上有一份正常的 .html，却没给出渲染计划 —— 预览会是空白")
        }
        XCTAssertEqual(
            plan.source, .file(page),
            "干净的时候该渲染盘上那一份（不是缓冲、也不是别的文件）"
        )
        XCTAssertEqual(
            plan.readAccessRoot.path, root.path,
            "读权限根不是文件所在目录 ⇒ 同目录的 css / 图片读不到，页面会渲染成裸文档"
        )
        XCTAssertTrue(
            plan.readAccessRoot.hasDirectoryPath,
            "读权限根没带「这是目录」那一档 ⇒ 相对地址会把基址当文件，`../x` 多退一级"
        )
    }

    /// **未保存改动不丢**：脏着的时候渲染的是缓冲，而相对路径仍按**文件所在目录**解析。
    func testDirtyBufferIsWhatGetsPreviewed() throws {
        let buffer = "<html><body><h1>还没保存的改动</h1></body></html>"
        guard case let .render(plan) = HTMLPreview.plan(
            path: page.path, isDirty: true, buffer: buffer, facts: facts
        ) else {
            return XCTFail("脏着的时候不给渲染计划 —— 用户看不到自己刚改的东西")
        }
        guard case let .buffer(text, base) = plan.source else {
            return XCTFail("脏着的时候该渲染缓冲，实测渲染的是 \(plan.source)")
        }
        XCTAssertEqual(text, buffer, "预览渲染的不是编辑缓冲（看到的是旧的那份）")
        XCTAssertEqual(
            base.path, root.path,
            "缓冲的基址不是文件所在目录 ⇒ 未保存时相对路径会解析到别处"
        )
    }

    func testMissingOrDirectoryOrRootedFileIsRefusedWithAReadableReason() throws {
        // 还没落盘
        if case .block(let reason) = HTMLPreview.plan(path: nil, isDirty: true, buffer: "<p>x", facts: facts) {
            XCTAssertFalse(reason.isEmpty, "拒绝时没有给一句可读的理由")
            XCTAssertEqual(
                reason, LocalizedStrings.text(.htmlPreviewNeedsSavedFile, language: .simplifiedChinese),
                "拒绝理由不是「先保存一次」那一句（Core 那几档文案按调用方给的语言出）"
            )
        } else {
            XCTFail("没有磁盘路径却给了渲染计划")
        }
        // 文件不在
        if case .block(let reason) = HTMLPreview.plan(
            path: page.path, isDirty: false, buffer: "", facts: .init(exists: false, isDirectory: false)
        ) {
            XCTAssertEqual(
                reason, LocalizedStrings.text(.htmlPreviewFileMissing, language: .simplifiedChinese),
                "文件不在了，说的不是那一句"
            )
        } else {
            XCTFail("文件不在却给了渲染计划")
        }
        // 是个目录
        if case .block(let reason) = HTMLPreview.plan(
            path: page.path, isDirty: false, buffer: "", facts: .init(exists: true, isDirectory: true)
        ) {
            XCTAssertEqual(
                reason, LocalizedStrings.text(.htmlPreviewPathIsDirectory, language: .simplifiedChinese),
                "目录，说的不是那一句"
            )
        } else {
            XCTFail("目录却给了渲染计划")
        }
        // 磁盘根之下：读权限根会变成 `/`（= 把整机交给页面里的脚本）
        if case .block(let reason) = HTMLPreview.plan(
            path: "/probe-root.html", isDirty: false, buffer: "", facts: .init(exists: true, isDirectory: false)
        ) {
            XCTAssertEqual(
                reason, LocalizedStrings.text(.htmlPreviewRootDirectoryRefused, language: .simplifiedChinese),
                "磁盘根这一档说的不是那一句"
            )
        } else {
            XCTFail("文件落在磁盘根下却给了渲染计划 —— 读权限根 = `/`，页面里的脚本能读整台机器")
        }
    }

    // MARK: - ② 相对路径按文件所在目录解析；越界 / 远程给可读理由或交浏览器页签

    func testRelativeResourcesResolveNextToTheFile() throws {
        for link in ["style.css", "./style.css", "img/pic.png", "sub/../style.css"] {
            XCTAssertEqual(
                HTMLPreview.decide(link: link, baseDirectory: root),
                .allow,
                "同目录的资源 `\(link)` 被拒绝了 ⇒ 预览渲染出来是裸文档"
            )
        }
        // 片段与内联数据留在本文档里，不算出网。
        XCTAssertEqual(HTMLPreview.decide(link: "#anchor", baseDirectory: root), .allow)
        XCTAssertEqual(HTMLPreview.decide(link: "data:text/plain,hi", baseDirectory: root), .allow)
    }

    func testOutsideAndRemoteTargetsSayWhy() throws {
        // 越界：读权限根之外
        let outside = HTMLPreview.decide(link: "../outside.txt", baseDirectory: root)
        guard case let .block(reason) = outside else {
            return XCTFail("落在读权限根之外的资源被放行了：\(outside) —— 页面能读整台机器")
        }
        XCTAssertTrue(reason.contains("outside.txt"), "拒绝时没说清是哪一条被拒：\(reason)")

        // 远程：预览不加载，但给一条能走的路（交浏览器页签）
        let remote = HTMLPreview.decide(link: "https://example.com/away", baseDirectory: root)
        guard case let .handOffToBrowser(reason) = remote else {
            return XCTFail("远程地址的裁决不是「交给浏览器页签」：\(remote)")
        }
        XCTAssertTrue(
            reason.contains("https://example.com/away"),
            "给的理由没带上那个地址：\(reason)"
        )
        XCTAssertFalse(remote.isAllowed, "远程地址在预览里被放行了（预览不该自己出网）")
    }

    // MARK: - ③ 真视图：与浏览器页签同一个引擎，读权限落到那个目录

    @MainActor
    func testPreviewViewRunsOnTheSameEngineAsBrowserTabs() throws {
        let host = UISnapshot.LiveHost(
            HTMLPreviewView(tabID: UUID(), path: page.path, isDirty: false, content: "",
                            onOpenInBrowser: { _ in }),
            size: CGSize(width: 700, height: 420)
        )
        host.pump(1.2)

        let webView = try XCTUnwrap(
            UISnapshot.LiveHost<Never>.findViews(ofType: WKWebView.self, in: host.hosting).first,
            "预览的视图树里没有 WKWebView —— 页面根本没被渲染（或者用了别的渲染器）"
        )
        let engine = try XCTUnwrap(
            webView.navigationDelegate as? WebKitBrowserEngine,
            "预览里那枚 WKWebView 的导航代理不是浏览器页签用的 `WebKitBrowserEngine`"
                + "（策略 / 外发留痕 / 本机读权限会变成第二份实现）"
        )
        XCTAssertTrue(
            engine.view === webView,
            "视图树里那枚 WKWebView 不是引擎自己的 view ⇒ 判出来的引擎不是真正在渲染的那一枚"
        )
        XCTAssertEqual(
            engine.localReadRoot?.path, root.path,
            "引擎的读权限根不是文件所在目录 ⇒ 同目录资源会被拒（页面渲染成裸文档）"
        )
    }

    /// 打不开的路径：视图里**没有**引擎，只有一句可读的理由（不给一张空白页冒充「渲染好了」）。
    @MainActor
    func testBlockedPathRendersAReasonInsteadOfAnEngine() throws {
        let missing = root.appendingPathComponent("nope.html")
        let host = UISnapshot.LiveHost(
            HTMLPreviewView(tabID: UUID(), path: missing.path, isDirty: false, content: "",
                            onOpenInBrowser: { _ in }),
            size: CGSize(width: 700, height: 260)
        )
        host.pump(0.8)
        let webViews = UISnapshot.LiveHost<Never>.findViews(ofType: WKWebView.self, in: host.hosting)
        XCTAssertTrue(
            webViews.isEmpty,
            "文件不在了还建了引擎（空白页会让用户以为「这个文件是空的」）"
        )
    }

    // MARK: - ④ 源码与预览互不覆盖：同一份文件，两条路，谁都不改谁

    @MainActor
    func testSourceAndPreviewNeverOverwriteEachOther() throws {
        let tabs = makeTabs()
        // 双击 .html 走的是**浏览器页签**那条路（这条口径没变）—— 注入一个假的接收端把它记下来。
        var handed: [URL] = []
        tabs.openInBrowserTab = { handed.append($0) }
        tabs.openFile(at: page)
        XCTAssertEqual(handed, [page], ".html 双击没有交给浏览器页签（语言登记表那条口径变了）")

        // 想改源码走「以源码打开」：进编辑器，且**真的能改**。
        tabs.openAsSource(at: page)
        let tab = try XCTUnwrap(
            tabs.tabs.first { $0.path == page.path },
            "以源码打开之后没有这一页 —— 「一键切回源码」没有落脚点"
        )
        XCTAssertTrue(
            tabs.supportsWebPagePreview(path: page.path),
            "这份文件在语言登记表里不是网页 ⇒ 状态栏不会给预览开关"
        )
        let source = tab.content
        XCTAssertTrue(source.contains("<h1>标题</h1>"), "以源码打开拿到的不是这份 html")

        // 切到预览（状态栏那枚开关打的就是它）：正文与脏标记都不许动。
        let previewBefore = tabs.previewVisible
        tabs.togglePreview()
        XCTAssertNotEqual(tabs.previewVisible, previewBefore, "预览开关没有翻动")
        let afterToggle = try XCTUnwrap(tabs.tabs.first { $0.path == page.path })
        XCTAssertEqual(afterToggle.content, source, "切到预览把源码改了（两面互相覆盖）")
        XCTAssertFalse(afterToggle.isDirty, "只是切了一下预览，页签却变脏了")

        // 改一个字：内容与脏标记都在源码那一侧，预览读的是它。
        let edited = source.replacingOccurrences(of: "标题", with: "改过的标题")
        tabs.updateContent(edited, for: tab.id)
        let dirty = try XCTUnwrap(tabs.tabs.first { $0.path == page.path })
        XCTAssertTrue(dirty.isDirty, "改了正文却没有未保存标记")
        guard case let .render(plan) = HTMLPreview.plan(
            path: dirty.path, isDirty: dirty.isDirty, buffer: dirty.content, facts: facts
        ) else {
            return XCTFail("脏着的时候不给预览计划")
        }
        XCTAssertEqual(
            plan.source, .buffer(text: edited, baseDirectory: plan.readAccessRoot),
            "预览没有跟着显示未保存的那份（用户会以为预览没跟上）"
        )

        // 保存：盘上换成新的一份，预览随之改读盘上那份（**不是**反过来）。
        XCTAssertTrue(tabs.save(tab.id), "保存失败（临时目录里不该失败）")
        let saved = try XCTUnwrap(tabs.tabs.first { $0.path == page.path })
        XCTAssertFalse(saved.isDirty, "保存之后还是脏的")
        XCTAssertEqual(
            try String(contentsOf: page, encoding: .utf8), edited,
            "保存之后盘上的 html 与编辑器里那一份不一致"
        )
        guard case let .render(savedPlan) = HTMLPreview.plan(
            path: saved.path, isDirty: saved.isDirty, buffer: saved.content, facts: facts
        ) else {
            return XCTFail("保存之后不给预览计划")
        }
        XCTAssertEqual(
            savedPlan.source, .file(page),
            "保存之后预览仍渲染缓冲（应当改回读盘上那份）"
        )
    }
}
