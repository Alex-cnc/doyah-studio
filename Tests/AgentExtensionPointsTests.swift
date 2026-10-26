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

/// `FR-AGT-LINK-EXT-003` 的**调用点**判据（契约的第五条在那个文件里，接线在这里）。
///
/// 钉的是三件事：① 不注入 = 旧行为逐字不变；② 注入之后钩子**只能收紧**（放行抬不动待批、
/// 挂了直接拒）；③ 每个被求值的钩子都留痕（含失败的），且来源**只管自己那一件能力**。
final class AgentPolicyCallSiteTests: XCTestCase {

    /// 按跳脚本吐事件的假模型（记录请求次数）。
    private final class ScriptedStreamingClient: LLMStreamingClient, @unchecked Sendable {
        var hops: [[LLMStreamEvent]]
        private(set) var requests: [LLMRequest] = []

        init(_ hops: [[LLMStreamEvent]]) { self.hops = hops }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            requests.append(request)
            let events = hops.isEmpty ? [.textDelta("（脚本用尽）"), .done] : hops.removeFirst()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    private final class RecordingDispatcher: AgentToolDispatcher, @unchecked Sendable {
        private(set) var invoked: [AgentToolInvocation] = []
        var outcome: AgentToolOutcome = .file(
            AgentToolFileOutput(path: "a.txt", text: "内容", truncated: false, totalBytes: 6))

        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            invoked.append(invocation)
            return outcome
        }
    }

    /// 固定的钩子来源（判据要能造任意结论，包括「钩子自己挂了」）。
    private struct FixedHooks: AgentPolicyHookSource {
        let results: [AgentPolicyHookResult]
        func hookResults(for invocation: AgentToolInvocation, workspace: String) -> [AgentPolicyHookResult] {
            results
        }
    }

    private final class RecordingAudit: AgentAuditSink, @unchecked Sendable {
        private(set) var records: [AgentActionRecord] = []
        func record(_ record: AgentActionRecord) async { records.append(record) }
    }

    private var directory: URL!
    private var store: AgentSessionStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-policy-site-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = AgentSessionStore(directory: directory)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: helpers

