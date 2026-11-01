import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **删除走废纸篓、可恢复、根不可删（`FR-STD-WS-FS-006`）的 App 内行为探针**。
///
/// ## 判什么
///
///   ① 删除文件或目录**进废纸篓**（不是直接抹掉）—— 盘上原位置没有了，废纸篓那一份**还在**、
///      内容一字不差；
///   ② **可恢复**：一次撤销把它搬回原处，内容与原来一样；
///   ③ 删除前**显示将影响几个文件**：读数来自 `WorkspaceStore.deletionSummary(for:)`，
///      目录 = 自身 + 递归内容；
///   ④ **根不可删**：`WorkspaceFileOperations.delete(root, in: root)` 抛 `rootNotDeletable`，
///      盘上什么都没少；
///   ⑤ **一次撤销把整棵搬回**（目录里两层都回来）；
///   ⑥ 反例：废纸篓那一份被别人清掉之后，撤销**如实拒绝**，绝不拿别的文件顶上。
///
/// ## 怎么判
///
/// 全部走真入口（`WorkspaceStore.delete` / `undoLastFileOperation`，以及
/// `WorkspaceFileOperations.delete` 这条根判定），断言落在 `FileManager` 的真实结果上：
/// 原位置在不在、废纸篓那一份在不在、字节内容是什么。
/// **不 mock 文件系统**：这一条需求的核心就是"真的进了系统废纸篓"，mock 掉正好把要判的东西替掉了。
///
/// ## 反证记录（2026-11-01：改坏一处产品代码 → 红 → 逐字节还原 → 绿）
///
/// · `WorkspaceFileOperations.delete` 改成 `removeItem` 并去掉「根不可删」守卫 ⇒ 本文件 5 处红
///   （「系统没告诉我们废纸篓里的位置 —— 撤销没有凭据」「工作区根被删掉了」…），还原后绿；
/// · `WorkspaceUndoLog.revert` 的删除档改成「假称撤成功、其实什么都没搬」⇒
///   「废纸篓那一份已经没了，撤销却报成功」红；
/// · `WorkspaceFileOperations.deletionSummary` 让目录一律报 1 项 ⇒「将删几项」那两条红，
///   还原后 5/5 绿。
///
/// ## 边界（如实登记）
///
/// · 「将删几项」这一句**句子**在视图的私有方法里（`deletionMessage(for:)`），探针判的是它读的
///   那个读数（`summary.items`）与分档（文件夹才给数字）；句子本身的长相归人工点验清单；
/// · `truncated`（数到 500 就停）**没有造 501 个文件去验** —— 造那么多文件在 CI 上比这条判据本身
///   更慢，这里只判「没截断时它说 false」；
/// · 不碰用户数据：夹具是临时目录；废纸篓里测试留下的那一份在 `Scratch.remove()` 时清掉。
final class WorkspaceFileTrashUndoProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    /// 夹具：`docs/a.txt`、`docs/b.md`、`docs/sub/c.txt`（目录总共 5 项 = 自身 + 2 + 子目录 + 1）。
    private func makeScratch(_ label: String) throws -> WorkspaceFileProbeKit.Scratch {
        let scratch = try WorkspaceFileProbeKit.Scratch(label)
        try scratch.write("甲\n", at: "docs/a.txt")
        try scratch.write("乙\n", at: "docs/b.md")
        try scratch.write("丙\n", at: "docs/sub/c.txt")
        try scratch.write("随手记\n", at: "single.txt")
        return scratch
    }

    // MARK: - ① ② 文件：进废纸篓 → 一次撤销搬回来

    @MainActor
    func testDeleteFileGoesToTheTrashAndOneUndoBringsItBack() async throws {
        let scratch = try makeScratch("fs-006a")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let entry = try WorkspaceFileProbeKit.entry("single.txt", in: scratch.root)

        XCTAssertEqual(
            store.deletionSummary(for: entry).items, 1,
            "单个文件的「将删几项」应当是 1"
        )
        XCTAssertTrue(store.delete(entry), "删除失败（notice=\(store.noticeText ?? "nil")）")

        XCTAssertFalse(scratch.exists("single.txt"), "删完之后原位置还在")
        let pending = try XCTUnwrap(store.undoLog.pending, "删完之后没有可撤销的账 —— 「可恢复」无从谈起")
        guard case let .deletion(original, trashed, _) = pending else {
            return XCTFail("删完之后记的账不是 `.deletion`，而是 \(pending)")
        }
        XCTAssertEqual(
            original.standardizedFileURL.path, scratch.url("single.txt").standardizedFileURL.path,
            "账上记的原位置不对"
        )
        let trashURL = try XCTUnwrap(trashed, "系统没告诉我们废纸篓里的位置 —— 撤销没有凭据")
        scratch.rememberTrash(trashURL)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: trashURL.path),
            "文件既不在原处也不在废纸篓里（\(trashURL.path)）—— 它是被直接抹掉的，需求要求走废纸篓"
        )
        XCTAssertTrue(
            trashURL.path.lowercased().contains("trash"),
            "它被放到了 \(trashURL.path)，不像是系统的废纸篓"
        )
        XCTAssertEqual(
            try String(contentsOf: trashURL, encoding: .utf8), "随手记\n",
            "废纸篓里那一份内容不对 —— 那不是原来那个文件"
        )

        let undone = try XCTUnwrap(
            WorkspaceFileProbeKit.undoLikeTheView(store: store, tabs: tabs),
            "撤销删除失败（notice=\(store.noticeText ?? "nil")）"
        )
        XCTAssertEqual(undone.kind, .deletion, "撤的不是刚才那一次删除")
        XCTAssertTrue(scratch.exists("single.txt"), "撤销之后文件没有回到原处")
        XCTAssertEqual(try scratch.text(at: "single.txt"), "随手记\n", "搬回来的是空壳 / 内容不对")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: trashURL.path),
            "撤销之后废纸篓里还留着一份 —— 下次再撤会把同一个文件搬两次"
        )
        XCTAssertFalse(store.canUndoFileOperation, "撤销只有一层：撤完账还挂着")
    }

    // MARK: - ③ ⑤ 目录：「将删几项」+ 整棵进废纸篓 + 一次撤销整棵搬回

    @MainActor
    func testDeleteDirectoryCountsItsContentsAndOneUndoRestoresTheWholeTree() async throws {
        let scratch = try makeScratch("fs-006b")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let docs = try WorkspaceFileProbeKit.entry("docs", in: scratch.root)

        let summary = store.deletionSummary(for: docs)
        XCTAssertEqual(
            summary.items, 5,
            "「将删几项」读数是 \(summary.items)；夹具里是 docs 自身 + a.txt + b.md + sub + sub/c.txt = 5"
        )
        XCTAssertFalse(summary.truncated, "这么小的目录不该被标成截断")

        XCTAssertTrue(store.delete(docs), "删除目录失败（notice=\(store.noticeText ?? "nil")）")
        XCTAssertFalse(scratch.exists("docs"), "删完之后目录还在")
        XCTAssertFalse(scratch.exists("docs/sub/c.txt"), "目录里的第二层还留在盘上")

        let pending = try XCTUnwrap(store.undoLog.pending)
        guard case let .deletion(_, trashed, _) = pending else {
            return XCTFail("删目录记的账不是 `.deletion`，而是 \(pending)")
        }
        let trashURL = try XCTUnwrap(trashed, "目录进废纸篓之后系统没给位置")
        scratch.rememberTrash(trashURL)
        XCTAssertTrue(scratch.removedTreeIsIntact(at: trashURL), "废纸篓里那一份不是整棵（缺文件或缺子目录）")

        XCTAssertNotNil(
            WorkspaceFileProbeKit.undoLikeTheView(store: store, tabs: tabs),
            "撤销删除目录失败（notice=\(store.noticeText ?? "nil")）"
        )
        XCTAssertTrue(scratch.exists("docs/a.txt"), "撤销之后第一层的文件没回来")
        XCTAssertTrue(scratch.exists("docs/b.md"), "撤销之后另一个文件没回来")
        XCTAssertTrue(scratch.exists("docs/sub/c.txt"), "撤销之后第二层的文件没回来 —— 只搬回了顶层")
        XCTAssertEqual(try scratch.text(at: "docs/sub/c.txt"), "丙\n", "搬回来的深层文件内容不对")
        XCTAssertEqual(try scratch.text(at: "docs/a.txt"), "甲\n")
    }

    // MARK: - ③ 读数分档：文件 = 1，不存在的 = 0

    @MainActor
    func testDeletionSummaryCountsWhatWillBeAffected() async throws {
        let scratch = try makeScratch("fs-006c")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let file = try WorkspaceFileProbeKit.entry("single.txt", in: scratch.root)
        let empty = try scratch.mkdir("empty")

        XCTAssertEqual(store.deletionSummary(for: file).items, 1)
        let emptyEntry = try WorkspaceFileProbeKit.entry("empty", in: scratch.root)
        XCTAssertEqual(
            store.deletionSummary(for: emptyEntry).items, 1,
            "空目录的「将删几项」= 它自己 1 项（界面上就不该说「及其中的 N 项」）"
        )
        XCTAssertEqual(
            WorkspaceFileOperations.deletionSummary(at: empty.appendingPathComponent("不存在")).items, 0,
            "对一个已经不在的路径报「将删 N 项」等于编数字"
        )
    }

    // MARK: - ④ 根不可删

    @MainActor
    func testWorkspaceRootCannotBeDeleted() async throws {
        let scratch = try makeScratch("fs-006d")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)

        XCTAssertThrowsError(
            try WorkspaceFileOperations.delete(scratch.root, in: scratch.root),
            "工作区根被删掉了（或者删除流程没拦住它）"
        ) { error in
            XCTAssertEqual(
                error as? WorkspaceFileOperations.Failure, .rootNotDeletable,
                "报的不是「工作区根目录不能删」，而是 \(error)"
            )
        }
        XCTAssertTrue(scratch.exists("docs/a.txt"), "拦住报错的同时盘上还是少了东西")
        XCTAssertFalse(store.canUndoFileOperation, "被拦下的删除不该记进撤销账")
    }

    // MARK: - ⑥ 反例：废纸篓那一份没了 ⇒ 撤销如实拒绝

    @MainActor
    func testUndoRefusesWhenTheTrashCopyIsGone() async throws {
        let scratch = try makeScratch("fs-006e")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let entry = try WorkspaceFileProbeKit.entry("single.txt", in: scratch.root)

        XCTAssertTrue(store.delete(entry))
        let pending = try XCTUnwrap(store.undoLog.pending)
        guard case let .deletion(_, trashed, _) = pending else {
            return XCTFail("删完之后记的账不是 `.deletion`，而是 \(pending)")
        }
        let trashURL = try XCTUnwrap(trashed)

        // 用户自己清了废纸篓（或别的程序把它搬走了）。
        try FileManager.default.removeItem(at: trashURL)

        let undone = WorkspaceFileProbeKit.undoLikeTheView(store: store, tabs: tabs)

        XCTAssertNil(undone, "废纸篓那一份已经没了，撤销却报成功 —— 那是拿别处的东西冒充撤销")
        XCTAssertFalse(scratch.exists("single.txt"), "撤销失败却凭空在工作区里造了一个文件")
        let notice = try XCTUnwrap(store.noticeText, "撤销失败没有任何提示（静默）")
        XCTAssertTrue(notice.contains("single.txt"), "提示里没说清是哪一个：\(notice)")
        XCTAssertTrue(store.canUndoFileOperation, "撤不回来却把账销了 —— 用户再也没法重试")
    }
}

// MARK: - 夹具的读数

private extension WorkspaceFileProbeKit.Scratch {

    /// 废纸篓里那一份是不是**整棵**（目录里两层文件都在，内容非空）。
    func removedTreeIsIntact(at trashedDirectory: URL) -> Bool {
        let manager = FileManager.default
        for relative in ["a.txt", "b.md", "sub/c.txt"] {
            let url = trashedDirectory.appendingPathComponent(relative)
            guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return false }
        }
        return manager.fileExists(atPath: trashedDirectory.appendingPathComponent("a.txt").path)
    }
}
