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
}
