import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// 判据：`T-REL-006-2`（登录项接线）——
/// 决策层与 `SMAppService` 实现早已存在，**没人调**就等于没有：系统重启后应用不自己起来，
/// 手机发消息没人接（2026-11-16 真机事实）。这里判的是「意愿 → 决策 → 注册器」这条线真的通。
@MainActor
final class LaunchAtLoginWiringTests: XCTestCase {

    private final class FakeRegistrar: LoginItemRegistering {
        var status: LaunchAtLoginStatus
        private(set) var registers = 0
        private(set) var unregisters = 0
        init(status: LaunchAtLoginStatus) { self.status = status }
        func register() throws { registers += 1; status = .enabled }
        func unregister() throws { unregisters += 1; status = .disabled }
    }

    func testEnabledWishRegistersOnceAndIsNotRepeated() {
        let state = AppState()
        let registrar = FakeRegistrar(status: .disabled)
        state.loginItemRegistrar = registrar
        state.launchAtLogin = true
        state.applyLaunchAtLogin()
        XCTAssertEqual(registrar.registers, 1, "开着就该注册")
        XCTAssertEqual(state.launchAtLoginStatus, .enabled)
        state.applyLaunchAtLogin()
        XCTAssertEqual(registrar.registers, 1, "已经是登录项，不许重复注册（重复会抛错）")
    }

    func testTurningItOffReallyUnregisters() {
        let state = AppState()
        let registrar = FakeRegistrar(status: .enabled)
        state.loginItemRegistrar = registrar
        state.launchAtLogin = false
        XCTAssertEqual(registrar.unregisters, 1, "关掉必须真的注销，不许只改本地开关")
        XCTAssertEqual(state.launchAtLoginStatus, .disabled)
    }

    func testRequiresApprovalIsNotFakedAsOn() {
        let state = AppState()
        let registrar = FakeRegistrar(status: .requiresApproval)
        state.loginItemRegistrar = registrar
        state.launchAtLogin = true
        state.applyLaunchAtLogin()
        XCTAssertEqual(registrar.registers, 0, "要求批准时再注册一次结局相同，只是「点了没反应」")
        XCTAssertEqual(state.launchAtLoginStatus, .requiresApproval, "要如实显示待批准，不许画成已开启")
    }

    func testMissingRegistrarSaysUnavailableNotSilent() {
        let state = AppState()
        state.loginItemRegistrar = nil
        state.applyLaunchAtLogin()
        XCTAssertEqual(state.launchAtLoginStatus, .unavailable)
    }
}
