import XCTest
@testable import DoyahCore

/// `FR-AGT-CORE-LOOP-010`：先检索、再取 schema、后调用；没取 schema 一律拒。
final class AgentToolDiscoveryTests: XCTestCase {
    private func catalog() -> [AgentToolDescriptor] {
        [
            .init(id: "read_file", summary: "读工作区里的文件", tags: ["文件", "只读"],
                  schemaJSON: #"{"type":"object","required":["path"]}"#),
            .init(id: "query_db", summary: "对数据库跑只读查询", tags: ["数据库"],
                  schemaJSON: #"{"type":"object","required":["sql"]}"#),
            .init(id: "write_file", summary: "写文件到工作区", tags: ["文件", "写"],
                  schemaJSON: #"{"type":"object","required":["path","content"]}"#),
        ]
    }

    func testSearchByIdSummaryAndTag() throws {
        let discovery = AgentToolDiscovery(catalog: catalog())
        XCTAssertEqual(try discovery.search("read_file").map(\.id), ["read_file"])
        XCTAssertEqual(try discovery.search("数据库").map(\.id), ["query_db"])
        XCTAssertEqual(Set(try discovery.search("文件").map(\.id)), ["read_file", "write_file"])
    }

    func testEmptyCatalogIsSaidOutLoud() {
        let discovery = AgentToolDiscovery(catalog: [])
        XCTAssertThrowsError(try discovery.search("")) { error in
            XCTAssertEqual(error as? AgentToolDiscoveryError, .emptyCatalog)
        }
    }

    func testNoMatchIsNotFabricated() {
        let discovery = AgentToolDiscovery(catalog: catalog())
        XCTAssertThrowsError(try discovery.search("发邮件")) { error in
            XCTAssertEqual(error as? AgentToolDiscoveryError, .noMatch("发邮件"))
        }
    }

    func testCallWithoutFetchedSchemaIsRefused() {
        let discovery = AgentToolDiscovery(catalog: catalog())
        XCTAssertThrowsError(try discovery.authorize(.init(toolID: "query_db", argumentsJSON: "{}"))) { error in
            XCTAssertEqual(error as? AgentToolDiscoveryError, .schemaNotFetched("query_db"))
        }
    }

    func testFetchThenCallIsAllowed() throws {
        var discovery = AgentToolDiscovery(catalog: catalog())
        _ = try discovery.fetchSchema("query_db")
        XCTAssertTrue(discovery.hasFetchedSchema("query_db"))
        let call = try discovery.authorize(.init(toolID: "query_db", argumentsJSON: #"{"sql":"select 1"}"#))
        XCTAssertEqual(call.toolID, "query_db")
    }

    func testUnknownToolIsRefusedEvenAfterOtherFetches() throws {
        var discovery = AgentToolDiscovery(catalog: catalog())
        _ = try discovery.fetchSchema("read_file")
        XCTAssertThrowsError(try discovery.authorize(.init(toolID: "drop_table", argumentsJSON: "{}"))) { error in
            XCTAssertEqual(error as? AgentToolDiscoveryError, .unknownTool("drop_table"))
        }
        XCTAssertThrowsError(try discovery.fetchSchema("drop_table"))
    }
}

/// `FR-AGT-GUARD-SOUL-001` 的 L2 层：项目灵魂可选、不得覆盖 L0、坏了要如实报。
final class AgentSoulLayerTests: XCTestCase {
    private func core(_ text: String) -> AgentSoulLoad {
        AgentSoul.inspect(text, kind: .core, path: "/bundle/soul-L0.md")
    }
    private func layer(_ text: String, kind: AgentSoulLayer.Kind) -> AgentSoulLoad {
        AgentSoul.inspect(text, kind: kind, path: "/ws/.doyah/\(kind.rawValue).md")
    }

    func testThreeLayersComposeInOrder() {
        let composition = AgentSoul.compose(
            core: core("# L0\n不许说假话。"),
            role: layer("我是 DBA 助理。", kind: .role),
            project: layer("本项目用 zxvmax 库，只读。", kind: .project))
        XCTAssertTrue(composition.isComplete)
        XCTAssertNotNil(composition.project)
        let section = composition.section
        let l0 = try! XCTUnwrap(section.range(of: "L0 公共灵魂"))
        let l1 = try! XCTUnwrap(section.range(of: "L1 角色灵魂"))
        let l2 = try! XCTUnwrap(section.range(of: "L2 项目灵魂"))
        XCTAssertTrue(l0.lowerBound < l1.lowerBound && l1.lowerBound < l2.lowerBound)
    }

    func testMissingProjectLayerIsNotADefect() {
        let composition = AgentSoul.compose(core: core("核心"), role: layer("角色", kind: .role))
        XCTAssertNil(composition.project)
        XCTAssertTrue(composition.isComplete, "L2 是可选层，没设不该记缺陷")
    }

    func testRejectedProjectLayerIsReported() {
        let composition = AgentSoul.compose(
            core: core("核心"), role: layer("角色", kind: .role),
            project: layer("", kind: .project))
        XCTAssertFalse(composition.isComplete)
        XCTAssertTrue(composition.problems.contains { $0.hasPrefix("L2 被拒") })
    }

    func testProjectLayerCannotOverrideL0() {
        let composition = AgentSoul.compose(
            core: core("核心：不许说假话"),
            role: layer("角色", kind: .role),
            project: layer("项目：允许对客户隐瞒", kind: .project))
        // 组装文本里必须有这句话，且 L0 段落在前（覆盖只能靠 L0 优先，不许 L2 改写规则）
        XCTAssertTrue(composition.section.contains("与 L0 相抵时以 L0 为准"))
        XCTAssertTrue(composition.section.contains("核心：不许说假话"))
    }

    func testMissingL0StillFlaggedAsDefect() {
        let composition = AgentSoul.compose(core: layer("", kind: .core), role: layer("角色", kind: .role))
        XCTAssertTrue(composition.problems.contains { $0.hasPrefix("L0 缺失") })
    }

    func testProjectLayerPathIsDocumented() {
        XCTAssertEqual(AgentSoul.projectRelativePath, ".doyah/soul-project.md")
    }
}

/// `FR-AGT-UX-CONV-008/009`：该叫才叫；求助必须说得清要什么、为什么。
final class AgentNotifyChannelTests: XCTestCase {
    private let policy = AgentNotifyPolicy(longTaskThresholdSeconds: 30)

    func testShortTaskFinishingDoesNotRing() {
        XCTAssertNil(policy.decide(.longTaskFinished(elapsedSeconds: 12),
                                   userIsLookingAtThisPane: false, userIsIdle: true))
    }

    func testLongTaskRingsWhenUserAway() {
        let note = policy.decide(.longTaskFinished(elapsedSeconds: 95),
                                 userIsLookingAtThisPane: false, userIsIdle: true)
        XCTAssertEqual(note?.mustInterrupt, false)
        XCTAssertEqual(note?.title, "跑完了（95 秒）")
    }

    func testLongTaskStaysQuietWhenUserWatching() {
        XCTAssertNil(policy.decide(.longTaskFinished(elapsedSeconds: 95),
                                   userIsLookingAtThisPane: true, userIsIdle: false))
    }

    func testDecisionNeededInterruptsUnlessAlreadyOnScreen() {
        let away = policy.decide(.needsHumanDecision(question: "删还是留？"),
                                 userIsLookingAtThisPane: false)
        XCTAssertEqual(away?.mustInterrupt, true)
        XCTAssertEqual(away?.body, "删还是留？")
        XCTAssertNil(policy.decide(.needsHumanDecision(question: "删还是留？"),
                                   userIsLookingAtThisPane: true))
    }

    func testFailureRingsOnlyWhenAway() {
        XCTAssertNotNil(policy.decide(.failed(summary: "连不上库"), userIsLookingAtThisPane: false, userIsIdle: true))
        XCTAssertNil(policy.decide(.failed(summary: "连不上库"), userIsLookingAtThisPane: true, userIsIdle: false))
    }

    func testHelpRequestRendersThreeLines() {
        let help = AgentHelpRequest(kind: .grant, ask: "允许访问 ~/work 目录",
                                    why: "要读工作区里的 SQL 脚本才能继续",
                                    resumeFrom: "第 3 步：扫脚本")
        XCTAssertTrue(help.isActionable)
        let text = help.rendered
        XCTAssertTrue(text.contains("需要你授权"))
        XCTAssertTrue(text.contains("原因："))
        XCTAssertTrue(text.contains("从「第 3 步：扫脚本」接着跑"))
    }

    func testVagueHelpRequestIsNotActionable() {
        let help = AgentHelpRequest(kind: .information, ask: "  ", why: "")
        XCTAssertFalse(help.isActionable)
    }

    func testManualActionKindIsDistinguished() {
        XCTAssertEqual(AgentHelpRequest.Kind.manualAction.label, "需要你亲手做一步")
        XCTAssertEqual(AgentHelpRequest.Kind.grant.label, "需要你授权")
        XCTAssertEqual(AgentHelpRequest.Kind.information.label, "需要你给信息")
    }
}
