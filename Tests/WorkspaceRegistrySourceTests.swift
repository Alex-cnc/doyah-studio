import XCTest
@testable import DoyahCore

/// `FR-STD-WS-FS-010` 的**源树判据**：表在 Core、切换只走一个裁决、两个入口共用同一份列表与动作。
///
/// Core 侧全绿只说明「算得对」。这条需求最容易悄悄坏掉的三处都在接线面上：
/// 1. `WorkspaceStore` 自己再判一遍「能不能切」（两处各判一次，迟早出现「这边说能切、那边说不能」）；
/// 2. 文件树标头与首页各写一份列表 / 各写一个动作（只补用户点到的那一处，另一处还是老形态）；
/// 3. 首页继续拿「页签历史里的工作区路径」当列表 —— 那是流水，不是授权表，沙箱下点不动。
final class WorkspaceRegistrySourceTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let url = root.appendingPathComponent(relative)
        let body = try String(contentsOf: url, encoding: .utf8)
        XCTAssertGreaterThan(body.count, 1000, "\(relative) 读到的内容太短，扫描面可疑")
        return body
    }

    /// 表与裁决住在 Core，`WorkspaceStore` 只消费它们。
    func testStoreConsumesTheCoreRegistryInsteadOfJudgingAgain() throws {
        let body = try text("App/WorkspaceStore.swift")
        for anchor in [
            "@Published private(set) var registry = WorkspaceRegistry()",
            "var knownWorkspaces: [KnownWorkspace] { registry.candidates }",
            "func switchTo(_ id: UUID) async",
            "switch registry.decision(for: id) {",
            "registry.add(",
            "registry.activate(id)",
            "WorkspaceRegistry.reconciled("
        ] {
            XCTAssertTrue(body.contains(anchor), "WorkspaceStore 里缺少锚点：\(anchor)")
        }
        // 反向：`choose` 里不许再有「清空书签再存」那一步 —— 那样已知工作区表永远只有一条，
        // 切换无从谈起。判在**函数体内**（`clear()` 里当然还有 removeAll，那是另一件事）。
        guard let start = body.range(of: "func choose("),
              let end = body.range(of: "func switchTo(", range: start.upperBound..<body.endIndex)
        else {
            XCTFail("`choose` / `switchTo` 有一处找不到了，这个反向判据失去目标")
            return
        }
        let chooseBody = String(body[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(
            chooseBody.contains("removeAll()"),
            "`choose` 里还在清空书签表：已知工作区永远只有一条"
        )
    }

    /// 两个入口同一份列表、同一个动作。
    func testBothEntryPointsShareOneListAndOneAction() throws {
        let switcher = try text("App/Views/WorkspaceSwitcher.swift")
        XCTAssertEqual(
            switcher.components(separatedBy: "workspace.switchTo(item.id)").count - 1,
            2,
            "切换组件里应有两处入口（标头菜单 + 首页行），都调同一个 `switchTo`"
        )
        XCTAssertTrue(switcher.contains("workspace.knownWorkspaces"), "切换组件应读同一份列表来源")

        let explorer = try text("App/Views/WorkspaceExplorerView.swift")
        XCTAssertTrue(explorer.contains("WorkspaceSwitchMenu()"), "文件树标头没有接切换菜单")

        let home = try text("App/Views/WorkspaceAreaView.swift")
        XCTAssertTrue(home.contains("WorkspaceKnownRow(item: item)"), "首页没有接同一行组件")
        XCTAssertTrue(home.contains("workspace.knownWorkspaces"), "首页应读同一份已知工作区表")
        // 反向：首页不许再拿页签历史当工作区列表（历史 ≠ 授权）。
        XCTAssertFalse(
            home.contains("tabs.history.workspaces"),
            "首页还在用页签历史里的工作区路径：那不是授权表，沙箱下点了也切不过去"
        )
    }

    /// 不可用那几档的理由只从语言表出（源码里不留人话字面量）。
    func testRefusalTextsComeFromTheLanguageTable() throws {
        let body = try text("App/WorkspaceStore.swift")
        for key in [
            "L(.workspaceUnavailableMissing)",
            "L(.workspaceUnavailableDenied)",
            "L(.workspaceUnavailableUnresolved)"
        ] {
            XCTAssertTrue(body.contains(key), "拒绝切过去时缺一句：\(key)")
        }
        let switcher = try text("App/Views/WorkspaceSwitcher.swift")
        for key in [
            "L(.workspaceUnavailableShortMissing)",
            "L(.workspaceUnavailableShortDenied)",
            "L(.workspaceUnavailableShortUnresolved)",
            "L(.workspaceSwitch)"
        ] {
            XCTAssertTrue(switcher.contains(key), "列表行缺一句：\(key)")
        }
    }

    /// 语言表：七个新键中英齐（少一侧 ⇒ 切到英文界面就是空格子）。
    func testNewLanguageKeysAreBilingual() throws {
        let body = try text("Core/Localization.swift")
        for key in [
            "workspaceUnavailableMissing",
            "workspaceUnavailableDenied",
            "workspaceUnavailableUnresolved",
            "workspaceUnavailableShortMissing",
            "workspaceUnavailableShortDenied",
            "workspaceUnavailableShortUnresolved",
            "workspaceSwitchActive"
        ] {
            XCTAssertTrue(
                body.contains("case \(key)\n") || body.contains("case \(key)"),
                "语言表枚举里没有 \(key)"
            )
            let row = ".\(key): [.simplifiedChinese:"
            guard let start = body.range(of: row) else {
                XCTFail("语言表里没有 \(key) 的中文一格")
                continue
            }
            let slice = String(body[start.lowerBound...].prefix(400))
            XCTAssertTrue(slice.contains(".english:"), "\(key) 少了英文一格")
        }
    }

    /// 可用性只能由 `DirectoryAccessStatus` 派生（不许在别处另写一套判定）。
    func testAvailabilityIsDerivedFromDirectoryAccessStatus() throws {
        let body = try text("Core/WorkspaceRegistry.swift")
        for anchor in [
            "case .granted: self = .available",
            "case .notAuthorized: self = .notAuthorized",
            "case .missing: self = .missing",
            "case .denied: self = .denied",
            "case .resolutionFailed: self = .unresolved"
        ] {
            XCTAssertTrue(body.contains(anchor), "可用性映射缺一档：\(anchor)")
        }
        // 活动状态只有一个来源：`Entry` 不许自己带 `isActive`（否则表里出现两处说法）。
        XCTAssertFalse(
            body.contains("public var isActive: Bool\n\n        public init(\n            id: UUID,"),
            "`Entry` 里不该有 isActive —— 活动状态只能由 `activeID` 决定"
        )
    }
}