    private var context: AgentLoopContext {
        AgentLoopContext(systemPrompt: "你是助手。", userPrompt: "读一下 a.txt",
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                 model: "fake", systemPrompt: "", userPrompt: ""),
                         sessionID: "s-policy", workspace: "ws-1")
    }

    private func toolHop(name: String = "read_file", arguments: String = #"{"path":"a.txt"}"#) -> [LLMStreamEvent] {
        [.toolCallDelta(index: 0, id: "call-0", name: name, argumentsFragment: arguments),
         .finished(reason: "tool_calls"), .done]
    }

    private func answerHop() -> [LLMStreamEvent] {
        [.textDelta("a.txt 的内容是「内容」"), .finished(reason: "stop"), .done]
    }

    private func loop(client: ScriptedStreamingClient,
                      dispatcher: RecordingDispatcher,
                      hooks: [AgentPolicyHookResult]?) -> AgentLoop {
        AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store,
                  policyHooks: hooks.map { FixedHooks(results: $0) })
    }

    private func manifest(
        id: String = "ext.policy",
        provides: [String] = ["read_file"],
        hooks: [AgentExtensionManifest.Hook] = []
    ) -> AgentExtensionManifest {
        AgentExtensionManifest(
            id: id,
            slot: AgentExtensionSlot.toolLibrary.manifestValue,
            provides: provides,
            permission: AgentExtensionManifest.Permission(readableDirectories: [], allowedCommands: []),
            hooks: hooks
        )
    }

    // MARK: - ① 不注入 = 旧行为逐字不变（既有判据一条都不必改）

    func testNoInjectionKeepsOldBehavior() async {
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()

        let result = await loop(client: client, dispatcher: dispatcher, hooks: nil).run(context: context)

        XCTAssertEqual(result.executedTools.map(\.name), ["read_file"])
        XCTAssertEqual(dispatcher.invoked.count, 1, "没有注入策略钩子时工具照旧执行一次")
        XCTAssertTrue(result.rejectedTools.isEmpty)
    }

    /// 注入了来源、但这一跳没有插件管（返回空）⇒ 也照旧执行（**空 ≠ 放行**，是不干预）。
    func testEmptyHookSetDoesNotIntervene() async {
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()

        let result = await loop(client: client, dispatcher: dispatcher, hooks: []).run(context: context)

        XCTAssertEqual(result.executedTools.map(\.name), ["read_file"])
        XCTAssertEqual(dispatcher.invoked.count, 1)
    }

    // MARK: - ② 只能收紧：allow 抬不动结论，deny/待批拦得住

    func testAllowHookLeavesToolExecuted() async {
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()

        let result = await loop(client: client, dispatcher: dispatcher,
                                hooks: [AgentPolicyHookResult(hookID: "ext.policy:preToolUse", level: .allow)])
            .run(context: context)

        XCTAssertEqual(dispatcher.invoked.count, 1, "钩子说放行 ⇒ 不改变原判定")
        XCTAssertEqual(result.executedTools.map(\.name), ["read_file"])
    }

    func testDenyHookStopsDispatch() async {
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()

        let result = await loop(client: client, dispatcher: dispatcher,
                                hooks: [AgentPolicyHookResult(hookID: "ext.policy:preToolUse", level: .deny)])
            .run(context: context)

        XCTAssertEqual(dispatcher.invoked.count, 0, "被钩子拒 ⇒ 分发器一次都不许被调")
        XCTAssertTrue(result.executedTools.isEmpty)
        XCTAssertEqual(result.rejectedTools.map(\.reason), [AgentToolRefusal.deniedByPolicy.rawValue])
    }

    func testRequiresApprovalHookDefersExecution() async {
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()

        let result = await loop(client: client, dispatcher: dispatcher,
                                hooks: [AgentPolicyHookResult(hookID: "ext.policy:preToolUse", level: .requiresApproval)])
            .run(context: context)

        XCTAssertEqual(dispatcher.invoked.count, 0, "转待批 ⇒ 这一跳不执行")
        XCTAssertEqual(result.rejectedTools.map(\.reason), [AgentToolRefusal.approvalRequired.rawValue])
    }

    /// **fail-closed**：钩子自己挂了 ⇒ 直接拒，哪怕另一条钩子说放行。
    func testFailedHookFailsClosed() async {
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()

        let result = await loop(client: client, dispatcher: dispatcher, hooks: [
            AgentPolicyHookResult(hookID: "ext.a:preToolUse", level: .allow),
            AgentPolicyHookResult(hookID: "ext.b:preToolUse", level: .allow, failed: true),
        ]).run(context: context)

        XCTAssertEqual(dispatcher.invoked.count, 0)
        XCTAssertEqual(result.rejectedTools.map(\.reason), [AgentToolRefusal.deniedByPolicy.rawValue])
    }

    /// 多条钩子取最严那一档（这里两档都不到 deny ⇒ 结果是待批，不是放行）。
    func testTwoHooksTakeTheStrictest() async {
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()

        let result = await loop(client: client, dispatcher: dispatcher, hooks: [
            AgentPolicyHookResult(hookID: "ext.a:preToolUse", level: .allow),
            AgentPolicyHookResult(hookID: "ext.b:preToolUse", level: .requiresApproval),
        ]).run(context: context)

        XCTAssertEqual(result.rejectedTools.map(\.reason), [AgentToolRefusal.approvalRequired.rawValue])
        XCTAssertEqual(dispatcher.invoked.count, 0)
    }

    // MARK: - ③ 留痕：每个被求值的钩子都在审计里（失败的也在）

    func testAuditKeepsEveryEvaluatedHook() async {
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()
        let audit = RecordingAudit()

        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store, audit: audit,
                             policyHooks: FixedHooks(results: [
                                AgentPolicyHookResult(hookID: "ext.a:preToolUse", level: .allow),
                                AgentPolicyHookResult(hookID: "ext.b:preToolUse", level: .allow, failed: true),
                             ]))
        _ = await loop.run(context: context)

        let policyRecords = audit.records.filter { ($0.detail ?? "").contains("policy:") }
        XCTAssertEqual(policyRecords.count, 1, "一次判定一条留痕")
        let detail = policyRecords.first?.detail ?? ""
        XCTAssertTrue(detail.contains("ext.a:preToolUse"), "失败的钩子也要点名，别只记结论")
        XCTAssertTrue(detail.contains("ext.b:preToolUse"))
        XCTAssertTrue(detail.contains("failed=true"), "要有「它挂了」这一格")
        XCTAssertEqual(policyRecords.first?.outcome, .denied)
    }

    // MARK: - ④ 真实来源：只管自己那一件能力，只认 preToolUse，卸了就不管

    func testSourceOnlyGovernsItsOwnCapability() {
        var desk = AgentExtensionDesk()
        desk.install(manifest(provides: ["read_file"],
                              hooks: [.init(kind: .preToolUse, maxTighten: .deny)]))
        let source = AgentExtensionPolicySource(desk: desk)

        XCTAssertEqual(
            source.hookResults(for: AgentToolInvocation(name: "read_file", argumentsJSON: "{}"), workspace: "ws").count,
            1)
        XCTAssertTrue(
            source.hookResults(for: AgentToolInvocation(name: "write_file", argumentsJSON: "{}"), workspace: "ws").isEmpty,
            "没提供这件工具 ⇒ 不许出结论（更不许替别人的工具判）")
    }

    func testSourceIgnoresOtherHookKinds() {
        var desk = AgentExtensionDesk()
        desk.install(manifest(hooks: [.init(kind: .preModelCall, maxTighten: .deny),
                                     .init(kind: .preCommand, maxTighten: .deny)]))
        let source = AgentExtensionPolicySource(desk: desk)

        XCTAssertTrue(
            source.hookResults(for: AgentToolInvocation(name: "read_file", argumentsJSON: "{}"), workspace: "ws").isEmpty,
            "preModelCall / preCommand 是另外两个挂点，不许在工具调用处冒充")
    }

    func testSourceRespectsNarrowedCapabilities() {
        var desk = AgentExtensionDesk()
        desk.install(manifest(provides: ["read_file"], hooks: [.init(kind: .preToolUse, maxTighten: .deny)]),
                     capabilities: [])
        let source = AgentExtensionPolicySource(desk: desk)

        XCTAssertTrue(
            source.hookResults(for: AgentToolInvocation(name: "read_file", argumentsJSON: "{}"), workspace: "ws").isEmpty,
            "用户一样能力都没批 ⇒ 钩子也不许管")
    }

    func testUninstalledPluginNoLongerGoverns() {
        var desk = AgentExtensionDesk()
        desk.install(manifest(hooks: [.init(kind: .preToolUse, maxTighten: .deny)]))

        _ = desk.uninstall(pluginID: "ext.policy")
        let source = AgentExtensionPolicySource(desk: desk)

        XCTAssertTrue(
            source.hookResults(for: AgentToolInvocation(name: "read_file", argumentsJSON: "{}"), workspace: "ws").isEmpty)
    }

    /// 清单三档 → 判定三档（`note` 只是提示，不改判定）。
    func testTightenLevelMapping() {
        XCTAssertEqual(AgentExtensionPolicySource.level(.note), .allow)
        XCTAssertEqual(AgentExtensionPolicySource.level(.requiresApproval), .requiresApproval)
        XCTAssertEqual(AgentExtensionPolicySource.level(.deny), .deny)
    }

    /// 端到端：装一个声明「工具调用要审批」的插件 ⇒ 循环里那件工具真的不执行。
    func testInstalledPluginActuallyStopsTheLoop() async {
        var desk = AgentExtensionDesk()
        desk.install(manifest(provides: ["read_file"],
                              hooks: [.init(kind: .preToolUse, maxTighten: .requiresApproval)]))
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()
        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store,
                             policyHooks: AgentExtensionPolicySource(desk: desk))

        let result = await loop.run(context: context)

        XCTAssertEqual(dispatcher.invoked.count, 0, "插件声明的收紧档在真实调用点生效")
        XCTAssertEqual(result.rejectedTools.map(\.reason), [AgentToolRefusal.approvalRequired.rawValue])
    }

    // MARK: - ④ 基线（`FR-AGT-OPS-OBS-002` 审批策略可配置）：用户定的宽严在同一个调用点生效

    /// 基线 = 每次都要批，**一个插件都没装** ⇒ 工具也不执行（这条在加基线之前是放行的）。
    func testBaselineAskStopsToolsWithoutAnyHooks() async {
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()
        let audit = RecordingAudit()
        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store, audit: audit,
                             policyBaseline: .requiresApproval)

        let result = await loop.run(context: context)

        XCTAssertEqual(dispatcher.invoked.count, 0)
        XCTAssertEqual(result.rejectedTools.map(\.reason), [AgentToolRefusal.approvalRequired.rawValue])
        let policyRecords = audit.records.filter { ($0.detail ?? "").contains("policy:") }
        XCTAssertEqual(policyRecords.count, 1)
        XCTAssertEqual(policyRecords.first?.outcome, .pendingApproval)
        XCTAssertTrue(policyRecords.first?.detail?.contains("baseline=ask") ?? false,
                      "留痕要点名是谁收紧的（这里没有插件，收的就是用户那一下）")
    }

    func testBaselineDenyBlocksEvenPlainRead() async {
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()
        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store,
                             policyBaseline: .deny)

        let result = await loop.run(context: context)

        XCTAssertEqual(dispatcher.invoked.count, 0)
        XCTAssertEqual(result.rejectedTools.map(\.reason), [AgentToolRefusal.deniedByPolicy.rawValue])
    }

    /// 默认基线（`allow`）+ 没装钩子 ⇒ 旧行为逐字不变，**审计里一条 policy 都不多出来**。
    /// 这条是防止「加了基线之后每件工具都被记一笔」，把审计刷成噪声。
    func testDefaultBaselineAddsNoPolicyAuditRecords() async {
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()
        let audit = RecordingAudit()
        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store, audit: audit)

        _ = await loop.run(context: context)

        XCTAssertEqual(dispatcher.invoked.count, 1, "基线是默认值时工具照旧执行")
        XCTAssertTrue(audit.records.filter { ($0.detail ?? "").contains("policy:") }.isEmpty)
    }

    /// **插件不许替用户放宽**：基线已经是 `deny`，插件声明「放行」也拦得住。
    func testPluginCannotLoosenUserBaseline() async {
        let client = ScriptedStreamingClient([toolHop(), answerHop()])
        let dispatcher = RecordingDispatcher()
        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store,
                             policyHooks: FixedHooks(results: [
                                AgentPolicyHookResult(hookID: "ext.nice:preToolUse", level: .allow),
                             ]),
                             policyBaseline: .deny)

        let result = await loop.run(context: context)

        XCTAssertEqual(dispatcher.invoked.count, 0)
        XCTAssertEqual(result.rejectedTools.map(\.reason), [AgentToolRefusal.deniedByPolicy.rawValue])
    }
}

