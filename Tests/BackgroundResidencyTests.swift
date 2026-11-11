import XCTest

@testable import DoyahCore

/// 「随系统启动 + 关窗常驻」的 **Core 纯决策**单测（`NFR-ALL-GATE-REL-006`）。
///
/// 覆盖什么：开关与系统状态的九种组合该做什么、关窗时该不该终止、菜单栏该不该留图标。
/// 不覆盖什么（如实说）：真去 `SMAppService.register()`、真关窗、真拉 IM 通道 ——
/// 那三样是 App 侧接线与真机点验的事，见台账该条的「判据」列。
final class BackgroundResidencyTests: XCTestCase {

    // MARK: - 关窗后的结局

    func testTerminatesWhenLaunchAtLoginOff() {
        let inputs = ResidencyInputs(launchAtLogin: false, imChannelEnabled: true)
        XCTAssertEqual(BackgroundResidency.onLastWindowClosed(inputs), .terminate)
    }

    func testTerminatesWhenChannelNotEnabled() {
        // 开关开着但通道没配 ⇒ 留着进程只是白占内存。
        let inputs = ResidencyInputs(launchAtLogin: true, imChannelEnabled: false)
        XCTAssertEqual(BackgroundResidency.onLastWindowClosed(inputs), .terminate)
    }

    func testKeepsRunningWhenBothOn() {
        let inputs = ResidencyInputs(launchAtLogin: true, imChannelEnabled: true)
        XCTAssertEqual(BackgroundResidency.onLastWindowClosed(inputs), .keepRunning)
    }

    func testExplicitQuitWins() {
        // 用户按「退出」永远优先，常驻不许抢。
        let inputs = ResidencyInputs(launchAtLogin: true, imChannelEnabled: true, explicitQuit: true)
        XCTAssertEqual(BackgroundResidency.onLastWindowClosed(inputs), .terminate)
        XCTAssertFalse(BackgroundResidency.wantsStatusItem(inputs))
    }

    // MARK: - 菜单栏入口

    func testStatusItemOnlyWhenResident() {
        XCTAssertTrue(BackgroundResidency.wantsStatusItem(
            ResidencyInputs(launchAtLogin: true, imChannelEnabled: true)))
        XCTAssertFalse(BackgroundResidency.wantsStatusItem(
            ResidencyInputs(launchAtLogin: true, imChannelEnabled: false)))
        XCTAssertFalse(BackgroundResidency.wantsStatusItem(
            ResidencyInputs(launchAtLogin: false, imChannelEnabled: true)))
    }

    func testStatusLineExplainsWhyResident() {
        let resident = ResidencyInputs(launchAtLogin: true, imChannelEnabled: true)
        XCTAssertEqual(BackgroundResidency.statusLine(resident), "常驻中：关窗不退出，IM 通道继续在线")
        XCTAssertNil(BackgroundResidency.statusLine(
            ResidencyInputs(launchAtLogin: false, imChannelEnabled: true)))
    }

    // MARK: - 登录项决策（九种组合）

    func testPlanDoesNotRegisterTwice() {
        let plan = LaunchAtLoginDecision.plan(desired: true, current: .enabled)
        XCTAssertEqual(plan.action, .none)
    }

    func testPlanRegistersWhenDisabled() {
        XCTAssertEqual(LaunchAtLoginDecision.plan(desired: true, current: .disabled).action, .register)
    }

    func testPlanAsksForApprovalInsteadOfRegistering() {
        // 再注册一次不会有不同结局，只会让界面「点了没反应」。
        let plan = LaunchAtLoginDecision.plan(desired: true, current: .requiresApproval)
        XCTAssertEqual(plan.action, .requestApproval)
    }

    func testPlanRetriesAfterFailure() {
        XCTAssertEqual(LaunchAtLoginDecision.plan(desired: true, current: .failed).action, .register)
    }

    func testPlanUnregistersWhenUserTurnsOff() {
        XCTAssertEqual(LaunchAtLoginDecision.plan(desired: false, current: .enabled).action, .unregister)
    }

    func testPlanDoesNothingWhenAlreadyOff() {
        XCTAssertEqual(LaunchAtLoginDecision.plan(desired: false, current: .disabled).action, .none)
        XCTAssertEqual(LaunchAtLoginDecision.plan(desired: false, current: .requiresApproval).action, .none)
    }

    func testUnavailableNeverActs() {
        XCTAssertEqual(LaunchAtLoginDecision.plan(desired: true, current: .unavailable).action, .none)
        XCTAssertEqual(LaunchAtLoginDecision.plan(desired: false, current: .unavailable).action, .none)
    }
}
