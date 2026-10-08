import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 终端**二级工具条右侧那四枚常用动作**的 App 侧探针（人类主人 2026-10-08 原话 · 片 `T-2`）。
///
/// ## 判的是什么
///
/// 人类主人那一句原话把四枚按钮的**语义**写死了：
///
/// > 「右侧是常用的工具按钮，比如一键启动 dsh-tui、Hermes，**清除终端会话窗口内容**，**重启终端**」
///
/// 而门禁（`Scripts/check-terminal-tabs.py`）只能判「这四枚在源码里成对存在」——
/// 「按钮在」不等于「点下去真的起了 dsh 终端 / 真的只擦屏幕 / 真的换了一条命」。
/// 前门补判据（`T-20261008-026`/`-027`）把这一点写得很直白：
/// **「一键启动 dsh」点击后确实起了一个 dsh 终端（有回显 / 有进程读数）—— 只出现按钮不算过。**
///
/// 所以这个文件把四枚的**行为**在离屏里跑成断言：
///
/// ① **一键启动**：新建一个页签 → 新页签的 `title` = 预设名 → 会话起来后**前台进程真的换人**
///    （不再是 shell）+ 屏幕上有回显（`dsh-tui` / `hermes` 各一遍）；
/// ② **清除会话窗口内容**：缓冲行数从 >0 变成 **0**，而 pid 不变、会话仍在跑（**只擦屏幕**）；
/// ③ **重启终端**：先弹确认（`pendingRestartTab` 立起来、pid **一个字节都没动**）→
///    确认之后 **pid 换人**（旧 ≠ 新）、页签还在；
/// ④ **二级条的版面**：渲染**真视图**（`TerminalSubToolbar` 就是产品里用的那一个），
///    页签 1 个 → 3 个时**左半必须变、右四分之一逐像素不变** —— 右侧那四枚按钮在右、且不被页签挤动。
///
/// ## 口径与边界（如实登记）
///
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 它**真开 shell**，与快照同一条纪律：
///   取证才跑、不进每轮门禁；
/// · **「前台进程名 = dsh-tui」这半条本机做不到**（实测，2026-10-08）：`dsh-tui` 是
///   `#!/usr/bin/env node`、`hermes` 是 `exec … python3` —— 前台进程组的可执行路径是
///   `node` / `python3`。所以「跑的是不是它」由**两件事**读出来：页签名（预设直接给）
///   与「前台进程换人了」（`foregroundProcessPath()` 不再是 shell）。**不假装**读到了那个名字；
/// · 不判外观（四枚图标长什么样归快照读图）；不判真鼠标点击（那归真人点验，
///   这里调的是按钮**接到的那同一个方法**：`TerminalModel.launchTab` / `clearActiveBuffer` /
///   `requestRestart`）。
final class TerminalSubToolbarProbeTests: XCTestCase {

    // MARK: - 工具

    /// 把一屏网格读成文本（与视图绘制用的是同一份数据：`displayLines()`）。
    @MainActor
    private func text(of pane: TerminalPane) -> String {
        pane.displayLines()
            .map { $0.map(\.displayText).joined() }
            .joined(separator: "\n")
    }

    /// 等到条件成立 —— 会话输出在主队列上派发，所以转主运行循环而不是 `sleep`。
    @MainActor
    @discardableResult
    private func waitUntil(
        _ description: String, timeout: TimeInterval = 20, _ condition: () -> Bool
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

    /// 前台进程的**可执行名**（标题推导用的那一步）；查不到 = nil。
    @MainActor
    private func foregroundName(of pane: TerminalPane) -> String? {
        TerminalTabTitle.derive(fromExecutablePath: pane.foregroundProcessPath())
    }

    /// 读数**落盘**。
    ///
    /// 为什么要落盘（实测 2026-10-08）：`swift test`（Xcode 构建系统那条路）**不把用例的 `print`
    /// 转发到终端** —— 屏幕上什么都看不到，而「读数」正是本片判据③④⑤要交的东西。
    /// 所以读数一律写进快照目录下的一份文本：前门要的「行为读数 / 界面元素 dump」是**盘上的东西**。
    @MainActor
    private func record(_ line: String) {
        let url = UISnapshot.outputDirectory.appendingPathComponent("terminal-subtoolbar-readings.txt")
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? (existing + "[\(stamp)] \(line)\n").write(to: url, atomically: true, encoding: .utf8)
        print(line)
    }

    private var shellName: String {
        TerminalTabTitle.derive(fromExecutablePath: TerminalSession.defaultShell()) ?? "zsh"
    }

    // MARK: - 探针一：一键启动（两枚预设各起一条真会话）

    /// 判据①②③里的第 ① 条：**「一键启动 dsh」点击后确实起了一个 dsh 终端**。
    ///
    /// 两枚预设走**同一条**代码路径（`TerminalModel.launchTab` → `TerminalPane.launch` →
    /// 会话起来那一刻把那一行送进 PTY），所以两枚一起判 —— 只判一枚的话，
    /// 另一枚的名字 / 命令写错了（`hermes` 写成 `Hermes`）不会被发现。
    @MainActor
    func testLaunchButtonsStartRealSessionsAndNameTheirTabs() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针真开 shell（取证专用）：DOYAH_UI_SNAPSHOT=1 才跑"
        )

