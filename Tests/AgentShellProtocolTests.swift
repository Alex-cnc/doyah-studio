import XCTest
@testable import DoyahCore

/// `T-3.28-*`：Agent shell 的回收协议（`FR-AGT-CORE-LOOP-006`）。
///
/// 这里的每一条都对应一次真机上踩过的坑，**负例尤其重要** ——
/// 协议出问题时人看到的是「命令卡 60 秒后超时」，不会看到「协议错了」。
final class AgentShellProtocolTests: XCTestCase {

    private let sentinel = "__DOYAH_AGENT_DONE_ABCDEF123456"

    // MARK: - 脚本拼法（T-3.28-01）

    func testScriptIsWrappedInBracketedPasteAndSubmittedOutside() {
        let script = AgentShellProtocol.script(command: "python3 hello.py", sentinel: sentinel)
        XCTAssertTrue(script.hasPrefix("\u{1B}[200~"), "必须用括号粘贴开头（否则多行脚本会被 zle 拆成多次提交）")
        XCTAssertTrue(script.hasSuffix("\u{1B}[201~\r"), "粘贴结束标记之后的那一次回车才是提交")
        XCTAssertTrue(script.contains("python3 hello.py\n__doyah_ec=$?\n"), "三行按 \\n 切，不按 \\r")
        XCTAssertTrue(script.contains("printf '\(sentinel):%d\\n' $__doyah_ec"), "格式串用单引号、变量不加引号")
        XCTAssertFalse(script.contains("\r\n"), "粘贴内部不许出现 CR（会被 zle 当控制字符）")
    }

    func testResetBytesCancelPendingLineBeforeNextCommand() {
        XCTAssertEqual(AgentShellProtocol.reset, "\u{03}\u{15}", "Ctrl-C 掐续行态 + Ctrl-U 清行缓冲")
    }

    // MARK: - 认哨兵（T-3.28-02 / 03）

    func testCompletionReadsExitCodeAndSplitsBody() {
        let buffer = "hello\r\n\(sentinel):0\r\n\u{1B}[1m%"
        let done = AgentShellProtocol.completion(in: buffer, sentinel: sentinel)
        XCTAssertEqual(done?.exitCode, 0)
        XCTAssertEqual(done?.body, "hello\r\n")
    }

    /// **负例（必须判不出来）**：回显里的那行 `printf '…:%d\n'`，冒号后面是 `%` 不是数字。
    func testEchoedPrintfLineIsNotMistakenForCompletion() {
        let buffer = "printf '\(sentinel):%d\\n' $__doyah_ec"
        XCTAssertNil(AgentShellProtocol.completion(in: buffer, sentinel: sentinel),
                     "回显行被当成完成 ⇒ 退出码会解析成 -1，模型会以为命令失败然后一直重试")
    }

    func testSentinelWithoutDigitsIsIgnored() {
        XCTAssertNil(AgentShellProtocol.completion(in: "\(sentinel):\r\n", sentinel: sentinel))
        XCTAssertNil(AgentShellProtocol.completion(in: "\(sentinel):x1", sentinel: sentinel))
    }

    func testNonZeroExitCodeIsReported() {
        let done = AgentShellProtocol.completion(in: "ModuleNotFoundError\n\(sentinel):1\n", sentinel: sentinel)
        XCTAssertEqual(done?.exitCode, 1)
        XCTAssertEqual(done?.body, "ModuleNotFoundError\n")
    }

    /// 一次读进来两段（上一条的尾巴 + 这一条）：只认本条的哨兵，正文只取本条之前。
    func testOnlyCurrentSentinelCounts() {
        let other = "__DOYAH_AGENT_DONE_ZZZZZZZZZZZZ"
        let buffer = "\(other):0\r\nsome output\r\n\(sentinel):2\r\n"
        let done = AgentShellProtocol.completion(in: buffer, sentinel: sentinel)
        XCTAssertEqual(done?.exitCode, 2, "只认本条的哨兵；上一条的残留不该被当成本次退出码")
        // 正文里可能夹着上一条的尾巴（缓冲在每条命令开始时清空，正常不会出现）——
        // 这里只钉「退出码取对了」，不假设正文绝对干净。
    }

    // MARK: - 清洗（T-3.28-04）

    func testStripControlRemovesAnsiBackspaceAndReturn() {
        let raw = "\u{1B}[1mhello\u{1B}[0m\r\nwor\u{08}ld\r\n"
        XCTAssertEqual(AgentShellProtocol.stripControl(raw), "hello\nworld")
    }

    func testStripEchoDropsPastedScriptWhenLineBreaksWereRewrapped() {
        // PTY 把 `\n` 折成 `\r\n` ⇒ 整段精确匹配不上，按行剔
        let body = "python3 hello.py\r\n__doyah_ec=$?\r\nprintf '\(sentinel):%d\\n' $__doyah_ec\r\nhello\r\n"
        let cleaned = AgentShellProtocol.stripEcho(body, echo: "")
        XCTAssertFalse(cleaned.contains("__doyah_ec=$?"), "回收脚本本身不该混进结果")
        XCTAssertTrue(cleaned.contains("hello"))
    }
}

extension AgentShellProtocolTests {
    /// 回归：回显里那行 `printf '…:%d\n'` 排在真正的结果行**前面**，不许因此判「没跑完」。
    /// 2026-10-31 真机现场：缓冲里已有 `…:0`，程序报「未命中」，卡满 60 秒。
    func testEchoedLiteralBeforeRealSentinelStillCompletes() {
        let buffer = """
        \u{1B}[7mprintf '__DOYAH_AGENT_DONE_ABCDEF123456:%d\\n' $__doyah_ec\u{1B}[27m
        hello
        __DOYAH_AGENT_DONE_ABCDEF123456:0
        """
        let done = AgentShellProtocol.completion(in: buffer, sentinel: sentinel)
        XCTAssertEqual(done?.exitCode, 0, "必须跳过回显里那处、认真正结果那处")
        XCTAssertTrue(done?.body.contains("hello") ?? false)
    }
}

extension AgentShellProtocolTests {
    /// 真机形态：zle 逐字重绘（每个字符夹 ESC[27m）+ 提示符尾巴 ⇒ 洗出来只剩程序输出。
    func testCleanOutputFromRealTerminalShape() {
        let raw = "\u{1B}[7mpython3 hello.py\u{1B}[27m\r\r\n"
            + "\u{1B}[27mp\u{1B}[27my\u{1B}[27mt\u{1B}[27mh\u{1B}[27mo\u{1B}[27mn\u{1B}[27m\r\n"
            + "hello\r\n"
            + "__DOYAH_AGENT_DONE_ABCDEF123456:0\r\n"
            + "\u{1B}[1m\u{1B}[7m%\u{1B}[27m   \r \r\r\n"
            + "alex@AlexdeMacBook-Pro doyah % \u{1B}[K"
        let clean = AgentShellProtocol.cleanOutput(raw, echo: "", command: "python3 hello.py")
        XCTAssertEqual(clean, "hello", "只留程序输出：命令回显、哨兵、提示符都不该进结果")
    }
}

extension AgentShellProtocolTests {
    /// 真机样本（2026-10-31 13:16 落盘）：提示符、命令回显、程序输出挤在**同一行**。
    func testCleanOutputFromSingleLinePromptAndEcho() {
        let raw = "%                                                                                                                        "
            + "alex@AlexdeMacBook-Pro doyah % python3 hello.py\nhello"
        XCTAssertEqual(AgentShellProtocol.cleanOutput(raw, command: "python3 hello.py"), "hello")
    }
}
