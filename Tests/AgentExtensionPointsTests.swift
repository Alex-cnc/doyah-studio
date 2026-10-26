import XCTest
@testable import DoyahCore

/// `FR-AGT-LINK-EXT-003` 的契约面判据（①权限声明 ②未授权不可调用 ③卸载无残留
/// ④扩展点仅六类、内核五项不可插件化 ⑤钩子只能收紧 ⑥装卸不改动已装能力的授权范围）。
///
/// 每条验收要点都两向钉：**正常**（该放行的放行）+ **该拒**（越界的具名拒绝）+
/// **边界**（前缀 / 空串 / 内核名字混进 provides 这类「差一点就漏」的形状）。
final class AgentExtensionPointsTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-ext-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: helpers

    private var readRoot: String { root.appendingPathComponent("readable", isDirectory: true).path }
    private var writeRoot: String { root.appendingPathComponent("data", isDirectory: true).path }

    private func manifest(
        id: String = "ext.sample",
        slot: String = AgentExtensionSlot.toolLibrary.manifestValue,
        provides: [String] = ["sample_tool"],
        directories: [String]? = nil,
        commands: [String]? = nil,
        hooks: [AgentExtensionManifest.Hook] = [],
        declaresPermission: Bool = true
    ) -> AgentExtensionManifest {
        let permission = declaresPermission
            ? AgentExtensionManifest.Permission(
                readableDirectories: directories ?? [readRoot],
                allowedCommands: commands ?? ["ls"]
            )
            : nil
        return AgentExtensionManifest(
            id: id,
            slot: slot,
            provides: provides,
            permission: permission,
            hooks: hooks
        )
    }

    // MARK: ① 清单写明权限

    func testManifestDecodesDeclaredPermission() throws {
        let json = """
        {
          "id": "ext.sample",
          "slot": "tool",
          "provides": ["sample_tool"],
          "permission": { "readableDirectories": ["\(readRoot)"], "allowedCommands": ["ls"] },
          "hooks": [{ "kind": "preToolUse", "maxTighten": "requiresApproval", "tighteningOnly": true }]
        }
        """
        let verdict = AgentExtensionValidator.decode(Data(json.utf8))
        let decoded = try XCTUnwrap(verdict.manifest, "合法的清单必须可装，读数：\(verdict)")
        XCTAssertEqual(decoded.id, "ext.sample")
        XCTAssertEqual(decoded.slot, "tool")
        XCTAssertEqual(decoded.permission?.readableDirectories, [readRoot])
        XCTAssertEqual(decoded.permission?.allowedCommands, ["ls"])
        XCTAssertEqual(decoded.hooks.count, 1)
        XCTAssertEqual(decoded.hooks.first?.maxTighten, .requiresApproval)
    }

    /// 该拒：清单里**根本没写权限块** ≠ 权限为空。
    func testManifestWithoutPermissionIsRejected() {
        let verdict = AgentExtensionValidator.validate(manifest(declaresPermission: false))
        XCTAssertEqual(verdict.rejection, .permissionNotDeclared)
    }

    /// 该拒：坏 JSON 不抛给宿主，落具名拒绝。
    func testBrokenJSONIsRejected() {
        XCTAssertEqual(AgentExtensionValidator.decode(Data("not a manifest".utf8)).rejection, .manifestUnreadable)
        XCTAssertEqual(AgentExtensionValidator.decode(Data("{}".utf8)).rejection, .manifestUnreadable)
    }

    /// 边界：声明了权限但是**空集**（`{}` 或两个空数组）—— 装得上，但什么都不许做。
    func testEmptyPermissionDeclarationGrantsNothing() {
        var desk = AgentExtensionDesk()
        let empty = AgentExtensionManifest(
            id: "ext.closed",
            slot: AgentExtensionSlot.toolLibrary.manifestValue,
            provides: ["closed_tool"],
            permission: .init(readableDirectories: [], allowedCommands: [])
        )
        XCTAssertEqual(desk.install(empty).rejection, nil, "空声明本身是合法声明（fail-closed 的那一端）")
        XCTAssertEqual(desk.read(path: readRoot, pluginID: "ext.closed"), .denied(.directoryNotDeclared))
        XCTAssertEqual(desk.run(command: "ls", pluginID: "ext.closed"), .denied(.commandNotDeclared))
        // 能力仍可调（它声明了 provides，用户装的时候把能力批了）
        XCTAssertEqual(desk.call(slot: .toolLibrary, capability: "closed_tool", pluginID: "ext.closed"), .allowed)
    }

    // MARK: ② 未授权的能力不可调用

    func testGrantedCapabilityIsCallableAndOthersAreNot() {
        var desk = AgentExtensionDesk()
        desk.install(manifest(provides: ["sample_tool", "extra_tool"]), capabilities: ["sample_tool"])

        XCTAssertEqual(desk.call(slot: .toolLibrary, capability: "sample_tool", pluginID: "ext.sample"), .allowed)
        // 该拒：声明里有、这次没批 ⇒ 不可调用
        XCTAssertEqual(
            desk.call(slot: .toolLibrary, capability: "extra_tool", pluginID: "ext.sample"),
            .denied(.capabilityNotGranted)
        )
        // 该拒：压根没声明的名字
        XCTAssertEqual(
            desk.call(slot: .toolLibrary, capability: "rm_rf", pluginID: "ext.sample"),
            .denied(.capabilityNotGranted)
        )
    }

    /// 装了才生效：没装 / 装被拒 ⇒ 一条都调不到。
    func testCallBeforeInstallIsDenied() {
        var desk = AgentExtensionDesk()
        XCTAssertEqual(
            desk.call(slot: .toolLibrary, capability: "sample_tool", pluginID: "ext.sample"),
            .denied(.notInstalled)
        )
        // 装被拒（缺权限块）之后仍不可调：拒绝不许留下半个可调的能力
        XCTAssertNotNil(desk.install(manifest(declaresPermission: false)).rejection)
        XCTAssertEqual(desk.installedIDs, [])
        XCTAssertEqual(
            desk.call(slot: .toolLibrary, capability: "sample_tool", pluginID: "ext.sample"),
            .denied(.notInstalled)
        )
    }

    func testSlotMismatchIsDenied() {
        var desk = AgentExtensionDesk()
        desk.install(manifest())
        XCTAssertEqual(
            desk.call(slot: .memoryBackend, capability: "sample_tool", pluginID: "ext.sample"),
            .denied(.slotMismatch)
        )
    }

    func testReadInsideDeclaredDirectoryAllowedOutsideDenied() {
        var desk = AgentExtensionDesk()
        desk.install(manifest())
        XCTAssertEqual(desk.read(path: readRoot + "/a.txt", pluginID: "ext.sample"), .allowed)
        XCTAssertEqual(desk.read(path: readRoot, pluginID: "ext.sample"), .allowed)
        XCTAssertEqual(desk.read(path: writeRoot + "/a.txt", pluginID: "ext.sample"), .denied(.directoryNotDeclared))
        XCTAssertEqual(desk.read(path: "/etc/passwd", pluginID: "ext.sample"), .denied(.directoryNotDeclared))
    }

    /// 边界：路径包含按**分量**比，不做字符串前缀（`/a/b` 不放行 `/a/bc`）。
    func testPathContainmentUsesComponentsNotStringPrefix() {
        var desk = AgentExtensionDesk()
        desk.install(manifest(directories: [readRoot], commands: ["ls"]))
        XCTAssertEqual(desk.read(path: readRoot + "sibling/x.txt", pluginID: "ext.sample"), .denied(.directoryNotDeclared))
        // `..` 穿越：标准化之后落在根外
        XCTAssertEqual(desk.read(path: readRoot + "/../escape.txt", pluginID: "ext.sample"), .denied(.directoryNotDeclared))
        // 声明了但这次安装没批 ⇒ 另一条具名拒绝（不是「未声明」）
        var partial = AgentExtensionDesk()
        partial.install(manifest(), directories: [])
        XCTAssertEqual(partial.read(path: readRoot + "/a.txt", pluginID: "ext.sample"), .denied(.directoryNotGranted))
    }

    func testRunDeclaredCommandAllowedUndeclaredDenied() {
        var desk = AgentExtensionDesk()
        desk.install(manifest(commands: ["ls", "git status"]))
        XCTAssertEqual(desk.run(command: "ls", pluginID: "ext.sample"), .allowed)
        XCTAssertEqual(desk.run(command: "ls -la", pluginID: "ext.sample"), .allowed)
        XCTAssertEqual(desk.run(command: "git status", pluginID: "ext.sample"), .allowed)
        XCTAssertEqual(desk.run(command: "rm -rf /", pluginID: "ext.sample"), .denied(.commandNotDeclared))
        // 声明 `git status` 放行的是「这个子命令 + 参数」，**不是**「这个程序」——
        // `git push --force` 是另一件事，必须自己再声明一条（否则一条宽松声明就放行了整个 git）
        XCTAssertEqual(desk.run(command: "git status --short", pluginID: "ext.sample"), .allowed)
        XCTAssertEqual(desk.run(command: "git push --force", pluginID: "ext.sample"), .denied(.commandNotDeclared))
    }

    /// 边界：声明 `ls` 不许放行 `lsblk`（另一个程序，字符串前缀会放过）。
    func testCommandPrefixBoundary() {
        var desk = AgentExtensionDesk()
        desk.install(manifest(commands: ["ls"]))
        XCTAssertEqual(desk.run(command: "lsblk", pluginID: "ext.sample"), .denied(.commandNotDeclared))
        XCTAssertEqual(desk.run(command: "ls  -la", pluginID: "ext.sample"), .allowed)
        var partial = AgentExtensionDesk()
        partial.install(manifest(commands: ["ls"]), commands: [])
        XCTAssertEqual(partial.run(command: "ls", pluginID: "ext.sample"), .denied(.commandNotGranted))
    }

    func testEmptyRequestsAreDenied() {
        var desk = AgentExtensionDesk()
        desk.install(manifest())
        XCTAssertEqual(desk.read(path: "   ", pluginID: "ext.sample"), .denied(.emptyRequest))
        XCTAssertEqual(desk.run(command: "", pluginID: "ext.sample"), .denied(.emptyRequest))
        XCTAssertEqual(
            desk.call(slot: .toolLibrary, capability: " ", pluginID: "ext.sample"),
            .denied(.emptyRequest)
        )
    }

    // MARK: ③ 卸载后无残留进程与配置文件

    func testUninstallRemovesOwnedFilesAndReportsCleanResidue() throws {
        let config = root.appendingPathComponent("config.json")
        let dataDir = root.appendingPathComponent("store", isDirectory: true)
        let dataFile = dataDir.appendingPathComponent("rows.db")
        let neighbour = root.appendingPathComponent("neighbour.txt")
        try Data("{}".utf8).write(to: config)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try Data("rows".utf8).write(to: dataFile)
        try Data("other".utf8).write(to: neighbour)

        var desk = AgentExtensionDesk()
        desk.install(manifest(), ownedPaths: [config.path, dataDir.path], childProcesses: [4242])

        let receipt = desk.uninstall(pluginID: "ext.sample")
        XCTAssertTrue(receipt.wasInstalled)
        XCTAssertEqual(receipt.removedPaths.sorted(), [config.path, dataDir.path].sorted())
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataDir.path))
        // 不许顺手删别人的东西
        XCTAssertTrue(FileManager.default.fileExists(atPath: neighbour.path), "只许删自己声明拥有的路径")
        // 进程交回去停；停了之后残留才真的干净
        XCTAssertEqual(receipt.processesToStop, [4242])
        XCTAssertEqual(receipt.residue.paths, [])
        XCTAssertEqual(receipt.residue.processes, [4242], "宿主还没报告进程终止 ⇒ 残留读数如实不干净")
        XCTAssertFalse(receipt.residue.grantRemains)
        desk.markProcessTerminated(pluginID: "ext.sample", processID: 4242)
        XCTAssertTrue(desk.residue(pluginID: "ext.sample").isClean)
        // 卸完之后那条能力也调不到了
        XCTAssertEqual(
            desk.call(slot: .toolLibrary, capability: "sample_tool", pluginID: "ext.sample"),
            .denied(.notInstalled)
        )
    }

    func testUninstallUnknownPluginIsNoOp() {
        var desk = AgentExtensionDesk()
        let receipt = desk.uninstall(pluginID: "ext.never")
        XCTAssertFalse(receipt.wasInstalled)
        XCTAssertEqual(receipt.removedPaths, [])
        XCTAssertTrue(receipt.residue.isClean)
    }

    // MARK: ④ 扩展点仅六类、内核五项不可插件化

    func testSlotListIsClosedAtSixAndKernelAtFive() {
        XCTAssertEqual(AgentExtensionSlot.allCases.count, 6)
        XCTAssertEqual(AgentKernelFacet.allCases.count, 5)
        let slots = Set(AgentExtensionSlot.allCases.map(\.manifestValue))
        let kernel = Set(AgentKernelFacet.allCases.map(\.manifestValue))
        XCTAssertEqual(slots, ["memory", "model", "tool", "schedule", "channel", "storage"])
        XCTAssertEqual(kernel, ["loop", "stop", "prior", "session", "queue"])
        XCTAssertTrue(slots.isDisjoint(with: kernel), "两套名字不许重叠，否则拒绝原因会指错方向")
    }

    func testKernelFacetAsSlotIsRejected() {
        for facet in AgentKernelFacet.allCases {
            let verdict = AgentExtensionValidator.validate(manifest(slot: facet.manifestValue))
            XCTAssertEqual(verdict.rejection, .slotIsKernelFacet, "想接管 \(facet.manifestValue) 必须被拒")
        }
    }

    func testUnknownSlotIsRejected() {
        XCTAssertEqual(AgentExtensionValidator.validate(manifest(slot: "seventh")).rejection, .slotUnknown)
        XCTAssertEqual(AgentExtensionValidator.validate(manifest(slot: "TOOL")).rejection, .slotUnknown,
                       "槽位字面量大小写敏感 —— 拼错就是拼错，不做模糊匹配")
    }

    func testKernelFacetInProvidesIsRejected() {
        XCTAssertEqual(
            AgentExtensionValidator.validate(manifest(provides: ["sample_tool", "loop"])).rejection,
            .providesKernelFacet
        )
    }

    func testEmptyProvidesOrIDIsRejected() {
        XCTAssertEqual(AgentExtensionValidator.validate(manifest(provides: [])).rejection, .providesEmpty)
        XCTAssertEqual(AgentExtensionValidator.validate(manifest(provides: ["  "])).rejection, .providesEmpty)
        XCTAssertEqual(AgentExtensionValidator.validate(manifest(id: "  ")).rejection, .idEmpty)
    }

    // MARK: ⑤ 策略钩子只能收紧、不能放宽（fail-closed）

    func testHookCannotWidenDeny() {
        let verdict = AgentPolicyCombiner.evaluate(
            base: .deny,
            hooks: [.init(hookID: "ext.sample/preToolUse", level: .allow)]
        )
        XCTAssertEqual(verdict.decision, .deny, "钩子说放行也抬不动基线的拒绝")
        XCTAssertEqual(verdict.traces.count, 1)
        XCTAssertFalse(verdict.traces[0].tightened)
    }

    func testHookCannotDowngradeApprovalToAllow() {
        let verdict = AgentPolicyCombiner.evaluate(
            base: .requiresApproval,
            hooks: [.init(hookID: "ext.sample/preModelCall", level: .allow)]
        )
        XCTAssertEqual(verdict.decision, .requiresApproval, "审批那一档降不下去 —— 否则就是「钩子替人放行」")
    }

    func testHookRaisesAllowToApprovalOrDeny() {
        let approval = AgentPolicyCombiner.evaluate(
            base: .allow,
            hooks: [.init(hookID: "ext.sample/preCommand", level: .requiresApproval)]
        )
        XCTAssertEqual(approval.decision, .requiresApproval)
        XCTAssertTrue(approval.traces[0].tightened)

        let deny = AgentPolicyCombiner.evaluate(
            base: .allow,
            hooks: [
                .init(hookID: "ext.sample/preCommand", level: .requiresApproval),
                .init(hookID: "ext.other/preCommand", level: .deny)
            ]
        )
        XCTAssertEqual(deny.decision, .deny)
        XCTAssertEqual(deny.traces.count, 2)
    }

    /// fail-closed：钩子自己挂了 ⇒ 拒绝（不是「忽略它，用别路的结果」）。
    func testFailingHookFailsClosed() {
        let verdict = AgentPolicyCombiner.evaluate(
            base: .allow,
            hooks: [
                .init(hookID: "ext.sample/preToolUse", level: .allow),
                .init(hookID: "ext.broken/preToolUse", level: .allow, failed: true)
            ]
        )
        XCTAssertEqual(verdict.decision, .deny)
        XCTAssertEqual(verdict.traces.count, 2)
        XCTAssertEqual(verdict.traces[1].failed, true)
        XCTAssertEqual(verdict.traces[1].level, .deny, "失败的那条留痕按它结论记：拒绝")
    }

    /// 审计不可绕过：每个被求值的钩子都有一条留痕（含失败的），没有「只要结论不留痕」的路径。
    func testTracesCoverEveryEvaluatedHook() {
        let hooks: [AgentPolicyHookResult] = [
            .init(hookID: "a", level: .allow),
            .init(hookID: "b", level: .requiresApproval),
            .init(hookID: "c", level: .allow, failed: true),
            .init(hookID: "d", level: .deny)
        ]
        let verdict = AgentPolicyCombiner.evaluate(base: .allow, hooks: hooks)
        XCTAssertEqual(verdict.traces.map(\.hookID), hooks.map(\.hookID), "顺序与条数一一对应")
        XCTAssertEqual(verdict.decision, .deny)
    }

    func testManifestDeclaringWideningHookIsRejected() {
        let widening = AgentExtensionManifest.Hook(kind: .preToolUse, maxTighten: .note, tighteningOnly: false)
        XCTAssertEqual(
            AgentExtensionValidator.validate(manifest(hooks: [widening])).rejection,
            .hookNotTighteningOnly
        )
        let tightening = AgentExtensionManifest.Hook(kind: .preToolUse, maxTighten: .deny)
        XCTAssertNil(AgentExtensionValidator.validate(manifest(hooks: [tightening])).rejection)
    }

    // MARK: ⑥ 装卸插件不改变已装能力的授权范围

    func testInstallingAndUninstallingAnotherPluginKeepsGrants() {
        var desk = AgentExtensionDesk()
        desk.install(manifest(id: "ext.a", provides: ["a_tool"]), childProcesses: [])
        let before = desk.grant(for: "ext.a")
        XCTAssertNotNil(before)

        desk.install(
            manifest(id: "ext.b", slot: AgentExtensionSlot.storage.manifestValue, provides: ["b_store"],
                     directories: [writeRoot], commands: []),
            ownedPaths: []
        )
        XCTAssertEqual(desk.grant(for: "ext.a"), before, "装第二个插件不许动第一个的授权面")

        _ = desk.uninstall(pluginID: "ext.b")
        XCTAssertEqual(desk.grant(for: "ext.a"), before, "卸第二个插件也不许动第一个的授权面")
        // 并且 acceess 结论逐条不变
        XCTAssertEqual(desk.call(slot: .toolLibrary, capability: "a_tool", pluginID: "ext.a"), .allowed)
        XCTAssertEqual(desk.read(path: readRoot + "/a.txt", pluginID: "ext.a"), .allowed)
        XCTAssertEqual(desk.read(path: writeRoot + "/b.txt", pluginID: "ext.a"), .denied(.directoryNotDeclared),
                       "B 的目录不会因为它装过就变成 A 的可读面")
        XCTAssertEqual(desk.installedIDs, ["ext.a"])
    }

    /// 边界：授权集合按声明的**交集**落账 —— 上层传进来的名字不在清单里就不生效（不能凭空扩权）。
    func testGrantIsIntersectedWithDeclaration() throws {
        var desk = AgentExtensionDesk()
        desk.install(
            manifest(provides: ["a_tool"], directories: [readRoot], commands: ["ls"]),
            capabilities: ["a_tool", "ghost_tool"],
            directories: [readRoot, "/etc"],
            commands: ["ls", "sh"]
        )
        let grant = try XCTUnwrap(desk.grant(for: "ext.sample"))
        XCTAssertEqual(grant.capabilities, ["a_tool"])
        XCTAssertEqual(grant.directories, [readRoot])
        XCTAssertEqual(grant.commands, ["ls"])
        XCTAssertEqual(desk.call(slot: .toolLibrary, capability: "ghost_tool", pluginID: "ext.sample"),
                       .denied(.capabilityNotGranted))
        XCTAssertEqual(desk.read(path: "/etc/passwd", pluginID: "ext.sample"), .denied(.directoryNotDeclared))
        XCTAssertEqual(desk.run(command: "sh -c id", pluginID: "ext.sample"), .denied(.commandNotDeclared))
    }
}
