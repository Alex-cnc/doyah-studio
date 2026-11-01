import AppKit
import CryptoKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **Git 只读与差异**（`FR-STD-WS-VCS-001`）—— 需求 D 的 App 内行为探针。
///
/// ## 为什么必须用真仓库
///
/// 「显示当前分支 / 改动清单 / 逐行差异」这三件事的判定一半在 git、一半在我们自己：
/// `GitWorktreeStatus.parse` 与 `GitUnifiedDiff.parse` 都已由 `Tests/` 的纯文本夹具判过，
/// 但那套判据**不会**发现下面这些（全部编译照过、单测照绿）：
///
///   · 传错了 `-C <root>`（跑在 App 的工作目录上）⇒ 分支与清单是**别的仓库**的；
///   · `loadDiff` 少传 `--` ⇒ 路径以 `-` 开头的文件被当成开关；
///   · 视图直接铺 `hunk.lines`（绕过呈现层）⇒ 折叠 / 按需渲染形同虚设；
///   · 顺手加一个「提交」按钮（需求原话「**不做提交 / 推送**」）。
///
/// 所以本探针在**临时目录里 `git init` 一个真仓库**（造一次提交、改一个文件、再放一个未跟踪文件），
/// 然后判：真 git 读数、真差异行、**读完之后仓库一个字节没变**（`.git/HEAD` / `.git/index` /
/// 工作树文件逐个哈希），以及**真面板里没有任何写操作入口**（含一条对照：同一套扫法看得见
/// 一枚写着「提交并推送」的真按钮）。
///
/// ## 边界（如实登记）
///
/// · 差分内容判到「`GitWorktreeProbe` → `GitUnifiedDiff` → `GitDiffPresentation`」这条链；
///   面板里那些 `Text` 的像素（哪一行画成红 / 绿）不在本轮（SwiftUI `Text` 在离屏宿主里
///   不落 `NSView`，读不到字形；同族实测见 `NotesEditorSaveProbeTests` 文件头）。
/// · 「暂存 / 未暂存两侧」只判到 `loadDiff(staged:)` 的参数真的分了两档（用 git 的真实读数）。
final class GitReadOnlyProbeTests: XCTestCase {

    private var repo: URL!
    private var changedFile: URL!
    private var untrackedFile: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
        repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitReadOnlyProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        changedFile = repo.appendingPathComponent("a.txt")
        untrackedFile = repo.appendingPathComponent("b.txt")

        // 夹具：一次真提交 + 一次真改动 + 一个未跟踪文件。
        _ = try git(["init", "-b", "probe-read-only"])
        try "第一行\n第二行\n".write(to: changedFile, atomically: true, encoding: .utf8)
        _ = try git(["add", "a.txt"])
        let commit = try git([
            "-c", "user.email=probe@example.com", "-c", "user.name=probe", "commit", "-m", "第一次提交",
        ])
        guard commit.contains("第一次提交") else {
            throw XCTSkip("这台机器上 git 提交不成功（\(commit)）⇒ 真仓库夹具造不出来，跳过（不算通过）")
        }
        try "第一行\n第二行改过了\n".write(to: changedFile, atomically: true, encoding: .utf8)
        try "还没纳入版本管理\n".write(to: untrackedFile, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        if let repo { try? FileManager.default.removeItem(at: repo) }
    }

    // MARK: - 夹具工具

