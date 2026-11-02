import XCTest
@testable import DoyahCore

/// 对话记忆的**接线**判据（`FR-AGT-KNOW-MEM-003`）。
///
/// 与 `AgentMemoryTests` 的分工：那一族证明「记忆层本身对」，这一族证明
/// **它真的被接上了** —— 台账 2026-10-28 把这条从 ✅ 降成 🟡 的原话是
/// 「写入 `AgentMemoryStore.record()` 除测试**零调用点**、盘上无记忆目录、无记忆界面」。
/// 所以这里的用例盯的是三件事：
/// 1. 「他说了记住」这句话能被解析成一条要写的记忆，且**问句 / 半句不算**；
/// 2. 一条原话写进去之后，**下一次组装上下文真的带上它**；删掉之后**这一次带不上**；
/// 3. 改完之后派生索引跟着对齐（②⑤），索引删掉能重建且**事实源一字不动**；
/// 4. 源树上那三处接线（对话入口 / 菜单入口 / 面板删除出口）**在**。
final class AgentMemoryDeskTests: XCTestCase {

    private var directory: URL!
    private var store: AgentMemoryStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-memory-desk-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = AgentMemoryStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func desk(_ workspace: String, connection: String? = "prod") -> AgentMemoryDesk {
        AgentMemoryDesk(store: store, workspace: workspace, connection: connection)
    }

    // MARK: - ① 「他说了记住」这句话的判定

    func testLongestTriggerWinsSoTheNoteDoesNotStartWithTheTriggerTail() {
        let draft = AgentMemoryInstruction.draft(from: "记住这个：以后默认用简体中文回答",
                                                workspace: "ws", connection: "prod")
        XCTAssertEqual(draft?.note, "以后默认用简体中文回答")
        XCTAssertEqual(draft?.kind, .pinned, "人明确让记的一条默认按「已钉住」落，才不会被按天数清掉")
        XCTAssertEqual(draft?.workspace, "ws")
        XCTAssertEqual(draft?.connection, "prod")
    }

    func testPolitenessPrefixesAndMissingColonAreStillAnInstruction() {
        XCTAssertEqual(AgentMemoryInstruction.draft(from: "请记住 生产库只读，不许写",
                                                    workspace: "ws", connection: "")?.note,
                       "生产库只读，不许写")
        XCTAssertEqual(AgentMemoryInstruction.draft(from: "帮我记住，别名统一用 pg",
                                                    workspace: "ws", connection: "")?.note,
                       "别名统一用 pg")
    }

    func testBareTriggerAndQuestionsAreNotInstructions() {
        XCTAssertNil(AgentMemoryInstruction.draft(from: "记住", workspace: "ws", connection: ""))
        XCTAssertNil(AgentMemoryInstruction.draft(from: "记住：", workspace: "ws", connection: ""))
        XCTAssertNil(AgentMemoryInstruction.draft(from: "记住这个字段叫什么？", workspace: "ws", connection: ""),
                     "问句是在问，不是在让我记 —— 收下它就会把一个问题当成一条事实")
        XCTAssertNil(AgentMemoryInstruction.draft(from: "记住这个字段叫什么?", workspace: "ws", connection: ""))
    }

    func testMentionsInTheMiddleOfASentenceAreNotInstructions() {
        XCTAssertNil(AgentMemoryInstruction.draft(from: "我记得这个字段以前是 NOT NULL", workspace: "ws", connection: ""))
        XCTAssertNil(AgentMemoryInstruction.draft(from: "你记住这个了吗", workspace: "ws", connection: ""))
        XCTAssertNil(AgentMemoryInstruction.draft(from: "", workspace: "ws", connection: ""))
    }

    // MARK: - ② 写进事实源 → 下一次组装上下文带得上；删掉 → 带不上

    func testRememberingFromAPromptReachesTheNextContext() {
        let board = desk("ws-ctx")
        let notice = board.rememberFromPrompt("记住：迁移脚本只在周二跑", at: now)
        guard case .remembered(let merged, let useCount, _, _)? = notice else {
            return XCTFail("应当记下一条，实际 \\(String(describing: notice))")
        }
        XCTAssertFalse(merged)
        XCTAssertEqual(useCount, 1)

        let snapshot = board.snapshot(now: now)
        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertTrue(snapshot.retainedIDs.contains(snapshot.entries[0].id))
        XCTAssertTrue(snapshot.reasonLines[snapshot.entries[0].id]?.isEmpty == false,
                      "逐条解释必须有话（① 可解释）")

        let references = AgentMemoryContext.references(from: snapshot.entries, now: now)
        XCTAssertEqual(references.count, 1, "写进去的这条必须能进上下文")
        guard case .file(let path, _) = references[0] else {
            return XCTFail("记忆走的是 `.file` 那一路")
        }
        XCTAssertTrue(path.hasPrefix("memory://"), path)
    }