        let model = TerminalModel()
        let firstID = model.tabs.activeID
        model.activePane.startIfNeeded(columns: 80, rows: 24)
        XCTAssertTrue(model.activePane.isRunning, "第一条会话没起来（后面的判据都失去前提）")

        for preset in TerminalLaunchCommand.allCases {
            let before = model.tabs.count
            let id = model.launchTab(preset)

            // ① 新会话进集合、成为当前页签
            XCTAssertEqual(model.tabs.count, before + 1, "一键启动没有新建页签")
            XCTAssertEqual(model.tabs.activeID, id, "一键启动之后当前页签不是它")
            XCTAssertEqual(
                model.title(for: model.tabs.activeTab), preset.tabTitle,
                "新页签的标题不是预设名 —— 用户点的是「一键启动 \(preset.rawValue)」"
            )

            // ② 会话起来之后，那一行命令真的送进了 PTY（前台进程换人 + 屏幕有回显）
            let pane = model.pane(for: id)
            pane.startIfNeeded(columns: 80, rows: 24)
            XCTAssertTrue(pane.isRunning, "\(preset.rawValue)：新页签的 shell 没起来")
            record("🚀 一键启动 \(preset.rawValue)：会话已起 pid=\(pane.processIdentifier)")

            let deadline = Date().addingTimeInterval(25)
            var samples: [String] = []
            var tookOver = false
            while Date() < deadline {
                let name = foregroundName(of: pane) ?? "nil"
                samples.append(
                    "前台=\(name) 路径=\(pane.foregroundProcessPath() ?? "nil")"
                        + " 缓冲非空行数=\(pane.bufferLineCount) 会话跑着=\(pane.isRunning)"
                )
                if name != "nil", name != shellName, pane.bufferLineCount > 0 {
                    tookOver = true
                    break
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            }
            // 采样时间线落盘（每 4 个采样记一条 —— 够看清楚过程，又不淹掉文件）。
            for (index, sample) in samples.enumerated() where index % 4 == 0 || index == samples.count - 1 {
                record("    t≈\(Double(index) * 0.5)s \(sample)")
            }
            let reading = "前台进程可执行名 = \((foregroundName(of: pane)) ?? "nil")"
                + " / 路径 = \(pane.foregroundProcessPath() ?? "nil")"
                + " / 缓冲非空行数 = \(pane.bufferLineCount)"
                + " / pid = \(pane.processIdentifier)"
            record("🚀 一键启动 \(preset.rawValue) 终读：\(reading)")
            XCTAssertTrue(tookOver, "\(preset.rawValue)：命令送出去了，但前台一直还是 shell（\(reading)）")
            XCTAssertFalse(
                text(of: pane).contains("command not found"),
                "\(preset.rawValue)：shell 回的是「command not found」—— 这台机器上没装它，"
                    + "按钮本身是对的，但这一遍判不出「真起了那个终端」"
            )

            XCTAssertGreaterThan(
                pane.bufferLineCount, 0,
                "\(preset.rawValue)：屏幕上一个字都没有 —— 没有回显（\(reading)）"
            )
            // 屏幕上确实是**它**在画（前几行落进读数文件给人看；判据只要求有内容）。
            record("🖥  \(preset.rawValue) 屏幕首几行：\n" + text(of: pane).split(separator: "\n").prefix(6)
                .map { "    |\($0)" }.joined(separator: "\n"))

            model.select(id: id)
        }

        XCTAssertEqual(model.tabs.count, 3, "两条预设各该留下一个页签")
        for tab in model.tabs.tabs where tab.id != firstID {
            model.pane(for: tab.id).stop()
        }
        model.pane(for: firstID).stop()
    }

    // MARK: - 探针二：清除会话窗口内容（只擦屏幕，不杀进程）