    @discardableResult
    private func git(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repo.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 仓库的「一个字节都没变」指纹：HEAD / index / 工作树里那两个文件。
    private func repositorySignature() throws -> [String: String] {
        var signature: [String: String] = [:]
        for (label, url) in [
            ("HEAD", repo.appendingPathComponent(".git/HEAD")),
            ("index", repo.appendingPathComponent(".git/index")),
            ("a.txt", changedFile!),
            ("b.txt", untrackedFile!),
        ] {
            signature[label] = try sha256(of: url)
        }
        return signature
    }

    // MARK: - ① 分支与改动清单（真 git 读数）

    @MainActor
    func testStatusReportsTheRealBranchAndChangeList() throws {
        let status: GitWorktreeStatus
        switch GitWorktreeProbe.loadStatus(root: repo.path) {
        case .success(let loaded):
            status = loaded
        case .failure(let failure):
            return XCTFail("真仓库读不出状态：\(failure) —— 面板会显示一句「读不到」")
        }

        // 与 git 自己说的分支名对一遍（`-C <root>` 真的指到了这个仓库）。
        let realBranch = try git(["rev-parse", "--abbrev-ref", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(status.branch, realBranch, "面板上的分支名与 git 自己说的不一致")
        XCTAssertEqual(status.branch, "probe-read-only", "分支名不是夹具那个：\(status.branch)")

        XCTAssertFalse(status.isClean, "工作树明明有改动，却报成干净")
        let paths = status.entries.map(\.path)
        XCTAssertTrue(paths.contains("a.txt"), "改动清单里没有刚改过的那份文件：\(paths)")
        XCTAssertTrue(paths.contains("b.txt"), "改动清单里没有未跟踪的那份文件：\(paths)")
        XCTAssertEqual(
            status.entries.first { $0.path == "a.txt" }?.kind, .modified,
            "a.txt 的归类不是「修改」"
        )
        XCTAssertEqual(
            status.entries.first { $0.path == "b.txt" }?.kind, .untracked,
            "b.txt 的归类不是「未跟踪」"
        )
        XCTAssertEqual(status.ahead, 0, "夹具没有上游，不该报 ahead")
        XCTAssertEqual(status.behind, 0, "夹具没有上游，不该报 behind")
    }

    // MARK: - ② 逐行差异：真的读出了那两行

    @MainActor
    func testDiffShowsTheChangedLinesAndThePresentationLayerCarriesThem() throws {
        let entry = try XCTUnwrap(
            GitWorktreeProbe.loadStatus(root: repo.path).probeSuccess?.entries.first { $0.path == "a.txt" },
            "改动清单里没有 a.txt ⇒ 差异这一路没有入口"
        )

        let document: GitDiffDocument
        switch GitWorktreeProbe.loadDiff(root: repo.path, entry: entry, staged: false) {
        case .success(let loaded):
            document = loaded
        case .failure(let failure):
            return XCTFail("真仓库读不出差异：\(failure)")
        }

        let file = try XCTUnwrap(document.files.first, "差异文档里一个文件都没有")
        XCTAssertEqual(file.displayPath, "a.txt", "差异对应的文件不是 a.txt")
        let added = file.hunks.flatMap(\.lines).filter { $0.kind == .added }.map(\.text)
        let removed = file.hunks.flatMap(\.lines).filter { $0.kind == .removed }.map(\.text)
        XCTAssertEqual(added, ["第二行改过了"], "新增那一行读错了：\(added)")
        XCTAssertEqual(removed, ["第二行"], "删掉那一行读错了：\(removed)")

        // 界面画的是**呈现层**那一份（折叠 / 按需渲染都在这条路上）。
        let presentation = GitDiffPresentation.make(for: file)
        let drawn = presentation.rows.compactMap { row -> GitDiffLine? in
            if case let .line(line) = row { return line }
            return nil
        }
        XCTAssertTrue(
            drawn.contains { $0.kind == .added && $0.text == "第二行改过了" },
            "呈现层没把新增那一行交出来：\(drawn.map(\.text))"
        )
        XCTAssertTrue(
            drawn.contains { $0.kind == .removed && $0.text == "第二行" },
            "呈现层没把删掉那一行交出来：\(drawn.map(\.text))"
        )
        XCTAssertEqual(presentation.hiddenRows, 0, "这么小的差异不该被按需渲染藏起来")
    }

    /// 未跟踪的文件也要能看差异（git 没有两侧可比，改走 `--no-index /dev/null`；
    /// 它的退出码 1 是「有差异」不是失败 —— 当成失败就等于「新增文件永远看不到内容」）。
    @MainActor
    func testUntrackedFileStillShowsItsContent() throws {
        let entry = try XCTUnwrap(
            GitWorktreeProbe.loadStatus(root: repo.path).probeSuccess?.entries.first { $0.path == "b.txt" }
        )
        guard case let .success(document) = GitWorktreeProbe.loadDiff(
            root: repo.path, entry: entry, staged: false
        ) else {
            return XCTFail("未跟踪的文件读不出差异 —— 新加的文件在界面上将是一片空白")
        }
        let texts = document.files.flatMap(\.hunks).flatMap(\.lines).map(\.text)
        XCTAssertTrue(
            texts.contains("还没纳入版本管理"),
            "未跟踪文件的内容没被读出来：\(texts)"
        )
    }

    // MARK: - ③ 只读：整条读流程跑完，仓库一个字节没变

    @MainActor
    func testReadingNeverWritesToTheRepository() throws {
        let before = try repositorySignature()

        // 把面板会做的那几件事全跑一遍（状态 + 两侧差异 + 呈现层）。
        for _ in 0..<2 {
            guard let status = GitWorktreeProbe.loadStatus(root: repo.path).probeSuccess else {
                return XCTFail("状态读不出来")
            }
            for entry in status.entries {
                _ = GitWorktreeProbe.loadDiff(root: repo.path, entry: entry, staged: false)
                _ = GitWorktreeProbe.loadDiff(root: repo.path, entry: entry, staged: true)
            }
        }

        let after = try repositorySignature()
        XCTAssertEqual(
            after, before,
            "读一遍仓库状态 / 差异之后仓库被改动了：\(before) → \(after)（只读这条承诺破了）"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git/index.lock").path),
            "留下了 `.git/index.lock` —— 有写操作挂在 index 上"
        )
    }

    // MARK: - ④ 真面板里没有任何写操作入口

    /// 关键词（中英）：需求原话「不做提交 / 推送」。暂存（stage / add）同属写操作。
    private let writeWords = ["提交", "推送", "暂存", "commit", "push", "stage", "add"]

    private func mentionsWrite(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return writeWords.contains { lowered.contains($0.lowercased()) }
    }

    @MainActor
    func testPanelOffersNoCommitOrPushEntry() async throws {
        let store = WorkspaceStore(
            store: DirectoryBookmarkStore(directoryURL: repo, fileName: "workspace-bookmark.json")
        )
        await store.choose(repo)
        XCTAssertEqual(
            store.rootPath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
            repo.resolvingSymlinksInPath().path,
            "工作区根没指到夹具仓库 ⇒ 面板读的是别处"
        )

        let host = UISnapshot.LiveHost(
            GitChangesPanel().environmentObject(store),
            size: CGSize(width: 900, height: 420)
        )
        // 等面板自己把 git 跑完（`refresh` 在后台队列上跑，结果回主线程）。
        host.pump(2.0)

        let buttons = UISnapshot.LiveHost<Never>.findViews(ofType: NSButton.self, in: host.hosting)
        let offenders = buttons.filter { button in
            mentionsWrite(button.title) || mentionsWrite(button.toolTip ?? "")
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "面板里出现了写操作入口：\(offenders.map { [$0.title, $0.toolTip ?? ""] })"
                + " —— 需求原话「不做提交 / 推送」"
        )
        // 这一页**一枚带字按钮都不该有**（提交 / 推送这类动作一定是带字的）。
        XCTAssertTrue(
            buttons.allSatisfy { $0.title.trimmingCharacters(in: .whitespaces).isEmpty },
            "面板里出现了带文字的按钮：\(buttons.map(\.title))"
        )
    }

    /// **对照（判据必须能判红）**：同一套「扫按钮」的量法，在真插一枚写着「提交并推送」的
    /// `NSButton` 时必须命中 —— 否则上面那条「零命中」可能只是这套遍历根本看不见按钮。
    @MainActor
    func testWriteEntryScanSeesAKnownWriteButton() throws {
        let host = UISnapshot.LiveHost(
            KnownWriteButtonProbe(), size: CGSize(width: 300, height: 80)
        )
        host.pump(0.3)
        let buttons = UISnapshot.LiveHost<Never>.findViews(ofType: NSButton.self, in: host.hosting)
        XCTAssertEqual(buttons.count, 1, "对照件没被扫到：\(buttons.map(\.title))")
        XCTAssertTrue(
            buttons.contains { mentionsWrite($0.title) },
            "同一套关键词判不出「提交并推送」⇒ 上面那条「没有写入口」不算数"
        )
    }
}

private extension Result {
    var probeSuccess: Success? {
        if case let .success(value) = self { return value }
        return nil
    }
}

/// 对照件：一枚写着「提交并推送」的真 `NSButton`（**不接进任何界面**，只为证明扫描量法能判红）。
private struct KnownWriteButtonProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        NSButton(title: "提交并推送", target: nil, action: nil)
    }

    func updateNSView(_ nsView: NSButton, context: Context) {}
}
