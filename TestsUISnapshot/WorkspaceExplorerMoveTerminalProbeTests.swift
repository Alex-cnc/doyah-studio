import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **文件树上的就地操作（`FR-STD-WS-FS-003`）：拖拽移动 + 右键「在终端中打开」的 App 内行为探针**。
///
/// ## 判什么
///
///   ① 拖进另一个目录 ⇒ **真的搬了**（源目录没有它、目标目录有它、内容不变），
///      并且**已打开的页签跟着走**（`WorkspaceTabSet.retargeting`），一次撤销能搬回去；
///   ② 搬进**自己的子树**、搬**工作区根** ⇒ 拒绝并给一句人话（盘上一个字节都不动）；
///   ③ 右键「在终端中打开」给的是 `/usr/bin/open -a Terminal <目录>` 计划：
///      文件开**父目录**、目录开**自己**、路径**原样当一个 argv**（空格 / 引号不拼 shell）；
///      越界相对路径**不给计划**。
///
/// ## 怎么判
///
/// · 移动：真 `WorkspaceStore.move` + `FileManager` 读回的真实结果；
/// · 终端：计划是 `WorkspaceTerminalOpen.plan` 的返回值（**纯函数**，但入参是**真列目录出来的条目**：
///   `relativePath` / `isDirectory` 都来自 `WorkspaceTree.children`）。
///
/// ## 反证记录（2026-11-01：改坏一处产品代码 → 红 → 逐字节还原 → 绿）
///
/// · `WorkspaceFileOperations.move` 改成 `copyItem` ⇒「搬完之后源目录里还在 —— 那是复制，不是移动」红；
/// · `WorkspaceFileMove.placement` 去掉「不能搬进自己里面」⇒「把自己搬进自己里面居然被接下了」红；
/// · `WorkspaceTerminalOpen.directory(for:isDirectory:)` 一律返回它自己 ⇒ 文件那两档计划红
///   （「文件应当开它所在的目录」「父目录路径没有原样传」）。三处一起改坏时本文件 5 处红，还原后 4/4 绿。
///
/// ## 边界（如实登记，这条需求有一半**没有**机器读数）
///
/// · **不真的把 Terminal 拉起来**：合法计划那一路会 `Process.run()` 起 `/usr/bin/open`，
///   在构建机上会闪一个终端窗口；而不合法的计划只有「越界相对路径」一档 ——
///   要喂给它一个越界条目就得自己造 `WorkspaceEntry`，可它的成员初始化是 `internal`（Core 里
///   **没有** `public init`），`@testable` 也够不着另一个模块的 internal。
///   ⇒ 「`WorkspaceStore.openInTerminal` 真的调到了 `WorkspaceTerminalOpen.plan`」这半截
///   **本文件没有判据**（只在产品里读得到、测试里读不到），已在回报里登记；
///   产品若愿意开一个进程启动的注入点（与 `WorkspaceBrowserModel` 的 `egressLog` 同形），
///   这一半就能补上机器读数；
/// · 右键**菜单项**点不动（SwiftUI 手势不吃合成事件，见 `NotesLayoutProbeTests` 头注释），
///   所以「行 → `onOpenInTerminal`」那半截同样归人工点验清单；
/// · 不碰用户数据：夹具是临时目录。
final class WorkspaceExplorerMoveTerminalProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    /// 夹具：`src/notes.txt`、`src/deep/d.txt`、`docs/`（空）、`带 空格 "引号" 的.txt`。
    private func makeScratch(_ label: String) throws -> WorkspaceFileProbeKit.Scratch {
        let scratch = try WorkspaceFileProbeKit.Scratch(label)
        try scratch.write("笔记\n", at: "src/notes.txt")
        try scratch.write("深处\n", at: "src/deep/d.txt")
        try scratch.mkdir("docs")
        try scratch.write("奇怪的名字\n", at: "带 空格 \"引号\" 的.txt")
        return scratch
    }

    // MARK: - ① 拖进另一个目录：真的搬、页签跟着走、一次撤销搬回去

    @MainActor
    func testDropIntoAnotherFolderMovesTheFileAndTheOpenTab() async throws {
        let scratch = try makeScratch("fs-003a")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)

        tabs.openFile(at: scratch.url("src/notes.txt"))
        let opened = try XCTUnwrap(tabs.tabs.first { $0.path == scratch.url("src/notes.txt").path })

        let outcome = WorkspaceFileProbeKit.drop("src/notes.txt", into: "docs", store: store, tabs: tabs)

        XCTAssertTrue(outcome.accepted, "拖进另一个目录被拒绝了（notice=\(store.noticeText ?? "nil")）")
        XCTAssertEqual(outcome.from?.standardizedFileURL.path, scratch.url("src/notes.txt").standardizedFileURL.path)
        XCTAssertEqual(outcome.to?.standardizedFileURL.path, scratch.url("docs/notes.txt").standardizedFileURL.path)
        XCTAssertFalse(scratch.exists("src/notes.txt"), "搬完之后源目录里还在 —— 那是复制，不是移动")
        XCTAssertTrue(scratch.exists("docs/notes.txt"), "目标目录里没有它")
        XCTAssertEqual(try scratch.text(at: "docs/notes.txt"), "笔记\n", "搬过去的那份内容不对")

        let after = try XCTUnwrap(tabs.tabs.first { $0.id == opened.id })
        XCTAssertEqual(after.path, scratch.url("docs/notes.txt").path, "搬完之后页签路径没跟着走")
        XCTAssertEqual(after.title, "notes.txt", "搬完之后页签标题不该变（文件名没变）")
        XCTAssertNotNil(store.noticeText, "搬完了什么都没说 —— 用户不知道它去哪了")

        // 一次撤销搬回去（与界面上那枚撤销同一条路）。
        let undone = try XCTUnwrap(
            WorkspaceFileProbeKit.undoLikeTheView(store: store, tabs: tabs),
            "撤销移动失败（notice=\(store.noticeText ?? "nil")）"
        )
        XCTAssertEqual(undone.kind, .move, "撤的不是刚才那一次移动")
        XCTAssertTrue(scratch.exists("src/notes.txt"), "撤销之后没有回到原目录")
        XCTAssertFalse(scratch.exists("docs/notes.txt"), "撤销之后目标目录里还留着一份")
        let back = try XCTUnwrap(tabs.tabs.first { $0.id == opened.id })
        XCTAssertEqual(back.path, scratch.url("src/notes.txt").path, "撤销移动之后页签路径没跟着回去")
    }

    // MARK: - ② 搬进自己的子树 / 搬根：拒绝且盘上不动

    @MainActor
    func testDropIntoOwnSubtreeIsRefusedWithAMessage() async throws {
        let scratch = try makeScratch("fs-003b")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)

        let outcome = WorkspaceFileProbeKit.drop("src", into: "src/deep", store: store, tabs: tabs)

        XCTAssertFalse(outcome.accepted, "把自己搬进自己里面居然被接下了")
        XCTAssertNil(outcome.from, "被拒绝的拖拽不该给出「从哪搬到哪」")
        XCTAssertTrue(scratch.exists("src/notes.txt"), "被拒绝之后盘上少了东西 —— 搬进自己里面会把整棵弄丢")
        XCTAssertTrue(scratch.exists("src/deep/d.txt"))
        let notice = try XCTUnwrap(store.noticeText, "拒绝时没有任何提示（静默）")
        XCTAssertTrue(notice.contains("src"), "提示里没说清是哪一个条目：\(notice)")
        XCTAssertFalse(store.canUndoFileOperation, "被拒绝的拖拽不该记进撤销账")
    }

    @MainActor
    func testWorkspaceRootCannotBeMoved() async throws {
        let scratch = try makeScratch("fs-003c")
        defer { scratch.remove() }

        XCTAssertThrowsError(
            try WorkspaceFileOperations.move(scratch.root, into: scratch.url("docs"), in: scratch.root),
            "工作区根被搬走了（或者搬根这条路没被挡住）"
        ) { error in
            XCTAssertEqual(
                error as? WorkspaceFileOperations.Failure, .rootNotMovable,
                "报的不是「工作区根目录不能搬」，而是 \(error)"
            )
        }
        XCTAssertTrue(scratch.exists("src/notes.txt"), "被拦下的同时盘上还是少了东西")
        XCTAssertTrue(scratch.exists("docs"), "目标目录被搬没了")
    }

    // MARK: - ③ 终端计划：文件开父目录、目录开自己、路径原样一个 argv

    @MainActor
    func testTerminalPlanForRealTreeEntries() async throws {
        let scratch = try makeScratch("fs-003d")
        defer { scratch.remove() }

        let notes = try WorkspaceFileProbeKit.entry("src/notes.txt", in: scratch.root)
        let srcDir = try WorkspaceFileProbeKit.entry("src", in: scratch.root)

        // 文件 ⇒ 开它**所在的目录**（cd 到文件本身是错的）。
        let filePlan = try XCTUnwrap(
            WorkspaceTerminalOpen.plan(
                relativePath: notes.relativePath, isDirectory: notes.isDirectory, in: scratch.root),
            "普通文件居然给不出终端计划"
        )
        XCTAssertEqual(filePlan.tool, "/usr/bin/open", "不是走 /usr/bin/open（靠 PATH 在 GUI 进程里找不到）")
        XCTAssertEqual(filePlan.arguments, ["-a", "Terminal", scratch.url("src").path],
                       "文件应当开它所在的目录，实际参数是 \(filePlan.arguments)")
        XCTAssertEqual(filePlan.arguments.count, 3, "路径被拆成了多个 argv（自己拼了参数）")

        // 目录 ⇒ 开**它自己**。
        let dirPlan = try XCTUnwrap(
            WorkspaceTerminalOpen.plan(
                relativePath: srcDir.relativePath, isDirectory: srcDir.isDirectory, in: scratch.root)
        )
        XCTAssertEqual(dirPlan.arguments, ["-a", "Terminal", scratch.url("src").path],
                       "目录应当开它自己，实际参数是 \(dirPlan.arguments)")

        // 带空格与引号的文件名 ⇒ 父目录路径**原样**当一个 argv（不拼 shell 引号 / 不截断）。
        let odd = try WorkspaceFileProbeKit.entry("带 空格 \"引号\" 的.txt", in: scratch.root)
        let oddPlan = try XCTUnwrap(
            WorkspaceTerminalOpen.plan(
                relativePath: odd.relativePath, isDirectory: odd.isDirectory, in: scratch.root),
            "带空格与引号的文件名给不出计划"
        )
        XCTAssertEqual(oddPlan.arguments.count, 3, "路径里有空格就被拆成了多个 argv")
        XCTAssertEqual(
            oddPlan.arguments.last, scratch.root.standardizedFileURL.path,
            "父目录路径没有原样传（被改写 / 被加引号 / 被截断）：\(oddPlan.arguments.last ?? "nil")"
        )
        XCTAssertEqual(oddPlan.directoryPath, scratch.root.standardizedFileURL.path)

        // 越界相对路径 ⇒ **不给计划**（不能让 `../..` 把终端开在工作区外面）。
        XCTAssertNil(
            WorkspaceTerminalOpen.plan(relativePath: "../外面", isDirectory: true, in: scratch.root),
            "越界相对路径居然给出了计划 —— 终端会被开到工作区外面"
        )
        XCTAssertNil(
            WorkspaceTerminalOpen.plan(relativePath: "../../外面.txt", isDirectory: false, in: scratch.root),
            "`..` 绕了两层就出了工作区，仍然给出了计划"
        )
        // 工作区根本身是合法目标（计划非空）—— 这一档与上面两档必须分得开。
        XCTAssertNotNil(
            WorkspaceTerminalOpen.plan(relativePath: "", isDirectory: true, in: scratch.root),
            "连工作区根都给不出终端计划 —— 右键根那一行就成了死键"
        )
    }
}
