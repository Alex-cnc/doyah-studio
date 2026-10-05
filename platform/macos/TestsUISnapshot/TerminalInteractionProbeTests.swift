import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 终端交互三面的 **App 内探针**（队列 `L-90` ㈠）—— 开发循环第 108 轮。
///
/// ## 为什么走「App 内探针」而不是真鼠标 / 真键盘
///
/// 清单 §0.2 把 5 条判进 D 类（`CGEvent` 模拟 + 截屏判读），前置是 TCC 授权；查实本机形态后那条路
/// 走不通（入口 `hermes` 是未签名 shell 脚本、真正执行者是自装未签名 python、launchd 还夹了一层
/// `osascript` ⇒ TCC 归因对象不确定，工具链一升级授权即失效）。所以改走**自己点自己**：把合成的
/// `NSEvent` 直接交给真 `TerminalHostView` 的方法（`mouseDown` / `mouseDragged` / `scrollWheel` /
/// `rightMouseDown` / `keyDown`）—— 合成事件只有**跨进程投递**才需要辅助功能授权。
///
/// ## 判据的形状（端到端：判字节去了谁手里，不判代码怎么写）
///
/// 被测的字节出口是**真 PTY**：终端里跑 `cat -v`（把收到的字节按可见形式打回屏幕），于是
/// 「视图到底把什么字节送给了前台程序」变成**屏幕上读得出来的事实**。行规程要 `-icanon`
/// （默认规程会把没有换行的报文扣在缓冲里不交给 `cat`，那是本次实测踩到的第一坑），
/// 鼠标上报模式（`?1002h` / `?1006h`）与 DECCKM（`?1h`）都由**程序自己**经真 PTY 置位
/// （`printf` 那一段）—— 探针注入的只有「点了哪里」，模式位是程序的。
///
/// 三条：
/// ① **鼠标上报**：前台接管鼠标时按下 / 拖动 / 滚轮真的转发（屏幕上出现 SGR 报文，且本机没有选区、
///    没有滚回滚区）；按住 **⌥** 拖动必须归本机（出现选区、报文不再增加）；
/// ② **方向键 DECCKM**：`?1h` 置位时 ↑ 走 SS3（屏幕上是 `^[OA`），复位后走 CSI（`^[[A`）；
/// ③ **右键归属**：前台接管鼠标时菜单仍归本机（`menu(for:)` 五项齐备且指向产品自己的动作），
///    只有「接管 + ⌥」才转发给程序（报文里出现 button code 2）。

/// ## 口径与边界（如实登记）
///
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 它真开 shell，与快照同一条纪律：取证才跑、
///   不进每轮门禁；跑法 `./Scripts/verify-ui-interactions.sh`（它会核对「跑了几条、有没有跳过」）；
/// · **右键「不按 ⌥」那一面不派发事件**：`super.rightMouseDown` 会真的弹出菜单并进入跟踪循环，
///   无人值守下会挂住 —— 那一面判的是「菜单备好了且五项指向产品自己的动作」＋ 入口脚本里的源锚点
///   （视图先问路由、再决定弹不弹）；「按 ⌥ 转发」那一面是**真派发**的；
/// · 「自己点自己」判得到「视图拿到这个事件之后做什么」，判不到「系统把事件送到这个视图」；
/// · 快照（每条一张）与「多光标 / 对象树逐行右键」两条留到 **㈡**。
final class TerminalInteractionProbeTests: XCTestCase {

    // MARK: - 工具

    /// 等到条件成立（默认 10 秒）。会话输出与前台进程查询都在主队列上，所以转主运行循环而不是 `sleep`。
    @discardableResult
    @MainActor
    private func waitUntil(_ description: String, timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        if condition() { return true }
        XCTFail("等不到：\(description)")
        return false
    }

    /// 屏幕上那一屏文本（按行拼；人读 / 断言 `contains` 用）。
    @MainActor
    private func text(of pane: TerminalPane) -> String {
        pane.displayLines().map { $0.map(\.displayText).joined() }.joined(separator: "\n")
    }

    /// 同样那一屏、但**行与行之间不加分隔**（报文在右边界会折行，加了分隔就断在中间）。
    @MainActor
    private func grid(of pane: TerminalPane) -> String {
        pane.displayLines().map { $0.map(\.displayText).joined() }.joined()
    }

