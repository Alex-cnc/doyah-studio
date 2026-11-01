import XCTest
@testable import DoyahCore

/// 真适配器烟测（`FR-STD-WS-TOOL-003`）：只在 `DOYAH_DAP_SMOKE=1` 时跑。
///
/// 为什么不进常规套件：它依赖本机装了 `lldb-dap` 与 `clang`。写进常规套件的话，
/// 「机器没装」会变成红，被人当成「代码坏了」—— 判据必须把「没条件」与「不通过」分开报。
final class DAPSmokeTests: XCTestCase {

    private func tool(_ path: String) -> String? {
        FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    func testRealLLDBDAPStopsAtBreakpointAndReadsVariable() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_DAP_SMOKE"] == "1" else {
            throw XCTSkip("未设 DOYAH_DAP_SMOKE=1 ⇒ 不跑真适配器烟测（不是通过，是没条件）")
        }
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer/usr/bin/lldb-dap",
            "/Library/Developer/CommandLineTools/usr/bin/lldb-dap",
        ].compactMap(tool)
        guard let adapter = candidates.first else {
            throw XCTSkip("本机没有 lldb-dap ⇒ 跳过（未知，不是绿）")
        }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dap-smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("smoke.c")
        try #"""
        #include <stdio.h>
        int main(void) {
            int total = 0;
            for (int i = 1; i <= 3; i++) {
                total += i;
            }
            printf("%d\n", total);
            return 0;
        }
        """#.write(to: source, atomically: true, encoding: .utf8)

        let binary = dir.appendingPathComponent("smoke")
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compile.arguments = ["-g", "-O0", "-o", binary.path, source.path]
        compile.standardError = Pipe()
        try compile.run()
        compile.waitUntilExit()
        XCTAssertEqual(compile.terminationStatus, 0, "clang 编译失败 ⇒ 烟测的前提没成立")

        let session = DAPSession(client: DAPClient(adapterPath: adapter, timeoutSeconds: 15))
        defer { session.disconnect() }

        // 断点打在第 5 行（`total += i;`）
        let outcome = try session.runUntilStop(program: binary.path,
                                              breakpoints: [source.path: [5]],
                                              waitSeconds: 30)
        guard case .stopped(let location) = outcome else {
            return XCTFail("真适配器应停在断点，实际：\(outcome)")
        }
        XCTAssertEqual(location.line, 5, "应停在第 5 行")
        XCTAssertEqual(location.reason, "breakpoint")

        // 单步：步过 `total += i;` 后仍在循环里，行号必须变（真适配器实测）
        guard case .stopped(let stepped) = try session.step(.over, threadId: location.threadId, waitSeconds: 15) else {
            return XCTFail("真适配器单步后应再次停住")
        }
        XCTAssertNotEqual(stepped.line, 5, "步过之后行号应当变化（实际仍在第 5 行 = 没真步进）")
        XCTAssertEqual(stepped.reason, "step")

        let variables = try session.variables(threadId: location.threadId)
        XCTAssertTrue(variables.keys.contains { $0 == "i" || $0 == "total" },
                      "停在循环里应能读到局部变量，实际：\(variables)")
    }
}
