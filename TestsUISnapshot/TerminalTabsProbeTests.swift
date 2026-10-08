import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 终端多会话（页签）的 **App 侧探针**（队列 `L-84` ㈡）—— 开发循环第 82 轮。
///
/// ## 为什么需要它（㈠ 的判据缺口）
///
/// ㈠ 把「顺序与归属」的判定搬进 Core 并穷举了单测，但**真开 shell 那一半没人证**：
/// 「每个页签 = 独立 PTY」「切页签不重启会话」「退出标记与重启」「关页签前先问一句」
/// 这几件事全靠视图 + `TerminalPane` + `TerminalSession`，Core 单测**照不到**，
/// 而真人点验（主诉场景）又只能在人在场时做。这个文件在**离屏**把这几件事跑成断言。
///
/// ## 口径
///
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 它**真开 shell**，不能挂在每轮门禁里
///   （与快照同一条纪律：取证才跑，门禁不跑）；
/// · 需求原话场景直接照搬：**一个页签跑长时间占着终端的程序（≈ `dsh-tui`），
///   另一个页签执行命令并返回**；
/// · 断言全部落在**行为**上（屏幕内容 / 前台进程名 / 页签状态），不点界面 ——
///   界面能不能点由真人与快照承担。
///
/// 边界（如实登记）：它验的是**本机 macOS 上的真 PTY 行为**；不验滚动条 / 拖拽 / 输入法，
/// 也不验「应用退出后会话是否保留」（需求口径里那是**后续**，不在本版）。
final class TerminalTabsProbeTests: XCTestCase {

    // MARK: - 工具

    /// 把一屏网格读成文本（与视图绘制用的是同一份数据：`displayLines()`）。
    @MainActor
    private func text(of pane: TerminalPane) -> String {
        pane.displayLines()
            .map { $0.map(\.displayText).joined() }
            .joined(separator: "\n")
    }