/// `FR-AGT-LINK-EXT-003` 的**真插件目录**判据：目录 ⇒ 台账。
///
/// 钉四件事：目录不存在不是错误 · 合法清单装得上且能力可调 · 坏清单逐条点名且不连坐别家 ·
/// 装配结论与文件系统遍历顺序无关。
final class AgentExtensionCatalogTests: XCTestCase {

    private var root: URL!
    private var plugins: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-ext-catalog-\(UUID().uuidString)", isDirectory: true)
        plugins = root.appendingPathComponent(AgentExtensionCatalog.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func writePlugin(_ directoryName: String, manifest: AgentExtensionManifest) throws -> URL {
        let directory = plugins.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent(AgentExtensionValidator.manifestFileName))
        return directory
    }

    private func manifest(id: String, provides: [String] = ["sample_tool"],
                          hooks: [AgentExtensionManifest.Hook] = []) -> AgentExtensionManifest {
        AgentExtensionManifest(
            id: id,
            slot: AgentExtensionSlot.toolLibrary.manifestValue,
            provides: provides,
            permission: AgentExtensionManifest.Permission(readableDirectories: [], allowedCommands: []),
            hooks: hooks)
    }

    /// 目录不存在 = 一个都没装（全新安装，不是错误，也不该报一句「读不出来」）。
    func testMissingDirectoryIsNotAnError() {
        let loaded = AgentExtensionCatalog.load(directory: plugins)

        XCTAssertTrue(loaded.desk.installedIDs.isEmpty)
        XCTAssertTrue(loaded.problems.isEmpty)
    }