    /// 前台进程名（`tcgetpgrp` 那条路，与页签标题同源）。取不到时是 `nil`。
    @MainActor
    private func foreground(_ pane: TerminalPane) -> String? {
        TerminalTabTitle.derive(fromExecutablePath: pane.foregroundProcessPath())
    }

    // MARK: - 读报文

    /// 屏幕上出现的一条 SGR 鼠标报文（`cat -v` 把 ESC 打成 `^[`，所以屏幕上是 `^[[<…`）。
    private struct Report {
        var code: Int
        var column: Int
        var row: Int
        var final: String
    }

    private func reports(in screen: String) -> [Report] {
        let pattern = try! NSRegularExpression(pattern: #"\^\[\[<(\d+);(\d+);(\d+)([Mm])"#)
        let range = NSRange(screen.startIndex..., in: screen)
        return pattern.matches(in: screen, range: range).compactMap { match in
            func group(_ index: Int) -> String {
                guard let slice = Range(match.range(at: index), in: screen) else { return "" }
                return String(screen[slice])
            }
            guard let code = Int(group(1)), let column = Int(group(2)), let row = Int(group(3)) else {
                return nil
            }
            return Report(code: code, column: column, row: row, final: group(4))
        }
    }

    /// 报文数**稳定下来**之后的条数（避开「上一条还在路上」造成的假红 / 假绿）。
    @MainActor
    private func settledReportCount(of pane: TerminalPane, quiet: TimeInterval = 0.3) -> Int {
        var last = reports(in: grid(of: pane)).count
        let deadline = Date().addingTimeInterval(5)
        var quietSince = Date()
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let now = reports(in: grid(of: pane)).count
            if now != last {
                last = now
                quietSince = Date()
                continue
            }
            if Date().timeIntervalSince(quietSince) >= quiet { return last }
        }
        return last
    }

    // MARK: - 挂真视图 / 造合成事件

    private struct Host {
        let window: NSWindow
        let view: TerminalHostView
    }

    /// 把**真** `TerminalHostView` 挂进**不上屏**的 borderless 窗口（与快照 / 滚动那两批同一条路：
    /// 没有真窗口，AppKit 自绘容器与坐标换算都不成立）。
    @MainActor
    private func mount(pane: TerminalPane, size: CGSize = CGSize(width: 900, height: 500)) -> Host {
        let view = TerminalHostView(model: pane, appearance: .alwaysDark, fontSize: 13)
        view.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        return Host(window: window, view: view)
    }

    @MainActor
    private func mouse(
        _ type: NSEvent.EventType,
        at point: CGPoint,
        modifiers: NSEvent.ModifierFlags = [],
        in window: NSWindow
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    @MainActor
    private func key(_ keyCode: UInt16, characters: String, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    /// 滚轮：`NSEvent.mouseEvent` 带不了滚动量，用 `CGEvent` **装**一个再包成 `NSEvent`
    /// （只是造事件对象，不投递 —— 投递才需要辅助功能授权）。
    private func wheel(deltaY: Int32) -> NSEvent {
        let source = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        )!
        return NSEvent(cgEvent: source)!
    }

    /// 起一个真 shell，并把前台切到「接管鼠标的那类程序」那一态：
    /// `-icanon`（没有它，不带换行的报文会被行规程扣住不交给 `cat` —— 本次实测第一坑）、
    /// `-echo`、模式位由 `printf` 那段**程序自己**置位，随后跑 `cat -v` 当「看得见的字节出口」。
    @MainActor
    private func bootCatPane(_ command: String) throws -> (TerminalModel, TerminalPane) {
        let model = TerminalModel()
        let pane = model.activePane
        pane.startIfNeeded(columns: 80, rows: 24)
        XCTAssertTrue(pane.isRunning, "shell 没起来")
        let marker = "READY-\(Int(Date().timeIntervalSince1970))"
        pane.send(text: "date +\(marker)-%s\n")
        waitUntil("shell 就位（回显了启动标记）") { self.text(of: pane).contains(marker) }
        pane.send(text: command + "\n")
        return (model, pane)
    }

    // MARK: - ① 鼠标上报：接管时转发，⌥ 时归本机

    @MainActor
    func testMouseReportingForwardsToTheProgramAndOptionKeepsItLocal() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针真开 shell（取证专用）：DOYAH_UI_SNAPSHOT=1 才跑"
        )

