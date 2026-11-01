import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **工作区新建文件（`FR-STD-WS-FS-004`）与重命名（`FR-STD-WS-FS-005`）的 App 内行为探针**。
///
/// ## 判什么（需求验收原文拆成可读的读数）
///
/// `FS-004` 新建文件：
///   ① 落在**选中的那个目录**下、**输入名即建**（改名框里敲的名字就是盘上的名字）；
///   ② 重名**要提示**，既不静默覆盖、也不静默顺延成一个自造的名字；
///   ③ 新建之后**自动打开且光标在首行**（`openFile(at:line:1)` 投递的第 1 行）。
///
/// `FS-005` 重命名：
///   ① 文件与目录**就地**改名（旧名不留在盘上、内容不动）；
///   ② 已打开的页签**路径与标题跟着改**、**脏内容不动**、页签标识不重发；
///   ③ 目录改名**整棵子树跟着改**；
///   ④ `a.txt2` 不被 `a.txt` 的改名**误伤**；
///   ⑤ 改名**可撤销**；旧名被占时**拒绝撤销**（不覆盖别人的新文件、账不落空）。
///
/// ## 怎么判（为什么是这一套）
///
/// · 走**真入口**：`WorkspaceStore.choose/createEntry/rename/undoLastFileOperation`，
///   以及 `WorkspaceExplorerView` 里那两段动作（`createEntry(in:asFile:)` / `commitRename(_:)`）
///   —— 逐行照抄在 `WorkspaceFileProbeKit` 里，含「建完就开页签落第 1 行」「改完页签跟着走」；
/// · 断言落在**真实磁盘**上：`FileManager` 读回来的名字集合、字节内容、文件在不在；
///   再对**模型状态**（页签路径 / 标题 / 脏内容 / 撤销账）；
/// · **不用 mock 文件系统**，也**不比对源码字符串** —— 后者在这两条需求上尤其会假绿
///   （「盘上真的换了名字」与「源码里写了 rename」是两件事）。
///
/// ## 反证记录（2026-11-01：改坏一处产品代码 → 红 → 逐字节还原 → 绿）
///
/// · `WorkspaceStore.createEntry(in:asFile:)` 的落点由「选中目录」换成「工作区根」⇒
///   本文件 10 处红（含「新建的文件没有落在**选中的那个目录**里」），还原后 8/8 绿；
/// · `WorkspaceTabsModel.openFile(at:line:)` 不再投递 `revealDelivery` ⇒
///   「打开之后没有投递「落在第几行」」红（单跑该例），还原后绿；
/// · `WorkspaceTabSet.retargetedPath` 的前缀比较去掉分隔符 ⇒ `a.txt2` 那条页签的路径被改成
///   `b.txt/2`（本文件的「被误伤」两条红），同时目录改名那条读出 `源码//deep/inner.txt`，
///   还原后绿。
///
/// ## 边界（如实登记，别当已验）
///
/// · 不判**界面上的像素**：改名框在不在行里、图标对不对齐，归 `RowActionRevealProbeTests` 那一族；
/// · 「光标在首行」判的是**投递**（`revealDelivery.line == 1`）—— 编辑器真把插入点摆在第 1 行
///   的几何读数在 `WorkspaceSessionCursorProbeTests`；这里不重复量像素；
/// · 视图那两段动作（建完就开页签落第 1 行 / 改完页签跟着走）住在 `WorkspaceExplorerView` 的
///   **私有方法**里，右键与菜单项又点不动（SwiftUI 手势不吃合成事件）⇒ 探针里是 `WorkspaceFileProbeKit`
///   的**逐行照抄件**；照抄件与产线之间的漂移本文件盯不到（那一半由既有的源码锚点用例守着，
///   本文件不重复）；
/// · 不碰用户数据：夹具是临时目录（含临时书签表），跑完删。
final class WorkspaceFileCreateRenameProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    // MARK: - 夹具

    /// 一个临时工作区：`src/`（含 `notes.txt` 与 `deep/inner.txt`）、`docs/`、`a.txt`、`a.txt2`。
    private func makeScratch(_ label: String) throws -> WorkspaceFileProbeKit.Scratch {
        let scratch = try WorkspaceFileProbeKit.Scratch(label)
        try scratch.write("原正文\n", at: "src/notes.txt")
        try scratch.write("深处\n", at: "src/deep/inner.txt")
        try scratch.write("文档\n", at: "docs/readme.md")
        try scratch.write("第一个\n", at: "a.txt")
        try scratch.write("第二个\n", at: "a.txt2")
        return scratch
    }

    // MARK: - FR-STD-WS-FS-004 ① 落地位置 + ③ 自动打开、光标在首行

    @MainActor
    func testNewFileLandsInTheSelectedDirectoryAndOpensOnTheFirstLine() async throws {
        let scratch = try makeScratch("fs-004a")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let src = try WorkspaceFileProbeKit.entry("src", in: scratch.root)
        let before = Set(try scratch.names(in: "src"))

        let created = try XCTUnwrap(
            WorkspaceFileProbeKit.createLikeTheView(in: src, store: store, tabs: tabs),
            "「新建文件」什么都没建出来（notice=\(store.noticeText ?? "nil")）—— 界面上就是点了没反应"
        )

        XCTAssertEqual(
            created.deletingLastPathComponent().standardizedFileURL.path,
            scratch.url("src").standardizedFileURL.path,
            "新建的文件没有落在**选中的那个目录**里，而是 \(created.path)"
        )
        let added = Set(try scratch.names(in: "src")).subtracting(before)
        XCTAssertEqual(
            added,
            [created.lastPathComponent],
            "选中目录里多出来的应当恰好是新建的那一个（实测 \(added)）"
        )
        XCTAssertEqual(
            try scratch.text(at: "src/\(created.lastPathComponent)"), "",
            "新建的文件必须是空的 —— 里面有字就等于替用户编了内容"
        )

        // ③ 自动打开且光标在首行
        let tab = try XCTUnwrap(
            tabs.tabs.first { $0.path == created.path },
            "新建的文件没有自动打开（页签集合里没有它）"
        )
        XCTAssertEqual(tabs.selectedID, tab.id, "新建之后切过去的不是这一页（用户还得自己找一遍）")
        let delivery = try XCTUnwrap(
            tabs.revealDelivery,
            "打开之后没有投递「落在第几行」⇒ 光标停在哪儿只能靠猜"
        )
        XCTAssertEqual(delivery.tabID, tab.id, "「落在第 1 行」投递给了另一页")
        XCTAssertEqual(delivery.line, 1, "光标应当落在第 1 行，实际投递的是第 \(delivery.line) 行")
    }

    // MARK: - FR-STD-WS-FS-004 ①「输入名即建」

    @MainActor
    func testTypedNameIsTheNameOnDisk() async throws {
        let scratch = try makeScratch("fs-004b")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let src = try WorkspaceFileProbeKit.entry("src", in: scratch.root)

        let created = try XCTUnwrap(
            WorkspaceFileProbeKit.createLikeTheView(in: src, store: store, tabs: tabs),
            "「新建文件」没建出东西（notice=\(store.noticeText ?? "nil")）"
        )
        XCTAssertEqual(
            store.renamingPath,
            "src/\(created.lastPathComponent)",
            "新建之后没有进改名态 —— 「输入名即建」就没有那个输入框"
        )

        let fresh = try WorkspaceFileProbeKit.entry("src/\(created.lastPathComponent)", in: scratch.root)
        let renamed = try XCTUnwrap(
            WorkspaceFileProbeKit.commitRename(fresh, to: "接口说明.md", store: store, tabs: tabs),
            "在改名框里敲了名字却提交不动（notice=\(store.noticeText ?? "nil")）"
        )

        XCTAssertEqual(renamed.lastPathComponent, "接口说明.md", "落盘的名字不是敲进去的那个")
        XCTAssertTrue(scratch.exists("src/接口说明.md"), "盘上没有 `src/接口说明.md`")
        XCTAssertFalse(
            scratch.exists("src/\(created.lastPathComponent)"),
            "改成新名之后默认名还留在盘上 —— 用户会看到两个文件"
        )
        let tab = try XCTUnwrap(tabs.tabs.first { $0.path == renamed.path }, "页签没跟着新名字走")
        XCTAssertEqual(tab.title, "接口说明.md", "页签标题没有跟着输入的名字改")
    }

    // MARK: - FR-STD-WS-FS-004 ② 重名要提示（不静默覆盖 / 不静默顺延）

    @MainActor
    func testDuplicateNameIsReportedAndNothingIsOverwritten() async throws {
        let scratch = try makeScratch("fs-004c")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let src = try WorkspaceFileProbeKit.entry("src", in: scratch.root)
        let before = Set(try scratch.names(in: "src"))

        let created = try XCTUnwrap(
            WorkspaceFileProbeKit.createLikeTheView(in: src, store: store, tabs: tabs),
            "「新建文件」没建出东西（notice=\(store.noticeText ?? "nil")）"
        )
        let fresh = try WorkspaceFileProbeKit.entry("src/\(created.lastPathComponent)", in: scratch.root)

        // 改成一个已经存在的名字（`src/notes.txt` 就在那儿）。
        let renamed = WorkspaceFileProbeKit.commitRename(fresh, to: "notes.txt", store: store, tabs: tabs)

        XCTAssertNil(renamed, "撞名居然改成功了 —— 那是覆盖或顺延，需求要求**提示**")
        XCTAssertEqual(
            try scratch.text(at: "src/notes.txt"), "原正文\n",
            "撞名时把原来那个文件覆盖了 —— 这是丢数据，不是提示"
        )
        let after = Set(try scratch.names(in: "src"))
        XCTAssertEqual(
            after,
            before.union([created.lastPathComponent]),
            "撞名之后盘上多出了别的东西（\(after)）—— 不许静默顺延成一个自造的名字"
        )
        let notice = try XCTUnwrap(store.noticeText, "撞名没有任何提示（静默失败）")
        XCTAssertTrue(notice.contains("notes.txt"), "提示里没说清是哪个名字撞了：\(notice)")
        XCTAssertEqual(
            store.renamingPath,
            "src/\(created.lastPathComponent)",
            "失败之后把改名框收掉了 —— 用户刚敲的字就这么没了"
        )
    }

    // MARK: - FR-STD-WS-FS-005 ①② 文件就地改名 + 页签跟改 + 脏内容不动

    @MainActor
    func testRenameKeepsTheOpenTabRetargetedWithItsDirtyContent() async throws {
        let scratch = try makeScratch("fs-005a")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let notes = try WorkspaceFileProbeKit.entry("src/notes.txt", in: scratch.root)

        tabs.openFile(at: scratch.url("src/notes.txt"))
        let opened = try XCTUnwrap(tabs.tabs.first { $0.path == scratch.url("src/notes.txt").path })
        tabs.updateContent("未保存的改动\n", for: opened.id)
        let dirtyTab = try XCTUnwrap(tabs.tabs.first { $0.id == opened.id })

        let renamed = try XCTUnwrap(
            WorkspaceFileProbeKit.commitRename(notes, to: "报告.md", store: store, tabs: tabs),
            "改名失败（notice=\(store.noticeText ?? "nil")）"
        )

        XCTAssertFalse(scratch.exists("src/notes.txt"), "「就地改名」之后旧名字不该还在盘上")
        XCTAssertEqual(
            try scratch.text(at: "src/报告.md"), "原正文\n",
            "改名把盘上那份内容也改了 —— 改名只该动名字"
        )

        let after = try XCTUnwrap(
            tabs.tabs.first { $0.id == opened.id },
            "改名把页签弄丢了 —— 应当是就地改写，不是关掉再开"
        )
        XCTAssertEqual(
            after.path, renamed.path,
            "页签路径没跟着改 —— 这时按 ⌘S 会写回一个已经不存在的旧路径"
        )
        XCTAssertEqual(after.title, "报告.md", "页签标题没跟着改")
        XCTAssertEqual(after.content, "未保存的改动\n", "改名把用户没保存的改动冲掉了")
        XCTAssertTrue(after.isDirty, "改完之后脏标记丢了 —— 关页签时就不会再问一句")
        XCTAssertEqual(
            tabs.tabs.filter { $0.path == renamed.path }.count, 1,
            "改名之后出现了两页指向同一文件"
        )

        // 路径真的指对了：保存应当写进新名字那个文件。
        XCTAssertTrue(tabs.save(opened.id), "改名之后保存失败（notice=\(tabs.errorText ?? "nil")）")
        XCTAssertEqual(try scratch.text(at: "src/报告.md"), "未保存的改动\n", "保存没有写到新路径上")
    }

    // MARK: - FR-STD-WS-FS-005 ③ 目录改名：整棵子树跟着走

    @MainActor
    func testRenameDirectoryRetargetsTheWholeSubtree() async throws {
        let scratch = try makeScratch("fs-005b")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let src = try WorkspaceFileProbeKit.entry("src", in: scratch.root)

        tabs.openFile(at: scratch.url("src/notes.txt"))
        tabs.openFile(at: scratch.url("src/deep/inner.txt"))
        let deepTab = try XCTUnwrap(tabs.tabs.first { $0.path == scratch.url("src/deep/inner.txt").path })
        tabs.updateContent("深改\n", for: deepTab.id)

        let renamed = try XCTUnwrap(
            WorkspaceFileProbeKit.commitRename(src, to: "源码", store: store, tabs: tabs),
            "目录改名失败（notice=\(store.noticeText ?? "nil")）"
        )

        XCTAssertFalse(scratch.exists("src"), "目录改名之后旧名字还在")
        XCTAssertTrue(scratch.exists("源码/notes.txt"), "子树里的文件没跟着搬过去")
        XCTAssertTrue(scratch.exists("源码/deep/inner.txt"), "第二层子目录没跟着搬过去")
        XCTAssertEqual(
            try scratch.text(at: "源码/deep/inner.txt"), "深处\n",
            "搬过去的那份内容不对（盘上那份没被页签里的脏内容污染）"
        )

        let second = try XCTUnwrap(
            tabs.tabs.first { $0.id == deepTab.id },
            "目录改名把子树里的页签弄丢了"
        )
        XCTAssertEqual(second.path, renamed.path + "/deep/inner.txt", "子树里的页签路径没跟着改")
        XCTAssertEqual(second.title, "inner.txt", "页签标题不该变（文件名没变）")
        XCTAssertEqual(second.content, "深改\n", "目录改名把子树里那页的脏内容冲掉了")
        XCTAssertTrue(second.isDirty)
        XCTAssertTrue(
            tabs.tabs.contains { $0.path == renamed.path + "/notes.txt" },
            "同一层那个文件的页签路径没跟着改"
        )
    }

    // MARK: - FR-STD-WS-FS-005 ④ `a.txt2` 不被 `a.txt` 误伤

    @MainActor
    func testRenameDoesNotTouchTheLookalikeFile() async throws {
        let scratch = try makeScratch("fs-005c")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let first = try WorkspaceFileProbeKit.entry("a.txt", in: scratch.root)

        tabs.openFile(at: scratch.url("a.txt"))
        tabs.openFile(at: scratch.url("a.txt2"))
        let lookalike = try XCTUnwrap(tabs.tabs.first { $0.path == scratch.url("a.txt2").path })

        _ = try XCTUnwrap(
            WorkspaceFileProbeKit.commitRename(first, to: "b.txt", store: store, tabs: tabs),
            "改名失败（notice=\(store.noticeText ?? "nil")）"
        )

        XCTAssertTrue(scratch.exists("a.txt2"), "改 `a.txt` 把 `a.txt2` 一起搬走了（前缀比较少了分隔符）")
        XCTAssertEqual(try scratch.text(at: "a.txt2"), "第二个\n", "`a.txt2` 的内容被改了")
        let after = try XCTUnwrap(tabs.tabs.first { $0.id == lookalike.id })
        XCTAssertEqual(after.path, scratch.url("a.txt2").path, "`a.txt2` 那条页签的路径被误伤")
        XCTAssertEqual(after.title, "a.txt2", "`a.txt2` 那条页签的标题被误伤")
    }

    // MARK: - FR-STD-WS-FS-005 ⑤ 改名可撤销

    @MainActor
    func testRenameCanBeUndone() async throws {
        let scratch = try makeScratch("fs-005d")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let first = try WorkspaceFileProbeKit.entry("a.txt", in: scratch.root)

        tabs.openFile(at: scratch.url("a.txt"))
        let opened = try XCTUnwrap(tabs.tabs.first { $0.path == scratch.url("a.txt").path })

        _ = try XCTUnwrap(
            WorkspaceFileProbeKit.commitRename(first, to: "b.txt", store: store, tabs: tabs),
            "改名失败（notice=\(store.noticeText ?? "nil")）"
        )
        XCTAssertTrue(store.canUndoFileOperation, "改完名之后没有可撤销的那一条")

        let undone = try XCTUnwrap(
            WorkspaceFileProbeKit.undoLikeTheView(store: store, tabs: tabs),
            "撤销改名失败（notice=\(store.noticeText ?? "nil")）"
        )
        XCTAssertEqual(undone.kind, .rename, "撤的不是刚才那一次改名")
        XCTAssertTrue(scratch.exists("a.txt"), "撤销之后旧名字没回来")
        XCTAssertEqual(try scratch.text(at: "a.txt"), "第一个\n", "撤销回来的那份内容不对")
        XCTAssertFalse(scratch.exists("b.txt"), "撤销之后新名字还在盘上 —— 那是复制了一份，不是撤回来")
        let after = try XCTUnwrap(tabs.tabs.first { $0.id == opened.id })
        XCTAssertEqual(after.path, scratch.url("a.txt").path, "撤销之后页签路径没跟着回去")
        XCTAssertEqual(after.title, "a.txt", "撤销之后页签标题没跟着回去")
        XCTAssertFalse(
            store.canUndoFileOperation,
            "撤销只有一层：撤完还挂着「撤销」，下一次点它会去撤更早那一下"
        )
    }

    // MARK: - FR-STD-WS-FS-005 ⑤ 旧名被占 ⇒ 拒绝撤销（不覆盖别人的新文件）

    @MainActor
    func testUndoRefusesWhenTheOldNameIsTaken() async throws {
        let scratch = try makeScratch("fs-005e")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let first = try WorkspaceFileProbeKit.entry("a.txt", in: scratch.root)

        _ = try XCTUnwrap(
            WorkspaceFileProbeKit.commitRename(first, to: "b.txt", store: store, tabs: tabs),
            "改名失败（notice=\(store.noticeText ?? "nil")）"
        )
        // 改完名之后，原名字被别人（用户 / 别的程序）重新建了一个。
        try scratch.write("别人的\n", at: "a.txt")

        let undone = WorkspaceFileProbeKit.undoLikeTheView(store: store, tabs: tabs)

        XCTAssertNil(undone, "旧名已被占，撤销居然也报成功 —— 文件被覆盖或被搬到了一个自造的名字下")
        XCTAssertEqual(try scratch.text(at: "a.txt"), "别人的\n", "撤销把别人的新文件覆盖了")
        XCTAssertTrue(scratch.exists("b.txt"), "撤销失败却把改名的那一份搬走了")
        let notice = try XCTUnwrap(store.noticeText, "撤销失败没有任何提示（静默）")
        XCTAssertTrue(notice.contains("a.txt"), "提示里没说清是哪个名字撞了：\(notice)")
        XCTAssertTrue(store.canUndoFileOperation, "撤不回来却把账销了 —— 用户再也没法重试")
    }
}