    @MainActor
    func testClearBufferWipesTheScreenButKeepsTheSession() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针真开 shell（取证专用）：DOYAH_UI_SNAPSHOT=1 才跑"
        )

        let model = TerminalModel()
        let pane = model.activePane
        pane.startIfNeeded(columns: 80, rows: 24)
        XCTAssertTrue(pane.isRunning)

        // 先让屏幕上真的有东西（40 行 ⇒ 一定进了回滚区，不是只擦可见屏）。
        pane.send(text: "for i in $(seq 1 40); do echo BUFFER-LINE-$i; done\n")
        waitUntil("屏幕上出现 BUFFER-LINE-40") { self.text(of: pane).contains("BUFFER-LINE-40") }
        waitUntil("回滚区里也有内容") { pane.maxScrollOffset > 0 }

        let beforeLines = pane.bufferLineCount
        let beforePID = pane.processIdentifier
        let beforeScrollback = pane.screen.scrollbackCount
        record("🧽 清屏前：缓冲非空行数 \(beforeLines) / 回滚区 \(beforeScrollback) 行 / pid \(beforePID)")

        model.clearActiveBuffer()

        let afterLines = pane.bufferLineCount
        record("🧽 清屏后：缓冲非空行数 \(afterLines) / 回滚区 \(pane.screen.scrollbackCount) 行 / pid \(pane.processIdentifier)")
        XCTAssertGreaterThan(beforeLines, 0, "清屏前屏幕上本来就没内容 —— 这条判据失去前提")
        XCTAssertEqual(afterLines, 0, "清完之后缓冲里还剩 \(afterLines) 行非空内容")
        XCTAssertEqual(pane.screen.scrollbackCount, 0, "回滚区没擦掉（只擦了可见屏）")

        // **不杀进程**：会话还在跑，进程号一个字节都没动。
        XCTAssertTrue(pane.isRunning, "清屏把会话弄死了 —— 它只该擦屏幕")
        XCTAssertEqual(pane.processIdentifier, beforePID, "清屏换了一条会话（pid 变了）")
        XCTAssertEqual(model.tabs.count, 1, "清屏动了页签集合")

        // 清完之后还能接着用（前台程序没被打断）。
        pane.send(text: "echo AFTER-CLEAR-OK\n")
        waitUntil("清屏之后会话还能执行命令") { self.text(of: pane).contains("AFTER-CLEAR-OK") }

        pane.stop()
    }

    // MARK: - 探针三：重启终端（先问一句 → 确认 → 换一条命）

    @MainActor
    func testRestartAsksFirstThenChangesTheProcessIdentifier() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针真开 shell（取证专用）：DOYAH_UI_SNAPSHOT=1 才跑"
        )

        let model = TerminalModel()
        let id = model.tabs.activeID
        let pane = model.activePane
        pane.startIfNeeded(columns: 80, rows: 24)
        XCTAssertTrue(pane.isRunning)
        let beforePID = pane.processIdentifier
        XCTAssertGreaterThan(beforePID, 0, "会话起来了却拿不到 pid —— 重启判据失去读数")

        // ① **先问一句**：请求重启只是把确认目标立起来，**什么都没有动**。
        model.requestRestart()
        XCTAssertEqual(model.pendingRestartTab, id, "会话在跑，重启却连问都不问")
        XCTAssertEqual(pane.processIdentifier, beforePID, "还没确认就把旧会话杀了 —— 静默杀进程")
        XCTAssertTrue(pane.isRunning)

        // 用户点了「取消」：状态回原位，会话还好好的。
        model.cancelRestart()
        XCTAssertNil(model.pendingRestartTab)
        XCTAssertEqual(pane.processIdentifier, beforePID)
        XCTAssertTrue(pane.isRunning)

        // ② 再来一次并**确认**：pid 必须换人，页签留着。
        model.requestRestart()
        model.confirmRestart()
        XCTAssertNil(model.pendingRestartTab, "确认之后确认目标没清掉（弹窗会再弹一次）")

        let afterPID = pane.processIdentifier
        record("🔁 重启：旧 pid \(beforePID) → 新 pid \(afterPID)（页签 id \(id) 不变）")
        XCTAssertTrue(pane.isRunning, "重启没有真的把 shell 拉起来")
        XCTAssertGreaterThan(afterPID, 0, "重启之后拿不到 pid")
        XCTAssertNotEqual(afterPID, beforePID, "重启前后 pid 一样 —— 会话根本没换")
        XCTAssertEqual(model.tabs.ids, [id], "重启动了页签集合")

        // ③ 二次确认框那一族文案**中英都在**（弹窗的读数：界面上会显示这四句）。
        //    两种语言都**显式**取（`localizedText`）—— 不靠环境语言：这台机器上的用户偏好
        //    是哪个语言都可能，读数里必须写清楚这一句是哪一种语言。
        let keys: [LKey] = [
            .terminalRestartConfirmTitle, .terminalRestartConfirmMessage,
            .terminalRestartConfirmAction, .commonCancel,
        ]
        for key in keys {
            for language in [AppLanguage.simplifiedChinese, .english] {
                let line = UISnapshot.localizedText(language) { L(key) }
                XCTAssertFalse(
                    line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "弹窗文案有空串：\(key.rawValue) / \(language.rawValue)"
                )
            }
        }
        for language in [AppLanguage.simplifiedChinese, .english] {
            let dump = UISnapshot.localizedText(language) {
                keys.map { "\($0.rawValue)=「\(L($0))」" }.joined(separator: " / ")
            }
            record("🪟 重启确认框（\(language.rawValue)）：\(dump)")
        }

        pane.stop()
    }

    // MARK: - 探针四：二级条的版面（左 = title 列表；右 = 四枚按钮）

    /// 一个**不连库、不碰用户数据**的宿主（与 `TerminalTabsProbeTests` 同一个形状）。
    @MainActor
    private func makeHost() throws -> (AppState, WorkspaceStore, WorkspaceTabsModel, TerminalModel) {
        let scratch = UISnapshot.outputDirectory.deletingLastPathComponent()
            .appendingPathComponent("ui-snapshot-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let state = AppState()
        state.connections = []
        state.selectedConnectionID = nil
        state.newQueryTab()
        return (
            state,
            WorkspaceStore.shared,
            WorkspaceTabsModel(
                store: WorkspaceHistoryStore(
                    fileURL: scratch.appendingPathComponent("terminal-subtoolbar-\(UUID().uuidString).json")
                )
            ),
            TerminalModel()
        )
    }

    private static let toolbarSize = CGSize(width: 900, height: 34)

    /// 渲染一遍**真二级条**（`TerminalSubToolbar` —— 产品里正在用的那一个）。
    ///
    /// 能单独离屏渲染的理由与 `LowerPaneTabStrip` 相同：这一条只带页签头 + 状态小字 + 四枚按钮，
    /// **不带**终端内容那半边（那半边挂着 `TerminalHostView`，一渲染就真开一条 shell）。
    @MainActor
    private func renderToolbar(
        _ name: String,
        host: (AppState, WorkspaceStore, WorkspaceTabsModel, TerminalModel)
    ) throws -> UISnapshot.LanguagePair {
        try UISnapshot.writeBothLanguages(name, size: Self.toolbarSize) {
            TerminalSubToolbar()
                .snapshotEnvironment(
                    state: host.0, workspace: host.1, tabs: host.2, terminal: host.3
                )
        }
    }

    /// 把快照按**像素**切一段另存（判据④要的「左（title 列表）/ 右（四个按钮）各一张」）。
    @MainActor
    private func writeCrop(ofPNGAt path: String, fromLeading: Int, width: Int, named name: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), "打不开快照 \(path)")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), "读不出快照 \(path)")
        let rect = CGRect(x: fromLeading, y: 0, width: width, height: image.height)
        let cropped = try XCTUnwrap(image.cropping(to: rect), "切不出这一段（\(rect)）")
        let data = try XCTUnwrap(
            NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]),
            "编码不出 PNG"
        )
        let out = UISnapshot.outputDirectory.appendingPathComponent("\(name).png")
        try data.write(to: out)
        return out.path
    }

    /// 判据④：**左半变 / 右四分之一不变** + 四枚按钮的提示文案真的进了这一遍渲染记录。
    ///
    /// 为什么是「分左右」比而不是「整张图不一样」：页签头挂到右边、或右侧那排按钮被页签挤走，
    /// 都会让整张图变 —— 只有分开判才判得开这两件事（与第 96 轮那条像素判据同一个理由）。
    @MainActor
    func testSubToolbarKeepsTitlesOnTheLeftAndFourButtonsInPlace() throws {
        try XCTSkipUnless(UISnapshot.isEnabled, "快照要 DOYAH_UI_SNAPSHOT=1")

        // 甲：**一个页签**（= 现状）。**不启动会话** —— 页签没起来时状态小字写「已停止」，
        // 于是中英两遍的像素必然不同（语言门禁的另一半）。
        let one = try makeHost()
        let onePair = try renderToolbar("manual-check-terminal-subtoolbar-1tab", host: one)

        // 乙：**三个页签**（`zsh` / `dsh-tui` / `psql`，其中 `psql` 已退出），当前是中间那个。
        let three = try makeHost()
        let firstID = three.3.tabs.activeID
        let secondID = three.3.newTab()
        let thirdID = three.3.newTab()
        three.3.rename(id: firstID, to: "zsh")
        three.3.rename(id: secondID, to: "dsh-tui")
        three.3.rename(id: thirdID, to: "psql")
        three.3.markExited(id: thirdID, code: 0)
        three.3.select(id: secondID)
        let threePair = try renderToolbar("manual-check-terminal-subtoolbar-3tabs", host: three)

        // 前置一：两遍确实是两个界面状态。
        XCTAssertNotEqual(
            Set(onePair.records[0].localizedStrings), Set(threePair.records[0].localizedStrings),
            "1 个页签与 3 个页签（含一个已退出）拿到的文案一样 —— 这一批拍的不是两个状态"
        )
        // 前置二：四枚动作的 `.help()` 文案真的在这一遍里取到了（「按钮在」的渲染侧读数）。
        let seen = Set(threePair.records[0].localizedStrings)
        let expectedHelps: [(String, LKey)] = [
            ("terminal-launch-dsh-tui", .terminalLaunchDshTUI),
            ("terminal-launch-hermes", .terminalLaunchHermes),
            ("terminal-clear-buffer", .terminalClearBuffer),
            ("terminal-restart", .terminalRestartTab),
        ]
        var missing: [String] = []
        for (identifier, key) in expectedHelps {
            let text = UISnapshot.localizedText(.simplifiedChinese) { L(key) }
            if !seen.contains(text) { missing.append("\(identifier) → 「\(text)」") }
        }
        XCTAssertTrue(missing.isEmpty, "右侧四枚动作的提示文案没进渲染记录：\(missing)")
        record("🧩 二级条右侧四枚（标识符 → 提示）：\n"
            + expectedHelps.map { entry -> String in
                let help = UISnapshot.localizedText(.simplifiedChinese) { L(entry.1) }
                return "    \(entry.0) → \(help)"
            }.joined(separator: "\n"))

        // 判据 A：左 / 右两段都有墨（二级条两侧都画了东西）。
        let pixelWidth = onePair.records[0].width
        let leftOne = try XCTUnwrap(
            UISnapshot.columnBand(ofPNGAt: onePair.records[0].file, fromLeading: 0, width: pixelWidth / 2)
        )
        let leftThree = try XCTUnwrap(
            UISnapshot.columnBand(ofPNGAt: threePair.records[0].file, fromLeading: 0, width: pixelWidth / 2)
        )
        let rightOne = try XCTUnwrap(
            UISnapshot.columnBand(
                ofPNGAt: onePair.records[0].file, fromLeading: pixelWidth * 3 / 4, width: pixelWidth / 4
            )
        )
        let rightThree = try XCTUnwrap(
            UISnapshot.columnBand(
                ofPNGAt: threePair.records[0].file, fromLeading: pixelWidth * 3 / 4, width: pixelWidth / 4
            )
        )
        XCTAssertGreaterThan(leftOne.ink, 0, "左半一个字都没画 —— 页签头不见了？")
        XCTAssertGreaterThan(rightOne.ink, 0, "右四分之一一个字都没画 —— 右侧那四枚按钮不见了？")

        let leftDiff = try XCTUnwrap(UISnapshot.differingPixels(leftOne, leftThree))
        let rightDiff = try XCTUnwrap(UISnapshot.differingPixels(rightOne, rightThree))
        record("📐 二级条左半差异 \(leftDiff) 像素 / 右四分之一差异 \(rightDiff) 像素（3 页签 vs 1 页签）")
        XCTAssertGreaterThan(
            leftDiff, 400,
            "页签从 1 个变 3 个，左半只差 \(leftDiff) 像素 —— 细分终端的 title 不在左半边？"
        )
        XCTAssertEqual(
            rightDiff, 0,
            "页签数一变右半也跟着变（\(rightDiff) 像素）—— 右侧那四枚按钮被页签挤动了"
        )

        // 判据 B（判据④的交付物）：左 / 右各切一张出来另存。
        let leftPath = try writeCrop(
            ofPNGAt: threePair.records[0].file, fromLeading: 0, width: pixelWidth / 2,
            named: "manual-check-terminal-subtoolbar-3tabs-left"
        )
        let rightPath = try writeCrop(
            ofPNGAt: threePair.records[0].file, fromLeading: pixelWidth * 3 / 4, width: pixelWidth / 4,
            named: "manual-check-terminal-subtoolbar-3tabs-right"
        )
        record("🖼  二级条左（title 列表）：\(leftPath)")
        record("🖼  二级条右（四枚按钮）：\(rightPath)")
        for entry in threePair.records {
            record("🖼  整条（\(entry.language)）：\(entry.file)")
        }
    }
}