    /// 等到条件成立（默认 10 秒）。测试里不能阻塞主线程等 —— 会话输出是在主队列上派发的，
    /// 所以这里**转主运行循环**而不是 `sleep`。
    @MainActor
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 10,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        if condition() { return true }
        XCTFail("等不到：\(description)")
        return false
    }

    /// 只由**执行结果**才会出现的标记（回避「tty 把我敲的命令回显出来」这个假绿）。
    private let resultPattern = try! NSRegularExpression(pattern: #"RESULT-\d{6,}"#)

    private func containsResult(_ haystack: String, _ pattern: NSRegularExpression) -> Bool {
        pattern.firstMatch(in: haystack, range: NSRange(haystack.startIndex..., in: haystack)) != nil
    }

    // MARK: - 探针一：两个页签 = 两条独立 PTY（需求原话场景）

    @MainActor
    func testTwoTabsRunIndependentShellsAndSurviveTabSwitching() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针真开 shell（取证专用）：DOYAH_UI_SNAPSHOT=1 才跑"
        )

        let model = TerminalModel()
        let first = model.activePane
        first.startIfNeeded(columns: 80, rows: 24)
        XCTAssertTrue(first.isRunning, "第一个页签的 shell 没起来")

        // ⌘T 走的就是这一条
        let secondID = model.newTab()
        let second = model.pane(for: secondID)
        XCTAssertTrue(second !== first, "两个页签拿到了同一个会话对象")
        second.startIfNeeded(columns: 80, rows: 24)
        XCTAssertTrue(second.isRunning, "第二个页签的 shell 没起来")
        XCTAssertNotEqual(model.tabs.ids, [1], "新页签没有进页签集合")
        XCTAssertEqual(model.tabs.activeID, secondID, "新建之后应当激活新页签")

        // ① 需求原话：**一个页签长时间占着终端**（`sleep 30` 起着 `dsh-tui` 的作用）
        first.send(text: "sleep 30\n")
        waitUntil("第一个页签的前台进程变成 sleep") {
            TerminalTabTitle.derive(fromExecutablePath: first.foregroundProcessPath()) == "sleep"
        }

        // ② …另一个页签**执行命令并返回**（旧版本里这一步只能去开系统终端）
        second.send(text: "date +RESULT-%s\n")
        waitUntil("第二个页签执行并打印出结果") { self.containsResult(self.text(of: second), self.resultPattern) }

        // ③ 互不干扰：结果只出现在第二个页签上，第一个页签里没有它
        XCTAssertTrue(
            containsResult(text(of: second), resultPattern),
            "第二个页签没执行到自己的命令"
        )
        XCTAssertFalse(
            containsResult(text(of: first), resultPattern),
            "两条会话串了：第二个页签的输出出现在第一个页签上"
        )
        // 前台进程名是页签标题的唯一来源，两条会话各自算各自的
        XCTAssertEqual(
            TerminalTabTitle.derive(fromExecutablePath: second.foregroundProcessPath()),
            TerminalTabTitle.derive(fromExecutablePath: TerminalSession.defaultShell()),
            "第二个页签的前台不该是别的程序（它正停在提示符上）"
        )

        // ④ **切页签不重启会话**（㈠ 的契约）：在第二个页签里留一个 shell 变量，
        //    切走再切回来它还在 —— 会话被重启过的话变量就没了。
        let token = "KEEPME-\(UUID().uuidString.prefix(6))"
        second.send(text: "PROBE_VAR=\(token)\n")
        waitUntil("第二个页签记住了变量") { self.text(of: second).contains(token) }

        model.select(id: 1)
        XCTAssertEqual(model.tabs.activeID, 1)
        XCTAssertTrue(first.isRunning, "切页签把第一个页签的会话弄死了")
        model.select(id: secondID)
        XCTAssertTrue(second.isRunning, "切回来把第二个页签的会话弄死了")

        second.send(text: "echo \"V=$PROBE_VAR\"\n")
        waitUntil("切回之后变量还在（会话没被重启）") { self.text(of: second).contains("V=\(token)") }

        // 收摊：把两条会话都关掉（`stop` 会 SIGHUP 整个进程组，`sleep 30` 一起收）
        first.stop()
        second.stop()
    }

    // MARK: - 探针二：退出标记 / 重启 / 关页签前先问一句 / 最后一个不许关

    @MainActor
    func testExitRestartConfirmationAndLastTabRefusal() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针真开 shell（取证专用）：DOYAH_UI_SNAPSHOT=1 才跑"
        )

        let model = TerminalModel()
        let firstID = model.tabs.activeID
        let secondID = model.newTab()
        let second = model.pane(for: secondID)
        second.startIfNeeded(columns: 80, rows: 24)
        XCTAssertTrue(second.isRunning)

        // ① 页签里的 shell 退出 ⇒ 页签被标「已退出」（真 PTY 的退出事件走完整条链）
        second.send(text: "exit\n")
        waitUntil("第二个页签被标成已退出") {
            model.tabs.tab(id: secondID)?.isExited == true
        }
        XCTAssertNotNil(model.exitedDetail(for: model.tabs.tab(id: secondID)!),
                        "「已退出」在语言表里取不到说法")

        // ② 重启：同一个页签换一条命（id 与状态位都回来）
        model.restart(id: secondID, columns: 80, rows: 24)
        XCTAssertEqual(model.tabs.tab(id: secondID)?.isExited, false, "重启后页签还挂着「已退出」")
        XCTAssertTrue(second.isRunning, "重启没有真的把 shell 拉起来")

        // ③ 前台有程序在跑 ⇒ 关页签**先问一句**（不许直接把用户在跑的东西杀掉）
        second.send(text: "sleep 30\n")
        waitUntil("第二个页签的前台进程变成 sleep") {
            TerminalTabTitle.derive(fromExecutablePath: second.foregroundProcessPath()) == "sleep"
        }
        model.refreshForegroundProcesses()
        model.requestClose(id: secondID)
        XCTAssertEqual(model.pendingCloseTab, secondID, "前台有程序在跑却没弹确认")
        XCTAssertEqual(model.tabs.count, 2, "还没确认就把页签关了")
        model.cancelClose()
        XCTAssertNil(model.pendingCloseTab)
        XCTAssertEqual(model.tabs.count, 2, "取消之后页签不该少")

        // 确认之后才真的关（会话也一起收掉）
        model.requestClose(id: secondID)
        model.confirmClose()
        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertNil(model.tabs.tab(id: secondID), "关掉的页签还在集合里")
        XCTAssertFalse(second.isRunning, "关页签没有把里面的会话收掉")

        // ④ **最后一个页签不许关**：判定拒绝 + 给用户一句说法（不许静默无反应）
        XCTAssertEqual(model.tabs.activeID, firstID)
        model.requestClose(id: firstID)
        XCTAssertEqual(model.tabs.count, 1, "最后一个页签被关掉了")
        XCTAssertNil(model.pendingCloseTab, "最后一个页签不该弹确认——它根本不能关")
        XCTAssertNotNil(model.refusalHint, "拒绝关页签却没给任何说法")
        XCTAssertTrue(model.refusalHint?.contains(L(.terminalTabLastTabHint)) ?? false)

        model.pane(for: firstID).stop()
    }

    // MARK: - 探针三：页签头真的画出来（快照 + 断言）

    /// 三个页签（`zsh` / `dsh-tui` / `psql`，其中 `psql` 已退出）的工具条左侧那条 ——
    /// 需求主诉场景**长什么样**，以及「已退出」到了像素上。
    ///
    /// 为什么只拍页签条（不拍整块下方面板）：整块面板会把终端内容也拍进去 ⇒ 渲染时真开一条
    /// shell（离屏渲染里挂着的子进程谁都不想要）。页签条是**产品的真视图**（`TerminalTabsBar`
    /// 就是工具条里用的那一个），拍它即拍产品。
    @MainActor
    func testTabStripSnapshotShowsThreeSessionsAndExitedMark() throws {
        try XCTSkipUnless(UISnapshot.isEnabled, "快照要 DOYAH_UI_SNAPSHOT=1")

        let model = TerminalModel()
        model.rename(id: model.tabs.activeID, to: "zsh")
        let dshID = model.newTab()
        model.rename(id: dshID, to: "dsh-tui")
        let psqlID = model.newTab()
        model.rename(id: psqlID, to: "psql")
        model.markExited(id: psqlID, code: 0)
        model.select(id: dshID)

        // 前置：这一批拍的确实是「三个页签、中间那个是当前、第三个已退出」
        XCTAssertEqual(model.tabs.ids, [1, 2, 3])
        XCTAssertEqual(model.tabs.activeID, dshID)
        XCTAssertEqual(model.title(for: model.tabs.activeTab), "dsh-tui")
        XCTAssertEqual(model.exitedDetail(for: model.tabs.tab(id: psqlID)!), L(.terminalTabExitedCode, "0"))

        for scheme in [ColorScheme.light, .dark] {
            let pair = try UISnapshot.writeBothLanguages(
                "terminal-tabs-bar\(scheme == .dark ? "-dark" : "")",
                size: CGSize(width: 620, height: 30),
                scheme: scheme
            ) {
                HStack(spacing: Spacing.hair) {
                    TerminalTabsBar(terminal: model)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xs)
            }

            // 「已退出」必须真的进到这两遍的像素里（语言快照门禁的另一半：文案不同 ⇒ 像素不同）。
            // 注意比的是**含**：「已退出（代码 0）」也满足 —— 页签头上给的是带退出码的那一句。
            XCTAssertTrue(
                pair.records[0].localizedStrings.contains { $0.contains("已退出") },
                "中文那遍的页签条上没有「已退出」的文案"
            )
            XCTAssertTrue(
                pair.records[1].localizedStrings.contains { $0.contains("Exited") },
                "英文那遍的页签条上没有「Exited」的文案"
            )
            XCTAssertTrue(pair.textsDiffer, "两遍拿到的文案一样 —— 语言没下去")
        }
    }

    // MARK: - 探针四的宿主（真工具条离屏渲染用）

    private struct StripHost {
        let state: AppState
        let workspace: WorkspaceStore
        let tabs: WorkspaceTabsModel
        let terminal: TerminalModel
        let tab: QueryTab
    }

    /// 一个**不连库、不碰用户数据**的宿主：`AppState` 空连接 + 一个查询页签 + 一个终端模型。
    ///
    /// 用真 `AppState` / 真 `TerminalModel`（不是造一个假的状态对象）：工具条读的就是它们，
    /// 造假的只会让判据判在别的地方。
    @MainActor
    private func makeStripHost() throws -> StripHost {
        let scratch = UISnapshot.outputDirectory.deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        state.newQueryTab()
        return StripHost(
            state: state,
            workspace: WorkspaceStore.shared,
            tabs: WorkspaceTabsModel(
                store: WorkspaceHistoryStore(
                    fileURL: scratch.appendingPathComponent("terminal-strip-\(UUID().uuidString).json")
                )
            ),
            terminal: TerminalModel(),
            tab: try XCTUnwrap(state.activeQueryTab, "没拿到查询页签")
        )
    }

    /// 渲染一遍**真工具条**（`LowerPaneTabStrip` —— 产品里正在用的那一个）。
    ///
    /// 为什么能渲染它：工具条那一行是**独立视图**（`App/Views/LowerPaneTabStrip.swift`），
    /// 不带上下面板的内容半边 —— 那一半挂着 `TerminalHostView`，一渲染就会真开 shell。
    @MainActor
    private func renderStrip(
        _ name: String, host: StripHost, collapsed: Bool = false
    ) throws -> UISnapshot.LanguagePair {
        try UISnapshot.writeBothLanguages(name, size: Self.stripSize) {
            LowerPaneTabStrip(tab: host.tab, isCollapsed: collapsed)
                .snapshotEnvironment(
                    state: host.state,
                    workspace: host.workspace,
                    tabs: host.tabs,
                    terminal: host.terminal
                )
        }
    }

    /// 渲染一遍**终端二级条**（`TerminalSubToolbar` —— 终端页签自己那一条）。
    ///
    /// 「细分终端 title 在**左侧**」这条位置判据自 `T-1b`（2026-10-08）起落在**这里** —— 外层条上
    /// 已经没有页签头了（`T-1a` 移出）。和 `LowerPaneTabStrip` 同一条理由能离屏渲染：它长在终端
    /// 内容顶部，而整块面板一渲染会真开 shell。
    @MainActor
    private func renderSubToolbar(_ name: String, host: StripHost) throws -> UISnapshot.LanguagePair {
        try UISnapshot.writeBothLanguages(name, size: Self.stripSize) {
            TerminalSubToolbar()
                .snapshotEnvironment(
                    state: host.state,
                    workspace: host.workspace,
                    tabs: host.tabs,
                    terminal: host.terminal
                )
        }
    }

    /// 工具条那一行的尺寸（点）：一行的实际高度约 26pt，取 40 留余量。
    ///
    /// **同一把尺子量两条**：外层页签条（`LowerPaneTabStrip`）与终端二级条（`TerminalSubToolbar`）
    /// 用同一个尺寸离屏渲染，左右分带的像素判据才是「同一套量法」。
    private static let stripSize = CGSize(width: 900, height: 40)

    /// 「左半必须变」的**下限**（像素）。
    ///
    /// 来源（实测，第 96 轮，当时量的还是外层条）：3 页签 vs 1 页签，左半实测差异 **10984** 像素
    /// （同一轮右四分之一 = 0）。`T-1b` 把页签头搬进二级条之后量的是**二级条**，读数由本用例每次
    /// `print` 出来（读数即证据）。下限仍取 **400**：多出来的两个页签头各约 100pt 宽 × 26pt 高
    /// （2× 下 ≈ 200×52 px），单是第二个页签头就远超 400 —— 既挡得住「几乎没变」（把页签头挪到
    /// 右边时实测 **0**），也不吃排版微调带来的几像素漂移。上限不设：判据要的是「变了」。
    private static let minimumStripLeftDiff = 400

    // MARK: - 探针四：二级条那一行的版面（细分终端 title 在左、右侧状态不受页签数影响）

    /// 清单那一行（`FR-EDIT-29` 多会话）第 ① 条是句**版面**话：「细分 terminal 的页签头在**左侧**」。
    ///
    /// `T-1a`/`T-1b`（2026-10-08）把页签头从**外层**页签条搬进**终端二级条**
    /// （`App/Views/TerminalSubToolbar.swift`）之后，这条版面判据**只能**在二级条上成立 ——
    /// 外层条上已经没有页签头了。所以这里量的是**二级条**：
    ///
    /// · 渲染**真二级条**（`TerminalSubToolbar` —— 独立视图，能单独离屏渲染），页签从 1 个变 3 个
    ///   （其中一个已退出）⇒ **左半**必须变（页签头确实长在左半边）；
    /// · **右四分之一**必须**逐像素相同**（右侧的状态小字不受页签数影响 ⇒ 在右、没被挤动）。
    ///
    /// 同一条用例还判**反面**（`T-1b` 的层级）：**外层条上不许有页签头** —— 同一个宿主上页签从
    /// 1 个变 3 个，**外层页签条整张图必须逐像素相同**（页签头要是还长在这一行，页签数一变它必变）。
    @MainActor
    func testStripKeepsTabHeadersOnTheLeftAndRightButtonsInPlace() throws {
        try XCTSkipUnless(UISnapshot.isEnabled, "快照要 DOYAH_UI_SNAPSHOT=1")

        // **一个宿主装齐两态**：页签数是两个界面的唯一变量（别的都别动，否则像素差异归不到页签头上）。
        // 会话不启 ⇒ 两态的 `TerminalPaneStatus` 都只画「已停止」—— 右侧才谈得上「逐像素相同」。
        let host = try makeStripHost()
        host.state.lowerPaneTab = .terminal
        host.state.isLowerPaneMaximized = false

        // 甲：**一个页签**（= 现状）—— 二级条与外层条各拍一遍。
        let one = try renderSubToolbar("manual-check-terminal-subtoolbar-1tab", host: host)
        let outerOne = try renderStrip("manual-check-terminal-strip-1tab", host: host)

        // 乙：**三个页签**（`zsh` / `dsh-tui` / `psql`，其中 `psql` 已退出），当前是中间那个。
        //    与探针三同一个场景 —— 需求主诉场景就是「一个跑着 dsh-tui、另一个执行命令」。
        let firstID = host.terminal.tabs.activeID
        let secondID = host.terminal.newTab()
        let thirdID = host.terminal.newTab()
        host.terminal.rename(id: firstID, to: "zsh")
        host.terminal.rename(id: secondID, to: "dsh-tui")
        host.terminal.rename(id: thirdID, to: "psql")
        host.terminal.markExited(id: thirdID, code: 0)
        host.terminal.select(id: secondID)
        let three = try renderSubToolbar("manual-check-terminal-subtoolbar-3tabs", host: host)
        let outerThree = try renderStrip("manual-check-terminal-strip-3tabs", host: host)

        // 前置一：两遍**确实是两个界面状态**（否则下面的像素差异是幻觉）。
        XCTAssertNotEqual(
            Set(one.records[0].localizedStrings), Set(three.records[0].localizedStrings),
            "1 个页签与 3 个页签（含一个已退出）拿到的文案一样 —— 这一批拍的不是两个状态"
        )
        // 前置二：同宽同高、同语言（两遍都取 `records[0]` = 中文），才谈得上「分左右比」。
        XCTAssertEqual(three.records[0].width, one.records[0].width, "两遍的图宽不一样")
        XCTAssertEqual(three.records[0].height, one.records[0].height, "两遍的图高不一样")

        let pixelWidth = one.records[0].width
        let leftOne = try XCTUnwrap(
            UISnapshot.columnBand(ofPNGAt: one.records[0].file, fromLeading: 0, width: pixelWidth / 2),
            "取不到左半列带（图不在盘上？）"
        )
        let leftThree = try XCTUnwrap(
            UISnapshot.columnBand(ofPNGAt: three.records[0].file, fromLeading: 0, width: pixelWidth / 2)
        )
        let rightOne = try XCTUnwrap(
            UISnapshot.columnBand(
                ofPNGAt: one.records[0].file, fromLeading: pixelWidth * 3 / 4, width: pixelWidth / 4
            )
        )
        let rightThree = try XCTUnwrap(
            UISnapshot.columnBand(
                ofPNGAt: three.records[0].file, fromLeading: pixelWidth * 3 / 4, width: pixelWidth / 4
            )
        )

        // 判据 A：**左半必须变** —— 细分终端的页签头长在二级条的左半边。
        XCTAssertGreaterThan(leftOne.ink, 0, "左半一个字都没画 —— 判据的前提不成立")
        XCTAssertGreaterThan(rightOne.ink, 0, "右四分之一一个字都没画 —— 右侧状态小字不见了？")
        let leftDiff = try XCTUnwrap(UISnapshot.differingPixels(leftOne, leftThree))
        let rightDiff = try XCTUnwrap(UISnapshot.differingPixels(rightOne, rightThree))
        print("📐 二级条左半差异 \(leftDiff) 像素 / 右四分之一差异 \(rightDiff) 像素（3 页签 vs 1 页签）")
        XCTAssertGreaterThan(
            leftDiff, Self.minimumStripLeftDiff,
            "页签从 1 个变 3 个，左半只差 \(leftDiff) 像素 —— 页签头不在左半边？"
        )

        // 判据 B：**右四分之一必须逐像素相同** —— 右侧那点东西不受页签数影响。
        XCTAssertEqual(
            rightDiff, 0,
            "页签数一变右半也跟着变（\(rightDiff) 像素）—— 右侧被页签挤动了"
        )

        // 判据 C（`T-1b` 层级）：**外层页签条整张图逐像素相同** —— 页签头不在这一行。
        // 页签头要是还长在外层条上，页签 1 个变 3 个它必变；不变 = 「平级」那件事的回归钉。
        let outerOneBand = try XCTUnwrap(
            UISnapshot.columnBand(
                ofPNGAt: outerOne.records[0].file, fromLeading: 0, width: outerOne.records[0].width
            ),
            "取不到外层条整张图（图不在盘上？）"
        )
        let outerThreeBand = try XCTUnwrap(
            UISnapshot.columnBand(
                ofPNGAt: outerThree.records[0].file, fromLeading: 0, width: outerThree.records[0].width
            )
        )
        let outerDiff = try XCTUnwrap(UISnapshot.differingPixels(outerOneBand, outerThreeBand))
        print("📐 外层页签条整张图差异 \(outerDiff) 像素（3 页签 vs 1 页签 · 判「页签头不在这行」）")
        XCTAssertEqual(
            outerDiff, 0,
            "页签数一变外层页签条整张图也跟着变（\(outerDiff) 像素）—— 页签头又长回外层条了"
            + "（它只属于终端二级条 `TerminalSubToolbar`）"
        )
    }

    // MARK: - 探针四之二：外层条右侧只剩**窗口按钮**、且按**面板状态**齐备

    /// 口径①说「最外层 tab bar 最右侧只保留最大化、恢复、最小化折叠按钮」—— 机器判据此前只有
    /// 源码级符号表（少一个符号就报红）。这里补上**状态 → 应有哪些**这一半：同一排按钮在不同面板
    /// 状态下换的是**哪几个**。
    ///
    /// `T-1a`（2026-10-08）把子终端那几件移出外层条（终端页签条 / 状态小字 / 重启 shell / 清空日志），
    /// 于是本条的基线随之改变：**终端态不再 `requires: .terminalRestart`**、任何态都**不许**再出现
    /// `.lowerPaneClear`（清空日志归位到问题 / 输出两页的内容顶部，不在这一条里）。
    ///
    /// 判的是**渲染记录里的文案**（`L(...)` 在这一遍真的取到的值）—— 这几个 `help` 正是鼠标停上去时
    /// 用户看到的那句话：「按钮在不在」与「它说不说话」一起判。
    ///
    /// 两个方向都判：该有的必须有，**不该有的不许有**（外层条上冒出子终端那几件 = 层级串了）。
    @MainActor
    func testRightSideButtonsMatchThePanelState() throws {
        try XCTSkipUnless(UISnapshot.isEnabled, "快照要 DOYAH_UI_SNAPSHOT=1")

        struct Case {
            let name: String
            let tab: LowerPaneTab
            let collapsed: Bool
            let requires: [LKey]
            let forbids: [LKey]
        }

        let cases = [
            // 终端态（不折叠）：外层条右侧**只剩窗口按钮**（最大化 + 收起）。
            // 重启 shell 已随 `T-1a` 移出（归 `T-2` 的二级条四按钮），清空日志归内容顶部 —— 这一行都不该有。
            Case(
                name: "manual-check-terminal-strip-buttons-terminal",
                tab: .terminal, collapsed: false,
                requires: [.lowerPaneMaximize, .lowerPaneHide],
                forbids: [.terminalRestart, .lowerPaneClear, .lowerPaneExpand]
            ),
            // 问题态：右侧同样是窗口按钮；清空日志**不在这一行**（它归问题页的内容顶部）。
            Case(
                name: "manual-check-terminal-strip-problem",
                tab: .problem, collapsed: false,
                requires: [.lowerPaneMaximize, .lowerPaneHide],
                forbids: [.lowerPaneClear, .terminalRestart, .lowerPaneExpand]
            ),
            // 折叠的终端态：最大化 / 收起换成**向上的展开箭头**（那是把面板恢复出来的唯一入口），
            // 而终端那排（重启 shell）与清空日志都不属于这一行。
            Case(
                name: "manual-check-terminal-strip-collapsed",
                tab: .terminal, collapsed: true,
                requires: [.lowerPaneExpand],
                forbids: [.lowerPaneHide, .lowerPaneMaximize, .lowerPaneClear, .terminalRestart]
            ),
        ]

        for item in cases {
            let host = try makeStripHost()
            host.state.lowerPaneTab = item.tab
            host.state.isLowerPaneMaximized = false
            let pair = try renderStrip(item.name, host: host, collapsed: item.collapsed)
            let seen = Set(pair.records[0].localizedStrings)

            for key in item.requires {
                let expected = UISnapshot.localizedText(.simplifiedChinese) { L(key) }
                XCTAssertTrue(
                    seen.contains(expected),
                    "「\(item.name)」右侧少了这个动作：\(key.rawValue)（界面上该显示「\(expected)」）"
                )
            }
            for key in item.forbids {
                let unexpected = UISnapshot.localizedText(.simplifiedChinese) { L(key) }
                XCTAssertFalse(
                    seen.contains(unexpected),
                    "「\(item.name)」右侧**不该有**这个动作：\(key.rawValue)（界面上出现了「\(unexpected)」）"
                )
            }
        }
    }

    // MARK: - 探针五：⌘1…9 / ⌘⇧[ ⌘⇧] / 双击改名 —— 落到**对的会话**上（清单那一行 ③④）

    /// 清单那一行还剩两句人话没机器判：
    ///
    /// · ③「**切换 / 直选落到对的会话**」—— ㈠ 在 Core 里穷举了 `select(numbered:)` 的**判定**，
    ///   但「按了 ⌘2 之后，屏幕上那一条到底是哪条 PTY」只有**真开三条 shell** 才判得住；
    /// · ④「**改名只贴页签、终端里跑的东西不受影响**」—— 这一条更必须真跑：改名的实现稍微走偏
    ///   （顺手重启一次会话），标题照样回来、页面照样正常，**从界面上看不出任何异常**，
    ///   而用户正在跑的东西已经没了。
    ///
    /// 走的是**真按键路径**（`TerminalTabs.command(key:command:shift:)`）而不是直接调 `select`：
    /// 按键 → 动作 → 会话，中间任何一段接错，这里都判得出来。
    @MainActor
    func testNumberedSelectionAndRenameLandOnTheRightSession() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针真开 shell（取证专用）：DOYAH_UI_SNAPSHOT=1 才跑"
        )

        let model = TerminalModel()
        let firstID = model.tabs.activeID
        let secondID = model.newTab()
        let thirdID = model.newTab()
        let ids = [firstID, secondID, thirdID]
        let panes = ids.map { model.pane(for: $0) }
        for pane in panes { pane.startIfNeeded(columns: 80, rows: 24) }
        XCTAssertTrue(panes.allSatisfy(\.isRunning), "三个页签的 shell 没都起来")
        XCTAssertEqual(Set(panes.map(ObjectIdentifier.init)).count, 3, "三个页签拿到了同一个会话对象")

        // 每条会话留一个自己的记号 —— 用「会话有没有被重启」当尺子（重启了记号就没了）。
        let tokens = ["A", "B", "C"].map { "TAB\($0)-\(UUID().uuidString.prefix(4))" }
        for (pane, token) in zip(panes, tokens) { pane.send(text: "PROBE_TAB=\(token)\n") }
        for (pane, token) in zip(panes, tokens) {
            waitUntil("会话记住了自己的记号 \(token)") { self.text(of: pane).contains(token) }
        }

        // ③ · ⌘2 直选：落到**第二条**会话上（不是"随便换了个页签"）。
        model.perform(try XCTUnwrap(
            TerminalTabs.command(key: "2", command: true, shift: false), "⌘2 没被解析成页签动作"
        ))
        XCTAssertEqual(model.tabs.activeID, secondID, "⌘2 之后当前页签不是第二个")
        XCTAssertTrue(model.activePane === panes[1], "⌘2 之后屏幕上的不是第二条会话")
        XCTAssertTrue(text(of: panes[1]).contains(tokens[1]), "⌘2 之后看到的内容不是第二条会话的")

        // ⌘1 / ⌘3 各来一次（数字是一基、且落到首尾两条）……
        model.perform(try XCTUnwrap(TerminalTabs.command(key: "1", command: true, shift: false)))
        XCTAssertEqual(model.tabs.activeID, firstID)
        XCTAssertTrue(model.activePane === panes[0], "⌘1 之后屏幕上的不是第一条会话")
        model.perform(try XCTUnwrap(TerminalTabs.command(key: "3", command: true, shift: false)))
        XCTAssertEqual(model.tabs.activeID, thirdID)
        XCTAssertTrue(model.activePane === panes[2], "⌘3 之后屏幕上的不是第三条会话")

        // ……越界的 ⌘4 什么都不许动；⌘0 与 ⇧⌘1 根本不是页签键（⇧⌘T 归「数据任务」，
        // 页签不许偷别人的键）—— 解析必须是 nil，不是"落到某一条"。
        model.perform(try XCTUnwrap(TerminalTabs.command(key: "4", command: true, shift: false)))
        XCTAssertEqual(model.tabs.activeID, thirdID, "⌘4 越界了，却把当前页签换掉了")
        XCTAssertNil(TerminalTabs.command(key: "0", command: true, shift: false), "⌘0 不该是页签键")
        XCTAssertNil(TerminalTabs.command(key: "1", command: true, shift: true), "⇧⌘1 不该是页签键")

        // ⌘⇧[ / ⌘⇧] 前后切（含**绕回**）：从第三条往下一格应回到第一条。
        // 顺带认 `{` `}`：美式键盘上 ⇧⌘] 实际给的是 `}` —— 这是实测过的坑（Core 的注释里记着）。
        model.perform(try XCTUnwrap(
            TerminalTabs.command(key: "]", command: true, shift: true), "⌘⇧] 没被解析"
        ))
        XCTAssertEqual(model.tabs.activeID, firstID, "⌘⇧] 在最后一条上没有绕回第一条")
        XCTAssertTrue(model.activePane === panes[0])
        model.perform(try XCTUnwrap(
            TerminalTabs.command(key: "}", command: true, shift: true), "⌘⇧} 没被解析（美式键盘给的就是它）"
        ))
        XCTAssertEqual(model.tabs.activeID, secondID, "⌘⇧} 没落到第二条")
        model.perform(try XCTUnwrap(
            TerminalTabs.command(key: "[", command: true, shift: true), "⌘⇧[ 没被解析"
        ))
        XCTAssertEqual(model.tabs.activeID, firstID, "⌘⇧[ 没回到第一条")

        // ④ 改名只贴页签：第二条里真跑一个长命令（`sleep 30` 起着 `dsh-tui` 的作用），
        //    改名前后的**前台进程**必须一模一样 —— 改名不是重启。
        model.select(id: secondID)
        panes[1].send(text: "sleep 30\n")
        waitUntil("第二条会话的前台进程变成 sleep") {
            TerminalTabTitle.derive(fromExecutablePath: panes[1].foregroundProcessPath()) == "sleep"
        }
        let foregroundBefore = panes[1].foregroundProcessPath()
        let titleBefore = model.title(for: model.tabs.tab(id: secondID)!)

        model.rename(id: secondID, to: "日志")
        XCTAssertEqual(model.title(for: model.tabs.tab(id: secondID)!), "日志", "改名没贴到页签上")
        XCTAssertTrue(panes[1].isRunning, "改名把这条会话弄死了")
        XCTAssertEqual(
            panes[1].foregroundProcessPath(), foregroundBefore,
            "改名把会话重启了（前台进程换人了）—— 页签名字不该动到 PTY"
        )

        // 留空确定 = 清掉重命名，标题**回落**到前台进程名（回落规则在 Core）。
        model.rename(id: secondID, to: "   ")
        model.refreshForegroundProcesses()
        XCTAssertEqual(
            model.title(for: model.tabs.tab(id: secondID)!), "sleep",
            "留空之后标题没回落到前台进程名（改名前是「\(titleBefore)」）"
        )
        XCTAssertTrue(panes[1].isRunning, "清掉重命名这步把会话弄死了")

        for pane in panes { pane.stop() }
    }

    // MARK: - 探针四之三：二级条 / 外层条的**运行时元素 dump** + 截图（`T-1b` 判据 ① ③）

    /// 证据文件落在快照目录（`DOYAH_SNAPSHOT_DIR`）—— 与 `NoteSearchProbeTests` 同款的命名。
    /// 落地之后 **脚本 / 人可核**：`terminal-tabs-evidence-<case>.json`。
    private func writeEvidence(_ caseName: String, _ payload: [String: Any]) throws {
        let directory = UISnapshot.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var enriched = payload
        enriched["case"] = caseName
        enriched["snapshotDirectory"] = directory.path
        let data = try JSONSerialization.data(withJSONObject: enriched, options: [.prettyPrinted, .sortedKeys])
        try data.write(
            to: directory.appendingPathComponent("terminal-tabs-evidence-\(caseName).json"),
            options: .atomic
        )
    }

    /// `T-1b` 的判据 ① 要的是**运行时元素 dump**（不是源码级清单）：外层页签集合 + 二级条元素清单 +
    /// 按钮 label；判据 ③ 要**一张截图**（终端页签 + 二级条）。
    ///
    /// 两个来源都是运行时的：
    /// · **渲染观测**（`UISnapshot` 记录里的 `localizedStrings`）：这一遍 `L(...)` **真的取到了哪些字**
    ///   —— 文案没进这一遍，就不许出现在 dump 里（挡住「源码里有、画面上没有」）；
    /// · **真模型**（`TerminalModel` / `LowerPaneTab`）：页签标题、图标名、文案键取自产品自己的类型，
    ///   不是在这一条用例里另抄一份。
    ///
    /// 判据同时钉住**两个方向**：外层条那遍**不含**任何子终端文案（层级），二级条那遍**不含**任何
    /// 窗口按钮文案（两条各司其职）。
    ///
    /// 源码级接线清单另有（`Scripts/check-terminal-tabs.py` 的静态锚点）；这一份是**这一遍渲染的事实**。
    /// 截图 = 二级条那两张（中英各一）+ 外层条两张（层级对照）。
    @MainActor
    func testTerminalSubToolbarElementDumpAndScreenshot() throws {
        try XCTSkipUnless(UISnapshot.isEnabled, "快照要 DOYAH_UI_SNAPSHOT=1")

        // 需求主诉场景：`zsh` / `dsh-tui` / `psql`，当前是中间那个，`psql` 已退出。
        let host = try makeStripHost()
        host.state.lowerPaneTab = .terminal
        host.state.isLowerPaneMaximized = false
        let firstID = host.terminal.tabs.activeID
        let secondID = host.terminal.newTab()
        let thirdID = host.terminal.newTab()
        host.terminal.rename(id: firstID, to: "zsh")
        host.terminal.rename(id: secondID, to: "dsh-tui")
        host.terminal.rename(id: thirdID, to: "psql")
        host.terminal.markExited(id: thirdID, code: 0)
        host.terminal.select(id: secondID)

        // 判据 ③：截图（终端页签 + 二级条）—— 二级条那一对（中英各一）。外层条也拍一对（层级对照）。
        let sub = try renderSubToolbar("manual-check-terminal-subtoolbar", host: host)
        let outer = try renderStrip("manual-check-terminal-strip", host: host)

        func zh(_ key: LKey) -> String { UISnapshot.localizedText(.simplifiedChinese) { L(key) } }
        func en(_ key: LKey) -> String { UISnapshot.localizedText(.english) { L(key) } }

        let subObserved = Set(sub.records[0].localizedStrings)
        let outerObserved = Set(outer.records[0].localizedStrings)

        // ---- 元素 dump 的四块 ----
        // ① 外层页签集合：四个下方面板页签（符号 + 中英标题）。
        let outerTabs: [[String: Any]] = LowerPaneTab.allCases.map {
            ["symbol": $0.symbolName, "zh": zh($0.textKey), "en": en($0.textKey)]
        }
        // ② 外层条右侧的窗口按钮（口径①：只剩最大化 / 收起 / 折叠态展开箭头）。
        let windowButtons: [[String: Any]] = [
            ["symbol": "rectangle.expand.vertical", "helpZH": zh(.lowerPaneMaximize), "helpEN": en(.lowerPaneMaximize)],
            ["symbol": "chevron.down", "helpZH": zh(.lowerPaneHide), "helpEN": en(.lowerPaneHide)],
            ["symbol": "chevron.up", "helpZH": zh(.lowerPaneExpand), "helpEN": en(.lowerPaneExpand)],
        ]
        // ③ 二级条元素清单：左侧细分终端 title 列表 + 「已退出」标记 + 右侧状态小字。
        let subElements: [[String: Any]] = [
            ["role": "tabs", "symbol": "terminal", "titles": host.terminal.tabs.tabs.map { host.terminal.title(for: $0) }],
            ["role": "exitedMark", "zh": zh(.terminalTabExited), "en": en(.terminalTabExited)],
            ["role": "status", "zh": zh(.terminalStopped), "en": en(.terminalStopped)],
        ]
        // ④ 二级条上的按钮 label（新建页签 / 关闭页签）。
        let subButtons: [[String: Any]] = [
            ["role": "newTab", "symbol": "plus", "labelZH": zh(.terminalTabNew), "labelEN": en(.terminalTabNew),
             "helpZH": "\(zh(.terminalTabNew))（⌘T）"],
            ["role": "closeTab", "symbol": "xmark", "labelZH": zh(.terminalTabClose), "labelEN": en(.terminalTabClose)],
        ]

        // ---- 前置：这一批拍的确实是那个场景 ----
        XCTAssertEqual(host.terminal.tabs.ids, [firstID, secondID, thirdID])
        XCTAssertEqual(host.terminal.tabs.activeID, secondID)
        XCTAssertEqual((subElements[0]["titles"] as? [String]) ?? [], ["zsh", "dsh-tui", "psql"],
                       "二级条左侧的细分终端 title 列表不是那三个")

        // ---- 二级条那遍：状态小字 / 已退出 / 两个按钮的 label 真的进了这一遍 ----
        // 注意：观测到的是 **`L(...)` 取到的值**，「新建终端页签」在界面上还带着 `（⌘T）` 后缀 ——
        // 那个后缀是源码里的字符串插值拼出来的（不是语言表里的一条），这一层观测不到，见 dump 的 `helpZH`。
        for (label, text) in [
            ("状态小字", zh(.terminalStopped)),
            ("已退出标记", zh(.terminalTabExited)),
            ("新建页签按钮", zh(.terminalTabNew)),
            ("关闭页签按钮", zh(.terminalTabClose)),
        ] {
            XCTAssertTrue(subObserved.contains(text), "二级条这一遍没画「\(label)」（应显示「\(text)」）")
        }
        // ---- 二级条那遍**不许**出现窗口按钮的文案（层级：那是外层条的事）----
        for (label, text) in [
            ("最大化", zh(.lowerPaneMaximize)),
            ("收起面板", zh(.lowerPaneHide)),
            ("展开面板", zh(.lowerPaneExpand)),
        ] {
            XCTAssertFalse(subObserved.contains(text), "二级条这一遍出现了外层条才有的「\(label)」—— 层级串了")
        }

        // ---- 外层条那遍：四个面板页签 + 两个窗口按钮文案都在 ----
        for tab in LowerPaneTab.allCases {
            XCTAssertTrue(outerObserved.contains(zh(tab.textKey)), "外层条这一遍没画出页签「\(zh(tab.textKey))」")
        }
        XCTAssertTrue(outerObserved.contains(zh(.lowerPaneMaximize)), "外层条这一遍没有最大化按钮")
        XCTAssertTrue(outerObserved.contains(zh(.lowerPaneHide)), "外层条这一遍没有收起按钮")

        // ---- 外层条那遍**不许**出现任何子终端文案（层级断言：判据①的运行时那一半）----
        let forbiddenKeys: [(String, LKey)] = [
            ("已退出标记", .terminalTabExited),
            ("状态小字", .terminalStopped),
            ("新建页签", .terminalTabNew),
            ("关闭页签", .terminalTabClose),
            ("重新开始 shell", .terminalRestart),
            ("清空", .lowerPaneClear),
        ]
        let leaked = forbiddenKeys.compactMap { outerObserved.contains(zh($0.1)) ? $0.0 : nil }
        XCTAssertTrue(
            leaked.isEmpty,
            "外层页签条这一遍出现了子终端项 \(leaked)：它们属于终端二级条 / 问题·输出内容顶部，不属于这一行"
        )

        // ---- 落盘：运行时元素 dump（脚本 / 人可核）----
        try writeEvidence("elements", [
            "outerStripTabs": outerTabs,
            "outerStripWindowButtons": windowButtons,
            "outerStripObservedStrings": outer.records[0].localizedStrings,
            "subToolbarElements": subElements,
            "subToolbarButtons": subButtons,
            "subToolbarObservedStrings": sub.records[0].localizedStrings,
            "layerForbiddenLeakedIntoOuterStrip": leaked,
            "screenshots": [
                sub.records[0].file, sub.records[1].file,
                outer.records[0].file, outer.records[1].file,
            ],
        ])
        print("🧾 运行时元素 dump → \(UISnapshot.outputDirectory.path)/terminal-tabs-evidence-elements.json")
    }
}
