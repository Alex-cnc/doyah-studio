import XCTest
@testable import DoyahCore

/// 网页文件在编辑器内预览的判据（`FR-STD-WS-WEB-003`）。
///
/// 钉四件事（每条都能判红 —— 改坏一处就得红）：
///   ① **读权限根 = 这份文件所在的目录**，不是整机；磁盘根那一档直接不给计划；
///   ② **有未保存改动就渲染缓冲**（看到的就是正在编辑的那份），没有就走盘上文件；
///   ③ 页面里的 `file:` 请求**落在根里才放行**（`/ws` 与 `/ws2` 不许因字符串前缀混成一个根）；
///   ④ 远程地址**不在预览里加载**，但给一条出路（交给浏览器页签），别的协议直接拒。
final class HTMLPreviewTests: XCTestCase {

    private let root = URL(fileURLWithPath: "/tmp/doyah-html-preview/ws")
    private var pagePath: String { root.appendingPathComponent("index.html").path }
    private let facts = HTMLPreview.FileFacts(exists: true, isDirectory: false)

    // MARK: ① 计划：渲染什么、给多少读权限

    func testCleanFileRendersTheFileOnDiskWithItsFolderAsReadRoot() {
        let outcome = HTMLPreview.plan(path: pagePath, isDirty: false, buffer: "<html></html>", facts: facts)

        guard case .render(let plan) = outcome else {
            return XCTFail("干净文件应当给出渲染计划，实际 \(outcome)")
        }
        XCTAssertEqual(plan.source, .file(URL(fileURLWithPath: pagePath)))
        XCTAssertEqual(plan.readAccessRoot.path, root.path, "读权限根必须是这个文件所在的目录（同目录资源要一起读）")
    }

    func testDirtyFileRendersTheBufferButKeepsResolvingRelativePathsAgainstTheFolder() {
        let buffer = "<html><body>未保存的改动</body></html>"
        let outcome = HTMLPreview.plan(path: pagePath, isDirty: true, buffer: buffer, facts: facts)

        guard case .render(let plan) = outcome else {
            return XCTFail("有未保存改动也该能预览，实际 \(outcome)")
        }
        XCTAssertEqual(plan.source, .buffer(text: buffer, baseDirectory: URL(fileURLWithPath: root.path, isDirectory: true)), "看到的应当是正在编辑的那份")
        XCTAssertEqual(plan.readAccessRoot.path, root.path, "渲染缓冲不改变读权限根")
    }

    func testSavedAndDirtyDifferInSourceSoSwitchingDoesNotGoStale() {
        let clean = HTMLPreview.plan(path: pagePath, isDirty: false, buffer: "x", facts: facts)
        let dirty = HTMLPreview.plan(path: pagePath, isDirty: true, buffer: "x", facts: facts)

        XCTAssertNotEqual(clean, dirty, "两种状态必须给出不同的计划，否则预览会停在旧内容上")
    }

    func testUnsavedPageWithoutPathIsRefusedWithAReadableReason() {
        let outcome = HTMLPreview.plan(path: nil, isDirty: true, buffer: "<html></html>", facts: facts)

        guard case .block(let reason) = outcome else {
            return XCTFail("没有路径就不该有渲染计划，实际 \(outcome)")
        }
        XCTAssertEqual(reason, LocalizedStrings.text(.htmlPreviewNeedsSavedFile, language: .simplifiedChinese))
        XCTAssertFalse(reason.isEmpty)
    }

    func testMissingFileAndDirectoryAreRefusedWithDistinctReasons() {
        let missing = HTMLPreview.plan(
            path: pagePath,
            isDirty: false,
            buffer: "",
            facts: .init(exists: false, isDirectory: false)
        )
        let directory = HTMLPreview.plan(
            path: pagePath,
            isDirty: false,
            buffer: "",
            facts: .init(exists: true, isDirectory: true)
        )

        guard case .block(let missingReason) = missing, case .block(let directoryReason) = directory else {
            return XCTFail("文件不存在 / 是目录都该拒绝，实际 \(missing) / \(directory)")
        }
        XCTAssertEqual(missingReason, LocalizedStrings.text(.htmlPreviewFileMissing, language: .simplifiedChinese))
        XCTAssertEqual(directoryReason, LocalizedStrings.text(.htmlPreviewPathIsDirectory, language: .simplifiedChinese))
        XCTAssertNotEqual(missingReason, directoryReason, "两种原因要分开说（用户得知道是哪种）")
    }