        let (_, pane) = try bootCatPane(
            "stty -icanon min 1 time 0 -echo; printf '\\033[?1002h\\033[?1006h'; cat -v"
        )
        defer { pane.stop() }

        // ⓪ 模式位是**程序自己**经真 PTY 置位的：探针只发命令，不写模式位。
        waitUntil("前台程序接管鼠标（?1002 / ?1006 经真 PTY 送到）") {
            pane.screen.isMouseReportingActive && pane.screen.isSGRMouseEnabled
        }
        waitUntil("前台进程是 cat") { self.foreground(pane) == "cat" }

        let host = mount(pane: pane)
        defer { host.window.contentView = nil }

        // ① 按下 / 松开：必须转发，坐标落在屏幕内
        let before = settledReportCount(of: pane)
        host.view.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 60, y: 440), in: host.window))
        host.view.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 60, y: 440), in: host.window))
        waitUntil("按下 / 松开被转发（屏幕上出现 SGR 报文）") {
            self.reports(in: self.grid(of: pane)).count >= before + 2
        }
        let pressed = reports(in: grid(of: pane))
        let down = try XCTUnwrap(pressed.first { $0.code == 0 && $0.final == "M" }, "没有左键按下的报文")
        XCTAssertTrue((1...80).contains(down.column), "列越界：\(down.column)")
        XCTAssertTrue((1...24).contains(down.row), "行越界：\(down.row)")

        // ② 点到右下角：坐标必须跟着变（判「点哪儿报哪儿」，而不是报一个恒定值）
        host.view.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 840, y: 60), in: host.window))
        host.view.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 840, y: 60), in: host.window))
        waitUntil("右下角那一次也被转发") {
            self.reports(in: self.grid(of: pane)).count > pressed.count
        }
        let latest = try XCTUnwrap(
            reports(in: grid(of: pane)).last { $0.code == 0 && $0.final == "M" },
            "右下角那一次没有报文"
        )
        XCTAssertGreaterThan(latest.column, down.column, "更靠右的点没有报出更大的列")
        XCTAssertGreaterThan(latest.row, down.row, "更靠下的点没有报出更大的行")

        // ③ 拖动（不按 ⌥）：报的是「按住移动」（按钮码 +32），本机**没有**选区
        host.view.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 300, y: 300), in: host.window))
        waitUntil("拖动被转发（按钮码 32 的移动报文）") {
            self.reports(in: self.grid(of: pane)).contains { $0.code == 32 && $0.final == "M" }
        }
        XCTAssertNil(pane.selection, "接管鼠标时本机不该出现选区")

        // ④ 滚轮（不按 ⌥）：转发（64 = 上滚），且本机**没有**滚回滚区
        var wheelForwarded = false
        for _ in 0..<20 {
            host.view.scrollWheel(with: wheel(deltaY: 40))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if reports(in: grid(of: pane)).contains(where: { $0.code == 64 }) {
                wheelForwarded = true
                break
            }
        }
        XCTAssertTrue(wheelForwarded, "接管鼠标时滚轮没有被转发（屏幕上没有 64 的报文）")
        XCTAssertEqual(pane.scrollOffset, 0, "接管鼠标时滚轮不该动本机的回滚区")

        // ⑤ 按住 ⌥ 拖动：**必须归本机** —— 既有选区、又不再有报文
        let beforeOption = settledReportCount(of: pane)
        host.view.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 200), modifiers: [.option], in: host.window))
        host.view.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 600, y: 260), modifiers: [.option], in: host.window))
        waitUntil("⌥ 拖动在本机建出选区") { pane.selection?.isEmpty == false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(
            settledReportCount(of: pane),
            beforeOption,
            "按住 ⌥ 时还是把拖动转发走了（本机再也选不了字）"
        )
    }

    // MARK: - ② 方向键（DECCKM）

    @MainActor
    func testCursorKeyBytesFollowDECCKMOnARealProgram() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针真开 shell（取证专用）：DOYAH_UI_SNAPSHOT=1 才跑"
        )

        let (_, pane) = try bootCatPane("stty -icanon min 1 time 0 -echo; printf '\\033[?1h'; cat -v")
        defer { pane.stop() }
        waitUntil("DECCKM 置位（?1h 经真 PTY 送到）") { pane.screen.isApplicationCursorKeysEnabled }
        waitUntil("前台进程是 cat") { self.foreground(pane) == "cat" }

        let host = mount(pane: pane)
        defer { host.window.contentView = nil }

        // 置位时：SS3 形式（`ESC O A` ⇒ 屏幕上 `^[OA`）
        host.view.keyDown(with: key(126, characters: "\u{F700}", in: host.window))
        waitUntil("↑ 走 SS3（屏幕上出现 ^[OA）") { self.grid(of: pane).contains("^[OA") }
        XCTAssertFalse(grid(of: pane).contains("^[[A"), "置位时不该出现 CSI 形式的方向键")

        // 回到 shell（⌃C 在 `-icanon` 下仍然送 SIGINT，因为 ISIG 没关），复位 DECCKM，再按一次
        pane.send([0x03])
        waitUntil("⌃C 之后前台不再是 cat") { self.foreground(pane) != "cat" }
        pane.send(text: "printf '\\033[?1l'; cat -v\n")
        waitUntil("DECCKM 复位") { !pane.screen.isApplicationCursorKeysEnabled }
        waitUntil("前台进程又是 cat") { self.foreground(pane) == "cat" }
        host.view.keyDown(with: key(125, characters: "\u{F701}", in: host.window))
        waitUntil("↓ 走 CSI（屏幕上出现 ^[[B）") { self.grid(of: pane).contains("^[[B") }
        XCTAssertFalse(grid(of: pane).contains("^[OB"), "复位后不该出现 SS3 形式的方向键")
    }

    // MARK: - ③ 右键归属

    @MainActor
    func testRightClickMenuStaysLocalAndOnlyOptionForwardsIt() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针真开 shell（取证专用）：DOYAH_UI_SNAPSHOT=1 才跑"
        )

        let (_, pane) = try bootCatPane(
            "stty -icanon min 1 time 0 -echo; printf '\\033[?1002h\\033[?1006h'; cat -v"
        )
        defer { pane.stop() }
        waitUntil("前台程序接管鼠标（?1002 / ?1006 经真 PTY 送到）") {
            pane.screen.isMouseReportingActive && pane.screen.isSGRMouseEnabled
        }
        waitUntil("前台进程是 cat") { self.foreground(pane) == "cat" }

        let host = mount(pane: pane)
        defer { host.window.contentView = nil }
        let point = CGPoint(x: 200, y: 300)

        // ① 不按 ⌥：菜单**必须**备好。这一面**故意不派发事件** —— `super.rightMouseDown`
        //    会真的弹出菜单并进入跟踪循环，无人值守下会挂住；视图那一行「先问路由再决定弹不弹」
        //    由入口脚本的源锚点守。
        let menu = try XCTUnwrap(
            host.view.menu(for: mouse(.rightMouseDown, at: point, in: host.window)),
            "接管鼠标时右键菜单没了"
        )
        let selectors = ["copy:", "paste:", "selectAll:", "clearScrollback:", "restartShell:"]
        let actionable = menu.items.filter { $0.action != nil }
        XCTAssertEqual(
            actionable.count,
            selectors.count,
            "右键菜单应当恰有五项：复制 / 粘贴 / 全选 / 清除回滚区 / 重新开始 shell"
        )
        for name in selectors {
            let selector = NSSelectorFromString(name)
            XCTAssertTrue(actionable.contains { $0.action == selector }, "菜单里没有 \(name)")
            XCTAssertTrue(host.view.responds(to: selector), "\(name) 在视图上不存在")
        }
        for item in actionable {
            XCTAssertFalse(item.title.isEmpty, "菜单项没有标题")
        }

        // ② 按住 ⌥：这一面**真派发** —— 必须转发给程序（SGR 里 button code 2 = 右键，⌥ = +8 ⇒ 10）
        let before = settledReportCount(of: pane)
        host.view.rightMouseDown(with: mouse(.rightMouseDown, at: point, modifiers: [.option], in: host.window))
        host.view.rightMouseUp(with: mouse(.rightMouseUp, at: point, modifiers: [.option], in: host.window))
        waitUntil("接管鼠标 + ⌥ 时右键被转发（按钮码 10 的按下与松开各一条）") {
            let seen = self.reports(in: self.grid(of: pane))
            return seen.count >= before + 2 && seen.contains { $0.code == 10 && $0.final == "M" }
        }
    }
}
