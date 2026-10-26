import XCTest
@testable import DoyahCore

/// `FR-AGT-LINK-EXT-003` 的**界面那一半**判据：装卸面板拿到的读数对不对。
///
/// 面板上每一行都是从台账投影出来的 —— 判据钉的就是这层投影：
/// 装了谁（按 id 排序、一个不漏）、每个真授权了什么（去空白 / 丢空项 / 去重、顺序照清单）、
/// 没装上的为什么（ASCII 机器码点名，可 grep）、卸完还剩什么（残留读数不粉饰）。
/// 正常 / 该拒 / 边界三向都咬住，不拿「构造函数能调通」当验收。
final class AgentExtensionPanelTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-extpanel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: helpers

    private var plugins: URL { root.appendingPathComponent(AgentExtensionCatalog.folderName, isDirectory: true) }
    private var readRoot: String { root.appendingPathComponent("readable", isDirectory: true).path }

    private func manifest(
        id: String = "ext.sample",
        slot: String = AgentExtensionSlot.toolLibrary.manifestValue,
        provides: [String] = ["sample_tool"],
        directories: [String]? = nil,
        commands: [String]? = nil,
        hooks: [AgentExtensionManifest.Hook] = []
    ) -> AgentExtensionManifest {
        AgentExtensionManifest(
            id: id,
            slot: slot,
            provides: provides,
            permission: AgentExtensionManifest.Permission(
                readableDirectories: directories ?? [readRoot],
                allowedCommands: commands ?? ["ls"]),
            hooks: hooks)
    }

    private func writePlugin(_ name: String, manifest: AgentExtensionManifest) throws -> URL {
        let directory = plugins.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest)
            .write(to: directory.appendingPathComponent(AgentExtensionValidator.manifestFileName))
        return directory
    }

    // MARK: 正常：装了谁

    /// 目录不存在 = 面板一行不画、也不报假问题（全新安装不是错误）。
    func testEmptyDirectoryProjectsNothing() {
        let panel = AgentExtensionPanel(load: AgentExtensionCatalog.load(directory: plugins))

        XCTAssertTrue(panel.rows.isEmpty)
        XCTAssertTrue(panel.problems.isEmpty)
    }

    /// 装上的按 id 排序逐行列出 —— 面板顺序不随文件系统遍历顺序变。
    func testInstalledPluginsProjectSortedByID() throws {
        _ = try writePlugin("zeta", manifest: manifest(id: "ext.z"))
        _ = try writePlugin("alpha", manifest: manifest(id: "ext.a"))
        _ = try writePlugin("mid", manifest: manifest(id: "ext.m", provides: ["other_tool"]))

        let panel = AgentExtensionPanel(load: AgentExtensionCatalog.load(directory: plugins))

        XCTAssertEqual(panel.rows.map(\.id), ["ext.a", "ext.m", "ext.z"])
        XCTAssertTrue(panel.problems.isEmpty)
    }

    /// 一行里的「真授权面」照台账报：能力 / 可读目录 / 可跑命令 三项都不许拿清单声明冒充。
    func testRowReportsGrantedSurfaceNotDeclaredSurface() {
        var desk = AgentExtensionDesk()
        desk.install(
            manifest(provides: ["tool_a", "tool_b"], directories: [readRoot], commands: ["ls", "cat"]),
            capabilities: ["tool_a"],          // 只批一个能力
            directories: [],                   // 一个目录都不批
            commands: ["ls"]                   // 只批一条命令
        )

        let panel = AgentExtensionPanel(desk: desk)

        XCTAssertEqual(panel.rows.count, 1)
        XCTAssertEqual(panel.rows[0].provides, ["tool_a"], "没批的能力不许出现在面板上")
        XCTAssertEqual(panel.rows[0].readableDirectories, [], "没批的目录不许出现在面板上")
        XCTAssertEqual(panel.rows[0].allowedCommands, ["ls"], "没批的命令不许出现在面板上")
    }

    /// 空白、空项、重复项都在投影这一层归一 —— 面板不该出现空行与同一行两遍。
    func testNamesAreTrimmedDedupedAndEmptiesDropped() {
        var desk = AgentExtensionDesk()
        desk.install(
            manifest(provides: [" tool_a ", "tool_a", "  ", "tool_b", ""],
                     directories: [" \(readRoot) ", " "],
                     commands: ["ls", "ls", ""])
        )

        let row = AgentExtensionPanel(desk: desk).rows[0]

        XCTAssertEqual(row.provides, ["tool_a", "tool_b"])
        XCTAssertEqual(row.readableDirectories, [readRoot])
        XCTAssertEqual(row.allowedCommands, ["ls"])
    }

    /// 顺序照清单原文（不排序）：排序会让人对不上自己写的那份 extension.json。
    func testOrderFollowsManifestNotAlphabet() {
        var desk = AgentExtensionDesk()
        desk.install(manifest(provides: ["zeta_tool", "alpha_tool", "mid_tool"]))

        XCTAssertEqual(AgentExtensionPanel(desk: desk).rows[0].provides,
                       ["zeta_tool", "alpha_tool", "mid_tool"])
    }

    /// 钩子条数与自有路径条数是两件不同的事（钩子 0 条 ≠ 没权限；自有路径 0 条 ≠ 不用清理）。
    func testHookAndOwnedPathCountsAreSeparateReadings() {
        var desk = AgentExtensionDesk()
        desk.install(
            manifest(hooks: [.init(kind: .preToolUse, maxTighten: .deny)]),
            ownedPaths: [root.appendingPathComponent("owned-1").path,
                         root.appendingPathComponent("owned-2").path]
        )

        let row = AgentExtensionPanel(desk: desk).rows[0]

        XCTAssertEqual(row.hookCount, 1)
        XCTAssertEqual(row.ownedPathCount, 2)
    }

    // MARK: 该拒：没装上的为什么

    /// 没装上的逐条点名「哪个文件 + 哪条机器码」，且**不影响**装上的那些照常出行。
    func testProblemsCarryFileAndMachineCodeWithoutHidingInstalledRows() throws {
        _ = try writePlugin("good", manifest: manifest(id: "ext.good"))
        // 缺权限块 ⇒ 具名拒收
        let noPermission = AgentExtensionManifest(
            id: "ext.noperm", slot: AgentExtensionSlot.toolLibrary.manifestValue,
            provides: ["sample_tool"], permission: nil)
        _ = try writePlugin("noperm", manifest: noPermission)
        // 坏 JSON ⇒ 读不出来
        let broken = plugins.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("not json".utf8)
            .write(to: broken.appendingPathComponent(AgentExtensionValidator.manifestFileName))

        let panel = AgentExtensionPanel(load: AgentExtensionCatalog.load(directory: plugins))

        XCTAssertEqual(panel.rows.map(\.id), ["ext.good"])
        XCTAssertEqual(panel.problems.map(\.file), ["broken/extension.json", "noperm/extension.json"])
        XCTAssertEqual(panel.problems.map(\.code),
                       [AgentExtensionRejection.manifestUnreadable.rawValue,
                        AgentExtensionRejection.permissionNotDeclared.rawValue],
                       "机器码要能被 grep，不许只留一句人话")
    }

    // MARK: 卸：卸完还剩什么

    /// 卸载真删自有路径：面板出「无残留」，台账里这一行也消失。
    func testUninstallLeavesCleanResidueAndDropsTheRow() throws {
        let owned = root.appendingPathComponent("plugin-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: owned.appendingPathComponent("payload.bin"))
        var desk = AgentExtensionDesk()
        desk.install(manifest(id: "ext.gone"), ownedPaths: [owned.path])

        let receipt = desk.uninstall(pluginID: "ext.gone")
        let residue = AgentExtensionPanel.residue(of: receipt)
        let panel = AgentExtensionPanel(desk: desk)

        XCTAssertTrue(receipt.wasInstalled)
        XCTAssertEqual(receipt.removedPaths, [owned.path])
        XCTAssertTrue(residue.isClean, "盘上那份与授权都没有了才算无残留")
        XCTAssertTrue(panel.rows.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path), "卸载必须真删")
    }

    /// 删不掉的自有路径**如实留在残留读数里** —— 面板不许替它说「干净了」。
    func testResidueNamesWhatCouldNotBeRemoved() {
        let receipt = AgentExtensionUninstallReceipt(
            pluginID: "ext.stuck",
            wasInstalled: true,
            removedPaths: [],
            processesToStop: [4242],
            residue: AgentExtensionResidue(paths: ["/tmp/stuck/plugin.json"],
                                           processes: [4242],
                                           grantRemains: false))

        let residue = AgentExtensionPanel.residue(of: receipt)

        XCTAssertFalse(residue.isClean)
        XCTAssertEqual(residue.paths, ["/tmp/stuck/plugin.json"])
        XCTAssertEqual(residue.processes, [4242])
    }

    /// 卸一个没装过的：不假装成功（`wasInstalled = false`），残留也照实为零。
    func testUninstallUnknownPluginDoesNotPretendSuccess() {
        var desk = AgentExtensionDesk()
        desk.install(manifest(id: "ext.kept"))

        let receipt = desk.uninstall(pluginID: "ext.never-installed")
        let panel = AgentExtensionPanel(desk: desk)

        XCTAssertFalse(receipt.wasInstalled)
        XCTAssertTrue(AgentExtensionPanel.residue(of: receipt).isClean)
        XCTAssertEqual(panel.rows.map(\.id), ["ext.kept"], "卸别家不许动到这一家")
    }

    /// 卸掉再装回同一个 id：行回来，且再卸一次仍然照实删（上一次的卸载记录不干扰这次）。
    func testReinstallAfterUninstallStillUninstallsCleanly() throws {
        let owned = root.appendingPathComponent("reinstallable", isDirectory: true)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        var desk = AgentExtensionDesk()
        desk.install(manifest(id: "ext.round"), ownedPaths: [owned.path])
        _ = desk.uninstall(pluginID: "ext.round")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)

        desk.install(manifest(id: "ext.round"), ownedPaths: [owned.path])
        let reinstalled = AgentExtensionPanel(desk: desk)
        let secondReceipt = desk.uninstall(pluginID: "ext.round")

        XCTAssertEqual(reinstalled.rows.map(\.id), ["ext.round"])
        XCTAssertEqual(reinstalled.rows[0].ownedPathCount, 1)
        XCTAssertTrue(secondReceipt.wasInstalled, "装回来之后它又是一份在装的授权")
        XCTAssertEqual(secondReceipt.removedPaths, [owned.path])
        XCTAssertTrue(AgentExtensionPanel.residue(of: secondReceipt).isClean)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    }
}
