import XCTest
@testable import DoyahCore

/// 三档授权（§3.36）的判定面 —— 五条判据逐条打，读数打进日志。
///
/// 判据与反例（照详设 §3.36 的验收）：
/// ① 「仅这一次」⇒ 同工具第 2 次**仍询问**；
/// ② 「本会话内」⇒ 第 2 次不问、**换会话再问**（反例：写进全局 ⇒ 判红）；
/// ③ 「总是允许」⇒ 落盘、重启后不问，且**只覆盖那条路径**（反例：工具名单键 ⇒ 判红）；
/// ④ 不可逆（删除 / 对外发送）选了「总是」**仍需确认**（反例：放行 ⇒ 判红）；
/// ⑤ 撤销一条之后**立即**恢复询问。
final class AgentApprovalGrantTests: XCTestCase {

    private var directory: URL!
    private let writeTool = "write_file"
    private let commandTool = "run_command"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("approval-grant-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store() -> AgentApprovalGrantStore { AgentApprovalGrantStore(directory: directory) }

    private func pathScope(_ tool: String, _ path: String) -> AgentApprovalScope {
        AgentApprovalScope(tool: tool, value: AgentApprovalScope.normalizedPath(path))
    }

    /// 「还要不要问人」= 判定的**反面**（`isGranted` 为假就要问）。
    private func mustAsk(_ store: AgentApprovalGrantStore, _ scope: AgentApprovalScope,
                         hazard: AgentApprovalHazard = .ordinary, session: String) -> Bool {
        !store.isGranted(scope, hazard: hazard, sessionID: session)
    }

    // MARK: - ① 仅这一次：不记任何东西，第 2 次仍询问

    func testOnceRecordsNothingSoTheSecondCallStillAsks() throws {
        var grants = store()
        let scope = pathScope(writeTool, "a.txt")

        let recorded = try grants.remember(scope, tier: .once, hazard: .ordinary, sessionID: "S1")
        XCTAssertNil(recorded, "「仅这一次」居然记下了授权：\(String(describing: recorded))")
        XCTAssertTrue(grants.grants.isEmpty, "「仅这一次」之后账本里有 \(grants.grants.count) 条")
        XCTAssertTrue(mustAsk(grants, scope, session: "S1"), "第 2 次没有重新询问（判据①判红）")
        XCTAssertTrue(FileManager.default.fileExists(atPath: grants.fileURL.path) == false,
                      "「仅这一次」往盘上写了文件")

        print("🧪 判据① 仅这一次：记账 \(grants.grants.count) 条 / 第 2 次仍问 = \(mustAsk(grants, scope, session: "S1")) / 盘上文件 = \(FileManager.default.fileExists(atPath: grants.fileURL.path))")
    }

    // MARK: - ② 本会话内：同会话不问；换会话 / 重启再问；不落盘

    func testSessionGrantStopsAskingInThisSessionOnly() throws {
        var grants = store()
        let scope = pathScope(writeTool, "notes/a.md")

        let recorded = try XCTUnwrap(
            try grants.remember(scope, tier: .session, hazard: .ordinary, sessionID: "S1"),
            "「本会话内允许」没有记下来"
        )
        XCTAssertEqual(recorded.sessionID, "S1", "会话级授权没记归属会话")
        let sameSessionGranted = !mustAsk(grants, scope, session: "S1")
        XCTAssertTrue(sameSessionGranted, "同会话第 2 次还在问（判据②判红）")
        // 反例方向：换一个会话 ⇒ 必须重新问（会话级不许变成全局）。
        let otherSessionAsks = mustAsk(grants, scope, session: "S2")
        XCTAssertTrue(otherSessionAsks, "换了会话还在放行（会话级漏成了全局 ⇒ 判红）")
        // 反例方向：重启（同目录重新读盘）⇒ 会话级不该在盘上。
        let restartAsks = mustAsk(store(), scope, session: "S1")
        XCTAssertTrue(restartAsks, "会话级授权写进了盘（重启后还免问 ⇒ 判红）")
        let persisted = FileManager.default.fileExists(atPath: grants.fileURL.path)
        XCTAssertFalse(persisted, "会话级授权落了盘")

        // 会话结束 ⇒ 立刻失效。
        grants.endSession(sessionID: "S1")
        let asksAfterSessionEnd = mustAsk(grants, scope, session: "S1")
        XCTAssertTrue(asksAfterSessionEnd, "会话结束后仍在放行（判据②判红）")

        print("🧪 判据② 本会话内：同会话免问 = \(sameSessionGranted) / 换会话仍问 = \(otherSessionAsks) / 重启仍问 = \(restartAsks) / 落盘 = \(persisted) / 会话结束后仍问 = \(asksAfterSessionEnd)")
    }

    // MARK: - ③ 总是允许：跨重启生效，且只覆盖那一条路径

    func testAlwaysGrantSurvivesRestartAndCoversOnlyThatPath() throws {
        var grants = store()
        let aFile = pathScope(writeTool, "/a/x.txt")
        _ = try XCTUnwrap(try grants.remember(aFile, tier: .always, hazard: .ordinary, sessionID: "S1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: grants.fileURL.path), "「总是允许」没有落盘")

        // 重启 = 同目录重新造一本账（进程里那份什么都不带）。
        let restarted = store()
        XCTAssertEqual(restarted.persistentGrants.count, 1, "重启后读回 \(restarted.persistentGrants.count) 条（应为 1）")
        XCTAssertFalse(mustAsk(restarted, aFile, session: "S2"), "重启后同一条路径又问了（判据③判红）")
        // 反例方向：范围不许糊 —— 另建一本账的同名文件、另一个目录的文件都要重新问。
        let otherDirectory = pathScope(writeTool, "/b/y.txt")
        XCTAssertTrue(mustAsk(restarted, otherDirectory, session: "S2"),
                      "允许写 /a/x.txt 顺带放行了 /b/y.txt（范围糊成「工具名」⇒ 判红）")
        let sibling = pathScope(writeTool, "/a/x.txt.bak")
        XCTAssertTrue(mustAsk(restarted, sibling, session: "S2"), "字符串前缀把 /a/x.txt.bak 也算进来了")
        // 反例方向：换工具也不行（键里必须有工具名）。
        let otherTool = pathScope("edit_file", "/a/x.txt")
        XCTAssertTrue(mustAsk(restarted, otherTool, session: "S2"), "换个工具还用同一条授权（键里没工具名）")

        print("🧪 判据③ 总是允许：重启后读回 \(restarted.persistentGrants.count) 条 / 同路径免问 = \(!mustAsk(restarted, aFile, session: "S2")) / 另一路径仍问 = \(mustAsk(restarted, otherDirectory, session: "S2")) / 同目录兄弟文件仍问 = \(mustAsk(restarted, sibling, session: "S2"))")
    }

    // MARK: - ④ 不可逆：选了「总是」也仍要确认（盘上有历史授权也不认）

    func testIrreversibleActionsAlwaysAskEvenWhenAlwaysWasChosen() throws {
        var grants = store()
        let commandRule = AgentApprovalHazardRules.command("rm -rf build")
        XCTAssertEqual(commandRule, .destructive, "`rm -rf` 没被判成不可逆：\(commandRule)")
        let sendRule = AgentApprovalHazardRules.text("im_send_message")
        XCTAssertEqual(sendRule, .outbound, "对外发送没被判成不可逆：\(sendRule)")

        for (scope, hazard) in [(AgentApprovalScope(tool: commandTool, value: "rm"), commandRule),
                                (AgentApprovalScope(tool: "im_send_message", value: "chat-1"), sendRule)] {
            let recorded = try grants.remember(scope, tier: .always, hazard: hazard, sessionID: "S1")
            XCTAssertNil(recorded, "不可逆动作被记成了「总是允许」：\(scope.key)")
            XCTAssertTrue(mustAsk(grants, scope, hazard: hazard, session: "S1"),
                          "不可逆动作选了「总是」之后不再确认（判据④判红）：\(scope.key)")
        }

        // 反例方向（更狠的一格）：盘上**已经**写着一条这样的授权（历史遗留 / 手改文件），判定也不许认。
        let legacy = AgentApprovalGrant(tool: commandTool, scope: "rm", tier: .always)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = AgentStoredDate.encoding
        try encoder.encode([legacy]).write(to: grants.fileURL)
        let restarted = store()
        XCTAssertEqual(restarted.persistentGrants.count, 1, "预置的那条授权没读进来（这一格就白测了）")
        XCTAssertTrue(mustAsk(restarted, AgentApprovalScope(tool: commandTool, value: "rm"),
                              hazard: .destructive, session: "S1"),
                      "盘上有一条针对 `rm` 的旧授权就放行了（判据④判红）")

        print("🧪 判据④ 不可逆：`rm -rf` ⇒ \(commandRule.rawValue)（可记授权 = \(commandRule.allowsGrant)）/ 对外发送 ⇒ \(sendRule.rawValue)（可记授权 = \(sendRule.allowsGrant)）/ 盘上预置一条后仍问 = \(mustAsk(restarted, AgentApprovalScope(tool: commandTool, value: "rm"), hazard: .destructive, session: "S1"))")
    }

    // MARK: - ⑤ 撤销：删掉一条之后立即恢复询问

    func testRevokingOneGrantRestoresAskingImmediately() throws {
        var grants = store()
        let first = pathScope(writeTool, "/a/x.txt")
        let second = pathScope(commandTool, "python3")
        let firstGrant = try XCTUnwrap(try grants.remember(first, tier: .always, hazard: .ordinary, sessionID: "S1"))
        _ = try XCTUnwrap(try grants.remember(second, tier: .always, hazard: .ordinary, sessionID: "S1"))
        XCTAssertEqual(grants.grants.count, 2, "记账条数 = \(grants.grants.count)")

        try grants.revoke(id: firstGrant.id)
        let firstAsksAfterRevoke = mustAsk(grants, first, session: "S1")
        let secondStillGranted = !mustAsk(grants, second, session: "S1")
        XCTAssertTrue(firstAsksAfterRevoke, "撤销之后还在放行（判据⑤判红）")
        XCTAssertTrue(secondStillGranted, "撤销一条把另一条也撤了")

        // 撤销要落盘：重启后也不该复活。
        let restarted = store()
        XCTAssertEqual(restarted.persistentGrants.count, 1, "撤销没落盘：重启后读回 \(restarted.persistentGrants.count) 条")
        XCTAssertTrue(mustAsk(restarted, first, session: "S1"), "撤销只改了内存，重启后又免问了（判据⑤判红）")
        let rebootsStillAsking = mustAsk(restarted, first, session: "S1")
        let rebootCount = restarted.persistentGrants.count

        try grants.revokeAll()
        XCTAssertTrue(grants.grants.isEmpty, "全部撤销之后还剩 \(grants.grants.count) 条")
        XCTAssertTrue(store().persistentGrants.isEmpty, "全部撤销没落盘")

        print("🧪 判据⑤ 撤销：撤 1 条后该条仍问 = \(firstAsksAfterRevoke) / 另一条仍免问 = \(secondStillGranted) / 重启后剩 \(rebootCount) 条且该条仍问 = \(rebootsStillAsking)")
    }

    // MARK: - 作用域取法（键不许糊成工具名）

    func testScopeKeysComeFromTheRealTarget() throws {
        XCTAssertEqual(AgentApprovalScope.normalizedPath("/a/b/../b/x.txt"), "/a/b/x.txt", "路径没有规范化")
        XCTAssertEqual(AgentApprovalScope.commandWord("  python3  hello.py "), "python3", "命令首词取错")
        XCTAssertNotEqual(AgentApprovalScope.argumentDigest("sql-1"),
                          AgentApprovalScope.argumentDigest("sql-2"), "参数摘要不区分参数")

        // 真出单的那几处：作用域是**目标**，不是工具名。
        let tools = AgentWorkspaceTools(root: directory)
        guard case .needsApproval(let write) = tools.prepareWrite(path: "a.txt", content: "x") else {
            return XCTFail("写文件没有出单")
        }
        XCTAssertEqual(write.scope, "a.txt", "写文件的作用域 = \(write.scope)（应为路径）")
        XCTAssertEqual(write.approvalScope.key, "write_file|a.txt")

        guard case .needsApproval(let command) = tools.prepareCommand("python3 hello.py") else {
            return XCTFail("命令没有出单")
        }
        XCTAssertEqual(command.scope, "python3", "命令的作用域 = \(command.scope)（应为首词）")
        XCTAssertEqual(command.hazard, .ordinary, "普通命令被判成 \(command.hazard.rawValue)")

        guard case .needsApproval(let gitReset) = tools.prepareCommand("git reset --hard") else {
            return XCTFail("git reset 没有出单")
        }
        XCTAssertEqual(gitReset.hazard, .destructive, "`git reset --hard` 没被判成不可逆：\(gitReset.hazard.rawValue)")

        // 越界出单：作用域 = 绝对路径，且永不记授权。
        guard case .needsApproval(let outside) = tools.prepareWrite(path: "/etc/hosts.bak", content: "x") else {
            return XCTFail("越界写没有出单")
        }
        XCTAssertEqual(outside.hazard, .outsideWorkspace, "越界单的危险面 = \(outside.hazard.rawValue)")
        XCTAssertEqual(outside.scope, "/etc/hosts.bak", "越界单的作用域 = \(outside.scope)")

        // SQL：`DELETE` 归不可逆，`UPDATE` 归普通（可记授权）。
        XCTAssertEqual(AgentApprovalHazardRules.sql("DELETE FROM orders"), .destructive)
        XCTAssertEqual(AgentApprovalHazardRules.sql("-- note\n  DROP TABLE orders"), .destructive)
        XCTAssertEqual(AgentApprovalHazardRules.sql("UPDATE orders SET a = 1"), .ordinary)

        print("🧪 作用域读数：写=\(write.scope) 命令=\(command.scope) git=\(gitReset.hazard.rawValue) 越界=\(outside.scope)/\(outside.hazard.rawValue)")
    }
}