    func testDeletingAnEntryIsImmediateInInspectionIndexAndContext() throws {
        let board = desk("ws-del")
        board.rememberFromPrompt("记住：备份窗口是凌晨两点", at: now)
        let id = try XCTUnwrap(board.snapshot(now: now).entries.first?.id)

        guard case .deleted(let indexRebuilt) = board.delete(id: id) else {
            return XCTFail("应当删掉")
        }
        XCTAssertTrue(indexRebuilt, "删完索引必须跟着对齐（② 要求「重建索引后也不再出现」）")

        let after = board.snapshot(now: now)
        XCTAssertTrue(after.entries.isEmpty)
        XCTAssertEqual(after.indexEntryCount, 0)
        XCTAssertTrue(AgentMemoryContext.references(from: after.entries, now: now).isEmpty,
                      "删掉的不能再进上下文")

        // 事实源里也不留：整份重写，不是打墓碑。
        let raw = try String(contentsOf: store.factFileURL(workspace: "ws-del"), encoding: .utf8)
        XCTAssertFalse(raw.contains(id))
        XCTAssertEqual(board.delete(id: id), .notFound, "再删一次要如实说「不在了」")
    }

    func testClearingRemovesEverythingAndReportsTheCount() {
        let board = desk("ws-clear")
        board.rememberFromPrompt("记住：生产库表名前缀是 biz_", at: now)
        board.rememberFromPrompt("记住：测试库每天凌晨重置", at: now)
        XCTAssertEqual(board.snapshot(now: now).entryCount, 2)

        guard case .cleared(let count, let indexRebuilt) = board.clear() else {
            return XCTFail("应当清空")
        }
        XCTAssertEqual(count, 2)
        XCTAssertTrue(indexRebuilt)
        XCTAssertEqual(board.snapshot(now: now).entryCount, 0)
        XCTAssertEqual(board.snapshot(now: now).indexEntryCount, 0)
    }

    // MARK: - ④ 脏内容一律拒收（负例）

