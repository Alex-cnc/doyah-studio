import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **关闭一个有未保存改动的页签**（`FR-STD-WS-UI-003` / `FR-EDIT-46`）—— 需求 A 的 App 内行为探针。
///
/// ## 判据落在「真页签条 + 真确认框 + 真按钮」上
///
/// `Core/WorkspaceClose.swift` 的判定（`WorkspaceClosePolicy.plan` / `keepsTab`）已由
/// `Tests/WorkspaceClosePolicyTests` 逐条钉过。那套判据全绿，界面照样可能：
///
///   · 根本没把 `pendingClose` 接到 `confirmationDialog` 上（**点了没反应**）；
///   · 把三个动作的次序写反（`取消` 排在最前，回车一按就取消）；
///   · 按钮只有图标没有文字（`confirmationDialog` 在 macOS 上是 `NSAlert`，
///     空标题的按钮会退化成「一个空按钮」—— 人类主人 2026-10-18 点验不过的正是这一幕）；
///   · 保存失败也照关（用户选的偏偏是「保存」）。
///
/// 本探针把真 `WorkspaceTabStrip` 装进离屏活宿主：SwiftUI 的 `confirmationDialog` 在 macOS 上
/// 会去挂一张真的 `NSAlert` 面板（实测 `window.attachedSheet` = `_NSAlertPanel`，
/// 面板里是 **3 枚真 `NSButton`**，标题与 `keyEquivalent` 都读得到）。于是「按钮文字 / 次序 /
/// Esc 落点 / 真点一下」四件事第一次都能机器化 —— 而且是**同一份**产品代码。
///
/// ## 边界（如实登记）
///
/// · 页签条上那枚 `xmark` 关闭键本身是 SwiftUI `Button`（离屏宿主里不落 `NSButton`，同族实测见
///   `NotesEditorSaveProbeTests` 文件头）⇒ 「点那枚键 → 模型拿到请求」这一段判到**它调用的那个
///   模型入口**（`requestClose`，页签条上的按钮直接调它）；从那一刻往后（弹框 / 三个按钮 / 点击
///   结局）全部判在**真视图与真按钮**上。
/// · 观感（间距 / 圆角 / 颜色）不在本判据内。
final class WorkspaceCloseProbeTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceCloseProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - 装配

    @MainActor
    private func makeTabs() -> WorkspaceTabsModel {
        WorkspaceTabsModel(
            store: WorkspaceHistoryStore.standard(applicationSupport: root),
            sessionStore: WorkspaceSessionStore.standard(applicationSupport: root)
        )
    }

    /// 装一条**真页签条**（真 `AppState` / 真工作区 / 真页签模型），返回宿主与页签模型。
    @MainActor
    private func makeStrip(
        _ tabs: WorkspaceTabsModel
    ) -> UISnapshot.LiveHost<AnyView> {
        let state = AppState()
        let workspace = WorkspaceStore(
            store: DirectoryBookmarkStore(directoryURL: root, fileName: "workspace-bookmark.json")
        )
        let browser = WorkspaceBrowserModel()
        let terminal = TerminalModel()
        let host = UISnapshot.LiveHost(
            AnyView(
                WorkspaceTabStrip()
                    .snapshotEnvironment(state: state, workspace: workspace, tabs: tabs, terminal: terminal)
                    .environmentObject(browser)
            ),
            size: CGSize(width: 900, height: 120)
        )
        host.pump(0.6)
        return host
    }

    /// 打开一个真文件并把它改脏（走「双击打开」那条真路：`openFile(at:)`）。
    @MainActor
    private func openDirtyTab(
        _ tabs: WorkspaceTabsModel, name: String = "notes.txt", original: String = "第一行\n"
    ) throws -> (tab: WorkspaceTab, url: URL) {
        let url = root.appendingPathComponent(name)
        try original.write(to: url, atomically: true, encoding: .utf8)
        tabs.openFile(at: url)
        let tab = try XCTUnwrap(
            tabs.tabs.first { $0.path == url.path },
            "打开之后没有 \(name) 这一页 —— 判据的入口没走通"
        )
        tabs.updateContent(original + "改过的第二行\n", for: tab.id)
        let dirty = try XCTUnwrap(tabs.tabs.first { $0.id == tab.id })
        XCTAssertTrue(dirty.isDirty, "改过内容之后页签还不是脏的 ⇒ 后面的判据都判不到点子上")
        return (dirty, url)
    }

    /// 真确认框里那几枚**真 `NSButton`**（按面板上的次序）。
    ///
    /// 注意先泵一轮：`confirmationDialog` 挂出那张 `NSAlert` 面板是**异步**的（本机实测：
    /// `requestClose` 之后不等一拍，`attachedSheet` 还是 nil）。
    @MainActor
    private func confirmButtons(_ host: UISnapshot.LiveHost<AnyView>) throws -> [NSButton] {
        host.pump(1.2)
        let sheet = try XCTUnwrap(
            host.window.attachedSheet,
            "有未保存改动却没挂出确认框（`window.attachedSheet` = nil）—— 用户点了关闭什么都不会发生"
        )
        let content = try XCTUnwrap(sheet.contentView, "确认框没有内容视图")
        let buttons = UISnapshot.LiveHost<Never>.findViews(ofType: NSButton.self, in: content)
        XCTAssertEqual(buttons.count, 3, "确认框里应当恰好三枚按钮：实测 \(buttons.map(\.title))")
        return buttons
    }

    // MARK: - ① 干净页签不弹框

    @MainActor
    func testCleanTabClosesWithoutAsking() throws {
        let url = root.appendingPathComponent("clean.txt")
        try "干净的文件\n".write(to: url, atomically: true, encoding: .utf8)

        let tabs = makeTabs()
        tabs.openFile(at: url)
        let tab = try XCTUnwrap(tabs.tabs.first { $0.path == url.path })
        XCTAssertFalse(tab.isDirty, "刚打开的文件不该是脏的（形态或内容被算成了改动）")

        let host = makeStrip(tabs)
        // 页签条上那枚关闭键调的就是这个入口。
        tabs.requestClose(tab.id)
        host.pump(0.8)

        XCTAssertNil(
            tabs.pendingClose,
            "干净页签也弹了确认框 —— 多一次点击就是多一次打扰（需求①）"
        )
        XCTAssertNil(host.window.attachedSheet, "干净页签居然挂出了确认框")
        XCTAssertFalse(
            tabs.tabs.contains { $0.id == tab.id },
            "干净页签没被关掉（用户点了关闭什么也没发生）"
        )
        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8), "干净的文件\n",
            "关一个干净页签不该动盘上的文件"
        )
    }

    // MARK: - ② 脏页签弹框，三个动作与次序固定

    @MainActor
    func testDirtyTabRaisesTheConfirmationWithAFixedActionOrder() throws {
        let tabs = makeTabs()
        let (tab, _) = try openDirtyTab(tabs)
        let host = makeStrip(tabs)

        tabs.requestClose(tab.id)
        let buttons = try confirmButtons(host)

        XCTAssertEqual(
            buttons.map(\.title),
            [L(.workspaceCloseSaveAndClose), L(.workspaceCloseDiscardChanges), L(.workspaceCloseCancel)],
            "确认框里的三枚按钮与次序不对：实测 \(buttons.map(\.title))"
        )
        // 「保存并关闭」在最前、是回车落点；「取消」排最后、是 Esc 落点。
        XCTAssertEqual(buttons[0].keyEquivalent, "\r", "第一枚不是回车落点（保存并关闭该在最前）")
        XCTAssertEqual(
            buttons[2].keyEquivalent, "\u{1b}",
            "最后一枚不是 Esc 落点（取消该在最后，按 Esc 才能出去）"
        )
        XCTAssertTrue(
            buttons.allSatisfy { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty },
            "确认框里出现了没有文字的按钮（只按图标渲染 ⇒ 用户看不出这是哪个选择）"
        )

        // 同一个次序在模型那一侧（`WorkspaceClosePolicy.confirmActions`，唯一出处）。
        let request = try XCTUnwrap(tabs.pendingClose, "确认框挂着，模型里却没有这次关闭请求")
        XCTAssertEqual(request.id, tab.id, "关闭请求指向了别的页签")
        XCTAssertEqual(request.title, tab.title, "确认框标题里的文件不对")
        XCTAssertEqual(
            request.actions, WorkspaceClosePolicy.confirmActions,
            "确认框的动作表与 `WorkspaceClosePolicy` 不是同一份（界面自己排了一遍）"
        )
        XCTAssertEqual(request.actions.first, .saveAndClose, "第一个动作不是「保存并关闭」")
        XCTAssertEqual(request.actions.last, .cancel, "最后一个动作不是「取消」")
    }

    // MARK: - ③ 取消：不关、盘上不动

    @MainActor
    func testClickingCancelKeepsTheTabAndLeavesTheFileAlone() throws {
        let tabs = makeTabs()
        let (tab, url) = try openDirtyTab(tabs)
        let host = makeStrip(tabs)
        tabs.requestClose(tab.id)
        let buttons = try confirmButtons(host)

        // 真点一下那枚「取消」。
        buttons[2].performClick(nil)
        host.pump(0.8)

        XCTAssertNil(tabs.pendingClose, "点了取消，请求还挂着")
        XCTAssertTrue(
            tabs.tabs.contains { $0.id == tab.id },
            "选了「取消」页签却被关掉了 —— 取消 = 什么都没发生"
        )
        XCTAssertTrue(
            tabs.tabs.first { $0.id == tab.id }?.isDirty ?? false,
            "取消之后改动被当成已保存（脏标记没了，用户会以为存过了）"
        )
        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8), "第一行\n",
            "选了取消却把文件写了"
        )
    }

    // MARK: - ④ 保存并关闭：先写盘，写成功才关

    @MainActor
    func testClickingSaveAndCloseWritesThenCloses() throws {
        let tabs = makeTabs()
        let (tab, url) = try openDirtyTab(tabs)
        let host = makeStrip(tabs)
        tabs.requestClose(tab.id)
        let buttons = try confirmButtons(host)

        buttons[0].performClick(nil)
        host.pump(0.8)

        XCTAssertFalse(
            tabs.tabs.contains { $0.id == tab.id },
            "选了「保存并关闭」页签却还在（这一条是需求的原话）"
        )
        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8), "第一行\n改过的第二行\n",
            "页签关了，磁盘上却没有刚敲的内容 —— 改动被丢了"
        )
    }

    // MARK: - ⑤ 保存失败就不关

    @MainActor
    func testSaveFailureKeepsTheTabOpen() throws {
        let tabs = makeTabs()
        let (tab, url) = try openDirtyTab(tabs, name: "blocked.txt")
        let host = makeStrip(tabs)

        // 造一条**真的会失败**的保存路（不靠权限位：把文件挪走、在原路径放一个目录，
        // 写文件就会如实地失败，而这一页里用户敲的字还在）。
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        tabs.requestClose(tab.id)
        let buttons = try confirmButtons(host)
        buttons[0].performClick(nil)
        host.pump(1.0)

        XCTAssertTrue(
            tabs.tabs.contains { $0.id == tab.id },
            "保存失败却把页签关了 —— 用户选的偏偏是「保存」，这一下等于把刚敲的字丢了"
        )
        XCTAssertNotNil(tabs.errorText, "保存失败却没有任何可见的说法（用户不知道发生了什么）")
        let kept = try XCTUnwrap(tabs.tabs.first { $0.id == tab.id })
        XCTAssertTrue(kept.isDirty, "保存失败之后脏标记被抹掉了 ⇒ 用户会以为已经存过")
        XCTAssertNil(tabs.pendingClose, "动作已经执行过，确认框的状态还挂着")
    }

    // MARK: - ⑥ 不保存直接关闭：关掉，但不碰盘上的文件

    @MainActor
    func testClickingDiscardClosesWithoutTouchingTheFile() throws {
        let tabs = makeTabs()
        let (tab, url) = try openDirtyTab(tabs)
        let host = makeStrip(tabs)
        tabs.requestClose(tab.id)
        let buttons = try confirmButtons(host)

        buttons[1].performClick(nil)
        host.pump(0.8)

        XCTAssertFalse(
            tabs.tabs.contains { $0.id == tab.id },
            "选了「不保存，直接关闭」页签却没关"
        )
        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8), "第一行\n",
            "「不保存」却把改动写进了文件 —— 这一档要的是原样不动"
        )
    }

    // MARK: - 对照（判据必须能判红）：这套「找真按钮」的量法确实看得见按钮

    /// 上面几条都建立在「从面板里扫到 3 枚真 `NSButton`」上。若这套遍历根本扫不到东西，
    /// 那些断言会以另一种方式（数不对）失败 —— 这一条把量法本身钉在明处：
    /// 往同一个宿主里插一枚**已知标题**的真 `NSButton`，同一套遍历必须扫得到它。
    @MainActor
    func testButtonScanSeesAKnownButton() throws {
        let host = UISnapshot.LiveHost(
            KnownButtonProbe(), size: CGSize(width: 300, height: 80)
        )
        host.pump(0.3)
        let buttons = UISnapshot.LiveHost<Never>.findViews(ofType: NSButton.self, in: host.hosting)
        XCTAssertTrue(
            buttons.contains { $0.title == "对照按钮" },
            "同一套遍历扫不到真插进去的 NSButton ⇒ 确认框那几条判据不算数：\(buttons.map(\.title))"
        )
    }
}

/// 对照件：一枚**写着字**的真 `NSButton`（只为证明扫描量法看得见按钮，不接进任何界面）。
private struct KnownButtonProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        NSButton(title: "对照按钮", target: nil, action: nil)
    }

    func updateNSView(_ nsView: NSButton, context: Context) {}
}
