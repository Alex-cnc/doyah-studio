import AppKit
import SwiftUI
import XCTest

import DoyahCore
import DoyahPlatform
@testable import DoyahStudioApp

/// **工作区根两态来源（`FR-STD-WS-FS-011`）的判据**。
///
/// ## 判什么（五条，逐条对应契约）
///
///   ① 空数据目录启动 ⇒ 根 = `~/.doyah`（绝对路径展开后逐字相等），目录被建出来且可写；
///   ② 旧数据（有 `workspacePath`、**没有**来源标记）⇒ 根落回默认根，并且**有可见提示**；
///   ③ 用户打开一个文件夹 ⇒ 根 = 那个文件夹、来源 = 用户打开；重载 store（= 重启）仍是它；
///   ④ 点「恢复默认」⇒ 根回到默认根，来源回到默认；
///   ⑤ 工具层面：根内写成功、根外写**不落盘**并出「越界」单 —— 用真 `AgentWorkspaceTools` 打。
///
/// ## 为什么量在 store 上而不是量在界面上
///
/// 根是**一份状态**（`WorkspaceStore.rootPath`），界面只是它的显示。用户报的那个缺陷
/// （装到 `/Applications` 之后 Agent 还在开发目录里动文件）的根因就在这份状态：
/// 旧版本用「活动书签 / 快照里的 workspacePath」直接推出根，于是同 bundle 的正式包继承了
/// 开发时打开的目录。判据必须打在推根的那个决定上，否则「界面显示了默认根、工具却还在别处」
/// 这类偏差照样漏。
///
/// 界面上那一半只判一条：迁移提示**画出来了**（②）。那一条走真视图 + 真 AX 树读，
/// 不是读变量 —— 「store 里有字符串」不等于「用户看得见」。
///
/// 跑法：`env DOYAH_UI_SNAPSHOT=1 swift test --scratch-path .build-agent --filter AgentWorkspaceRootProbeTests`
final class AgentWorkspaceRootProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "要真视图与真 AX 树：DOYAH_UI_SNAPSHOT=1 才跑（取证工具，不进每轮门禁）"
        )
    }

    // MARK: - 夹具

    /// 一个**假的家目录**：`~/.doyah` 换到它下面，断言不必碰主人真正的 `~/.doyah`。
    ///
    /// 默认根由 `AgentWorkspaceRoot.directoryName` 拼出来 —— 与产品同一个常量，
    /// 所以「假家目录里的默认根」与「真家目录里的默认根」是同一条规则的两次求值（见判据 ① 的第二段）。
    private struct Home {
        let base: URL
        let home: URL
        let state: URL

        var defaultRoot: URL { home.appendingPathComponent(AgentWorkspaceRoot.directoryName, isDirectory: true) }

        func stateFile(_ name: String) -> URL { state.appendingPathComponent(name, isDirectory: false) }

        func remove() { try? FileManager.default.removeItem(at: base) }
    }

    private func makeHome(_ label: String) throws -> Home {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-agent-root-\(label)", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = base.appendingPathComponent("home", isDirectory: true)
        let state = base.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        return Home(base: base, home: home, state: state)
    }

    /// 生产形状的 store：书签 / 来源标记 / 会话快照各一个临时文件，默认根指向假家目录。
    @MainActor
    private func makeStore(_ home: Home) -> WorkspaceStore {
        WorkspaceStore(
            store: DirectoryBookmarkStore(directoryURL: home.state, fileName: "probe-bookmarks.json"),
            originStore: WorkspaceRootOriginStore(fileURL: home.stateFile("probe-origin.json")),
            sessionStore: WorkspaceSessionStore(fileURL: home.stateFile("probe-session.json")),
            defaultRoot: home.defaultRoot
        )
    }

    /// `realpath` 口径（`/var/folders/…` → `/private/var/folders/…`）：书签解析出来的路径是这一版。
    private func reported(_ url: URL) -> String { WorkspaceFileProbeKit.reported(url) }

    // MARK: - ① 空数据目录 ⇒ 默认根（并建目录、可写）

    @MainActor
    func testFreshDataDirectoryFallsBackToTheDefaultRoot() async throws {
        let home = try makeHome("fresh")
        defer { home.remove() }

        // 判据成立的前提：默认根此刻**不存在**（否则「被创建」这一半无从谈起）。
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: home.defaultRoot.path),
            "夹具里的默认根一开始就存在（\(home.defaultRoot.path)）—— 「目录被创建」这一半量不到"
        )

        let store = makeStore(home)
        await store.load()

        print("ROOT[①] 期望默认根=\(home.defaultRoot.path)")
        print("ROOT[①] 实得 rootPath=\(store.rootPath ?? "nil") origin=\(store.rootOrigin.rawValue) notice=\(store.originNotice ?? "nil")")

        XCTAssertEqual(store.rootPath, home.defaultRoot.path, "空数据目录启动后的根不是默认根")
        XCTAssertEqual(store.rootOrigin, .defaultRoot, "空数据目录启动后的来源不是「默认」")
        XCTAssertNil(store.originNotice, "首次运行不该出现迁移提示")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: home.defaultRoot.path),
            "默认根没有被建出来：\(home.defaultRoot.path)"
        )
        XCTAssertTrue(
            FileManager.default.isWritableFile(atPath: home.defaultRoot.path),
            "默认根建出来了但不可写 —— Agent 在这个根下什么都干不成"
        )

        // 生产的默认根就是 `~/.doyah`（逐字相等，展开 `~` 之后）。
        let production = AgentWorkspaceRoot.defaultURL()
        let expected = NSString(string: "~/\(AgentWorkspaceRoot.directoryName)").expandingTildeInPath
        print("ROOT[①] 生产默认根=\(production.path) 期望=\(expected)")
        XCTAssertEqual(production.path, expected, "生产默认根不是 ~/\(AgentWorkspaceRoot.directoryName)")
        XCTAssertEqual(
            production.standardizedFileURL.path,
            URL(fileURLWithPath: expected, isDirectory: true).standardizedFileURL.path,
            "生产默认根展开后与 `~/.doyah` 的绝对路径不一致"
        )
    }

    // MARK: - ② 旧数据（有 workspacePath、无来源标记）⇒ 默认根 + 可见提示

    @MainActor
    func testLegacyWorkspacePathIsMigratedToTheDefaultRootWithAVisibleNotice() async throws {
        let home = try makeHome("legacy")
        defer { home.remove() }

        // 旧版本留下的两样东西：指向「开发目录」的书签 + 快照里记的 workspacePath。
        let devDirectory = home.base.appendingPathComponent("dev-studio", isDirectory: true)
        try FileManager.default.createDirectory(at: devDirectory, withIntermediateDirectories: true)
        try "let x = 1\n".write(
            to: devDirectory.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)

        let bookmarkStore = DirectoryBookmarkStore(
            directoryURL: home.state, fileName: "probe-bookmarks.json")
        let created = try MacDirectoryAccess.makeBookmark(for: devDirectory)
        _ = try await bookmarkStore.save(
            DirectoryBookmark(
                displayName: created.displayName,
                bookmarkData: created.bookmarkData,
                createdAt: created.createdAt,
                lastKnownPath: created.lastKnownPath
            ))
        try WorkspaceSessionStore(fileURL: home.stateFile("probe-session.json")).save(
            WorkspaceSessionSnapshot(workspacePath: devDirectory.path, tabs: []))
        // **没有**来源标记（`probe-origin.json` 不存在）—— 这就是现状那一档。
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: home.stateFile("probe-origin.json").path),
            "夹具里不该有来源标记（有标记就不是迁移那一档了）"
        )

        let store = makeStore(home)
        await store.load()

        let notice = store.originNotice
        print("ROOT[②] 旧 workspacePath=\(devDirectory.path)")
        print("ROOT[②] 实得 rootPath=\(store.rootPath ?? "nil") origin=\(store.rootOrigin.rawValue)")
        print("ROOT[②] 提示=\(notice ?? "nil")")

        XCTAssertEqual(store.rootPath, home.defaultRoot.path, "旧数据没有被迁移到默认根")
        XCTAssertEqual(store.rootOrigin, .defaultRoot, "旧数据迁移后的来源不是「默认」")
        let unwrapped = try XCTUnwrap(notice, "旧数据迁移**静默**了：store 里没有那句提示")
        XCTAssertTrue(
            unwrapped.contains(AgentWorkspaceRoot.directoryName),
            "迁移提示里没写新根是 ~/\(AgentWorkspaceRoot.directoryName)：\(unwrapped)"
        )
        XCTAssertTrue(
            unwrapped.contains(devDirectory.path),
            "迁移提示里没写原来那个目录（用户没法照它改回去）：\(unwrapped)"
        )

        // **看得见**：把生产那一格（`AgentWorkspaceSection`）真画一遍。
        //
        // 离屏宿主里读不回 `Text` 的字符串（SwiftUI 的正文不是 `NSTextField`，AX 树在
        // 没有辅助功能会话时不铺开 —— 实测读数 `[]`，如实登记这一格的边界），所以这里量两件
        // 与「那一行在屏幕上」等价的事：**版面多出一行** + **像素真的变了**。同一份 store、
        // 同一尺寸，只把提示收起来再画一次 —— 两个读数之间的差只可能来自那一行。
        let measured = measurement(store: store)
        print("ROOT[②] 版面高度 有提示=\(measured.heightWith) 无提示=\(measured.heightWithout)")
        print("ROOT[②] 像素指纹 有提示=\(measured.signatureWith.prefix(12)) 无提示=\(measured.signatureWithout.prefix(12))")
        XCTAssertGreaterThan(
            measured.heightWith, measured.heightWithout,
            "提示没有占到版面（收起它前后高度一样）—— 界面上根本没有那一行"
        )
        XCTAssertNotEqual(
            measured.signatureWith, measured.signatureWithout,
            "提示没有画出来（收起它前后像素一模一样）"
        )

        // 标记落盘之后重启不再重复提示（迁移只发生一次）。
        let reloaded = makeStore(home)
        await reloaded.load()
        XCTAssertEqual(reloaded.rootPath, home.defaultRoot.path)
        XCTAssertNil(reloaded.originNotice, "重启之后又提示了一次 —— 迁移标记没有落盘")
    }

    // MARK: - ③ 用户打开 /tmp/ws-x ⇒ 用它；重载仍是它

    @MainActor
    func testUserOpenedFolderBecomesTheRootAndSurvivesReload() async throws {
        let home = try makeHome("useropened")
        defer { home.remove() }

        let userFolder = URL(fileURLWithPath: "/tmp/ws-x", isDirectory: true)
        try? FileManager.default.removeItem(at: userFolder)
        try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: userFolder) }
        try "seed\n".write(
            to: userFolder.appendingPathComponent("seed.txt"), atomically: true, encoding: .utf8)

        let store = makeStore(home)
        await store.load()
        XCTAssertEqual(store.rootPath, home.defaultRoot.path, "起点不是默认根（前置条件不成立）")

        await store.choose(userFolder)
        print("ROOT[③] 打开=\(userFolder.path) 实得=\(store.rootPath ?? "nil") origin=\(store.rootOrigin.rawValue)")
        XCTAssertEqual(
            store.rootPath, reported(userFolder),
            "用户打开的目录没有成为根"
        )
        XCTAssertEqual(store.rootOrigin, .userOpened, "来源没记成「用户打开」")

        // 重载 store = 重启（同一份数据目录）。
        let restarted = makeStore(home)
        await restarted.load()
        print("ROOT[③] 重启后=\(restarted.rootPath ?? "nil") origin=\(restarted.rootOrigin.rawValue)")
        XCTAssertEqual(restarted.rootPath, reported(userFolder), "重启之后根不是用户打开的那个目录")
        XCTAssertEqual(restarted.rootOrigin, .userOpened, "重启之后来源丢了")
        XCTAssertNil(restarted.originNotice, "用户显式选择之后不该有迁移提示")

        // ④ 恢复默认：根回到默认根，且重启仍是默认根。
        await restarted.restoreDefaultRoot()
        print("ROOT[④] 恢复默认后=\(restarted.rootPath ?? "nil") origin=\(restarted.rootOrigin.rawValue)")
        XCTAssertEqual(restarted.rootPath, home.defaultRoot.path, "「恢复默认」没把根切回默认根")
        XCTAssertEqual(restarted.rootOrigin, .defaultRoot, "「恢复默认」之后来源不是「默认」")

        let afterRestore = makeStore(home)
        await afterRestore.load()
        XCTAssertEqual(afterRestore.rootPath, home.defaultRoot.path, "恢复默认之后重启又回到用户目录")
        XCTAssertEqual(afterRestore.rootOrigin, .defaultRoot)
    }

    // MARK: - ⑤ 工具层面：根内写成功、根外写被拦（报越界）

    @MainActor
    func testAgentToolsWriteInsideTheRootAndAreStoppedOutside() async throws {
        let home = try makeHome("tools")
        defer { home.remove() }

        let store = makeStore(home)
        await store.load()
        let rootPath = try XCTUnwrap(store.rootPath, "默认根没起来，工具判据无从谈起")
        let tools = AgentWorkspaceTools(root: URL(fileURLWithPath: rootPath, isDirectory: true))

        // ① 根内：出单 → 批准 → 落盘，文件真的在默认根下。
        let inside = tools.prepareWrite(path: "probe.txt", content: "hello\n")
        guard case .needsApproval(let request) = inside else {
            return XCTFail("根内写在出单阶段就被拒了：\(inside)")
        }
        let written = tools.writeFile(
            path: "probe.txt", content: "hello\n",
            fingerprint: request.fingerprint, granted: [request.fingerprint])
        print("ROOT[⑤] 根内写=\(written) 目标=\(rootPath)/probe.txt")
        guard case .wrote = written else {
            return XCTFail("根内写没有落盘：\(written)")
        }
        let onDisk = URL(fileURLWithPath: rootPath).appendingPathComponent("probe.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: onDisk.path), "根内写报成功但盘上没有文件")
        XCTAssertEqual(try String(contentsOf: onDisk, encoding: .utf8), "hello\n")

        // ② 根外：不落盘，出「越界」单（`hazard == .outsideWorkspace`，payload 里写明越界）。
        let outsidePath = home.base.appendingPathComponent("outside-probe.txt").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: outsidePath))
        let outside = tools.prepareWrite(path: outsidePath, content: "should not land\n")
        print("ROOT[⑤] 根外写=\(outside)")
        guard case .needsApproval(let outsideRequest) = outside else {
            return XCTFail("根外写没有出「越界」单（而是 \(outside)）—— 那等于放行")
        }
        XCTAssertEqual(outsideRequest.hazard, .outsideWorkspace, "根外写没被标成越界")
        XCTAssertTrue(outsideRequest.payload.contains("越界"), "越界单上没写明这是越界：\(outsideRequest.payload)")
        XCTAssertTrue(
            outsideRequest.payload.contains(outsidePath),
            "越界单上没写目标绝对路径：\(outsideRequest.payload)"
        )
        // 没有批准指纹 ⇒ 一个字节都不许动。
        let refused = tools.writeFile(
            path: outsidePath, content: "should not land\n",
            fingerprint: "not-the-fingerprint", granted: [])
        print("ROOT[⑤] 根外未批准写=\(refused)")
        if case .wrote = refused {
            XCTFail("根外写在没有批准的情况下落了盘")
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outsidePath),
            "根外被拦住了没错，但盘上还是出现了那个文件"
        )
    }

    // MARK: - 界面读数（真视图 + 真 AX 树）

    /// 画两次同一格：一次带迁移提示，一次（把提示收起来之后）不带。
    ///
    /// - Returns: 两次的版面高度与像素指纹。高度差 = 那一行在版面上占了位置；
    ///   指纹差 = 那一行真的画到了屏幕上。
    @MainActor
    private func measurement(
        store: WorkspaceStore
    ) -> (heightWith: CGFloat, heightWithout: CGFloat,
          signatureWith: String, signatureWithout: String) {
        func section() -> some View {
            AgentWorkspaceSection()
                .environmentObject(store)
                .frame(width: 560, alignment: .leading)
                .padding(Spacing.m)
        }
        func fittedHeight() -> CGFloat {
            NSHostingView(rootView: section()).fittingSize.height
        }

        let heightWith = fittedHeight()
        let live = UISnapshot.LiveHost(AnyView(section()), size: CGSize(width: 620, height: 320), scheme: .light)
        live.pump(0.5)
        let axLabels = Self.accessibilityLabels(in: live.hosting)
        print("ROOT[②] 离屏 AX 标签读数 \(axLabels.count) 条：\(axLabels.prefix(6))")
        let signatureWith = (try? live.signature()) ?? ""

        store.dismissOriginNotice()
        live.pump(0.5)
        let signatureWithout = (try? live.signature()) ?? ""
        let heightWithout = fittedHeight()

        return (heightWith, heightWithout, signatureWith, signatureWithout)
    }

    /// 递归读 AX 树里的标签 / 值 / 标题 / 标识（SwiftUI 的 `Text` 不一定落成 `NSTextField`，
    /// 所以不能只扫视图树）。**按选择器取值**而不是按协议调方法：AppKit 里这几样在不同类上
    /// 有的声明成方法、有的声明成属性（实测编译期两种都撞过），选择器只有一种形状。
    @MainActor
    private static func accessibilityLabels(in host: NSView) -> [String] {
        var labels: [String] = []
        var visited = Set<ObjectIdentifier>()

        func note(_ text: String?) {
            guard let text, !text.isEmpty, !labels.contains(text) else { return }
            labels.append(text)
        }

        func walk(_ element: Any) {
            guard let object = element as? NSObject else { return }
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            for selector in ["accessibilityLabel", "accessibilityValue",
                             "accessibilityTitle", "accessibilityIdentifier"] {
                note(axObject(object, selector) as? String)
            }
            if let children = axObject(object, "accessibilityChildren") as? [Any] {
                for child in children { walk(child) }
            }
        }

        walk(host)

        // 视图树那一半：SwiftUI 的 `Text` 不保证落成 `NSTextField`，所以两条都扫。
        func walkViews(_ view: NSView) {
            let identifier = view.accessibilityIdentifier()
            if !identifier.isEmpty { note(identifier) }
            if let field = view as? NSTextField {
                note(field.stringValue)
                note(field.placeholderString)
                note(field.accessibilityIdentifier())
            }
            for subview in view.subviews { walkViews(subview) }
        }
        walkViews(host)
        return labels
    }

    /// 按选择器读一个 AX 取值（**只认返回对象的那些选择器**：label / value / title / children
    /// 在 ObjC 侧都是 `id`，`perform` 拿到的是同一个东西）。
    private static func axObject(_ object: NSObject, _ selectorName: String) -> Any? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }
}