    /// 合法清单 ⇒ 装上；装上的能力真的能调（台账不是一张摆设）。
    func testValidManifestIsInstalledAndCallable() throws {
        let directory = try writePlugin("ext.a", manifest: manifest(id: "ext.a"))

        let loaded = AgentExtensionCatalog.load(directory: plugins)

        XCTAssertEqual(loaded.desk.installedIDs, ["ext.a"])
        XCTAssertTrue(loaded.problems.isEmpty)
        XCTAssertEqual(loaded.desk.call(slot: .toolLibrary, capability: "sample_tool", pluginID: "ext.a"), .allowed)
        XCTAssertEqual(loaded.desk.grant(for: "ext.a")?.ownedPaths, [directory.path],
                       "插件目录登记为自有路径 —— 没有面板时这是卸载唯一的清理依据")
    }

    /// 坏 JSON 只点名它自己，别家照装。
    func testBrokenManifestDoesNotBlockOthers() throws {
        _ = try writePlugin("ext.good", manifest: manifest(id: "ext.good"))
        let broken = plugins.appendingPathComponent("ext.broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{ 这不是 JSON".utf8)
            .write(to: broken.appendingPathComponent(AgentExtensionValidator.manifestFileName))

        let loaded = AgentExtensionCatalog.load(directory: plugins)

        XCTAssertEqual(loaded.desk.installedIDs, ["ext.good"])
        XCTAssertEqual(loaded.problems.map(\.file), ["ext.broken/extension.json"])
        XCTAssertEqual(loaded.problems.map(\.rejection), [.manifestUnreadable])
    }

