import XCTest

/// `FR-STD-WS-FS-003` 的**源树判据**：拖拽移动与「在终端中打开」必须真的接到界面上。
///
/// ## 为什么要有这一条
///
/// Core 侧（`WorkspaceFileMove` / `WorkspaceTerminalOpen` / `WorkspaceFileOperations.move`）
/// 全绿只说明「算得对、搬得动」；如果 `WorkspaceTreeRow` 没挂 `.onDrag` / `.dropDestination`、
/// 右键菜单没长出「在终端中打开」，产品侧就还是**拖不动、点不到** —— 而 Core 判据一条都不会红。
/// 同族教训见 `Tests/DialogButtonSourceTests`、`Tests/MarkdownPreviewFollowSourceTests`。
final class WorkspaceFileMoveSourceTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let url = root.appendingPathComponent(relative)
        let body = try String(contentsOf: url, encoding: .utf8)
        // 空跑防护：读到的必须真是那份文件，不是空壳。
        XCTAssertGreaterThan(body.count, 4000, "\(relative) 读到的内容太短，扫描面可疑")
        return body
    }

    /// 行视图：拖得动（`.onDrag` 载荷是相对路径）+ 只有目录行接落点 + 右键多出「在终端中打开」。
    func testRowIsDraggableAndOnlyDirectoriesAcceptDrops() throws {
        let body = try text("App/Views/WorkspaceExplorerView.swift")
        for anchor in [
            ".onDrag {",
            "NSItemProvider(object: entry.relativePath as NSString)",
            ".dropDestination(for: String.self)",
            "guard entry.isDirectory, let first = items.first else { return false }",
            "return onDropInto(first)",
            "isDropTargeted = entry.isDirectory && targeted",
            "Button(L(.workspaceOpenInTerminal)) { onOpenInTerminal() }",
            "Button(L(.workspaceReveal)) { onReveal() }"
        ] {
            XCTAssertTrue(body.contains(anchor), "行视图缺少拖拽 / 菜单锚点：\(anchor)")
        }
        // 反向：拖拽不许走剪贴板那套老路（`NSPasteboard` 与文件 URL 载荷在这里都是错的入口）。
        XCTAssertFalse(body.contains("NSPasteboard"), "行内拖拽不许绕道剪贴板")
    }

    /// 父视图：行的落点接回 store（**搬成功后页签要跟着走**），落到工作区根那一行也要有落点。
    func testViewWiresDropsToTheStore() throws {
        let body = try text("App/Views/WorkspaceExplorerView.swift")
        for anchor in [
            "let outcome = workspace.move(sourcePath, into: entry.relativePath)",
            "workspaceTabs.retarget(from: from.path, to: to.path)",
            "return outcome.accepted",
            "onOpenInTerminal: { workspace.openInTerminal(entry) }",
            "let outcome = workspace.move(first, into: \"\")",
            "isRootDropTargeted"
        ] {
            XCTAssertTrue(body.contains(anchor), "父视图缺少接线锚点：\(anchor)")
        }
    }

    /// store：判定只走 `WorkspaceFileMove.placement` 一处，落地要记撤销；终端要真跑计划。
    func testStoreUsesOneDecisionAndRunsTheTerminalPlan() throws {
        let body = try text("App/WorkspaceStore.swift")
        for anchor in [
            "func move(_ sourcePath: String, into directoryPath: String) -> MoveOutcome",
            "switch WorkspaceFileMove.placement(source: sourcePath, into: directoryPath)",
            "undoLog.record(.move(from: source, to: moved, workspace: rootURL))",
            "func openInTerminal(",
            "process.executableURL = URL(fileURLWithPath: plan.tool)",
            "process.arguments = plan.arguments"
        ] {
            XCTAssertTrue(body.contains(anchor), "store 缺少锚点：\(anchor)")
        }
        // 反向：不许自己另写一套几何判定（`hasPrefix` 那条老写法会把 `ab` 当成 `a` 的子树）。
        XCTAssertFalse(
            body.contains("relativePath.hasPrefix(directoryPath)"),
            "子树判定不许在 store 里手写一份"
        )
    }
}
