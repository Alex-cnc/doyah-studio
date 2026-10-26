import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// `FR-AGT-UX-CONV-014` / `FR-AGT-UX-CONV-015`：斜杠命令的**落地形状**
/// （解析已在 `AgentSlashCommandTests`，这里测「解析出来之后要做什么」）。
///
/// 三条被测纪律：
/// ① 七条命令**全部本地执行、不进模型**；
/// ② 改配置的两条（`/model` `/theme`）**只出单、不落地** —— 批准是别人的事；
/// ③ 不认的命令 / 缺参数**如实拒收**，审计行永远一行。
final class AgentSlashCommandRuntimeTests: XCTestCase {
    private let runtime = AgentSlashCommandRuntime()
    private let parser = AgentSlashCommandParser()

    // MARK: - 正常路：七条命令各自落到哪

    func testEveryDocumentedCommandHasALocalEffect() {
        let expected: [(String, AgentSlashCommandEffect)] = [
            ("/help", .help(lines: parser.helpText)),
            ("/clear", .clearContext),
            ("/compact", .compactContext),
            ("/sessions 备份", .searchSessions(query: "备份")),
            ("/stop", .stopRun),
            ("/model gpt-4o", .configChange(kind: .model, argument: "gpt-4o")),
            ("/theme 深色", .configChange(kind: .theme, argument: "深色")),
        ]
        for (raw, want) in expected {
            XCTAssertEqual(runtime.plan(raw), want, "\(raw) 的落地形状不对")
        }
        // 七条**全部**有形状（没有一条落空 ⇒ 不会有人把它当人话发给模型）
        XCTAssertEqual(expected.count, AgentSlashCommandKind.allCases.count)
    }

    func testHelpTextComesFromTheSingleSourceNotACopy() {
        guard case let .help(lines)? = runtime.plan("/help") else {
            return XCTFail("/help 没有落到 .help")
        }
        // 与解析器里的唯一真源**逐字**相同：不许在 runtime 里另抄一份文案。
        XCTAssertEqual(lines, parser.helpText)
        XCTAssertFalse(lines.isEmpty)
    }

    func testAuditLineIsTheParserOneAndSingleLine() {
        XCTAssertEqual(runtime.plan("/clear")?.auditLine, "slash /clear")
        XCTAssertEqual(runtime.plan("/stop")?.auditLine, "slash /stop")
        XCTAssertEqual(runtime.plan("/model gpt-4o")?.auditLine, "slash /model arg=gpt-4o")
        // 参数里塞换行 ⇒ 审计行**仍然一行**，且正文不被带出来（只带一行摘要）
        let multi = runtime.plan("/model gpt-4o\nrm -rf /\n\t more")
        XCTAssertEqual(multi?.auditLine, "slash /model arg=gpt-4o rm -rf / more")
        XCTAssertFalse(multi?.auditLine.contains("\n") ?? true)
    }

    // MARK: - 该拒的：不认 / 缺参数 / 不是命令

    func testUnknownCommandIsRejectedNotGuessed() {
        guard case let .rejected(command)? = runtime.plan("/nope") else {
            return XCTFail("/nope 没有被拒收")
        }
        XCTAssertEqual(command, .unknown(name: "nope"))
        XCTAssertTrue(runtime.plan("/nope")?.auditLine.contains("unknown") ?? false)
        XCTAssertFalse(runtime.plan("/nope")?.performedLocally ?? true, "被拒的命令不算做成了一件事")
    }

    func testMissingArgumentIsRejectedInsteadOfDefaulted() {
        guard case .rejected? = runtime.plan("/model") else {
            return XCTFail("/model 缺参数应当被拒收，而不是拿默认值顶")
        }
        guard case .rejected? = runtime.plan("/sessions") else {
            return XCTFail("/sessions 缺关键词应当被拒收")
        }
        XCTAssertTrue(runtime.plan("/model")?.auditLine.contains("missing-argument") ?? false)
    }

    func testPlainTextAndBareSlashAreNotCommands() {
        XCTAssertNil(runtime.plan("帮我看看这张表"))
        XCTAssertNil(runtime.plan("/"), "单个斜杠不是命令")
        XCTAssertNil(runtime.plan("/ help"), "斜杠后跟空白不是命令")
        XCTAssertNil(runtime.plan(""))
    }

    // MARK: - 改配置：只出单、不落地