    /// 缺权限块 ⇒ 具名拒绝（不是「装上了但什么都不能做」）。
    func testManifestWithoutPermissionIsRejectedByName() throws {
        let noPermission = AgentExtensionManifest(
            id: "ext.noperm", slot: AgentExtensionSlot.toolLibrary.manifestValue,
            provides: ["sample_tool"], permission: nil)
        _ = try writePlugin("ext.noperm", manifest: noPermission)

        let loaded = AgentExtensionCatalog.load(directory: plugins)

        XCTAssertTrue(loaded.desk.installedIDs.isEmpty)
        XCTAssertEqual(loaded.problems.map(\.rejection), [.permissionNotDeclared])
    }

    /// 没有清单的普通子目录直接跳过（既不算装上、也不算问题）。
    func testDirectoryWithoutManifestIsSkipped() throws {
        try FileManager.default.createDirectory(at: plugins.appendingPathComponent("just-a-folder"),
                                                withIntermediateDirectories: true)

        let loaded = AgentExtensionCatalog.load(directory: plugins)

        XCTAssertTrue(loaded.desk.installedIDs.isEmpty)
        XCTAssertTrue(loaded.problems.isEmpty)
    }

    /// 装配结论与遍历顺序无关（同一批插件，创建顺序反过来也得到同一份排序）。
    func testInstallOrderIsDeterministic() throws {
        _ = try writePlugin("ext.z", manifest: manifest(id: "ext.z"))
        _ = try writePlugin("ext.a", manifest: manifest(id: "ext.a"))
        _ = try writePlugin("ext.m", manifest: manifest(id: "ext.m"))

        let first = AgentExtensionCatalog.load(directory: plugins).desk.installedIDs
        let second = AgentExtensionCatalog.load(directory: plugins).desk.installedIDs

        XCTAssertEqual(first, ["ext.a", "ext.m", "ext.z"])
        XCTAssertEqual(first, second)
    }
}