    func testSecretFragmentsAndRowDataNeverGetWritten() {
        let board = desk("ws-dirty")
        let secret = board.rememberFromPrompt("记住：连接串里的口令是 password=hunter2hunter2", at: now)
        guard case .refused(let reasons, _)? = secret else {
            return XCTFail("密钥片段应当被拒，实际 \\(String(describing: secret))")
        }
        XCTAssertTrue(reasons.contains { if case .secretFragment = $0 { return true }; return false }, "\\(reasons)")

        let rows = board.rememberFromPrompt("记住：| 1 | alice | 2026-01-01 |", at: now)
        guard case .refused(let rowReasons, _)? = rows else {
            return XCTFail("结果集行应当被拒，实际 \\(String(describing: rows))")
        }
        XCTAssertTrue(rowReasons.contains { if case .rowLikeContent = $0 { return true }; return false }, "\\(rowReasons)")

        XCTAssertEqual(board.snapshot(now: now).entryCount, 0, "拒收就是没写")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.factFileURL(workspace: "ws-dirty").path))
    }

    // MARK: - ③ 工作区隔离

    func testTwoWorkspacesCannotSeeEachOther() {
        let left = desk("ws-left")
        let right = desk("ws-right")
        left.rememberFromPrompt("记住：左边这套库叫 analytics", at: now)
        right.rememberFromPrompt("记住：右边这套库叫 billing", at: now)

        XCTAssertEqual(left.snapshot(now: now).entries.map(\.note), ["左边这套库叫 analytics"])
        XCTAssertEqual(right.snapshot(now: now).entries.map(\.note), ["右边这套库叫 billing"])
    }

    // MARK: - ⑤ 索引是纯派生缓存

    func testRebuildingTheIndexRestoresItByteForByteAndLeavesTheSourceUntouched() throws {
        let board = desk("ws-index")
        board.rememberFromPrompt("记住：对账表每天 03:00 生成", at: now)
        board.rememberFromPrompt("记住：慢查询阈值是 500ms", at: now)

        let before = try Data(contentsOf: store.factFileURL(workspace: "ws-index"))
        XCTAssertTrue(store.hasIndex(workspace: "ws-index"))
        XCTAssertTrue(store.removeIndex(workspace: "ws-index"))
        XCTAssertFalse(board.snapshot(now: now).indexExists, "索引删掉 ⇒ 面板如实说「不在盘」")

        guard case .indexRebuilt(let count) = board.rebuildIndex(at: now) else {
            return XCTFail("应当重建成功")
        }
        XCTAssertEqual(count, 2)
        let rebuilt = try XCTUnwrap(store.loadIndex(workspace: "ws-index"))
        XCTAssertEqual(rebuilt.ids, board.snapshot(now: now).entries.map(\.id))

        let after = try Data(contentsOf: store.factFileURL(workspace: "ws-index"))
        XCTAssertEqual(after, before, "索引是派生缓存：重建不许动事实源一个字节")
    }

    func testAStaleIndexIsReportedRatherThanSilentlyUsed() throws {
        let board = desk("ws-stale")
        board.rememberFromPrompt("记住：一库一账号，不共用", at: now)
        board.rememberFromPrompt("记住：连接名带库名后缀", at: now)
        let id = try XCTUnwrap(board.snapshot(now: now).entries.first?.id)

        // 绕过工作面直接删事实源里的那一条 ⇒ 索引停在旧状态（面板必须看得出来）。
        XCTAssertTrue(try store.remove(id: id, workspace: "ws-stale"))
        let snapshot = board.snapshot(now: now)
        XCTAssertTrue(snapshot.indexIsStale)
        XCTAssertEqual(snapshot.indexEntryCount, 2)
        XCTAssertEqual(snapshot.entryCount, 1)
    }

    // MARK: - ⑥ 坏文件 / 认不出的条目跳过并计数

    func testDamagedSourcesAreReportedAndNeverLookEmpty() throws {
        let board = desk("ws-broken")
        let header = try AgentMemoryStore.encoder.encode(AgentMemoryHeader(workspace: "ws-broken"))
        let garbage = Data("{not json".utf8)
        var payload = header
        payload.append(0x0A)
        payload.append(garbage)
        payload.append(0x0A)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try payload.write(to: store.factFileURL(workspace: "ws-broken"))

        let damaged = board.snapshot(now: now)
        XCTAssertEqual(damaged.skippedLines, 1)
        XCTAssertTrue(damaged.hasSkippedReadings, "读不进来的要显式说，不许当成「空」")

        // 头一行没了 ⇒ 现在写不进去（覆盖它等于把读不出来的东西悄悄清掉）。
        try Data("{}\n".utf8).write(to: store.factFileURL(workspace: "ws-broken"))
        let headless = board.snapshot(now: now)
        XCTAssertTrue(headless.missingHeader)
        XCTAssertFalse(headless.isReadable)
        XCTAssertEqual(board.rememberFromPrompt("记住：这条写不进去", at: now),
                       .refused([.sourceUnreadable], truncatedCharacters: 0))
        XCTAssertEqual(desk("ws-broken").snapshot(now: now).entryCount, 0)
    }

    // MARK: - 源锚点：三处接线真的在（这条判据只能从源树判）

    func testTheChatEntryPointMenuAndPanelAreActuallyWired() throws {
        let root = repoRoot()
        let appState = try String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8)

        let loop = try block("func makeAgentChatLoop", in: appState)
        XCTAssertTrue(loop.contains("rememberAgentMemoryFromPrompt(prompt, workspacePath: workspacePath)"),
                      "对话入口必须接写入 —— 否则写入又回到「除测试零调用点」")
        XCTAssertFalse(loop.contains("guard case .ready") &&
                       loop.range(of: "rememberAgentMemoryFromPrompt")!.lowerBound >
                       loop.range(of: "guard case .ready")!.lowerBound,
                       "「记住」是人的指令，要排在端点判定之前")

        let delete = try block("func deleteAgentMemory", in: appState)
        XCTAssertTrue(delete.contains("desk.delete(id: id)"), "面板删除要落到工作面（真删）")
        XCTAssertTrue(delete.contains("refreshAgentMemory()"), "删完必须重读，屏幕上的那一行才跟着消失")

        let commands = try String(contentsOf: root.appendingPathComponent("App/DoyahStudioCommands.swift"),
                                  encoding: .utf8)
        XCTAssertTrue(commands.contains("appState.openAgentMemory()"), "菜单里要有入口")

        let window = try String(contentsOf: root.appendingPathComponent("App/Views/MainWindow.swift"),
                                encoding: .utf8)
        XCTAssertTrue(window.contains("$appState.isAgentMemoryPresented"),
                      "面板要真的挂到窗口上（挂了没开口也等于没有）")

        let panel = try String(contentsOf: root.appendingPathComponent("App/Views/AgentMemoryPanel.swift"),
                               encoding: .utf8)
        XCTAssertTrue(panel.contains("appState.deleteAgentMemory(id: entry.id)"), "逐条删除的出口")
        XCTAssertTrue(panel.contains("appState.clearAgentMemory()"), "整层清空的出口")
        XCTAssertTrue(panel.contains("appState.rebuildAgentMemoryIndex()"), "重建索引的出口")
        XCTAssertTrue(panel.contains("snapshot.reasonLines"), "「为什么记着它」要上屏（① 可解释）")
    }

    // MARK: - 夹具

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 取一个函数的函数体（签名到下一个顶层缩进 4 空格的 `func`）。
    private func block(_ signature: String, in source: String) throws -> String {
        guard let start = source.range(of: signature) else {
            throw NSError(domain: "memory-desk", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "找不到 \\(signature)"])
        }
        let rest = source[start.upperBound...]
        if let end = rest.range(of: "\n    func ") {
            return String(rest[..<end.lowerBound])
        }
        return String(rest)
    }
}