    func testConfigurationCommandsOnlyProduceAPendingChange() {
        for raw in ["/model gpt-4o", "/theme 深色", "/THEME light"] {
            guard let effect = runtime.plan(raw) else { return XCTFail("\(raw) 没有形状") }
            XCTAssertTrue(effect.mutatesConfiguration, "\(raw) 必须走配置变更那条")
            XCTAssertFalse(effect.performedLocally, "\(raw) 不许自己落地")
            guard case .configChange = effect else {
                return XCTFail("\(raw) 应当是 .configChange")
            }
        }
        // 其余五条**都不许**被当成改配置（改配置 = 必须过审批，放宽等于绕开审批）
        for raw in ["/help", "/clear", "/compact", "/sessions 备份", "/stop"] {
            XCTAssertFalse(runtime.plan(raw)?.mutatesConfiguration ?? true, "\(raw) 不该要审批")
        }
    }

    func testPendingRecordCannotExecuteBeforeApproval() throws {
        guard let effect = runtime.plan("/theme 深色") else { return XCTFail("没有形状") }
        let record = runtime.auditRecord(for: effect, outcome: .pendingApproval, sessionID: "chat-1")
        XCTAssertEqual(record.outcome, .pendingApproval)
        XCTAssertEqual(record.sessionID, "chat-1")
        // 一条命令 = 一条记录，摘要里就是那一行审计
        XCTAssertTrue(record.sql.contains("slash /theme arg=深色"))

        var approval = AgentApproval(record: record, state: .pending)
        XCTAssertTrue(approval.awaitsHumanDecision)
        XCTAssertFalse(approval.canExecute, "批准之前不许执行")
        try approval.approve(by: "tester")
        XCTAssertTrue(approval.canExecute)
        XCTAssertThrowsError(try approval.approve(by: "tester"), "重复批准必须被状态机挡住")
    }

    // MARK: - 边界：清上下文不动会话级设置

    func testClearTranscriptKeepsSessionLevelSettings() {
        var state = AgentChatState()
        state.appendNotice("hello")
        state.cards.append(AgentToolCard(name: "write_file", arguments: "x"))
        state.steps.append(AgentChatStep(index: 1))
        let endpointBefore = state.endpoint
        let scopeBefore = state.taskScope
        let grantsBefore = state.grants

        state.clearTranscript()

        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertTrue(state.cards.isEmpty)
        XCTAssertTrue(state.steps.isEmpty)
        XCTAssertNil(state.currentAction)
        // **不降授权、不动端点**：清上下文不是「重置会话设置」
        XCTAssertEqual(state.endpoint, endpointBefore)
        XCTAssertEqual(state.taskScope, scopeBefore)
        XCTAssertEqual(state.grants, grantsBefore)
    }

    // MARK: - 界面侧那两口（App 层：待批单 + `/theme` 参数别名）

    func testThemeArgumentAliasesAndUnknownIsNil() {
        XCTAssertEqual(AgentSlashThemeArgument.preference(from: "深色"), .alwaysDark)
        XCTAssertEqual(AgentSlashThemeArgument.preference(from: "DARK"), .alwaysDark)
        XCTAssertEqual(AgentSlashThemeArgument.preference(from: "浅色"), .alwaysLight)
        XCTAssertEqual(AgentSlashThemeArgument.preference(from: " 跟随系统 "), .followSystem)
        XCTAssertNil(AgentSlashThemeArgument.preference(from: "巧克力色"), "认不出的值不许猜")
    }

    func testPendingChangeCarriesKindArgumentAndSingleLineAudit() throws {
        guard let effect = runtime.plan("/model gpt-4o") else { return XCTFail("没有形状") }
        let record = runtime.auditRecord(for: effect, outcome: .pendingApproval)
        let approval = AgentApproval(record: record, state: .pending)
        let change = try XCTUnwrap(AgentSlashPendingChange(effect: effect, approval: approval))
        XCTAssertEqual(change.kind, .model)
        XCTAssertEqual(change.argument, "gpt-4o")
        XCTAssertEqual(change.auditLine, "slash /model arg=gpt-4o")
        XCTAssertEqual(change.id, approval.id)

        // 非配置类 effect 装不出待批单（那是别的东西，不该出现在审批位上）
        XCTAssertNil(AgentSlashPendingChange(effect: .clearContext, approval: approval))
    }
}
