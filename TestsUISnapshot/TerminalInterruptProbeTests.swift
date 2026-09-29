import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 终端**作业控制**（`⌃C` 打断前台进程）的 **App 侧探针**（队列 `L-92` ㈡ ①）—— 开发循环第 95 轮。
///
/// ## 为什么需要它
///
/// 「沙箱构建里按 `⌃C` 打断 `sleep 30` 不可靠」这条**长期挂在待人工验收清单上要人点**
/// （清单 §0.3 第 3 条）。2026-09-29 需求提出者拍板**默认改出非沙箱包**（原话：「改非沙箱，
/// 先验证功能，上架都不知道猴年马月了」）之后，这件事**不再需要人点**：
/// 往 PTY 喂一个 `0x03` 字节，看前台进程是否真的被打断即可 —— 不需要任何系统权限。
///
/// ## 判据的形状（判行为，不判「有没有写代码」）
///
/// ① 先在真 shell 里跑 `sleep 30`，**等到它真的占住前台**（`tcgetpgrp` 读出来是 `sleep`）；
/// ② 喂 `0x03`；
/// ③ 断言「前台不再是 `sleep`」，且这件事发生得**远早于 30 秒**（超时 8 秒即判红 ——
///    `⌃C` 没送到的话 `sleep` 会一直占着，8 秒时探针自己红）；
/// ④ 再敲一条命令并等它回来 —— 证明被中断的是**前台进程**，shell 本身还活着
///    （判据方向反了会看不到这条回声）。
///
/// ## 口径与边界（如实登记）
///
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）—— 它**真开 shell**，与快照同一条纪律：
///   取证才跑，不进每轮门禁；
/// · 它用**真 `TerminalPane` + 真 `forkpty` 会话**（与界面同一个类，不是替身）；
/// · **边界**：这条判的是「**非沙箱构建**（= 现在的默认与交付口径）下 `⌃C` 可用」。
///   **没有**做「同一个探针在沙箱里必红」的 A/B —— 那要把测试二进制也套上沙箱
///   （会引入一堆与本事无关的失败），或需要 GUI 里真点一次。沙箱那一面「`⌃C` 不可靠」的依据
///   仍是 2026-09-22 的沙箱 / 非沙箱对照实验（SRS `R-18` / v3.36），本探针**不重复主张**它。
final class TerminalInterruptProbeTests: XCTestCase {

    /// 等到条件成立（默认 10 秒）。会话输出与前台进程查询都在主队列上，所以转主运行循环而不是 `sleep`。
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

    @MainActor
    private func text(of pane: TerminalPane) -> String {
        pane.displayLines()
            .map { $0.map(\.displayText).joined() }
            .joined(separator: "\n")
    }

    /// 前台进程名（`tcgetpgrp` 那条路，与页签标题同源）。取不到时是 `nil`。
    @MainActor
    private func foreground(_ pane: TerminalPane) -> String? {
        TerminalTabTitle.derive(fromExecutablePath: pane.foregroundProcessPath())
    }

    @MainActor
    func testControlCInterruptsTheForegroundSleep() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "本探针真开 shell（取证专用）：DOYAH_UI_SNAPSHOT=1 才跑"
        )

        let model = TerminalModel()
        let pane = model.activePane
        pane.startIfNeeded(columns: 80, rows: 24)
        XCTAssertTrue(pane.isRunning, "shell 没起来")
        defer { pane.stop() }

        // ⓪ 先等提示符就位：命令敲在提示符之前会被行编辑吞掉，那不是本探针要判的事。
        let readyMarker = "READY-\(Int(Date().timeIntervalSince1970))"
        pane.send(text: "date +\(readyMarker)-%s\n")
        waitUntil("shell 就位（回显了启动标记）") { self.text(of: pane).contains(readyMarker) }

        // ① 让一个前台进程真的占住终端
        pane.send(text: "sleep 30\n")
        waitUntil("前台进程变成 sleep") { self.foreground(pane) == "sleep" }

        // ② 喂一个 ⌃C 字节（0x03 = ETX；PTY 的行规程把它交给前台进程组 = SIGINT）
        let sent = Date()
        pane.send([0x03])

        // ③ 「前台不再是 sleep」必须**远早于** 30 秒发生
        waitUntil("⌃C 之后前台进程不再是 sleep（8 秒内）", timeout: 8) {
            self.foreground(pane) != "sleep"
        }
        let elapsed = Date().timeIntervalSince(sent)
        XCTAssertLessThan(elapsed, 8, "8 秒还没让开前台 ⇒ sleep 没被打断（0x03 没送到前台进程组）")

        // ④ 被中断的只是前台进程：shell 本身还在，敲一条命令还回得来
        pane.send(text: "echo ALIVE-$((1+1))\n")
        waitUntil("⌃C 之后 shell 还能执行命令") { self.text(of: pane).contains("ALIVE-2") }
    }
}
