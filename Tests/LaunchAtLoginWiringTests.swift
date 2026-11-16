import XCTest
@testable import DoyahCore
@testable import DoyahPlatform
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

/// 判据：`T-REL-006-3`（未签名构建的兜底通道）——
/// `SMAppService` 在 ad-hoc 签名下永远 `.notFound`（本机实测 `TeamIdentifier=not set`），
/// 若不兜底，「开机自启」开关就是个摆设：重启后 QQ 通道又断。
@MainActor
final class LaunchAgentFallbackTests: XCTestCase {

    func testPlistCarriesLabelProgramAndRunAtLoad() throws {
        let xml = LaunchAgentLoginItem.plist(executablePath: "/Users/x/Applications/Doyah Studio.app/Contents/MacOS/DoyahStudio")
        XCTAssertTrue(xml.contains("<key>Label</key>"), xml)
        XCTAssertTrue(xml.contains(LaunchAgentLoginItem.label), "label 要能一眼认出是谁的")
        XCTAssertTrue(xml.contains("<key>RunAtLoad</key>"), "登录即启动靠这个键")
        XCTAssertTrue(xml.contains("<true/>"), xml)
        XCTAssertTrue(xml.contains("/Contents/MacOS/DoyahStudio"), "路径带空格也要原样进去")
    }

    func testPlistEscapesXmlSensitiveCharacters() {
        let xml = LaunchAgentLoginItem.plist(executablePath: "/tmp/a&b< c>.app/x")
        XCTAssertTrue(xml.contains("a&amp;b&lt; c&gt;"), "路径里的 & < > 必须转义，否则 plist 解析失败")
        XCTAssertFalse(xml.contains("a&b<"), "不许原样塞进去")
    }

    func testInstallThenRemoveIsObservableByFilePresence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("la-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("\(LaunchAgentLoginItem.label).plist")
        XCTAssertFalse(LaunchAgentLoginItem.isInstalled(at: url))
        try LaunchAgentLoginItem.install(executablePath: "/tmp/DoyahStudio", at: url)
        XCTAssertTrue(LaunchAgentLoginItem.isInstalled(at: url), "装完必须真的在盘上")
        try LaunchAgentLoginItem.remove(at: url)
        XCTAssertFalse(LaunchAgentLoginItem.isInstalled(at: url), "关掉必须真的删掉，不许只改内存")
        try? FileManager.default.removeItem(at: directory)
    }

    func testFallbackTakesOverWhenSMAppServiceSaysUnavailable() {
        let state = AppState()
        let fake = FakeUnavailableRegistrar()
        state.loginItemRegistrar = fake
        state.launchAtLogin = true
        state.applyLaunchAtLogin()
        XCTAssertEqual(state.launchAtLoginStatus, .enabled,
                       "SMAppService 不可用时必须走兜底，而不是把开关留成「不可用」")
        XCTAssertTrue(LaunchAgentLoginItem.isInstalled(at: LaunchAgentLoginItem.url()),
                      "兜底要真的写出 plist（本机 ad-hoc 签名下 SMAppService 永远 notFound）")
        // 收尾：把测试写出来的 plist 删掉，别留在主人的 LaunchAgents 里。
        state.launchAtLogin = false
        XCTAssertFalse(LaunchAgentLoginItem.isInstalled(at: LaunchAgentLoginItem.url()))
    }

    private final class FakeUnavailableRegistrar: LoginItemRegistering {
        var status: LaunchAtLoginStatus = .unavailable
        func register() throws { XCTFail("不可用时不该调 register") }
        func unregister() throws { XCTFail("不可用时不该调 unregister") }
    }
}
