import XCTest
@testable import DoyahCore

/// 调试器接入的口径层（`FR-STD-WS-TOOL-003`）。
///
/// 三条判据都不是「能否调试」，而是**出错时说真话**，所以每条都配一个「故意坏掉」的反例：
/// ① 断点被挪动 ⇒ 必须说「原位置已不存在」（且多处命中**不许猜**）；
/// ② 调试期改文件 ⇒ 必须提示「代码与运行体不一致」，没在调试时**不许**弹；
/// ③ 调试器不可用 ⇒ 编辑仍然可用（`canEdit` 恒真），且给出原因。
final class DAPCoreTests: XCTestCase {

    // MARK: - ① 分帧（半包是常态，不许当错误）

    func testEncodeDecodeRoundtrip() {
        let body = Data(#"{"seq":1,"type":"request","command":"initialize"}"#.utf8)
        var buffer = DAPFrame.encode(body: body)
        XCTAssertEqual(DAPFrame.decode(&buffer), [body])
        XCTAssertTrue(buffer.isEmpty, "整包解完缓冲区应为空")
    }

    func testPartialBodyWaitsForMoreBytes() {
        let body = Data(String(repeating: "a", count: 40).utf8)
        var buffer = DAPFrame.encode(body: body)
        let head = buffer.prefix(20)
        var partial = Data(head)
        XCTAssertEqual(DAPFrame.decode(&partial), [], "体还没齐时不许判错，也不许吐出半条")
        partial.append(buffer.dropFirst(20))
        XCTAssertEqual(DAPFrame.decode(&partial), [body])
    }

    func testTwoMessagesInOneRead() {
        let a = Data("A".utf8), b = Data("BB".utf8)
        var buffer = DAPFrame.encode(body: a)
        buffer.append(DAPFrame.encode(body: b))
        XCTAssertEqual(DAPFrame.decode(&buffer), [a, b])
    }

    func testHeaderWithoutContentLengthIsSkippedNotLooped() {
        var buffer = Data("X-Nope: 1\r\n\r\n".utf8)
        XCTAssertEqual(DAPFrame.decode(&buffer), [], "读不懂的头只能丢掉，不许死循环")
        XCTAssertTrue(buffer.isEmpty)
    }

    // MARK: - ② 断点复验（判据 ①）

    func testBreakpointUnchangedWhenSameLineSameText() {
        let bp = DebugBreakpoint(line: 2, anchor: "let a = 1")
        let result = DebugBreakpoints.recheck(bp, against: "// hi\nlet a = 1\nlet b = 2")
        XCTAssertEqual(result, .unchanged(bp))
    }

    func testBreakpointMovedSaysOriginalLocationGone() {
        let bp = DebugBreakpoint(line: 1, anchor: "let a = 1")
        let result = DebugBreakpoints.recheck(bp, against: "// 新加一行注释\nlet a = 1\nlet b = 2")
        guard case .moved(let to, let message) = result else {
            return XCTFail("应判为「移走了」，实际：\(result)")
        }
        XCTAssertEqual(to, 2)
        XCTAssertTrue(message.contains("原位置已不存在"), "判据 ① 要求说清原位置已不存在：\(message)")
        XCTAssertTrue(message.contains("第 2 行"), "要给出新位置：\(message)")
    }

    func testBreakpointRemovedWhenTextGone() {
        let bp = DebugBreakpoint(line: 1, anchor: "let a = 1")
        let result = DebugBreakpoints.recheck(bp, against: "let b = 2")
        guard case .removed(let message) = result else {
            return XCTFail("应判为移除，实际：\(result)")
        }
        XCTAssertTrue(message.contains("原位置已不存在"))
    }

    func testBreakpointRemovedWhenAmbiguousInsteadOfGuessing() {
        let bp = DebugBreakpoint(line: 1, anchor: "return nil")
        // 内容在原行已不在，但新文本里出现两处 —— 猜错会停在意想不到的地方，必须移除
        let result = DebugBreakpoints.recheck(bp, against: "let x = 1\nreturn nil\nfoo()\nreturn nil")
        guard case .removed(let message) = result else {
            return XCTFail("多处命中应移除而不是挑一处，实际：\(result)")
        }
        XCTAssertTrue(message.contains("2 处"), "要说清为什么无法判断：\(message)")
    }

    // MARK: - ③ 调试期改文件（判据 ②）

    func testFileChangeDuringDebugWarnsInconsistency() {
        let warning = DebugConsistency.warning(state: .running, changedFiles: ["Editor.swift"])
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning!.contains("代码与运行体不一致"), "判据 ② 的原话：\(warning!)")
        XCTAssertTrue(warning!.contains("Editor.swift"), "要说清改了哪个文件：\(warning!)")
    }

    func testFileChangeWhenNotDebuggingIsSilent() {
        XCTAssertNil(DebugConsistency.warning(state: .idle, changedFiles: ["Editor.swift"]))
        XCTAssertNil(DebugConsistency.warning(state: .terminated(reason: "用户停止"), changedFiles: ["Editor.swift"]),
                     "调试结束后改文件是日常，不许再弹")
    }

    func testNoChangedFilesNoWarning() {
        XCTAssertNil(DebugConsistency.warning(state: .running, changedFiles: []))
    }

    // MARK: - ④ 不可用不挡编辑（判据 ③）

    func testUnavailableDebuggerNeverBlocksEditing() {
        let reasons: [DebugUnavailableReason] = [
            .adapterNotFound(name: "lldb-dap"),
            .adapterExited(code: 1),
            .handshakeTimeout(seconds: 10),
            .stoppedByUser,
        ]
        for reason in reasons {
            let availability = DebugAvailability.whenUnavailable(reason)
            XCTAssertFalse(availability.canStart, "\(reason) 时调试入口应关")
            XCTAssertTrue(availability.canEdit, "判据 ③：\(reason) 时编辑必须仍可用")
            XCTAssertFalse(availability.sentence.isEmpty, "关掉入口必须给一句原因")
        }
    }

    func testUnavailableSentencesAreReadable() {
        let sentence = DebugUnavailableReason.adapterExited(code: 2).sentence
        XCTAssertTrue(sentence.contains("退出码 2"), "要带可核对的信息：\(sentence)")
        XCTAssertTrue(sentence.contains("编辑不受影响"), "判据 ③ 的承诺要写出来：\(sentence)")
    }
}