    func testPageDirectlyInDiskRootIsRefusedInsteadOfGrantingTheWholeMachine() {
        let outcome = HTMLPreview.plan(path: "/index.html", isDirty: false, buffer: "", facts: facts)

        guard case .block(let reason) = outcome else {
            return XCTFail("磁盘根下的页面不该拿到渲染计划，实际 \(outcome)")
        }
        XCTAssertEqual(reason, LocalizedStrings.text(.htmlPreviewRootDirectoryRefused, language: .simplifiedChinese))
    }

    // MARK: ② 页面里的资源 / 链接

    func testSiblingStyleSheetAndImageAreAllowed() {
        XCTAssertTrue(HTMLPreview.decide(link: "style.css", baseDirectory: root).isAllowed)
        XCTAssertTrue(HTMLPreview.decide(link: "img/logo.png", baseDirectory: root).isAllowed, "子目录也要能读")
        XCTAssertTrue(HTMLPreview.decide(link: "#top", baseDirectory: root).isAllowed, "同文档锚点不发请求")
    }

    func testRelativePathEscapingTheFolderIsRefusedWithAReadableReason() {
        let decision = HTMLPreview.decide(link: "../secret/salary.txt", baseDirectory: root)

        guard case .block(let reason) = decision else {
            return XCTFail("`../` 逃出目录必须被拒，实际 \(decision)")
        }
        XCTAssertTrue(reason.contains("/tmp/doyah-html-preview/secret"), "原因里要写清被拒的是哪个路径：\(reason)")
        XCTAssertFalse(reason.isEmpty)
    }

    func testAbsoluteLocalPathOutsideTheFolderIsRefused() {
        let decision = HTMLPreview.decide(link: "file:///etc/passwd", baseDirectory: root)

        guard case .block(let reason) = decision else {
            return XCTFail("根外的绝对路径必须被拒，实际 \(decision)")
        }
        XCTAssertTrue(reason.contains("/etc/passwd"), "原因要带上被拒的路径：\(reason)")
    }

    func testSiblingFolderWithTheSameNamePrefixIsNotTreatedAsInside() {
        // `/ws` 与 `/ws2` 用 `hasPrefix` 会误判成同一个根 —— 这里钉住分量比较。
        let sibling = URL(fileURLWithPath: "/tmp/doyah-html-preview/ws2/page.html")

        XCTAssertFalse(HTMLPreview.isWithinRoot(sibling, root: root))
        XCTAssertTrue(HTMLPreview.isWithinRoot(root.appendingPathComponent("deep/a.html"), root: root))
    }

    func testRemoteAddressIsNotLoadedInThePreviewButOffersTheBrowserTab() {
        let decision = HTMLPreview.decide(link: "https://example.com/x.png", baseDirectory: root)

        guard case .handOffToBrowser(let reason) = decision else {
            return XCTFail("远程地址应当是「交给浏览器页签」那一档，实际 \(decision)")
        }
        XCTAssertFalse(decision.isAllowed, "预览不许替用户发起远程请求")
        XCTAssertTrue(reason.contains("https://example.com/x.png"), "原因里要带上那个地址：\(reason)")
    }

    func testJavascriptAndOtherSchemesAreRefused() {
        let js = HTMLPreview.decide(link: "javascript:alert(1)", baseDirectory: root)
        XCTAssertFalse(js.isAllowed, "`javascript:` 不许在预览里执行")

        guard case .block = HTMLPreview.decide(link: "ftp://example.com/a", baseDirectory: root) else {
            return XCTFail("未知协议应当被拒")
        }
    }

    func testInlineDataAndBlankPagesHaveNoEgressSoTheyAreAllowed() {
        XCTAssertTrue(HTMLPreview.decide(link: "data:text/plain,hi", baseDirectory: root).isAllowed)
        XCTAssertTrue(
            HTMLPreview.decide(resource: URL(string: "about:blank")!, baseDirectory: root).isAllowed,
            "空白页没有出网，不该记一条拒绝"
        )
    }

    func testEmptyAddressIsRefused() {
        guard case .block(let reason) = HTMLPreview.decide(link: "   ", baseDirectory: root) else {
            return XCTFail("空地址应当被拒")
        }
        XCTAssertEqual(reason, LocalizedStrings.text(.htmlPreviewEmptyAddress, language: .simplifiedChinese))
    }

    func testReasonsFollowTheRequestedLanguage() {
        let english = HTMLPreview.decide(link: "../outside.txt", baseDirectory: root, language: .english)
        guard case .block(let reason) = english else {
            return XCTFail("根外地址在英文语境下同样要拒")
        }
        XCTAssertTrue(reason.contains("outside the directory"), "拒绝理由跟着调用方给的语言走：\(reason)")
    }
}
