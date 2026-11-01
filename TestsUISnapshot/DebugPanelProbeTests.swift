import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 调试器界面半的行为判据（`FR-STD-WS-TOOL-003`）：断点账本 → 面板 → DAP。
///
/// Core 那半已有真烟测（`DAPSmokeTests`，`DOYAH_DAP_SMOKE=1` 时真起 lldb-dap），这里判的是
/// **界面这一层有没有把线接上**：
///
///   ① 点断点真的写进账本，面板那一屏读的是同一份账本（不是各自一份）；
///   ② 「开始调试」把 `DebugBreakpointSet.dapMap()` 那份 `[path: [行号]]` 交给 `DAPSession`
///      （源锚点 + 行为面：缺适配器时如实报「找不到调试适配器」，而不是静默不动）；
///   ③ 四个单步按钮打的是 `DAPSession.Step` 的四个真请求（`.over/.into/.out/.resume`）；
///   ④ 停止之后回到 idle，变量面板清空（不留上一轮的读数冒充当前）。
///
/// 跑法：`env DOYAH_UI_SNAPSHOT=1 swift test --filter DebugPanelProbeTests`
final class DebugPanelProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    private struct Harness: View {
        @ObservedObject var model: DebugSessionModel
        var body: some View { DebugPanelView(model: model) }
    }

    // MARK: - ① 断点：点进去、面板读同一份

    @MainActor
    func testBreakpointToggleLandsInTheSharedLedger() throws {
        let model = DebugSessionModel()
        let path = "/tmp/probe/main.c"
        model.toggleBreakpoint(line: 12, in: path)
        model.toggleBreakpoint(line: 4, in: path)
        XCTAssertEqual(model.breakpoints.lines(for: path), [4, 12])
        XCTAssertEqual(model.breakpoints.dapMap()[path], [4, 12],
                       "发给适配器的必须是升序行号 —— 与 Core 账本同一份")
        XCTAssertTrue(model.log.contains { $0.contains("12") }, "点了断点要有可读回执（含行号）")

        // 面板那一屏用的是同一个模型（不是自己再存一份）：
        // 程序路径那一格必须绑着模型里的值 —— SwiftUI 的 `TextField` 在宿主里是真 `NSTextField`。
        model.program = "/tmp/probe/main"
        let host = UISnapshot.LiveHost(Harness(model: model), size: CGSize(width: 720, height: 560))
        host.pump(0.6)
        let fields = UISnapshot.LiveHost<Harness>.findViews(ofType: NSTextField.self, in: host.hosting)
        XCTAssertTrue(fields.contains { $0.stringValue == "/tmp/probe/main" },
                      "面板里找不到绑着模型的那一格程序路径 —— 界面与账本不是同一份")
        XCTAssertEqual(model.breakpoints.listing.first?.lines, [4, 12],
                       "面板清单读的就是账本（同一条断点不许在界面里另存一份）")
    }

    @MainActor
    func testToggleRemovesTheSameLine() {
        let model = DebugSessionModel()
        let path = "/tmp/probe/main.c"
        model.toggleBreakpoint(line: 7, in: path)
        model.toggleBreakpoint(line: 7, in: path)
        XCTAssertTrue(model.breakpoints.isEmpty, "再点一次要去掉，不能越点越多")
    }

    // MARK: - ② 开始调试：真的是 DAP，缺适配器要如实报

    @MainActor
    func testMissingAdapterIsReportedHonestly() async throws {
        let model = DebugSessionModel()
        model.program = "/bin/echo"
        model.adapterPath = "/nonexistent/lldb-dap"
        model.start()
        // 起进程是后台跳，等它落定。**必须 `await` 让出主 actor** ——
        // 用同步 runloop 泵会把 MainActor 攥在手里，后台那一跳的 `MainActor.run` 永远排不进来（实测卡成 running）。
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, model.phase == .running {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if case .failed(let reason) = model.phase {
            XCTAssertFalse(reason.isEmpty, "失败必须带原因，不许空着")
            XCTAssertTrue(reason.contains("/nonexistent/lldb-dap"),
                          "原因里要带那个找不到的路径（与语言无关，用户才知道去哪找），实测：\(reason)")
        } else {
            XCTFail("适配器不存在却没报失败：\(model.phase)")
        }
    }

    @MainActor
    func testEmptyProgramIsRefusedBeforeSpawning() {
        let model = DebugSessionModel()
        model.program = "   "
        model.start()
        if case .failed(let reason) = model.phase {
            XCTAssertFalse(reason.isEmpty, "空程序要当场给一句可读理由")
        } else {
            XCTFail("空程序不该进 running 态")
        }
    }

    // MARK: - ③ 单步：四个按钮各打一个真请求

    func testStepButtonsMapToRealDAPCommands() throws {
        let source = try String(contentsOfFile: root + "App/Views/DebugPanelView.swift", encoding: .utf8)
        XCTAssertTrue(source.contains("model.step(.resume)"), "「继续」没有打 continue")
        XCTAssertTrue(source.contains("model.step(.over)"), "「步过」没有打 next")
        XCTAssertTrue(source.contains("model.step(.into)"), "「步入」没有打 stepIn")
        XCTAssertTrue(source.contains("model.step(.out)"), "「步出」没有打 stepOut")
        // 四个请求名由 Core 定（`DAPSession.Step.rawValue`），界面不许自己写字面量协议名。
        XCTAssertEqual(DAPSession.Step.resume.rawValue, "continue")
        XCTAssertEqual(DAPSession.Step.over.rawValue, "next")
        XCTAssertEqual(DAPSession.Step.into.rawValue, "stepIn")
        XCTAssertEqual(DAPSession.Step.out.rawValue, "stepOut")
    }

    // MARK: - ④ 停止：回到 idle 并清空变量

    @MainActor
    func testStopResetsStateAndVariables() {
        let model = DebugSessionModel()
        model.program = "/bin/echo"
        model.stop()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.variables.isEmpty)
        XCTAssertFalse(model.isBusy)
    }

    // MARK: - 工具

    private var root: String {
        #filePath.replacingOccurrences(of: "TestsUISnapshot/DebugPanelProbeTests.swift", with: "")
    }

    @MainActor
    private func pump() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}
