import XCTest

/// `FR-STD-WS-WEB-002` 的**源树判据**：预览的跟随滚动必须走 `Core/MarkdownPreviewFollow`
/// 这一处状态面，并且**换页签时必须真的激活**。
///
/// ## 为什么要有这一条
///
/// 2026-10-29 之前这件模型只存一个 `Int`（`@Published private(set) var line = 1`），
/// `report` 直接把外部报来的值赋进去。那时代码读起来完全正常、单看也「能跟随」——
/// 缺的是**页签身份**，而这件东西**不写就不会有**：`Tests/MarkdownPreviewFollowTests`
/// 判的是核心层，若视图侧没人调 `activate`，那 11 条判据全绿而产品照旧串行号。
/// 同族教训见 `Tests/DialogButtonSourceTests`（口径进了 Core、视图不接线 = 死代码）。
final class MarkdownPreviewFollowSourceTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let url = root.appendingPathComponent(relative)
        let body = try String(contentsOf: url, encoding: .utf8)
        // 空跑防护：读到的必须真是那两个文件，不是空壳。
        XCTAssertGreaterThan(body.count, 4000, "\(relative) 读到的内容太短，扫描面可疑")
        return body
    }

    /// 模型不许自己算行号：三个入口都要转给核心层。
    func testCursorModelDelegatesToCoreState() throws {
        let body = try text("App/Views/MarkdownPreviewView.swift")
        for anchor in [
            "private var follow = MarkdownPreviewFollow()",
            "follow.activate(tab)",
            "follow.report(line: reported, tab: tab)",
            "follow.retain(Set(tabs))"
        ] {
            XCTAssertTrue(body.contains(anchor), "模型缺少核心层接线锚点：\(anchor)")
        }
        // 反向：旧写法（把外部报来的值直接赋值给发布属性）不许回来。
        XCTAssertFalse(body.contains("self.line = line"), "报来的行号不许绕过核心层直接赋值")
    }

    /// 视图侧：换页签 / 关页签 / 首次出现三条路都要同步，且同步里既有激活也有收；
    /// 光标报数要**带页签身份**（否则那次报数记不到任何页签名下）。
    func testWorkspaceAreaActivatesOnTabChange() throws {
        let body = try text("App/Views/WorkspaceAreaView.swift")
        for anchor in [
            ".onAppear { syncPreviewCursor() }",
            ".onChange(of: tabs.selectedID)",
            ".onChange(of: tabs.tabs.map(\\.id))",
            "previewCursor.retain(tabs: tabs.tabs.map(\\.id))",
            "previewCursor.activate(tab: id)",
            "previewCursor.report(line: line, tab: tab.id)"
        ] {
            XCTAssertTrue(body.contains(anchor), "视图缺少页签同步锚点：\(anchor)")
        }
    }

    /// 预览读的仍然是模型发布的那个行号（不是自己另存一份）。
    func testPreviewReadsThePublishedLine() throws {
        let body = try text("App/Views/MarkdownPreviewView.swift")
        XCTAssertTrue(body.contains("onChange(of: cursor.line)"), "预览要跟着模型发布的行走")
        XCTAssertTrue(body.contains("scroll(proxy, toSourceLine: cursor.line)"), "滚动落点仍取模型那一行")
    }
}
